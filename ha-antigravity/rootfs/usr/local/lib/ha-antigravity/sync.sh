# Workspace sync: fetch the repo set in repo_url into HC_REPO, checking out
# only the folder repo_path names (default assistant) plus any validated
# relative paths listed in <repo_path>/sync-includes.json, and publish the
# assembled folder as HC_WORKSPACE. Never fatal: on any failure the previous
# workspace copy stays in place.

_sync_status() {
  mkdir -p "$HC_STATUS"
  printf '%s\n' "$1" > "$HC_STATUS/last_sync_status"
}

_key_text() {
  local raw="$1" body
  if [[ "$raw" =~ ^[[:space:]]*(-----BEGIN[A-Z\ ]+-----)(.*)(-----END[A-Z\ ]+-----)[[:space:]]*$ ]]; then
    body="${BASH_REMATCH[2]//[[:space:]]/}"
    printf '%s\n' "${BASH_REMATCH[1]}"
    while [[ -n "$body" ]]; do
      printf '%s\n' "${body:0:70}"
      body="${body:70}"
    done
    printf '%s\n' "${BASH_REMATCH[3]}"
  else
    printf '%s\n' "$raw"
  fi
}

_write_deploy_key() {
  local raw key="$HC_STATE/deploy_key"
  raw="$(opt '.deploy_key')"
  rm -f "$key"
  [[ -n "$raw" ]] || return 1
  mkdir -p "$HC_STATE"
  ( umask 077
    if [[ "$raw" == *"BEGIN"* ]]; then
      _key_text "$raw" > "$key"
    else
      printf '%s' "$raw" | base64 -d > "$key" 2>/dev/null || true
    fi )
  if ! ssh-keygen -y -P '' -f "$key" </dev/null >/dev/null 2>&1; then
    rm -f "$key"
    return 2
  fi
}

: "${HC_KNOWN_HOSTS:=/usr/share/ha-antigravity/known_hosts}"
_git_ssh_command() {
  printf '%s' "ssh -i $HC_STATE/deploy_key -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=accept-new -o 'UserKnownHostsFile=$HC_STATE/known_hosts $HC_KNOWN_HOSTS'"
}

# True when $1 is a safe relative path (strict character allowlist, no leading/
# trailing/double slash, no ".", "..", or leading "-" segment, no glob chars).
_rel_path_ok() {
  local p="$1" seg
  local -a segs=()
  p="${p%/}"
  [[ -n "$p" && "$p" != /* && "$p" != *"//"* ]] || return 1
  [[ "$p" =~ ^[A-Za-z0-9._/-]+$ ]] || return 1
  IFS=/ read -r -a segs <<<"$p"
  (( ${#segs[@]} > 0 )) || return 1
  for seg in "${segs[@]}"; do
    [[ -n "$seg" && "$seg" != . && "$seg" != .. && "$seg" != -* ]] || return 1
  done
  return 0
}

_repo_path() {
  local p
  p="$(opt '.repo_path')"
  [[ -n "$p" ]] || p=assistant
  p="${p%/}"
  _rel_path_ok "$p" || return 1
  printf '%s' "$p"
}

# Validates <repo_path>/sync-includes.json if present and prints "from<TAB>to"
# lines. Returns 0 when absent or valid, 1 when malformed or unsafe.
_read_sync_includes() {
  local inc="$HC_REPO/$1/sync-includes.json" from to
  [[ ! -e "$inc" && ! -L "$inc" ]] && return 0
  [[ -f "$inc" && ! -L "$inc" ]] || return 1
  jq -e '
    type == "array"
    and all(.[]; type == "object"
                 and (keys | sort) == ["from", "to"]
                 and (.from | type == "string" and test("\\A[A-Za-z0-9._/-]+\\z"))
                 and (.to | type == "string" and test("\\A[A-Za-z0-9._/-]+\\z")))
  ' "$inc" >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r from to; do
    _rel_path_ok "$from" && _rel_path_ok "$to" || return 1
    printf '%s\t%s\n' "${from%/}" "${to%/}"
  done < <(jq -r '.[] | "\(.from)\t\(.to)"' "$inc" 2>/dev/null)
}

_fetch_repo() {
  local url="$1" path="$2"
  if [[ -d "$HC_REPO/.git" ]]; then
    git -C "$HC_REPO" remote set-url origin "$url" \
      && git -C "$HC_REPO" sparse-checkout set --no-cone -- "$path" \
      && git -C "$HC_REPO" fetch --quiet --depth 1 origin HEAD \
      && git -C "$HC_REPO" reset --quiet --hard FETCH_HEAD
  else
    rm -rf "$HC_REPO"
    git clone --quiet --depth 1 --filter=blob:none --sparse "$url" "$HC_REPO" \
      && git -C "$HC_REPO" sparse-checkout set --no-cone -- "$path"
  fi
}

# Verifies no component along $1/$2 (inside staged workspace $1) is a symlink.
_dst_no_symlinks() {
  local rel="$2" cur="$1" seg
  local -a segs=()
  IFS=/ read -r -a segs <<<"$rel"
  for seg in "${segs[@]}"; do
    cur="$cur/$seg"
    [[ ! -L "$cur" ]] || return 1
  done
  return 0
}

_publish_workspace() {
  local path="$1" src="$HC_REPO/$1" new="$HC_WORKSPACE.new" old="$HC_WORKSPACE.old"
  local inc_lines="" from to
  local -a extra_sparse=()
  [[ -d "$src" ]] || return 1
  if ! inc_lines="$(_read_sync_includes "$path")"; then
    log "sync: sync-includes.json is malformed or unsafe; keeping the previous workspace"
    return 2
  fi
  if [[ -n "$inc_lines" ]]; then
    while IFS=$'\t' read -r from _to; do
      [[ -n "$from" ]] && extra_sparse+=("$from")
    done <<<"$inc_lines"
    git -C "$HC_REPO" sparse-checkout set --no-cone -- "$path" "${extra_sparse[@]}" </dev/null 2>/dev/null || return 2
  fi
  rm -rf "$new" "$old"
  cp -R "$src" "$new"
  if [[ -n "$inc_lines" ]]; then
    while IFS=$'\t' read -r from to; do
      [[ -n "$from" ]] || continue
      local fsrc="$HC_REPO/$from" fdst="$new/$to"
      if [[ ! -e "$fsrc" || -L "$fsrc" ]]; then
        log "sync: include '$from' is missing or a symlink; keeping the previous workspace"
        rm -rf "$new"
        return 2
      fi
      if [[ -d "$fsrc" ]] && find "$fsrc" -type l | grep -q .; then
        log "sync: include '$from' contains a symlink; keeping the previous workspace"
        rm -rf "$new"
        return 2
      fi
      if ! _dst_no_symlinks "$new" "$to"; then
        log "sync: include target '$to' traverses a symlink; keeping the previous workspace"
        rm -rf "$new"
        return 2
      fi
      mkdir -p "$(dirname "$fdst")"
      rm -rf "$fdst"
      cp -R "$fsrc" "$fdst"
    done <<<"$inc_lines"
  fi
  [[ -d "$HC_WORKSPACE" ]] && mv "$HC_WORKSPACE" "$old"
  mv "$new" "$HC_WORKSPACE"
  rm -rf "$old"
}

# shellcheck disable=SC2034
HC_SYNC_RESULT=""
sync_workspace() {
  local url rc path pub_rc=0
  HC_SYNC_RESULT=kept
  url="$(opt '.repo_url')"
  mkdir -p "$HC_WORKSPACE"
  if [[ -z "$url" ]]; then
    log "sync: no repo_url set; the workspace is left as it is"
    _sync_status none
    HC_SYNC_RESULT=none
    return 0
  fi
  if ! path="$(_repo_path)"; then
    log "sync: repo_path is not a relative path inside the repo; keeping the previous workspace"
    _sync_status "failed: repo_path is not valid"
    return 0
  fi
  if [[ "$url" != file://* ]]; then
    _write_deploy_key && rc=0 || rc=$?
    if (( rc == 1 )); then
      log "sync: the deploy key is empty; keeping the previous workspace"
      _sync_status "failed: deploy key is empty"
      return 0
    elif (( rc == 2 )); then
      log "sync: the deploy key is not a valid private key without a passphrase; keeping the previous workspace"
      _sync_status "failed: deploy key is not valid"
      return 0
    fi
    if [[ -f "$HC_STATE/known_hosts" ]]; then
      ssh-keygen -R github.com -f "$HC_STATE/known_hosts" >/dev/null 2>&1 || true
      rm -f "$HC_STATE/known_hosts.old"
    fi
    GIT_SSH_COMMAND="$(_git_ssh_command)"
    export GIT_SSH_COMMAND
  fi
  if ! _fetch_repo "$url" "$path" </dev/null 2>/dev/null; then
    log "sync: could not fetch the repo; keeping the previous workspace"
    _sync_status "failed: fetch"
    return 0
  fi
  local commit published="$HC_STATE/published"
  commit="$(git -C "$HC_REPO" rev-parse HEAD 2>/dev/null)" || commit=""
  if [[ -n "$commit" && -f "$published" && "$(cat "$published")" == "$commit $path" \
        && -n "$(ls -A "$HC_WORKSPACE" 2>/dev/null)" ]]; then
    date -u +%Y-%m-%dT%H:%M:%SZ > "$HC_STATUS/last_sync"
    _sync_status ok
    # shellcheck disable=SC2034
    HC_SYNC_RESULT=same
    log "sync: no new commit; the workspace is left as it is"
    return 0
  fi
  _publish_workspace "$path" || pub_rc=$?
  if (( pub_rc == 1 )); then
    log "sync: the repo has no $path folder; keeping the previous workspace"
    _sync_status "failed: no $path folder"
    return 0
  elif (( pub_rc != 0 )); then
    _sync_status "failed: invalid sync-includes"
    return 0
  fi
  [[ -n "$commit" ]] && printf '%s\n' "$commit $path" > "$published"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$HC_STATUS/last_sync"
  _sync_status ok
  # shellcheck disable=SC2034
  HC_SYNC_RESULT=ok
  log "sync: workspace updated"
}
