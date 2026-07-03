# Writing instructions for multi-tool and scheduled agents

Read this when the agent chains several tools (fetch, then fetch, then post) or runs on a
schedule. This is the hard part of the job. A one-tool agent (summarize, look up a username)
just needs a plain instruction and does not need this file.

## Contents

- Why a vague instruction fails
- Write a numbered procedure
- Pin concrete ids
- End on the side effect
- When a run stops short

## Why a vague instruction fails

An agent that has to chain several tools needs MORE than "write a digest and post it". With a
vague instruction it tends to do the early reads and then wander or stop before the final
action. The fix is to remove the agent's freedom on the fragile path: spell out the steps.

## Write a numbered procedure

Write `instructions.agents_md` as an explicit, numbered procedure that names the exact tools
in order and ends with the terminal action:

> "Every run, do exactly these steps and nothing else: (1) call LIST_REPOSITORY_ISSUES for
> owner/repo X; (2) call LIST_COMMITS for X; (3) write a 3-bullet digest; (4) call SEND_MESSAGE
> to channel C0XXXX with that digest. Do not check triggers, do not stop before step 4."

## Pin concrete ids

Hard-code the channel id, repo, and any other identifier in the instructions, especially for a
scheduled agent. If you tell it to "pick a channel" it will list and re-choose on every fire,
which is fragile. Resolve the id once (for example with `discover-tools.sh` or a
LIST_ALL_CHANNELS action) and write that id into the instruction.

## End on the side effect

Make the last numbered step the terminal tool (the post, the write), and say explicitly
"finish by doing step N". The terminal action is the whole point of the run; do not let the
instruction trail off after the reads.

## Prefer narrow, filtered tools over big list dumps

A tool that returns a huge payload (e.g. Slack `LIST_ALL_CHANNELS`, which can return ~200 KB) tends
to make the agent reach for a shell/code tool (`python3`, `jq`) to sift the result — which trips a
*separate* code-execution approval gate and derails the run, even when the instructions forbid it.
Pick the narrowest action that answers the question: `FIND_CHANNELS` (server-side filtered) instead
of `LIST_ALL_CHANNELS`; a single `GET_AN_ISSUE` when you know the number instead of
`LIST_REPOSITORY_ISSUES`. Resolve an id once with a filtered action, pin the result into the
instruction, and keep each run's tool payloads small.

## When a run stops short

A multi-tool run can finish with no errors yet never reach the final action — it does the early
reads, then wanders (into its own builtin tools, or "let me check the triggers…") and stops.
Read `test-agent.sh`'s `TOOLS:` line: if the terminal tool is in the ordered list, the run got
there; if it's missing, the run stopped short. (Only to confirm a gated WRITE actually returned
`ok:true` do you need `check-tools.sh <trace_id> <TERMINAL_TOOL>` — see the Verify section of
`SKILL.md`.) If it stopped short, the config is usually fine — the run just wandered. Re-test
with a blunter, more explicit numbered instruction using the rules above.
