#!/usr/bin/env bash
# List the integration connections this project already has (wraps list_connections).
# Usage: list-connections.sh
# Prints one line per connection: integration  slug  valid/active.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
agenta_post "/api/triggers/connections/query" '{}' \
  | jq -r '.connections[] | "\(.integration_key)\t\(.slug)\tvalid=\(.flags.is_valid)\tactive=\(.flags.is_active)"'
