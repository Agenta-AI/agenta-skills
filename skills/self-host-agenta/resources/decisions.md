# The setup questionnaire (OSS)

Five decisions shape the whole setup. Give the user one line of context and the default for
each, then ask (use your harness's question UI if it has one). Decision 4 applies to remote
setups only, and decision 5 only if their agents will use MCP servers. Do not restate the
commands the docs already carry — link the page.

## 1. Where does it run?

- **Local machine** *(default)* — one Docker host, reached at `http://localhost`. Fastest
  path to a working agent. No hardening needed on a private machine.
- **Remote server** — a VPS or cloud box others can reach. Adds the exposure decision (4)
  and hardening. How-to: https://docs.agenta.ai/self-host/guides/deploy-remotely .

What it changes: the URL env vars and whether you harden. A public host means you must
harden (resources/harden.md).

## 2. Model authentication — how the agent reaches an LLM

- **Managed provider API key** *(default)* — an Anthropic / OpenAI key set in Agenta.
  Works local or remote. The normal choice.
- **Your own Claude / Codex subscription** — reuse a personal Claude Code or ChatGPT login
  instead of a metered key. **Local only:** it mounts your login into the runner container,
  so it does not apply to a shared remote host. How-to:
  https://docs.agenta.ai/self-host/use-your-own-subscription .

What it changes: where the model credential comes from. The subscription path has a
uid-1000 mount gotcha (troubleshoot.md entry 3).

## 3. Sandbox — where the agent's code actually runs

This is the safety decision, and it is central: the whole point is running an agent.

- **Local** *(default for a first local setup)* — the agent runs inside the runner
  container. Fast, no extra credentials, but not isolated: runs share the container and its
  mounted credentials. Fine for a single trusted user. How-to:
  https://docs.agenta.ai/self-host/agent-execution/run-agents-locally .
- **Daytona** — each run executes in its own cloud sandbox, isolated from the host and from
  other runs. Needs a Daytona API key and a one-time snapshot build
  (`agenta-agent-sandbox-v1`). Use it whenever more than one person can start runs. How-to:
  https://docs.agenta.ai/self-host/agent-execution/daytona .

What it changes: `AGENTA_RUNNER_DAYTONA_*` variables and the snapshot. Daytona also needs
the durable store published on a public endpoint, since the cloud sandbox reaches it over the
internet; a store bound to loopback leaves agent files lost silently (troubleshoot.md entry
9). Full trade-off:
https://docs.agenta.ai/self-host/agent-execution/sandbox-isolation-and-security .

Rule: single trusted operator -> local is fine. Anyone else can reach it -> Daytona.

## 4. Exposure (remote only) — how the outside reaches the stack

- **Plain `IP:port`** — Traefik publishes on port 80 (`TRAEFIK_PORT` to change). Set the
  URL env vars to your host. A public IP means you must harden (resources/harden.md).
- **Domain with TLS** — terminate TLS with the SSL stage or a proxy in front. How-to:
  https://docs.agenta.ai/self-host/guides/using-ssl .

What it changes: the URL env vars, and whether requests come through a proxy. A proxy in
front is the case that produces `http://` redirects unless you set the forwarded-header vars
(troubleshoot.md entry 2).

## 5. MCP servers — where they live, and who may connect one

Only if their agents will use MCP servers. Ask it before they connect the first one; the
symptom otherwise reads as a broken MCP server (troubleshoot.md entry 15).

How it works. Give the user this much before asking. From Agenta 0.119.0 an agent no longer
dials an MCP server from its own sandbox. The `api` container relays every MCP call, so the
server's credential stays on the deployment instead of traveling into the sandbox. The relay
has its own outbound guard, and that guard is what decides which MCP servers the agents can
reach: by default it requires https and refuses any address that resolves inside a private or
otherwise internal range.

Then ask two things: will your agents use MCP servers on your own network or served over
plain HTTP, and will people you do not trust be able to connect MCP servers on this
deployment?

- **Permissive** *(what the env templates ship from 0.119.0)* — keep
  `AGENTA_GATEWAYS_INSECURE_EGRESS_ALLOWED=true` and
  `AGENTA_GATEWAYS_INSECURE_HTTP_ALLOWED=true`. The relay reaches an MCP server on the LAN or
  on a plain-HTTP address, which is how a self-hosted MCP server usually looks. Right for a
  deployment only the operator and people they trust can use.
- **Strict, plus an allowlist** — set `AGENTA_GATEWAYS_INSECURE_EGRESS_ALLOWED=false` and name
  the internal servers you do trust in `AGENTA_MCP_GATEWAY_HOST_ALLOWLIST`. Right when people
  you do not vet can connect MCP servers here, because an open guard lets a connection someone
  else creates reach any address the API container can reach, including addresses inside your
  network. Recipe: harden.md entry 4.

State that trade-off once and let them pick. Do not argue for HTTPS: on their own network it
is their call.

What it changes: `AGENTA_GATEWAYS_INSECURE_EGRESS_ALLOWED` and
`AGENTA_MCP_GATEWAY_HOST_ALLOWLIST` are read by the `api` container and govern what the relay
may call. `AGENTA_GATEWAYS_INSECURE_HTTP_ALLOWED` is read by `services` and `runner` and
governs the other direction, the hop back into Agenta: it lets the gateway credential travel
when the Agenta deployment itself is served over plain HTTP. A deployment upgraded from an
earlier version keeps its old env file, which carries neither line, so it gets the strict
behavior until they are added (troubleshoot.md entry 15). Full reference:
https://docs.agenta.ai/self-host/configuration .
