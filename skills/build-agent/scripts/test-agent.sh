#!/usr/bin/env bash
# Invoke an agent over a STREAMING invoke AND verify the run, in one call.
#
# Usage: test-agent.sh <application_id> <config.json> "<message>"
#   Inlines the full config on every invoke. NOTE (provisional / open item): this script hits
#   the low-level agent-service endpoint, which does NOT hydrate a committed reference, so the
#   config must be carried inline — that inlining is a lab artifact. The product API invoke path
#   loads a committed reference server-side, so bare-reference invoke is a product feature. Treat
#   the invoke detail here as provisional (see references/config-schema.md).
#
# Why streaming: the batch invoke returns ONLY the run's final assistant text. A multi-tool
# run that ends on a tool-call turn therefore comes back EMPTY or mid-sentence even though the
# tools ran — the old "unreliable OUTPUT" problem. A streaming invoke (Accept:
# application/x-ndjson) returns EVERY event — each tool_call, each tool_result, the assistant
# text, and any approval gate — so the run is self-describing and you do not have to read the
# trace to see what happened.
#
# Prints:
#   OUTPUT:   the assistant's reply text (assembled from the streamed message deltas)
#   TOOLS:    every tool the run CALLED, in order, with a (calls/results) count — this is the
#             reliable "did it reach the terminal tool" signal, straight from the invoke
#             response. It makes check-tools.sh optional for that question.
#   APPROVAL: any tool that tripped a human-approval gate (the run pauses here; over a one-shot
#             HTTP invoke the stream ends at the gate, so the gated tool's RESULT is not in the
#             stream even when a headless "auto" policy later runs it — confirm a WRITE with
#             check-tools.sh <trace> <TOOL> if it must have completed).
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
STREAM="$TMP/stream.ndjson"; HDR="$TMP/headers"

# Accept: application/x-ndjson negotiates a streaming invoke (one JSON event per line). The
# other stream types are text/event-stream and application/jsonl; ndjson is the easiest to parse.
curl -s -N -X POST "$AGENTA_HOST/services/agent/v0/invoke" \
  -H "Authorization: ApiKey $AGENTA_API_KEY" -H "Content-Type: application/json" \
  -H "Accept: application/x-ndjson" \
  --max-time 600 -D "$HDR" -d "$BODY" > "$STREAM"

CODE="$(awk 'toupper($1) ~ /^HTTP/ {c=$2} END{print c}' "$HDR")"
TRACE_ID="$(awk 'tolower($1)=="x-ag-trace-id:" {print $2}' "$HDR" | tr -d '\r')"

# OUTPUT: concatenate the assistant message deltas (the streamed reply text).
OUTPUT="$(jq -rj 'select(.type=="message_delta") | .data.delta // ""' "$STREAM" 2>/dev/null)"
# TOOLS: the ordered tool_call names, short form (strip the mcp__agenta-tools__<integration>__ prefix).
TOOLS="$(jq -r 'select(.type=="tool_call") | (.data.name // "?") | sub("^mcp__agenta-tools__";"")' "$STREAM" 2>/dev/null)"
# grep -c prints 0 but EXITS 1 on no matches; under `set -e` (from lib.sh) that would kill the
# script on a zero-tool-call run (the common no-tools agent) before printing anything. Guard it.
N_CALLS="$(jq -r 'select(.type=="tool_call")   | .data.id' "$STREAM" 2>/dev/null | grep -c . || true)"
N_RESULTS="$(jq -r 'select(.type=="tool_result") | .data.id' "$STREAM" 2>/dev/null | grep -c . || true)"
APPROVALS="$(jq -r 'select(.type=="interaction_request")
  | "\(.data.kind // "interaction") on \(.data.payload.toolCall.title // .data.payload.toolCall.toolCallId // "?" | sub("^mcp__agenta-tools__";""))"' "$STREAM" 2>/dev/null)"

echo "OUTPUT: ${OUTPUT:-<no assistant text — the run ended on a tool-call/approval turn; see TOOLS>}"
if [[ -n "$TOOLS" ]]; then
  echo "TOOLS: $(paste -sd'|' <<<"$TOOLS" | sed 's/|/ -> /g')  (${N_CALLS} calls, ${N_RESULTS} results)"
else
  echo "TOOLS: (none — the run made no tool calls)"
fi
[[ -n "$APPROVALS" ]] && while IFS= read -r a; do echo "APPROVAL: $a"; done <<<"$APPROVALS"

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
  head -c 800 "$STREAM" >&2; echo >&2
  exit 1
fi
