#!/usr/bin/env bash
# Find the Agenta gateway tools that fit plain-language capabilities (wraps find_capabilities).
#
# Usage: discover-tools.sh "<capability 1>" "<capability 2>" ...
#   One short action fragment per arg, e.g. "post a message to a slack channel".
#
# Prints, per capability: the ready-to-wire gateway tool (provider/integration/action/connection)
# and the connection state. Then a one-line readiness verdict. The printed `tool` object can be
# dropped straight into parameters.agent.tools (add a "connection" slug when state is ready).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[[ $# -ge 1 ]] || { echo 'usage: discover-tools.sh "<capability>" ["<capability>" ...]' >&2; exit 1; }

USE_CASES="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
RESP="$(agenta_post "/api/tools/discover" "$(jq -n --argjson uc "$USE_CASES" '{use_cases:$uc}')")"

echo "$RESP" | jq -r '
  .capabilities[] |
  "• \(.use_case)\n    tool: \((.tool | {type,provider,integration,action,connection}) | @json)\n    state: \(.connection.state // "?")\n    alternatives: \([.alternatives[]?.action] | @json)"
  ' 2>/dev/null || { echo "DISCOVER FAILED:"; echo "$RESP" | head -c 800; exit 1; }
echo "READY (all primary connections ready): $(jq -r '.ready' <<<"$RESP")"
NOTES="$(jq -r '.notes[]?' <<<"$RESP")"
[[ -n "$NOTES" ]] && { echo "NOTES:"; echo "$NOTES"; }
echo "CONNECTIONS:"; jq -r '.connections[] | "  \(.integration): \(.state)"' <<<"$RESP"
