# Module Organization & Visibility — Deep Dive

The SKILL.md §X gives the doctrine. This file is the worked-example layer: how to apply
the four-tier `crate | mod.rs | file | inline` pattern, when to promote between tiers,
when `pub(crate)` is right vs `pub`, and how to refactor existing code that drifted.

---

## I. The four-tier pattern in practice

### Tier 1 — `crate`

A workspace member with its own `Cargo.toml`. Belongs at the top of the dependency
graph for its concern.

```toml
# crates/foo/Cargo.toml
[package]
name = "axiom-foo"
version.workspace = true

[dependencies]
{workspace}-types = { workspace = true }
```

Promote a `mod.rs` to a crate when it satisfies the §XI extraction criteria.
Demote a crate back into a parent's `mod.rs` if it stops paying for itself.

### Tier 2 — `mod.rs`

Directory-as-module. Common shape:

```rust
// src/foo/mod.rs

pub mod a;       // file submodule: src/foo/a.rs
pub mod b;       // file submodule: src/foo/b.rs
pub mod types;   // directory submodule: src/foo/types/mod.rs

#[doc(inline)]
pub use a::*;
#[doc(inline)]
pub use b::B;

/// Glue trait that submodules implement.
pub trait FooThing {
    fn name(&self) -> &str;
}
```

Why `mod.rs` over a single `foo.rs`: the directory creates space for siblings (sub-files),
inline tests, fixtures, and per-submodule docs. A `foo.rs` that grows past ~400 LOC
should consider mod.rs promotion.

### Tier 3 — `file`

`src/foo/a.rs`. The leaf unit. Most code lives here. A file submodule is named exactly
like a function or method: pick the noun that describes its responsibility.

```rust
// src/foo/a.rs

use crate::types::DecisionRecord;
use crate::foo::FooThing;

pub struct A { /* ... */ }

impl A {
    pub fn new() -> Self { Self { /* ... */ } }
    pub(crate) fn internal_helper(&self) -> u32 { /* ... */ }
}

impl FooThing for A {
    fn name(&self) -> &str { "A" }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn internal_helper_works() {
        // Can see pub(crate) items because we're inside the same crate.
        let a = A::new();
        assert_eq!(a.internal_helper(), 0);
    }
}
```

A file submodule can sprout its own subtree:
```
src/foo/a.rs              ← `pub mod impls;` declared at top
src/foo/a/impls.rs        ← submodule of a
```
This is unusual but valid. Most cases prefer promoting `a.rs` to `a/mod.rs` if it
needs internal substructure.

### Tier 4 — `inline`

Inline modules within a single `.rs` file:

```rust
// src/foo/a.rs (using inline pattern)

pub mod types {
    //! Public types — re-exported at parent.
    pub struct Decision { /* ... */ }
    pub struct DecisionBuilder { /* ... */ }
    pub struct DecisionRow { /* ... */ }
}

pub mod traits {
    //! Public traits.
    pub trait Decide {
        fn decide(&self) -> bool;
    }
}

mod impls {
    //! PRIVATE — never exports anything. Just hosts impl blocks.
    use super::types::*;
    use super::traits::Decide;

    impl Decision {
        pub fn new() -> Self { /* ... */ }
    }

    impl Decide for Decision {
        fn decide(&self) -> bool { true }
    }

    impl DecisionBuilder {
        pub fn new() -> Self { /* ... */ }
        pub fn build(self) -> Decision { /* ... */ }
    }
}

mod utils {
    //! Private helpers used by impls/.
    pub(super) fn weight(n: u32) -> f64 { n as f64 / 100.0 }
}

#[cfg(test)]
mod tests {
    use super::types::*;

    #[test]
    fn decision_builds() {
        let d = DecisionBuilder::new().build();
        assert!(d.decide());
    }
}

// At the parent (foo/mod.rs):
//
// pub mod a;
// #[doc(inline)] pub use a::types::*;
// #[doc(inline)] pub use a::traits::*;
```

The discipline:
- `mod types {}` — `pub struct/enum` definitions only. No methods.
- `mod traits {}` — `pub trait` definitions only.
- `mod impls {}` — **PRIVATE.** Hosts every `impl Foo {}` and `impl Trait for Foo {}` block. Never exports.
- `mod utils {}` — private helpers `pub(super)`-scoped to the file.
- `#[cfg(test)] mod tests {}` — tests of `pub(crate)` items.

### Why `mod impls` is private — and the depth-cap connection

Implementations are an artifact of types, not a concept consumers reach for. Exposing
`crate::foo::a::impls::Decision::new()` creates a useless second path; consumers
already reach `Decision::new()` via the `types::Decision` re-export. Keeping `impls`
private:

1. **Flattens the public surface.** Only `types` and `traits` appear in rustdoc.
2. **Lets you split impl files freely.** Adding `impls2.rs` doesn't change anything publicly.
3. **Keeps the file readable.** A reader scanning the file sees `types` first (the WHAT) and `impls` second (the HOW).

### The full re-export pattern — the operational form of the depth-cap

The inline `mod` partition combined with `pub use` re-exports is **the operational
mechanism by which the depth-cap rule is honored**. Internally the file is organized
into named partitions; externally consumers see a single flat module surface:

```rust
// crates/foo/src/bar.rs

pub mod types  { /* pub struct Decision; pub struct DecisionBuilder; ... */ }
pub mod traits { /* pub trait Decide; ... */ }
mod      impls { /* MEGA-PRIVATE — never exports anything */ }
mod      utils { /* private helpers — sometimes promoted to pub when genuinely shared */ }

// Re-export the public partitions at the file root, flattening the surface.
#[doc(inline)] pub use self::{types::*, traits::*};
// (utils::* re-exported only if utils contains genuinely public helpers.)
```

Then at the parent (`crates/foo/src/lib.rs` or `crates/foo/src/mod.rs`):

```rust
pub mod bar;
#[doc(inline)] pub use bar::*;  // hoist `bar`'s public surface to crate root
```

Consumers reach `crate::foo::Decision` (depth 3) instead of
`crate::foo::bar::types::Decision` (depth 5). The inline partitions exist for
internal organization; the re-exports preserve a flat external surface.

The hard rules:
- **`mod impls` — ALWAYS PRIVATE.** Never `pub use impls::*`. Implementations are not a concept; they're an artifact.
- **`mod utils` — usually private.** Re-export only when its contents are genuinely public utilities (Role A free fns from `feedback_rust_design_spectrum.md`); leave private when its contents are `pub(super)` internal helpers.
- **`mod types` and `mod traits` — re-exported via `#[doc(inline)] pub use`** so consumers see a flat `crate::foo::Decision` rather than `crate::foo::bar::types::Decision`.
- **The whole pattern preserves the std-canonical `{crate}::{module}::{submodule}::{Item}` depth-cap** — internal organization can be deeper than the public surface, because re-exports collapse the depth at the boundary.

When a submodule organized this way grows large enough to warrant its own crate (per
§V triggers), the same internal structure transplants directly: `bar/src/lib.rs`
keeps the `mod types; mod traits; mod impls; mod utils;` partition, and the
re-exports happen at the new crate root. The depth cap survives the promotion
because the structure was already organized for flattening.

---

## II. Visibility ladder — when each modifier is right

| Visibility | Reach | Use when |
|---|---|---|
| `pub` | External + entire crate | The item IS the crate's public API. `pub fn serve()`, library types, public traits |
| `pub(crate)` | Anywhere within THIS crate | **Default for cross-module helpers.** Survives reorgs. Reachable from inline `#[cfg(test)]` |
| `pub(super)` | Parent module only | Genuinely sibling-scoped — only the immediate parent's other children consume it |
| `pub(in crate::foo)` | A specific module subtree | Fine-grained lockdown — internal item shared by `crate::foo::*` only |
| (private) | Defining module + descendants | The default. Most items live here. |

### The `pub(crate)` default rule

When in doubt, choose `pub(crate)`. It:
- Survives module reorganization (a sibling-rename doesn't break it).
- Stays out of the public API (rustdoc doesn't surface it).
- Reachable from inline `#[cfg(test)] mod tests` (which run inside the crate's privacy boundary).
- Migrating to `pub(super)` later is a 1-character delete; migrating from a brittle `pub(super)` chain is hours.

### The test visibility split

Two tiers of tests, distinguished by visibility:

| Test type | Location | Sees |
|---|---|---|
| **Inline tests** | `#[cfg(test)] mod tests {}` co-located with the code | `pub(crate)` and private items via `use super::*` |
| **Integration tests** | `crates/<name>/tests/*.rs` (separate compilation unit) | `pub` items only — the crate is treated as an external consumer |

The split is enforced by the visibility system itself; you cannot accidentally
violate it. The implication for design:

- Tests of internals (helpers, edge cases of `pub(crate)` fns) → INLINE.
- Tests of the public contract (the API users will call) → `tests/` directory.
- Doc tests under `///` go through the public API too — they live with the inline tier.

If you find yourself wanting to test a `pub(crate)` item from `tests/`, the answer
is either (a) move the test inline, or (b) the item should actually be `pub` and
that's a public-API design conversation.

### `pub(super)` — the brittle special case

```rust
// src/foo/a.rs
pub(super) fn helper() { /* ... */ }
```

The reach: only `src/foo/mod.rs` (`a`'s parent). If you later move `a.rs` to
`src/bar/a.rs`, the `pub(super)` reach becomes `src/bar/mod.rs` — but you probably
wanted "the crate", and now `crate::foo::other::caller` can't reach `helper` even
though it could before.

`pub(crate)` would have survived the move untouched. `pub(super)` is correct ONLY
when the item is truly a parent-only concern AND the parent-child relationship is
stable.

---

## III. Path discipline

```rust
// DO — absolute paths from the crate root
use crate::types::DecisionRecord;
use crate::supervisor::bots::quad_tick;
use crate::feeds::Channel;

// DO — single super:: for genuine siblings
// (in src/foo/a.rs, reaching src/foo/b.rs)
use super::b::Sibling;

// DO NOT
use super::super::types::DecisionRecord;        // ← brittle
use super::super::super::feeds::Channel;        // ← code smell
use super::super::supervisor::bots::quad_tick;  // ← refactor request
```

### The grep test

```sh
rg -n "super::super::"
```

Should approach 0. Every `super::super::` is a refactor candidate. Convert to
`crate::` form. The conversion is mechanical — IDE goto-definition tells you the
absolute path; copy-paste it into the import.

### Naming-depth as a smell

`Type::Path::Components::Item` with > 4 `::` separators:

```rust
use axiom::something::some::thing::why::are::we::still::nesting::Item;
//                                                                  ^^ smell
```

Three responses, in order of preference:

1. **Promote a sub-path to its own crate.** Per §XI's extraction criteria.
2. **Flatten via `pub use`** at an ancestor. `pub use crate::a::b::c::*` at `crate::a` gives `crate::a::Item`.
3. **Re-home the type.** It's living in the wrong crate / module if its natural import path is unreadable.

---

## IV. Refactoring drifted modules

### Detect drift

```sh
# Single-file modules > 600 LOC
find . -name '*.rs' -not -path './target/*' | xargs wc -l | awk '$1 > 600 { print }'

# super::super:: chains (visibility-path drift)
rg -n 'super::super::'

# pub(super) usage (consider pub(crate) conversion)
rg -n 'pub\(super\)'

# Deep import paths
rg -n '^use [a-z_:]+::[a-z_:]+::[a-z_:]+::[a-z_:]+::[a-z_:]+::'
```

### Repair

**> 600 LOC file:**
1. Identify cohesive groupings inside.
2. Extract the largest grouping to a new submodule.
3. Choose tier: usually inline `mod` first, file submodule if the grouping is independent.
4. Re-run wc; iterate.

**`super::super::` chains:**
1. For each occurrence, identify the absolute path via the file tree.
2. Replace with `crate::...` form.
3. Use IDE refactor where available; otherwise sed-style mechanical replace.

**`pub(super)` audit:**
1. For each `pub(super)`, check if any non-parent caller exists. If yes → bug; tighten.
2. If only parent uses it, ask: is the parent likely to be reorganized? If yes → `pub(crate)`.
3. Convert the safe ones; leave the truly-parent-only.

**Deep import paths:**
1. Trace what the deep path resolves to.
2. Add a `pub use` at the right ancestor to flatten.
3. Update the imports.
4. Run `cargo doc --no-deps`; verify the public surface is now flat.

---

## V. When to PROMOTE a tier

| From → To | Triggers |
|---|---|
| inline → file | Inline module > 200 LOC; cohesive sub-grouping; needs its own tests |
| file → mod.rs | File > 400 LOC; multiple coherent sub-systems; planning to add `types/` + `impls/` siblings |
| mod.rs → crate | API stable; ≥ 2 workspace consumers; compile cost dominates; independent versioning; service-boundary entry point (per §XI) |

Promotion is reversible. If you promote `mod.rs → crate` and later realize the crate
was premature, fold it back into the parent's `mod.rs`. The cost of the wrong
promotion is some churn; the cost of the missed promotion is endless flat files.

---

## VI. Worked example — refactoring a drifted file

Before (a `crates/foo/src/lib.rs` that drifted to 800 LOC):

```rust
// 800 lines of types, traits, impls, helpers, tests all mixed
pub struct A { /* 50 LOC */ }
pub struct B { /* 60 LOC */ }
pub struct C { /* 40 LOC */ }
pub trait Foo { fn foo(&self); }
impl Foo for A { /* 80 LOC */ }
impl Foo for B { /* 90 LOC */ }
impl Foo for C { /* 70 LOC */ }
fn helper1() { /* 30 LOC */ }
fn helper2() { /* 40 LOC */ }
#[cfg(test)] mod tests { /* 200 LOC */ }
```

Step 1 — apply inline pattern (still one file, but partitioned):

```rust
pub mod types {
    pub struct A { /* ... */ }
    pub struct B { /* ... */ }
    pub struct C { /* ... */ }
}

pub mod traits {
    pub trait Foo { fn foo(&self); }
}

mod impls {
    use super::types::*;
    use super::traits::Foo;
    impl Foo for A { /* ... */ }
    impl Foo for B { /* ... */ }
    impl Foo for C { /* ... */ }
}

mod utils {
    pub(super) fn helper1() { /* ... */ }
    pub(super) fn helper2() { /* ... */ }
}

#[cfg(test)]
mod tests { /* ... */ }

#[doc(inline)]
pub use types::*;
#[doc(inline)]
pub use traits::*;
```

Step 2 — if still > 600 LOC, promote inline → file:

```
crates/foo/src/
├── lib.rs            ← `pub mod types; pub mod traits;` + re-exports
├── types.rs          ← struct A, B, C
├── traits.rs         ← trait Foo
├── impls.rs          ← impl Foo for A/B/C
└── utils.rs          ← helper1, helper2
```

Step 3 — if `types.rs` itself drifts past 200 LOC with cohesive sub-groupings,
promote `types.rs` → `types/mod.rs` with submodules.

Each promotion is a small mechanical refactor. The compounding effect: a crate
that started as one 800-LOC file becomes a navigable subtree, each module
under 200 LOC, each public re-export `#[doc(inline)]` flat at the crate root.

---

## VII. Drop-in promotion — the simplest valid pattern

The simplest valid promotion is one shell command + one line of code.

### Tier 2 drop-in (file → mod.rs sub-tree)

```sh
cp -rf <source>/crates/core/src/time <target>/crates/core/src/
```

Then in `crates/core/src/lib.rs`:

```rust
pub mod time;
```

Done. The `time/` subtree is now part of the core crate. Every consumer of core sees
`<crate>_core::time::*` immediately. No new crate, no Cargo.toml gymnastics, no
feature-flag plumbing — because `time/` is internal to core and inherits all
its build context.

### Tier 1 promotion (mod.rs → independent crate)

When `time` deserves crate status (per §V triggers — independent versioning, ≥ 2
consumers, dominant compile cost):

```sh
cargo new --lib --name <workspace>-time crates/time
rm -rf crates/time/src
cp -rf <source-of-time-subtree> crates/time/src
mv crates/time/src/mod.rs crates/time/src/lib.rs
```

Then `crates/time/Cargo.toml` declares features and (if `time` is genuinely
foundational) keeps deps external-only — no `<workspace>-*` deps. Same shape
as a fully isolated client crate.

### The canonical Rust SDK cascade pattern

A common Rust workspace shape — visible in tokio (`tokio-*`), serde (`serde_*`),
axum (`axum-*`), and many others — is the **traits / types / utils → core → domain
→ umbrella** dependency cascade:

```
{workspace}-traits ──┐
{workspace}-types  ──┼──→ {workspace}-core ──→ {workspace}-domain-1 ──┐
{workspace}-utils  ──┘                     ──→ {workspace}-domain-2 ──┼──→ {workspace} (umbrella)
                                           ──→ ...                    ──┘
```

`{workspace}-core` acts as a "mini-SDK" that:
- Re-exports `traits`, `types`, `utils` (often gated by feature flags).
- Is the single dep every mid-tier (domain) crate takes — no domain crate depends on `traits` or `types` directly.
- Cascades feature flags upward — turning on `core/time` enables `time` everywhere downstream that imports from core.
- The umbrella crate then re-exports core + every domain crate (also feature-gated), giving consumers a single import surface.

The DAG flows in one direction (`a, b, c → core → d, e, f → umbrella`), preventing
cycles. Any crate above core can freely depend on core + any sibling-domain crate
without cycle risk, because none of them depend back on the others through core.

### The cascade-through-core pattern (concrete)

For a newly promoted `{workspace}-time` to reach the rest of the SDK without
forcing every consumer to add an explicit `{workspace}-time` dep, route it
through core:

```toml
# crates/core/Cargo.toml
[dependencies]
"{workspace}-time" = { workspace = true, optional = true }

[features]
default = ["std"]
time = ["dep:{workspace}-time"]
full = ["std", "time", /* other gated features */]
```

```rust
// crates/core/src/lib.rs
#[cfg(feature = "time")]
pub use {workspace}_time as time;
```

Now:
- The core crate owns the feature gate. Consumers activate `time` once via `core/time` — no per-consumer dep on `{workspace}-time`.
- The umbrella crate's `full` feature cascades automatically.
- A consumer that genuinely wants a direct dep on `{workspace}-time` can have it (the crate is independent), but the default path is through core.

This pattern prevents feature-flag matrices from exploding across consumers.
Every mid-tier crate above core takes core directly and cascades features
through it. Anything new follows the same pattern.

(Project-specific concrete crate names live in `code-style/rust.md` and
project-level memory — this skill stays language-agnostic.)

### Why this matters

The chronic failure mode: a developer wants to use functionality from a sibling
crate, can't reach it because the feature flag isn't activated, and instead of adding
the 1 line to Cargo.toml that would have enabled it — duplicates the code locally.
The cascade-through-core pattern eliminates the friction. If the feature exists at
the core layer, you reach for `axiom_core::<topic>` and it's either there (because
the feature is on) or you turn the feature on — never duplicate.

---

## VIII. Anti-patterns

| Anti-pattern | Why bad | Fix |
|---|---|---|
| Top-level file > 600 LOC | Reader can't navigate; merge conflicts cluster | Apply inline pattern; promote tiers |
| `pub(super) fn` used 5 hops away | Visibility is wrong; lying about reach | `pub(crate)` |
| `use super::super::super::Foo` | Path drift; refactor fragility | `use crate::...::Foo` |
| `mod impls; pub use impls::*;` | Defeats the whole point of mod impls | Make `mod impls` private; never re-export |
| `pub` on every internal helper | Pollutes public API; rustdoc shows clutter | `pub(crate)` |
| `pub mod types; pub mod traits; pub mod impls;` | impls leaked publicly | Make `mod impls` private (no `pub`) |
| New `*-api-types` crate for shared serializable types | Duplicates the workspace's `*-types` crate | Use the existing `*-types` crate; if it's missing serde/sqlx, add the feature, don't fork the home |
| New crate for each small concept | Bloats workspace; slows builds | Promote only when §XI extraction criteria met |

---

## See also

- `~/.claude/skills/rust/SKILL.md` §X-XI — doctrine summary
- `~/.claude/skills/rust/typespace.md` — the type-system layer (generics, trait objects, etc.)
- `~/.claude/projects/-Users-jo3-src-fl03-axiom/memory/feedback_pub_crate_over_pub_super.md`
- `~/.claude/projects/-Users-jo3-src-fl03-axiom/memory/feedback_module_pattern_doctrine.md`
- `~/.claude/projects/-Users-jo3-src-fl03-axiom/memory/feedback_axiom_types_canonical_home.md`
