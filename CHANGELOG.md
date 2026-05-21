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

### `finance` skill — sweep (5.0.4 → 5.1.0)

- **`SKILL.md`** — Added `version: 5.1.0` to frontmatter; rewrote the description with concrete trigger keywords (Greeks, IV, Itô/SDEs, VaR/CVaR, Sharpe/Sortino/Calmar, Kelly, Markowitz, CAPM/Fama-French/APT, Vasicek/CIR/Nelson-Siegel, Monte Carlo, PDE, backtesting); collapsed the duplicated "Activation" block into the module table; added a `Canonical references` table pointing at Hull / Bjork / Shreve / Wilmott / Glasserman / Grinold-Kahn / Cochrane.
- **`QUANT.md`** — Removed the trader-policy "Drawdown rules" block (size-reduction / lockout cadence); that content lives in `@trader`. Replaced with mathematical content: Ulcer Index, Martin ratio, and a note on time-under-water as a complementary drawdown shape metric.
- **`MODELS.md`** — Added explicit put-side Theta and put-side Rho formulas; added a second-order Greeks pointer (Vanna, Volga, Charm); expanded Heston pricing with full characteristic-function form (C_j, D_j, d_j, g_j with the two (u_j, b_j) pairs), a calibration sketch, and a warning about the "Little Heston Trap" branch-cut formulation. Added a new "American Options & Early Exercise" subsection covering the free-boundary intuition, American-call-equals-European on non-dividend stocks, the optimal-exercise boundary for puts, and the three standard numerical routes (CRR binomial, Longstaff-Schwartz LSM, PSOR).
- **`plugin.json`** — Bumped to 5.1.0 with an expanded description and richer keyword set (`black-scholes`, `heston`, `var`, `portfolio-theory`, `backtesting`).
- Bumped the marketplace entry to 5.1.0 with the refreshed description.

### `trader` skill — sweep (5.0.4 → 5.1.0)

- **`SKILL.md`** — Tightened the 9-gate contract: every gate is now a precise boolean with explicit pass/fail criteria (Gate 2 net-of-fee EV with the `EV_net = p_true − entry − fee × (1 − entry)` form, Gate 4 half-Kelly $1 floor + negative-Kelly trap, Gate 5 pairwise `|ρ| ≤ 0.5`, Gate 8 ±2¢ depth + 30s staleness window). Rewrote the 7-step cycle with explicit read-only (1-2) vs write (3-7) phase separation and an atomicity note covering steps 4-5. Bumped frontmatter to 5.1.0; added cross-skill load pointer to `@finance/QUANT.md` for Kelly and EV depth.
- **`axiom.md`** — Rebuilt against the live `axiom-mcp` server source (`~/src/fl03/axiom/bin/mcp/src/impls/impl_mcp_tools.rs`). Added previously undocumented tools: `axiom_status`, `axiom_cancel_orders`, `axiom_redeem_slug`, `axiom_scan`, `axiom_watchlist`, `market_midpoint`, `market_price`, `market_candles`, and the kill-switch surface (`kill_switch_get`, `kill_engage`, `kill_disengage`, `kill_switch_set`). Fixed `axiom_buy` — added the required `side: "yes"|"no"` parameter that the wire schema enforces, plus the FAK-default note. Documented the `mcp__axiom__<tool>` Claude Code naming convention. Clarified that `market_price`/`market_candles` are BTC-only via datasync and are NOT the settlement oracle (`chainlink_btc_price` remains the Gate 3 source for BTC strikes).
- **`jailbreak.md`** — Expanded the standing-authorization list to cover the newly documented tools (status, cancel_orders, redeem_slug, scan, watchlist, kill_engage/disengage). Restricted `kill_switch_set()` with custom levels to explicit per-session operator approval. Noted the `mcp__axiom__` namespace.
- **`plugin.json`** — Bumped to 5.1.0; richer description; added `kelly` and `9-gate-contract` keywords; dropped the speculative `futures` keyword (Axiom is Polymarket-only today).
- Bumped the marketplace entry to 5.1.0 with the refreshed description.

### `polymarket` skill — sweep (5.0.4 → 5.1.0)

- **`SKILL.md`** — Rewritten as the primer + index per the v5.1.0 progressive-disclosure doctrine. Endpoint depth extracted to a new `apis.md`; strategy and exploit content stays in their existing companions. Replaced the USDC.e-only collateral description with the current pUSD wrapper (`CollateralOnramp` / `CollateralOfframp` around USDC.e). Replaced the architectural diagram with a clean four-layer table (CLOB / Relayer / Polygon CTF / UMA OO) and a vertical flow diagram. Added an explicit ID ladder (`token_id` / `condition_id` / `question_id` / `slug` / `event_id`). Added the order-lifecycle five-step table (create → submit → match-or-rest → settle → confirm) with the four order types (GTC / GTD / FOK / FAK) + `post_only` modifier. Replaced the hard-coded "~2% taker fee" claim with a per-market query pattern via `/fee-rate/{token_id}` and `/clob-markets/{condition_id}`; sample fees from the docs are 10–30 bps. Added authoritative external references and Context7 library IDs. Bumped frontmatter to 5.1.0.
- **New `apis.md`** — Endpoint reference extracted from SKILL.md. Documents all four APIs: Gamma (market discovery, no auth), CLOB (order book + trading, L2 auth for writes), Data (analytics, no auth), and Relayer-v2 (gasless tx submission, builder or relayer API key). Includes per-endpoint request/response shapes, pagination (cursor `LTE=` end-of-stream convention), per-API rate-limit matrix, the `/prices-history` "`market` = token_id" gotcha, and full L1 / L2 EIP-712 + HMAC auth header sets. Context7-grounded against `/websites/polymarket_api-reference` and `docs.polymarket.com/api-reference/*`.
- **`strategies.md`** — Corrected the 3-second sports matching delay to the documented 1-second figure. Replaced the hard-coded `0.02 * len(prices)` taker-fee assumption in the negative-risk arb scanner with a `taker_fee_rate` placeholder and a pointer to the live CLOB `/fee-rate/{token_id}` endpoint. Added `version: 5.1.0` to frontmatter.
- **`exploits.md`** — Rewrote §II "Sports Matching Delay" from 2.7 seconds to the documented 1 second; added the `itode` per-market flag pointer on `/clob-markets/{condition_id}`. Expanded §IV "Resolution Sniping" with the explicit UMA proposer bond ($750 pUSD) and dispute path. Updated the decay-tracking table with the 1s delay note. Added `version: 5.1.0` to frontmatter.
- **`plugin.json`** — Bumped to 5.1.0; rewrote the description with concrete triggers (pUSD, CTF, negative risk, relayer-v2, UMA 2h challenge, identifier ladder).
- Bumped the marketplace entry to 5.1.0 with the refreshed description.

### `workflow` skill — restructure (5.0.4 → 5.1.0)

- **`SKILL.md` rewrite.** Reorganized into eight numbered sections — branching, GH conventions, plan/sprint structure, **automated release pipeline**, CI workflows, Rust crate scaffolding, references, cross-skill pointers. Frontmatter aligned with the rust skill (multi-line description, `version` key).
- **Rebase-vs-squash decision tree** added as an explicit four-row table (track/topic → dev.N → patch → main) tagged with strategy, rationale, and required approval level. Replaces prose-split treatment.
- **New §IV "Automated Release Pipeline".** Documents every step of `.github/workflows/release.yml`: trigger semantics (subject regex + `plugin.json` cross-check), mod-10 cascade (`Z<9 patch` / `Y<9 minor` / `major`), 11-step ordered table (detect → version compute → CHANGELOG slice → tag → GH release → next-patch cut + multi-file version bump → commit/push → draft PR → dev.0 cut → orphan sweep → milestone roll), operator pre-flight requirements, post-squash verification, idempotency model, and re-dispatch recipe.
- **Removed: manual release-dance content** ("Release Collapse" section that told users to `git tag` / `gh release create` / create milestones by hand). All of that is automation-owned now; §IV documents the automation and the operator's role around it.
- **Reframed §V "CI/CD Workflows"** as explicitly scoped to Rust workspace projects (this marketplace has no compilable code, only `release.yml`). "Required Workflows" → "Recommended workflow set" with a scope note.
- **Rewrote §VI "Rust Workspace Crate Scaffolding".** Cross-refs `rust/cargo.md` §3 (workspaces) and §4 (feature gates) for cargo mechanics rather than duplicating them. Retains axiom-family project policy (mandatory env features, umbrella SDK registration, WIT directory, SDK facade rule).
- **PR template parameterized.** Test plan section no longer hard-codes Rust gates; ships a project-type table (Marketplace / Rust workspace / Hybrid).
- **`references/release-checklist.md` rewrite.** Reorganized as **Phase A (pre-squash) → B (squash) → C (post-squash verification) → D (crates.io) → E (manual cleanup)**, with an explicit "What you NEVER do manually anymore" list strikethrough-marking the eight operations release.yml now owns. Operator focus is the CHANGELOG slice, `plugin.json` version match, and quality gates.
- **`references/ci-patterns.md` reframed.** Added scope header clarifying it's a template library for Rust workspace projects (not the marketplace's own CI). Removed the stale "Known Issues in Current Axiom Workflows" section. Added cross-references into `rust/cargo.md` for command flags, feature gates, and publishing.
- **`references/crate-template.md` reframed.** Marked as axiom-family project policy; added cross-references to `rust/cargo.md` §2 / §4 for generic `Cargo.toml` schema and feature-gate semantics. Template content unchanged.
- **`plugin.json` and marketplace entry** bumped to 5.1.0 with refreshed descriptions naming the release-pipeline behavior and the `rust/cargo.md` cross-reference.

### `webassembly` skill — sweep (5.0.4 → 5.1.0)

- **`SKILL.md`** — Frontmatter rewritten to match the v5.1.0 baseline (multi-line description with concrete triggers, `slug`, `version`, `metadata.openclaw`). Cross-skill pointers fully rewired: stale references to the deleted `rust/wasm.md` and `rust/wasmtime-host.md` replaced with the standalone `wasmtime` sibling skill (host embedding) and the `rust` skill (language/build surface). Added a "Toolchain Pointers" table mapping each tool (`wasm-tools` / `wac` / `wit-bindgen` / `wasmtime` / `cargo-component` / `wasm-bindgen`) to its depth location. Common-gotchas section now distinguishes `wasm32-wasi` (legacy alias for `wasm32-wasip1`) from `wasm32-wasip2` (Tier 2) and `wasm32-wasip3` (Tier 3).
- **`wit.md`** — Major additions reflecting current spec state at component-model.bytecodealliance.org: feature gates (`@since` / `@unstable` / `@deprecated`) as a stability table; resource handle modes (`own<T>` / `borrow<T>`) with semantics table; async types (`future<T>` / `stream<T>`) and the `async` function modifier; the `include` directive with `with`-rename for plain-name conflict resolution; `use` renaming via `as`. Added a canonical keyword inventory (43 keywords) noting which are gated. Code-generation cross-ref updated from "rust skill" to the `wasmtime` sibling + crate docs.
- **`wasi.md`** — Rewrote the preview2 section as "WASI 0.2 (current stable)" with the seven core APIs listed alongside their Phase 3 status; added `wasi:http/*` (the proxy world), `wasi:sockets/udp`, and `wasi:sockets/ip-name-lookup` which were missing. New "WASI preview3 / 0.3 (in development)" section covering the upcoming async surface and the `wasm32-wasip3` Tier 3 target. Rebuilt the target section as a tier table (`wasm32-unknown-unknown` / `wasm32-wasip1` / `wasm32-wasip2` / `wasm32-wasip3`) noting the rename of `wasm32-wasi` → `wasm32-wasip1`.
- **`wasm-components.md`** — Resources section gained an `own<T>` vs `borrow<T>` wire/lifetime table. Host-side instantiation pattern reframed as language-agnostic (numbered shape) with the Rust sketch as illustration; cross-ref redirected to the `wasmtime` sibling skill. `cargo-component` note clarifies it is mutually exclusive with `wasm-bindgen` (component vs raw module). All "rust-wasm skill" stale references removed.
- **`wasm.md`** — Runtime landscape gained a `jco` entry (component-to-JS transpiler) and a wasmtime cross-ref to the sibling skill.
- **`plugin.json`** — Bumped to 5.1.0; richer description naming the gates, async types, handle modes, target ladder, and 0.3 trajectory; expanded keyword set (`wasi-preview2`, `wasm32-wasip2`, `wasm-tools`, `canonical-abi`).
- **Marketplace entry** bumped to 5.1.0 with the refreshed description.

### `typing` skill — buildout (5.0.4 → 5.1.0)

- **`SKILL.md`** — Built out from a 4-line stub (162 bytes) into a full language-agnostic typespace primer (~680 lines). Frontmatter rewritten to v5.1.0 baseline (multi-line description with concrete triggers, `slug`, `version`, `metadata.openclaw`). Eleven numbered sections: Curry-Howard correspondence; the four polymorphisms (parametric/ad-hoc/subtype/row) with worked examples in Haskell/TypeScript/Rust/OCaml/Scala/PureScript; kinds + HKTs; variance (with the language matrix: Haskell/Scala/Kotlin/C#/Java/TypeScript/Rust/OCaml, plus TypeScript 4.7+ `in`/`out`/`in out` syntax verified against the TS handbook); type classes vs traits vs interfaces (dispatch + coherence + openness; orphan rule); GADTs (with Haskell + OCaml + TypeScript-emulator examples); dependent + refinement types overview; type-driven design discipline; existentials; decision frameworks per language tier; anti-patterns table; reference-file index + canonical external pointers. Explicit cross-skill pointer to `rust/typespace.md` for Rust-specific surface (no duplication).
- **New `dependent-types.md`** (~445 lines) — Pi/Sigma types, indexed families (with `Vect` + `Fin` + safe indexing, verified against the Idris 2 tutorial), propositional equality and `Refl`, universes + totality, language survey (Idris 2 / Agda / Lean 4 / Rocq / F\* / ATS), refinement types (Liquid Haskell, Dafny, F\*), TypeScript branded-type pattern, Rust newtype + const generics as poor-man's dependent flavors, pragmatic when-to-use rubric, canonical references.
- **New `type-level-programming.md`** (~635 lines) — GADTs in depth (Haskell + OCaml + the `DataKinds` indexed-vector encoding), type families (closed/open/associated, type-level Plus, functional-dependencies relationship), HKTs and kind polymorphism (Haskell `Functor`, Scala 3 `F[_]`, the defunctionalization encoding for HKT-less languages like TypeScript's URI2HKT pattern), phantom types and type-state, type-level naturals + singletons, row polymorphism (OCaml/PureScript/Elm/Haskell encodings, polymorphic variants), the TypeScript conditional/mapped/template-literal type machine (with `infer`, distributive conditionals, route-param parsing, mapped-with-`as` renaming, TS 4.7+ variance annotations verified against the handbook), finally-tagless + free-monad patterns, decision matrix, anti-patterns, canonical references.
- **`plugin.json`** — Bumped to 5.1.0; rewrote description naming the actual cross-language surface and companion-file split; expanded keyword set from 6 keys (rust/typescript/haskell/dependent-types-style) to 19 (type-systems, refinement-types, gadts, higher-kinded-types, type-level-programming, variance, row-polymorphism, idris, agda, lean, ocaml, scala, fstar, liquid-haskell).
- **Marketplace entry** bumped to 5.1.0 with the refreshed description.
- **Cross-skill pointers verified**: `rust/typespace.md` is the Rust-specific companion (variance via `PhantomData`, type-state, sealed traits, GATs, object safety) — typing/SKILL.md and dependent-types.md both point there for Rust syntax and explicitly avoid duplicating it.

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
| finance | 5.1.0 | Swept: trader-policy drawdown rules removed from QUANT.md; Heston pricing expanded with full characteristic function + calibration; American-options section added; SKILL.md description sharpened with concrete triggers and canonical references |
| polymarket | 5.1.0 | Swept: SKILL.md restructured as primer + index; new apis.md extracts Gamma/CLOB/Data/Relayer endpoint reference (Context7-grounded); pUSD collateral, 1s sports delay, $750 UMA bond, and per-market fee patterns corrected throughout |
| rust | 5.1.0 | Restructured: cargo.md + rustc.md split out; SKILL.md trimmed 1430→1050; orphan WASM files removed |
| trader | 5.1.0 | Swept: 9-gate contract tightened to precise booleans; axiom.md rebuilt against the live axiom-mcp source (added scan/watchlist/redeem_slug/status/market_midpoint/price/candles + full kill-switch surface; fixed axiom_buy `side` parameter); jailbreak.md expanded for new authorized tools |
| typing | 5.0.4 | Awaiting v5.1.0 sweep |
| wasmtime | 5.0.4 | Awaiting v5.1.0 sweep |
| webassembly | 5.0.4 | Awaiting v5.1.0 sweep |
| workflow | 5.1.0 | Restructured: SKILL.md reorganized into 8 sections with new §IV "Automated Release Pipeline" documenting release.yml; rebase-vs-squash decision tree added; manual release-dance content removed; crate scaffolding cross-refs rust/cargo.md instead of duplicating; release-checklist rewritten around the squash-merge trigger |
