#!/usr/bin/env bash
# Create a cron schedule that runs a given agent revision (wraps create_schedule).
#
# Usage: create-schedule.sh <variant_id> <revision_id> "<cron 5-field UTC>" <event_key> [name] [inputs_json]
#   <revision_id> from create-agent.sh / build.sh (or update-agent.sh after a change) — pins
#                 which committed revision the schedule runs. Without this, the schedule has
#                 no bound revision at all ("Which version runs?" is left unset in the Agenta
#                 UI, which treats it as a required field). Pass the literal word "latest" to
#                 have this script look up the variant's current HEAD revision for you.
#   <cron>       five-field expression, UTC, one-minute floor (e.g. "0 7,13 * * *" = 07:00 & 13:00 UTC daily)
#   <event_key>  a label recorded on each delivery (free text)
#   [inputs_json] optional JSON object/string mapped into the run inputs each fire
#                 (shape: references/trigger-inputs.md)
#
# Prints the created schedule id (and name). Convert the user's local time to UTC yourself.
# If you later commit a new revision with update-agent.sh, re-run this (or the equivalent
# update call) so the schedule points at the new revision_id — it does not follow automatically.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VARIANT="${1:?usage: create-schedule.sh <variant_id> <revision_id> <cron> <event_key> [name] [inputs_json]}"
REVISION_ARG="${2:?usage: create-schedule.sh <variant_id> <revision_id> <cron> <event_key> [name] [inputs_json]}"
CRON="${3:?cron required}"
EVENT_KEY="${4:?event_key required}"
NAME="${5:-$EVENT_KEY}"
INPUTS="${6:-}"

REVISION="$(resolve_revision_id "$VARIANT" "$REVISION_ARG")" || exit 1

DATA="$(jq -n --arg ek "$EVENT_KEY" --arg cron "$CRON" --arg vid "$VARIANT" --arg rid "$REVISION" \
  '{event_key:$ek, schedule:$cron, references:{workflow_variant:{id:$vid}, workflow_revision:{id:$rid}}}')"
if [[ -n "$INPUTS" ]]; then
  DATA="$(jq --argjson inp "$INPUTS" '. + {inputs_fields:$inp}' <<<"$DATA")"
fi
BODY="$(jq -n --arg name "$NAME" --argjson data "$DATA" '{schedule:{name:$name, data:$data}}')"
RESP="$(agenta_post "/api/triggers/schedules/" "$BODY")"
ID="$(jq -r '.schedule.id // .id // empty' <<<"$RESP")"
if [[ -z "$ID" ]]; then echo "CREATE SCHEDULE FAILED:"; echo "$RESP" | head -c 1000; exit 1; fi
jq -c '{schedule_id: (.schedule.id // .id), name: (.schedule.name // .name), cron: (.schedule.data.schedule // null)}' <<<"$RESP"
