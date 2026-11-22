# The run command's agent: Antigravity CLI once (agy_once), as the agent the
# command named, with the options run_timeout and run_max_turns.
run_name_ok() {
  [[ "$1" =~ ^[a-z][a-z0-9-]{0,31}$ ]] || return 1
  [[ "$1" != chat ]]
}

run_configured() {
  local dir_file="$HC_WORKSPACE/.agents/agents/$1/agent.md"
  local flat_file="$HC_WORKSPACE/.agents/agents/$1.md"
  run_name_ok "$1" || return 1
  { [[ -f "$dir_file" && ! -L "$dir_file" ]] || [[ -f "$flat_file" && ! -L "$flat_file" ]]; }
}

run_agent() {
  local _ra_agent="${2:-}" _ra_limit _ra_turns _ra_log _ra_prompt _ra_rc=0 _ra_started=$SECONDS
  local _ra_marker="$HC_STATE/run-${2:-}.started"
  if ! run_configured "$_ra_agent"; then
    printf -v "$1" '%s' not_configured
    return 0
  fi
  _ra_limit="$(opt_number '.run_timeout' 900)"
  _ra_turns="$(opt_number '.run_max_turns' 60)"
  _ra_log="$HC_STATE/run-$_ra_agent.log"
  _ra_prompt="$HC_STATE/run-$_ra_agent.prompt"
  mkdir -p "$HC_STATE"
  declare -F clean_handover >/dev/null && clean_handover
  clear_result "$_ra_agent"
  : > "$_ra_marker"
  rm -f "$_ra_log"
  ( umask 077; : > "$_ra_log"
    printf 'Today is %s. Your result file is %s/%s.json. Do your run.\n' \
      "$(date +%F)" "$HC_RESULTS" "$_ra_agent" > "$_ra_prompt" )
  agy_once "$_ra_agent" "$_ra_limit" "$_ra_turns" "$_ra_prompt" "$_ra_log" || _ra_rc=$?
  rm -f -- "$_ra_prompt"
  log "run: $_ra_agent ended with status $_ra_rc after $((SECONDS - _ra_started)) seconds"
  if (( _ra_rc == 124 )); then
    printf -v "$1" '%s' timeout
  elif (( _ra_rc == 0 )) && publish_result "$_ra_agent" "$_ra_marker"; then
    printf -v "$1" '%s' ok
  else
    printf -v "$1" '%s' failed
  fi
}
