# Hardening a public-IP deployment

Do this when the host has a public IP or is reachable by anyone but you. A default local
deployment on a private network does not need it. The configuration reference lists every
variable: https://docs.agenta.ai/self-host/configuration .

## 1. Keep Postgres and the Traefik dashboard on loopback

The published Compose ports for Postgres and the Traefik dashboard are bound to `127.0.0.1`:

```yaml
# postgres
- "${POSTGRES_PORT:-127.0.0.1:5432}:5432"
# traefik dashboard
- "127.0.0.1:${TRAEFIK_UI_PORT:-8080}:8080"
```

**As of PR #5308 this loopback bind is the default.** Before that, these ports bound to
`0.0.0.0` and were reachable from the public internet. If you run an older stack, or if you
override `POSTGRES_PORT` / `TRAEFIK_UI_PORT`, confirm they still bind to `127.0.0.1` and not
`0.0.0.0`. Verify with the port check in test.md (step 7).

The bundled SeaweedFS object store publishes on `127.0.0.1:${AGENTA_STORE_PORT:-8333}` by
the same loopback default. Leave it there when agents run in the local sandbox; nothing
outside the Compose network needs it. A Daytona sandbox is the exception. It runs in the
cloud and reaches the store over the public internet, so a Daytona deployment has to publish
the store on its own subdomain through an opt-in traefik router (`AGENTA_STORE_TRAEFIK_ENABLE`
plus `AGENTA_STORE_DOMAIN`), which is a hostname-scoped route, not a `0.0.0.0` bind of the raw
port. Without it, agent files are lost silently (troubleshoot.md entry 9).

## 2. Change the default database credentials

The example env files ship `username` / `password` as the Postgres user and password, wired
into the DB URIs (`postgresql://username:password@postgres:5432/...`). Change both before
exposing the host, and update every URI that embeds them (the core DB URIs and the
supertokens URI). Do not leave the defaults on a reachable deployment.

## 3. Generate real secret keys

The example env files ship `AGENTA_AUTH_KEY=replace-me` and `AGENTA_CRYPT_KEY=replace-me`.
Replace both with generated values:

```bash
openssl rand -hex 32   # run once per key
```

Set the results as `AGENTA_AUTH_KEY` and `AGENTA_CRYPT_KEY` in your env file. `AGENTA_CRYPT_KEY`
encrypts stored secrets, so changing it later invalidates anything already encrypted with the
old value. Generate it once, before first use.

The example env files ship the same `replace-me` placeholder for several more secrets. Replace
each before exposing the host:

- `AGENTA_RUNNER_TOKEN` — the shared token that gates the runner. **Required** even locally
  (the runner refuses to boot without it), and it must be the **same** value on the `api`,
  `services`, and `runner` containers. `openssl rand -hex 32`. (troubleshoot.md entry 6.)
- `AGENTA_STORE_ACCESS_KEY` / `AGENTA_STORE_SECRET_KEY` — credentials for the bundled object
  store. `AGENTA_STORE_SIGNING_KEY` — the mount-signing key; generate with
  `openssl rand -base64 32`. The `seaweedfs` service and the api read these same values, so a
  shared replacement still works out of the box.

## 4. Close the MCP gateway's egress guard if others can connect MCP servers

From Agenta 0.119.0 the `api` container relays every MCP call an agent makes, so the address
an MCP connection names is dialed from your API container rather than from the sandbox. From
that version the four self-host env templates ship the relay's outbound guard open, because a
self-hosted MCP server usually sits on the operator's own network or answers over plain HTTP:

```bash
AGENTA_GATEWAYS_INSECURE_EGRESS_ALLOWED=true
```

With the guard open, anyone who can create an MCP connection on this deployment can aim one at
any address your API container can reach, including `10.0.0.0/8` and the rest of your internal
network. On a deployment where people you do not vet can create those connections, close the
guard and name the internal servers you trust instead:

```bash
AGENTA_GATEWAYS_INSECURE_EGRESS_ALLOWED=false
AGENTA_MCP_GATEWAY_HOST_ALLOWLIST=mcp.internal,10.0.0.5
```

The allowlist is comma-separated and holds hostnames with no scheme and no path. A listed host
skips the guard entirely; every other target must use https and must resolve to a public
address, or the agent's tool call fails with `blocked target` (troubleshoot.md entry 15). Both
variables are read by the `api` container only, so recreate it after the change:

```bash
docker compose up -d --force-recreate api
```

Closing the guard does not affect the credential the run carries back into Agenta. That is
`AGENTA_GATEWAYS_INSECURE_HTTP_ALLOWED`, read by `services` and `runner`, and it stays as it
is (decisions.md entry 5).
