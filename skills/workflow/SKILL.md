---
name: workflow
description: >
  This skill should be used when creating branches, opening PRs, managing releases,
  setting up GitHub Actions, creating milestones, linking issues, tagging versions,
  adding new crates to a Rust workspace, writing version/sprint plans, or when the
  user says "create a branch", "open a PR", "tag a release", "setup CI", "add a crate",
  "new crate", "new sprint", "write the plan", "start a new phase", "rebase and merge
  this sprint". Covers the full development lifecycle: the `v{x}.{y}.{z}-dev.{i}`
  branching scheme, the rebase-vs-squash decision tree, the automated patch-release
  pipeline (.github/workflows/release.yml — tag, release, next-patch cut, version
  bump, dev.0, orphan sweep, milestone roll), GH issue/PR/milestone conventions,
  Rust workspace crate scaffolding policy, and the version-level / sprint-level
  plan-file structure. Project-policy companion to the language-mastery skills;
  cargo command semantics live in `rust/cargo.md`.
version: 5.1.0
---

# Workflow — Development Lifecycle & Release Management

Standard operating procedures for branching, GitHub operations, CI/CD, releases,
and Rust workspace scaffolding. This file is the primer + index; depth lives in
the reference files at the bottom.

> **Scope note.** This skill carries *project-policy* (branch names, merge
> strategies, plan-file structure, release pipeline behavior). Generic cargo
> command semantics live in the `rust` skill's `cargo.md`. When in doubt:
> conventions and branch lifecycle here, manifest/workspace mechanics there.

---

## I. Branching Convention

### Naming: `v{x}.{y}.{z}-dev.{i}`

- `x.y.z` — semver version being developed (this is the **patch branch**).
- `i` — sprint/phase number, 0-indexed. `dev.0` is the first sprint of a new patch.
- Example: `v5.1.0-dev.0` is sprint 0 of patch `v5.1.0`.

### Branch hierarchy

```
main                    ← released, tagged, immutable history (squash commits)
└── v{x}.{y}.{z}        ← patch branch; accumulates dev.0..dev.9 via rebase
    ├── v{x}.{y}.{z}-dev.0   ← sprint 0 (the only one open at any time)
    ├── v{x}.{y}.{z}-dev.1   ← sprint 1 (cut from patch branch AFTER dev.0 merges)
    └── ...                  ← up to dev.9 (the automated mod-10 cascade)
```

### Merge strategy decision tree

| Source → Target | Strategy | Why | Approval |
|---|---|---|---|
| track / topic → `v{x}.{y}.{z}-dev.{i}` | `--rebase --delete-branch` | Tracks are ephemeral; keep linear sprint history | Reviewer |
| `v{x}.{y}.{z}-dev.{i}` → `v{x}.{y}.{z}` | `--rebase` | Preserve sprint commit history as a readable tree | Operator |
| `v{x}.{y}.{z}` → `main` | `--squash` | Releases are one commit each; **triggers `release.yml`** | Operator (explicit) |

**Rules.**

- Prefer `gh` CLI over raw `git` for all branch/PR operations. GitHub ignores
  git-originated operations w.r.t. autodelete and PR lifecycle. Fall back to
  `git` only if `gh` fails.
- **Never force-push to `main` or to a version branch.** Both are operator-protected
  and the release pipeline depends on linear history on `main`.
- Don't start `dev.(N+1)` until `dev.N` is merged. Parallel phase branches hide
  cross-cutting drift — the phase structure exists to prevent that.
- Each sprint PR has a clear title: `feat({scope}): {description}` (the version
  is implicit in the head branch name).

### Branch lifecycle commands

```bash
# Open sprint N
gh pr create --base "v{x}.{y}.{z}" --head "v{x}.{y}.{z}-dev.{N}" --draft

# Close sprint N: rebase-merge into patch branch
gh pr merge "v{x}.{y}.{z}-dev.{N}" --rebase --delete-branch

# Open next sprint
git checkout "v{x}.{y}.{z}"
git pull --rebase origin "v{x}.{y}.{z}"
git checkout -b "v{x}.{y}.{z}-dev.{N+1}"
git push -u origin "v{x}.{y}.{z}-dev.{N+1}"
```

The final sprint of a patch is followed by a squash-merge of the patch branch
into `main`. **That squash-merge fires the automated release pipeline** —
see §IV.

---

## II. GitHub Issues, PRs, Milestones

### Issue title convention

`{type}({scope}): {description}`

| Type | When |
|------|------|
| `feat` | New capability |
| `fix` | Bug fix |
| `bug` | Bug report (not yet fixed) |
| `chore` | Maintenance, version bumps |
| `cleanup` | Dead code removal, restructuring |
| `refactor` | Code restructuring without behavior change |
| `docs` | Documentation-only change |

### Standard labels

`bug`, `enhancement`, `cleanup`, `refactor`, `tracking`, `documentation`.

### PR body template

```markdown
## Summary
- Bullet points describing what changed and why.

## Issues
- Closes #N
- Fixes #M

## Test Plan
- [ ] <project-appropriate gate 1>
- [ ] <project-appropriate gate 2>
```

The test plan is project-shaped. Common gates by project type:

| Project type | Gates |
|---|---|
| Marketplace / docs-only | Manual review; frontmatter lint; install-script dry run |
| Rust workspace | `cargo fmt --all --check`, `cargo clippy --workspace --features full -- -D warnings`, `cargo test --workspace --features full` |
| Hybrid (TS + Rust) | The Rust set plus `pnpm lint && pnpm test` (or equivalent) |

### Milestones

One milestone per patch version: `v{x}.{y}.{z}`. Attach every issue targeted
for that release. The automated pipeline **rolls open issues forward to the
next milestone** on release (see §IV.5).

```bash
# Create
gh api "repos/${OWNER}/${REPO}/milestones" --method POST -f title="v0.1.5"

# Attach
gh issue edit N --milestone "v0.1.5"

# Triage stale
gh issue close N --comment "Superseded by #M" --reason "not planned"
gh issue close N --comment "Resolved in v0.1.5"      --reason "completed"
```

---

## III. Plan & Sprint Structure

Every patch `v{x}.{y}.{z}` is decomposed into ordered sprints. Plans live in
`.artifacts/plans/`, design docs in `.artifacts/docs/`. (Adapt the directory
to the project; the structure is what matters.)

### File naming

Drop the date prefix on versioned artifacts — use frontmatter for the date.

| File | Scope |
|---|---|
| `v{xyz}.plan.md` | Version-level plan (roadmap across all sprints) |
| `v{xyz}-dev{N}.plan.md` | Sprint N plan (scoped to one phase) |
| `v{xyz}-design.md` | Version-level design doc |
| `v{xyz}-dev{N}-design.md` | Sprint-specific design doc (if needed) |

`{xyz}` is the compact version (e.g., `015` = `0.1.5`, `510` = `5.1.0`).

**Frontmatter (required on versioned plans + designs):**

```md
---
title: v0.1.5 Stability Sprint Plan
createdAt: 2026-04-14
version: v0.1.5
phase: 0           # omit for version-level plans
description: One-sentence summary. Helps skim across many plans.
---
```

Required keys: `title`, `createdAt`, `version`. Optional: `phase`,
`description` (recommended), `updatedAt`.

Non-versioned artifacts (audits, point-in-time research, reports) keep
date-prefixed names — they're frozen in time by design:

- `.artifacts/reports/2026-04-14-v015-audit.md`
- `.artifacts/research/2026-04-14-quad-math-audit.md`

### Sprint internal structure — the five sections

Every sprint plan follows the same shape. This forces critical work to land
before enhancements and ensures validation ships with every sprint.

```
1. Critical issues    — must-fix blockers, security, data loss, broken pipelines
2. Enhancements       — capabilities the sprint adds
3. Optimizations      — performance, cleanup, dead-code removal
4. Wiring / Interfaces — CLI/MCP/GUI surface wire-up for new behavior
5. Audit              — validation: tests, manual checks, live observation
```

Even if a section is "N/A for this sprint" say so explicitly. Tracks within
a sprint usually map to one of these five sections.

### Version-level plan

`v{xyz}.plan.md` is the roadmap. For each sprint, list:

- Number (`dev.0`, `dev.1`, …).
- Theme (one sentence).
- Entry criteria (what must be true before starting).
- Exit criteria (what defines "done" for this sprint).
- Link to the sprint plan file.

### Canonical git flow

```
1. Write v{xyz}.plan.md (version roadmap with sprint list).
2. For each sprint N:
   a. Open branch v{xyz}-dev.{N} off v{xyz}.
   b. Write v{xyz}-dev{N}.plan.md (the 5 sections).
   c. Dispatch track PRs against v{xyz}-dev.{N}.
   d. When sprint complete + audited, rebase-merge dev.N → v{xyz}. Delete dev branch.
3. When all sprints done, squash-merge v{xyz} → main (operator-approved).
4. release.yml does the rest (tag, release, next-patch, dev.0, sweep, milestone roll).
```

**Rename historical plans cautiously.** Old date-prefixed plans are historical
record — leave them. Only new plans use the dateless convention.

---

## IV. The Automated Release Pipeline

**Source of truth:** `.github/workflows/release.yml`. Read that file if anything
below disagrees with reality — the workflow is canonical.

### Trigger

The pipeline runs on `push` to `main` (and on `workflow_dispatch`). On every
push to `main` it inspects the HEAD commit subject and proceeds only if it
matches:

- `vX.Y.Z` (operator convention; gh appends ` (#N)` on squash — tolerated), or
- `release: vX.Y.Z` (back-compat for automation-authored PRs).

The extracted version is **cross-checked against `.claude-plugin/plugin.json`**.
A stray commit subject can't fire the pipeline against the wrong version — the
job logs `::warning::` and exits cleanly.

### Steps executed (in order)

| # | Step | Effect |
|---|---|---|
| 1 | Detect release squash commit | Parses HEAD subject, validates against `plugin.json` |
| 2 | Compute next version (mod-10 cascade) | `Z<9 → patch`, else `Y<9 → minor`, else `major`; emits `current`, `next`, `tag`, branch names |
| 3 | Extract release notes from `CHANGELOG.md` | Slices the `## v{CURRENT}` section; fails the run if missing |
| 4 | Tag `v{CURRENT}` on main | Idempotent: skips if tag already exists locally or on origin |
| 5 | Create GitHub Release | Idempotent: skips if release exists; uses extracted notes |
| 6 | Cut next patch branch + bump versions | Branches `v{NEXT}` off main; rewrites `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (root + every plugin entry), every `skills/*/plugin.json`, every `skills/*/SKILL.md` frontmatter version, and `README.md` |
| 7 | Commit + push patch branch | `chore({PATCH}/version): bump plugin {CURRENT} → {NEXT}` |
| 8 | Open draft PR `v{NEXT}` → main | Title `release: v{NEXT}`; the empty container for the new patch's sprints |
| 9 | Cut `v{NEXT}-dev.0` off `v{NEXT}` | First sprint branch of the new patch, ready for work |
| 10 | Orphan sweep | Deletes `v{CURRENT}-dev.{0..9}` from origin |
| 11 | Milestone roll | Creates milestone `v{NEXT}` if missing; moves every open issue from `v{CURRENT}` → `v{NEXT}` |

Every step is **idempotent** — a partial prior run can be safely re-driven via
`workflow_dispatch` once the underlying issue is fixed.

### Operator responsibilities before the squash

1. The patch branch `v{x}.{y}.{z}` must contain a `## v{x}.{y}.{z}` section in
   `CHANGELOG.md`. If it's missing, step 3 fails the whole run.
2. `.claude-plugin/plugin.json` `version` must equal the patch version. (The
   version was set automatically when the *previous* release cut this patch
   branch — only intervene if you renumbered manually.)
3. Branch protection on `main` must require PR + linear history + no
   force-push. The pipeline depends on `git log -1 --format=%s HEAD` returning
   the squash subject.
4. PR title format: bare `v{x}.{y}.{z}` (preferred) or `release: v{x}.{y}.{z}`.
   gh appends ` (#N)` on squash; the regex tolerates that suffix.

### Operator responsibilities after the squash

Usually: **nothing**. Verify the run succeeded:

```bash
gh run list --workflow=release.yml --limit 3
gh release view "v{x}.{y}.{z}"
gh pr view "v{next}"        # the draft PR should exist
git fetch --prune origin    # observe v{next}-dev.0 appearing
```

If a step failed mid-pipeline, fix the cause and re-dispatch:

```bash
gh workflow run release.yml --ref main
```

The idempotency guards (`if tag exists`, `if release exists`, `if branch
exists`, `if milestone exists`) make re-runs safe.

### Mod-10 cascade — what to expect

| Current `Z` | Result |
|---|---|
| `Z < 9` | Patch bump: `(X, Y, Z+1)` |
| `Z == 9` and `Y < 9` | Minor bump: `(X, Y+1, 0)` |
| `Z == 9` and `Y == 9` | Major bump: `(X+1, 0, 0)` |

The pipeline is named "patch pipeline" but the cascade handles all three.
This is intentional — every release looks the same to the operator.

---

## V. CI/CD Workflows (Rust Workspace Projects)

This marketplace's only workflow is `release.yml`. The patterns below apply
to **Rust workspace projects** (the axiom family); pull them in when standing
up CI for a new Rust project.

### Recommended workflow set

| Workflow | Triggers | Purpose |
|---|---|---|
| `cargo-clippy.yml` | PR (synchronize), push (main + tags) | Lint + SARIF upload |
| `cargo-test.yml` | PR (main), push (main + tags), release | Test matrix: stable + nightly |
| `cargo-build.yml` | push (main + tags) | Multi-target: native + WASM (wasip1, wasip2) |
| `cargo-publish.yml` | release (published) | Sequential crates.io publish |
| `release.yml` | release (published) | GH release notes + crates.io/docs.rs links |
| `docker.yml` | push (tags), workflow_dispatch | Multi-container Docker builds |
| `fly-io.yml` | workflow_dispatch | Deploy to Fly.io |
| `cleanup.yml` | PR (closed) | Branch cleanup |

Templates: `references/ci-patterns.md`.

### Standing patterns

- **Matrix builds.** Features × targets × toolchains.
- **Sequential publishing.** `max-parallel: 1` on the publish matrix to
  serialize crates.io uploads in dependency order.
- **Concurrency control.** `cancel-in-progress: false` per workflow/ref group
  — interrupting a release mid-flight is worse than queuing.
- **SARIF upload.** Clippy results to GitHub code scanning on public repos.
- **WASM builds.** `cargo-component` for `wasm32-wasip2`; native `cargo build`
  for `wasm32-wasip1` and the wasm32-unknown target.
- **Nightly matrix.** `no_std`, `alloc+nightly` feature combos on the nightly
  toolchain. Catches feature-gate drift early.

### Standard env block

```yaml
env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: full
```

---

## VI. Rust Workspace Crate Scaffolding

Cargo command semantics (`cargo new`, `cargo init`, the manifest schema,
workspace inheritance, feature-gate syntax) live in `rust/cargo.md`. This
section covers **project-policy** for the axiom-family Rust workspaces —
conventions cargo itself doesn't enforce.

### When adding a crate under `crates/*`

1. **Create** with `cargo init --lib crates/{name}`, then `mkdir crates/{name}/wit`.
2. **Cargo.toml** — copy `references/crate-template.md` verbatim. Critical
   policy rules:
   - All metadata inherits from workspace (`field.workspace = true`).
   - Only `name` and `description` are crate-specific.
   - `[lib] bench = false` unless the crate carries benchmarks.
   - `[package.metadata.docs.rs]` and `[package.metadata.release]` are required.
   - `build = "build.rs"` with the standard build script.
3. **Mandatory environment features.** Every crate defines `default`, `full`,
   `std`, `alloc`, `nightly`, `wasm`, `wasi`. Feature propagation rules:
   - `std` → enables `alloc` and propagates `/std` to all deps.
   - `full` → enables all optional features AND propagates `/full` to axiom deps.
   - Optional deps: `config = ["dep:axiom-config"]`.
   - Conditional propagation: `"axiom-config?/serde"`.
4. **Register in workspace root.**
   ```toml
   [workspace.dependencies]
   axiom-{name} = { default-features = false, path = "crates/{name}", version = "{X.Y.Z}" }

   [workspace]
   members = [..., "crates/{name}"]
   ```
5. **Register in the umbrella SDK** (`crates/axiom/Cargo.toml`).
   ```toml
   [dependencies]
   axiom-{name} = { optional = true, workspace = true }

   [features]
   {name} = ["dep:axiom-{name}"]
   full   = [..., "axiom-{name}?/full"]
   ```
   Re-export in `crates/axiom/src/lib.rs`:
   ```rust
   #[cfg(feature = "{name}")]
   pub use axiom_{name} as {name};
   ```
6. **WIT directory.** `crates/{name}/wit/` with at minimum `types.wit`,
   `{name}.wit`, `world.wit`. Even if the crate isn't a wasm component today,
   the world file documents the intended surface.

### SDK Facade Rule

**No crate within `crates/*` is imported directly by external consumers.**
Consumers depend ONLY on `axiom` and use feature gates.

```toml
# CORRECT
axiom = { version = "{X.Y.Z}", features = ["bot", "engine"] }

# WRONG — never do this externally
axiom-bot    = "{X.Y.Z}"
axiom-engine = "{X.Y.Z}"
```

Exceptions:

- `clients/*` — independent standalone libraries; not part of the SDK surface.
- `components/*` — consumers of the axiom SDK (they depend on it like any
  external project would).

For the cargo-side mechanics of workspace inheritance and feature gates, see
`rust/cargo.md` §3 (workspaces) and §4 (feature gates).

---

## VII. Reference Files

- **`references/ci-patterns.md`** — full GitHub Actions templates (Clippy,
  Test, Build, Publish, Release, Docker, Cleanup) derived from the production
  pzzld-rs implementation. Drop-in starting point for Rust workspace projects.
- **`references/crate-template.md`** — the complete `Cargo.toml` template for
  a new axiom-family crate, plus the feature-gate checklist.
- **`references/release-checklist.md`** — operator pre-flight checklist for
  the squash-merge that fires the release pipeline. Pairs with §IV above.

---

## VIII. Cross-Skill Pointers

- `rust` — language fluency, ownership, async, traits, no_std tiers.
- `rust/cargo.md` — every cargo command, the `Cargo.toml` schema, workspace
  mechanics, feature-gate syntax, `[profile.*]`, `.cargo/config.toml`,
  registries. Workflow defers to it for cargo semantics.
- `rust/rustc.md` — compiler knobs (codegen flags, target triples, editions,
  lints, sanitizers).
- `webassembly` — language-agnostic WASM toolchain.
- `wasmtime` — Rust-side host embedding.
