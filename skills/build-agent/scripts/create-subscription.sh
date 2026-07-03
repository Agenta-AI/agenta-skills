#!/usr/bin/env bash
# Create an event subscription that runs a given agent variant when a provider event
# fires (wraps create_subscription, POST /api/triggers/subscriptions/).
#
# Usage: create-subscription.sh <variant_id> <event_key> <connection> [name] [trigger_config_json] [inputs_json]
#   <variant_id>   the agent variant to run on each event (from create-agent.sh / build.sh)
#   <event_key>    the provider event key printed by discover-triggers.sh
#   <connection>   the event source connection: its id or its slug (discover-triggers.sh
#                  prints the state; scripts/extras/list-connections.sh prints ids)
#   [name]         human label (defaults to event_key)
#   [trigger_config_json]  event parameters shaped by the event's trigger_config schema
#   [inputs_json]  inputs_fields template mapped into the run inputs on each fire
#                  (shape: references/trigger-inputs.md)
#
# The connection MUST be `ready` before you create the subscription — needs_auth means
# stop and ask the user to connect it first. A created subscription proves nothing ran:
# verify actual fires with `bash scripts/triggers.sh deliveries`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VARIANT="${1:?usage: create-subscription.sh <variant_id> <event_key> <connection> [name] [trigger_config_json] [inputs_json]}"
EVENT_KEY="${2:?event_key required}"
CONNECTION="${3:?connection id or slug required}"
NAME="${4:-$EVENT_KEY}"
TRIGGER_CONFIG="${5:-}"
INPUTS="${6:-}"

# The endpoint takes the connection id; accept a slug and resolve it.
CONNS="$(agenta_post "/api/triggers/connections/query" '{}')"
CONN_ID="$(jq -r --arg c "$CONNECTION" \
  '[.connections[] | select(.id == $c or .slug == $c)][0].id // empty' <<<"$CONNS")"
if [[ -z "$CONN_ID" ]]; then
  {
    echo "CONNECTION NOT FOUND: '$CONNECTION' matches no connection id or slug in this project."
    echo "Connections in this project (integration  slug  id  state):"
    jq -r '.connections[] | "  \(.integration_key)\t\(.slug)\t\(.id)\tvalid=\(.flags.is_valid) active=\(.flags.is_active)"' <<<"$CONNS"
  } >&2
  exit 1
fi

DATA="$(jq -n --arg ek "$EVENT_KEY" --arg vid "$VARIANT" \
  '{event_key:$ek, references:{workflow_variant:{id:$vid}}}')"
if [[ -n "$TRIGGER_CONFIG" ]]; then
  DATA="$(jq --argjson tc "$TRIGGER_CONFIG" '. + {trigger_config:$tc}' <<<"$DATA")"
fi
if [[ -n "$INPUTS" ]]; then
  DATA="$(jq --argjson inp "$INPUTS" '. + {inputs_fields:$inp}' <<<"$DATA")"
fi
BODY="$(jq -n --arg name "$NAME" --arg cid "$CONN_ID" --argjson data "$DATA" \
  '{subscription:{name:$name, connection_id:$cid, data:$data}}')"
RESP="$(agenta_post "/api/triggers/subscriptions/" "$BODY")"
ID="$(jq -r '.subscription.id // empty' <<<"$RESP")"
if [[ -z "$ID" ]]; then echo "CREATE SUBSCRIPTION FAILED:"; echo "$RESP" | head -c 1000; exit 1; fi
jq -c '{subscription_id: .subscription.id, name: .subscription.name, event_key: .subscription.data.event_key, connection_id: .subscription.connection_id}' <<<"$RESP"
echo "NOTE: creation proves nothing fired. The connection must stay ready; confirm real fires with: bash scripts/triggers.sh deliveries"
