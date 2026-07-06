# Recording a reflection against a trace

Read this when you want to attach a note or reflection to an agent's traces — for a demo of
self-review, or to leave a comment on a run for a human to see later.

## Contents

- What it does
- How to run it
- The current limitation

## What it does

`annotate-trace.sh` records a reflection (an annotation) against an application's traces
through `POST /api/annotations/`. The note is stored on the run and shows up alongside the
trace in Agenta.

## How to run it

```bash
bash scripts/extras/annotate-trace.sh <application_id> "<note>"
```

The script lives in `scripts/extras/` (not the core loop): it is an experimenter demo, not
something the build loop calls.

It prints the created annotation's span id and the note text. Get the `application_id` from
`create-agent.sh` / `build.sh`, and get a trace id from `test-agent.sh` if you want to point a
human at the specific run the note is about.

## The current limitation

This script drives the public HTTP API from outside a run: you supply an `application_id`
and a note yourself, from your terminal, about a run you already tested. That is still why it
lives in `scripts/extras/` — there is no public-API equivalent bound to "your own current
trace," so it stays an experimenter and demo tool for out-of-run annotation.

That said, an agent built and run **on** the Agenta platform (with the default build kit) can
self-annotate at runtime: it has an `annotate_trace` platform op that targets its own current
trace and span automatically. The agent supplies only `references.evaluator.slug` (the
annotation category, e.g. `self_reflection`) and `data.outputs` (the scores, labels, or notes);
a new slug auto-creates a simple evaluator. Write instructions that call that op when you want
an agent to grade itself as part of a run — reach for this script only when you, a human, want
to attach a note from outside a run.
