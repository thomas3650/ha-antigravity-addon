# Reports the result of a command to Home Assistant as one fixed event
# (ha_antigravity_outcome). Run by the add-on's own script as root.
raise_outcome() {
  local command="$1" outcome="$2" agent="${3:-}" by="${4:-}" body
  if [[ -z "${SUPERVISOR_TOKEN:-}" ]]; then
    log "outcome: $command=$outcome${agent:+ $agent} (not reported: no Supervisor token)"
    return 0
  fi
  # shellcheck disable=SC2016
  body="$(jq -cn --arg c "$command" --arg o "$outcome" --arg a "$agent" --arg b "$by" \
            '{command:$c,outcome:$o} + (if $a != "" then {agent:$a} else {} end)
             + (if $b != "" then {by:$b} else {} end)')"
  if curl -fsS -m 10 -o /dev/null -X POST \
       -H "Content-Type: application/json" \
       -d "$body" \
       -K - \
       "${HC_CORE_API:-http://supervisor/core/api}/events/ha_antigravity_outcome" \
       <<<"header = \"Authorization: Bearer $SUPERVISOR_TOKEN\""; then
    log "outcome: $command=$outcome"
  else
    log "outcome: $command=$outcome (could not reach Home Assistant)"
  fi
  return 0
}
