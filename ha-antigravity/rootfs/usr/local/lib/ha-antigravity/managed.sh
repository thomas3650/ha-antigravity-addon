# Managed settings: a file .agents/managed-settings.json in the working
# folder becomes Antigravity CLI's session settings (--settings), which the
# antigravity user cannot write. Its deny rules and toolPermission baseline
# are also seeded into ~/.gemini/antigravity-cli/settings.json as defense in
# depth. A file that is not exactly one JSON object never replaces a good one.
# The last good copy is kept under /data, because /etc is new after every
# image update.

_managed_source_ok() {
  local src="$1" real_dir real_ws
  [[ -f "$src" && ! -L "$src" ]] || return 1
  real_dir="$(cd -P "$(dirname "$src")" 2>/dev/null && pwd -P)" || return 1
  real_ws="$(cd -P "$HC_WORKSPACE" 2>/dev/null && pwd -P)" || return 1
  [[ "$real_dir" == "$real_ws/.agents" ]] || return 1
  jq -es 'length == 1 and (.[0] | type == "object")' "$src" >/dev/null 2>&1
}

# Seeds baseline deny rules and toolPermission into the CLI's global
# settings.json without ever reading user-writable files as root (prevents
# symlink TOCTOU against root-only files like /data/options.json) and without
# passing file contents on jq's command line.
_seed_cli_settings() {
  local managed="$1" target="$HC_HOME/.gemini/antigravity-cli/settings.json"
  local cur_tmp merged_tmp
  [[ -f "$managed" && ! -L "$managed" ]] || return 0
  mkdir -p "$HC_STATE"
  cur_tmp="$(umask 077; mktemp "$HC_STATE/.cli-settings-cur.XXXXXX")" || return 0
  merged_tmp="$(umask 077; mktemp "$HC_STATE/.cli-settings-new.XXXXXX")" || { rm -f "$cur_tmp"; return 0; }
  printf '{}\n' > "$cur_tmp"
  if [[ "$(id -u)" == 0 ]] && declare -F as_antigravity >/dev/null 2>&1; then
    # Read as the antigravity user with a size and time cap, refusing symlinks.
    # shellcheck disable=SC2016
    if as_antigravity timeout 5 sh -c '[ -f "$1" ] && [ ! -L "$1" ] && head -c 65536 -- "$1"' sh "$target" \
       > "$cur_tmp.raw" 2>/dev/null \
       && jq -es 'length == 1 and (.[0] | type == "object")' "$cur_tmp.raw" >/dev/null 2>&1; then
      mv -f "$cur_tmp.raw" "$cur_tmp"
    else
      rm -f "$cur_tmp.raw"
    fi
  elif [[ -f "$target" && ! -L "$target" ]]; then
    if head -c 65536 -- "$target" > "$cur_tmp.raw" 2>/dev/null \
       && jq -es 'length == 1 and (.[0] | type == "object")' "$cur_tmp.raw" >/dev/null 2>&1; then
      mv -f "$cur_tmp.raw" "$cur_tmp"
    else
      rm -f "$cur_tmp.raw"
    fi
  fi
  # shellcheck disable=SC2016
  if jq -cn --slurpfile cur "$cur_tmp" --slurpfile m "$managed" '
    ($cur[0] // {})
    | .toolPermission = ($m[0].toolPermission // "request-review")
    | .enableTerminalSandbox = ($m[0].enableTerminalSandbox // false)
    | .permissions = ((.permissions // {}) + {deny: ($m[0].permissions.deny // ["command(*)"])})
  ' > "$merged_tmp" 2>/dev/null; then
    if [[ "$(id -u)" == 0 ]] && declare -F as_antigravity >/dev/null 2>&1; then
      # shellcheck disable=SC2016
      as_antigravity sh -c 'mkdir -p "$(dirname "$1")" && [ ! -L "$1" ] && umask 077 && cat > "$1.new" && mv -f "$1.new" "$1"' \
        sh "$target" <"$merged_tmp" >/dev/null 2>&1 || true
    else
      mkdir -p "$(dirname "$target")"
      if [[ ! -L "$target" ]]; then
        cp "$merged_tmp" "$target.new" && mv -f "$target.new" "$target"
      fi
    fi
  fi
  rm -f "$cur_tmp" "$cur_tmp.raw" "$merged_tmp"
}

install_managed_settings() {
  local src="$HC_WORKSPACE/.agents/managed-settings.json"
  local keep="$HC_STATUS/managed-settings.json"
  local dst="$HC_MANAGED_DIR/settings.json"
  mkdir -p "$HC_STATUS"
  if [[ ! -e "$src" && ! -L "$src" ]]; then
    if [[ -f "$keep" ]]; then
      rm -f "$keep"
      log "managed settings: none in the working folder; removed"
    fi
  elif _managed_source_ok "$src"; then
    if ! { cp "$src" "$keep.new" && mv "$keep.new" "$keep"; }; then
      log "managed settings: could not keep a copy; keeping the last good copy"
    fi
  else
    log "managed settings: the file in the working folder is not one JSON object in a real file; keeping the last good copy"
  fi
  if [[ -f "$keep" ]]; then
    mkdir -p "$HC_MANAGED_DIR"
    if ! { cp "$keep" "$dst.new" && chmod 644 "$dst.new" && mv "$dst.new" "$dst"; }; then
      log "managed settings: could not install the file"
    else
      _seed_cli_settings "$dst"
    fi
  else
    rm -f "$dst"
  fi
  return 0
}
