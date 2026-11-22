# Folders under /data and who owns them:
#   workspace  root, read-only for the antigravity user
#   handover   antigravity user
#   results    antigravity user, and its jobs folder
#   jobs       antigravity user (the job files the chat writes), and its .requests
#   home       root:root 0755 so the antigravity user cannot rename ~/.gemini;
#              only explicit subdirectories (notes, tool-record, .cache, .config,
#              .ssh, .npm, .local, .gemini/antigravity-cli, .gemini/config/projects)
#              are owned by the antigravity user; ~/.gemini and ~/.gemini/config/*
#              stay root-owned read-only placeholders so the user cannot add or
#              shadow global hooks, MCP servers, plugins, agents, skills, or rules
#   status     root, readable by the antigravity user; its jobs/ holds each job's
#              public copy of its state, for the chat's job_status
#   state, repo, options file   root only

_root_dir() {
  local d="$1"
  [[ -L "$d" ]] && rm -f "$d"
  mkdir -p "$d"
}

_user_dir() {
  local d="$1"
  [[ -L "$d" ]] && rm -f "$d"
  mkdir -p "$d"
  if [[ "$(id -u)" == 0 ]]; then
    chown "$HC_USER:$HC_USER" "$d"
  fi
}

ensure_layout() {
  local gdir="$HC_HOME/.gemini" cdir="$HC_HOME/.gemini/config" sname="Home"
  if declare -F opt >/dev/null 2>&1; then
    sname="$(opt '.session_name' 'Home')"
  fi

  _root_dir "$HC_HOME"
  _root_dir "$HC_STATE"
  _root_dir "$HC_STATUS"
  _root_dir "$(dirname "$HC_WORKSPACE")"
  _root_dir "$HC_WORKSPACE"
  _root_dir "$HC_JOB_STATE"
  _root_dir "$gdir"
  _root_dir "$cdir"
  local d f
  for d in "$cdir/plugins" "$cdir/agents" "$cdir/skills" "$cdir/rules"; do
    [[ -L "$d" ]] && rm -f "$d"
    mkdir -p "$d"
    [[ "$(id -u)" == 0 ]] && chmod 755 "$d" 2>/dev/null || true
  done

  if [[ "$(id -u)" == 0 ]]; then
    chmod 755 "$HC_HOME" "$gdir" "$cdir" 2>/dev/null || true
  fi

  # Root-owned global config placeholders so agy cannot load user-injected
  # global hooks, MCP servers, plugins, agents, skills, or rules.
  for f in .migrated hooks.json mcp_config.json config.json skills.json plugins.json rules.json AGENTS.md GEMINI.md; do
    rm -f "$cdir/$f"
  done
  : > "$cdir/.migrated"
  printf '{}\n' > "$cdir/hooks.json"
  printf '{"mcpServers":{}}\n' > "$cdir/mcp_config.json"
  jq -cn --arg n "$sname" '{cliRemoteControlHostname:$n}' > "$cdir/config.json"
  printf '{}\n' > "$cdir/skills.json"
  printf '{}\n' > "$cdir/plugins.json"
  printf '{}\n' > "$cdir/rules.json"
  : > "$cdir/AGENTS.md"
  : > "$cdir/GEMINI.md"

  # User-owned top-level writable directories (never chown -R).
  _user_dir "$HC_HANDOVER"
  _user_dir "$HC_RESULTS"
  _user_dir "$HC_JOBS"
  _user_dir "$HC_NOTES"
  _user_dir "$HC_HOME/tool-record"
  _user_dir "$HC_HOME/.cache"
  _user_dir "$HC_HOME/.config"
  _user_dir "$HC_HOME/.ssh"
  _user_dir "$HC_HOME/.npm"
  _user_dir "$HC_HOME/.local"
  _user_dir "$cdir/projects"
  _user_dir "$gdir/antigravity-cli"

  if [[ "$(id -u)" != 0 ]]; then
    mkdir -p "$HC_HOME/.config/antigravity" "$HC_JOB_RESULTS" "$HC_JOBS/ended" "$HC_JOB_REQUESTS"
    return 0
  fi

  # Lock /data/home, ~/.gemini and ~/.gemini/config as root-owned read-only;
  # antigravity cannot rename ~/.gemini or write into ~/.gemini/config.
  chown root:root "$HC_HOME" "$gdir" "$cdir"
  chmod 755 "$HC_HOME" "$gdir" "$cdir"
  for d in "$cdir/plugins" "$cdir/agents" "$cdir/skills" "$cdir/rules"; do
    chown root:root "$d"
    chmod 555 "$d"
  done
  for f in .migrated hooks.json mcp_config.json config.json skills.json plugins.json rules.json AGENTS.md GEMINI.md; do
    chown root:root "$cdir/$f"
    chmod 444 "$cdir/$f"
  done

  # Subdirectories inside user-owned folders are created as the antigravity
  # user so root never follows a symlink planted there.
  runuser -u "$HC_USER" -- mkdir -p \
    "$HC_HOME/.config/antigravity" "$HC_JOB_RESULTS" "$HC_JOBS/ended" "$HC_JOB_REQUESTS" \
    </dev/null 2>/dev/null || true

  chown -R root:root "$(dirname "$HC_WORKSPACE")" "$HC_STATE" "$HC_STATUS"
  chmod -R u=rwX,go=rX "$(dirname "$HC_WORKSPACE")" "$HC_STATUS"
  chmod 700 "$HC_STATE"
  if [[ -d "$HC_REPO" && ! -L "$HC_REPO" ]]; then
    chown -R root:root "$HC_REPO"
    chmod 700 "$HC_REPO"
  fi
  [[ -f "$HC_OPTIONS" && ! -L "$HC_OPTIONS" ]] && chmod 600 "$HC_OPTIONS"
  return 0
}
