# Contributing to agenta-skills

This documents the process for testing skills in this repo (starting with `build-agent`),
filing bugs, and proposing fixes. It reflects what actually worked across a real QA pass on
`build-agent` (issues #3-#8, PRs #9-#17) — not a theoretical process.

## Testing a skill

1. Install in an isolated folder with no prior Agenta codebase context, so you're testing what
   a real user would experience, not what you already know:
   ```
   npx skills add Agenta-AI/agenta-skills
   ```
2. Set credentials the skill itself asks for (see the skill's own `SKILL.md` for the exact
   variables — for `build-agent`, `AGENTA_API_KEY` and `AGENTA_API_URL`). Test against a real
   deployment, not just cloud defaults, if the change you're testing is self-host-specific.
3. Run real use cases through the skill from a coding agent session (Claude Code, Codex),
   using plain-language prompts a real user would type. Don't hand-write the config yourself
   first — that's testing your own understanding, not the skill's.
4. **Verify, don't trust a clean-looking transcript.** A skill's own scripts print
   verification lines for a reason — read them:
   - `RESOLVED` must show the harness/model/connection you actually intended, not a silent
     fallback.
   - `TOOLS` must show every expected tool call reached the terminal action, not stopped
     short.
   - For a gated WRITE (an approval-required tool call), a name appearing in `TOOLS` is not
     proof it completed — use `check-tools.sh` (or the skill's equivalent) to confirm the
     tool actually returned a result, and where possible, read the real side effect back
     (fetch the Slack channel, check the Gmail draft) rather than trusting the trace alone.
   - If a run stalls on an approval gate through a low-level test script, that's often not
     "slow", it's a session that has nothing to approve against and will never resolve. Test
     writes either through a real session, or with an explicit, documented testing-only
     bypass (see `harness.permissions.default_mode` in `skills/build-agent/SKILL.md`) — never
     silently.
5. Clean up what you created (`archive-agent.sh`, remove test schedules/subscriptions)
   before moving to the next test.

## Filing a bug

- **One GitHub issue per distinct bug.** Bundling unrelated bugs into one issue makes review
  and fixing harder for everyone, and was called out explicitly in review more than once.
- **Reproduce it yourself before filing.** A bug relayed secondhand (a screenshot, a
  paraphrase) is a lead, not a confirmed finding. Reproduce directly against the live API
  where possible, and say how many times (e.g. "reproduced 4x across two coding agents").
- **Separate the confirmed symptom from your explanation of the root cause.** If the root
  cause is your best inference rather than something mechanically proven (LLM behavior
  especially — you usually can't trace output to one line of prompt text), say so explicitly
  in the issue. Don't present a guess as settled fact.
- **Show the evidence, not just a description.** A raw API request/response pair, or a
  concrete before/after, is worth more than "the guidance was wrong."

## Filing a fix

- **One PR per issue.** Same reasoning as above — reviewers need to approve or reject one
  change at a time.
- **Write the description like a teammate will read it cold**: what was broken, why (root
  cause, with the same honesty caveat as above), the change with a concrete before/after when
  a behavior or output shape moved, what you tested, and what a reviewer should manually QA.
- **Live-verify before you claim it's fixed.** Reasoning about a fix is not the same as
  running it. Test the actual failure case end to end against a real deployment, and clean up
  whatever you created while testing.
- **When a reviewer disputes a technical claim, re-verify against the source before
  defending it.** Twice in this repo's history a first-pass technical explanation (an env var
  precedence, a permission-mode meaning) turned out to be backwards on review. Both times the
  right move was re-reading the actual source (SDK code, live API behavior) rather than
  arguing from the original write-up, and posting the correction transparently on the same
  thread rather than quietly fixing it. Being wrong once, caught, and corrected in public is
  fine. Defending a claim you haven't re-checked is not.

## Writing or editing a skill (SKILL.md, references/)

- Every fact in a skill's instructions should be something you confirmed against a live
  deployment, not something assumed from general platform knowledge. If you can't verify it
  live, say so rather than stating it as settled.
- Document a testing-only convenience (e.g. an approval-gate bypass) as an explicit,
  named opt-in with a stated reason — never fold it into the default boilerplate a caller
  copies without thinking.
- Keep hard rules terse and actionable. A rule earns its place in `SKILL.md` by having
  actually caused a failure during testing — write it as the fix for that failure, not as
  general advice.
