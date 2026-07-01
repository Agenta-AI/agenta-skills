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
bash scripts/annotate-trace.sh <application_id> "<note>"
```

It prints the created annotation's span id and the note text. Get the `application_id` from
`create-agent.sh` / `build.sh`, and get a trace id from `test-agent.sh` if you want to point a
human at the specific run the note is about.

## The current limitation

There is no agent-callable platform operation for this yet, so this is an experimenter and
demo tool. A self-reflecting **agent** cannot call it autonomously today — you run it yourself,
from your terminal, about a run you just tested. Do not build an agent whose instructions tell
it to annotate its own traces; that path does not exist yet.
