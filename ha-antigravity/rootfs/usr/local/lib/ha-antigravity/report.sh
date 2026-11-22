# The report command: runs the working folder's .agents/report as the
# antigravity user and writes what it prints to the add-on's log, framed,
# limited and cleaned.
: "${HC_LIMIT_BIN:=/usr/local/bin/ha-antigravity-limit}"
: "${HC_REPORT_LIMIT:=30}"
: "${HC_REPORT_GRACE:=5}"
: "${HC_REPORT_LINES:=200}"
: "${HC_REPORT_CHARS:=200}"
: "${HC_REPORT_KIB:=256}"
HC_REPORT_FILE=.agents/report

report_configured() {
  local src="$HC_WORKSPACE/$HC_REPORT_FILE" real_dir real_ws
  [[ -f "$src" && ! -L "$src" ]] || return 1
  real_dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd -P)" || return 1
  real_ws="$(cd -P "$HC_WORKSPACE" 2>/dev/null && pwd -P)" || return 1
  [[ "$real_dir" == "$real_ws/.agents" ]] || return 1
  as_antigravity test -r "$src" -a -x "$src" </dev/null >/dev/null 2>&1
}

_report_frame() {
  # shellcheck disable=SC2034
  local LC_ALL=C.UTF-8
  local label="${1:-report}" max="${2:-$HC_REPORT_LINES}" chars="${3:-$HC_REPORT_CHARS}"
  local kib="${4:-$HC_REPORT_KIB}" line n=0 more=0
  printf '%s: begin\n' "$label"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line//[[:cntrl:]]/}"
    line="${line//[$'\xc2\x80'-$'\xc2\x9f']/}"
    [[ -n "$line" ]] || continue
    if (( n >= max )); then more=1; break; fi
    n=$((n + 1))
    printf '%s: | %s\n' "$label" "${line:0:chars}"
  done < <(head -c "$((kib * 1024))" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null \
           | tr -d '\000-\011\013-\037\177' | grep -av '^$')
  if (( more )); then
    printf '%s: end, %d lines, more left out\n' "$label" "$n"
  else
    printf '%s: end, %d lines\n' "$label" "$n"
  fi
}

run_report() {
  local _rr_month="${2:-}" _rr_src="$HC_WORKSPACE/$HC_REPORT_FILE" _rr_out="$HC_STATE/report.out" _rr_rc=0
  local -a _rr_args=()
  if [[ -n "$_rr_month" && ! "$_rr_month" =~ ^[0-9]{4}-[0-9]{2}$ ]]; then
    log "report: the argument is not a month"
    printf -v "$1" '%s' failed
    return 0
  fi
  if ! report_configured; then
    printf -v "$1" '%s' not_configured
    return 0
  fi
  [[ -n "$_rr_month" ]] && _rr_args=("$_rr_month")
  mkdir -p "$HC_STATE"
  rm -f "$_rr_out"
  ( umask 077; : > "$_rr_out" )
  ( cd "$HC_WORKSPACE" && ulimit -f "$HC_REPORT_KIB" && as_antigravity env HC_LIMIT_GRACE="$HC_REPORT_GRACE" \
      "$HC_LIMIT_BIN" "$HC_REPORT_LIMIT" "$_rr_src" "${_rr_args[@]}" \
  ) </dev/null >>"$_rr_out" 2>/dev/null &
  wait $! || _rr_rc=$?
  if (( _rr_rc == 0 )); then
    _report_frame report "$HC_REPORT_LINES" "$HC_REPORT_CHARS" "$HC_REPORT_KIB" < "$_rr_out" | log_lines
    printf -v "$1" '%s' ok
  elif (( _rr_rc == 124 )); then
    log "report: failed with status 124, the time limit"
    printf -v "$1" '%s' failed
  else
    log "report: failed with status $_rr_rc"
    printf -v "$1" '%s' failed
  fi
  rm -f "$_rr_out"
  return 0
}
