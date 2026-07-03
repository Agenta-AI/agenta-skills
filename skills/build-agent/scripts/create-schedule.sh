#!/usr/bin/env bash
# Create a cron schedule that runs a given agent variant (wraps create_schedule).
#
# Usage: create-schedule.sh <variant_id> "<cron 5-field UTC>" <event_key> [name] [inputs_json]
#   <cron>       five-field expression, UTC, one-minute floor (e.g. "0 7,13 * * *" = 07:00 & 13:00 UTC daily)
#   <event_key>  a label recorded on each delivery (free text)
#   [inputs_json] optional JSON object/string mapped into the run inputs each fire
#                 (shape: references/trigger-inputs.md)
#
# Prints the created schedule id (and name). Convert the user's local time to UTC yourself.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VARIANT="${1:?usage: create-schedule.sh <variant_id> <cron> <event_key> [name] [inputs_json]}"
CRON="${2:?cron required}"
EVENT_KEY="${3:?event_key required}"
NAME="${4:-$EVENT_KEY}"
INPUTS="${5:-}"

DATA="$(jq -n --arg ek "$EVENT_KEY" --arg cron "$CRON" --arg vid "$VARIANT" \
  '{event_key:$ek, schedule:$cron, references:{workflow_variant:{id:$vid}}}')"
if [[ -n "$INPUTS" ]]; then
  DATA="$(jq --argjson inp "$INPUTS" '. + {inputs_fields:$inp}' <<<"$DATA")"
fi
BODY="$(jq -n --arg name "$NAME" --argjson data "$DATA" '{schedule:{name:$name, data:$data}}')"
RESP="$(agenta_post "/api/triggers/schedules/" "$BODY")"
ID="$(jq -r '.schedule.id // .id // empty' <<<"$RESP")"
if [[ -z "$ID" ]]; then echo "CREATE SCHEDULE FAILED:"; echo "$RESP" | head -c 1000; exit 1; fi
jq -c '{schedule_id: (.schedule.id // .id), name: (.schedule.name // .name), cron: (.schedule.data.schedule // null)}' <<<"$RESP"
