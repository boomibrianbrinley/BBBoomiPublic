# Boomi Runtime Log Footprint (Bash)

A **Bash** script to analyze disk usage by Boomi parent processes (process components) so you can tune logging and optimize process design in Boomi AtomSphere local runtime environments.

## Overview

This tool scans your Boomi local Atom runtime directories to identify which processes are consuming the most disk space through execution logs, helping you make informed decisions about logging levels and process optimization.

## Features

- **Accurate Execution Counting**: Parses actual execution history directories to count real process executions
- **Process Correlation**: Maps execution logs to parent processes using XML component definitions
- **Disk Usage Analysis**: Measures both process definitions and execution log sizes
- **Dual Rankings**: Shows top processes by total size and average execution size
- **CSV Export**: Generates detailed reports for further analysis
- **Active Process Focus**: Filters out processes with zero executions for cleaner results
- **Safe & Read-Only**: Non-destructive analysis using only filesystem metadata

## Requirements

- Bash 3.2+ (macOS default is fine)
- Read access to Boomi Atom runtime directories
- Standard Unix tools: awk, sed, find, du, sort, head, tr, grep

## Installation

1. Clone or download the script to your Boomi Atom directory
2. Make it executable:
   ```bash
   chmod +x boomi-runtime-log-footprint.sh
   ```

## Configuration

Configure by passing paths and options as command-line flags:

```bash
# Example paths
EXECUTION_DIR="/opt/Boomi/atom/jmxDemo/execution"
PROCESSES_DIR="/opt/Boomi/atom/jmxDemo/processes"
LOGS_DIR="/opt/Boomi/atom/jmxDemo/logs"
TOP_N=5
OUTPUT_CSV="boomi_log_space_report.csv"
```

## Usage

Run from your Boomi Atom directory:

```bash
cd /path/to/your/boomi/atom
./boomi-runtime-log-footprint.sh \
  --exec  "/opt/Boomi/atom/jmxDemo/execution" \
  --proc  "/opt/Boomi/atom/jmxDemo/processes" \
  --logs  "/opt/Boomi/atom/jmxDemo/logs" \
  --top   5 \
  --out   "boomi_log_space_report.csv"
```

Tip: add --debug to print mapping previews and troubleshooting details.

## Output

The script provides:

### Terminal Output
- **Process definitions loaded**: Count of XML component files processed
- **Execution analysis**: Number of execution history directories found
- **Two ranking tables**: 
  - Top processes by total execution size
  - Top processes by average execution size
- **Summary statistics**: Total processes, executions, and disk usage

### CSV Report
Detailed report (`boomi_log_space_report.csv`) with columns:
- Process Name
- Process ID  
- Process Type
- Folder Path
- Execution Count
- Total Size (Bytes/MB)
- Average Size (MB)
- Max Size (MB)
- Process Definition Size (MB)
- Execution Logs Size (MB)

## Example Output

```
Boomi Process Log Space Analyzer
==================================================
Execution Directory: /opt/Boomi/atom/jmxDemo/execution
Processes Directory: /opt/Boomi/atom/jmxDemo/processes
Logs Directory: /opt/Boomi/atom/jmxDemo/logs

Step 1: Loading process definitions...
Loading 17 process directories...
Loaded 17 process definitions

Step 2: Analyzing process directory sizes (definitions)...
Analyzing 17 process directories...

Step 3: Analyzing execution history...
Analyzing 8 execution history directories...

TOP PROCESSES BY TOTAL EXECUTION SIZE
================================================================================
Process Name                             Process ID                             Count  Total MB   Avg MB   Max MB  
--------------------------------------------------------------------------------
Generate List of Processes that have ex  6b721029-248d-4ddf-92aa-a323cffc3a8d   1      0.14       0.14     0.12   
[Util] Get Enterprise Component          b4a05576-94a3-4be2-9dc3-51ae1734a43b   1      0.09       0.09     0.07   
Test grep shape                          8953cead-f065-4cf0-8551-fa5e620bd2cc   6      0.03       0.01     0.01   

SUMMARY
Total processes analyzed: 3
Total executions found: 8
Total combined size: 0.26 MB
Execution history size: 0.06 MB
```

## How It Works

1. **Process Definition Analysis**: Scans the `/processes` directory for process XML files to build a mapping of process IDs to readable names and metadata

2. **Execution History Parsing**: Analyzes `/execution/history` directories containing actual execution logs, parsing `process_log.xml` files to extract:
   - Process names from execution messages
   - Execution timestamps
   - File sizes for each execution

3. **Correlation & Aggregation**: Maps execution data back to process definitions and aggregates statistics by parent process

4. **Filtering & Ranking**: Excludes processes with zero executions and ranks by total disk usage and average execution size

## Directory Structure Expected

```
/path/to/boomi/atom/
├── execution/
│   ├── history/
│   │   └── YYYY.MM.DD/
│   │       └── execution-{uuid}-YYYY.MM.DD/
│   │           ├── process_log.xml
│   │           ├── data0_log.xml
│   │           └── metrics.xml
│   └── *.properties
├── processes/
│   └── {process-uuid}/
│       └── {process-uuid}.xml
└── logs/
    └── *.container.log
```

## Troubleshooting

### Common Issues

**"No execution data found"**
- Check that `EXECUTION_DIR` points to the correct execution directory
- Ensure execution history exists in `{EXECUTION_DIR}/history/`

**"Unknown processes found"**
- Some executions may not map to process definitions if XML files are missing
- Check that `PROCESSES_DIR` contains the correct process XML files

**Permission errors**
- Ensure read access to all Boomi directories
- Run with appropriate user permissions

### Extending the Script

The script is designed to be extensible:

- Add new metrics: extend the awk aggregation and CSV output
- Custom filtering: add include/exclude rules on process name or folder
- Enhanced parsing: expand process_log.xml parsing patterns
- Integration: feed the CSV into your monitoring/BI tooling

## Limitations

- **Container logs**: Shared container logs are noted but not allocated to specific processes (would require log content parsing)
- **Process correlation**: Relies on process name matching between executions and definitions
- **Historical data**: Only analyzes execution history that exists on disk

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve the analyzer.

## License

This script is provided as-is for Boomi environment analysis and optimization purposes.

---

**Author**: Community contributed  
**Date**: February 2026  
**Version**: 1.0 (Bash)
