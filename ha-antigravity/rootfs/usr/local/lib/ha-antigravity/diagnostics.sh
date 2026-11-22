# Start-up diagnostics. Informational: nothing here stops the add-on.
run_diagnostics() {
  local meminfo="${HC_MEMINFO:-/proc/meminfo}" total avail disk version
  if [[ -r "$meminfo" ]]; then
    total="$(awk '/^MemTotal:/ {print int($2/1024)}' "$meminfo")"
    avail="$(awk '/^MemAvailable:/ {print int($2/1024)}' "$meminfo")"
    log "diagnostics: memory: ${avail} MB available of ${total} MB"
    (( avail < 512 )) && log "diagnostics: WARNING: less than 512 MB of memory available"
  fi
  disk="$(df -Pm "$HC_DATA" 2>/dev/null | awk 'NR==2 {print $4}')"
  [[ -n "$disk" ]] && log "diagnostics: disk: ${disk} MB free in $HC_DATA"
  if touch "$HC_DATA/.write-test" 2>/dev/null; then
    rm -f "$HC_DATA/.write-test"
    log "diagnostics: /data is writable"
  else
    log "diagnostics: WARNING: /data is not writable"
  fi
  if version="$(as_antigravity "${HC_AGY_BIN:-agy}" --version 2>/dev/null)"; then
    log "diagnostics: Antigravity CLI $version"
  else
    log "diagnostics: WARNING: Antigravity CLI did not run"
  fi
  if [[ -z "${HC_OFFLINE:-}" ]]; then
    if [[ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' https://antigravity.google)" =~ ^[2345] ]]; then
      log "diagnostics: network reachable"
    else
      log "diagnostics: WARNING: antigravity.google is not reachable"
    fi
  fi
  return 0
}
