#!/usr/bin/env bash
# Shared helpers for the build-agent kit. Every script sources this.
# It reads credentials from the environment and defines thin wrappers over the
# Agenta HTTP API: agenta_get / agenta_post / agenta_delete.
#
# Credentials (set by you before running any script):
#   AGENTA_API_KEY   required. From your Agenta project settings (API keys).
#   AGENTA_HOST      optional. Defaults to Agenta cloud. Set it only if self-hosting.
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

# Checks that harness.kind and llm.provider are a consistent pairing, when both are
# present in the given config file. The Claude Code harness ("claude") only runs
# Anthropic models — pairing it with any other provider is accepted by the create/commit
# endpoints with no server-side error, but the agent then gets no Model & Harness
# resolved in the Agenta UI and won't run correctly. This check is tolerant of missing
# fields (safe to use on a partial update-agent.sh delta, which merges onto the existing
# config) — it only fires when both fields are actually present and inconsistent.
#
# Usage: _check_harness_provider_consistency <config.json>
_check_harness_provider_consistency() {
  local config_file="$1"
  local harness_kind provider model
  harness_kind="$(jq -r '.harness.kind // empty' "$config_file" 2>/dev/null || true)"
  provider="$(jq -r '.llm.provider // empty' "$config_file" 2>/dev/null || true)"
  model="$(jq -r '.llm.model // empty' "$config_file" 2>/dev/null || true)"

  if [ -n "$harness_kind" ] && [ -n "$provider" ] && [ "$harness_kind" = "claude" ] && [ "$provider" != "anthropic" ]; then
    {
      echo "CONFIG ERROR: harness.kind=\"claude\" requires llm.provider=\"anthropic\" — the"
      echo "  Claude Code harness only runs Anthropic models. Found llm.provider=\"$provider\","
      echo "  llm.model=\"$model\" instead."
      echo "  This exact mismatch is accepted by the API with no error, but the agent then"
      echo "  gets no Model & Harness resolved in the Agenta UI and won't run correctly."
      echo "  Fix: set llm.provider back to \"anthropic\" and llm.model to one of"
      echo "  sonnet/opus/haiku/default (see SKILL.md). This skill does not currently support"
      echo "  building agents on a non-Claude harness — do not substitute a different provider"
      echo "  while leaving harness.kind=\"claude\"."
    } >&2
    return 1
  fi
  return 0
}

# Full validation for a brand-new agent config (create-agent.sh). Requires the fixed
# boilerplate fields to all be present — a simple agent has no reason to omit any of
# them — plus the harness/provider consistency check above.
#
# Usage: validate_agent_config <config.json>
# Prints nothing on success. On failure, prints a specific CONFIG ERROR to stderr and
# returns non-zero — the caller should stop and fix the config rather than proceed.
validate_agent_config() {
  local config_file="$1"
  local field val

  for field in '.llm.model' '.llm.provider' '.llm.connection.mode' \
               '.harness.kind' '.runner.kind' '.sandbox.kind'; do
    val="$(jq -r "$field // empty" "$config_file" 2>/dev/null || true)"
    if [ -z "$val" ]; then
      {
        echo "CONFIG ERROR: required field $field is missing or empty in $config_file."
        echo "  instructions / tools / mcps / skills are the only fields you write yourself —"
        echo "  llm / harness / runner / sandbox must be copied exactly from the boilerplate"
        echo "  in SKILL.md, even for the simplest agent. Fix the config before creating/testing."
      } >&2
      return 1
    fi
  done

  _check_harness_provider_consistency "$config_file"
}

# Lighter validation for an update-agent.sh delta, which deep-merges onto the existing
# config and so may legitimately omit any of the boilerplate fields. Only checks for an
# internal inconsistency in what IS being submitted.
#
# LIMITATION: this does not fetch and merge the current committed config, so it only
# catches a mismatch when both harness.kind and llm.provider are present together in the
# delta itself. A delta that changes ONLY llm.provider (relying on merge to keep a
# previous harness.kind: "claude") will NOT be caught here. This is why update-agent.sh's
# own guidance is to always pass the complete config, boilerplate included — do that
# rather than relying on this check as a full safety net for a minimal delta.
#
# Usage: validate_agent_config_delta <config.json>
validate_agent_config_delta() {
  _check_harness_provider_consistency "$1"
}

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
