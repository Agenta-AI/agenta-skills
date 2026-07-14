# Send setup feedback (optional, user-approved)

At the end of a setup, or when something breaks, offer to send anonymous feedback so the
Agenta team can improve this skill and the self-host flow. **Ask first.** Send only if the
user agrees. Thank them either way — the team is grateful for the help.

## Topic

Publish to the public ntfy.sh topic for setup and installation feedback:

```
agenta-bdk-feedback-install
```

## Safety — read before sending

ntfy topics are **public and unauthenticated**. Anyone can read them.

- **Never** send API keys, tokens, passwords, DB credentials, `.env` contents, private data,
  or full stack traces.
- Redact hostnames, IPs, and anything identifying if the user has not agreed to share them.
- Send **short** errors and the exact failing command only — not full logs.
- Send a success report too, even when nothing broke; it tells the team the flow worked.

## Report format

Keep it under ~4 KB. Only useful operational context.

```text
Agent: <your agent name or runtime>
Date: <ISO timestamp>
Status: <success | partial | failed>

Summary:
<2-5 sentences: what the user set up (local/remote, sandbox choice) and how it went>

Issues Found:
- <confusing step, failed command, missing doc, wrong default, etc.>
- <or "None">

Actions Taken:
- <key steps / commands that mattered>

Blocked:
- <what stopped progress, if anything>
- <or "None">

Suggested Fixes:
- <specific docs/skill/product improvement>
- <or "None">
```

## Publish command

Use `curl` with stdin. Fill in the report; keep the safety rules above.

```bash
curl -sS \
  -H "Title: Agenta self-host setup feedback" \
  -H "Tags: feedback,install" \
  -H "Priority: default" \
  --data-binary @- \
  "https://ntfy.sh/agenta-bdk-feedback-install" <<'EOF'
Agent: <your agent name or runtime>
Date: <ISO timestamp>
Status: <success | partial | failed>

Summary:
<what happened during setup>

Issues Found:
- <issue, or "None">

Actions Taken:
- <what mattered>

Blocked:
- <blocker, or "None">

Suggested Fixes:
- <improvement, or "None">
EOF
```

After sending, thank the user.
