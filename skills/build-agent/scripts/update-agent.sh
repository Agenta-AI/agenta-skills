#!/usr/bin/env bash
# Commit an updated config to an EXISTING agent (wraps commit_revision,
# POST /api/workflows/revisions/commit). Prefer this over archive-and-recreate: the app,
# its slug, its variant id, and any schedules or subscriptions pointing at it keep working.
#
# Usage: update-agent.sh <variant_id> <config.json> [message]
#   <variant_id>   from create-agent.sh / build.sh
#   <config.json>  the FULL new parameters.agent object (same file shape create-agent.sh takes)
#   [message]      commit message (default: "update agent config")
#
# Merge semantics: the new config deep-merges onto the current one. Scalars and lists
# (tools, skills, mcps) replace wholesale; a nested object key you leave out keeps its old
# value. Pass the complete config, boilerplate included, so the result is exactly what you
# wrote. Re-test after updating: bash scripts/test-agent.sh <application_id> <config.json> "<msg>"
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

VARIANT="${1:?usage: update-agent.sh <variant_id> <config.json> [message]}"
CONFIG_FILE="${2:?usage: update-agent.sh <variant_id> <config.json> [message]}"
MESSAGE="${3:-update agent config}"

validate_agent_config_delta "$CONFIG_FILE" || exit 1

AGENT_CONFIG="$(cat "$CONFIG_FILE")"
BODY="$(jq -n --arg vid "$VARIANT" --arg msg "$MESSAGE" --argjson agent "$AGENT_CONFIG" \
  '{workflow_revision:{workflow_variant_id:$vid, message:$msg,
    delta:{set:{parameters:{agent:$agent}}}}}')"
RESP="$(agenta_post "/api/workflows/revisions/commit" "$BODY")"
REV_ID="$(jq -r '.workflow_revision.id // empty' <<<"$RESP")"
if [[ -z "$REV_ID" ]]; then
  echo "UPDATE FAILED:" >&2
  echo "$RESP" | head -c 1500 >&2; echo >&2
  exit 1
fi
jq -c '{revision_id: .workflow_revision.id, variant_id: (.workflow_revision.workflow_variant_id // .workflow_revision.variant_id // null), message: (.workflow_revision.message // null)}' <<<"$RESP"
