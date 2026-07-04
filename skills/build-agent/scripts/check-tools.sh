#!/usr/bin/env bash
# Show which tools an invoke actually CALLED, whether each RETURNED a result, and a verdict for a
# terminal tool — from span-level ground truth.
#
# Usage: check-tools.sh <trace_id> [expected_terminal_tool]
#   [expected_terminal_tool]  a substring of the tool the run MUST end with, e.g. SEND_MESSAGE.
#
# WHY THE RESULT MATTERS, NOT JUST THE NAME: a tool's execute_tool span appears as soon as the
# tool is CALLED. The span carries the tool's RESULT in attributes.output.value ONLY once the
# tool actually returned. A gated WRITE that is dispatched but whose approval never resolves
# (common over a one-shot HTTP invoke) leaves an execute_tool span with NO output.value — i.e.
# "called" but not "completed". So the tool NAME being present is NOT proof of success; a
# non-empty output IS the reliable signal. For an external WRITE, the only certain proof of the
# side effect is reading it back (e.g. fetch the Slack channel history).
#
# `test-agent.sh`'s batch invoke already lists every tool called and each result's ok/ERROR
# straight from `data.outputs.messages` (see the Verify section of SKILL.md) — you usually don't
# need this script. Reach for it in two cases: a run that STOPPED SHORT (finished with no errors
# but never reached the final tool — check-tools confirms it truly never ran) or STALLED at an
# approval gate (`stop_reason == "paused"`), where the gated tool's call is in the invoke response
# but it has no result yet because the run paused before it executed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
TRACE_ID="${1:?usage: check-tools.sh <trace_id> [expected_terminal_tool]}"
EXPECT="${2:-}"
RESP="$(agenta_post "/api/spans/query" "$(jq -n --arg t "$TRACE_ID" \
  '{filtering:{conditions:[{field:"trace_id",operator:"is",value:$t}]}}')")"

echo "spans: $(jq -r '.count // (.spans|length) // 0' <<<"$RESP")"

# Per execute_tool span: short tool name + whether it RETURNED a result (non-empty output.value).
echo "tools (called -> did it return a result?):"
jq -r '.spans[]? | select((.span_name//.name//"")|test("execute_tool"))
  | (((.span_name//.name)|sub("execute_tool +";"")|sub("^mcp__agenta-tools__";""))) as $n
  | (((.attributes.output.value // .attributes.output // "")|tostring)|length) as $olen
  | "  \($n)\t\(if $olen>0 then "returned" else "NO RESULT (dispatched only — e.g. stalled at an approval gate)" end)"' \
  <<<"$RESP" 2>/dev/null || echo "  (could not parse spans)"

if [[ -n "$EXPECT" ]]; then
  RAN="$(jq -r --arg e "$EXPECT" '[.spans[]? | select((.span_name//.name//"")|test("execute_tool"))
    | select((.span_name//.name)|test($e))] | length' <<<"$RESP" 2>/dev/null)"
  OUT="$(jq -r --arg e "$EXPECT" '[.spans[]? | select((.span_name//.name//"")|test("execute_tool"))
    | select((.span_name//.name)|test($e))
    | ((.attributes.output.value // .attributes.output // "")|tostring)] | last // ""' <<<"$RESP" 2>/dev/null)"
  if [[ "${RAN:-0}" -eq 0 ]]; then
    echo "VERDICT: INCOMPLETE — terminal tool '$EXPECT' never ran (the agent stopped short; re-test with a blunt, numbered instruction)."
  elif [[ -z "$OUT" ]]; then
    echo "VERDICT: UNCONFIRMED — '$EXPECT' was dispatched but its span carries NO result."
    echo "  A gated WRITE whose approval never resolved looks exactly like this. Do NOT assume it was"
    echo "  delivered — confirm the side effect by reading it back (e.g. fetch the Slack channel history)."
  elif grep -qiE '"ok": ?false|not_in_channel|channel_not_found|invalid_auth|missing_scope|"error": ?"[^"]' <<<"$OUT"; then
    echo "VERDICT: FAILED — '$EXPECT' ran but returned an error: $(grep -oiE 'not_in_channel|channel_not_found|invalid_auth|missing_scope' <<<"$OUT" | head -1)"
  else
    echo "VERDICT: PASS — '$EXPECT' ran AND returned a result (its span has output)."
    echo "  For an external WRITE, reading the side effect back is still the only certain proof of delivery."
  fi
fi
exit 0
