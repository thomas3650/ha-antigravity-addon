load helpers

@test "ensure_layout creates the folders and ~/.gemini/config placeholders" {
  load_lib options layout
  set_options '{"session_name":"TestHouse"}'
  ensure_layout
  [ -d "$HC_HOME" ] && [ -d "$HC_HANDOVER" ] && [ -d "$HC_STATE" ] && [ -d "$HC_WORKSPACE" ]
  [ -d "$HC_STATUS" ] && [ -d "$HC_RESULTS" ] && [ -d "$HC_NOTES" ]
  [ -f "$HC_HOME/.gemini/config/.migrated" ]
  [ "$(cat "$HC_HOME/.gemini/config/hooks.json")" = "{}" ]
  [ "$(cat "$HC_HOME/.gemini/config/mcp_config.json")" = '{"mcpServers":{}}' ]
  [ "$(jq -r '.cliRemoteControlHostname' "$HC_HOME/.gemini/config/config.json")" = "TestHouse" ]
  [ -d "$HC_HOME/.gemini/config/projects" ]
  [ -d "$HC_HOME/.gemini/antigravity-cli" ]
}

@test "as root, workspace and ~/.gemini/config are locked read-only against the antigravity user" {
  [ "$(id -u)" -eq 0 ] || skip "needs root; runs in the container test"
  HC_USER=antigravity
  load_lib options layout
  d="$HC_DATA"
  while [ "$d" != / ]; do chmod o+x "$d"; d="$(dirname "$d")"; done
  ensure_layout
  [ "$(stat -c %U "$HC_WORKSPACE")" = "root" ]
  [ "$(stat -c %U "$HC_HANDOVER")" = "antigravity" ]
  [ "$(stat -c %U "$HC_RESULTS")" = "antigravity" ]
  [ "$(stat -c %a "$HC_STATE")" = "700" ]
  [ "$(stat -c %U:%a "$HC_STATUS")" = "root:755" ]
  [ "$(stat -c %U:%a "$HC_HOME")" = "root:755" ]
  [ "$(stat -c %U:%a "$HC_HOME/.gemini")" = "root:755" ]
  [ "$(stat -c %U:%a "$HC_HOME/.gemini/config")" = "root:755" ]
  [ "$(stat -c %U:%a "$HC_HOME/.gemini/config/hooks.json")" = "root:444" ]
  [ "$(stat -c %U:%a "$HC_HOME/.gemini/config/mcp_config.json")" = "root:444" ]
  [ "$(stat -c %U "$HC_HOME/.gemini/config/projects")" = "antigravity" ]
  [ "$(stat -c %U "$HC_HOME/.gemini/antigravity-cli")" = "antigravity" ]
  run runuser -u antigravity -- mv "$HC_HOME/.gemini" "$HC_HOME/.gemini.bak"
  [ "$status" -ne 0 ]
  run runuser -u antigravity -- touch "$HC_WORKSPACE/x"
  [ "$status" -ne 0 ]
  run runuser -u antigravity -- sh -c "echo '{}' > '$HC_HOME/.gemini/config/hooks.json'"
  [ "$status" -ne 0 ]
  run runuser -u antigravity -- rm -f "$HC_HOME/.gemini/config/hooks.json"
  [ "$status" -ne 0 ]
  run runuser -u antigravity -- touch "$HC_HOME/.gemini/config/plugins/evil"
  [ "$status" -ne 0 ]
  run runuser -u antigravity -- touch "$HC_HOME/.gemini/config/projects/ok"
  [ "$status" -eq 0 ]
  run runuser -u antigravity -- touch "$HC_HOME/.gemini/antigravity-cli/ok"
  [ "$status" -eq 0 ]
  run runuser -u antigravity -- touch "$HC_HOME/notes/ok"
  [ "$status" -eq 0 ]
  run runuser -u antigravity -- touch "$HC_HOME/.config/antigravity/ok"
  [ "$status" -eq 0 ]
  run runuser -u antigravity -- touch "$HC_HOME/.cache/ok"
  [ "$status" -eq 0 ]
}

@test "ensure_layout creates the jobs folder and the jobs' results folder" {
  load_lib layout
  ensure_layout
  [ -d "$HC_JOBS" ]
  [ -d "$HC_JOB_RESULTS" ]
  [ -d "$HC_JOBS/ended" ]
  [ -d "$HC_JOB_STATE" ]
}

@test "as root, the jobs folders are the antigravity user's, and a link in the results folder is not followed" {
  [ "$(id -u)" -eq 0 ] || skip "needs root; runs in the container test"
  HC_USER=antigravity
  load_lib layout
  d="$HC_DATA"
  while [ "$d" != / ]; do chmod o+x "$d"; d="$(dirname "$d")"; done
  ensure_layout
  [ "$(stat -c %U "$HC_JOBS")" = "antigravity" ]
  [ "$(stat -c %U "$HC_JOB_RESULTS")" = "antigravity" ]
  [ "$(stat -c %U "$HC_JOBS/ended")" = "antigravity" ]
  [ "$(stat -c %U "$HC_JOB_STATE")" = "root" ]
  rm -r "$HC_JOB_RESULTS"
  mkdir -p "$BATS_TEST_TMPDIR/rootdir"
  ln -s "$BATS_TEST_TMPDIR/rootdir" "$HC_JOB_RESULTS"
  chown -h antigravity:antigravity "$HC_JOB_RESULTS"
  ensure_layout
  [ "$(stat -c %U "$BATS_TEST_TMPDIR/rootdir")" = "root" ]
}
