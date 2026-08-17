#!/usr/bin/env python3
"""
Boomi Process Log Space Analyzer

This script analyzes disk usage by Boomi parent processes (process components)
to help tune logging and process design.

Author: GitHub Copilot
Date: February 2026
"""

import os
import sys
import json
import csv
import xml.etree.ElementTree as ET
from pathlib import Path
from collections import defaultdict
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple
import re
from datetime import datetime

# Configuration - Modify these paths as needed
EXECUTION_DIR = "/opt/Boomi/atom/jmxDemo/execution"
PROCESSES_DIR = "/opt/Boomi/atom/jmxDemo/processes"  # Changed from COMPONENT_DIR
LOGS_DIR = "/opt/Boomi/atom/jmxDemo/logs"
TOP_N = 20  # Number of top processes to show
OUTPUT_CSV = "boomi_log_space_report.csv"

@dataclass
class ExecutionInfo:
    """Information about a single execution"""
    execution_id: str
    process_name: str
    process_id: str
    size_bytes: int
    timestamp: Optional[datetime] = None

@dataclass
class ProcessInfo:
    """Information about a Boomi process"""
    process_id: str
    process_name: str
    process_type: str
    folder_name: str = ""

@dataclass
class ExecutionStats:
    """Statistics for process executions"""
    process_info: ProcessInfo
    execution_count: int
    total_size_bytes: int
    max_size_bytes: int
    
    @property
    def total_size_mb(self) -> float:
        return self.total_size_bytes / (1024 * 1024)
    
    @property
    def avg_size_mb(self) -> float:
        if self.execution_count == 0:
            return 0.0
        return self.total_size_mb / self.execution_count
    
    @property
    def max_size_mb(self) -> float:
        return self.max_size_bytes / (1024 * 1024)

def get_file_size_recursive(path: Path) -> int:
    """
    Recursively calculate total size of files in a directory or single file.
    Returns size in bytes.
    """
    if not path.exists():
        return 0
    
    if path.is_file():
        return path.stat().st_size
    
    total_size = 0
    try:
        for item in path.rglob('*'):
            if item.is_file():
                total_size += item.stat().st_size
    except (OSError, PermissionError) as e:
        print(f"Warning: Could not access {path}: {e}")
    
    return total_size

def parse_process_xml(xml_path: Path) -> Optional[ProcessInfo]:
    """
    Parse a Boomi process XML file to extract process information.
    """
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        # Extract component information
        process_id = ""
        process_name = ""
        process_type = ""
        folder_name = ""
        
        # Find the ID element
        id_elem = root.find('.//Id')
        if id_elem is not None:
            process_id = id_elem.text or ""
        
        # Find the Name element  
        name_elem = root.find('.//Name')
        if name_elem is not None:
            process_name = name_elem.text or ""
        
        # Find the Type element
        type_elem = root.find('.//Type')
        if type_elem is not None:
            process_type = type_elem.text or ""
        
        # Find the FolderId element with name attribute
        folder_elem = root.find('.//FolderId[@name]')
        if folder_elem is not None:
            folder_name = folder_elem.get('name', '')
        
        return ProcessInfo(
            process_id=process_id,
            process_name=process_name,
            process_type=process_type,
            folder_name=folder_name
        )
    
    except (ET.ParseError, FileNotFoundError, PermissionError) as e:
        print(f"Warning: Could not parse process XML {xml_path}: {e}")
        return None

def load_process_mapping() -> Dict[str, ProcessInfo]:
    """
    Load all process directories and their main XML files to create a mapping from process ID to ProcessInfo.
    """
    processes = {}
    processes_path = Path(PROCESSES_DIR)
    
    if not processes_path.exists():
        print(f"Warning: Processes directory not found: {PROCESSES_DIR}")
        return processes
    
    # Find all process directories (those that are directories and have UUID-like names)
    process_dirs = [d for d in processes_path.iterdir() 
                   if d.is_dir() and len(d.name) == 36 and '-' in d.name]
    
    print(f"Loading {len(process_dirs)} process directories...")
    
    for process_dir in process_dirs:
        process_id = process_dir.name
        # Look for the main XML file (same name as directory)
        main_xml = process_dir / f"{process_id}.xml"
        
        if main_xml.exists():
            process_info = parse_process_xml(main_xml)
            if process_info and process_info.process_id:
                processes[process_info.process_id] = process_info
        else:
            print(f"Warning: Main XML file not found for process {process_id}")
    
    print(f"Loaded {len(processes)} process definitions")
    return processes

def parse_execution_log(execution_dir: Path) -> Optional[ExecutionInfo]:
    """
    Parse an execution directory to extract process information and size.
    """
    try:
        process_log_path = execution_dir / "process_log.xml"
        if not process_log_path.exists():
            return None
        
        # Parse the process log to get process name
        tree = ET.parse(process_log_path)
        root = tree.getroot()
        
        # Find the first log event with process name
        process_name = ""
        for log_event in root.findall('.//LogEvent'):
            message_elem = log_event.find('Message')
            if message_elem is not None and message_elem.text:
                message = message_elem.text
                if "Executing Process" in message:
                    # Extract process name from "Executing Process {name}"
                    process_name = message.replace("Executing Process ", "").strip()
                    break
        
        if not process_name:
            return None
        
        # Get execution size (entire directory)
        size_bytes = get_file_size_recursive(execution_dir)
        
        # Extract execution ID from directory name
        execution_id = execution_dir.name
        
        # Extract timestamp if available
        timestamp = None
        try:
            # Try to parse timestamp from directory name or log
            time_attr = None
            for log_event in root.findall('.//LogEvent'):
                time_attr = log_event.get('time')
                if time_attr:
                    break
            
            if time_attr:
                timestamp = datetime.fromisoformat(time_attr.replace('Z', '+00:00'))
        except:
            pass
        
        return ExecutionInfo(
            execution_id=execution_id,
            process_name=process_name,
            process_id="",  # Will be resolved later
            size_bytes=size_bytes,
            timestamp=timestamp
        )
    
    except (ET.ParseError, FileNotFoundError, PermissionError) as e:
        print(f"Warning: Could not parse execution log {execution_dir}: {e}")
        return None

def create_process_name_to_id_mapping(processes: Dict[str, ProcessInfo]) -> Dict[str, str]:
    """
    Create a mapping from process names to process IDs.
    """
    name_to_id = {}
    for process_id, process_info in processes.items():
        name_to_id[process_info.process_name] = process_id
    return name_to_id

def analyze_execution_history() -> List[ExecutionInfo]:
    """
    Analyze execution history directories to get actual execution logs.
    Returns list of ExecutionInfo objects.
    """
    executions = []
    execution_path = Path(EXECUTION_DIR)
    
    if not execution_path.exists():
        print(f"Warning: Execution directory not found: {EXECUTION_DIR}")
        return executions
    
    # Look for execution history directories
    history_path = execution_path / "history"
    if not history_path.exists():
        print(f"Warning: Execution history directory not found: {history_path}")
        return executions
    
    # Find all execution directories (recursively)
    execution_dirs = []
    for item in history_path.rglob("execution-*"):
        if item.is_dir():
            execution_dirs.append(item)
    
    print(f"Analyzing {len(execution_dirs)} execution history directories...")
    
    for execution_dir in execution_dirs:
        execution_info = parse_execution_log(execution_dir)
        if execution_info:
            executions.append(execution_info)
    
    return executions
    """
    Analyze process directories to get actual disk usage by process.
    Returns mapping of process_id -> total_size_bytes
    """
def analyze_process_directories() -> Dict[str, int]:
    """
    Analyze process directories to get process definition sizes.
    Returns mapping of process_id -> total_size_bytes
    """
    process_sizes = defaultdict(int)
    processes_path = Path(PROCESSES_DIR)
    
    if not processes_path.exists():
        print(f"Warning: Processes directory not found: {PROCESSES_DIR}")
        return dict(process_sizes)
    
    # Find all process directories (those that are directories and have UUID-like names)
    process_dirs = [d for d in processes_path.iterdir() 
                   if d.is_dir() and len(d.name) == 36 and '-' in d.name]
    
    print(f"Analyzing {len(process_dirs)} process directories...")
    
    for process_dir in process_dirs:
        process_id = process_dir.name
        
        # Get total size of entire process directory recursively
        dir_size = get_file_size_recursive(process_dir)
        process_sizes[process_id] = dir_size
    
    return dict(process_sizes)



def analyze_container_logs() -> Dict[str, int]:
    """
    Analyze container log files and attempt to correlate log entries with processes.
    This is a basic implementation that could be enhanced with process-specific parsing.
    """
    log_sizes = defaultdict(int)
    logs_path = Path(LOGS_DIR)
    
    if not logs_path.exists():
        print(f"Warning: Logs directory not found: {LOGS_DIR}")
        return dict(log_sizes)
    
    # Find all container log files
    log_files = list(logs_path.glob("*.container.log"))
    print(f"Analyzing {len(log_files)} container log files...")
    
    # For now, we'll just divide the total log size among all known processes
    # This could be enhanced to parse log entries and correlate with specific processes
    total_log_size = sum(get_file_size_recursive(log_file) for log_file in log_files)
    
    # Since we can't easily correlate container logs to specific processes without
    # parsing the log content (which would be memory intensive), we'll note this
    # limitation and focus on execution-specific data
    print(f"Total container log size: {total_log_size / (1024 * 1024):.1f} MB")
    print("Note: Container logs are not process-specific and not included in per-process analysis")
    
    return dict(log_sizes)

def generate_execution_stats(processes: Dict[str, ProcessInfo], 
                           process_sizes: Dict[str, int],
                           executions: List[ExecutionInfo]) -> List[ExecutionStats]:
    """
    Generate execution statistics by combining process info with execution history data.
    """
    stats_dict = defaultdict(lambda: {
        'process_info': None,
        'execution_count': 0,
        'total_execution_size': 0,
        'max_execution_size': 0,
        'process_definition_size': 0
    })
    
    # Create process name to ID mapping
    name_to_id = create_process_name_to_id_mapping(processes)
    
    # Track unknown processes
    unknown_processes = set()
    
    # Process execution history
    for execution in executions:
        # Try to resolve process ID from process name
        process_id = name_to_id.get(execution.process_name, "")
        
        if not process_id:
            # Create a fallback process ID if we can't resolve it
            process_id = f"unknown_process_{hash(execution.process_name) % 10000}"
            unknown_processes.add(execution.process_name)
        
        # Update execution stats
        stats = stats_dict[process_id]
        stats['execution_count'] += 1
        stats['total_execution_size'] += execution.size_bytes
        stats['max_execution_size'] = max(stats['max_execution_size'], execution.size_bytes)
        
        # Set process info if we have it
        if process_id in processes:
            stats['process_info'] = processes[process_id]
        elif not stats['process_info']:
            # Create placeholder for unknown process
            stats['process_info'] = ProcessInfo(
                process_id=process_id,
                process_name=execution.process_name,
                process_type="unknown"
            )
    
    # Add process definition sizes
    for process_id, definition_size in process_sizes.items():
        if process_id in stats_dict:
            stats_dict[process_id]['process_definition_size'] = definition_size
        else:
            # Process has definition but no executions
            if process_id in processes:
                process_info = processes[process_id]
            else:
                process_info = ProcessInfo(
                    process_id=process_id,
                    process_name="NO_EXECUTIONS_FOUND",
                    process_type="unknown"
                )
            
            stats_dict[process_id] = {
                'process_info': process_info,
                'execution_count': 0,
                'total_execution_size': 0,
                'max_execution_size': 0,
                'process_definition_size': definition_size
            }
    
    # Convert to ExecutionStats objects (exclude processes with 0 executions)
    stats_list = []
    for process_id, stats in stats_dict.items():
        # Skip processes with no executions
        if stats['execution_count'] == 0:
            continue
            
        # Total size = execution logs + process definition
        total_size = stats['total_execution_size'] + stats['process_definition_size']
        
        execution_stats = ExecutionStats(
            process_info=stats['process_info'],
            execution_count=stats['execution_count'],
            total_size_bytes=total_size,
            max_size_bytes=max(stats['max_execution_size'], stats['process_definition_size'])
        )
        stats_list.append(execution_stats)
    
    if unknown_processes:
        print(f"Warning: Found {len(unknown_processes)} processes with unknown IDs (could not map name to ID)")
        print(f"Unknown process names: {', '.join(list(unknown_processes)[:3])}{'...' if len(unknown_processes) > 3 else ''}")
    
    return stats_list

def print_summary_table(stats_list: List[ExecutionStats], title: str, top_n: int = TOP_N):
    """
    Print a formatted summary table to the terminal.
    """
    print(f"\n{title}")
    print("=" * 120)
    
    # Table header
    header = f"{'Process Name':<40} {'Process ID':<38} {'Count':<6} {'Total MB':<10} {'Avg MB':<8} {'Max MB':<8}"
    print(header)
    print("-" * 120)
    
    # Table rows
    for i, stats in enumerate(stats_list[:top_n]):
        process_name = stats.process_info.process_name[:39]  # Truncate long names
        process_id = stats.process_info.process_id[:37]  # Truncate long IDs
        
        row = f"{process_name:<40} {process_id:<38} {stats.execution_count:<6} " \
              f"{stats.total_size_mb:<10.2f} {stats.avg_size_mb:<8.2f} {stats.max_size_mb:<8.2f}"
        print(row)
    
    print("-" * 120)
    print(f"Showing top {min(top_n, len(stats_list))} of {len(stats_list)} processes")

def write_csv_report(stats_list: List[ExecutionStats], filename: str):
    """
    Write detailed CSV report with all processes.
    """
    csv_path = Path(filename)
    
    with open(csv_path, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        
        # CSV Header
        writer.writerow([
            'Process Name', 'Process ID', 'Process Type', 'Folder Path',
            'Execution Count', 'Total Size (Bytes)', 'Total Size (MB)', 
            'Average Size (MB)', 'Max Size (MB)', 'Process Definition Size (MB)',
            'Execution Logs Size (MB)'
        ])
        
        # CSV Data rows
        for stats in stats_list:
            definition_size_mb = 0
            execution_size_mb = stats.total_size_mb
            
            # Try to separate definition size from total if possible
            # This is approximate since we combined them in the stats
            if hasattr(stats, 'process_definition_size_mb'):
                definition_size_mb = stats.process_definition_size_mb
                execution_size_mb = stats.total_size_mb - definition_size_mb
            
            writer.writerow([
                stats.process_info.process_name,
                stats.process_info.process_id,
                stats.process_info.process_type,
                stats.process_info.folder_name,
                stats.execution_count,
                stats.total_size_bytes,
                stats.total_size_mb,
                stats.avg_size_mb,
                stats.max_size_mb,
                definition_size_mb,
                execution_size_mb
            ])
    
    print(f"\nDetailed CSV report written to: {csv_path.absolute()}")

def main():
    """
    Main execution function.
    """
    print("Boomi Process Log Space Analyzer")
    print("=" * 50)
    print(f"Execution Directory: {EXECUTION_DIR}")
    print(f"Processes Directory: {PROCESSES_DIR}")
    print(f"Logs Directory: {LOGS_DIR}")
    print()
    
    # Step 1: Load process definitions
    print("Step 1: Loading process definitions...")
    processes = load_process_mapping()
    
    # Step 2: Analyze process directory sizes (definitions)
    print("\nStep 2: Analyzing process directory sizes (definitions)...")
    process_sizes = analyze_process_directories()
    
    # Step 3: Analyze execution history (actual executions and logs)
    print("\nStep 3: Analyzing execution history...")
    executions = analyze_execution_history()
    
    # Step 4: Analyze container logs (informational only for now)
    print("\nStep 4: Analyzing container logs...")
    analyze_container_logs()
    
    # Step 5: Generate statistics
    print("\nStep 5: Generating execution statistics...")
    stats_list = generate_execution_stats(processes, process_sizes, executions)
    
    if not stats_list:
        print("No execution data found. Please check the directory paths.")
        return
    
    # Step 5: Sort and display results
    
    # Sort by total size (descending)
    stats_by_total = sorted(stats_list, key=lambda x: x.total_size_bytes, reverse=True)
    print_summary_table(stats_by_total, "TOP PROCESSES BY TOTAL EXECUTION SIZE", TOP_N)
    
    # Sort by average size (descending)  
    stats_by_avg = sorted(stats_list, key=lambda x: x.avg_size_mb, reverse=True)
    print_summary_table(stats_by_avg, "TOP PROCESSES BY AVERAGE EXECUTION SIZE", TOP_N)
    
    # Step 6: Write CSV report
    print(f"\nStep 6: Writing CSV report...")
    write_csv_report(stats_by_total, OUTPUT_CSV)
    
    # Summary
    total_process_size = sum(stats.total_size_bytes for stats in stats_list)
    total_executions = sum(stats.execution_count for stats in stats_list)
    execution_history_size = sum(execution.size_bytes for execution in executions)
    
    print(f"\nSUMMARY")
    print(f"Total processes analyzed: {len(stats_list)}")
    print(f"Total executions found: {total_executions}")
    print(f"Total combined size: {total_process_size / (1024 * 1024):.2f} MB")
    print(f"Execution history size: {execution_history_size / (1024 * 1024):.2f} MB")
    
    print(f"\nNote: This analysis covers both process definitions and execution history.")
    print(f"Process definitions: XML configurations and process-specific data")
    print(f"Execution history: Individual execution logs with process flow data")
    print(f"Container logs ({LOGS_DIR}) are shared across all processes.")

if __name__ == "__main__":
    main()