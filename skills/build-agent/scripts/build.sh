#!/usr/bin/env bash
# Create an agent and test it in one shot (the fast path for simple agents).
#
# Usage: build.sh <config.json> <slug> "<test message>" [name]
# Prints the create ids, then the OUTPUT / RESOLVED / TRACE from one test invoke.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONFIG_FILE="${1:?usage: build.sh <config.json> <slug> \"<test message>\" [name]}"
SLUG="${2:?usage: build.sh <config.json> <slug> \"<test message>\" [name]}"
MESSAGE="${3:?usage: build.sh <config.json> <slug> \"<test message>\" [name]}"
NAME="${4:-$SLUG}"
HERE="$(dirname "${BASH_SOURCE[0]}")"

IDS="$("$HERE/create-agent.sh" "$CONFIG_FILE" "$SLUG" "$NAME")"
echo "CREATED: $IDS"
APP_ID="$(jq -r '.application_id' <<<"$IDS")"
"$HERE/test-agent.sh" "$APP_ID" "$CONFIG_FILE" "$MESSAGE"
