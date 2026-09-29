#!/usr/bin/env bash
# Dedup/resumability icin yerel durum dosyasi (.watch-tmp/incident-map.json).
# signature -> {jira_key, branch, pr_id, pr_url, status, created_at, updated_at}
# status ilerleyisi: jira_created -> fix_committed -> pushed -> pr_created

STATE_FILE="${TMP_DIR}/incident-map.json"

state_init() {
    [ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
}

# state_has SIGNATURE
state_has() {
    jq -e --arg k "$1" 'has($k)' "$STATE_FILE" >/dev/null 2>&1
}

# state_get SIGNATURE FIELD
state_get() {
    jq -r --arg k "$1" --arg f "$2" '.[$k][$f] // empty' "$STATE_FILE"
}

# state_set SIGNATURE JSON_PATCH_OBJECT
state_set() {
    local sig="$1" patch="$2" tmp
    tmp="$(mktemp "${TMP_DIR}/state.XXXXXX")"
    jq --arg k "$sig" --argjson patch "$patch" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.[$k] = ((.[$k] // {created_at: $now}) + $patch + {updated_at: $now})' \
       "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
