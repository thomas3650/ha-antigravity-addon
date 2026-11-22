load helpers
bats_require_minimum_version 1.5.0

@test "agy_env has HOME and no Supervisor token" {
  load_lib env
  export SUPERVISOR_TOKEN=secret
  run agy_env
  [[ "$output" == *"HOME=$HC_HOME"* ]]
  [[ "$output" != *"SUPERVISOR_TOKEN"* ]]
  [[ "$output" != *"secret"* ]]
}

@test "as_antigravity runs a command without the Supervisor token and disables auto-update" {
  load_lib env
  export SUPERVISOR_TOKEN=secret HASSIO_TOKEN=secret2
  run as_antigravity env
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret"* ]]
  [[ "$output" == *"AGY_CLI_DISABLE_AUTO_UPDATE=true"* ]]
}

@test "resolve_tz keeps a TZ that is set" {
  load_lib env
  export TZ=America/New_York
  resolve_tz
  [ "$TZ" = "America/New_York" ]
}

@test "resolve_tz falls back to UTC and says so" {
  load_lib env
  unset TZ
  run bash -c "source '$LIB/paths.sh'; source '$LIB/log.sh'; source '$LIB/env.sh'; resolve_tz; echo TZ=\$TZ"
  [[ "$output" == *"TZ=UTC"* ]]
  [[ "$output" == *"no time zone"* ]]
}

@test "assistant_env passes entries whose names start with ASSISTANT_" {
  load_lib options env
  set_options '{"assistant_env":["ASSISTANT_ONE=http://example.test:1/mcp","ASSISTANT_TWO=b c"]}'
  run --separate-stderr assistant_env
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ASSISTANT_ONE=http://example.test:1/mcp" ]
  [ "${lines[1]}" = "ASSISTANT_TWO=b c" ]
  [ -z "$stderr" ]
}

@test "assistant_env ignores other names and logs the name, not the value" {
  load_lib options env
  set_options '{"assistant_env":["PATH=/tmp/evil","HOME=/tmp","GEMINI_API_KEY=sk-secret","assistant_lower=x","ASSISTANT_OK=1"]}'
  run --separate-stderr assistant_env
  [ "$status" -eq 0 ]
  [ "$output" = "ASSISTANT_OK=1" ]
  [[ "$stderr" == *"ignoring assistant_env entry 'PATH'"* ]]
  [[ "$stderr" == *"ignoring assistant_env entry 'GEMINI_API_KEY'"* ]]
  [[ "$stderr" != *"sk-secret"* ]]
  [[ "$stderr" != *"/tmp/evil"* ]]
}

@test "assistant_env refuses a whole entry that holds a line break" {
  load_lib options env
  set_options '{"assistant_env":["ASSISTANT_A=1\nASSISTANT_B=2","ASSISTANT_OK=1"]}'
  run --separate-stderr assistant_env
  [ "$status" -eq 0 ]
  [ "$output" = "ASSISTANT_OK=1" ]
}

@test "assistant_env never logs an entry that has no name" {
  load_lib options env
  set_options '{"assistant_env":["sk-pasted-secret with spaces","barewordsecret123","half_secret=rest"]}'
  run --separate-stderr assistant_env
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [[ "$stderr" != *"pasted"* ]]
  [[ "$stderr" != *"barewordsecret123"* ]]
  [[ "$stderr" == *"an assistant_env entry without a name"* ]]
  [[ "$stderr" == *"ignoring assistant_env entry 'half_secret'"* ]]
}

@test "assistant_env prints nothing without the option or the options file" {
  load_lib options env
  run --separate-stderr assistant_env
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  set_options '{}'
  run --separate-stderr assistant_env
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "agy_env includes the assistant's variables" {
  load_lib options env
  set_options '{"assistant_env":["ASSISTANT_ONE=1"]}'
  run agy_env
  [[ "$output" == *"ASSISTANT_ONE=1"* ]]
  [[ "$output" == *"HOME=$HC_HOME"* ]]
}

@test "agy_once sends prompt via stream-json stdin, passes HA_AGY_MAX_TURNS, cleans up transcript, and maps turns/timeout" {
  load_lib options env
  mkdir -p "$HC_WORKSPACE" "$HC_HOME/.gemini/antigravity-cli/brain/11111111-2222-3333-4444-555555555555" \
           "$HC_HOME/.gemini/antigravity-cli/conversations"
  touch "$HC_HOME/.gemini/antigravity-cli/conversations/11111111-2222-3333-4444-555555555555.pb"
  set_options '{"job_model":"gemini-3.8-flash-high"}'
  export HC_LIMIT_BIN="$BATS_TEST_DIRNAME/../ha-antigravity/rootfs/usr/local/bin/ha-antigravity-limit"
  export HC_AGY_BIN="$BATS_TEST_TMPDIR/fake-agy"
  cat > "$HC_AGY_BIN" <<'EOF'
#!/usr/bin/env bash
read -r stdin_line
printf 'ARGS=%s\nENV_UNATT=%s ENV_TURNS=%s\nSTDIN=%s\n' "$*" "$HA_AGY_UNATTENDED" "$HA_AGY_MAX_TURNS" "$stdin_line"
printf '{"event":"init","conversation_id":"11111111-2222-3333-4444-555555555555"}\n'
if [[ "${FAKE_MODE:-ok}" == "turns" ]]; then
  : > "$HA_AGY_TURNS_MARK"
  exit 0
elif [[ "${FAKE_MODE:-ok}" == "timeout" ]]; then
  exit 3
fi
EOF
  chmod +x "$HC_AGY_BIN"
  printf 'hello secret prompt' > "$BATS_TEST_TMPDIR/p.txt"
  out="$BATS_TEST_TMPDIR/out.log"
  run agy_once house-check 30 12 "$BATS_TEST_TMPDIR/p.txt" "$out"
  [ "$status" -eq 0 ]
  grep -q 'ENV_UNATT=house-check ENV_TURNS=12' "$out"
  grep -q -- '--model gemini-3.8-flash-high' "$out"
  grep -q -- '--input-format stream-json' "$out"
  grep -q '"content":"hello secret prompt"' "$out"
  # Prompt is never on argv
  ! grep -q 'ARGS=.*hello secret prompt' "$out"
  # Transcript directory cleaned up
  [ ! -e "$HC_HOME/.gemini/antigravity-cli/brain/11111111-2222-3333-4444-555555555555" ]
  [ ! -e "$HC_HOME/.gemini/antigravity-cli/conversations/11111111-2222-3333-4444-555555555555.pb" ]

  # Turn limit marker returns 1 and writes max turns message
  : > "$out"
  run agy_once house-check 30 12 "$BATS_TEST_TMPDIR/p.txt" "$out" FAKE_MODE=turns
  [ "$status" -eq 1 ]
  grep -qi 'max turns' "$out"

  # Exit 3 (--print-timeout) normalizes to 124
  : > "$out"
  run agy_once house-check 30 12 "$BATS_TEST_TMPDIR/p.txt" "$out" FAKE_MODE=timeout
  [ "$status" -eq 124 ]
}
