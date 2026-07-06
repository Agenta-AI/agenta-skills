---
name: build-agent
description: >-
  Turn a plain-language request into a working, tested Agenta agent through the Agenta API.
  Use when the user wants to build, create, schedule, or test an Agenta agent from their
  coding agent (Claude Code, Codex, Cursor). Writes one config and runs a few bundled shell
  scripts. Triggers on "build an Agenta agent", "create an agent on Agenta", "schedule an
  Agenta agent", or wiring an agent to a tool like GitHub or Slack via Agenta.
---

# Build an Agenta agent

You turn a plain-language request into a working, tested agent on Agenta. You do it by
writing one JSON config and running a few bundled scripts. **Optimize for the fewest calls
and the least time.** The simplest agent is two steps: write the config, run `build.sh`.
Do not over-think simple asks.

Agenta is an open-source platform for building, testing, and deploying LLM apps and agents.
This skill builds Agenta *agents* over the Agenta HTTP API.

**Use this skill first.** Everything you need is in this folder: the playbook below and the
scripts in `scripts/`. These facts were confirmed against a live Agenta deployment. Do not
browse the web or the codebase by default. Only if you get truly stuck do the open-source
repo (`https://github.com/Agenta-AI/agenta`) and docs (`https://docs.agenta.ai`) exist as a
fallback; prefer what is written here.

## First run: credentials and prerequisites

Do these two things once, before any build.

**1. Credentials.** The scripts need `AGENTA_API_KEY`, and `AGENTA_HOST` only if the user
self-hosts (it defaults to Agenta cloud, `https://cloud.agenta.ai`).

- Ask the user for their API key. Point them to it: the **API keys** page in their Agenta
  project settings (on cloud, under `https://cloud.agenta.ai`). Ask for the host URL only if
  they self-host, in which case it is their own Agenta domain.
- Then offer to set it up for them, either way they prefer:
  - **Write it for them:** create a `.env` file in the working directory with
    `AGENTA_API_KEY=...` (and `AGENTA_HOST=...` if self-hosting). `lib.sh` picks up a local
    `.env` automatically.
  - **Hand them a block to paste:** give them the lines to `export`, or the `.env` contents
    to create themselves.
- Never print or commit the key. Add `.env` to `.gitignore` if the directory is a repo.

**2. Prerequisites.** Run `bash scripts/check-prereqs.sh`. It verifies `bash`, `curl`, and
`jq` are installed. On a miss it prints the exact install command for the user's platform;
show that to the user and ask them to install the tool, then continue.

## The shape of every agent

An agent is one JSON object, `parameters.agent`. You only ever decide four things inside it:
`instructions.agents_md` (who it is / what it does), `tools` (integration actions it can
call), `skills` (reusable know-how), and whether it needs a trigger (a schedule or an event).
The rest is fixed boilerplate — copy it exactly:

```json
{
  "instructions": { "agents_md": "<what the agent is and does>" },
  "llm": { "model": "sonnet", "provider": "anthropic", "connection": { "mode": "self_managed" } },
  "tools": [],
  "mcps": [],
  "skills": [],
  "harness": { "kind": "claude" },
  "runner": { "kind": "sidecar", "interactions": { "headless": "auto" } },
  "sandbox": { "kind": "local" }
}
```

Keep `llm` / `harness` / `runner` / `sandbox` exactly as above unless told otherwise. `model`
is an alias (`sonnet`, `opus`, `haiku`, `default`), never a raw model id. For the full config
field by field — tool entries, skill entries, and the fields that 500 if misplaced — read
`references/config-schema.md`.

## The loop (run it in order, skip what the ask doesn't need)

1. **Read the ask. Decide what it needs** using the decision table below. Most asks need only
   instructions. Do not discover tools or triggers an ask does not call for.
2. **If it needs integration actions, discover them** with `bash scripts/discover-tools.sh
   "<capability>"`. This prints the exact `tools` entries and each connection's state. Detail:
   `references/tools-and-connections.md`.
3. **If a needed connection is not `ready`, STOP and ask the user to connect it.** Do not
   guess, do not fabricate a result. Report which integration needs connecting and why, then
   stop. That is a correct, complete outcome, not a failure.
4. **Write the config** to a file under `configs/`. Integration actions go in `tools`,
   reusable know-how in `skills`, the behavior in `instructions.agents_md`. For a multi-tool
   or scheduled agent, write `instructions.agents_md` as an explicit numbered procedure that
   names the exact tools in order and ends on the terminal action — otherwise the run wanders
   or stops short. Depth in `references/writing-instructions.md`.
5. **Create and test in one shot:** `bash scripts/build.sh <config> <slug> "<test message>"`.
   Read the OUTPUT and RESOLVED lines. RESOLVED must show
   `harness=claude model=sonnet connection=self_managed`.
6. **If it needs a trigger**, create it against the variant id AND the revision id (both
   printed by `create-agent.sh` / `build.sh`) — a schedule with `bash scripts/create-schedule.sh`,
   an event subscription with `bash scripts/create-subscription.sh` (only after
   `discover-triggers.sh` and a `ready` connection). Passing the revision id is required: without
   it the trigger has no bound version to run, which the Agenta UI treats as an error. Pass the
   literal word `latest` in place of a revision id if you only have the variant id at hand.
   Confirm with `bash scripts/triggers.sh schedules` (or `subscriptions`).
7. **Report** in a short bullet list: what you built, the artifact ids, what you tested, the
   result, and anything that needs the user.

## Decision table

| The ask… | Needs | What to add |
|---|---|---|
| transform text the user pastes (summarize, rewrite, classify) | nothing extra | `instructions` only |
| apply a body of know-how (a writing style, a review rubric) | a skill | one `skills` entry |
| read or write in an outside tool (GitHub, Slack, …) | gateway tools | `discover-tools.sh`, then `tools` entries |
| run on a clock (e.g. twice a day) | a schedule | build the agent, then `create-schedule.sh` |
| react to an outside event (new issue, new message) | a subscription | `discover-triggers.sh`, then `create-subscription.sh` (needs a ready connection) |
| change an agent that already exists | a new revision | `update-agent.sh` against the variant id, then re-test |

## Scripts (your only interface to the API)

Run them as `bash scripts/<name>` from this skill's directory. They wrap real Agenta
endpoints and load credentials themselves — you never handle the API key.

- `check-prereqs.sh` — verify `bash`/`curl`/`jq` before you start.
- `build.sh <config.json> <slug> "<msg>" [name]` — create the agent AND test it. The fast path.
- `create-agent.sh <config.json> <slug> [name]` — create only; prints `application_id` /
  `variant_id` / `revision_id`. Use when you need the variant id before scheduling.
- `test-agent.sh <application_id> <config.json> "<msg>"` — batch invoke + verify. A single
  non-streaming call returns the full real turn, so it prints OUTPUT (the last assistant
  message), a `TOOLS:` line (every tool called, in order, with call/result counts), an
  `APPROVAL:` line when the run paused on an approval gate, RESOLVED (the config the run
  actually used), and the TRACE id.
- `discover-tools.sh "<capability>" ...` — find gateway tools for plain-language actions; shows
  each connection's state and the ready-to-wire tool object.
- `discover-triggers.sh "<event>" ...` — find event triggers (for subscriptions only).
- `update-agent.sh <variant_id> <config.json> [message]` — commit a new config to an EXISTING
  agent. Prefer this over archive-and-recreate: the slug, the ids, and any triggers survive.
- `create-schedule.sh <variant_id> <revision_id> "<cron UTC>" <event_key> [name] [inputs_json]`
  — cron trigger. The revision id (from `create-agent.sh` / `build.sh`) pins which committed
  version runs; omitting it leaves the schedule with no bound revision. Pass `latest` instead
  of a real id to have the script look up the variant's current HEAD revision for you.
- `create-subscription.sh <variant_id> <revision_id> <event_key> <connection> [name]
  [trigger_config_json] [inputs_json]` — event trigger. Same revision-id requirement (and
  `latest` shortcut) as `create-schedule.sh`. The connection (id or slug) must be `ready`
  first; verify actual fires with `triggers.sh deliveries`.
- `triggers.sh schedules|subscriptions|deliveries|rm-schedule <id>|rm-subscription <id>`.
- `check-tools.sh <trace_id> [terminal_tool]` — OPTIONAL fallback. `test-agent.sh` already lists
  the tools a run called (its `TOOLS:` line). Reach for this only to confirm a gated WRITE
  actually returned `ok:true` — pass the terminal tool for a PASS/INCOMPLETE verdict from the
  trace spans.
- `archive-agent.sh <application_id>` — soft-delete an app; use it to clean up or free a slug.

Two extras live in `scripts/extras/` and stay out of the loop: `list-connections.sh`
(discover already prints the CONNECTIONS block; see `references/tools-and-connections.md`)
and `annotate-trace.sh` (an experimenter demo; see `references/annotate-trace.md`).

## Deeper topics (read on demand)

Keep to the loop above for a simple agent. Read one of these only when the task calls for it.

| To do this | Read |
|---|---|
| Understand the full agent config field by field | `references/config-schema.md` |
| Discover tools, wire a connection, add an event trigger | `references/tools-and-connections.md` |
| Write instructions for a multi-tool or scheduled agent | `references/writing-instructions.md` |
| Shape the inputs a schedule or subscription passes to the run | `references/trigger-inputs.md` |
| Record a reflection against a trace | `references/annotate-trace.md` |

## Hard rules (these prevent the usual failures)

- **A trigger needs the revision id, not just the variant id.** `create-schedule.sh` and
  `create-subscription.sh` both take `<variant_id> <revision_id> ...` — pass both (printed by
  `create-agent.sh` / `build.sh`), or pass `latest` in place of the revision id if you only have
  the variant id at hand. Omitting the revision id creates a trigger with no bound version,
  which the Agenta UI treats as an error ("Which version runs?" required, unset).
- **Fewest calls.** A no-tools agent is exactly two actions: write the config, run `build.sh`.
  Don't re-list, don't re-verify facts already given here, don't re-read the schema.
- **Test before you declare done.** A claim with no `build.sh` / `test-agent.sh` behind it does
  not count. Check OUTPUT is right and RESOLVED shows the intended config.
- **Write the persona as an explicit imperative.** The agent is Claude Code underneath; on
  ambiguous input it falls back to a generic coding-assistant persona instead of doing the job.
  Author `instructions.agents_md` as an explicit imperative — who the agent is and what it does,
  stated as a command, not a vague topic. (Likewise phrase a one-off test with a verb:
  `"Summarize the following text:\n\n<text>"`, not a bare `<text>`, so the test isn't read as a
  chat opener.)
- **Crons are UTC, five fields, one-minute floor.** Convert the user's local time yourself.
- **needs_auth means stop.** If a needed connection is not `ready`, stop and ask the user to
  connect it. That is the whole job for that step.
- **Discovery is a search, not an oracle.** `discover-tools.sh` / `discover-triggers.sh` return
  high-recall best guesses over the live catalog. The matched **connection state** is reliable;
  the matched **integration and action** are not always right. A search matches on words: "save
  notes to Notion" can match Slack's `SEARCH_MESSAGES` as the primary tool and still print
  `READY: true` — while the Notion action you wanted is buried in `alternatives` and its
  connection is `needs_auth`. So: **confirm the matched tool's `integration` is the one you
  asked for**, and treat the per-integration `CONNECTIONS:` block (not the headline `READY`
  line) as the source of truth. If the match looks off, re-word the fragment or pick from the
  alternatives — a search for "new telegram message" can return a Slack event the same way.
- **Change an existing agent by committing, not recreating.** `update-agent.sh <variant_id>
  <config.json>` commits a new revision to the same app; the slug, the ids, and any schedules
  or subscriptions keep working. Archive-and-recreate loses all of them. Re-test after the
  update with `test-agent.sh`.
- **A failed build still creates the app.** If `build.sh` creates the app but the invoke fails,
  the app (and its slug) already exist. Fix the config and re-test with `test-agent.sh` against
  the existing `application_id` — do NOT re-run `build.sh` with the same slug (it conflicts).
  For a clean retry, `archive-agent.sh <application_id>` first.
- **Invoke carries the config inline (a lab artifact, not a gap).** `build.sh` and
  `test-agent.sh` inline the full config on every invoke against the low-level agent-service
  endpoint, which does not hydrate a committed reference. That part is unrelated to the
  endpoint/auth/body-shape contract itself, which is settled — see
  `docs/designs/invoke-negotiations/specs.md` in the `agenta` repo. The product API invoke path
  loads a committed reference server-side, so bare-reference invoke is a real product feature;
  this kit still doesn't use that path, and there's no need to rewrite the scripts to invoke by
  bare reference.
- **Report short.** A few bullets. Lead with the result and the artifact ids.

## Verify (don't trust a 200)

`test-agent.sh` sends a non-streaming invoke (`Accept: application/json`). The response's
`data.outputs` carries the run's full real turn, not just a final string: `messages` (assistant
text plus a `role: "tool"` entry for every tool call and result, in order), `stop_reason`, and —
only when the run paused on an approval gate — `pending_interaction`. The script reads this
directly, so OUTPUT / TOOLS / APPROVAL below come straight off the invoke response, no trace
needed. (Endpoint, auth, body shape, and this response contract are settled — see
`docs/designs/invoke-negotiations/specs.md` in the `agenta` repo. The script sends no extra
headers, so it gets the defaults: full transcript, resolved workflow embeds.)

`test-agent.sh` also prints RESOLVED from the run's trace. It must match what you intended. If
it shows a different harness/model, the run silently fell back — fix the config and re-test.
Traces flush a second or two late; the script already retries.

**Multi-tool agents — read the `TOOLS:` line, not just OUTPUT.** A run that makes several tool
calls can end on its tool-call turn, so OUTPUT (the last assistant message) is genuinely EMPTY —
that is not a failure or a parsing gap, it means the run's last turn was a tool call rather than
a reply. `test-agent.sh`'s `TOOLS:` line lists every tool the run CALLED, in order, with each
result's ok/ERROR (e.g. `github__LIST_COMMITS -> ok -> slack__SEND_MESSAGE -> ok (2 calls, 2
results)`). That line is your reliable "did it reach the terminal tool, and did that tool return
ok" signal. If the terminal tool is in the list with an ok result, the run got there and
finished; if it's missing, the run STOPPED SHORT (did the early reads, then wandered and never
reached the final action). If it stopped short, re-test with a blunter, numbered instruction —
the config is usually fine, the run just wandered. See `references/writing-instructions.md`.

`test-agent.sh` prints an `APPROVAL:` line when `stop_reason == "paused"` — a WRITE (like
`SEND_MESSAGE`) tripped a human-approval gate. The run stopped there: that tool's call is in
TOOLS, but it has no matching result yet, because the run paused before executing it. The write
may not complete within this invoke at all (the approval can go unresolved).

`check-tools.sh` is the **fallback** for what this invoke can't show yet: whether a gated tool
actually RETURNED after the fact. It reads the trace spans — a tool's span appears as soon as it
is CALLED, but only carries a result once it actually returned. So `bash scripts/check-tools.sh
<trace_id> SEND_MESSAGE` prints `VERDICT: PASS` only when that tool ran AND returned a result;
`UNCONFIRMED` when the tool was dispatched but its span has no result (the classic
stalled-approval signature); and `INCOMPLETE` when it never ran. **A tool NAME appearing in the
executed list is NOT proof it completed** — a gated write can sit in the list with no result. And
for an external WRITE, even a returned result is only truly confirmed by reading the side effect
back (e.g. fetch the channel history). That read-back is the one certain check.
