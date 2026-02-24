#!/usr/bin/env bash
set -euo pipefail

########################################
# Usage
#./BoomiLocalExecutionAnalysis.sh \
#  --exec /opt/Boomi/atom/jmxDemo/execution \
#  --comp /opt/Boomi/atom/jmxDemo/component \
#  --top 25 \
#  --out boomi_report.csv
########################################
usage() {
  cat <<EOF
Usage:
  $0 --exec <execution_dir> --comp <component_dir> [--top N] [--out output.csv]

Required:
  --exec    Path to Boomi execution directory
  --comp    Path to Boomi component directory

Optional:
  --top     Number of top processes to display (default: 20)
  --out     Output CSV file (default: ./boomi_log_space_report.csv)

Example:
  $0 --exec /opt/Boomi/atom/jmxDemo/execution \
     --comp /opt/Boomi/atom/jmxDemo/component \
     --top 25 \
     --out report.csv
EOF
  exit 1
}

########################################
# Parse Arguments
########################################
EXEC_DIR=""
COMP_DIR=""
TOPN=20
OUT_CSV="./boomi_log_space_report.csv"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exec)
      EXEC_DIR="$2"
      shift 2
      ;;
    --comp)
      COMP_DIR="$2"
      shift 2
      ;;
    --top)
      TOPN="$2"
      shift 2
      ;;
    --out)
      OUT_CSV="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      ;;
  esac
done

########################################
# Validate Inputs
########################################
[[ -z "$EXEC_DIR" || -z "$COMP_DIR" ]] && usage

if [[ ! -d "$EXEC_DIR" ]]; then
  echo "ERROR: Execution directory not found: $EXEC_DIR" >&2
  exit 1
fi

if [[ ! -d "$COMP_DIR" ]]; then
  echo "WARNING: Component directory not found: $COMP_DIR"
  echo "Correlation may be limited."
fi

########################################
# Helpers
########################################
kib_to_mib() {
  awk -v kib="$1" 'BEGIN { printf "%.2f", kib/1024.0 }'
}

extract_meta_value() {
  local exec_path="$1"
  local regex="$2"

  find "$exec_path" -maxdepth 3 -type f \( \
      -iname "*.properties" -o -iname "*.xml" -o -iname "*.json" -o -iname "*.txt" -o -iname "*.cfg" \
    \) -size -512k 2>/dev/null \
    | while IFS= read -r f; do
        local m
        m="$(grep -E -m 1 "$regex" "$f" 2>/dev/null || true)"
        if [[ -n "$m" ]]; then
          echo "$m" | sed -E 's/^[^=:"]*[=:"][[:space:]]*//; s/[",[:space:]]*$//'
          return 0
        fi
      done
  return 1
}

resolve_component_name_by_id() {
  local comp_id="$1"
  [[ -z "$comp_id" ]] && return 1

  local hit
  hit="$(grep -R --include='*.xml' -n -m 1 "$comp_id" "$COMP_DIR" 2>/dev/null || true)"
  [[ -z "$hit" ]] && return 1

  local file="${hit%%:*}"
  local name

  name="$(grep -E -m 1 'name="[^"]+"' "$file" 2>/dev/null | sed -E 's/.*name="([^"]+)".*/\1/' || true)"
  [[ -z "$name" ]] && \
    name="$(grep -E -m 1 '<name>[^<]+' "$file" 2>/dev/null | sed -E 's/.*<name>([^<]+).*/\1/' || true)"

  [[ -n "$name" ]] && echo "$name" && return 0
  return 1
}

print_row() {
  printf "%-40s  %-24s  %8s  %14s  %14s  %14s\n" "$1" "$2" "$3" "$4" "$5" "$6"
}

########################################
# Processing
########################################
tmp_exec="$(mktemp)"
tmp_agg="$(mktemp)"
tmp_sorted="$(mktemp)"
trap 'rm -f "$tmp_exec" "$tmp_agg" "$tmp_sorted"' EXIT

while IFS= read -r -d '' exec_folder; do
  size_kib="$(du -sk "$exec_folder" 2>/dev/null | awk '{print $1}')"

  proc_id="$(extract_meta_value "$exec_folder" '(process(Id|ID)|component(Id|ID)|process_id|component_id)[[:space:]]*[:=][[:space:]]*["]?[A-Za-z0-9._:-]+' || true)"
  proc_name="$(extract_meta_value "$exec_folder" '(process(Name|NAME)|process_name|component(Name|NAME)|component_name)[[:space:]]*[:=][[:space:]]*["][^"]+["]' || true)"

  if [[ -z "$proc_name" && -n "$proc_id" ]]; then
    proc_name="$(resolve_component_name_by_id "$proc_id" || true)"
  fi

  if [[ -n "$proc_name" && -n "$proc_id" ]]; then
    key="$proc_name|$proc_id"
  elif [[ -n "$proc_name" ]]; then
    key="$proc_name|"
  elif [[ -n "$proc_id" ]]; then
    key="UNKNOWN_PROCESS|$proc_id"
  else
    key="UNKNOWN_PROCESS|"
  fi

  echo "$key|$size_kib" >> "$tmp_exec"
done < <(find "$EXEC_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

awk -F'|' '
  {
    k=$1 "|" $2
    cnt[k] += 1
    sum[k] += $3
    if ($3 > mx[k]) mx[k] = $3
  }
  END {
    for (k in cnt) {
      split(k,a,"|")
      printf "%s|%s|%d|%d|%d\n", a[1], a[2], cnt[k], sum[k], mx[k]
    }
  }
' "$tmp_exec" > "$tmp_agg"

sort -t'|' -k4,4nr "$tmp_agg" | head -n "$TOPN" > "$tmp_sorted"

########################################
# Output
########################################
echo
print_row "Parent Process" "Process ID" "Exec Cnt" "Total (MB)" "Avg (MB)" "Max (MB)"
print_row "----------------------------------------" "------------------------" "--------" "--------------" "--------------" "--------------"

while IFS='|' read -r proc_name proc_id cnt total_kib max_kib; do
  avg_kib=$(( total_kib / cnt ))
  total_mb="$(kib_to_mib "$total_kib")"
  avg_mb="$(kib_to_mib "$avg_kib")"
  max_mb="$(kib_to_mib "$max_kib")"

  print_row "$proc_name" "${proc_id:-}" "$cnt" "$total_mb" "$avg_mb" "$max_mb"
done < "$tmp_sorted"

{
  echo "ParentProcess,ProcessId,ExecutionCount,TotalMB,AverageMB,MaxMB"
  while IFS='|' read -r proc_name proc_id cnt total_kib max_kib; do
    avg_kib=$(( total_kib / cnt ))
    echo "\"$proc_name\",\"$proc_id\",$cnt,$(kib_to_mib "$total_kib"),$(kib_to_mib "$avg_kib"),$(kib_to_mib "$max_kib")"
  done < "$tmp_sorted"
} > "$OUT_CSV"

echo
echo "CSV written to: $OUT_CSV"
