# Troubleshooting

Field-verified OSS failures, keyed to the exact error text. Each entry is
symptom -> cause -> fix. If your symptom is not here, the configuration reference
(https://docs.agenta.ai/self-host/configuration) and networking doc
(https://docs.agenta.ai/self-host/infrastructure/networking) are the next stops.

## 1. `could not find runner CLI at /app/runner/src/cli.ts`

**Symptom.** An agent run fails and the API logs show a message like
`<backend> could not find runner CLI at /app/runner/src/cli.ts`.

**Cause.** The API did not get a runner URL, so the SDK adapter fell back to launching the
runner as a subprocess and looked for its CLI on disk. The API image does not contain the
runner, so the CLI is not there. This means `AGENTA_RUNNER_INTERNAL_URL` is unset or was
overridden to empty in your env file.

**Fix.** Point the API at the runner container over HTTP:

```bash
AGENTA_RUNNER_INTERNAL_URL=http://runner:8765
```

The Compose files default this to `http://runner:8765` already, so this bites when a custom
env file blanks it out. Confirm your env file does not set `AGENTA_RUNNER_INTERNAL_URL=` to
empty. Runner variables are in the configuration reference:
https://docs.agenta.ai/self-host/configuration .

## 2. Behind a reverse proxy or Cloudflare, redirects come back as `http://` and drop `/api`

**Symptom.** The stack works on a plain IP, but once you put a proxy (Cloudflare, an
upstream nginx, a load balancer) in front, API calls 307/308-redirect to a `http://` URL and
sometimes lose the `/api` prefix. Login loops or mixed-content errors follow.

**Cause.** The API runs under gunicorn's Uvicorn worker, which only trusts forwarded
headers (`X-Forwarded-Proto`, `X-Forwarded-For`) from clients in its trusted list. The
immediate client is now the proxy, not loopback, so Uvicorn ignores the `https` signal and
builds `http://` redirects. Traefik, in turn, does not trust forwarded headers from the
upstream proxy by default.

**Fix.** Trust the proxy at both hops.

1. Tell Uvicorn to trust forwarded headers from any client, in your env file:

   ```bash
   FORWARDED_ALLOW_IPS=*
   ```

2. Tell Traefik to trust forwarded headers on the web entrypoint. Add to the `traefik`
   service command in your Compose file:

   ```yaml
   - --entrypoints.web.forwardedHeaders.insecure=true
   ```

Set `FORWARDED_ALLOW_IPS=*` only when a trusted proxy sits in front of the stack. It tells
Uvicorn to believe the `X-Forwarded-*` headers on every request.

## 3. Subscription run behaves as if you never logged in

**Symptom.** You mounted `~/.claude` (or another harness login) into the runner for a
personal-subscription run, but the harness prompts to log in again or fails to authenticate.

**Cause.** The runner container runs as the user `node`, uid 1000. A harness login file is
mode `0600` and owned by your host user. If your host uid is not 1000, the container cannot
read the file through the bind mount, so the login looks absent.

**Fix.** Copy the login into a directory owned by uid 1000 and mount that directory
**read-write** (the harness rewrites tokens). The subscription how-to has the exact commands
and the `id -u` check: https://docs.agenta.ai/self-host/use-your-own-subscription .

## 4. `permission denied ... /var/run/docker.sock`

**Symptom.** A container or `run.sh` fails with `permission denied` on
`/var/run/docker.sock`.

**Cause.** Your user is not in the `docker` group and cannot reach the Docker daemon.

**Fix.** Run as root, use `sudo`, or add yourself to the group and open a new shell:

```bash
sudo usermod -aG docker $USER   # then start a new shell
```

Docker-group membership is root-equivalent on the host. Grant it deliberately.

## 5. Fresh OSS quick start: supertokens fails on an empty `POSTGRESQL_CONNECTION_URI`

**Symptom.** On a first OSS `--gh` deploy, the supertokens container fails to start or
cannot connect to Postgres, and its config shows an empty `POSTGRESQL_CONNECTION_URI`.

**Cause.** The OSS `gh` Compose file maps
`POSTGRESQL_CONNECTION_URI: ${POSTGRES_URI_SUPERTOKENS}` with **no fallback default**, but
the OSS example env file ships `POSTGRES_URI_SUPERTOKENS` **commented out**. So the variable
is empty and supertokens gets no connection string.

**Fix.** Uncomment the line in your OSS env file:

```bash
POSTGRES_URI_SUPERTOKENS=postgresql://username:password@postgres:5432/agenta_oss_supertokens
```

Match the credentials and DB name to your deployment. This is a known OSS gap; treat it as
pending until the fallback lands upstream.

## 6. `AGENTA_RUNNER_TOKEN is required` — runner won't boot, or runs fail with 401

**Symptom.** One of: the stack refuses to start with
`AGENTA_RUNNER_TOKEN is required`; the runner container exits at boot logging
`AGENTA_RUNNER_TOKEN is required. Generate a secret ...`; or an agent run fails with
`AGENTA_RUNNER_TOKEN is required to call the agent runner ...` or an opaque `401` from the
runner.

**Cause.** The runner token is now **mandatory**. Both the `gh` and `dev` Compose files
guard it as `${AGENTA_RUNNER_TOKEN:?...}`, the runner refuses to boot without it, and the
services→runner call sends it as a bearer token that the runner rejects with `401` if it
does not match. So the token is either blank (won't boot) or set to a **different** value on
the two sides (401 on every run).

**Fix.** Set the **same** non-empty value on both the `services` and `runner` containers —
they read the one `AGENTA_RUNNER_TOKEN`. The example env files ship
`AGENTA_RUNNER_TOKEN=replace-me`; replace it and keep both sides equal. Generate one with:

```bash
openssl rand -hex 32
```

## 7. Durable mounts fail with `503 Mount storage backend is not configured`

**Symptom.** An agent run that reads or writes a session/mounted file fails, the mounts API
returns `503` with `Mount storage backend is not configured`, or files silently do not
persist across runs.

**Cause.** Mount signing is backed by an object store. The `gh` Compose files now bundle a
SeaweedFS `seaweedfs` service and the `api` `depends_on` it, so this works out of the box —
but a custom env file that blanks the `AGENTA_STORE_*` vars, or an older stack from before
the store was bundled, leaves the API with no store to sign against.

**Fix.** Keep the store vars pointing at the bundled service and non-empty:

```bash
AGENTA_STORE_ENDPOINT_URL=http://seaweedfs:8333
AGENTA_STORE_BUCKET=agenta-store
AGENTA_STORE_ACCESS_KEY=...      # example ships replace-me
AGENTA_STORE_SECRET_KEY=...      # example ships replace-me
AGENTA_STORE_SIGNING_KEY=...     # example ships replace-me; openssl rand -base64 32
```

Confirm the `seaweedfs` container is healthy (test.md step 5). To use an external
S3-compatible store (AWS S3, Cloudflare R2, MinIO) instead, point those vars at it and clear
`AGENTA_STORE_SIGNING_KEY` (its presence selects the bundled-SeaweedFS signing path). Store
options are in the configuration reference:
https://docs.agenta.ai/self-host/configuration#store-durable-object-store .

## 8. `docker compose --env-file <name>` silently loads the default env file

**Symptom.** You run `docker compose` directly (not `run.sh`) with a non-default env file,
e.g. `docker compose ... --env-file .env.oss.gh.local up`, and the stack behaves as if it
read a different file: wrong ports, `/api` 404s, or missing runner/store values.

**Cause.** The Compose services load their env via `env_file: ${ENV_FILE:-<default>}`.
`--env-file` only feeds variable **interpolation**; it does **not** set the `ENV_FILE`
variable, so `${ENV_FILE:-<default>}` falls back to the committed default file — not the one
you passed.

**Fix.** Prefer `run.sh`, which exports `ENV_FILE` for you. If you must drive Compose
directly, use the default filename, or set `ENV_FILE` — export it, or put
`ENV_FILE=<path>` inside the env file you pass to `--env-file`:

```bash
export ENV_FILE=.env.oss.gh.local
docker compose -f <compose-file> --env-file "$ENV_FILE" up -d
```
