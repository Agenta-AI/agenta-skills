#!/usr/bin/env bash
# Shared helpers for the build-agent kit. Every script sources this.
# It reads credentials from the environment and defines thin wrappers over the
# Agenta HTTP API: agenta_get / agenta_post / agenta_delete.
#
# Credentials (set by you before running any script):
#   AGENTA_API_KEY   required. From your Agenta project settings (API keys).
#   AGENTA_API_URL   optional. The full API URL, e.g. https://eu.cloud.agenta.ai/api or
#                    http://localhost/api. Set it if self-hosting or on a non-default cloud
#                    region. Defaults to https://cloud.agenta.ai/api.
#
# Precedence: values already in the environment win. If AGENTA_API_KEY is not in the
# environment, the kit falls back to a .env file (AGENTA_ENV_FILE, then ./.env, then a
# .env next to these scripts). The build-agent skill can write that .env for you.
# Kept to pre-4.0 bash so it runs under macOS's stock bash 3.2.
set -euo pipefail

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${AGENTA_API_KEY:-}" ]; then
  for _envfile in "${AGENTA_ENV_FILE:-}" "$PWD/.env" "$_LIB_DIR/.env"; do
    if [ -n "$_envfile" ] && [ -f "$_envfile" ]; then
      set -a; . "$_envfile"; set +a
      break
    fi
  done
fi

# Cloud is the default. AGENTA_API_URL already includes /api (e.g. https://eu.cloud.agenta.ai/api).
: "${AGENTA_API_URL:=https://cloud.agenta.ai/api}"
_API_BASE="${AGENTA_API_URL%/}"
# Every call site below builds its own /api/... or /services/... path, so also keep a bare
# root (no /api suffix) for the one call site that needs a non-/api path.
_API_ROOT="${_API_BASE%/api}"

if [ -z "${AGENTA_API_KEY:-}" ]; then
  {
    echo "AGENTA_API_KEY is not set."
    echo "Get a key from your Agenta project settings (API keys page), then set it one of two ways:"
    echo "  export AGENTA_API_KEY=...        # and AGENTA_API_URL=https://your-domain/api if self-hosting"
    echo "  echo 'AGENTA_API_KEY=...' > .env # a .env in this directory is picked up automatically"
  } >&2
  exit 1
fi

_AUTH=(-H "Authorization: ApiKey $AGENTA_API_KEY" -H "Content-Type: application/json")

agenta_post()   { curl -s -X POST   "$_API_ROOT$1" "${_AUTH[@]}" -d "$2"; }
agenta_get()    { curl -s           "$_API_ROOT$1" "${_AUTH[@]}"; }
agenta_delete() { curl -s -X DELETE "$_API_ROOT$1" "${_AUTH[@]}"; }

# Resolves a <revision_id> argument for create-schedule.sh / create-subscription.sh.
# A real revision id (from create-agent.sh / build.sh / update-agent.sh) passes straight
# through. The literal value "latest" (case-insensitive) instead fetches the variant's
# current HEAD revision via /api/workflows/revisions/log, so a caller who only has the
# variant_id at hand (e.g. wiring a trigger some time after the agent was built) doesn't
# have to go look up the revision id first.
#
# Usage: rid="$(resolve_revision_id "$VARIANT" "$REVISION_ARG")" || exit 1
resolve_revision_id() {
  local variant_id="$1" revision_arg="${2:-}" requested resp rid
  requested="$(printf '%s' "$revision_arg" | tr '[:upper:]' '[:lower:]')"
  if [ -n "$revision_arg" ] && [ "$requested" != "latest" ]; then
    printf '%s' "$revision_arg"
    return 0
  fi
  resp="$(agenta_post "/api/workflows/revisions/log" \
    "$(jq -n --arg vid "$variant_id" '{workflow_revisions:{workflow_variant_id:$vid, depth:1}}')")"
  rid="$(jq -r '.workflow_revisions[0].id // empty' <<<"$resp")"
  if [ -z "$rid" ]; then
    {
      echo "REVISION LOOKUP FAILED: could not resolve the latest revision for variant $variant_id."
      echo "$resp" | head -c 800
      echo
    } >&2
    return 1
  fi
  printf '%s' "$rid"
}
