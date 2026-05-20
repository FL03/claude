---
name: workflow
description: >
  This skill should be used when creating branches, opening PRs, managing releases,
  setting up GitHub Actions, creating milestones, linking issues, tagging versions,
  adding new crates to the workspace, writing version/sprint plans, or when the user says
  "create a branch", "open a PR", "tag a release", "setup CI", "add a crate", "new crate",
  "new sprint", "write the plan", "start a new phase", "rebase and merge this sprint".
  Covers the full development lifecycle: branching conventions, GH issue/PR/milestone
  management, release process, CI/CD workflows, Rust workspace crate scaffolding,
  and the sprint/phase/plan structure (dev.N branches, version-level plans, sprint plans
  with the 5-section structure).
version: 1.1.0
---

# Workflow — Development Lifecycle & Release Management

Standard operating procedures for branching, GitHub operations, CI/CD, releases,
and Rust workspace crate scaffolding. Every agent must follow these conventions exactly.

## Branching Convention

### Naming: `v{x}.{y}.{z}-dev.{i}`

- `x.y.z` = semver version being developed
- `i` = sprint/phase number (0-indexed)
- Example: `v0.0.9-dev.0` is sprint 0 of version 0.0.9

### Branch Lifecycle

```
1. Create:   gh pr create --base v{x}.{y}.{z} --head v{x}.{y}.{z}-dev.{i}
2. Work:     commit to v{x}.{y}.{z}-dev.{i}
3. Complete: rebase onto v{x}.{y}.{z}, merge via gh pr merge --rebase
4. Next:     create v{x}.{y}.{z}-dev.{i+1} from v{x}.{y}.{z}
```

### Release Collapse

When all phases complete:

```
1. Squash v{x}.{y}.{z} into default branch (main):
   gh pr create --base main --head v{x}.{y}.{z}
   gh pr merge --squash

2. Tag the release:
   git tag v{x}.{y}.{z}
   git push origin v{x}.{y}.{z}

3. Create GitHub release:
   gh release create v{x}.{y}.{z} --title "v{x}.{y}.{z}" --generate-notes

4. Branch cleanup is automatic (GH autodelete on merge)
```

### Rules

- **Prefer `gh` CLI** over raw `git` for all branch/PR operations.
  GitHub ignores git-originated operations w.r.t. autodelete and PR lifecycle.
  Fall back to `git` only if `gh` fails.
- Never force-push to `main` or a version branch.
- Each phase branch gets its own PR with a clear title: `v{x}.{y}.{z} Phase {i}: {description}`.

## GitHub Issue Management

### Issue Lifecycle

```
Create:   gh issue create --title "scope(area): description" --label "type"
Link:     Reference in PR body: "Closes #N" or "Fixes #N"
Milestone: gh issue edit N --milestone "v{x}.{y}.{z}"
```

### Title Convention

`{type}({scope}): {description}`

| Type | When |
|------|------|
| `feat` | New capability |
| `fix` | Bug fix |
| `bug` | Bug report (not yet fixed) |
| `chore` | Maintenance, version bumps |
| `cleanup` | Dead code removal, restructuring |
| `refactor` | Code restructuring without behavior change |

### Labels

Standard set: `bug`, `enhancement`, `cleanup`, `refactor`, `tracking`, `documentation`

### Milestones

Create one per version: `v{x}.{y}.{z}`. Attach all issues targeted for that release.

```bash
gh api repos/{owner}/{repo}/milestones --method POST -f title="v0.0.9"
gh issue edit N --milestone "v0.0.9"
```

### Stale Issue Triage

Close issues that are superseded or already resolved:

```bash
gh issue close N --comment "Superseded by #M" --reason "not planned"
gh issue close N --comment "Resolved in v{x}.{y}.{z}" --reason "completed"
```

## Pull Request Convention

### PR Title

Same as issue convention: `{type}({scope}): {description}`

### PR Body Template

```markdown
## Summary
- Bullet points describing what changed and why

## Issues
- Closes #N
- Fixes #M

## Test Plan
- [ ] `cargo clippy --workspace --features full`
- [ ] `cargo fmt --all --check`
- [ ] `cargo test --workspace --features full`
```

### Merge Strategy by Context

| Source → Target | Strategy | Why |
|----------------|----------|-----|
| `dev.{i}` → `v{x}.{y}.{z}` | `--rebase` | Preserve phase commit history |
| `v{x}.{y}.{z}` → `main` | `--squash` | Clean single release commit |

## CI/CD Workflows (.github/workflows/)

### Required Workflows

| Workflow | Triggers | Purpose |
|----------|----------|---------|
| `cargo-clippy.yml` | PR (synchronize), push (main + tags) | Lint + SARIF upload |
| `cargo-test.yml` | PR (main), push (main + tags), release | Test matrix: stable + nightly |
| `cargo-build.yml` | push (main + tags) | Multi-target: native + WASM (wasip1, wasip2) |
| `cargo-publish.yml` | release (published) | Sequential crates.io publish |
| `release.yml` | release (published) | GH release notes + links |
| `docker.yml` | push (tags), workflow_dispatch | Multi-container Docker builds |
| `fly-io.yml` | workflow_dispatch | Deploy to Fly.io |
| `cleanup.yml` | PR (closed) | Branch cleanup |

### Workflow Patterns

Refer to `references/ci-patterns.md` for full workflow templates derived from the
production pzzld-rs reference implementation.

Key patterns:
- **Matrix builds**: features × targets × toolchains
- **Sequential publishing**: `max-parallel: 1` for crates.io to prevent race conditions
- **Concurrency control**: `cancel-in-progress: false` per workflow/ref group
- **SARIF upload**: Clippy results to GitHub code scanning (public repos)
- **WASM builds**: cargo-component for wasip1, native for wasip2
- **Nightly matrix**: `no_std`, `alloc+nightly` feature combos on nightly toolchain

### Standard Environment

```yaml
env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: full
```

## Rust Workspace Crate Scaffolding

### Adding a New Crate to `crates/*`

Every crate within `crates/*` follows an exact structure. Deviations are bugs.

#### 1. Create the crate

```bash
cargo init --lib crates/{name}
mkdir -p crates/{name}/wit
```

#### 2. Cargo.toml Template

Refer to `references/crate-template.md` for the complete Cargo.toml template.

Critical rules:
- **ALL metadata** inherits from workspace (authors, edition, version, etc.)
- **Only `name` and `description`** are crate-specific
- **`[lib] bench = false`** unless the crate has benchmarks
- **`[package.metadata.docs.rs]`** and **`[package.metadata.release]`** sections required
- **`build = "build.rs"`** with a standard build script

#### 3. Feature Gate Architecture

Every crate MUST define these environment features:

```toml
[features]
default = ["std"]
full = ["default", ...all optional features..., "dep/full" for each axiom dep...]

# Environment features (MANDATORY)
std = ["alloc", "dep/std"...]
alloc = ["dep/alloc"...]
nightly = []
wasm = ["std", "dep/wasm"...]
wasi = ["dep/wasi"...]
```

Feature propagation rules:
- `std` MUST enable `alloc` and propagate `/std` to all deps
- `full` MUST enable all optional features AND propagate `/full` to axiom deps
- Optional deps use `?/` conditional propagation: `"axiom-config?/serde"`
- Feature activation for optional deps: `config = ["dep:axiom-config"]`

#### 4. Register in Workspace

In root `Cargo.toml`:

```toml
# Add to [workspace.dependencies]
axiom-{name} = { default-features = false, path = "crates/{name}", version = "0.0.9" }

# Add to members list
members = [..., "crates/{name}"]
```

#### 5. Register in Umbrella SDK

In `crates/axiom/Cargo.toml`:

```toml
[dependencies]
axiom-{name} = { optional = true, workspace = true }

[features]
{name} = ["dep:axiom-{name}"]
full = [..., "axiom-{name}?/full"]
```

In `crates/axiom/lib.rs`:

```rust
#[cfg(feature = "{name}")]
pub use axiom_{name} as {name};
```

#### 6. WIT Directory

Every crate gets `crates/{name}/wit/` with at minimum:
- `types.wit` — shared type definitions
- `{name}.wit` — interface definitions
- `world.wit` — world definition

### SDK Facade Rule

**No crate within `crates/*` should EVER be imported directly by consumers.**
Consumers depend ONLY on `axiom` and use feature gates.

```toml
# CORRECT
axiom = { version = "0.0.9", features = ["bot", "engine"] }

# WRONG — NEVER do this
axiom-bot = "0.0.9"
axiom-engine = "0.0.9"
```

Exceptions:
- `clients/*` — independent standalone libraries, not part of the SDK
- `components/*` — depend on the axiom SDK (they are consumers)

## Plan & Sprint Structure

Every version (`v{x}.{y}.{z}`) is decomposed into ordered sprints/phases. Each sprint is a single `dev.N` branch. Plans live in `.artifacts/plans/` and design docs live in `.artifacts/docs/`.

### Plan File Naming (versioned artifacts)

**Drop the date prefix.** Use frontmatter to carry the date instead. Naming is compact and stable:

| File | Scope |
|---|---|
| `.artifacts/plans/v{xyz}.plan.md` | Version-level plan (roadmap across all sprints) |
| `.artifacts/plans/v{xyz}-dev{N}.plan.md` | Sprint N plan (scoped to one phase) |
| `.artifacts/docs/v{xyz}-design.md` | Version-level design doc |
| `.artifacts/docs/v{xyz}-dev{N}-design.md` | Sprint-specific design doc (if needed) |

`{xyz}` is the compact version (e.g., `015` = `0.1.5`, `016` = `0.1.6`).

**Frontmatter (required on versioned plans + designs):**

```md
---
title: v0.1.5 Stability Sprint Plan
createdAt: 2026-04-14
version: v0.1.5
phase: 0           # omit for version-level plans
description: One-sentence summary of this plan/design. Helps skim across many plans.
---

{plan body}
```

Required keys: `title`, `createdAt`, `version`. Optional: `phase` (for sprint plans), `description` (recommended for browseability), `updatedAt` (if the plan is revised after first publication). The `createdAt` key is unambiguous against any future `updatedAt` or `reviewedAt` fields.

Non-versioned artifacts (ad-hoc reports, audits, point-in-time research) keep their date-prefixed names — they're frozen in time by design. Examples:
- `.artifacts/reports/2026-04-14-v015-audit.md` — keeps date (reports are time-series)
- `.artifacts/research/2026-04-14-quad-math-audit.md` — keeps date (one-shot research)

### Sprint Internal Structure

Every sprint plan follows the same shape. Structuring this way forces critical work to land before enhancements and ensures validation ships with every sprint:

```
1. Critical issues       — must-fix blockers, security, data loss, broken pipelines
2. Enhancements           — capabilities the sprint adds
3. Optimizations          — performance, cleanup, dead-code removal
4. Wiring / Interfaces    — CLI/MCP/GUI surface wire-up for new behavior
5. Audit                  — validation that the changes meet spec (tests, manual checks, live observation)
```

Sprint plans should be written with these five sections — even if a section is "N/A for this sprint" say so explicitly. Tracks within a sprint usually map to one of these five sections.

### Version-Level Plan

The version plan (`v{xyz}.plan.md`) is the roadmap. It lists each sprint with:
- Number (`dev.0`, `dev.1`, ...)
- Theme (one sentence)
- Entry criteria (what must be true before starting)
- Exit criteria (what defines "done" for this sprint)
- Link to the sprint plan file

### Git Flow (canonical)

```
1. Write v{xyz}.plan.md (version roadmap with sprint list).
2. For each sprint N:
   a. Open branch v{xyz}-dev.{N} off v{xyz}.
   b. Write v{xyz}-dev{N}.plan.md (scoped to this phase's 5 sections).
   c. Dispatch track PRs targeting v{xyz}-dev.{N}.
   d. When sprint complete + audited, rebase-merge v{xyz}-dev.{N} → v{xyz}. Delete dev branch.
3. When all sprints in v{xyz}.plan.md complete, squash-merge v{xyz} → main (user-approved).
4. Tag release, create GH release.
```

**Don't start `dev.(N+1)` until `dev.N` is merged.** Parallel phase branches defeat the point of the phase structure — they hide cross-cutting drift.

### Rules

- **Rebase-merge dev.N → version** — preserves phase commit history as readable trees
- **Squash-merge version → main** — main shows one commit per release
- **Track branches within a sprint** are ephemeral; `gh pr merge --rebase --delete-branch` is the standard pattern
- **Version-changing PRs (dev.N → version OR version → main) require explicit user approval**
- **Rename historical plans cautiously.** Old dated-filename plans should be left alone — they're historical record. New plans use the new convention.

## Additional Resources

### Reference Files

- **`references/ci-patterns.md`** — Full CI/CD workflow templates from pzzld-rs reference
- **`references/crate-template.md`** — Complete Cargo.toml template for new crates
- **`references/release-checklist.md`** — Step-by-step release process checklist
