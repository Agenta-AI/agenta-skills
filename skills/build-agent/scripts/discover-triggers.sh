#!/usr/bin/env bash
# Find provider trigger events that fit plain-language fragments (wraps find_triggers).
#
# Usage: discover-triggers.sh "<event 1>" "<event 2>" ...
#   e.g. "new github issue opened", "new telegram message received".
# Prints, per fragment: event_key, connection state, and a compact trigger_config schema hint.
#
# NOTE: this is for EVENT subscriptions only. A time-based schedule (cron) does NOT need this —
# go straight to create-schedule.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || { echo 'usage: discover-triggers.sh "<event>" ["<event>" ...]' >&2; exit 1; }

USE_CASES="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
RESP="$(agenta_post "/api/triggers/discover" "$(jq -n --argjson uc "$USE_CASES" '{use_cases:$uc}')")"

echo "$RESP" | jq -r '
  .capabilities[]? // .events[]? // empty |
  "• \(.use_case // .event_key // "?")\n    event_key: \(.event_key // .event.event_key // "?")\n    state: \(.connection.state // "?")\n    config_keys: \((.trigger_config.properties // .event.trigger_config.properties // {}) | keys | @json)"
  ' 2>/dev/null || true
echo "--- raw top-level keys (for shape debugging) ---"
jq -r 'keys|join(",")' <<<"$RESP" 2>/dev/null || { echo "DISCOVER-TRIGGERS FAILED:"; echo "$RESP" | head -c 800; }
