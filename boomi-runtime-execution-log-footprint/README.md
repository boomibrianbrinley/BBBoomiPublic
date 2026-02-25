# Boomi Runtime Execution Log Footprint

`boomi-runtime-log-footprint.sh` is a lightweight Bash utility that analyzes a Boomi Atom runtime’s filesystem and ranks processes by **execution-history log footprint** (plus **process definition size**).

It’s designed for **local Atom runtime analysis** — no APIs required.

---

## What it does

For the given Atom runtime directories, the script:

1. Loads process definitions from the `processes/` directory
2. Analyzes execution history under `execution/history/`
3. Correlates executions to process names via `process_log.xml`
4. Aggregates per process:
   - Execution count
   - Total execution footprint
   - Average and max execution footprint
   - Process definition size
   - Combined total footprint
5. Ranks processes by:
   - **Total footprint**
   - **Average footprint**
6. Reports container log size (`*.container.log`) as **informational only** (not included in per-process totals)

---

## Expected directory structure

The script expects the typical Boomi Atom layout:

```
<atom_root>/
├── execution/
│   └── history/
│       └── **/execution-*/process_log.xml
├── processes/
│   └── <uuid>/<uuid>.xml
└── logs/
    └── *.container.log
```

Notes:

- The script scans for directories named `execution-*` under `<exec>/history`.
- Process definitions are expected as UUID directories with a matching XML file: `<uuid>/<uuid>.xml`.

---

## Requirements

- Bash (macOS or Linux)
- Standard Unix tools: `find`, `grep`, `sed`, `awk`, `du`, `sort`, `head`, `wc`

No Python, no external dependencies.

---

## Install

1. Copy the script into your repo
2. Make it executable:

```bash
chmod +x boomi-runtime-log-footprint.sh
```

---

## Usage

```bash
./boomi-runtime-log-footprint.sh   --exec <execution_dir>   --proc <processes_dir>   --logs <logs_dir>   [--top N]   [--out output.csv]   [--debug]   [--keep-temp]
```

### Required parameters

| Parameter | Description |
|---|---|
| `--exec` | Path to Boomi execution directory (expects `<exec>/history`) |
| `--proc` | Path to Boomi processes directory (`<uuid>/<uuid>.xml`) |
| `--logs` | Path to Boomi logs directory (used for `*.container.log` informational total) |

### Optional parameters

| Parameter | Description |
|---|---|
| `--top N` | Number of top processes to display (default: `5`) |
| `--out file.csv` | Write a CSV report. If omitted, **no CSV is written** |
| `--debug` | Enable debug output (helpful for mapping issues) |
| `--keep-temp` | Keep intermediate temp files (prints paths at end) |

---

## Examples

### macOS / Linux example (your paths)

```bash
./boomi-runtime-log-footprint.sh   --exec '/opt/Boomi/atom/jmxDemo/execution'   --proc '/opt/Boomi/atom/jmxDemo/processes'   --logs '/opt/Boomi/atom/jmxDemo/logs'   --top 10
```

### Write CSV output

```bash
./boomi-runtime-log-footprint.sh   --exec '/opt/Boomi/atom/jmxDemo/execution'   --proc '/opt/Boomi/atom/jmxDemo/processes'   --logs '/opt/Boomi/atom/jmxDemo/logs'   --out boomi-log-footprint.csv
```

### Debug + keep temp files

```bash
./boomi-runtime-log-footprint.sh   --exec '/opt/Boomi/atom/jmxDemo/execution'   --proc '/opt/Boomi/atom/jmxDemo/processes'   --logs '/opt/Boomi/atom/jmxDemo/logs'   --debug --keep-temp
```

---

## How execution count is calculated

- Each `execution-*` directory under `<exec>/history` is treated as a single execution **if** it contains a `process_log.xml`.
- The script extracts the process name from the first `<Message>` containing:

```
Executing Process <Process Name>
```

- To avoid accidental double counting, the script **de-dupes** by `(process_id, execution_id)`.

---

## How size is calculated

Per process:

- **Execution footprint**: sum of `du -sk` sizes for counted `execution-*` directories
- **Process definition size**: recursive `du -sk` size of the `<uuid>/` process directory
- **Total footprint**: `execution_sum + process_definition_size`

Container logs (`*.container.log`) are reported as a single total only and are **not** included in per-process totals.

---

## Output

The script prints two ranked tables:

1. Top processes by **total footprint**
2. Top processes by **average footprint**

If `--out` is provided, it also writes a CSV sorted by **total footprint**.

---

## Troubleshooting

### “Unknown process names (not mapped to IDs)”
This usually means the process name extracted from `process_log.xml` did not match any `<Name>` in the process definition XMLs.

Try running with:

```bash
--debug --keep-temp
```

Then inspect:
- `proc_map` (process definitions loaded)
- `exec_events` (executions parsed + process names)
- `stats` (final aggregation)

### No executions found
Ensure:
- `<exec>/history` exists
- `execution-*` directories contain `process_log.xml`

---

## Safety

- Read-only analysis (no file modifications)
- Works on local runtime directories

---



