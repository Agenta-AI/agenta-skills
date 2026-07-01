# The agent config, field by field

The full shape of `parameters.agent`, the one JSON object that defines an agent. Read this
when a plain instruction is not enough — when the agent needs tools, needs skills, or when a
create call returns a 500 and you need to check the shape.

## Contents

- The whole object
- The four fields you decide
- The fixed boilerplate (copy exactly)
- A tool entry (gateway object)
- A skill entry (name / description / body / files)
- Folders and files inside a skill
- Fields that 500 if misplaced

## The whole object

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

## The four fields you decide

- `instructions.agents_md` — a Markdown string. Who the agent is and what it does. For a
  simple agent this is one or two sentences. For a multi-tool or scheduled agent it must be an
  explicit numbered procedure (see `writing-instructions.md`).
- `tools` — the integration actions the agent may call. Each entry is a gateway object (below).
  Empty for an agent that only transforms text.
- `skills` — reusable know-how bundled with the agent. Each entry is a skill template (below).
  Empty unless the agent applies a body of know-how (a writing style, a review rubric).
- Whether it needs a **trigger** — a schedule (cron) or an event subscription. This is not a
  field in `parameters.agent`; it is a separate object you create after the agent exists
  (`create-schedule.sh`, or a subscription — see `tools-and-connections.md`).

## The fixed boilerplate (copy exactly)

Keep `llm`, `mcps`, `harness`, `runner`, and `sandbox` exactly as in the template unless the
user asks otherwise.

- `llm.model` is an **alias** — `sonnet`, `opus`, `haiku`, or `default` — never a raw model id.
- `llm.provider` is `anthropic` and `llm.connection.mode` is `self_managed` in the default
  setup.
- `harness.kind` is `claude`. `runner.kind` is `sidecar`. `sandbox.kind` is `local`.

RESOLVED (printed by `test-agent.sh`) must echo these back:
`harness=claude model=sonnet connection=self_managed`. If it does not, the run fell back to a
default — fix the config and re-test.

## A tool entry (gateway object)

A `tools` entry is a gateway object. Do not hand-write it: run `discover-tools.sh` and copy
what it prints, then add the `connection` slug when the connection is `ready`.

```json
{ "type": "gateway", "provider": "composio", "integration": "github",
  "action": "GET_THE_AUTHENTICATED_USER", "connection": "github-08f" }
```

See `tools-and-connections.md` for how discovery and connection state work.

## A skill entry (name / description / body / files)

A `skills` entry is a skill template. Three fields are **required** — `name` (kebab-case),
`description`, `body` (the SKILL.md Markdown) — and three are optional: `files`,
`disable_model_invocation`, `allow_executable_files`.

```json
{ "name": "clear-writing",
  "description": "When to use this skill (one line).",
  "body": "# Title\n\nThe know-how the agent applies, in Markdown.",
  "files": [
    { "path": "references/checklist.md", "content": "# Checklist\n..." },
    { "path": "scripts/lint.py", "content": "#!/usr/bin/env python3\n...", "executable": true }
  ]
}
```

## Folders and files inside a skill

A skill can carry folders and files. Each `files` item is `{ path, content, executable? }`,
where `path` is a relative POSIX path (no leading `/`, no `..`, and not `SKILL.md`). A folder
is just `/`-separated segments in the path (`references/checklist.md`); there is no separate
folder object. The runner materializes them into a directory next to `SKILL.md`, so the body
can reference them by relative path. Most skills need only `name` / `description` / `body`;
reach for `files` when the skill ships a reference doc, a template, or a helper script.

## Fields that 500 if misplaced

- `slug` and `content` are **not** top-level fields on a skill entry. Putting them there
  returns a 500. The skill body goes in `body`; a file's text goes in that file's `content`
  inside a `files` item.
- Keep the boilerplate blocks present. Dropping `runner`, `harness`, or `sandbox` can make the
  run fall back to a default configuration.
