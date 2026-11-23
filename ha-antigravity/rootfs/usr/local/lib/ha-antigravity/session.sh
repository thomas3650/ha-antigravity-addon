# The chat session: Antigravity CLI with Remote Control in tmux, as the
# antigravity user. A session is started fresh, unless the option chat_resume
# is on: then it continues the last conversation (--continue), except when it
# opens with a prompt or a clear had to become a restart.

HC_TMUX_SOCKET=ha
HC_TMUX_SESSION=chat

logged_in() {
  [[ -s "$HC_AUTH_FILE" ]] && return 0
  local d f
  for d in "$HC_HOME/.gemini/antigravity-cli" "$HC_HOME/.config" "$HC_HOME/.local/share"; do
    [[ -d "$d" ]] || continue
    f="$(find "$d" -maxdepth 3 -type f -size +0c \
         \( -name 'antigravity-oauth-token' -o -name 'credential-user-scope' -o -name 'authstore.enc' -o -name 'auth.json' -o -name 'plugin-secrets.json' \) \
         2>/dev/null | head -n 1)"
    [[ -n "$f" ]] && return 0
  done
  return 1
}

managed_session_hook() {
  jq -e 'any(.[]; ((.enabled // true) == true) and ((.SessionStart // []) | arrays | length > 0))' \
    "$HC_WORKSPACE/.agents/hooks.json" >/dev/null 2>&1
}

chat_resume_on() {
  [[ "${HC_CHAT_RESUME:-$(opt_bool '.chat_resume' false)}" == true ]]
}

# Prints the argv for the chat session, one argument per line.
chat_command() {
  local model=""
  model="${HC_CHAT_MODEL:-$(opt '.chat_model' '')}"
  if [[ -n "$model" && ! "$model" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
    log "options: ignoring invalid chat_model"
    model=""
  fi
  local -a argv=(agy --remote-control)
  [[ -f "$HC_MANAGED_DIR/settings.json" ]] && argv+=(--settings "$HC_MANAGED_DIR/settings.json")
  argv+=(--add-dir "$HC_HANDOVER" --add-dir "$HC_RESULTS" --add-dir "$HC_NOTES" --add-dir "$HC_JOBS")
  if [[ -f "$HC_WORKSPACE/.agents/agents/chat/agent.md" || -f "$HC_WORKSPACE/.agents/agents/chat.md" ]]; then
    argv+=(--agent chat)
  fi
  [[ -n "$model" ]] && argv+=(--model "$model")
  if [[ -n "${1:-}" ]]; then
    argv+=(-i "$1")
  elif chat_resume_on && [[ -z "${HC_CHAT_FRESH:-}" && -z "${HC_RESUME_FAILED:-}" ]]; then
    argv+=(--continue)
  fi
  printf '%s\n' "${argv[@]}"
}

next_chat_argv() {
  mapfile -t CHAT_ARGV < <(chat_command "${HC_OPENING_PROMPT:-}")
  CHAT_RESUMING=0
  [[ "${CHAT_ARGV[${#CHAT_ARGV[@]}-1]}" == --continue ]] && CHAT_RESUMING=1
  unset HC_OPENING_PROMPT HC_CHAT_FRESH HC_RESUME_FAILED
}

: "${HC_CHAT_QUICK:=30}"
: "${HC_RESUME_TRIES:=2}"
chat_resume_failed() {
  local took="$1" rc="$2"
  [[ "$took" =~ ^[0-9]+$ ]] || took=0
  [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
  [[ "${CHAT_RESUME_FAILS:-}" =~ ^[0-9]+$ ]] || CHAT_RESUME_FAILS=0
  if [[ "${CHAT_RESUMING:-0}" != 1 ]] || (( rc == 0 )); then
    CHAT_RESUME_FAILS=0
    return 1
  fi
  if (( took < HC_CHAT_QUICK )); then
    CHAT_RESUME_FAILS=0
    HC_RESUME_FAILED=1
    return 0
  fi
  CHAT_RESUME_FAILS=$((CHAT_RESUME_FAILS + 1))
  if (( CHAT_RESUME_FAILS >= HC_RESUME_TRIES )); then
    CHAT_RESUME_FAILS=0
    HC_RESUME_FAILED=1
  fi
  return 1
}

chat_alive() {
  as_antigravity tmux -L "$HC_TMUX_SOCKET" has-session -t "$HC_TMUX_SESSION" 2>/dev/null
}

start_chat() {
  local entry prompt="${1:-}" fresh="${2:-}" try
  local -a extra=()
  [[ -z "$prompt" && -z "$fresh" ]] && chat_alive && return 0
  declare -F clean_handover >/dev/null && clean_handover
  log "chat: starting a new session"
  while IFS= read -r entry; do
    extra+=(-e "$entry")
  done < <(assistant_env)
  [[ -n "$prompt" ]] && extra+=(-e "HC_OPENING_PROMPT=$prompt")
  [[ -n "$fresh" ]] && extra+=(-e "HC_CHAT_FRESH=1")
  as_antigravity mkdir -p "$(dirname "$HC_SESSION_MARK")" 2>/dev/null || true
  for try in 1 2; do
    if chat_alive; then
      [[ -z "$prompt" && -z "$fresh" ]] && return 0
      as_antigravity tmux -L "$HC_TMUX_SOCKET" kill-session -t "$HC_TMUX_SESSION" 2>/dev/null || true
    fi
    as_antigravity tmux -L "$HC_TMUX_SOCKET" new-session -d -s "$HC_TMUX_SESSION" \
      -e "HC_SESSION_NAME=$(opt '.session_name' 'Home')" \
      -e "HC_CHAT_RESUME=$(opt_bool '.chat_resume' false)" \
      -e "HC_CHAT_MODEL=$(opt '.chat_model' '')" \
      -e "HA_AGY_SESSION_MARK=$HC_SESSION_MARK" \
      "${extra[@]}" \
      -c "$HC_WORKSPACE" /usr/local/bin/ha-antigravity-chat && return 0
    (( try == 1 )) && sleep 1
  done
  log "chat: a new session could not be started"
  return 1
}

restart_chat() {
  as_antigravity tmux -L "$HC_TMUX_SOCKET" kill-session -t "$HC_TMUX_SESSION" 2>/dev/null || true
  start_chat "${1:-}" "${2:-}"
}

: "${HC_CLEAR_WAIT:=15}"
_clear_seen() {
  local line src at
  if [[ "$(id -u)" == 0 ]] && declare -F as_antigravity >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    line="$(as_antigravity timeout 2 sh -c '[ -f "$1" ] && [ ! -L "$1" ] && head -c 64 -- "$1"' sh "$HC_SESSION_MARK" </dev/null 2>/dev/null)" || return 1
  else
    [[ -f "$HC_SESSION_MARK" && ! -L "$HC_SESSION_MARK" ]] || return 1
    if command -v timeout >/dev/null 2>&1; then
      line="$(timeout 2 head -c 64 -- "$HC_SESSION_MARK" 2>/dev/null)" || return 1
    else
      line="$(head -c 64 -- "$HC_SESSION_MARK" 2>/dev/null)" || return 1
    fi
  fi
  read -r src at <<<"$line"
  [[ "$src" =~ ^[a-z]+$ && "$at" =~ ^[0-9]+$ ]] && (( at >= $1 ))
}

_pane_runs_agy() {
  local tty
  tty="$(as_antigravity tmux -L "$HC_TMUX_SOCKET" display-message -p -t "$HC_TMUX_SESSION" \
           '#{pane_tty}' 2>/dev/null)" || return 1
  [[ "$tty" =~ ^/dev/(pts/[0-9]+)$ ]] || return 1
  pgrep -t "${BASH_REMATCH[1]}" -f -- '--remote-control' >/dev/null 2>&1
}

_chat_keys() {
  as_antigravity tmux -L "$HC_TMUX_SOCKET" send-keys -t "$HC_TMUX_SESSION" "$@"
}

clear_chat() {
  local prompt="${1:-}" since waited=0
  if ! managed_session_hook || ! chat_alive; then
    restart_chat "$prompt" fresh
    return
  fi
  if ! _pane_runs_agy; then
    log "chat: Antigravity CLI is not running in the pane; restarting"
    restart_chat "$prompt" fresh
    return
  fi
  as_antigravity rm -f "$HC_SESSION_MARK" 2>/dev/null || true
  since="$(date +%s)"
  _chat_keys Escape
  sleep 0.5
  _chat_keys C-u
  _chat_keys -l /clear
  _chat_keys Enter
  until _clear_seen "$since"; do
    (( waited >= HC_CLEAR_WAIT )) && break
    sleep 1
    waited=$((waited + 1))
  done
  if ! _clear_seen "$since"; then
    log "chat: the clear was not confirmed; restarting"
    restart_chat "$prompt" fresh
    return
  fi
  declare -F clean_handover >/dev/null && clean_handover
  if [[ -n "$prompt" ]]; then
    as_antigravity tmux -L "$HC_TMUX_SOCKET" set-buffer -b hc-opening -- "$prompt"
    as_antigravity tmux -L "$HC_TMUX_SOCKET" paste-buffer -p -d -b hc-opening -t "$HC_TMUX_SESSION"
    sleep 0.5
    _chat_keys Enter
  fi
  log "chat: a new conversation"
}

chat_quick_exits() {
  local count="$1" took="$2"
  [[ "$count" =~ ^[0-9]+$ ]] || count=0
  [[ "$took" =~ ^[0-9]+$ ]] || took=0
  if (( took < HC_CHAT_QUICK )); then
    printf '%s' "$((count + 1))"
  else
    printf '0'
  fi
}
