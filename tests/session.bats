load helpers

@test "chat_command launches agy --remote-control with add-dirs and never dangerously-skip-permissions" {
  load_lib options session
  export HC_MANAGED_DIR="$BATS_TEST_TMPDIR/managed"
  set_options '{"session_name":"Home"}'
  mkdir -p "$HC_WORKSPACE"
  run chat_command
  [[ "${lines[0]}" == "agy" ]]
  [[ "$output" == *"--remote-control"* ]]
  [[ "$output" == *"$HC_HANDOVER"* ]]
  [[ "$output" != *"--agent"* ]]
  [[ "$output" != *"dangerously"* ]]
}

@test "chat_command uses --settings, --model, and --agent chat when present" {
  load_lib options session
  export HC_MANAGED_DIR="$BATS_TEST_TMPDIR/managed"
  mkdir -p "$HC_MANAGED_DIR" "$HC_WORKSPACE/.agents/agents/chat"
  printf '{"toolPermission":"request-review"}\n' > "$HC_MANAGED_DIR/settings.json"
  touch "$HC_WORKSPACE/.agents/agents/chat/agent.md"
  set_options '{"chat_model":"claude-opus-5-5-medium"}'
  run chat_command
  [[ "$output" == *$'--settings\n'"$HC_MANAGED_DIR/settings.json"* ]]
  [[ "$output" == *$'--agent\nchat'* ]]
  [[ "$output" == *$'--model\nclaude-opus-5-5-medium'* ]]
}

@test "chat_command passes an opening prompt with -i" {
  load_lib options session
  mkdir -p "$HC_WORKSPACE"
  run chat_command "Present today's summary"
  [ "${lines[${#lines[@]}-2]}" = "-i" ]
  [ "${lines[${#lines[@]}-1]}" = "Present today's summary" ]
}

@test "logged_in follows the credentials file" {
  load_lib options session
  run logged_in
  [ "$status" -ne 0 ]
  mkdir -p "$(dirname "$HC_AUTH_FILE")"
  printf '{"token":"ok"}\n' > "$HC_AUTH_FILE"
  run logged_in
  [ "$status" -eq 0 ]
}

@test "start_chat hands session name, chat_model, session mark, and assistant_env to tmux" {
  load_lib options env session
  set_options '{"session_name":"Office","chat_model":"gemini-4-neon-high","assistant_env":["ASSISTANT_ONE=1","PATH=/tmp/evil"]}'
  as_antigravity() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/as_agy"; [[ "$*" != *has-session* ]]; }
  start_chat
  grep -q -- "-e HC_SESSION_NAME=Office" "$BATS_TEST_TMPDIR/as_agy"
  grep -q -- "-e HC_CHAT_MODEL=gemini-4-neon-high" "$BATS_TEST_TMPDIR/as_agy"
  grep -q -- "-e HA_AGY_SESSION_MARK=" "$BATS_TEST_TMPDIR/as_agy"
  grep -q -- "-e ASSISTANT_ONE=1" "$BATS_TEST_TMPDIR/as_agy"
  ! grep -q -- "PATH=/tmp/evil" "$BATS_TEST_TMPDIR/as_agy"
}

@test "start_chat hands an opening prompt to the chat session, and none when none is given" {
  load_lib options env session
  as_antigravity() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/as_agy"; [[ "$*" != *has-session* ]]; }
  start_chat "Say hello to the owner"
  grep -q -- "-e HC_OPENING_PROMPT=Say hello to the owner" "$BATS_TEST_TMPDIR/as_agy"
  : > "$BATS_TEST_TMPDIR/as_agy"
  start_chat
  ! grep -q -- "HC_OPENING_PROMPT" "$BATS_TEST_TMPDIR/as_agy"
}

@test "restart_chat ends the session and passes the opening prompt on" {
  load_lib options env session
  as_antigravity() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/as_agy"; [[ "$*" != *has-session* ]]; }
  restart_chat "Say hello to the owner"
  grep -q -- "kill-session" "$BATS_TEST_TMPDIR/as_agy"
  grep -q -- "-e HC_OPENING_PROMPT=Say hello to the owner" "$BATS_TEST_TMPDIR/as_agy"
}

@test "the opening prompt is used for the first start only" {
  load_lib options session
  mkdir -p "$HC_WORKSPACE"
  export HC_OPENING_PROMPT="Say hello to the owner"
  next_chat_argv
  [ "${CHAT_ARGV[0]}" = "agy" ]
  [ "${CHAT_ARGV[${#CHAT_ARGV[@]}-1]}" = "Say hello to the owner" ]
  [ -z "${HC_OPENING_PROMPT:-}" ]
  next_chat_argv
  [ "${CHAT_ARGV[0]}" = "agy" ]
  [[ "${CHAT_ARGV[*]}" != *"Say hello"* ]]
}

@test "chat_resume passes --continue unless fresh or opening prompt or failed" {
  load_lib options session
  mkdir -p "$HC_WORKSPACE"
  set_options '{"chat_resume":true}'
  next_chat_argv
  [ "$CHAT_RESUMING" -eq 1 ]
  [ "${CHAT_ARGV[${#CHAT_ARGV[@]}-1]}" = "--continue" ]
  export HC_CHAT_FRESH=1
  next_chat_argv
  [ "$CHAT_RESUMING" -eq 0 ]
  [[ "${CHAT_ARGV[*]}" != *"--continue"* ]]
  export HC_OPENING_PROMPT="Good morning"
  next_chat_argv
  [ "$CHAT_RESUMING" -eq 0 ]
  [[ "${CHAT_ARGV[*]}" != *"--continue"* ]]
}

@test "a chat session that cannot be started is tried once more, and the failure is logged" {
  load_lib options env session
  as_antigravity() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/as_agy"; return 1; }
  run start_chat
  [ "$(grep -c -- "new-session" "$BATS_TEST_TMPDIR/as_agy")" -eq 2 ]
  [[ "$output" == *"could not be started"* ]]
}

@test "a new chat session starts from a handover folder with nothing that reads as instructions" {
  load_lib options env retention session
  mkdir -p "$HC_HANDOVER"; touch "$HC_HANDOVER/AGENTS.md"
  as_antigravity() { [[ "$*" != *has-session* ]]; }
  start_chat 2>/dev/null
  [ ! -e "$HC_HANDOVER/AGENTS.md" ]
}

@test "chat_quick_exits counts quick exits and resets after 30s" {
  load_lib options session
  [ "$(chat_quick_exits 0 3)" = 1 ]
  [ "$(chat_quick_exits 1 29)" = 2 ]
  [ "$(chat_quick_exits 2 0)" = 3 ]
  [ "$(chat_quick_exits 2 30)" = 0 ]
  [ "$(chat_quick_exits x y)" = 1 ]
}

@test "chat_resume_failed clears --continue after quick exit or repeated failures" {
  load_lib options session
  CHAT_RESUMING=1
  run chat_resume_failed 5 1
  [ "$status" -eq 0 ]
  CHAT_RESUMING=1
  chat_resume_failed 5 1
  [ "$HC_RESUME_FAILED" = "1" ]
  unset HC_RESUME_FAILED
  CHAT_RESUMING=1
  ! chat_resume_failed 45 1
  [ "${CHAT_RESUME_FAILS}" -eq 1 ]
  ! chat_resume_failed 45 1
  [ "$HC_RESUME_FAILED" = "1" ]
}

@test "managed_session_hook reads workspace .agents/hooks.json SessionStart" {
  load_lib options session
  mkdir -p "$HC_WORKSPACE/.agents"
  run managed_session_hook
  [ "$status" -ne 0 ]
  printf '{"h":{"SessionStart":[{"type":"command","command":"./hooks/session-start"}]}}\n' > "$HC_WORKSPACE/.agents/hooks.json"
  run managed_session_hook
  [ "$status" -eq 0 ]
}

@test "clear_chat sends /clear and confirms via session mark, or restarts when unconfirmed" {
  load_lib options env retention session
  mkdir -p "$HC_WORKSPACE/.agents" "$(dirname "$HC_SESSION_MARK")"
  printf '{"h":{"SessionStart":[{"type":"command","command":"./hooks/session-start"}]}}\n' > "$HC_WORKSPACE/.agents/hooks.json"
  chat_alive() { return 0; }
  _pane_runs_agy() { return 0; }
  as_antigravity() {
    printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/keys"
    if [[ "$*" == *"/clear"* ]]; then
      printf 'clear %s\n' "$(date +%s)" > "$HC_SESSION_MARK"
    fi
  }
  run clear_chat "Good morning"
  [ "$status" -eq 0 ]
  grep -q -- "-l /clear" "$BATS_TEST_TMPDIR/keys"
  grep -q -- "set-buffer -b hc-opening -- Good morning" "$BATS_TEST_TMPDIR/keys"

  # Unconfirmed clear falls back to restart_chat
  rm -f "$HC_SESSION_MARK"
  HC_CLEAR_WAIT=0
  as_antigravity() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/keys2"; return 0; }
  restart_chat() { printf 'RESTART %s %s\n' "$1" "$2" > "$BATS_TEST_TMPDIR/restarted"; }
  run clear_chat "Hello"
  [ "$(cat "$BATS_TEST_TMPDIR/restarted")" = "RESTART Hello fresh" ]
}

@test "the chat loop leaves a shell after three quick exits and waits before restarts" {
  chat="$BATS_TEST_DIRNAME/../ha-antigravity/rootfs/usr/local/bin/ha-antigravity-chat"
  grep -q 'quick_exits="$(chat_quick_exits "$quick_exits" "$((SECONDS - started))")"' "$chat"
  grep -q 'if (( quick_exits >= 3 )); then' "$chat"
  grep -q 'exec bash -l' "$chat"
  grep -q 'sleep 10' "$chat"
}
