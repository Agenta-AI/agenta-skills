# Test the deployment — mandatory

Do not report success until this passes. "Containers are up" is not proof. Run every step;
if one fails, go to troubleshoot.md, fix, and rerun. Replace `localhost` with the host and
adjust the port if you changed `TRAEFIK_PORT`.

## 1. API health -> 200

The API mounts under `/api`, so through Traefik the health route is `/api/health`:

```bash
curl -fsS http://localhost/api/health && echo OK
```

A 200 JSON body means the API and its DB migrations are up. A 404 usually means the web/API
URL env vars are wrong for the port you deployed on (quick-start's custom-port section).

## 2. Runner reachable from the API container

The API reaches the runner over the internal network at `http://runner:8765`:

```bash
docker compose exec api curl -fsS http://runner:8765/health
```

It returns the runner identity (`status`, `runner`, `protocol`, `engines`, `harnesses`). If
this fails while the runner container is up, `AGENTA_RUNNER_INTERNAL_URL` is wrong or blank
(troubleshoot.md entry 1). Also confirm the startup config line:

```bash
docker compose logs runner | grep '\[sandbox-agent\]'
```

Look for the redacted config summary and `http server listening on 0.0.0.0:8765`. A bad
provider list or a Daytona provider with no credential fails startup here, not at first run.

## 3. Sign up and reach the studio

Open `http://localhost` (or your host URL) in a browser, sign up, and land in the studio.
The first account gets its own organization. If sign-up loops or redirects to `http://`
behind a proxy, that is the forwarded-header case (troubleshoot.md entry 2).

## 4. Create an agent and run it — the real proof

This is what "working" means. Do it through the studio UI (or the API):

1. Create an agent. Give it an instruction and, if you can, enable one tool.
2. Run a plain prompt. Confirm the agent responds.
3. Run a prompt that exercises the tool (a tool call). Confirm the tool call happens and the
   run finishes without error.

If model auth fails, revisit decision 2 (managed key vs subscription; subscription has the
uid-1000 mount gotcha, troubleshoot.md entry 3). If a run fails with a `401` from the runner
or `AGENTA_RUNNER_TOKEN is required`, the token is unset or mismatched (troubleshoot.md
entry 6). To build the agent itself, the `build-agent` skill drives this over the API.

## 5. Object store healthy — durable mounts persist

Agent/session mounts are signed against the bundled SeaweedFS object store, which the `gh`
Compose files run as the `seaweedfs` service and the `api` depends on. Confirm it is up and
answering on its loopback-bound port:

```bash
docker compose ps seaweedfs                 # State should be "healthy"
curl -fsS http://127.0.0.1:8333 >/dev/null && echo OK   # adjust AGENTA_STORE_PORT if set
```

Then prove persistence end to end: run the agent once so it writes a session file, then run
it again and confirm the file is still there. A `503 Mount storage backend is not
configured` or a file that vanishes between runs means the store is missing or the
`AGENTA_STORE_*` vars are blank (troubleshoot.md entry 7).

## 6. Confirm the run executed where you chose

- **Local sandbox:** the run should complete and the runner logs should show it handled the
  run in-container, with no `/dev/fuse` or CLI-not-found error.
- **Daytona:** a healthy run creates a sandbox and tears it down. The sandbox count in your
  Daytona dashboard should return to 0 after the run finishes; a count stuck above 0 means
  sandboxes are leaking. Smoke test: https://docs.agenta.ai/self-host/agent-execution/daytona .

## 7. Remote only: published ports are loopback-bound

On a public host, confirm Postgres and the Traefik dashboard are not on the internet:

```bash
docker compose ps --format '{{.Service}}\t{{.Ports}}' | grep -E 'postgres|traefik'
```

Postgres (`5432`) and the dashboard (`8080`) must show `127.0.0.1:`, not `0.0.0.0:`. If they
show `0.0.0.0`, harden them (harden.md entry 1).

When all steps pass, the deployment works and an agent runs on it. Offer feedback
(send-feedback.md).
