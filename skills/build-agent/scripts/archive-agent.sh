#!/usr/bin/env bash
# Archive (soft-delete) an agent application. Use to clean up a throwaway or a failed-build app,
# or to free a slug for a retry.
# Usage: archive-agent.sh <application_id>
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
APP_ID="${1:?usage: archive-agent.sh <application_id>}"
agenta_post "/api/simple/applications/$APP_ID/archive" '{}' \
  | jq -c '{archived: (.application.id // "?"), deleted_at: (.application.deleted_at // "set")}' 2>/dev/null \
  || echo "archived $APP_ID"
