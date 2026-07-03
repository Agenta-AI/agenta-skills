# What a schedule or subscription passes to the run

Read this when you create a schedule or a subscription and need to control the inputs the
agent receives on each fire — the optional `inputs_json` argument of `create-schedule.sh`
and `create-subscription.sh`.

## Contents

- The inputs template (`inputs_fields`)
- The context you can select from
- What a schedule fire looks like
- What a subscription fire looks like
- Practical templates for an agent

## The inputs template (`inputs_fields`)

Both trigger kinds carry an optional `inputs_fields` template. On each fire the platform
resolves it into the run's `data.inputs`:

- Every **leaf string starting with `$`** is resolved as a JSON Path against the fire's
  context (below). Leaf strings starting with `/` resolve as JSON Pointer.
- **Every other leaf is passed through literally** — plain strings, numbers, nested
  objects. There is no string interpolation: `"Summarize $.event.attributes"` stays that
  literal text; a selector must be the whole leaf.
- A selector that matches nothing resolves to `null` (no error).
- If you **omit** `inputs_fields`, the run receives the whole context object as its inputs.

## The context you can select from

```json
{
  "event":        { "event_id", "event_type", "timestamp", "created_at", "attributes" },
  "subscription": { "id", "name", "tags", "meta", "created_at", "updated_at" },
  "scope":        { "project_id" }
}
```

`subscription` holds the firing schedule's or subscription's own header fields (for a
schedule, its name and id — the key is still called `subscription`).

## What a schedule fire looks like

On a cron tick, `event` is synthetic:

- `event.event_id` — `"<schedule_id>:<tick ISO timestamp>"` (the dedup key).
- `event.event_type` — the `event_key` you gave `create-schedule.sh`.
- `event.attributes` — `{ "timestamp": "<tick ISO timestamp>" }`, nothing else.

So a schedule has no payload worth mapping; the useful part of the template is the literal
message you want the agent to receive.

## What a subscription fire looks like

On a provider event:

- `event.event_type` — the provider trigger slug.
- `event.attributes` — the provider's event payload (e.g. the GitHub issue, the Slack
  message). This is the part you map into the run.

## Practical templates for an agent

The agent workflow reads its task from `inputs.messages` (the same shape the invoke path
uses). A schedule that should run a fixed job every fire:

```json
{ "messages": [ { "role": "user", "content": "Run the daily digest now." } ] }
```

A subscription that should hand the agent the provider payload alongside a fixed
instruction (remember: no interpolation, so the payload rides as a sibling key):

```json
{
  "messages": [ { "role": "user", "content": "Triage the GitHub issue in inputs.event." } ],
  "event": "$.event.attributes"
}
```

If you pass no `inputs_json` at all, the agent receives the raw context object as inputs —
fine for a smoke test, but a real agent should get an explicit `messages` entry so the run
starts from an imperative instruction (see `writing-instructions.md`).
