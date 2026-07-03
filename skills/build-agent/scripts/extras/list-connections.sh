#!/usr/bin/env bash
# EXTRA (not part of the core loop): list the integration connections this project already
# has (wraps list_connections). `discover-tools.sh` already prints the CONNECTIONS block,
# which is usually all you need; reach for this only to see every connection with its id.
# Usage: extras/list-connections.sh
# Prints one line per connection: integration  slug  id  valid/active.
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
agenta_post "/api/triggers/connections/query" '{}' \
  | jq -r '.connections[] | "\(.integration_key)\t\(.slug)\t\(.id)\tvalid=\(.flags.is_valid)\tactive=\(.flags.is_active)"'
