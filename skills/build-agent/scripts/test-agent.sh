#!/usr/bin/env bash
# Invoke an agent over a NON-STREAMING (batch) invoke AND verify the run, in one call.
#
# Usage: test-agent.sh <application_id> <config.json> "<message>"
#   Inlines the full config on every invoke. NOTE (open item, unrelated to the response shape
#   below): this script hits the low-level agent-service endpoint, which does NOT hydrate a
#   committed reference, so the config must be carried inline — that inlining is a lab artifact.
#   The product API invoke path loads a committed reference server-side (bare-reference invoke is
#   the product feature); this script still does not use that path. See the settled invoke
#   contract in `docs/designs/invoke-negotiations/specs.md` (the `agenta` repo) for the endpoint,
#   auth, and body shape this script relies on — all unchanged by that contract.
#
# Why batch is enough now: a non-streaming invoke (Accept: application/json) returns the run's
# FULL real turn, not just the final assistant text — `data.outputs.messages` carries assistant
# text AND a `role: "tool"` entry for every tool_call (`tool_call_id`, `tool_name`, `input`) and
# tool_result (`content`, `is_error`), in stream order, plus `stop_reason` and — only when the run
# paused on an approval gate — `pending_interaction`. So one batch call is self-describing: you
# do not need a streaming invoke or the trace to see what happened. (Streaming still exists and
# is unchanged; this script just no longer needs it to see the ordered tool turn.)
#
# Default headers/flags: this script sends no extra headers, so the response carries the
# defaults — full transcript (`x-ag-messages-transcript: full`), resolved workflow embeds
# (`x-ag-workflow-embeds: resolve`). Body `flags` (`stream`/`trim`/`force`/`resolve`) always win
# over header sugar if you add them. `x-ag-session-control: force` (session take-over) is a
# recognized header but returns 406 today — nothing to wire against yet.
#
# Prints:
#   OUTPUT:   the last assistant message's content (from `data.outputs.messages`)
#   TOOLS:    the ordered `role: "tool"` entries — each call's `tool_name`, each result's
#             ok/ERROR (from `is_error`) — with a (calls/results) count. This is the reliable
#             "did it reach the terminal tool, and did that tool return ok" signal, straight from
#             the invoke response.
#   APPROVAL: when `stop_reason == "paused"`, the gated tool from `pending_interaction.tool`. The
#             run stopped there; that tool's call is in TOOLS but it has no matching result yet —
#             the approval has to resolve (or the session continue) before it does. Confirm a WRITE
#             that must have completed with `check-tools.sh <trace> <TOOL>`.
#   RESOLVED: harness / model / provider / connection.mode the run actually executed with
#   TRACE:    the trace id (inspect with: agenta_get /api/simple/traces/<id>)
# Exits non-zero if the invoke HTTP status is not 200.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP_ID="${1:?usage: test-agent.sh <application_id> <config.json> \"<message>\"}"
CONFIG_FILE="${2:?usage: test-agent.sh <application_id> <config.json> \"<message>\"}"
MESSAGE="${3:?usage: test-agent.sh <application_id> <config.json> \"<message>\"}"

AGENT_CONFIG="$(cat "$CONFIG_FILE")"
BODY="$(jq -n --arg app "$APP_ID" --arg msg "$MESSAGE" --argjson agent "$AGENT_CONFIG" '
  {data: {inputs: {messages: [{role: "user", content: $msg}]}, parameters: {agent: $agent}},
   references: {application: {id: $app}}}')"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
RESP_FILE="$TMP/resp.json"; HDR="$TMP/headers"

# Accept: application/json negotiates the non-streaming (batch) invoke — one JSON object back,
# not an event stream.
curl -s -X POST "$AGENTA_HOST/services/agent/v0/invoke" \
  -H "Authorization: ApiKey $AGENTA_API_KEY" -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  --max-time 600 -D "$HDR" -d "$BODY" > "$RESP_FILE"

CODE="$(awk 'toupper($1) ~ /^HTTP/ {c=$2} END{print c}' "$HDR")"
TRACE_ID="$(awk 'tolower($1)=="x-ag-trace-id:" {print $2}' "$HDR" | tr -d '\r')"

# OUTPUT: the last assistant message's content. Genuinely empty when the run ends on a tool
# call with no closing reply — that is not a parsing failure, read TOOLS for what happened.
OUTPUT="$(jq -r '[.data.outputs.messages[]? | select(.role=="assistant")] | last | .content // ""' "$RESP_FILE" 2>/dev/null)"

# TOOLS: every role:"tool" entry in stream order — a call prints its tool_name, a result prints
# ok/ERROR from is_error. Distinguish call vs result by which field is present.
TOOLS="$(jq -r '
  [.data.outputs.messages[]? | select(.role=="tool")
    | if has("tool_name") then (.tool_name // "?")
      else (if .is_error == true then "ERROR" else "ok" end)
      end
  ] | join(" -> ")' "$RESP_FILE" 2>/dev/null)"
N_CALLS="$(jq -r '[.data.outputs.messages[]? | select(.role=="tool") | select(has("tool_name"))] | length' "$RESP_FILE" 2>/dev/null)"
N_RESULTS="$(jq -r '[.data.outputs.messages[]? | select(.role=="tool") | select(has("is_error"))] | length' "$RESP_FILE" 2>/dev/null)"

STOP_REASON="$(jq -r '.data.outputs.stop_reason // empty' "$RESP_FILE" 2>/dev/null)"
PENDING_TOOL="$(jq -r '.data.outputs.pending_interaction.tool // empty' "$RESP_FILE" 2>/dev/null)"

echo "OUTPUT: ${OUTPUT:-<no assistant text — the run ended on a tool-call/approval turn; see TOOLS>}"
if [[ -n "$TOOLS" ]]; then
  echo "TOOLS: $TOOLS  (${N_CALLS:-0} calls, ${N_RESULTS:-0} results)"
else
  echo "TOOLS: (none — the run made no tool calls)"
fi
[[ "$STOP_REASON" == "paused" ]] && echo "APPROVAL: paused on ${PENDING_TOOL:-<tool name not reported>}"

if [[ -n "$TRACE_ID" ]]; then
  # Traces flush asynchronously; retry a few times before giving up.
  RESOLVED=""
  for _ in 1 2 3 4 5; do
    TRACE="$(agenta_get "/api/simple/traces/$TRACE_ID")"
    RESOLVED="$(jq -r 'first(.. | objects | select(has("harness") and has("llm")))
      | "harness=\(.harness.kind // "?") model=\(.llm.model // "?") provider=\(.llm.provider // "?") connection=\(.llm.connection.mode // "?")"' <<<"$TRACE" 2>/dev/null)"
    [[ -n "$RESOLVED" ]] && break
    sleep 2
  done
  echo "RESOLVED: ${RESOLVED:-<trace not flushed yet; re-check: agenta_get /api/simple/traces/$TRACE_ID>}"
  echo "TRACE: $TRACE_ID"
fi

if [[ "$CODE" != "200" ]]; then
  echo "INVOKE STATUS: ${CODE:-<none>} (not 200)" >&2
  head -c 800 "$RESP_FILE" >&2; echo >&2
  exit 1
fi
