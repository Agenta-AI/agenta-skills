#!/usr/bin/env bash
# List/inspect/remove triggers (wraps list_schedules, list_subscriptions, list_deliveries,
# remove_schedule, remove_subscription).
#
# Usage:
#   triggers.sh schedules                 list schedules
#   triggers.sh subscriptions             list subscriptions
#   triggers.sh deliveries                list recent delivery logs
#   triggers.sh rm-schedule <id>          delete a schedule
#   triggers.sh rm-subscription <id>      delete a subscription
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "${1:-}" in
  schedules)     agenta_get "/api/triggers/schedules/" | jq -r '(.schedules // .[] // [])[]? | "\(.id)\t\(.name)\t\(.data.schedule // "?")"' ;;
  subscriptions) agenta_get "/api/triggers/subscriptions/" | jq -r '(.subscriptions // .[] // [])[]? | "\(.id)\t\(.name)\t\(.data.event_key // "?")"' ;;
  deliveries)    agenta_get "/api/triggers/deliveries" | jq -c '.' | head -c 1500 ;;
  rm-schedule)   agenta_delete "/api/triggers/schedules/${2:?id}" | jq -c '{deleted:(.schedule.id // .id // "?")}' ;;
  rm-subscription) agenta_delete "/api/triggers/subscriptions/${2:?id}" | jq -c '{deleted:(.subscription.id // .id // "?")}' ;;
  *) echo "usage: triggers.sh {schedules|subscriptions|deliveries|rm-schedule <id>|rm-subscription <id>}" >&2; exit 1 ;;
esac
