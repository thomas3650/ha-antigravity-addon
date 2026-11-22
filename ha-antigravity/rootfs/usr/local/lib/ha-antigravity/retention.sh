# Handover retention and instruction-file cleaning across writable folders.
_days_ago() {
  date -d "$1 days ago" +%F 2>/dev/null || date -v-"$1"d +%F
}

prune_handover() {
  local cutoff file name day removed=0 days="${HC_HANDOVER_DAYS:-30}"
  [[ "$days" =~ ^[0-9]+$ ]] || return 0
  cutoff="$(_days_ago "$days")" || return 0
  for file in "$HC_HANDOVER"/*.md; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    name="${file##*/}"; day="${name%.md}"
    [[ "$day" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || continue
    if [[ "$day" < "$cutoff" ]]; then
      rm -f "$file" && removed=$((removed + 1))
    fi
  done
  if (( removed )); then
    log "handover: removed $removed file(s) older than $days days"
  fi
  return 0
}

clean_handover() {
  local removed=0
  local -a runner=() dirs=()
  [[ -d "$HC_HANDOVER" ]] && dirs+=("$HC_HANDOVER")
  [[ -d "${HC_RESULTS:-}" ]] && dirs+=("$HC_RESULTS")
  [[ -d "${HC_NOTES:-}" ]] && dirs+=("$HC_NOTES")
  [[ -d "${HC_JOBS:-}" ]] && dirs+=("$HC_JOBS")
  (( ${#dirs[@]} )) || return 0
  if [[ "$(id -u)" == 0 ]] && declare -F as_antigravity >/dev/null; then
    runner=(as_antigravity)
  fi
  removed="$("${runner[@]}" find "${dirs[@]}" -mindepth 1 \( \
                 -iname AGENTS.md -o -iname GEMINI.md \
                 -o -iname CLAUDE.md -o -iname CLAUDE.local.md \
                 -o -iname .agents -o -iname .agent -o -iname _agents -o -iname _agent \
                 -o -iname .claude -o -iname hooks.json -o -iname mcp_config.json -o -iname .mcp.json \
               \) -prune -print -exec rm -rf {} + 2>/dev/null | wc -l)"
  removed="${removed//[[:space:]]/}"
  if (( ${removed:-0} )); then
    log "handover: removed $removed file(s) that could be read as instructions"
  fi
  return 0
}
