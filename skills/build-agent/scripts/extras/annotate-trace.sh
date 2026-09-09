#!/usr/bin/env bash
# EXTRA (not part of the core loop): record a reflection/annotation against an application's
# traces (wraps POST /api/annotations/).
#
# Usage: extras/annotate-trace.sh <application_id> "<note>"
# NOTE: this drives the public HTTP API from outside a run, so it stays an experimenter/demo
# tool for human use. On-platform agents (default build kit) can self-annotate at runtime via
# the `annotate_trace` platform op instead (see references/annotate-trace.md).
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
APP_ID="${1:?usage: extras/annotate-trace.sh <application_id> \"<note>\"}"
NOTE="${2:?note required}"
BODY="$(jq -n --arg app "$APP_ID" --arg note "$NOTE" \
  '{annotation:{origin:"human",kind:"adhoc",channel:"api",data:{note:$note},references:{application:{id:$app}},links:{}}}')"
agenta_post "/api/annotations/" "$BODY" | jq -c '{annotation_span:(.annotation.span_id // "?"), note:(.annotation.data.note // "?")}'
