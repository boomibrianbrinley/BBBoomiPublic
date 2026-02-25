#!/usr/bin/env bash
# Recommended filename: boomi-runtime-log-footprint.sh
# Purpose: Rank Boomi processes by execution-history log footprint (plus process definition size).

set -euo pipefail

usage() {
  cat <<EOF
Usage:
  # Recommended filename: boomi-runtime-log-footprint.sh
  $0 --exec <execution_dir> --proc <processes_dir> --logs <logs_dir> [--top N] [--out output.csv] [--debug]

Required:
  --exec    Path to Boomi execution directory (expects: <exec>/history)
  --proc    Path to Boomi processes directory (UUID dirs with <uuid>/<uuid>.xml)
  --logs    Path to Boomi logs directory (for *.container.log informational size)

Optional:
  --top     Number of top processes to display (default: 5)
  --out     Output CSV file (if omitted, no CSV is written)
  --debug   Enable debug output
  --keep-temp  Keep intermediate TSV files (for debugging)
EOF
  exit 1
}

EXEC_DIR=""
PROC_DIR=""
LOGS_DIR=""
TOPN=5
OUT_CSV=""
DEBUG=0
KEEP_TEMP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --exec) EXEC_DIR="$2"; shift 2 ;;
    --proc) PROC_DIR="$2"; shift 2 ;;
    --logs) LOGS_DIR="$2"; shift 2 ;;
    --top)  TOPN="$2"; shift 2 ;;
    --out)  OUT_CSV="$2"; shift 2 ;;
    --debug) DEBUG=1; shift ;;
    --keep-temp) KEEP_TEMP=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$EXEC_DIR" || -z "$PROC_DIR" || -z "$LOGS_DIR" ]] && usage
[[ -d "$EXEC_DIR" ]] || { echo "ERROR: Execution dir not found: $EXEC_DIR" >&2; exit 1; }
[[ -d "$PROC_DIR" ]] || { echo "ERROR: Processes dir not found: $PROC_DIR" >&2; exit 1; }
[[ -d "$LOGS_DIR" ]] || { echo "ERROR: Logs dir not found: $LOGS_DIR" >&2; exit 1; }

kib_to_mb() { awk -v kib="$1" 'BEGIN { printf "%.2f", kib/1024.0 }'; }

normalize_name() {
  # Collapse all whitespace (tabs/newlines/multiple spaces) to a single space and trim.
  echo "$1" \
    | tr -d '\r' \
    | tr '\t' ' ' \
    | tr '\n' ' ' \
    | sed -E 's/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//' \
    || true
}

xml_tag_value() {
  local file="$1"
  local tag="$2"

  # Portable extraction of the first <tag>...</tag> value, even if it spans multiple lines.
  # Uses awk (BSD/GNU compatible) instead of GNU-sed-only address ranges.
  local block
  block="$(awk -v T="$tag" '
    BEGIN { inblock=0; buf="" }
    {
      if (!inblock) {
        if (index($0, "<" T ">") > 0) { inblock=1 }
      }
      if (inblock) {
        buf = buf $0 "\n"
        if (index($0, "</" T ">") > 0) { print buf; exit }
      }
    }
  ' "$file" 2>/dev/null \
    | tr -d '\r' \
    | tr -d '\t' \
    | tr '\n' ' ' \
    | head -c 200000 || true)"

  if [[ -z "${block:-}" ]]; then
    echo ""
    return 0
  fi

  echo "$block" \
    | sed -E "s/.*<${tag}>([^<]*)<\/${tag}>.*/\1/" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    || true
}


# Extract value of a tag within the first <Component>...</Component> block.
xml_component_tag_value() {
  local file="$1"
  local tag="$2"

  # Extract the first <Component>...</Component> block, then extract <tag>...</tag> from within it.
  local block
  block="$(awk '
    BEGIN { inblock=0; buf="" }
    {
      if (!inblock) {
        if ($0 ~ /<Component[ >]/) { inblock=1 }
      }
      if (inblock) {
        buf = buf $0 "\n"
        if ($0 ~ /<\/Component>/) { print buf; exit }
      }
    }
  ' "$file" 2>/dev/null \
    | tr -d '\r' \
    | tr -d '\t' \
    | tr '\n' ' ' \
    | head -c 500000 || true)"

  if [[ -z "${block:-}" ]]; then
    echo ""
    return 0
  fi

  echo "$block" \
    | sed -E "s/.*<${tag}>([^<]*)<\/${tag}>.*/\1/" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    || true
}
# Extract the <Id> and the first <Name> that appears AFTER that </Id> within the first <Component>...</Component> block.
# Outputs: "<id>\t<name>" (either may be blank).
xml_component_id_and_name() {
  local file="$1"

  local block
  block="$(awk '
    BEGIN { inblock=0; buf="" }
    {
      if (!inblock) {
        if ($0 ~ /<Component[ >]/) { inblock=1 }
      }
      if (inblock) {
        buf = buf $0 "\n"
        if ($0 ~ /<\/Component>/) { print buf; exit }
      }
    }
  ' "$file" 2>/dev/null \
    | tr -d '\r' \
    | tr -d '\t' \
    | tr '\n' ' ' \
    | head -c 800000 || true)"

  if [[ -z "${block:-}" ]]; then
    printf "\t\n"
    return 0
  fi

  # First <Id>...</Id>
  local pid
  pid="$(echo "$block" | awk '
    {
      s=$0
      if (match(s, /<Id>[^<]*<\/Id>/)) {
        seg=substr(s, RSTART, RLENGTH)
        gsub(/.*<Id>/, "", seg)
        gsub(/<\/Id>.*/, "", seg)
        print seg
      }
    }
  ' | head -n 1 | sed -E "s/^[[:space:]]+//; s/[[:space:]]+$//" || true)"

  # First <Name>...</Name> AFTER first </Id>
  local pname
  pname="$(echo "$block" | awk '
    {
      s=$0
      id_end = index(s, "</Id>")
      if (id_end > 0) {
        rest = substr(s, id_end + 5)
        if (match(rest, /<Name>[^<]*<\/Name>/)) {
          seg=substr(rest, RSTART, RLENGTH)
          gsub(/.*<Name>/, "", seg)
          gsub(/<\/Name>.*/, "", seg)
          print seg
        }
      }
    }
  ' | head -n 1 | sed -E "s/^[[:space:]]+//; s/[[:space:]]+$//" || true)"

  printf "%s\t%s\n" "$pid" "$pname"
}

# Extract FolderId name attribute: <FolderId name="Something">...</FolderId>
xml_folder_name_attr() {
  local file="$1"
  grep -m 1 -E '<FolderId[^>]*name="[^"]+"' "$file" 2>/dev/null \
    | sed -E 's/.*name="([^"]+)".*/\1/' \
    | tr -d '\r' | tr -d '\t' || true
}

# Extract a process name from a Boomi process definition XML (best-effort).
# Different runtimes/exports may store the display name differently.
extract_process_name_from_definition_xml() {
  local file="$1"
  local v=""

  # Prefer the Name inside the <Component> element (this is typically the process display name)
  v="$(xml_component_id_and_name "$file" | awk -F'\t' '{print $2}')"
  v="$(normalize_name "$v")"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  # Try common tag variants
  v="$(xml_tag_value "$file" "Name")"; v="$(normalize_name "$v")"; [[ -n "${v:-}" ]] && { echo "$v"; return 0; }
  v="$(xml_tag_value "$file" "name")"; v="$(normalize_name "$v")"; [[ -n "${v:-}" ]] && { echo "$v"; return 0; }
  v="$(xml_tag_value "$file" "DisplayName")"; v="$(normalize_name "$v")"; [[ -n "${v:-}" ]] && { echo "$v"; return 0; }
  v="$(xml_tag_value "$file" "ProcessName")"; v="$(normalize_name "$v")"; [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  # Try common attribute patterns (e.g., name="...") near a process/component element
  v="$(grep -E -m 1 '<(Process|process|Component|component)[^>]*[[:space:]]name="[^"]+"' "$file" 2>/dev/null \
      | sed -E 's/.*[[:space:]]name="([^"]+)".*/\1/' \
      | tr -d '\r' | tr -d '\t' \
      || true)"
  v="$(normalize_name "$v")"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  # Try property-style name keys
  v="$(grep -E -m 1 '(processName|ProcessName|displayName|DisplayName)[[:space:]]*[:=]' "$file" 2>/dev/null \
      | sed -E 's/.*(processName|ProcessName|displayName|DisplayName)[[:space:]]*[:=][[:space:]]*"?([^"<]+)"?.*/\2/' \
      | tr -d '\r' | tr -d '\t' \
      || true)"
  v="$(normalize_name "$v")"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  # Last resort: some Boomi files include a FolderId name attribute that is often human-readable
  v="$(xml_folder_name_attr "$file")"
  v="$(normalize_name "$v")"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  echo ""
  return 0
}

# Extract process name from process_log.xml:
# Find first <Message>Executing Process X</Message>
extract_process_name_from_process_log() {
  local file="$1"
  # Remove tags and the prefix
  local line
  line="$(grep -m 1 -E '<Message>.*Executing Process ' "$file" 2>/dev/null || true)"
  [[ -z "${line:-}" ]] && return 1
  echo "$line" \
    | sed -E 's/.*<Message>//; s/<\/Message>.*//; s/Executing Process[[:space:]]+//;' \
    | tr -d '\r' \
    | tr -d '\t' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    || true
}

# Extract process id from process_log.xml (best-effort).
# Tries common tag/attribute/key patterns.
extract_process_id_from_process_log() {
  local file="$1"
  local v

  # XML tag forms
  v="$(grep -E -m 1 '<(ProcessId|processId|processID|process_id)>' "$file" 2>/dev/null \
      | sed -E 's/.*<(ProcessId|processId|processID|process_id)>([^<]+)<\/(ProcessId|processId|processID|process_id)>.*/\2/' \
      | tr -d '\r' | tr -d '\t' \
      || true)"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  # Attribute forms: processId="..." or componentId="..."
  v="$(grep -E -m 1 '(processId|processID|componentId|componentID)="[^"]+"' "$file" 2>/dev/null \
      | sed -E 's/.*(processId|processID|componentId|componentID)="([^"]+)".*/\2/' \
      | tr -d '\r' | tr -d '\t' \
      || true)"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  # Key/value forms in messages
  v="$(grep -E -m 1 '(processId|processID|componentId|componentID)[[:space:]]*[:=][[:space:]]*' "$file" 2>/dev/null \
      | sed -E 's/.*(processId|processID|componentId|componentID)[[:space:]]*[:=][[:space:]]*"?([^"[:space:]>]+)"?.*/\2/' \
      | tr -d '\r' | tr -d '\t' \
      || true)"
  [[ -n "${v:-}" ]] && { echo "$v"; return 0; }

  echo ""
  return 0
}

# Stable-ish unknown id like python: unknown_process_<hash%10000>
unknown_id_for_name() {
  local name="$1"
  local n
  n="$(printf "%s" "$name" | cksum | awk '{print $1}')"
  echo "unknown_process_$(( n % 10000 ))"
}

tmp_proc_map="$(mktemp)"
tmp_exec_events="$(mktemp)"
tmp_stats="$(mktemp)"
tmp_sorted_total="$(mktemp)"
tmp_sorted_avg="$(mktemp)"
if [[ "$KEEP_TEMP" -eq 1 ]]; then
  trap ':' EXIT
else
  trap 'rm -f "$tmp_proc_map" "$tmp_exec_events" "$tmp_stats" "$tmp_sorted_total" "$tmp_sorted_avg"' EXIT
fi

if [[ "$DEBUG" -eq 1 ]]; then
  echo "DEBUG enabled"
  echo "EXEC_DIR=$EXEC_DIR"
  echo "PROC_DIR=$PROC_DIR"
  echo "LOGS_DIR=$LOGS_DIR"
fi

########################################
# Step 1+2: Load process definitions + definition sizes
# Output TSV: process_id \t process_name \t process_type \t folder_name \t def_kib
########################################
# Python: process dirs are UUID-like (len 36 and contains '-')
proc_dirs_count="$(find "$PROC_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
[[ "$DEBUG" -eq 1 ]] && echo "DEBUG: process dirs (top-level): $proc_dirs_count" >&2

while IFS= read -r -d '' d; do
  base="$(basename "$d")"
  # UUID-ish filter
  if [[ ${#base} -eq 36 && "$base" == *-* ]]; then
    main_xml="$d/$base.xml"
    if [[ ! -f "$main_xml" ]]; then
      [[ "$DEBUG" -eq 1 ]] && echo "DEBUG: Missing main xml: $main_xml" >&2
      continue
    fi

    comp_pair="$(xml_component_id_and_name "$main_xml")"
    pid="$(echo "$comp_pair" | awk -F'\t' '{print $1}')"
    pname_from_comp="$(echo "$comp_pair" | awk -F'\t' '{print $2}')"

    [[ -z "${pid:-}" ]] && pid="$(xml_tag_value "$main_xml" "Id")"

    pname="$(normalize_name "$pname_from_comp")"
    if [[ -z "${pname:-}" ]]; then
      pname="$(extract_process_name_from_definition_xml "$main_xml")"
    fi


    ptype="$(xml_tag_value "$main_xml" "Type")"
    folder="$(xml_folder_name_attr "$main_xml")"

    # Fallbacks similar to python behavior
    [[ -z "${pid:-}" ]] && pid="$base"
    [[ -z "${pname:-}" ]] && pname="UNKNOWN_NAME"
    [[ -z "${ptype:-}" ]] && ptype="unknown"

    def_kib="$(du -sk "$d" 2>/dev/null | awk '{print $1}' || echo 0)"

    printf "%s\t%s\t%s\t%s\t%s\n" "$pid" "$pname" "$ptype" "$folder" "$def_kib" >> "$tmp_proc_map"
  fi
done < <(find "$PROC_DIR" -mindepth 1 -maxdepth 1 -type d -print0)

proc_loaded="$(wc -l < "$tmp_proc_map" | tr -d ' ')"
echo "Loaded $proc_loaded process definitions"

if [[ "$DEBUG" -eq 1 ]]; then
  echo "DEBUG: First 20 lines of process map TSV (pid, name, type, folder, kib; tabs as [TAB]):" >&2
  head -n 20 "$tmp_proc_map" | sed -E $'s/\t/[TAB]/g' >&2
fi

########################################
# Step 3: Analyze execution history
# Python: EXEC_DIR/history/**/execution-* dirs, parse process_log.xml
# Output TSV: exec_id \t process_id \t process_name \t exec_kib
########################################
history_path="$EXEC_DIR/history"
if [[ ! -d "$history_path" ]]; then
  echo "Warning: Execution history directory not found: $history_path" >&2
else
  exec_dirs_count="$(find "$history_path" -type d -name "execution-*" 2>/dev/null | wc -l | tr -d ' ')"
  echo "Analyzing $exec_dirs_count execution history directories..."

  while IFS= read -r -d '' exec_dir; do
    plog="$exec_dir/process_log.xml"
    [[ -f "$plog" ]] || { [[ "$DEBUG" -eq 1 ]] && echo "DEBUG: Missing $plog" >&2; continue; }

    pname="$(extract_process_name_from_process_log "$plog" || true)"
    pname="$(normalize_name "$pname")"

    pid_from_log="$(extract_process_id_from_process_log "$plog")"
    pid_from_log="$(normalize_name "$pid_from_log")"

    [[ -n "${pname:-}" ]] || { [[ "$DEBUG" -eq 1 ]] && echo "DEBUG: Could not extract process name from $plog" >&2; continue; }

    exec_id="$(basename "$exec_dir")"   # e.g., execution-123456...
    exec_kib="$(du -sk "$exec_dir" 2>/dev/null | awk '{print $1}' || echo 0)"
    printf "%s\t%s\t%s\t%s\n" "$exec_id" "$pid_from_log" "$pname" "$exec_kib" >> "$tmp_exec_events"
  done < <(find "$history_path" -type d -name "execution-*" -print0)
fi

exec_found="$(wc -l < "$tmp_exec_events" | tr -d ' ')"
echo "Executions parsed: $exec_found"
if [[ "$DEBUG" -eq 1 ]]; then
  echo "DEBUG: First 20 lines of exec events TSV (exec_id, pid, name, kib; tabs as [TAB]):" >&2
  head -n 20 "$tmp_exec_events" | sed -E $'s/\t/[TAB]/g' >&2
fi

########################################
# Step 4: Container logs (informational only)
########################################
container_kib="$(find "$LOGS_DIR" -maxdepth 1 -type f -name "*.container.log" -exec du -k {} + 2>/dev/null | awk '{s+=$1} END{print s+0}')"
echo "Total container log size: $(kib_to_mb "$container_kib") MB"
echo "Note: Container logs are not process-specific and are NOT included in per-process totals."

########################################
# Step 5: Generate stats (match python totals)
#
# For each execution event:
#  - map process_name -> process_id using proc_map
#  - if not found, create unknown_process_<hash%10000>
# totals per process_id:
#  - exec_count, exec_sum_kib, max_exec_kib
# total_kib = exec_sum_kib + def_kib
# avg_mb = (total_kib/1024) / exec_count
########################################
awk -F'\t' -v DEBUG="$DEBUG" '
function norm(s) {
  # 1) Whitespace + case
  gsub(/[[:space:]]+/," ",s)
  sub(/^ /,"",s)
  sub(/ $/,"",s)
  s = tolower(s)

  # 2) Normalize common Unicode punctuation to ASCII (best-effort)
  gsub(/’|‘/,"\047",s)
  gsub(/–|—/,"-",s)

  # 3) Strip common trailing wrappers that sometimes appear in logs
  #    e.g., Process Name (12345), Process Name [DEV]
  sub(/[[:space:]]*\\[[^]]*\\][[:space:]]*$/,"",s)

  # 4) Strip common copy suffixes
  #    e.g., Process Name - Copy
  sub(/[[:space:]]*-[[:space:]]*copy[[:space:]]*$/,"",s)

  # 5) Final trim
  gsub(/[[:space:]]+/," ",s)
  sub(/^ /,"",s)
  sub(/ $/,"",s)

  return s
}
function ord(c) { return index("\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037 !\"#$%&\047()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~", c) }
BEGIN { OFS="|" }
FNR==NR {
  # proc map file: pid, pname, ptype, folder, def_kib
  pid=$1; pname=$2; ptype=$3; folder=$4; def=$5+0
  nkey = norm(pname)
  # Keep first seen mapping per normalized name
  if (!(nkey in name_to_id)) {
    name_to_id[nkey]=pid
    id_to_name[pid]=pname
    id_to_type[pid]=ptype
    id_to_folder[pid]=folder
    def_kib[pid]=def
  }
  next
}
{
  # exec events: exec_id, pid_from_log, pname, exec_kib
  exec_id=$1
  pname=$3
  ekib=$4+0
  nkey = norm(pname)

  pid=name_to_id[nkey]
  if (pid=="") {
    # Stable-ish unknown id (consistent within a run)
    h=0
    for (i=1; i<=length(nkey); i++) h = (h*33 + ord(substr(nkey,i,1))) % 1000000007
    pid="unknown_process_" (h % 10000)
    if (!(pid in id_to_name)) {
      id_to_name[pid]=pname
      id_to_type[pid]="unknown"
      id_to_folder[pid]=""
      def_kib[pid]=0
      unknown_names[pname]=1
    }
  }

  # De-dupe by (process id, execution id)
  key = pid SUBSEP exec_id
  if (seen_exec[key]++) next

  exec_count[pid]++
  exec_sum[pid]+=ekib
  if (ekib > max_exec[pid]) max_exec[pid]=ekib
  seen[pid]=1
}
END {
  for (pid in seen) {
    c = exec_count[pid]+0
    es = exec_sum[pid]+0
    def = def_kib[pid]+0
    total = es + def
    avg = (c>0) ? (total / c) : 0
    m = max_exec[pid]+0
    maxv = (def > m) ? def : m

    print pid, id_to_name[pid], id_to_type[pid], id_to_folder[pid], c, total, avg, maxv, def, es
  }

  if (DEBUG==1) {
    u=0
    for (n in unknown_names) u++
    if (u>0) print "DEBUG: Unknown process names (not mapped to IDs): " u > "/dev/stderr"
  }
}
' "$tmp_proc_map" "$tmp_exec_events" > "$tmp_stats"

if [[ "$DEBUG" -eq 1 ]]; then
  echo "DEBUG: First 20 lines of computed stats (pipe-delimited):" >&2
  head -n 20 "$tmp_stats" >&2
fi

if [[ ! -s "$tmp_stats" ]]; then
  echo "No execution data found. Please check paths and that process_log.xml exists under $EXEC_DIR/history." >&2
  exit 0
fi

# Sort by total_kib desc and avg_kib desc
sort -t'|' -k6,6nr "$tmp_stats" > "$tmp_sorted_total"
sort -t'|' -k7,7nr "$tmp_stats" > "$tmp_sorted_avg"

print_table() {
  local title="$1"
  local file="$2"
  echo
  echo "$title"
  printf "%0.s=" {1..120}; echo
  printf "%-40s %-38s %6s %10s %8s %8s\n" "Process Name" "Process ID" "Count" "Total MB" "Avg MB" "Max MB"
  printf "%0.s-" {1..120}; echo

  head -n "$TOPN" "$file" | while IFS='|' read -r pid pname ptype folder cnt total_kib avg_kib max_kib def_kib exec_kib; do
    # Truncate like python
    disp_name="$pname"; [[ ${#disp_name} -gt 39 ]] && disp_name="${disp_name:0:39}"
    disp_id="$pid"; [[ ${#disp_id} -gt 37 ]] && disp_id="${disp_id:0:37}"
    total_mb="$(kib_to_mb "$total_kib")"
    avg_mb="$(kib_to_mb "$avg_kib")"
    max_mb="$(kib_to_mb "$max_kib")"
    printf "%-40s %-38s %6s %10s %8s %8s\n" "$disp_name" "$disp_id" "$cnt" "$total_mb" "$avg_mb" "$max_mb"
  done

  printf "%0.s-" {1..120}; echo
  total_lines="$(wc -l < "$file" | tr -d ' ')"
  show_n="$TOPN"; [[ "$show_n" -gt "$total_lines" ]] && show_n="$total_lines"
  echo "Showing top $show_n of $total_lines processes"
  if [[ "$TOPN" -gt "$total_lines" ]]; then
    echo "Note: Requested top $TOPN, but only $total_lines processes have execution history."
  fi
}

print_table "TOP PROCESSES BY TOTAL EXECUTION SIZE" "$tmp_sorted_total"
print_table "TOP PROCESSES BY AVERAGE EXECUTION SIZE" "$tmp_sorted_avg"

# CSV (sorted by total like python)
if [[ -n "$OUT_CSV" ]]; then
  {
    echo "Process Name,Process ID,Process Type,Folder Path,Execution Count,Total Size (Bytes),Total Size (MB),Average Size (MB),Max Size (MB),Process Definition Size (MB),Execution Logs Size (MB)"
    while IFS='|' read -r pid pname ptype folder cnt total_kib avg_kib max_kib def_kib exec_kib; do
      # Convert KiB -> Bytes and MB
      total_bytes=$(( total_kib * 1024 ))
      total_mb="$(kib_to_mb "$total_kib")"
      avg_mb="$(kib_to_mb "$avg_kib")"
      max_mb="$(kib_to_mb "$max_kib")"
      def_mb="$(kib_to_mb "$def_kib")"
      exec_mb="$(kib_to_mb "$exec_kib")"
      # CSV escape quotes
      pname_csv="${pname//\"/\"\"}"
      folder_csv="${folder//\"/\"\"}"
      echo "\"$pname_csv\",\"$pid\",\"$ptype\",\"$folder_csv\",$cnt,$total_bytes,$total_mb,$avg_mb,$max_mb,$def_mb,$exec_mb"
    done < "$tmp_sorted_total"
  } > "$OUT_CSV"

  echo
  echo "CSV written to: $OUT_CSV"
fi

if [[ "$KEEP_TEMP" -eq 1 ]]; then
  echo
  echo "Kept temp files for inspection:" >&2
  echo "  proc_map: $tmp_proc_map" >&2
  echo "  exec_events: $tmp_exec_events" >&2
  echo "  stats: $tmp_stats" >&2
  echo "  sorted_total: $tmp_sorted_total" >&2
  echo "  sorted_avg: $tmp_sorted_avg" >&2
fi
