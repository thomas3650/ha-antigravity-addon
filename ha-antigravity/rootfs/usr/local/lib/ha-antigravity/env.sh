# The environment of everything that runs as the antigravity user. Nothing
# from the container's own environment is passed on, so the token Home
# Assistant injects (SUPERVISOR_TOKEN) never reaches agy.
: "${HC_AGY_BIN:=agy}"
: "${HC_LIMIT_BIN:=/usr/local/bin/ha-antigravity-limit}"

resolve_tz() {
  if [[ -z "${TZ:-}" ]]; then
    log "no time zone from Home Assistant; using UTC"
    TZ=UTC
  fi
  export TZ
}

# Extra variables for the antigravity user, from the option assistant_env.
# Only names starting with ASSISTANT_ are accepted, so an option cannot
# replace HOME, PATH or a variable agy itself reads.
assistant_env() {
  local re='\AASSISTANT_[A-Z0-9_]+=[^\x00-\x1f\x7f]*\z' name
  [[ -f "$HC_OPTIONS" ]] || return 0
  jq -r --arg re "$re" '.assistant_env[]? | strings | select(test($re))' "$HC_OPTIONS" 2>/dev/null
  while IFS= read -r name; do
    if [[ -n "$name" ]]; then
      log "options: ignoring assistant_env entry '$name'"
    else
      log "options: ignoring an assistant_env entry without a name"
    fi
  done < <(jq -r --arg re "$re" \
            '.assistant_env[]? | strings | select(test($re) | not) | ([capture("\\A(?<n>[A-Za-z0-9_]+)=").n][0] // "")' \
            "$HC_OPTIONS" 2>/dev/null)
  return 0
}

agy_env() {
  printf '%s\n' \
    "HOME=$HC_HOME" \
    "USER=$HC_USER" \
    "LOGNAME=$HC_USER" \
    "SHELL=/bin/bash" \
    "PATH=/usr/local/bin:/usr/bin:/bin" \
    "TERM=${TERM:-xterm-256color}" \
    "LANG=C.UTF-8" \
    "TZ=${TZ:-UTC}" \
    "HC_DATA=$HC_DATA" \
    "AGY_CLI_DISABLE_AUTO_UPDATE=true"
  assistant_env 2>/dev/null
}

as_antigravity() {
  local -a vars
  local runuser_bin
  mapfile -t vars < <(agy_env)
  if [[ "$(id -u)" == 0 ]]; then
    runuser_bin="$(command -v runuser || echo /usr/sbin/runuser)"
    env -i "${vars[@]}" "$runuser_bin" -u "$HC_USER" -- "$@"
  else
    env -i "${vars[@]}" "$@"
  fi
}

# Removes the transient conversation artifacts and transcript created by one
# headless run, giving --no-session-persistence parity.
_agy_cleanup_conv() {
  local out="$1" cid=""
  cid="$(jq -Rr 'fromjson? | objects | .conversation_id | strings' "$out" 2>/dev/null | head -n 1)" || cid=""
  [[ "$cid" =~ ^[A-Za-z0-9-]{8,64}$ ]] || return 0
  as_antigravity rm -rf -- \
    "$HC_HOME/.gemini/antigravity-cli/brain/$cid" \
    "$HC_HOME/.gemini/antigravity-cli/conversations/$cid" \
    "$HC_HOME/.gemini/antigravity-cli/conversations/$cid."* </dev/null >/dev/null 2>&1 || true
}

# agy_once <agent> <seconds> <turns> <prompt-file> <out-file> [VAR=value...]
# - runs agy once as the antigravity user, without a terminal, as the agent,
# from the working folder, within the time limit and the turn limit
# (enforced by the workspace PreInvocation hook via HA_AGY_MAX_TURNS), and
# marked as unattended for the gate (HA_AGY_UNATTENDED). The prompt arrives
# on stdin as stream-json, never on a command line. Returns 124 on timeout
# (whether from ha-antigravity-limit or agy --print-timeout exit 3), 1 when
# the turn limit stopped the run, or agy's own status.
agy_once() {
  local agent="$1" seconds="$2" turns="$3" prompt="$4" out="$5" rc=0 model="" turns_mark
  shift 5
  if declare -F opt >/dev/null 2>&1; then
    model="$(opt '.job_model' '')"
  fi
  if [[ -n "$model" && ! "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
    declare -F log >/dev/null 2>&1 && log "options: ignoring invalid job_model"
    model=""
  fi
  turns_mark="$HC_HOME/.cache/ha-antigravity/turns-${agent}-${BASHPID:-$$}"
  as_antigravity mkdir -p "$(dirname "$turns_mark")" </dev/null >/dev/null 2>&1 || true
  as_antigravity rm -f -- "$turns_mark" </dev/null >/dev/null 2>&1 || true
  local -a extra_args=(
    --input-format stream-json --output-format stream-json
    --disable-slash-commands --print-timeout "${seconds}s"
    --agent "$agent"
    --add-dir "$HC_HANDOVER" --add-dir "$HC_RESULTS" --add-dir "$HC_NOTES" --add-dir "$HC_JOBS"
  )
  [[ -f "$HC_MANAGED_DIR/settings.json" ]] && extra_args+=(--settings "$HC_MANAGED_DIR/settings.json")
  [[ -n "$model" ]] && extra_args+=(--model "$model")
  local stream_in="$HC_STATE/agy-in-${agent}-${BASHPID:-$$}.jsonl"
  mkdir -p "$HC_STATE"
  ( umask 077; jq -cn --rawfile content "$prompt" '{event:"user",message:{content:$content}}' > "$stream_in" )
  ( cd "$HC_WORKSPACE" && as_antigravity env \
      HA_AGY_UNATTENDED="$agent" \
      HA_AGY_MAX_TURNS="$turns" \
      HA_AGY_TURNS_MARK="$turns_mark" \
      "$@" \
      "$HC_LIMIT_BIN" "$seconds" "$HC_AGY_BIN" "${extra_args[@]}" \
  ) <"$stream_in" >>"$out" 2>&1 &
  wait $! || rc=$?
  rm -f -- "$stream_in"
  _agy_cleanup_conv "$out"
  if [[ -f "$turns_mark" && ! -L "$turns_mark" ]]; then
    as_antigravity rm -f -- "$turns_mark" </dev/null >/dev/null 2>&1 || true
    printf 'ha-antigravity: reached max turns (%s)\n' "$turns" >> "$out"
    return 1
  fi
  if (( rc == 3 )); then
    return 124
  fi
  return "$rc"
}
