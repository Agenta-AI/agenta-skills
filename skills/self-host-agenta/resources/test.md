# Test the deployment

Testing has levels. Always run the sanity check. Then ask the user whether they want to go
further, and tell them the rough time cost so they can choose. Do not run the deeper tests without
asking.

If a step fails, go to troubleshoot.md, fix, and rerun. Replace `localhost` with the host and adjust
the port if you changed `TRAEFIK_PORT`.

## Sanity check (always run, about a minute)

This proves the stack is alive. Run all three.

### 1. API health -> 200

The API mounts under `/api`, so through Traefik the health route is `/api/health`:

```bash
curl -fsS http://localhost/api/health && echo OK
```

A 200 JSON body means the API and its DB migrations are up. A 404 usually means the web/API URL env
vars are wrong for the port you deployed on (quick-start's custom-port section).

### 2. Runner reachable from the API container

The API reaches the runner over the internal network at `http://runner:8765`:

```bash
docker compose exec api curl -fsS http://runner:8765/health
```

It returns the runner identity (`status`, `runner`, `protocol`, `engines`, `harnesses`). If this
fails while the runner container is up, `AGENTA_RUNNER_INTERNAL_URL` is wrong or blank
(troubleshoot.md entry 1). A bad provider list or a Daytona provider with no credential fails runner
startup; check `docker compose logs runner | grep '\[sandbox-agent\]'` for the redacted config
summary and `http server listening on 0.0.0.0:8765`.

### 3. Sign up and reach the studio

Open `http://localhost` (or your host URL) in a browser, sign up, and land in the studio. The first
account gets its own organization. If sign-up loops or redirects to `http://` behind a proxy, that is
the forwarded-header case (troubleshoot.md entry 2).

On a remote host, also confirm published ports are loopback-bound (see "Remote only" below).

## Ask before going further

Once the sanity check passes, ask the user which they want:

- **Nothing more.** The stack is up and reachable.
- **A quick functional check (a few minutes).** Run one prompt through an agent (level 1 below).
- **A full end-to-end check (about 15 to 20 minutes).** Every agent feature: a tool call, durable
  mounts, and where the run executed (levels 1 to 3 below).

## Level 1: run a prompt

Through the studio UI (or the API):

1. Create an agent. Give it an instruction.
2. Run a plain prompt. Confirm the agent responds.

If model auth fails, revisit decision 2 (managed key vs subscription; a subscription on a non-1000
host needs the uid override, troubleshoot.md entry 3). If a run fails with a `401` from the runner or
`AGENTA_RUNNER_TOKEN is required`, the token is unset or mismatched (troubleshoot.md entry 6). To
build the agent itself, the `build-agent` skill drives this over the API.

## Level 2: tool call and durable mounts

1. Enable one tool on the agent and run a prompt that exercises it. Confirm the tool call happens and
   the run finishes without error.
2. Confirm the object store is healthy, then prove persistence: run the agent so it writes a session
   file, run it again, and confirm the file is still there.

```bash
docker compose ps seaweedfs                              # State should be "healthy"
curl -fsS http://127.0.0.1:8333 >/dev/null && echo OK    # adjust AGENTA_STORE_PORT if set
```

A `503 Mount storage backend is not configured` or a file that vanishes between runs means the store
is missing or the `AGENTA_STORE_*` vars are blank (troubleshoot.md entry 7).

## Level 3: confirm the run executed where you chose

- **Local sandbox:** the run completes and the runner logs show it handled the run in-container, with
  no `/dev/fuse` or CLI-not-found error.
- **Daytona:** a healthy run creates a sandbox and tears it down. The sandbox count in your Daytona
  dashboard returns to 0 after the run; a count stuck above 0 means sandboxes are leaking. If files
  vanish between turns and the runner logs `mount degraded`, the store is not reachable from the
  cloud sandbox (troubleshoot.md entry 9). Smoke test:
  https://docs.agenta.ai/self-host/agent-execution/daytona .

## Remote only: published ports are loopback-bound

On a public host, confirm Postgres and the Traefik dashboard are not on the internet:

```bash
docker compose ps --format '{{.Service}}\t{{.Ports}}' | grep -E 'postgres|traefik'
```

Postgres (`5432`) and the dashboard (`8080`) must show `127.0.0.1:`, not `0.0.0.0:`. If they show
`0.0.0.0`, harden them (harden.md entry 1).

When the chosen level passes, offer feedback (send-feedback.md).
