# Agenta skills

Skills that teach your coding agent (Claude Code, Codex, Cursor, and more) to build
[Agenta](https://github.com/Agenta-AI/agenta) agents through the Agenta API. Install a skill
once, then build Agenta agents from your terminal by asking your coding agent in plain
language.

One repo, many skills. Each skill lives under `skills/` and travels with its own scripts and
reference files.

## Skills

| Skill | What it does |
|---|---|
| [`build-agent`](skills/build-agent/) | Turn a plain-language request into a working, tested Agenta agent: write one config, run a few scripts, schedule it, verify it. |
| [`self-host-agenta`](skills/self-host-agenta/) | Router and field guide for self-hosting Agenta with Docker Compose: the four decisions, `run.sh` flags, hardening, troubleshooting, and verification. |

More skills will land as sibling folders under `skills/`.

## Install

Two channels, both point at this repo. Pick the one for your coding agent.

### Claude Code (plugin marketplace)

```
/plugin marketplace add Agenta-AI/agenta-skills
/plugin install build-agent@agenta
```

### Codex, Cursor, and others (npx skills)

[`npx skills`](https://github.com/vercel-labs/skills) copies the skill into each tool's native
directory:

```bash
# interactive: pick your agents and skills
npx skills add Agenta-AI/agenta-skills

# or target tools and a skill directly
npx skills add Agenta-AI/agenta-skills -a claude-code -a codex -a cursor
npx skills add Agenta-AI/agenta-skills --skill build-agent --agent '*'

# refresh later
npx skills update
```

## Credentials

The skills call the Agenta API and need one or two values:

- `AGENTA_API_KEY` — **required.** Get it from your Agenta project settings (the API keys
  page). On cloud that is under [cloud.agenta.ai](https://cloud.agenta.ai).
- `AGENTA_HOST` — **optional.** Defaults to Agenta cloud (`https://cloud.agenta.ai`). Set it
  only if you self-host, to your own Agenta domain.

The skill will ask you for these on first run and can write a local `.env` for you, or hand
you a block to paste. Set them either as environment variables or in a `.env` file in your
working directory:

```bash
export AGENTA_API_KEY=your-key-here
# export AGENTA_HOST=https://your-agenta-domain   # only if self-hosting
```

The bundled scripts need `bash`, `curl`, and `jq`. The skill runs a preflight
(`check-prereqs.sh`) that checks for them and prints the install command for your platform if
one is missing.

## License

MIT. See [LICENSE](LICENSE).
