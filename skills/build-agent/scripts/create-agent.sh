#!/usr/bin/env bash
# Create an Agenta agent (application + variant + first committed revision) in ONE call.
#
# Usage: create-agent.sh <config.json> <slug> [name]
#   <config.json>  a file holding the parameters.agent object (the agent config)
#   <slug>         url-safe slug, also used as the app name if [name] is omitted
#
# Prints a compact JSON line: {"application_id","variant_id","revision_id","slug"}
# Exits non-zero and prints the raw error if creation failed.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG_FILE="${1:?usage: create-agent.sh <config.json> <slug> [name]}"
SLUG="${2:?usage: create-agent.sh <config.json> <slug> [name]}"
NAME="${3:-$SLUG}"

AGENT_CONFIG="$(cat "$CONFIG_FILE")"
BODY="$(jq -n --arg slug "$SLUG" --arg name "$NAME" --argjson agent "$AGENT_CONFIG" '
  {application: {slug: $slug, name: $name,
    data: {uri: "agenta:builtin:agent:v0", parameters: {agent: $agent}}}}')"

RESP="$(agenta_post "/api/simple/applications/" "$BODY")"

APP_ID="$(jq -r '.application.id // empty' <<<"$RESP")"
if [[ -z "$APP_ID" ]]; then
  echo "CREATE FAILED:" >&2
  echo "$RESP" | head -c 1500 >&2; echo >&2
  exit 1
fi
jq -c '{application_id: .application.id, variant_id: .application.variant_id, revision_id: .application.revision_id, slug: .application.slug}' <<<"$RESP"
