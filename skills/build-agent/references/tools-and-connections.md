# Tools, connections, and event triggers

Read this when the agent needs to read or write in an outside tool (GitHub, Slack, and so on),
or when it should react to an outside event. For a schedule (a clock), you do not need any of
this — go straight to `create-schedule.sh`.

## Contents

- Discover the tools an ask needs
- Read the connection state
- needs_auth means stop
- Discovery is a search, not an oracle
- Wire the tool into the config
- Event triggers (subscriptions)
- List what is already connected

## Discover the tools an ask needs

Run one short action fragment per capability:

```bash
bash scripts/discover-tools.sh "post a message to a slack channel" "list issues in a repo"
```

For each capability it prints the ready-to-wire gateway tool
(`provider` / `integration` / `action` / `connection`), the connection's state, and any
alternative actions. It ends with a one-line readiness verdict and the project's connections.

## Read the connection state

Each capability reports a connection `state`. Only `ready` means you can wire and run the tool.
Any other state (for example `needs_auth`) means the integration is not connected for this
project yet.

**The per-capability `state` and the `CONNECTIONS:` block are authoritative — the headline
`READY (all primary connections ready)` line is not.** `READY: true` only means the connection
of whatever tool got matched as *primary* is ready; if discovery matched the wrong integration
(it matches on words — see "Discovery is a search" below), `READY` can say `true` while the
integration you actually asked for is `needs_auth`. Always confirm the matched tool's
`integration` is the one you wanted, and read the `CONNECTIONS:` block for that integration's
real state, before you trust the headline.

## needs_auth means stop

If a needed connection is not `ready`, **stop**. Do not guess a connection slug, do not
fabricate a result, do not pretend it is connected. Report exactly which integration needs
connecting and why, then stop and ask the user to connect it in Agenta. That is a correct,
complete outcome for that step, not a failure.

## Discovery is a search, not an oracle

`discover-tools.sh` and `discover-triggers.sh` return high-recall best guesses over the live
catalog. The matched **integration** and **connection state** are reliable; the matched
**action / event** is not always right. Always confirm the chosen action is actually what you
want before wiring it. If it looks off, re-word the fragment or pick from the alternatives.

Real example: a search for "new telegram message" can return a **Slack** event, because it
matched on the word "message". Confirm both the integration AND the action.

## Wire the tool into the config

When the connection is `ready`, drop the printed `tool` object straight into
`parameters.agent.tools`, and set its `connection` to the ready connection's slug:

```json
{ "type": "gateway", "provider": "composio", "integration": "github",
  "action": "GET_THE_AUTHENTICATED_USER", "connection": "<connection-slug>" }
```

Use the exact `connection` slug that `discover-tools.sh` printed for *your* project — do not
copy the placeholder above, and do not copy a slug out of these docs. A project can have **more
than one connection for the same integration** (e.g. two GitHub connections). `discover-tools.sh`
picks one and prints its slug; if you need a specific one, run `list-connections.sh` to see all
of them and set the slug you want.

An agent that chains several tools needs an explicit numbered instruction that names those
tools in order and ends on the terminal action — see `writing-instructions.md`.

## Event triggers (subscriptions)

An agent that reacts to an outside event (a new issue, a new message) needs a **subscription**,
which needs a `ready` connection. Discover the event first:

```bash
bash scripts/discover-triggers.sh "new github issue opened" "new telegram message received"
```

It prints, per fragment, the `event_key`, the connection state, and the `trigger_config`
schema hint. This is for EVENT subscriptions only. A time-based schedule (cron) does NOT use
this path — use `create-schedule.sh` directly.

## List what is already connected

```bash
bash scripts/list-connections.sh
```

One line per connection: integration, slug, and whether it is valid and active. Use it to find
the slug for a connection you already know is `ready`.
