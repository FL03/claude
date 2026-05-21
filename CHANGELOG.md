# Changelog

All notable changes to this skill marketplace are documented here. Each skill also maintains its version in its own `plugin.json`.

## v5.1.0 — 2026-05-20

### `rust` skill — restructure (5.0.4 → 5.1.0)

- **New `cargo.md`** (~1090 lines) — the full cargo surface: commands, `Cargo.toml` schema, workspaces, feature gates, `[profile.*]`, `.cargo/config.toml`, registries/publishing, the subcommand ecosystem (clippy/rustfmt/nextest/deny/audit/hack/machete/component/etc.), sccache, parallel-agent build workflows (verbatim port from SKILL.md §IX), and machine-readable output (`--message-format=json`, `cargo metadata`). Context7-grounded against The Cargo Book (`/websites/doc_rust-lang_cargo`).
- **New `rustc.md`** (~630 lines) — practical compiler knobs: codegen flags (`-C` family), RUSTFLAGS precedence, target triples and tiers, lint levels and groups, editions (2015/2018/2021/2024), sanitizers, conditional compilation (`cfg` predicates), `--print` queries, debug flags (`--emit`, `-Z time-passes`, `-Z print-type-sizes`, `-Z self-profile`). Sourced from The Rustc Book, The Rust Reference, The Edition Guide, and The Unstable Book.
- **Trimmed `SKILL.md`** from 1430 → ~1050 lines: §VIII Cargo and §IX Parallel Workflows extracted to `cargo.md`; §XI Module Organization condensed (depth in `module-organization.md`); §XIV Macros condensed (depth in `macros.md`).
- **Deleted `skills/rust/wasm.md` and `skills/rust/wasmtime-host.md`** — content now in the standalone `webassembly` and `wasmtime` sibling skills. The orphan-files cleanup completes the marketplace's per-skill encapsulation.
- Refreshed the `Reference Files` index to add `cargo.md`/`rustc.md` and drop the deleted WASM files.
- Bumped frontmatter, `plugin.json`, and the marketplace entry to 5.1.0.

### Marketplace-wide sweep

[Pending — filled in after the parallel sibling-skill sweep completes.]

### Infrastructure

- Spec at `docs/superpowers/specs/2026-05-20-rust-skill-refactor-design.md`.
- Plan at `docs/superpowers/plans/2026-05-20-rust-skill-refactor.md`.

---

## v5.0.4 — 2026-05-20 (squashed into main)

### Added
- `plugin.json` manifest for every skill, enabling independent versioning and marketplace installation
- `.claude-plugin/plugin.json` — repo-level plugin metadata
- `scripts/install.sh` — local skill installer for development workflow
- Marketplace restructured: `skills` → `plugins` array with per-skill `git-subdir` sources
- Marketplace renamed `fl03` → `fl03-skills` to avoid conflict with the shepherd marketplace

### Changed
- `.claude-plugin/marketplace.json` now lists all eight skills as individually installable plugins

---

## Skills

Authoritative version is each skill's `plugin.json`. Snapshot:

| Skill | Version | Notes |
|---|---|---|
| finance | 5.0.4 | Awaiting v5.1.0 sweep |
| polymarket | 5.0.4 | Awaiting v5.1.0 sweep |
| rust | 5.1.0 | Restructured: cargo.md + rustc.md split out; SKILL.md trimmed 1430→1050; orphan WASM files removed |
| trader | 5.0.4 | Awaiting v5.1.0 sweep |
| typing | 5.0.4 | Awaiting v5.1.0 sweep |
| wasmtime | 5.0.4 | Awaiting v5.1.0 sweep |
| webassembly | 5.0.4 | Awaiting v5.1.0 sweep |
| workflow | 5.0.4 | Awaiting v5.1.0 sweep |
