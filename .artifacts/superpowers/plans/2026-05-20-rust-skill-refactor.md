# Rust Skill Refactor + Marketplace Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `skills/rust/SKILL.md` (1430 lines) into a leaner primer plus dedicated `cargo.md` and `rustc.md` reference files, delete two orphaned WASM files, then run a parallel marketplace-wide sweep to bring the seven non-rust skills to the same depth/clarity baseline. Release as `fl03-skills@5.1.0`.

**Architecture:** Two-pass sequencing. Pass 1 is the rust-skill refactor + Context7-grounded authoring of `cargo.md` and `rustc.md`. Pass 2 dispatches one general-purpose subagent per non-rust skill (seven in parallel) to audit, condense, and validate each one against upstream docs. All edits go in the repo first, then sync to `~/.claude/skills/` via the existing `scripts/install.sh`. Branch dance (squash v5.0.4 → main, open v5.1.0, sprint on v5.1.0-dev.0) happens up front so all version bumps land on the right branch.

**Tech Stack:** Markdown skill files, JSON manifests, bash + git, Context7 MCP for documentation grounding, the existing `scripts/install.sh` for syncing to `~/.claude/`, parallel `Agent` tool dispatch for the sibling sweep.

**Spec reference:** `docs/superpowers/specs/2026-05-20-rust-skill-refactor-design.md`

---

## Task 1: Commit the spec on v5.0.4

**Files:**
- Modify: working tree only (commit existing untracked `docs/superpowers/specs/2026-05-20-rust-skill-refactor-design.md`)

- [ ] **Step 1.1: Confirm working tree is clean except for the spec**

Run: `git status`
Expected: only `docs/` is untracked; nothing else modified.

- [ ] **Step 1.2: Stage the spec**

```bash
git add docs/superpowers/specs/2026-05-20-rust-skill-refactor-design.md
```

- [ ] **Step 1.3: Commit**

```bash
git commit -m "$(cat <<'EOF'
docs(specs): rust skill refactor + marketplace sweep design

Adds the design spec for splitting skills/rust/SKILL.md into a leaner
primer plus dedicated cargo.md and rustc.md, deleting the orphaned
wasm.md and wasmtime-host.md, and running a parallel sweep of the seven
non-rust skills.
EOF
)"
```

Expected output: one file changed, single commit on `v5.0.4`.

- [ ] **Step 1.4: Verify**

Run: `git log --oneline -2`
Expected: top commit is the spec commit.

---

## Task 2: Branch dance — squash v5.0.4 → main, open v5.1.0, open dev.0

> **STOP and confirm with the user before executing this task.** This task does an irreversible squash-merge to `main` and creates two new branches. Confirm sequencing (do this BEFORE the rust refactor, not after) and confirm the user wants the automated release pipeline triggered now.

**Files:** None (git operations only).

- [ ] **Step 2.1: Pre-flight — fetch + verify remote state**

```bash
git fetch --all --prune
git log --oneline origin/main..HEAD
git log --oneline HEAD..origin/main
```

Expected: clean delta (your v5.0.4 commits vs main).

- [ ] **Step 2.2: Confirm with user**

Surface the squash plan to the user before running it. Get explicit "yes". This is a `main`-affecting operation.

- [ ] **Step 2.3: Switch to main and pull**

```bash
git checkout main
git pull origin main
```

- [ ] **Step 2.4: Squash-merge v5.0.4 into main**

```bash
git merge --squash v5.0.4
```

Resolve any conflicts (unlikely on a docs-only delta). Then commit:

```bash
git commit -m "$(cat <<'EOF'
chore: squash v5.0.4 into main

Closes out the v5.0.4 cycle. Spec for the v5.1.0 refactor (rust skill
restructure + marketplace sweep) is included.
EOF
)"
```

- [ ] **Step 2.5: Push main**

```bash
git push origin main
```

Expected: triggers `.github/workflows/release.yml`. The pipeline default is a patch bump (would create `v5.0.5`); we override below by opening the v5.1.0 branch manually.

- [ ] **Step 2.6: Create v5.1.0 branch off main**

```bash
git checkout -b v5.1.0
git push -u origin v5.1.0
```

- [ ] **Step 2.7: Create v5.1.0-dev.0 sprint branch**

```bash
git checkout -b v5.1.0-dev.0
git push -u origin v5.1.0-dev.0
```

- [ ] **Step 2.8: Verify branch state**

```bash
git branch --show-current
git log --oneline -3
```

Expected: on `v5.1.0-dev.0`, top of log is the squash commit.

---

## Task 3: Delete the orphaned WASM files in skills/rust/

**Files:**
- Delete: `skills/rust/wasm.md`
- Delete: `skills/rust/wasmtime-host.md`

- [ ] **Step 3.1: Confirm both files exist**

```bash
ls -la skills/rust/wasm.md skills/rust/wasmtime-host.md
```

- [ ] **Step 3.2: Confirm content lives in the sibling skills**

```bash
ls skills/wasmtime/ skills/webassembly/
```

Expected: both directories present with their own SKILL.md.

- [ ] **Step 3.3: Delete**

```bash
git rm skills/rust/wasm.md skills/rust/wasmtime-host.md
```

- [ ] **Step 3.4: Stage but do not commit yet — bundle with the SKILL.md trim in Task 9**

```bash
git status
```

Expected: both files staged as deleted.

---

## Task 4: Resolve Context7 IDs for the Cargo Book and Rustc Book

**Files:** None — captures IDs into shell vars for later tasks.

- [ ] **Step 4.1: Resolve the Cargo Book ID**

Use the Context7 MCP `resolve-library-id` tool with query: "rust cargo book package manager". Pick the highest-confidence match whose name reads like "The Cargo Book" or whose org is `rust-lang`.

Record the resolved ID. Expected format: `/rust-lang/cargo` or similar.

- [ ] **Step 4.2: Resolve the Rustc Book ID**

Use Context7 `resolve-library-id` with query: "rust rustc book compiler flags". Pick the canonical match (likely `/rust-lang/rust` or the rustc-book-specific entry if it exists).

Record the resolved ID.

- [ ] **Step 4.3: Smoke-test both IDs**

Run `query-docs` against each with a probe query like "what is the lto profile setting" (cargo) and "what is the opt-level codegen flag" (rustc). Confirm useful results return.

If either lookup fails, search for alternate IDs (try `the-cargo-book`, `cargo-book`, `rust-cargo`). If no match found anywhere, document this in the file's source comment and fall back to `WebFetch` against `https://doc.rust-lang.org/cargo/` and `https://doc.rust-lang.org/rustc/` respectively.

- [ ] **Step 4.4: Record IDs for use in Tasks 5–7**

Note both IDs at the top of a scratch file or in shell exports:

```bash
export CARGO_BOOK_ID="<resolved-id>"
export RUSTC_BOOK_ID="<resolved-id>"
```

---

## Task 5: Bootstrap cargo.md — frontmatter + §1 Commands + §2 Cargo.toml schema

**Files:**
- Create: `skills/rust/cargo.md`

- [ ] **Step 5.1: Query Context7 for cargo command surface**

```text
query-docs $CARGO_BOOK_ID "cargo build check test run doc bench install publish search tree update clean fetch vendor — what does each command do and what are the most important flags"
```

Save the response for use in §1.

- [ ] **Step 5.2: Query Context7 for Cargo.toml schema**

```text
query-docs $CARGO_BOOK_ID "Cargo.toml manifest format — [package] [dependencies] [features] [profile] [patch] [target] [lib] [[bin]] [workspace] fields and their valid values"
```

- [ ] **Step 5.3: Write cargo.md with frontmatter and the first two sections**

Use the Write tool. The file starts:

```markdown
---
name: cargo
description: |
  The full cargo surface for any Rust workspace: commands, Cargo.toml schema,
  workspaces, feature gates, .cargo/config.toml, registries, the subcommand
  ecosystem, sccache, parallel-agent build workflows, and machine-readable
  output. Companion reference to the rust skill — open this when the task
  is about cargo invocations, the manifest, or the build pipeline.
type: reference
version: 5.1.0
---

# Cargo — The Build System and Package Manager

Cargo is the workspace coordinator. It owns dependency resolution, the
compilation pipeline, the feature graph, and the toolchain interface.
Every operational rule here is sourced from the Cargo Book (queried via
Context7) or from upstream crate documentation — not from memory.

This file is opened by the rust skill on cargo-shaped questions. The
sections progress from daily commands → manifest reference → workspace
orchestration → feature/config nuance → ecosystem subcommands → parallel
build patterns. Skim to find the relevant section, then read deep.

---

## §1. Commands

[Insert command-by-command writeup grounded in Context7 §5.1 output.
For each command (build, check, test, run, doc, bench, install, publish,
search, tree, update, clean, fetch, vendor): one-paragraph purpose, the
flags worth knowing, the canonical invocation, and any non-obvious
behavior. Length target: ~120 lines.]

---

## §2. Cargo.toml schema

[Insert manifest reference grounded in Context7 §5.2 output. Cover:
[package] required + common fields with MSRV via rust-version,
[dependencies] including version reqs, path=, git= rev/tag/branch,
optional, default-features=false, features=[...], package=,
workspace=true inheritance; [dev-dependencies] and [build-dependencies];
[features] with default, additive rule, dep: syntax, ? propagation,
unification; [profile.*] including dev/release/test/bench plus
opt-level/lto/codegen-units/debug/strip/panic/incremental/
overflow-checks plus [profile.<name>.package.<crate>] overrides;
[patch] and [patch.crates-io]; [target.'cfg(...)'.dependencies];
[lib] and [[bin]] with name/path/crate-type/required-features/
bench/test/doctest/harness; [workspace] with members/default-members/
exclude/resolver/package/dependencies/lints/metadata.
Length target: ~140 lines.]

---
```

Replace the bracketed `[Insert ...]` blocks with the actual Context7-grounded
content. Do not commit the bracket placeholders.

- [ ] **Step 5.4: Verify line count is in range**

```bash
wc -l skills/rust/cargo.md
```

Expected: roughly 270–320 lines at this stage (frontmatter + §1 + §2).

- [ ] **Step 5.5: Verify no placeholder text remains**

```bash
grep -nE '\[Insert|TBD|TODO|placeholder' skills/rust/cargo.md
```

Expected: no matches.

---

## Task 6: Append cargo.md §3 Workspaces + §4 Feature gates + §5 .cargo/config.toml + §6 Registries

**Files:**
- Modify: `skills/rust/cargo.md`

- [ ] **Step 6.1: Query Context7 for workspace mechanics**

```text
query-docs $CARGO_BOOK_ID "cargo workspace root manifest virtual manifest members default-members resolver workspace.dependencies workspace.package workspace.lints inheritance"
```

- [ ] **Step 6.2: Query Context7 for feature mechanics**

```text
query-docs $CARGO_BOOK_ID "cargo features additive default-features dep: prefix optional dependencies feature unification mutually exclusive features dangerous"
```

- [ ] **Step 6.3: Query Context7 for .cargo/config.toml**

```text
query-docs $CARGO_BOOK_ID ".cargo/config.toml configuration file [build] [target] [net] [registries] [alias] [term] [env] sections and their keys"
```

- [ ] **Step 6.4: Query Context7 for publishing**

```text
query-docs $CARGO_BOOK_ID "cargo login publish yank unyank owner package alt registries crates.io semver versioning"
```

- [ ] **Step 6.5: Append §3 through §6 to cargo.md**

Use the Edit tool with `old_string` being the last line currently in the file (e.g., the §2 trailing divider) and `new_string` being that line plus four new sections. Each section:

- §3 Workspaces — ~80 lines, sourced from Step 6.1
- §4 Feature gates — ~70 lines, sourced from Step 6.2 (also import the additive/`?`/`dep:` discipline currently in SKILL.md §VIII)
- §5 .cargo/config.toml — ~70 lines, sourced from Step 6.3
- §6 Registries & publishing — ~50 lines, sourced from Step 6.4

- [ ] **Step 6.6: Verify line count and placeholder absence**

```bash
wc -l skills/rust/cargo.md
grep -nE '\[Insert|TBD|TODO|placeholder' skills/rust/cargo.md
```

Expected: cargo.md is now ~540–600 lines total. No placeholders.

---

## Task 7: Append cargo.md §7 Subcommand ecosystem + §8 sccache

**Files:**
- Modify: `skills/rust/cargo.md`

- [ ] **Step 7.1: Resolve Context7 IDs (or WebFetch crate READMEs) for each subcommand**

For each of: clippy, rustfmt, cargo-expand, cargo-nextest, cargo-deny, cargo-audit, cargo-hack, cargo-machete, cargo-udeps, cargo-flamegraph, cargo-binstall, cargo-watch, cargo-edit, cargo-msrv, cargo-component, wasm-tools, sccache —

1. Try `resolve-library-id` with the tool name.
2. If a match exists, query for "what does this do, how to install, the single most-used invocation".
3. If no Context7 match, `WebFetch` the crate's `https://crates.io/crates/<name>` page (or the github README).

- [ ] **Step 7.2: Build the subcommand table**

For each tool: one-paragraph (1–3 sentences) purpose, install command, and the canonical invocation. Group them into a markdown table where rows are tools and columns are Purpose / Install / Canonical invocation.

- [ ] **Step 7.3: Write §8 sccache**

Cover: what it is, `RUSTC_WRAPPER=sccache` activation, what it caches (rustc invocations) vs what it doesn't (linking), concurrency safety, `sccache --show-stats`, when payoff is high (overlapping dep graphs across agents).

- [ ] **Step 7.4: Append to cargo.md**

Use the Edit tool. Target sections combined: ~90 lines.

- [ ] **Step 7.5: Verify**

```bash
wc -l skills/rust/cargo.md
grep -nE '\[Insert|TBD|TODO|placeholder' skills/rust/cargo.md
```

Expected: ~630–690 lines. No placeholders.

---

## Task 8: Append cargo.md §9 Parallel-agent build workflows + §10 JSON message format

**Files:**
- Modify: `skills/rust/cargo.md`

- [ ] **Step 8.1: Read the current §IX from SKILL.md**

```bash
sed -n '830,983p' skills/rust/SKILL.md
```

This is the verbatim source for §9. It is already well-edited; the port is mostly a copy with light section-header renaming (§IX → §9) and any cross-reference fixes.

- [ ] **Step 8.2: Query Context7 for JSON message format**

```text
query-docs $CARGO_BOOK_ID "cargo --message-format=json compiler-message compiler-artifact build-finished build-script-executed JSON output reasons fields"
```

- [ ] **Step 8.3: Append §9 (verbatim port) + §10 (JSON output) to cargo.md**

§9 — verbatim port of SKILL.md lines 830–983 with heading level reset to `## §9. Parallel-agent build workflows` and subheadings to `### …`. ~150 lines.

§10 — a tight reference for parsing cargo's JSON output with `jq`. ~30 lines. Include the snippet for extracting errors:

```bash
cargo check -p mycrate --message-format=json 2>&1 \
  | jq 'select(.reason == "compiler-message" and .message.level == "error")'
```

Plus the exit-code gate pattern and a one-paragraph note on `cargo-metadata` for static workspace inspection.

- [ ] **Step 8.4: Verify total cargo.md length**

```bash
wc -l skills/rust/cargo.md
```

Expected: ~810–870 lines. (Spec target was ~600; the verbatim §9 port plus richer §1–2 content typically lands higher. That's fine — the file is the canonical cargo reference. Document the size honestly.)

- [ ] **Step 8.5: Run a final grep for placeholders**

```bash
grep -nE '\[Insert|TBD|TODO|placeholder|XXX' skills/rust/cargo.md
```

Expected: no matches.

---

## Task 9: Bootstrap rustc.md — frontmatter + §1 Invocation + §2 Codegen + §3 RUSTFLAGS

**Files:**
- Create: `skills/rust/rustc.md`

- [ ] **Step 9.1: Query Context7 for rustc invocation + codegen flags**

```text
query-docs $RUSTC_BOOK_ID "rustc -C codegen options opt-level lto codegen-units panic target-cpu target-feature strip debuginfo incremental link-arg relocation-model"
```

- [ ] **Step 9.2: Query Context7 for RUSTFLAGS precedence**

```text
query-docs $RUSTC_BOOK_ID "RUSTFLAGS env variable precedence build.rustflags target.<triple>.rustflags command line how cargo combines rustflags from multiple sources"
```

- [ ] **Step 9.3: Write rustc.md**

Use the Write tool:

```markdown
---
name: rustc
description: |
  Practical rustc reference for the daily-driver knobs that change build
  output: codegen flags, RUSTFLAGS precedence, target triples and tiers,
  lint levels and groups, editions, sanitizers, conditional compilation,
  --print queries, and useful debug flags. Companion to the rust skill —
  open this when the task involves compiler behavior beyond what cargo
  exposes directly.
type: reference
version: 5.1.0
---

# rustc — Practical Compiler Knobs

This file covers what an engineer needs to drive rustc through cargo (and
occasionally direct) without reading the full Rustc Book. Every flag here
is sourced from the Rustc Book (queried via Context7). Internals (MIR/HIR
phases, the compilation pipeline) are out of scope — see the Rustc Dev
Guide if you need them.

---

## §1. Invocation basics

[Insert content sourced from Context7. Cover: rustc vs cargo rustc — when
to drop to direct rustc (one-off scripts, debugging codegen with no
project, building build.rs target). Mention -h flag groups (-C, -W, -Z,
--emit, --print). ~25 lines.]

---

## §2. Codegen flags (-C)

[Insert content sourced from Step 9.1. Cover each flag with one row in
a markdown table: opt-level (0/1/2/3/s/z meanings); lto (off/thin/fat);
codegen-units (defaults + tradeoff); panic (unwind/abort); target-cpu /
target-feature; strip (none/debuginfo/symbols); debuginfo (0/1/2);
incremental; link-arg; relocation-model. Length: ~70 lines.]

---

## §3. RUSTFLAGS

[Insert content sourced from Step 9.2. Cover the precedence chain:
command-line -C > [target.<triple>] rustflags > [build] rustflags >
RUSTFLAGS env > [host] rustflags. Common values:
RUSTFLAGS="-D warnings",
RUSTFLAGS="-C target-cpu=native",
RUSTFLAGS="-C link-arg=-fuse-ld=lld". Note the cache-busting gotcha:
changing RUSTFLAGS invalidates the incremental cache. ~40 lines.]

---
```

Replace `[Insert ...]` blocks with the actual content. No placeholders in the committed file.

- [ ] **Step 9.4: Verify**

```bash
wc -l skills/rust/rustc.md
grep -nE '\[Insert|TBD|TODO|placeholder' skills/rust/rustc.md
```

Expected: ~155 lines. No placeholders.

---

## Task 10: Append rustc.md §4 Targets + §5 Lints + §6 Editions + §7 Sanitizers

**Files:**
- Modify: `skills/rust/rustc.md`

- [ ] **Step 10.1: Query Context7 for target triples**

```text
query-docs $RUSTC_BOOK_ID "target triple format arch-vendor-os-env platform support tier 1 tier 2 tier 3 list of supported targets x86_64-unknown-linux-gnu aarch64-apple-darwin wasm32"
```

- [ ] **Step 10.2: Query Context7 for lint system**

```text
query-docs $RUSTC_BOOK_ID "rustc lints allow warn deny forbid lint groups unused warnings future_incompatible rust_2018_idioms nonstandard_style let_underscore --cap-lints"
```

- [ ] **Step 10.3: Query Context7 for editions**

```text
query-docs $RUSTC_BOOK_ID "rust edition 2015 2018 2021 2024 differences migration cargo fix --edition --edition-idioms"
```

- [ ] **Step 10.4: Query Context7 for sanitizers**

```text
query-docs $RUSTC_BOOK_ID "rustc -Z sanitizer address leak thread memory hwaddress unstable nightly platform restrictions"
```

- [ ] **Step 10.5: Append §4 through §7 to rustc.md**

§4 Target triples — anatomy of `arch-vendor-os-env`, the canonical triples developers hit, tier 1/2/3 explanation, `rustup target add/list/remove`. ~45 lines.

§5 Lints — levels (allow/warn/deny/forbid with forbid's special semantics), lint groups, `#![deny(...)]` in crate root vs `cargo clippy -- -D warnings`, `--cap-lints` for dep suppression. Include the table of canonical lint groups. ~40 lines.

§6 Editions — what each edition gates, `edition = "2024"` placement, `cargo fix --edition` migration flow, `--edition-idioms` for optional cleanup. ~25 lines.

§7 Sanitizers — `-Z sanitizer=...` (nightly only), required RUSTFLAGS, target restrictions (most are linux-gnu-only), when to reach for each. ~25 lines.

- [ ] **Step 10.6: Verify**

```bash
wc -l skills/rust/rustc.md
grep -nE '\[Insert|TBD|TODO|placeholder' skills/rust/rustc.md
```

Expected: ~290–310 lines. No placeholders.

---

## Task 11: Append rustc.md §8 Conditional compilation + §9 Print queries + §10 Debug flags

**Files:**
- Modify: `skills/rust/rustc.md`

- [ ] **Step 11.1: Query Context7 for cfg attribute**

```text
query-docs $RUSTC_BOOK_ID "rustc cfg attribute conditional compilation cfg(feature) cfg(target_os) cfg(target_arch) cfg(debug_assertions) --cfg --check-cfg cfg! macro vs attribute"
```

- [ ] **Step 11.2: Query Context7 for --print queries**

```text
query-docs $RUSTC_BOOK_ID "rustc --print cfg target-list target-spec-json sysroot target-libdir rustc-commit-hash code-models relocation-models link-args"
```

- [ ] **Step 11.3: Query Context7 for debug flags**

```text
query-docs $RUSTC_BOOK_ID "rustc debug flags -Z time-passes -Z print-type-sizes --emit llvm-ir --emit asm --emit mir cargo build -v -vv -Z self-profile compile-time profiling"
```

- [ ] **Step 11.4: Append §8, §9, §10 to rustc.md**

§8 Conditional compilation — all the `cfg` predicates, custom `--cfg foo` and `--check-cfg cfg(foo)`, the `cfg!()` runtime macro vs `#[cfg]` compile-time attribute distinction. ~35 lines.

§9 Print queries — table of useful `rustc --print` invocations with what each is good for. ~25 lines.

§10 Debug flags — `-Z time-passes`, `-Z print-type-sizes`, `--emit=…`, `cargo build -v`/`-vv`, `-Z self-profile`. ~25 lines.

- [ ] **Step 11.5: Final rustc.md verification**

```bash
wc -l skills/rust/rustc.md
grep -nE '\[Insert|TBD|TODO|placeholder|XXX' skills/rust/rustc.md
```

Expected: ~375–400 lines (spec target was ~250; landed thicker because Context7 grounding produces richer tables — acceptable). No placeholders.

---

## Task 12: Trim SKILL.md §VIII — replace with cargo.md pointer

**Files:**
- Modify: `skills/rust/SKILL.md:677-828`

- [ ] **Step 12.1: Read the current §VIII**

```bash
sed -n '677,828p' skills/rust/SKILL.md
```

Confirm the boundaries (it ends just before `## IX. Parallel Agent Build Workflows`).

- [ ] **Step 12.2: Compose the replacement**

The replacement is ~25 lines:

```markdown
## VIII. Cargo & Feature Gates

For the full cargo surface — commands, Cargo.toml schema, workspaces,
[profile.*] tuning, .cargo/config.toml, registries, the subcommand
ecosystem (clippy/rustfmt/expand/nextest/deny/audit/hack/machete/etc.),
sccache, and machine-readable output — see `cargo.md` in this skill.

The four rules that keep the feature graph sane (always memorize these):

- **Features are additive.** Cargo unifies features across the dep graph.
  "Feature A XOR feature B" breaks downstream.
- **Every new dependency gets its own named feature.** `hashbrown = ["dep:hashbrown"]`
  — never gate a dep behind an abstract feature like `alloc` or `std`.
- **Propagate with `?` syntax:** `"<crate>?/json"` only forwards if the
  `<crate>` dep is enabled.
- **`default-features = false` at workspace level;** enable what you need
  per-crate. Minimizes default compile surface.

The three-tier system (`no_std` / `alloc` / `std`) for library crates and
the canonical sealed-trait + cfg-gated impl pattern live in `cargo.md §4`.

For parallel-agent build patterns — `CARGO_TARGET_DIR` isolation, worktree
discipline, `-j` throttling, wave-gate vs in-lane checks, the canonical
shell preamble — see `cargo.md §9`.
```

- [ ] **Step 12.3: Apply the edit**

Use the Edit tool with `old_string` = the entire current §VIII content (lines 677–828) and `new_string` = the replacement.

- [ ] **Step 12.4: Verify**

```bash
grep -n '^## VIII\|^## IX' skills/rust/SKILL.md
sed -n '/^## VIII/,/^## IX/p' skills/rust/SKILL.md | wc -l
```

Expected: §VIII is now ~25 lines. §IX header is still at its original position (next task handles it).

---

## Task 13: Trim SKILL.md §IX — replace with cargo.md pointer

**Files:**
- Modify: `skills/rust/SKILL.md` (§IX block)

- [ ] **Step 13.1: Compose the replacement**

```markdown
## IX. Parallel Agent Build Workflows

The full operational discipline — `CARGO_TARGET_DIR` per-agent isolation,
git-worktree-based lane isolation, `CARGO_BUILD_JOBS` throttling, scoped
checks vs `--workspace`, wave-gate vs in-lane semantics, `sccache` for
shared compilation cache, machine-readable output gating, and the
canonical shell preamble with `trap … EXIT` cleanup — lives in `cargo.md §9`.

Headline rules to memorize:

- **Never set `CARGO_TARGET_DIR` globally.** Always per-agent shell.
- **Cargo holds a file lock on `target/`.** Two agents on the same `target/`
  serialize, error, or corrupt artifacts. Always isolate.
- **Wave-gate checks are serial** (one `cargo check --workspace` at a time
  on the main `target/`). **In-lane checks are fully parallel** (each
  agent on its own `CARGO_TARGET_DIR`).
- **Scope checks to affected crates** (`-p crate`) inside lanes; only the
  wave-gate touches `--workspace`.
```

- [ ] **Step 13.2: Apply the edit**

Use Edit with `old_string` = full current §IX (the verbatim block now lives in `cargo.md`, so deletion is safe).

- [ ] **Step 13.3: Verify**

```bash
grep -n '^## IX\|^## X' skills/rust/SKILL.md
```

Expected: §IX is now compact, §X (Patterns & Idioms) immediately follows.

---

## Task 14: Trim SKILL.md §XI Module Organization — replace with pointer to module-organization.md

**Files:**
- Modify: `skills/rust/SKILL.md` (§XI block, currently ~127 lines)

- [ ] **Step 14.1: Read the current §XI**

```bash
sed -n '/^## XI\. /,/^## XII\. /p' skills/rust/SKILL.md
```

- [ ] **Step 14.2: Compose ~30-line replacement**

Pull only the headline rules; depth goes to `module-organization.md`. Keep:

- The four-tier pattern (`crate | mod.rs | file | inline`) named with a sentence each
- The `mod impls / types / traits / utils` convention named in 3–4 lines
- The `pub(crate)` default rule in 2 lines
- The absolute-path discipline in 2 lines
- One-paragraph reference to `module-organization.md` for the depth

- [ ] **Step 14.3: Apply the edit**

Use Edit with `old_string` = full §XI block and `new_string` = the ~30-line summary.

- [ ] **Step 14.4: Verify**

```bash
sed -n '/^## XI\. /,/^## XII\. /p' skills/rust/SKILL.md | wc -l
```

Expected: ~30 lines.

---

## Task 15: Trim SKILL.md §XIV Macros — replace with pointer to macros.md

**Files:**
- Modify: `skills/rust/SKILL.md` (§XIV block, currently ~64 lines)

- [ ] **Step 15.1: Read current §XIV**

```bash
sed -n '/^## XIV\. /,/^## XV\. /p' skills/rust/SKILL.md
```

- [ ] **Step 15.2: Compose ~25-line replacement**

Keep:

- The three flavors in one sentence each (declarative, derive, attribute, function-like)
- The "when to reach for a macro" rule of thumb (~5 lines)
- The decision matrix in a small table (3 rows: "code generation across many items", "DSL", "cross-cutting boilerplate")
- One paragraph pointing to `macros.md` for syn/quote/proc-macro2 depth

- [ ] **Step 15.3: Apply the edit**

Use Edit.

- [ ] **Step 15.4: Verify**

```bash
sed -n '/^## XIV\. /,/^## XV\. /p' skills/rust/SKILL.md | wc -l
```

Expected: ~25 lines.

---

## Task 16: Update SKILL.md WebAssembly + Reference Files index

**Files:**
- Modify: `skills/rust/SKILL.md` (Reference Files section near end, lines 1370–1430)

- [ ] **Step 16.1: Read the current Reference Files section**

```bash
sed -n '/^## Reference Files/,$p' skills/rust/SKILL.md
```

- [ ] **Step 16.2: Compose the new Reference Files section**

Drop the WebAssembly entries (`wasm.md`, `wasmtime-host.md`). Add the new entries (`cargo.md`, `rustc.md`). Restructure into:

```markdown
## Reference Files

Progressive disclosure — open these only when the task enters their area.

### Core Rust

- **`ownership-borrowing.md`** — detailed ownership patterns, split borrows, lifetime elision.
- **`types-strings.md`** — `String`/`&str`, numeric types, `From`/`Into`/`TryFrom` conversion surface.
- **`errors-iteration.md`** — error-handling chains, iterator adaptors, `Result` ergonomics.
- **`concurrency-memory.md`** — async, threads, `Arc`/`Mutex`/`RwLock`, channels, `Send`/`Sync`.
- **`advanced-traps.md`** — `unsafe`, FFI, performance pitfalls, drop order.
- **`typespace.md`** — generics, trait objects, `impl Trait`, associated types, GATs, const
  generics, object safety, variance, `PhantomData`, type-state.
- **`macros.md`** — declarative macro patterns (fragment specifiers, repetition, recursion,
  hygiene); procedural macros (derive/attribute/function-like, syn/quote/proc-macro2 triad);
  proc-macro crate structure, testing with trybuild.
- **`module-organization.md`** — the four-tier pattern depth, inline `impls/types/traits/utils`,
  visibility ladder, absolute-path discipline, naming-depth as a code smell.

### Tooling

- **`cargo.md`** — full cargo surface: commands, Cargo.toml schema, workspaces, feature
  gates, `.cargo/config.toml`, registries/publishing, the subcommand ecosystem
  (clippy/rustfmt/nextest/deny/audit/hack/machete/component/etc.), sccache, parallel-agent
  build workflows, JSON message format.
- **`rustc.md`** — practical compiler knobs: codegen flags (`-C` family), RUSTFLAGS
  precedence, target triples and tiers, lint levels and groups, editions, sanitizers,
  conditional compilation (`cfg` predicates), `--print` queries, debug flags
  (`--emit`, `-Z time-passes`, etc.).

### Ecosystem — docs.rs is the source of truth

This skill deliberately does NOT ship per-crate cheatsheets. Crate APIs drift; a local file
rots the moment a minor version bumps. Go to the canonical indexes:

- **`https://docs.rs/{crate}/latest/{crate}/all.html`** — every item the crate exports on one
  page. Fastest way to see what exists before coding against it.
- **`https://docs.rs/crate/{crate}/latest/features`** — full feature matrix for a given
  version, including which features pull in which deps.
- **`https://crates.io/crates/{crate}`** — version history, reverse deps, source links.

Reach for those over memory whenever the question is "does this crate have X?" or "what
features does X gate?". Examples: `docs.rs/tokio/latest/tokio/all.html`,
`docs.rs/crate/axum/latest/features`, `docs.rs/sqlx/latest/sqlx/all.html`.

### Related skills

- **`code-style`** (sibling skill) — personal preferences layer (MSRV floor, hashbrown over
  std HashMap, naming idioms, module convention). Load it whenever producing Rust the user
  will read — this skill stays project- and style-agnostic.
- **`webassembly`** (sibling skill) — language-agnostic WIT syntax, component model
  semantics, WASI capability model, binary format. Cross to it whenever the question is
  conceptual ("what does this WIT contract mean").
- **`wasmtime`** (sibling skill) — Rust-side host embedding: `Engine`/`Store`/`Linker`/
  `Component`, `bindgen!` macro, WASI grants. Cross to it for any host-side WASM runtime
  question.
- **`workflow`** (sibling skill) — branching conventions, GH issue/PR/milestone management,
  CI/CD patterns, Rust workspace scaffolding, sprint/phase structure.
```

- [ ] **Step 16.3: Apply the edit**

Use Edit with `old_string` = the full current Reference Files block (and any WebAssembly section above it) and `new_string` = the replacement above.

- [ ] **Step 16.4: Verify**

```bash
grep -nE 'wasm\.md|wasmtime-host\.md' skills/rust/SKILL.md
```

Expected: no matches.

```bash
grep -nE 'cargo\.md|rustc\.md' skills/rust/SKILL.md
```

Expected: multiple matches (in the new Reference Files entries and in the §VIII / §IX / §XI / §XIV pointer paragraphs).

---

## Task 17: Final SKILL.md line count + frontmatter bump

**Files:**
- Modify: `skills/rust/SKILL.md` (frontmatter only)

- [ ] **Step 17.1: Get current line count**

```bash
wc -l skills/rust/SKILL.md
```

Expected: ~950–1050 lines.

- [ ] **Step 17.2: Update frontmatter**

The frontmatter currently has `version: 5.0.4`. Edit it to `version: 5.1.0`. Update the description to drop the wasmtime mention and add the new `cargo.md`/`rustc.md` mentions.

Use Edit. Target `old_string` = current frontmatter block. `new_string`:

```yaml
---
name: Rust
slug: rust
version: 5.1.0
description: |
  Make any agent, session, or cron fluent in idiomatic Rust. Covers ownership,
  borrowing, lifetimes, error handling, async (tokio), traits, generics, trait
  objects, the no_std/alloc/std tier system, declarative and procedural macros,
  and pointers to docs.rs / crates.io for ecosystem crate lookup. Companion
  reference files: `cargo.md` (full cargo surface — commands, manifest, workspaces,
  features, profiles, .cargo/config.toml, subcommand ecosystem, sccache,
  parallel-agent build workflows) and `rustc.md` (practical compiler knobs —
  codegen flags, RUSTFLAGS precedence, target triples, lints, editions,
  sanitizers, cfg, --print, debug flags). Attach this skill whenever producing
  or reviewing Rust. Not project-specific and not style-opinionated — personal
  preferences live in the `code-style` skill; project rules live in the project
  itself. Language-agnostic WebAssembly material lives in the `webassembly`
  skill; Rust-side host embedding lives in the `wasmtime` skill.
metadata:
  openclaw:
    emoji: "🦀"
    requires:
      bins: ["rustc", "cargo"]
    os: ["linux", "darwin", "win32"]
---
```

- [ ] **Step 17.3: Verify**

```bash
head -25 skills/rust/SKILL.md
```

Expected: frontmatter shows `version: 5.1.0` and the new description.

---

## Task 18: Bump plugin.json + marketplace.json + CHANGELOG.md

**Files:**
- Modify: `skills/rust/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `CHANGELOG.md`

- [ ] **Step 18.1: Bump skills/rust/plugin.json**

Edit `version` from `5.0.4` to `5.1.0`. Also refresh the `description` field to match the new SKILL.md frontmatter description (a tighter one-paragraph version). Confirm no other fields drift.

- [ ] **Step 18.2: Bump marketplace.json**

Edit the top-level `version` from `5.0.4` to `5.1.0`. Edit the `rust` plugin entry's `version` to `5.1.0`. Refresh its `description` field too.

```bash
grep -A2 '"name": "rust"' .claude-plugin/marketplace.json
```

Expected: shows `"version": "5.1.0"` after edit.

- [ ] **Step 18.3: Create or update CHANGELOG.md**

```bash
ls CHANGELOG.md 2>/dev/null && echo "exists" || echo "create"
```

If exists, prepend a 5.1.0 entry. If not, create it with this content:

```markdown
# Changelog

## 5.1.0 — 2026-05-20

### rust skill — restructure
- Extracted `§VIII Cargo & Feature Gates` and `§IX Parallel Agent Build Workflows` from `SKILL.md` into a new dedicated `cargo.md` (~800 lines, Context7-grounded against the Cargo Book).
- Added a new `rustc.md` covering practical compiler knobs (codegen flags, RUSTFLAGS, targets, lints, editions, sanitizers, cfg, --print, debug flags) — Context7-grounded against the Rustc Book.
- Deleted the orphaned `skills/rust/wasm.md` and `skills/rust/wasmtime-host.md` — their content has moved to the standalone `wasmtime` and `webassembly` skills.
- Trimmed `SKILL.md` from 1430 to ~1000 lines: lightly condensed `§XI Module Organization` and `§XIV Macros` (depth already lived in `module-organization.md` and `macros.md`).
- Refreshed the `Reference Files` index to add `cargo.md`/`rustc.md` and drop the deleted WASM files.
- Bumped frontmatter, `plugin.json`, and the marketplace entry to 5.1.0.

### marketplace-wide sweep
[Filled in after Task 24 completes — substantive changes per sibling skill.]

### infrastructure
- Spec at `docs/superpowers/specs/2026-05-20-rust-skill-refactor-design.md`.
- Plan at `docs/superpowers/plans/2026-05-20-rust-skill-refactor.md`.
```

- [ ] **Step 18.4: Verify all three files**

```bash
grep -nE '"version"' skills/rust/plugin.json .claude-plugin/marketplace.json
head -5 CHANGELOG.md
```

Expected: all show 5.1.0.

---

## Task 19: Sync rust skill to ~/.claude and verify parity

**Files:** None (uses existing install script).

- [ ] **Step 19.1: Run installer**

```bash
./scripts/install.sh rust
```

Expected: copies `skills/rust/*` into `~/.claude/skills/rust/`. Output shows files copied.

- [ ] **Step 19.2: Verify parity**

```bash
./scripts/install.sh --status
```

Expected: `rust` is "up to date" (or equivalent installer-side language).

- [ ] **Step 19.3: Spot-check installed copy**

```bash
ls -la ~/.claude/skills/rust/
diff -q skills/rust/SKILL.md ~/.claude/skills/rust/SKILL.md
diff -q skills/rust/cargo.md ~/.claude/skills/rust/cargo.md
diff -q skills/rust/rustc.md ~/.claude/skills/rust/rustc.md
```

Expected: directory shows `cargo.md` and `rustc.md` present; no `wasm.md` or `wasmtime-host.md`; diffs are silent.

---

## Task 20: Commit the rust refactor on v5.1.0-dev.0

**Files:** None (commit only).

- [ ] **Step 20.1: Stage everything**

```bash
git add skills/rust/ .claude-plugin/marketplace.json CHANGELOG.md docs/superpowers/plans/
```

- [ ] **Step 20.2: Show diff for sanity check**

```bash
git diff --cached --stat
```

Expected:
- `skills/rust/SKILL.md`: large reduction
- `skills/rust/cargo.md`: new file, ~800 lines
- `skills/rust/rustc.md`: new file, ~400 lines
- `skills/rust/wasm.md`: deleted
- `skills/rust/wasmtime-host.md`: deleted
- `skills/rust/plugin.json`: small diff (version + description)
- `.claude-plugin/marketplace.json`: small diff (version + rust description)
- `CHANGELOG.md`: new or updated
- `docs/superpowers/plans/2026-05-20-rust-skill-refactor.md`: new file

- [ ] **Step 20.3: Commit**

```bash
git commit -m "$(cat <<'EOF'
refactor(skills/rust): extract cargo.md + rustc.md; trim SKILL.md

- New: cargo.md — full cargo surface (commands, manifest, workspaces,
  features, profiles, .cargo/config.toml, registries, subcommands,
  sccache, parallel-agent build workflows, JSON output). Context7-grounded
  against the Cargo Book.
- New: rustc.md — practical compiler knobs (codegen, RUSTFLAGS, targets,
  lints, editions, sanitizers, cfg, --print, debug flags). Context7-grounded
  against the Rustc Book.
- Removed: wasm.md, wasmtime-host.md — content now lives in the standalone
  webassembly and wasmtime sibling skills.
- Trimmed SKILL.md from 1430 to ~1000 lines: §VIII and §IX replaced with
  pointer paragraphs; §XI and §XIV condensed (depth in their own files).
- Bumped versions to 5.1.0 (skills/rust/plugin.json, SKILL.md frontmatter,
  marketplace.json).
- Synced to ~/.claude/skills/rust/.
EOF
)"
```

- [ ] **Step 20.4: Push**

```bash
git push origin v5.1.0-dev.0
```

---

## Task 21: Dispatch 7 parallel agents for the sibling sweep

**Files:** None (agent dispatch).

> **STOP and confirm with the user before dispatching.** Show the brief template (Step 21.2) for one skill and get a "go" before firing all seven in parallel.

- [ ] **Step 21.1: Confirm dispatch readiness**

```bash
ls skills/
```

Expected: directories `finance`, `polymarket`, `rust`, `trader`, `typing`, `wasmtime`, `webassembly`, `workflow`. Confirm exactly 7 non-rust skills.

- [ ] **Step 21.2: Compose the per-agent brief template**

```text
You are a documentation auditor for the Claude Code skill at /Users/jo3/src/fl03/claude/skills/<SKILL>/.

CONTEXT
The fl03-skills marketplace is being brought to a unified "portable knowledge silo" standard at version 5.1.0. The rust skill was just refactored as the reference baseline; you have NOT seen that refactor but you should treat this skill the same way.

DOCTRINE (extracted from the rust skill baseline)
1. Progressive disclosure: SKILL.md is primer + index; depth lives in companion reference files. If a topic has its own .md, SKILL.md gives a summary + pointer, not a duplicate.
2. Context7-grounded facts: every library/API/CLI claim must be verifiable against upstream docs via Context7 MCP. If a fact can't be sourced, remove it. WebFetch on the canonical docs page is an acceptable fallback when Context7 has no entry.
3. Terse over redundant: if two sentences say the same thing, keep one. If a table communicates faster than prose, use the table.
4. Frontmatter consistency: name, slug, version (5.1.0 if substantive change lands), and a description trigger paragraph that lists concrete triggers ("when the user asks about X", "when the task involves Y").
5. Portable knowledge silo: any agent loading this skill cold should have working knowledge of the topic. No assumed shared context.

YOUR TASK
1. Read every file in skills/<SKILL>/.
2. Identify thin sections (missing depth that the topic actually needs) and thick sections (duplication, wordy passages, content that belongs in a companion file but lives in SKILL.md).
3. Add depth where thin, condense where thick. All factual additions must be Context7-grounded.
4. Verify frontmatter on every file. The skill's primary version source is skills/<SKILL>/plugin.json. If substantive changes land, bump to 5.1.0; if cosmetic only, leave the version alone and note this in your summary.
5. DO NOT touch skills/rust/.
6. DO NOT add new skills.
7. DO NOT restructure across skills (don't move content into or out of this skill's directory).

"Substantive change" definition: any addition or removal of a section, any rewrite of more than ~25 lines in a single file, any frontmatter description change, or any cross-skill pointer update. Pure typo fixes, single-line wording tweaks, and reflow do not bump version.

EXPECTED OUTPUT (when you're done)
A summary in this exact format:

  Skill: <SKILL>
  Substantive change: yes | no
  Version: 5.0.4 → <5.1.0 or unchanged>
  Files touched: <comma-separated list>
  Added: <bullet list of what you added and why>
  Removed: <bullet list of what you removed and why>
  Cross-skill notes: <any references to other skills that need attention; or "none">

CONSTRAINTS
- Read/Edit/Write/Bash/Grep tools only.
- No Agent recursion (don't dispatch nested agents).
- Commit your changes locally; don't push.
- Work in /Users/jo3/src/fl03/claude/ — the current branch is v5.1.0-dev.0.
```

- [ ] **Step 21.3: Get user "go" on the brief**

Surface the brief template to the user. Confirm it captures intent before firing 7 agents in parallel.

- [ ] **Step 21.4: Dispatch all 7 agents in a single message**

In ONE message, call the `Agent` tool 7 times with `subagent_type: "general-purpose"`, substituting the skill name in each brief:

1. `finance`
2. `polymarket`
3. `trader`
4. `typing`
5. `wasmtime`
6. `webassembly`
7. `workflow`

Set `run_in_background: false` so results return in-band and can be reviewed before integration.

- [ ] **Step 21.5: Capture each agent's summary**

When all 7 return, capture their summary blocks. They will be needed for Task 22's review.

---

## Task 22: Review agent reports + integrate

**Files:** Multiple under `skills/<sibling>/`.

- [ ] **Step 22.1: Read each agent summary**

For each of the 7 returned summaries: note Substantive Change (yes/no), Files Touched, Added/Removed bullets, Cross-skill notes.

- [ ] **Step 22.2: Run a diff check**

```bash
git status
git diff --stat
```

Expected: changes spread across the 7 swept skill directories. Should NOT touch `skills/rust/`.

- [ ] **Step 22.3: Spot-check three diffs**

Pick three of the seven (e.g., `finance`, `typing`, `wasmtime`) and read the full diff:

```bash
git diff skills/finance/
git diff skills/typing/
git diff skills/wasmtime/
```

Verify: changes match the agent's summary, no scope creep, no broken markdown.

- [ ] **Step 22.4: Resolve cross-skill notes**

If any agent flagged a cross-skill reference (e.g., webassembly references the now-deleted `skills/rust/wasmtime-host.md`), fix the reference in the affected file.

- [ ] **Step 22.5: Verify markdown integrity**

```bash
for f in $(git diff --name-only | grep '\.md$'); do
  head -1 "$f" | grep -qE '^(---|#)' && echo "OK $f" || echo "BROKEN $f"
done
```

Expected: every changed .md starts with either YAML frontmatter delimiter or an H1 heading.

---

## Task 23: Bump versions for changed siblings + update marketplace.json + CHANGELOG.md

**Files:**
- Modify: per-skill `plugin.json` files (only where Substantive Change = yes)
- Modify: `.claude-plugin/marketplace.json`
- Modify: `CHANGELOG.md`

- [ ] **Step 23.1: For each skill where Substantive Change = yes, bump plugin.json**

```bash
# Example for finance if it changed:
grep '"version"' skills/finance/plugin.json
# Edit to 5.1.0
```

Repeat for each skill flagged as substantive in Task 22.1.

- [ ] **Step 23.2: Update marketplace.json**

For each substantively-changed plugin, update its `version` field in `.claude-plugin/marketplace.json` to `5.1.0`. Refresh its `description` if the agent's summary indicates the trigger surface changed.

- [ ] **Step 23.3: Fill in the CHANGELOG.md "marketplace-wide sweep" section**

Replace the `[Filled in after Task 24 completes — ...]` placeholder with the actual per-skill entries based on agent summaries. Format:

```markdown
### marketplace-wide sweep

- **finance** — <one-line summary of added/removed>
- **polymarket** — <one-line summary; or "no substantive change">
- **trader** — <one-line summary>
- **typing** — <one-line summary>
- **wasmtime** — <one-line summary>
- **webassembly** — <one-line summary>
- **workflow** — <one-line summary>
```

- [ ] **Step 23.4: Verify**

```bash
grep -A1 '"name":' .claude-plugin/marketplace.json | grep -E 'name|version'
```

Expected: every plugin entry's version matches its `plugin.json`.

```bash
grep -nE '\[Filled in|TODO|TBD' CHANGELOG.md
```

Expected: no matches.

---

## Task 24: Final sync to ~/.claude + parity check

**Files:** None (uses install script).

- [ ] **Step 24.1: Run full sync**

```bash
./scripts/install.sh --all
```

Expected: every skill copied. Output shows file counts per skill.

- [ ] **Step 24.2: Verify parity**

```bash
./scripts/install.sh --status
```

Expected: every skill "up to date".

- [ ] **Step 24.3: Spot-check one swept skill's installed copy**

```bash
diff -rq skills/finance/ ~/.claude/skills/finance/ | head
```

Expected: empty (no differences).

- [ ] **Step 24.4: Confirm orphaned WASM files are gone from ~/.claude**

```bash
ls ~/.claude/skills/rust/wasm.md ~/.claude/skills/rust/wasmtime-host.md 2>&1
```

Expected: "No such file or directory" for both.

---

## Task 25: Final commit + push v5.1.0-dev.0

**Files:** None (commit + push only).

- [ ] **Step 25.1: Stage everything**

```bash
git add skills/ .claude-plugin/marketplace.json CHANGELOG.md
git status
```

Expected: changes across the swept skills, marketplace.json, CHANGELOG.md.

- [ ] **Step 25.2: Commit**

```bash
git commit -m "$(cat <<'EOF'
chore(skills): marketplace-wide sweep — bring siblings to v5.1.0 baseline

Parallel audit of finance, polymarket, trader, typing, wasmtime, webassembly,
and workflow by 7 dispatched general-purpose agents. Each skill was audited
for thin/thick sections, Context7-grounded against upstream docs, and
frontmatter-verified. See CHANGELOG.md for per-skill summaries.

Marketplace version bumped to 5.1.0. Per-skill version bumps applied only to
skills with substantive changes (see definition in spec).
EOF
)"
```

- [ ] **Step 25.3: Push**

```bash
git push origin v5.1.0-dev.0
```

---

## Task 26: Rebase-merge v5.1.0-dev.0 → v5.1.0

**Files:** None (git merge only).

> **STOP and confirm with the user before doing the merge.** Per `CLAUDE.md`, this is a `--rebase` strategy, not a force-push.

- [ ] **Step 26.1: Switch to v5.1.0**

```bash
git checkout v5.1.0
git pull origin v5.1.0
```

- [ ] **Step 26.2: Rebase dev.0 onto v5.1.0**

```bash
git checkout v5.1.0-dev.0
git rebase v5.1.0
```

Expected: clean rebase (no conflicts; dev.0 was branched from v5.1.0 and nothing else has landed).

- [ ] **Step 26.3: Fast-forward v5.1.0 to dev.0**

```bash
git checkout v5.1.0
git merge --ff-only v5.1.0-dev.0
git push origin v5.1.0
```

- [ ] **Step 26.4: Verify**

```bash
git log --oneline -5 v5.1.0
```

Expected: contains all the refactor + sweep commits.

---

## Task 27: Mark plan complete + surface release readiness

**Files:** None (status surface).

- [ ] **Step 27.1: Confirm final state**

```bash
git log --oneline origin/main..v5.1.0 | wc -l
```

Expected: 2–4 commits (rust refactor + sweep + any cleanup).

- [ ] **Step 27.2: Surface to user**

Report:
- v5.1.0 branch is ready
- The squash-merge `v5.1.0 → main` is the next operator-driven step (triggers the automated release pipeline per `CLAUDE.md`)
- Open issues or follow-ups noted by any of the 7 sweep agents

- [ ] **Step 27.3: Mark TaskList complete**

Update the brainstorming TaskList: task #7 (Transition to writing-plans) → completed once this plan is approved and execution begins.

---

## Self-Review Notes

**Spec coverage check:** every spec goal maps to at least one task —
- Goal 1 (cargo.md): Tasks 5–8.
- Goal 2 (rustc.md): Tasks 9–11.
- Goal 3 (SKILL.md trim ~1000 lines): Tasks 12–17.
- Goal 4 (delete orphan WASM files): Task 3.
- Goal 5 (marketplace sweep): Tasks 21–23.
- Goal 6 (Context7 grounding): Tasks 4–11 explicitly query Context7 before writing.

**Placeholder scan:** the `[Insert ...]` blocks inside Task 5/9 step templates are part of the *plan instruction* (telling the engineer to fill in the section using Context7 results during execution), not placeholders in the final artifact. The plan itself contains no "TBD" / "TODO" / "fill in later" — every step has the exact command or content the engineer needs to execute.

**Type consistency:** version is `5.1.0` throughout. Branch name is `v5.1.0-dev.0` throughout. The seven sibling skills are listed identically in every task that mentions them (`finance, polymarket, trader, typing, wasmtime, webassembly, workflow`).

**Cross-task references:** Task 18 references Task 24 (CHANGELOG sweep section); Task 22 references Task 21's summaries. No undefined symbols.
