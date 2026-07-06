#!/usr/bin/env bash
# Find provider trigger events that fit plain-language fragments (wraps find_triggers).
#
# Usage: discover-triggers.sh "<event 1>" "<event 2>" ...
#   e.g. "new github issue opened", "new telegram message received".
# Prints, per fragment: the MATCHED event_key and its "fires_on" description, connection
# state, required trigger_config fields, and any ALTERNATIVES with their own descriptions.
#
# The match is a keyword search, not a semantic oracle: it can return a plausible-looking
# event_key (right integration, right connection state) whose "fires_on" description does
# NOT actually match what you asked for (e.g. "new issue opened" matching an "artifact
# created" event purely on the shared word "created"). ALWAYS read fires_on for the
# MATCHED event — and check ALTERNATIVES — before wiring anything into create-subscription.sh.
# If nothing in MATCHED or ALTERNATIVES actually fires on the requested event, this
# integration does not support it yet: stop and tell the user, don't wire up the closest
# keyword hit.
#
# NOTE: this is for EVENT subscriptions only. A time-based schedule (cron) does NOT need this —
# go straight to create-schedule.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || { echo 'usage: discover-triggers.sh "<event>" ["<event>" ...]' >&2; exit 1; }

USE_CASES="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
RESP="$(agenta_post "/api/triggers/discover" "$(jq -n --argjson uc "$USE_CASES" '{use_cases:$uc}')")"

echo "$RESP" | jq -r '
  def firstline: (. // "") | split("\n")[0] | gsub("^\\s+|\\s+$";"");
  .capabilities[]? // .events[]? // empty |
  if (.event // .event_key // null) == null then
    "• \(.use_case // "?")",
    "    NO MATCH: \(.note // "no trigger event matched this use case")"
  else
    "• \(.use_case // .event.event_key // .event_key // "?")",
    "    MATCHED: \(.event.event_key // .event_key // "?")",
    "    fires_on: \(.event.description // .description // "" | firstline)",
    "    state: \(.connection.state // "?")  connection: \(.connection.slug // .connection.id // "?")",
    "    config_required: \((.event.trigger_config.required // .trigger_config.required // []) | @json)",
    (if ((.alternatives // []) | length) > 0 then
       "    ALTERNATIVES (check these if MATCHED above does not really fit):",
       (.alternatives[] | "      - \(.event_key // "?"): \(.description // "" | firstline)")
     else empty end)
  end
  ' 2>/dev/null || true
echo "--- raw top-level keys (for shape debugging) ---"
jq -r 'keys|join(",")' <<<"$RESP" 2>/dev/null || { echo "DISCOVER-TRIGGERS FAILED:"; echo "$RESP" | head -c 800; }
