---
name: self-host-agenta
description: Guided setup assistant for self-hosting open-source Agenta and running an agent on it. Use when the user wants to self-host Agenta, set up an Agenta agent on their own machine or server, run an agent locally, or says "help me self-host Agenta", "set up an agent", "self-host and run an agent". Walks the user through the decisions, executes against the OSS self-host docs, and ends with a working, tested agent.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash
user-invocable: true
---

# Self-host Agenta

You are helping a user stand up open-source Agenta and get a working agent running on it.
This is a guided setup, not a reference lookup. Walk them through it and **end with a
tested, working agent**. This skill covers the open-source edition; if EE (access control,
SSO, multi-org) comes up, say so and defer it.

The public OSS self-host docs at **https://docs.agenta.ai/self-host** are the source of
truth for every command. Link the page; do not restate its commands here. You already have
the repo, its `AGENTS.md`, and these docs. Infer the obvious. Do not re-explain what you can
read. Be concise.

## Workflow (follow in order)

1. **Understand, then propose a plan before doing anything.** In a few sentences, state
   your understanding of what they want and how you would set it up (local machine or
   remote server), and name the decisions you need from them. Do not run commands yet.

2. **Surface the decisions, then ask.** Each decision below gets one line of context and a
   sensible default. If your harness has a question/choice UI (an AskUserQuestion-style
   tool), use it so the user just picks. For a decision with a default, phrase it as
   "I'll default to X unless you want to change it." Do not dump every option as prose.
   Detail and per-decision doc links: [resources/decisions.md](resources/decisions.md).

3. **Get approval on the plan, then execute.** Follow the OSS docs for the actual commands
   (the routing table below). Work from a checked-out clone of
   https://github.com/Agenta-AI/agenta; `run.sh` resolves paths relative to its root.

4. **Test — mandatory, never skipped.** Once the stack is up, prove it works end to end:
   health check, sign up, create an agent, run a prompt and a tool call, confirm the run
   completes. If anything fails, troubleshoot and retry. Do not report success until the
   test passes. Steps: [resources/test.md](resources/test.md).

5. **Offer feedback.** At the end, or when something breaks, ask the user: "May I send
   anonymous setup feedback to help the Agenta team improve this?" Send only if they agree,
   and never send secrets. Thank them either way — the team is grateful.
   How: [resources/send-feedback.md](resources/send-feedback.md).

## The decisions (OSS)

Make these with the user in step 2. Full context and doc links in
[resources/decisions.md](resources/decisions.md).

- **Where** — local machine (default), or a remote server.
- **Model auth** — a managed provider API key (works anywhere, the default), or your own
  Claude/Codex subscription (local only).
- **Sandbox (where agent code runs)** — local (fast, shares the runner container, single
  trusted user; default for a first local setup), or Daytona (isolated per run, needs a
  Daytona API key).
- **Exposure** — only if remote: plain `IP:port`, or a domain with TLS.

## Routing table: "I want to X" -> OSS doc

| Goal | Page |
|---|---|
| First local deploy (port 80 or custom port) | https://docs.agenta.ai/self-host/quick-start |
| Where to start / what applies to me | https://docs.agenta.ai/self-host/overview |
| Every environment variable (incl. runner vars) | https://docs.agenta.ai/self-host/configuration |
| Network topology, ports, container DNS | https://docs.agenta.ai/self-host/infrastructure/networking |
| How the services fit together | https://docs.agenta.ai/self-host/infrastructure/architecture |
| Deploy on a remote server | https://docs.agenta.ai/self-host/guides/deploy-remotely |
| Put it behind a domain with TLS | https://docs.agenta.ai/self-host/guides/using-ssl |
| How a run reaches the runner | https://docs.agenta.ai/self-host/agent-execution/how-agents-run |
| Run agents with my own Claude/ChatGPT subscription | https://docs.agenta.ai/self-host/use-your-own-subscription |
| Run agents in a cloud sandbox (Daytona) | https://docs.agenta.ai/self-host/agent-execution/daytona |
| Run agents locally in the runner container | https://docs.agenta.ai/self-host/agent-execution/run-agents-locally |
| Which sandbox is safe for my deployment | https://docs.agenta.ai/self-host/agent-execution/sandbox-isolation-and-security |
| Add binaries, deps, or CPU to agent runs | https://docs.agenta.ai/self-host/agent-execution/customize-the-agent-runtime |

## Resources

- [resources/decisions.md](resources/decisions.md) — the questionnaire in depth: each
  decision, its context, default, what it changes, and the doc page with the how-to.
- [resources/test.md](resources/test.md) — the mandatory end-to-end test that proves the
  deployment and an agent actually work.
- [resources/troubleshoot.md](resources/troubleshoot.md) — field-verified failures keyed to
  the exact error text.
- [resources/harden.md](resources/harden.md) — OSS remote hardening, for a public host.
- [resources/send-feedback.md](resources/send-feedback.md) — how to send the optional,
  user-approved setup feedback. Public topic; never include secrets.

## Ground rules

- The docs are the source of truth. If a resource file and a doc disagree, the doc wins.
- Verify every command before handing it to the user; these run against a real deployment.
- Never print or send secrets (API keys, tokens, passwords, DB creds).
