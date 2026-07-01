#!/usr/bin/env bash
# Show which tools an invoke actually CALLED and whether the run hit any tool errors
# (span-level ground truth).
#
# Usage: check-tools.sh <trace_id> [expected_terminal_tool]
#   [expected_terminal_tool]  a substring of the tool the run MUST end with, e.g. SEND_MESSAGE.
#     If given, prints PASS only when that tool actually executed.
#
# Use this to verify a MULTI-TOOL agent: such runs can return an empty/partial invoke OUTPUT
# even when every tool call succeeded (a known runner behavior — see BUILD-AGENT.md). They can
# also STOP SHORT — finish with no errors but never reach the final tool. "error markers: none"
# is NOT proof of success; the terminal tool being in the executed list is. The tool spans are
# the truth.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TRACE_ID="${1:?usage: check-tools.sh <trace_id> [expected_terminal_tool]}"
EXPECT="${2:-}"
RESP="$(agenta_post "/api/spans/query" "$(jq -n --arg t "$TRACE_ID" \
  '{filtering:{conditions:[{field:"trace_id",operator:"is",value:$t}]}}')")"

echo "spans: $(jq -r '.count // 0' <<<"$RESP")"
EXECUTED="$(jq -r '.spans[] | (.span_name//.name//"") | select(test("execute_tool")) | sub("execute_tool +";"")' <<<"$RESP" 2>/dev/null)"
echo "tools executed:"
if [[ -n "$EXECUTED" ]]; then printf '  %s\n' $EXECUTED; else echo "  (none — the run made no tool calls)"; fi

set +e +o pipefail
OK_COUNT="$(grep -o -E '"ok\\?": ?true' <<<"$RESP" | wc -l | tr -d ' ')"
ERRS="$(grep -o -E 'not_in_channel|channel_not_found|invalid_auth|missing_scope|"ok\\?": ?false' <<<"$RESP" | sort | uniq -c | tr '\n' ';')"
echo "tool ok:true markers: ${OK_COUNT:-0}"
echo "error markers: ${ERRS:-none}"
if [[ -n "$EXPECT" ]]; then
  if grep -qF "$EXPECT" <<<"$EXECUTED"; then
    echo "VERDICT: PASS — terminal tool '$EXPECT' executed"
  else
    echo "VERDICT: INCOMPLETE — terminal tool '$EXPECT' never ran (the agent stopped short; re-test with a blunt, numbered instruction)"
  fi
fi
exit 0
