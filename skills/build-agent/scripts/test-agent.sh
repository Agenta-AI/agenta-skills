#!/usr/bin/env bash
# Invoke an agent AND verify the run actually used the intended config, in one call.
#
# Usage: test-agent.sh <application_id> <config.json> "<message>"
#   Sends the full config inline on each invoke. The exact product invoke path is still
#   being finalized; inlining the config is the form that works today, so treat the invoke
#   detail here as provisional (see references/config-schema.md).
#
# Prints:
#   OUTPUT:   the assistant's reply text
#   RESOLVED: harness / model / provider / connection.mode the run actually executed with
#   TRACE:    the trace id (inspect with: agenta_get /api/simple/traces/<id>)
# Exits non-zero if the invoke status is not 200.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP_ID="${1:?usage: test-agent.sh <application_id> <config.json> \"<message>\"}"
CONFIG_FILE="${2:?usage: test-agent.sh <application_id> <config.json> \"<message>\"}"
MESSAGE="${3:?usage: test-agent.sh <application_id> <config.json> \"<message>\"}"

AGENT_CONFIG="$(cat "$CONFIG_FILE")"
BODY="$(jq -n --arg app "$APP_ID" --arg msg "$MESSAGE" --argjson agent "$AGENT_CONFIG" '
  {data: {inputs: {messages: [{role: "user", content: $msg}]}, parameters: {agent: $agent}},
   references: {application: {id: $app}}}')"

RESP="$(agenta_post "/services/agent/v0/invoke" "$BODY")"
CODE="$(jq -r '.status.code // "?"' <<<"$RESP")"
TRACE_ID="$(jq -r '.trace_id // empty' <<<"$RESP")"
OUTPUT="$(jq -r '.data.outputs.messages[-1].content // (.data|tostring)' <<<"$RESP")"

echo "OUTPUT: $OUTPUT"
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
  echo "INVOKE STATUS: $CODE (not 200)" >&2
  echo "$RESP" | head -c 800 >&2; echo >&2
  exit 1
fi
