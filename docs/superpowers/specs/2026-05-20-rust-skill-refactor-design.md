# Rust Skill Refactor + Marketplace Sweep — Design

Date: 2026-05-20
Author: FL03 (with Claude Code)
Target release: `fl03-skills@5.1.0`

## Problem

`skills/rust/SKILL.md` has grown to 1430 lines. Two heavy operational sections —
Cargo & Feature Gates (§VIII, 155 lines) and Parallel Agent Build Workflows
(§IX, 155 lines) — belong in dedicated reference files under progressive
disclosure. The skill ships no dedicated `rustc.md`, leaving compiler flags,
target triples, lint groups, and codegen knobs scattered across primer prose
and the "Common Compiler Errors" section. Two leftover files
(`skills/rust/wasm.md`, `skills/rust/wasmtime-host.md`) duplicate material now
owned by the standalone `wasmtime` and `webassembly` skills.

Sibling skills (`finance`, `polymarket`, `trader`, `typing`, `wasmtime`,
`webassembly`, `workflow`) have not been audited against the rust skill's
post-refactor depth/condensation baseline. The marketplace needs a coordinated
pass to bring all skills to the same "portable knowledge silo" standard.

## Goals

1. Add a dedicated `cargo.md` covering the full cargo surface: commands,
   `Cargo.toml` schema, workspaces, feature gates, `.cargo/config.toml`,
   registries/publishing, the subcommand ecosystem, sccache, parallel-agent
   build workflows, and machine-readable output.
2. Add a dedicated `rustc.md` covering practical compiler knobs: codegen
   flags, RUSTFLAGS precedence, target triples and tiers, lint levels and
   groups, editions, sanitizers, conditional compilation, `--print` queries,
   debug flags.
3. Trim `SKILL.md` from ~1430 to ~1000 lines by extracting §VIII and §IX into
   `cargo.md` and lightly condensing §XI (module organization) and §XIV
   (macros), each of which has a dedicated reference file already.
4. Delete the orphaned `skills/rust/wasm.md` and `skills/rust/wasmtime-host.md`.
5. Bring all non-rust skills to the same depth/clarity baseline via a
   parallel-agent sweep.
6. Ground every cargo flag, rustc flag, `Cargo.toml` key, and crate command
   against the Cargo Book, Rustc Book, or crate docs via Context7 MCP. No
   memorized facts in the new files.

## Non-Goals

- Rewriting `ownership-borrowing.md`, `typespace.md`, `macros.md`,
  `module-organization.md`, `concurrency-memory.md`, `errors-iteration.md`,
  `types-strings.md`, `advanced-traps.md`. They keep their current content.
- Migrating WASM toolchain material (cargo-component, wit-bindgen,
  wasm-bindgen, wasmtime) back into the rust skill. That material lives in
  `webassembly/` and `wasmtime/` and stays there.
- Changing the marketplace name, slugs, or repository layout.
- Adding new skills to the marketplace.

## File Layout (post-refactor)

```
skills/rust/
  SKILL.md                  # primer + index, ~1000 lines
  plugin.json               # version 5.1.0
  cargo.md                  # NEW
  rustc.md                  # NEW
  ownership-borrowing.md    # unchanged
  types-strings.md          # unchanged
  errors-iteration.md       # unchanged
  concurrency-memory.md     # unchanged
  advanced-traps.md         # unchanged
  typespace.md              # unchanged
  macros.md                 # unchanged
  module-organization.md    # unchanged
  # DELETED: wasm.md, wasmtime-host.md
```

## SKILL.md Trim Plan

| Section | Action | Approx. lines after |
|---|---|---|
| Frontmatter | Update `version: 5.1.0`; refresh description to drop WASM toolchain mention | 24 |
| §0 Canonical reference | Keep verbatim | 62 |
| §I Ownership & Borrowing | Keep | 41 |
| §II Lifetimes | Keep | 29 |
| §III Error Handling | Keep | 52 |
| §IV Traits & Generics | Keep | 326 |
| §V Async Rust (tokio) | Keep | 64 |
| §VI Strings | Keep | 36 |
| §VII Iterators | Keep | 26 |
| §VIII Cargo & Feature Gates | **Extract** → `cargo.md`. Replace with ~25-line summary + pointer | 25 |
| §IX Parallel Agent Build Workflows | **Extract** → `cargo.md`. Replace with ~10-line pointer | 10 |
| §X Patterns & Idioms | Keep | 71 |
| §XI Module Organization | Trim to summary + pointer to `module-organization.md` | 30 |
| §XII When to Extract a Crate | Keep | 15 |
| §XIII Unsafe | Keep | 29 |
| §XIV Macros | Trim to summary + pointer to `macros.md` | 25 |
| §XV Common Compiler Errors | Keep; add cross-ref to `rustc.md` | 20 |
| §XVI Testing | Keep | 37 |
| §XVII Performance Quick Hits | Keep; add cross-ref to `rustc.md` codegen flags | 17 |
| Anti-Patterns | Keep | 13 |
| Reference Files | Rewrite: drop wasm/wasmtime entries; add cargo.md + rustc.md; fix cross-references | 50 |
| WebAssembly section | Replace with 5-line pointer paragraph to `webassembly` + `wasmtime` skills | 5 |

Target total: **~1000 lines** (down from 1430).

Arithmetic: 1430 − 155 (§VIII extracted) − 155 (§IX extracted) + 35 (their
replacement pointers) − 97 (§XI lightly trimmed: ~127 → ~30) − 39 (§XIV
lightly trimmed: ~64 → ~25) = **1019 lines**. The "~1000" target leaves
margin for cross-reference edits inside the kept sections.

## cargo.md Outline

Target: ~600 lines, organized for progressive disclosure within the file.

### §1 Commands

For each of `build`, `check`, `test`, `run`, `doc`, `bench`, `install`,
`publish`, `search`, `tree`, `update`, `clean`, `fetch`, `vendor`: the flags
worth knowing, the canonical invocation, and any non-obvious behavior.
Includes `--features`, `--no-default-features`, `--all-features`,
`--workspace`, `-p`/`--package`, `--bin`, `--example`, `--target`,
`--release`, `--profile`, `--target-dir`, `--offline`, `--frozen`, `--locked`.

### §2 Cargo.toml schema

- `[package]` — required and common fields (`name`, `version`, `edition`,
  `rust-version` MSRV, `description`, `license`, `repository`, `homepage`,
  `documentation`, `readme`, `keywords`, `categories`, `authors`,
  `exclude`/`include`, `publish`, `metadata`).
- `[dependencies]` — version requirements, `path=`, `git=` with `rev/tag/branch`,
  `optional`, `default-features = false`, `features = [...]`, `package =`,
  `workspace = true` inheritance.
- `[dev-dependencies]`, `[build-dependencies]` — same shape, different scopes.
- `[features]` — `default`, additive rule, `dep:` syntax, `?` propagation,
  feature unification across the dep graph.
- `[profile.*]` — `dev`/`release`/`test`/`bench`, `opt-level`, `lto`,
  `codegen-units`, `debug`, `strip`, `panic`, `incremental`,
  `overflow-checks`, `[profile.<name>.package.<crate>]` overrides.
- `[patch]`/`[patch.crates-io]` — local patching of registry crates.
- `[target.'cfg(...)'.dependencies]` — platform-specific deps.
- `[lib]` and `[[bin]]` — `name`, `path`, `crate-type`, `required-features`,
  `bench`, `test`, `doctest`, `harness`.
- `[workspace]` — `members`, `default-members`, `exclude`, `resolver`,
  `package`, `dependencies`, `lints`, `metadata`.

### §3 Workspaces

Root + member layout, virtual manifests, `[workspace.dependencies]` with
`workspace = true` inheritance, `[workspace.package]` inheritance,
`[workspace.lints]` for centralized lint config, `default-members` for
focused builds, resolver versions 1/2/3.

### §4 Feature gates

The full rule set: additive, `dep:` prefix to keep features and deps from
sharing a namespace, `?` propagation only when the dep is enabled, why
mutually-exclusive features break downstream, verifying matrices with
`cargo hack --feature-powerset`.

### §5 .cargo/config.toml

- `[build]` — `target`, `rustflags`, `jobs`, `incremental`, `dep-info-basedir`.
- `[target.<triple>]` — `linker`, `runner`, `rustflags`, `ar`.
- `[net]` — `git-fetch-with-cli`, `offline`, `retry`.
- `[registries]` and `[source]` — alt registries, source replacement.
- `[alias]` — custom cargo subcommands.
- `[term]` — `verbose`, `color`, `progress`.
- `[env]` — env vars set during cargo invocations.

### §6 Registries & publishing

`cargo login`, `cargo publish` (dry-run, allow-dirty, no-verify rules),
`cargo yank`/`cargo unyank`, `cargo owner`, `cargo package --list`, alt
registries config, semver and `cargo-semver-checks` for compatibility
verification.

### §7 Subcommand ecosystem

For each: one-line purpose, install command, the single most-used invocation.

| Tool | Purpose | Install |
|---|---|---|
| clippy | ~700 lints; `-D warnings` for CI gating | rustup component |
| rustfmt | Deterministic formatting; `rustfmt.toml` config | rustup component |
| cargo-expand | Expand macros (nightly) | `cargo install cargo-expand` |
| cargo-nextest | Faster test runner with per-test isolation | `cargo binstall cargo-nextest` |
| cargo-deny | License/advisory/duplicate audits | `cargo install cargo-deny` |
| cargo-audit | RustSec advisory check | `cargo install cargo-audit` |
| cargo-hack | Feature-powerset and per-feature checks | `cargo install cargo-hack` |
| cargo-machete | Find unused deps (fast) | `cargo install cargo-machete` |
| cargo-udeps | Find unused deps (deep, nightly) | `cargo install cargo-udeps` |
| cargo-flamegraph | CPU flamegraph via perf/dtrace | `cargo install flamegraph` |
| cargo-binstall | Pre-built binary install | `cargo install cargo-binstall` |
| cargo-watch | Re-run on file change | `cargo install cargo-watch` |
| cargo-edit | `cargo add`/`rm`/`upgrade` from CLI | now built-in for `add` |
| cargo-msrv | Find/verify the MSRV | `cargo install cargo-msrv` |
| cargo-component | Build WASM components (see `webassembly` skill) | `cargo install cargo-component` |

### §8 sccache

Install, `RUSTC_WRAPPER=sccache`, what it caches (rustc invocations, not
linking), when it pays off (overlapping dep graphs across agents),
concurrency safety, `sccache --show-stats`.

### §9 Parallel-agent build workflows

Port §IX of the current SKILL.md verbatim with light edits:
- `target/` contention as the failure mode.
- `CARGO_TARGET_DIR` isolation patterns (branch-scoped, ephemeral, named lane).
- Git worktree + per-worktree target.
- `-j` and `CARGO_BUILD_JOBS` throttling rule.
- Crate-scoped checks vs `--workspace`.
- Wave-gate vs in-lane discipline.
- The canonical shell preamble with `trap … EXIT` cleanup.

### §10 JSON message format

`--message-format=json`, the key `reason` values (`compiler-message`,
`compiler-artifact`, `build-finished`, `build-script-executed`), and
`jq` patterns for extracting errors, artifacts, and exit gating.

## rustc.md Outline

Target: ~250 lines.

### §1 Invocation basics

`rustc` vs `cargo rustc`, when to drop to direct rustc (one-off scripts,
investigating codegen, no Cargo project), the `-h` flag groups.

### §2 Codegen flags (`-C`)

`opt-level` (0/1/2/3/s/z meanings), `lto` (off/thin/fat), `codegen-units`
(default 16 dev / 16 release pre-1.41, 256 dev / 16 release current),
`panic` (unwind/abort), `target-cpu`/`target-feature`, `strip`
(none/debuginfo/symbols), `debuginfo` (0/1/2 = none/line-tables/full),
`incremental`, `link-arg`, `relocation-model`.

### §3 RUSTFLAGS

Precedence: command-line `-C` > `[target.<triple>] rustflags` >
`[build] rustflags` > `RUSTFLAGS` env > `[host] rustflags`. Common values
(`-D warnings`, `-C target-cpu=native`, `-C link-arg=-fuse-ld=lld`).

### §4 Target triples

Anatomy: `arch-vendor-os-env`. Canonical triples developers hit:
`x86_64-unknown-linux-gnu`, `aarch64-apple-darwin`,
`aarch64-unknown-linux-gnu`, `aarch64-unknown-linux-musl`,
`x86_64-pc-windows-msvc`, `wasm32-wasip2`, `wasm32-unknown-unknown`,
`wasm32-wasip1`. Tier 1 (host tools + library tested), Tier 2 (library
tested, host tools when possible), Tier 3 (community-maintained).
`rustup target add/list/remove`.

### §5 Lints

Levels: `allow`, `warn`, `deny`, `forbid` (last one is uncancellable).
Groups: `unused`, `warnings`, `future_incompatible`, `rust_2018_idioms`,
`nonstandard_style`, `let_underscore`. Where lints come from: `rustc -W help`.
`#![deny(...)]` in crate root vs `cargo clippy -- -D warnings` for the
CI gate. `--cap-lints` for dep-side suppression.

### §6 Editions

2015/2018/2021/2024. What each edition gates (NLL, `dyn`, `try`, async, etc.).
`edition = "2024"` in `[package]`. `cargo fix --edition` for migration.
`cargo fix --edition-idioms` for the optional idiom lints.

### §7 Sanitizers

`-Z sanitizer=address|leak|thread|memory|hwaddress` (nightly only). When to
reach for each. Required `RUSTFLAGS`, target restrictions
(linux-gnu-only for most).

### §8 Conditional compilation

`#[cfg(feature = ...)]`, `#[cfg(target_os = ...)]`,
`#[cfg(target_arch = ...)]`, `#[cfg(target_pointer_width = "64")]`,
`#[cfg(debug_assertions)]`, custom `--cfg foo` and
`--check-cfg cfg(foo)`. Difference between `cfg!()` macro (runtime
expression that returns bool) and `#[cfg]` attribute (compile-time
gating that removes code).

### §9 Print queries (`rustc --print`)

`cfg` (current target's cfg flags), `target-list`, `target-spec-json`,
`sysroot`, `target-libdir`, `rustc-commit-hash`,
`code-models`/`relocation-models`/`link-args`. What each is useful for.

### §10 Debug flags

`-Z time-passes` (nightly), `-Z print-type-sizes` (nightly), `--emit=llvm-ir`,
`--emit=asm`, `--emit=mir`, `cargo build -v`/`-vv` to see the rustc command line,
`-Z self-profile` for compile-time profiling.

## Validation Plan

For every flag, key, default, or command quoted in `cargo.md` or `rustc.md`,
the source must be verifiable against:

- **The Cargo Book** — via Context7 `resolve-library-id` → `query-docs`
  on `/rust-lang/cargo` (or equivalent ID returned by the resolver).
- **The Rustc Book** — via Context7 on `/rust-lang/rust` or
  `/rust-lang/rustc`.
- **Crate docs** — `https://docs.rs/{crate}/latest/{crate}/` and
  `https://docs.rs/crate/{crate}/latest/features` for ecosystem subcommand
  flags (clippy, rustfmt, nextest, sccache, cargo-deny, cargo-hack, etc.).

When Context7 has no entry for a niche tool (e.g., `cargo-machete`,
`cargo-msrv`), fall back to the crate's `README.md` on crates.io via
`WebFetch` and treat that as the source.

Memory-only facts are forbidden in these files. If a flag can't be sourced,
it doesn't go in.

## Marketplace Sweep (Pass 2)

After the rust skill is committed and synced, dispatch one general-purpose
agent per non-rust skill in parallel — seven agents total — using the
parallel-dispatch pattern.

Skills:
- `finance`
- `polymarket`
- `trader`
- `typing`
- `wasmtime`
- `webassembly`
- `workflow`

### Per-agent brief

Each agent receives:

1. **Target skill path** — absolute path to its skill directory under
   `skills/`.
2. **Doctrine extracted from the refactored rust skill:**
   - Progressive disclosure: SKILL.md is primer + index; depth lives in
     companion reference files.
   - Terse pointer paragraphs over duplicated content. If two files cover
     the same thing, one becomes a pointer.
   - Context7-grounded facts: any library/API/CLI claim must be
     verifiable against upstream docs.
   - Frontmatter consistency: `name`, `version` (5.1.0), `description`
     trigger paragraph that names the concrete triggers.
   - "Portable knowledge silo" framing: any agent should be able to load
     the skill cold and have working knowledge of the topic.
3. **Per-skill task:**
   - Audit the current SKILL.md and companion files.
   - Identify thin sections (missing depth needed for the topic) and
     thick sections (duplicate or unnecessarily verbose).
   - Add depth where thin (Context7-grounded).
   - Condense where thick.
   - Verify version + frontmatter.
   - Update `plugin.json` to 5.1.0 if substantive changes land.

   **"Substantive change" definition for version bump:** any addition or
   removal of a section, any rewrite of more than ~25 lines in a single
   file, any frontmatter description change, or any cross-skill pointer
   update. Pure typo fixes, single-line wording tweaks, and reflow do not
   bump version on their own.
4. **Expected output:** summary of changes (added/removed/restructured),
   files touched, version bump recommendation, any cross-skill
   inconsistencies noted.
5. **Constraints:**
   - No new skills.
   - No structural moves between skills without surfacing to the user.
   - Don't touch `skills/rust/`.
   - Don't recurse into nested Agent calls.

### Integration after sweep

1. Review each agent's diff summary.
2. Resolve any cross-skill inconsistencies (e.g., two agents both
   claiming a topic).
3. Run `./scripts/install.sh --all` to re-sync `~/.claude/skills/` if any
   sweep changed installed-side state.
4. Bump `.claude-plugin/marketplace.json` `version` to `5.1.0` and update
   each plugin entry whose skill bumped.
5. Update `CHANGELOG.md` with a 5.1.0 entry describing the rust restructure
   and the sibling sweep.

## Branching & Release

Per `CLAUDE.md` conventions:

1. Current branch is `v5.0.4`.
2. After the spec is approved and (optionally) the implementation plan
   exists, squash-merge `v5.0.4` → `main`. This triggers the automated
   release pipeline (`.github/workflows/release.yml`).
3. Open `v5.1.0` branch off `main` (manual — pipeline default is patch
   bump to `v5.0.5`; minor bump is operator-driven).
4. Implementation work happens on `v5.1.0-dev.0` off `v5.1.0`. Rebase-merge
   `dev.0` → `v5.1.0` when complete. Squash-merge `v5.1.0` → `main` at
   release.
5. No force-pushes to `main` or any version branch.

## Sync to ~/.claude

After each significant skill edit:

```bash
./scripts/install.sh rust              # rust skill only
./scripts/install.sh --status          # confirm parity
./scripts/install.sh --all             # at release time
```

The installer copies from `skills/<name>/` into `~/.claude/skills/<name>/`.
After the rust refactor lands and is committed, sync once; after the
marketplace sweep returns and is integrated, sync everything.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Cross-references in SKILL.md break after section extraction | Grep `(?i)\b(section|§|chapter)\s+(VIII|IX)\b` across all skills; update references before commit. |
| Sibling skills reference rust skill's old anchor structure | The marketplace sweep agents are explicitly tasked to flag cross-skill references. Integration step resolves. |
| Context7 lacks an entry for a tool | Fall back to crate `README.md` via `WebFetch`. Mark the file with a comment noting the source. |
| Parallel agents step on each other | Each agent gets exactly one skill directory. No shared files. Agents work read-only on `skills/rust/`. |
| `~/.claude/skills/rust/` diverges from repo | The install script is idempotent. Final pre-release step runs `./scripts/install.sh --status` and reconciles. |
| Squashing v5.0.4 → main triggers pipeline patch bump | The pipeline is patch-bump-defaulted; minor bump to 5.1.0 requires manually creating the v5.1.0 branch off main after the squash. Spec accounts for this. |

## Success Criteria

- `skills/rust/SKILL.md` is ~1000 lines and reads as a clean primer + index.
- `skills/rust/cargo.md` exists, is ~600 lines, and every flag is
  Context7-grounded.
- `skills/rust/rustc.md` exists, is ~250 lines, and every flag is
  Context7-grounded.
- `skills/rust/wasm.md` and `skills/rust/wasmtime-host.md` are deleted.
- `skills/rust/plugin.json` is `5.1.0`.
- All seven non-rust skills have been audited; substantive changes bumped to
  5.1.0; unchanged skills explicitly noted.
- `.claude-plugin/marketplace.json` `version` is `5.1.0` and each plugin
  entry matches its skill's version.
- `CHANGELOG.md` has a 5.1.0 entry.
- `~/.claude/skills/` matches `skills/` for every skill.
- Branch graph: `v5.0.4` squash-merged to `main`, `v5.1.0` branch open,
  work landed on `v5.1.0-dev.0` and rebase-merged.

## Out of Scope

- Refactoring the install script.
- Refactoring marketplace.json schema beyond version bumps and per-plugin
  entry refreshes.
- Adding CI workflows for skill validation.
- Adding new skills.
