#!/usr/bin/env bash
# Shared helpers for the build-agent kit. Every script sources this.
# It reads credentials from the environment and defines thin wrappers over the
# Agenta HTTP API: agenta_get / agenta_post / agenta_delete.
#
# Credentials (set by you before running any script):
#   AGENTA_API_KEY   required. From your Agenta project settings (API keys).
#   AGENTA_HOST      optional. Defaults to Agenta cloud. Set it only if self-hosting.
#
# AGENTA_HOST, not AGENTA_API_URL: these scripts curl the public REST API directly from
# outside Agenta's infra, the same way the SDK derives its own api_url (host + "/api").
# AGENTA_API_URL is a different, internal override for a workflow running INSIDE Agenta's
# infra that needs a different internal address than the public host. Not relevant here.
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

# Cloud is the default. Self-hosted users set AGENTA_HOST to their own domain.
: "${AGENTA_HOST:=https://cloud.agenta.ai}"

if [ -z "${AGENTA_API_KEY:-}" ]; then
  {
    echo "AGENTA_API_KEY is not set."
    echo "Get a key from your Agenta project settings (API keys page), then set it one of two ways:"
    echo "  export AGENTA_API_KEY=...        # and AGENTA_HOST=https://your-domain if self-hosting"
    echo "  echo 'AGENTA_API_KEY=...' > .env # a .env in this directory is picked up automatically"
  } >&2
  exit 1
fi

_AUTH=(-H "Authorization: ApiKey $AGENTA_API_KEY" -H "Content-Type: application/json")

agenta_post()   { curl -s -X POST   "$AGENTA_HOST$1" "${_AUTH[@]}" -d "$2"; }
agenta_get()    { curl -s           "$AGENTA_HOST$1" "${_AUTH[@]}"; }
agenta_delete() { curl -s -X DELETE "$AGENTA_HOST$1" "${_AUTH[@]}"; }

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
