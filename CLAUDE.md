# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a Claude Code skill marketplace — a collection of independently installable skills published by FL03. It contains no compilable code. All content is Markdown and JSON.

The marketplace is registered in Claude Code as `fl03-skills` and lives at `https://github.com/FL03/claude`.

## Registering the Marketplace

On a new machine, register this marketplace once:

```
/marketplace add https://github.com/FL03/claude.git
```

Then install individual skills:

```
/install fl03-skills/rust
/install fl03-skills/finance
/install fl03-skills/webassembly
```

## Local Development Install

For active skill development, use the install script to sync changes directly to `~/.claude/skills/`:

```bash
./scripts/install.sh --list              # show available skills and versions
./scripts/install.sh --status           # compare available vs installed
./scripts/install.sh rust finance       # install specific skills
./scripts/install.sh --all              # install all skills
./scripts/install.sh --uninstall rust   # remove a skill
```

## Structure

```
.claude-plugin/
  marketplace.json    — marketplace manifest listing all skills as plugins
  plugin.json         — repo-level plugin metadata

skills/{name}/
  plugin.json         — per-skill manifest (name, version, description, keywords)
  SKILL.md            — skill entry point with YAML frontmatter
  *.md                — companion reference files loaded by the skill
  agents/*.md         — sub-agent definitions (optional)

scripts/
  install.sh          — local installer: copies skills to ~/.claude/skills/

CHANGELOG.md          — version history for the marketplace and each skill
```

## Skill Authoring

Every skill requires a `SKILL.md` with YAML frontmatter:

```yaml
---
name: skill-name
description: |
  One-paragraph trigger description. This is what Claude reads to decide
  whether to load the skill.
user-invocable: true   # omit if only invoked programmatically
version: 1.0.0
---
```

Companion reference files (e.g. `QUANT.md`, `MODELS.md`) are loaded by the skill's `SKILL.md`. They use `type: reference` in frontmatter and have no trigger logic of their own.

Agent definitions under `agents/` include `name`, `description`, `triggers`, `model`, and `mode` in frontmatter.

## Versioning

Version sources of truth:
- **Per skill**: `skills/{name}/plugin.json` → `version`
- **Marketplace**: `.claude-plugin/marketplace.json` → `version` (tracks the registry itself)

When bumping a skill's version, update both:
1. `skills/{name}/plugin.json`
2. `skills/{name}/SKILL.md` frontmatter (if it carries its own `version:` key)
3. The matching entry in `.claude-plugin/marketplace.json`
4. `CHANGELOG.md`

## Branching & Release Workflow

Branches follow `v{x}.{y}.{z}-dev.{i}` (sprint branches off a version branch).

| Source → Target | Strategy |
|---|---|
| `dev.{i}` → `v{x}.{y}.{z}` | `--rebase` |
| `v{x}.{y}.{z}` → `main` | `--squash` (triggers automated release pipeline) |

The automated pipeline (`.github/workflows/release.yml`) handles tagging, GitHub release creation, next patch branch, version bumps, dev.0, orphan sweep, and milestone roll. **Do not force-push to `main` or any version branch.**

## PR & Issue Conventions

Title format: `{type}({scope}): {description}`

Common types: `feat`, `fix`, `chore`, `cleanup`, `refactor`

PR body must include `## Summary`, `## Issues` (with `Closes #N`), and `## Test Plan`.
