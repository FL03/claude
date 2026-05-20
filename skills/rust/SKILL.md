---
name: Rust
slug: rust
version: 4.1.0
description: |
  Make any agent, session, or cron fluent in idiomatic Rust. Covers ownership, borrowing,
  lifetimes, error handling, async (tokio), traits, generics, trait objects, cargo + feature
  gates, the no_std/alloc/std tier system, declarative and procedural macros (derive,
  attribute, function-like; syn/quote/proc-macro2 triad), the cargo ecosystem (clippy,
  rustfmt, cargo-expand, cargo-component, cargo-flamegraph, rustup toolchain management),
  WASM toolchain (component model + wasmtime host), and pointers to docs.rs / crates.io
  for ecosystem crate lookup. Attach this skill whenever producing or reviewing Rust.
  Not project-specific and not style-opinionated — personal preferences live in the
  `code-style` skill; project rules live in the project itself. Language-agnostic
  WebAssembly material (WIT syntax, component model semantics, WASI) lives in the
  `webassembly` skill; this one owns the Rust-side integration.
metadata:
  openclaw:
    emoji: "🦀"
    requires:
      bins: ["rustc", "cargo"]
    os: ["linux", "darwin", "win32"]
---

# Rust — Idiomatic Systems Programming

You write idiomatic, production-grade Rust. The compiler is your collaborator, not your enemy.
When the borrow checker rejects code, the **design** is wrong — restructure, don't fight.

This SKILL.md is the entry point. Depth lives in the reference files listed at the bottom.
Read this file end-to-end when attached; open a reference file only when the task enters that
sub-area.

---

## 0. The canonical reference is the std library itself — but custom is encouraged

The doctrines in this skill (core/alloc/std tier, method chaining, trait
justification, orphan rule, module organization, free-fn roles) are observed
from how `core`, `alloc`, and `std` are built — not invented. **But this is
not a "defer to std" rule, and it is absolutely not "rewrite functionality
std already provides."** It's two-tier:

### Tier 1 — std's SURFACE: use it; don't reinvent it

If std provides a function, type, or trait that solves your actual problem,
USE IT. Re-implementing is the dedup failure mode.

- `core::cmp::min(a, b)` — not `pub fn min<T>(a: T, b: T) -> T`.
- `Vec<T>` — not `MyVec<T>` unless newtype-for-orphan-rule.
- `core::iter::Iterator` — implement it on your type, don't define a parallel `MyIterator`.
- `core::future::Future`, `core::fmt::Display`, `core::error::Error` — same rule.

Grep before defining (the memory ledger has a "canonical types already exist" feedback rule for this). The grep includes std.

### Tier 2 — std's GRAMMAR: adopt it for custom designs

For problems std DOESN'T solve (your domain types — `Bot`, `Decision`, `Allocator`,
domain-specific aggregators, etc.), design **custom** abstractions in std's grammar:

- **Chainable methods** returning `Self` or a derived type (Iterator/Option/Result/builder shape).
- **Traits with associated types** for extension points (the `Iterator::Item` shape).
- **Sealed marker traits** for closed-set type-level claims (the `Send`/`Sync` shape).
- **Operator overloading via `core::ops::*`** for natural domain syntax.
- **Newtype wrapping** for orphan-rule + invariant encoding (`NonZeroU32`/`Reverse<T>` shape).
- **`mod utils`** for stateless reusable bits (`core::mem::swap` shape).
- **`pub(crate)` defaults** for cross-module helpers (audit std source — every crate uses this).
- **`mod.rs` directories** vs **single-file modules** matched to scale (`core/src/iter/` vs `core/src/option.rs`).

These are GRAMMATICAL patterns. They tell you HOW to shape custom things, not
WHAT to build. Custom design is encouraged — even necessary — for things std
doesn't cover. The discipline is keeping that custom design in std's idiom so
borrow checker, consumers, and future agents all read it without surprise.

### The decision flow

1. **Does std already provide this?** Grep `core::`/`alloc::`/`std::` docs + source. If yes → USE std.
2. **Does std provide an analogous pattern for a different domain?** Your need is iterator-like, future-like, error-like? → IMPLEMENT std's trait on your domain type. Don't redefine the trait.
3. **Does an existing workspace struct ALMOST do this?** (Most common case mid-task.) → ADD the missing method to its `impl` block in the same crate. 5-15 min detour, then return to the original task. Don't define a parallel type. Don't refactor surrounding code. See `feedback_extend_existing_structs_stay_on_task.md`.
4. **Does std provide neither AND no workspace analog exists?** → DESIGN custom in std's grammar (chainable, associated types, sealed markers, `pub(crate)` defaults, four-tier module layout).

Step 3 is the workflow-level discipline that prevents the dedup ledger from
accumulating: the 15-minute detour into an existing impl block beats the 200-LOC
parallel rewrite every time. Step 4 is the actual custom-design work for things
no existing type covers — and is encouraged for domain-specific abstractions.

### Files worth reading once for the grammar

`core/src/iter/traits/iterator.rs`, `core/src/option.rs`, `core/src/result.rs`,
`core/src/cmp.rs`, `core/src/marker.rs`, `core/src/ops/arith.rs`,
`core/src/convert/mod.rs`, `core/src/mem.rs`, `core/src/fmt/mod.rs`,
`std/src/process.rs` (the `Command` builder).

See `feedback_study_rust_std_as_canonical_reference.md` for the full pattern map.

---

## I. Ownership & Borrowing (The Foundation)

Everything in Rust has exactly one owner. This isn't a limitation — it's a design tool.

### Rules

1. Each value has one owner. When the owner goes out of scope, the value is dropped.
2. You can have EITHER one `&mut T` OR any number of `&T` — never both simultaneously.
3. References must always be valid (no dangling pointers, enforced at compile time).

### Common Patterns

```rust
// MOVE: ownership transfers — original is invalid after this
let s1 = String::from("hello");
let s2 = s1;  // s1 is MOVED into s2. s1 is now invalid.

// BORROW: temporary read access — original stays valid
let s1 = String::from("hello");
let len = calculate_length(&s1);  // borrows s1, doesn't move it
println!("{s1} has length {len}"); // s1 still valid

// MUTABLE BORROW: temporary exclusive write access
let mut s = String::from("hello");
change(&mut s);  // exclusive mutable borrow

fn calculate_length(s: &str) -> usize { s.len() }
fn change(s: &mut String) { s.push_str(", world"); }
```

### Traps

- `for item in vec` **moves** the vec. Use `for item in &vec` or `.iter()` to borrow.
- `String` moved into function → pass `&str` for read-only access.
- Can't return `&T` pointing to local data — return owned `T` instead.
- Split borrows: `let (a, b) = slice.split_at_mut(n);` for simultaneous `&mut` to different parts.

Deep dive: `ownership-borrowing.md`.

---

## II. Lifetimes

Lifetimes tell the compiler how long references are valid. Usually inferred; annotate when ambiguous.

```rust
// Explicit: output lifetime tied to input
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}

// Struct holding a reference needs a lifetime parameter
struct Excerpt<'a> {
    part: &'a str,
}

// 'static means the reference CAN live for the entire program
// String is 'static-capable (it owns its data)
// &'static str = string literal or leaked memory
```

### When to Use `'static`

- String literals: `"hello"` is `&'static str`
- Thread spawns: `std::thread::spawn` requires `'static` (no borrowed data)
- Trait objects: `Box<dyn Trait + 'static>` when you need ownership
- **Don't** slap `'static` everywhere to shut up the compiler — it means you're hiding a design issue.

---

## III. Error Handling

### Library Code — Custom Errors with `thiserror`

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum MyError {
    #[error("network request failed: {0}")]
    Network(#[from] reqwest::Error),

    #[error("invalid data: {msg}")]
    InvalidData { msg: String },

    #[error("not found: {0}")]
    NotFound(String),
}

// Use ? for propagation
fn fetch_data(url: &str) -> Result<Data, MyError> {
    let resp = reqwest::blocking::get(url)?;  // auto-converts via From
    let data = parse(resp).map_err(|e| MyError::InvalidData { msg: e.to_string() })?;
    Ok(data)
}
```

### Binary Code — `anyhow` for Convenience

```rust
use anyhow::{Context, Result};

fn main() -> Result<()> {
    let config = load_config()
        .context("failed to load config")?;
    run(config)?;
    Ok(())
}
```

### Rules

- **Never `.unwrap()` in library code or event loops.** Use `?`, `.unwrap_or_default()`, or explicit match.
- `.unwrap()` is acceptable in `main()`, startup, and tests.
- `.expect("reason")` > `.unwrap()` when the invariant matters.
- Chain `?` liberally — it's Rust's primary error propagation mechanism.
- Libraries return concrete `Error` types (`thiserror`-derived); binaries collapse to `anyhow::Result`. Don't mix at boundaries.

Deep dive: `errors-iteration.md`.

---

## IV. Traits & Generics

Traits define behavior. Generics make it reusable.

```rust
// Define behavior
pub trait Driver: Send + Sync {
    fn name(&self) -> &str;
    fn evaluate(&self, ctx: &EvalContext) -> Signal;
}

// Use generics with trait bounds
fn run_driver<D: Driver>(driver: &D, ctx: &EvalContext) -> Signal {
    driver.evaluate(ctx)
}

// Or impl Trait (simpler for single-use)
fn run_driver(driver: &impl Driver, ctx: &EvalContext) -> Signal {
    driver.evaluate(ctx)
}

// Complex bounds → where clause
fn process<T, E>(item: T) -> Result<(), E>
where
    T: Driver + Clone + 'static,
    E: std::error::Error + Send,
{
    // ...
}
```

### Derive Macros — Use Aggressively

```rust
#[derive(Debug, Clone, PartialEq, PartialOrd)]
pub struct Signal {
    pub direction: f64,
    pub confidence: f64,
    pub timestamp: i64,
}

// With serde (feature-gated)
#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
pub struct Candle {
    pub open: f64,
    pub high: f64,
    pub low: f64,
    pub close: f64,
    pub volume: f64,
    pub timestamp: i64,
}
```

Generics, trait objects, `impl Trait`, associated types, GATs, const generics, variance,
object safety, and type-state patterns are the *typespace* — how Rust lets you trade static
vs dynamic dispatch and encode invariants in types. That deserves its own file: `typespace.md`.

### The Rust design spectrum — method chaining first

Before "when not to use a trait," the deeper question: **what shape SHOULD the logic take?**
The function-first instinct (writing `pub fn foo(args) -> Result` for any new logic)
misses Rust's grain. Rust's "functional" character is the **chaining of methods** —
iterators, builders, futures, sinks — each link a small bit of logic, evaluated in
sequence, often lazily.

The design spectrum, in order of preference:

| Tier | Shape | When |
|---|---|---|
| 1 | **Method on a struct/enum, often returning another type for chaining** | The default. Iterators, builders, futures, fluent APIs. Bulk of code lives here. |
| 2 | **Struct + methods (no chain)** | State involved, no chain natural — accumulator, config, connection. `&self` / `&mut self` / `self`. |
| 3 | **Trait + impls** | Extension point — see decision tree below. |
| 4 | **Free fn — public utility API** | Small, stateless, called from many unrelated places. Lives in `utils.rs`. THESE are the API surface. |
| 5 | **Free fn — private helper** | Small, stateless, backs ONE struct's methods. Same file as the struct. Stays private. |

Free functions are tiers 4-5, NOT tier 1. The "I have a thing to do, I'll write a
function" instinct misses tiers 1-3 — which is where the bulk of Rust code belongs
because data almost always belongs to a type, and methods on that type chain to
produce results.

#### Function-first → method-chain (the most common mistake)

WRONG (free-floating functions threading state through args):
```rust
pub fn compute_kelly_fraction(bet: f64, capital: f64, edge: f64) -> f64 { /* ... */ }
pub fn clamp_kelly(f: f64, max: f64) -> f64 { f.min(max).max(0.0) }

let f = compute_kelly_fraction(bet, capital, edge);
let f = clamp_kelly(f, 0.5);
```

RIGHT (state in a struct, methods chain):
```rust
pub struct KellyClob { bet: f64, capital: f64 }

impl KellyClob {
    pub fn fraction(&self, edge: f64) -> f64 { /* ... */ }
    pub fn clamped(self, max: f64) -> Self { /* returns Self — chainable */ }
    pub fn validated(self) -> Result<Self, Error> { /* ... */ }
    pub fn into_size(self) -> f64 { /* terminal */ }
}

let size = KellyClob::new(bet, capital)
    .clamped(0.5)
    .validated()?
    .into_size();
```

Method chaining generalizes beyond iterators. HTTP requests, builders, futures,
fluent SQL — all the same pattern: methods return `Self` (or a derived type) so
the next method attaches. The caller reads top-to-bottom what's happening to the
value.

#### Iterator-style chaining IS Rust's "functional" idiom

```rust
let active: Vec<_> = bot_registry
    .iter()
    .filter(|b| b.power == Power::On)
    .filter(|b| matches!(b.mode, BotMode::Paper | BotMode::Live))
    .map(|b| b.summary())
    .take(10)
    .collect();
```

Lazy until `.collect()`. Each link composable, swappable, refactorable. THIS
is what "Rust is functional" means — not "use lots of free functions."

#### When free functions ARE right

Two roles, both legitimate:

**Role A — Public utility API (utils.rs / helpers.rs):**
```rust
// crates/core/src/time/utils.rs
pub fn now_micros() -> i64 { /* ... */ }
pub fn align_to_5min(t: i64) -> i64 { /* ... */ }
```
Stateless, reusable across dozens of call sites, no `Self` to attach to.

**Role B — Private helper backing struct methods (same file):**
```rust
impl Decision {
    pub fn validate(&self) -> Result<(), Error> {
        check_market_id(&self.market_id)?;
        check_kelly_f(self.kelly_f)?;
        Ok(())
    }
}
fn check_market_id(s: &str) -> Result<(), Error> { /* private */ }
fn check_kelly_f(f: Option<f64>) -> Result<(), Error> { /* private */ }
```
Private free fns break up a method's body without competing with the public API.

**Role C — Framework requirement (follow the framework's API surface):**
```rust
// wasm-bindgen demands free fns
#[wasm_bindgen]
pub fn greet(name: &str) -> String { format!("Hello, {name}") }

// axum demands free fn handlers with extractor args
async fn get_bots(
    State(state): State<AppState>,
    Query(params): Query<BotQuery>,
) -> Result<Json<Vec<BotSummary>>, StatusCode> { /* ... */ }
```
But other frameworks demand structure (tarpc → trait + impl on a struct; clap → struct
with derive macros). Lesson: don't fight the framework. The right shape is what its
macros / codegen expect.

**Bonus pattern — `pub fn run` in lib.rs for clean bin split:**
```rust
// crates/<name>/src/lib.rs — the app-specific SDK
pub fn run() -> anyhow::Result<()> { /* config, services, supervisor, bind */ }
```
```rust
// bin/<crate>/bin/<app>.rs — thin shim
fn main() -> anyhow::Result<()> { init_tracing()?; <crate>::run() }
```
`pub fn run` is unit-testable; `fn main` isn't. `lib.rs` compiles to multiple targets;
the bin doesn't have to. The lib becomes the SDK; the bin becomes the entry shim.

**Workspace bin layout convention** (project-specific): `bin/<crate>/src/` is the SDK
(`[lib] path = "src/lib.rs"`); `bin/<crate>/bin/<app>.rs` is the binary entry
(`[[bin]] path = "bin/<app>.rs"`). A workspace member can ship multiple binaries by
adding more `[[bin]]` entries — all sharing the same `src/` SDK.

#### The Forward<T> canonical pattern (when a trait IS earned)

```rust
pub trait Forward<T> {
    type Output;
    fn forward(self, input: T) -> Self::Output;
}

// Owning model — consumes self
impl<X> Forward<f64> for Model<X> where X: Layer { type Output = f64; ... }

// Reference impl — model stays alive across multiple .forward() calls
impl<X> Forward<f64> for &Model<X> where X: Layer { type Output = f64; ... }

// Generic over input/output — composable across the layer chain
impl<X, Y, Z> Forward<Y> for &Model<X>
where X: Layer<Input = Y, Output = Z> {
    type Output = Z;
    fn forward(self, input: Y) -> Z { /* ... */ }
}
```

Why both `Model<X>` AND `&Model<X>` impls: owning consumes; reference keeps the
model alive for repeated calls. The trait abstracts over both.

#### Lifetime composition in trait impls

When the impl needs to relate references, lifetimes appear in the impl block.
Clippy `needless_lifetimes` warns ONLY when they could be elided. When you need
them to express a relationship, use them:

```rust
impl<'a, X, Y, Z> core::ops::Add<State<&'a Y>> for State<&'a mut X>
where /* bounds connecting X, Y, Z */
{
    type Output = Z;
    fn add(self, rhs: State<&'a Y>) -> Z { /* ... */ }
}
```

Reading: `'a` ties the mutable borrow of `X` to the immutable borrow of `Y`; both
must outlive the operation. `State<&'a mut X> + State<&'a Y> → Z`. Operator
overloading via standard `core::ops::Add` — gets you `+` syntax for free.

Deep dive: see `feedback_rust_design_spectrum.md` for the full doctrine including
the decision flow and anti-patterns table.

### When NOT to use a trait

A trait must justify itself. Valid justifications (any one suffices):

1. **Associated types abstract over impl-specific shapes** (`Iterator::Item`).
2. **`Self`-abstraction enables generic code** (`Add<Rhs = Self>`, `From<T>`).
3. **Multiple types implement it as an extension point** (`Display`, `Debug`, `Drop`).
4. **Marker semantics** (`Send`, `Sync`, `Copy`, sealed marker traits).
5. **Trait-object dispatch is the consumer's API** (`Box<dyn Plugin>`).
6. **Sealed repr markers** — private type-system contracts (`ndarray::RawData`: Owned/Shared/View). Generic code parameterizes over the marker; sealed prevents downstream invention.
7. **HKT via Generic Associated Types (GATs)** — `type Item<'a> where Self: 'a` for borrow-from-self iteration. Stable since 1.65.
8. **Generic binary/n-ary operators** — `trait Binary<T> { type Output; fn op(self, rhs: T) -> Self::Output; }`, companion to `core::ops::Add` etc.
9. **Trait-extends-std pattern** — define the trait in a foundational crate (`crates/traits`), blanket-impl it on external types (`Vec`, `ndarray::ArrayBase`, …) cfg-gated; downstream consumers get the impls automatically.

If none of these hold, you are writing a method-bag, not a trait. Anti-pattern:

```rust
// BAD — concrete types in every signature; no Self-abstraction; no associated types;
// no extension point. Vec<f64> already has everything needed; the trait adds NOTHING.
pub trait Covariance {
    fn covariance(&self, other: &[f64]) -> f64;
    fn correlation(&self, other: &[f64]) -> f64;
}
```

Two correct shapes for the same logic:

```rust
// (a) Free function — generic over numeric type, reusable everywhere.
pub fn covariance<T: Float + Sum + Copy>(x: &[T], y: &[T]) -> T { /* ... */ }
pub fn correlation<T: Float + Sum + Copy>(x: &[T], y: &[T]) -> T { /* ... */ }

// (b) Struct + methods — when state is involved (incremental, batch).
pub struct CovarianceAccumulator<T: Float> { /* running state */ }
impl<T: Float> CovarianceAccumulator<T> {
    pub fn push(&mut self, x: T, y: T) { /* Welford update */ }
    pub fn covariance(&self) -> T { /* ... */ }
}
```

The decision tree, when tempted to declare a new trait:

| Question | Yes → trait | No → keep asking |
|---|---|---|
| Associated type that varies per impl? | trait | next |
| Self-abstraction non-trivially used? | trait | next |
| Multiple unrelated types will impl it? | trait | next |
| Marker (no behavior, just a type-level claim)? | trait | next |
| Trait-object dispatch is the API? | trait | **not a trait** |

If you fall through to "not a trait": stateless → free fn; stateful → struct + methods.

**Why this matters beyond style.** A method-bag trait that hardcodes concrete types
(`&[f64]`) is unreachable to consumers with different concrete types (`&[f32]`,
`&[Decimal]`). They will rewrite from scratch. Bad trait design is a leading CAUSE
of the duplicate-code failure mode. Generic free fns and struct methods don't have
this problem because consumers parameterize at the call site.

### The orphan rule (coherence) — where impls can live

`impl Trait for Type` is only allowed in crate `C` if **Trait is local to C** OR
**Type is local to C**. You CANNOT implement an external trait on an external type.

```rust
// In crates/traits — Binary IS local; ndarray::ArrayBase is external
pub trait Binary<T> { type Output; fn op(self, rhs: T) -> Self::Output; }

#[cfg(feature = "ndarray")]
impl<A, S, D, B, T> Binary<ndarray::ArrayBase<T, D>> for ndarray::ArrayBase<S, D>
where /* bounds */
{ /* ✅ ALLOWED — Binary is local */ }
```

```rust
// In a downstream crate — Binary is external; Tensor IS local
pub struct Tensor<A, D> { /* ... */ }
impl<A, B, D> Binary<Tensor<B, D>> for Tensor<A, D> { /* ✅ Tensor is local */ }
```

```rust
// Anywhere downstream — both external — FORBIDDEN
impl Binary<Vec<f64>> for Vec<f64> { /* ❌ orphan rule violation */ }
```

**Architectural consequence:** define a trait in the most foundational crate that
can reach the types you'd want to impl it on — typically a `crates/traits` (or
similarly named) no_std-capable crate at the root of the workspace. The crate that
defines the trait can blanket-impl it on `Vec`, `HashMap`, `ndarray::ArrayBase`, etc.
with cfg gates per dep — downstream sees those impls for free.

**This is why `core::ops::Add` lives in `core`** — so every downstream crate can
implement it on its own types and get `+` syntax. If `Add` were in some random
crate, only that crate could blanket-impl it on `i32`, `f64`, etc.

**Newtype workaround** — when you truly need `impl ExternalTrait for ExternalType`:

```rust
pub struct MyVec<T>(pub Vec<T>);

impl<T> core::fmt::Display for MyVec<T>
where T: core::fmt::Display
{
    fn fmt(&self, f: &mut core::fmt::Formatter) -> core::fmt::Result { /* ... */ }
}
```

Local newtype gives the orphan-rule its locality and your code its impl. Cost: a
wrapper at the API boundary; users do `MyVec(some_vec)` to opt in.

(Note the path discipline above: `core::fmt::*` inline rather than `use std::fmt::{Display, Formatter}`. The order `core → alloc → std` is the **flagability ladder** — reach for the lowest tier that has the item. `core::net::SocketAddr`, `core::time::Duration`, `core::ops::Add`, `core::fmt::Display` are all `core`-tier; using their `std::` aliases blocks `no_std` consumers for zero gain. The same struct definition compiles across `no_std`/`alloc`/`std` when its imports stay at the lowest sufficient tier — that's why foundational crates near the root of a workspace's dependency graph win by reaching for `core::` reflexively, since they need to compile for every downstream tier. Inline single-use paths rather than importing.)

**Anti-pattern:** defining a trait downstream and then wanting to impl it on a
type from an upstream sibling crate. The orphan rule blocks this; the only fix is
to MOVE the trait definition upstream. So when designing a trait, ask first: what
types do I want this implementable on? — and define it where those types are
reachable.

Deep dive: see `feedback_orphan_rule_coherence.md` for full mechanics including
`#[fundamental]` types and the formal coherence rule.

---

## V. Async Rust (tokio)

```rust
// Async function
async fn fetch_price(url: &str) -> Result<f64> {
    let resp = reqwest::get(url).await?;
    let data: PriceResponse = resp.json().await?;
    Ok(data.price)
}

// Spawning tasks
let handle = tokio::spawn(async move {
    fetch_price("https://api.example.com/price").await
});
let price = handle.await??; // double ? — JoinError then inner Result

// Select — race multiple futures
tokio::select! {
    price = fetch_price("source_a") => { /* use price */ }
    _ = tokio::time::sleep(Duration::from_secs(5)) => { /* timeout */ }
}

// Shared state across tasks
let state = Arc::new(RwLock::new(AppState::default()));
let state_clone = state.clone();
tokio::spawn(async move {
    let mut guard = state_clone.write().await;
    guard.update();
});
```

### Async Traps

- **Don't hold `MutexGuard` across `.await`** — use tokio's `Mutex` or restructure.
- **`Rc` is not `Send`** — use `Arc` for anything crossing task boundaries.
- **Blocking in async** — use `tokio::task::spawn_blocking()` for CPU-heavy work.
- **`.await` is a yield point** — state can change between awaits.
- **Sync I/O in async functions** — use `tokio::fs` instead of `std::fs`.

Deep dive: `concurrency-memory.md`.

---

## VI. Strings

```rust
// String = owned, heap-allocated, growable
// &str = borrowed slice, immutable reference to string data
// &'static str = string literal, lives forever

let owned: String = String::from("hello");
let borrowed: &str = &owned;          // borrow
let literal: &str = "hello";          // static lifetime

// Prefer &str in function params (accepts both)
fn greet(name: &str) { println!("Hello, {name}"); }
greet(&owned);   // works
greet(literal);  // works

// String concatenation
let s = format!("{} {}", first, last);  // best — no moves
let s = owned + " world";              // moves owned!
```

### UTF-8 Traps

- `s[0]` **doesn't compile** — use `.chars().nth(0)` or `.as_bytes()[0]`
- `.len()` returns **bytes**, not characters — use `.chars().count()` for char count
- Slicing `&s[0..4]` can panic if it splits a multi-byte char

Deep dive: `types-strings.md`.

---

## VII. Iterators

Iterators are lazy — nothing executes until consumed.

```rust
// Three ways to iterate
for item in &vec      { /* borrows: &T */ }
for item in &mut vec  { /* mutable borrow: &mut T */ }
for item in vec       { /* moves/consumes: T */ }

// Chaining (lazy until collect/for_each/count/etc.)
let result: Vec<f64> = prices
    .iter()
    .filter(|p| **p > 0.0)
    .map(|p| p * 1.1)
    .collect();

// Turbofish for type inference
let sum = values.iter().sum::<f64>();
let grouped: HashMap<_, Vec<_>> = items.into_iter()
    .map(|x| (x.key, x.value))
    .into_group_map();  // from itertools
```

---

## VIII. Cargo & Feature Gates

```toml
# Workspace-level dependency (define once)
[workspace.dependencies]
serde = { version = "1", default-features = false }
tokio = { version = "1", default-features = false }

# Crate-level (reference workspace)
[dependencies]
serde = { optional = true, workspace = true }
tokio = { optional = true, workspace = true }

# Feature gates
[features]
default = ["std"]
std = ["serde?/std"]
json = ["serde", "serde/derive", "serde_json"]
http = ["reqwest", "tokio/rt-multi-thread", "tokio/macros"]
full = ["default", "json", "http"]
```

### Feature Gates as Compile-Time DI

Feature flags are not just configuration — they are Rust's compile-time dependency-injection
mechanism. The rules that keep them sane:

- **Features are additive.** If you find yourself writing "feature A XOR feature B," refactor.
  Cargo unifies features across the dep graph; mutually-exclusive features break downstream.
- **Every new dependency gets its own named feature.** `hashbrown = ["dep:hashbrown"]` — never
  gate a dep behind an abstract feature like `alloc` or `std`.
- **Propagate with `?` syntax:** `"<workspace>-core?/json"` only forwards if the `<workspace>-core` dep is enabled.
- **`default-features = false` at workspace level;** enable what you need per-crate. This
  minimizes default compile surface.

### `no_std` / `alloc` / `std` — The Three Tiers

Library crates should support as many tiers as practical:

| Tier | `core` only | `alloc` | `std` |
|---|---|---|---|
| `no_std` (bare-metal, some embedded) | ✓ | ✗ | ✗ |
| `alloc` (heap, no OS services) | ✓ | ✓ | ✗ |
| `std` (hosted OS) | ✓ | ✓ | ✓ |

```rust
#![cfg_attr(not(feature = "std"), no_std)]
#[cfg(feature = "alloc")]
extern crate alloc;
```

Libraries meant to be reused aim for `no_std + alloc` by default; add `std` as the ergonomic
path. Binaries are always `std`. If the dep graph is hopelessly tied to `std`, don't pretend —
drop the `no_std` claim rather than leaving broken feature combinations.

### Common Commands

```bash
cargo fmt --all                                    # format everything
cargo clippy --workspace --features full           # lint everything
cargo build --workspace --features full            # build everything
cargo test --workspace --features full             # test everything
cargo build -p my-crate --features "json,http"     # build one crate with features
cargo doc --workspace --no-deps --open             # generate docs
```

### Cargo Ecosystem & Toolchain

The Rust toolchain ships with `rustup` (toolchain manager) and `cargo` (build system +
package manager). Beyond the core, these tools form the working ecosystem:

| Tool | What it does | Install |
|------|-------------|---------|
| **clippy** | Lint collection (~700 lints). `-D warnings` treats all as errors. Categories: `correctness`, `style`, `complexity`, `perf`, `nursery`. Configure via `#[allow(...)]` or `clippy.toml`. | Ships with rustup |
| **rustfmt** | Deterministic formatting. `cargo fmt --all` formats the workspace. Configure via `rustfmt.toml` (e.g., `edition`, `max_width`, `imports_granularity`). | Ships with rustup |
| **cargo-expand** | Expands all macros in a crate and prints the result. Essential for debugging derive macros and `macro_rules!`. Requires nightly: `cargo +nightly expand --lib -p my-crate`. | `cargo install cargo-expand` |
| **cargo-component** | Build tool for WASM components. Generates a component (not a raw module) from a Rust crate with WIT bindings. The bridge between `cargo build` and the component model. | `cargo install cargo-component` |
| **cargo-binstall** | Downloads pre-built binaries for cargo packages instead of compiling from source. `cargo binstall ripgrep` is 100x faster than `cargo install ripgrep` when a binary release exists. | `cargo install cargo-binstall` |
| **cargo-flamegraph** | CPU profiling via `perf`/`dtrace`. `cargo flamegraph --bin my-app` produces an interactive SVG flamegraph. Always use `--release`. | `cargo install flamegraph` |
| **cargo-nextest** | Faster test runner with per-test process isolation, retries, and JUnit output. Drop-in replacement: `cargo nextest run --workspace`. | `cargo binstall cargo-nextest` |
| **cargo-deny** | Audit dependency licenses, ban specific crates, detect duplicate deps, check advisories. CI-ready: `cargo deny check`. | `cargo install cargo-deny` |
| **cargo-udeps** | Find unused dependencies. Requires nightly: `cargo +nightly udeps --workspace`. | `cargo install cargo-udeps` |
| **wasm-tools** | Swiss-army knife for `.wasm` files: validate, print (disassemble), compose, extract WIT. Not cargo-specific but essential for WASM workflows. | `cargo install wasm-tools` |
| **rustup** | Manages toolchains (stable/nightly/specific versions), targets (`wasm32-wasip2`, `aarch64-unknown-linux-gnu`), and components. `rustup target add wasm32-wasip2` for cross-compilation. | System install |

**`rustup` target management:**
```bash
rustup target list --installed                     # what targets are available
rustup target add wasm32-wasip2                    # add WASM component target
rustup target add aarch64-unknown-linux-gnu        # add ARM Linux cross-compile
rustup component add rust-src                      # needed for some cross-compile scenarios
rustup run nightly cargo expand                    # run a command under nightly
```

**docs.rs feature inspection** — before adding a dependency, check its feature matrix:
`https://docs.rs/crate/{name}/latest/features`. This shows every feature flag, what deps
it pulls in, and which features are default. Faster than reading Cargo.toml on GitHub.

### Canonical pattern: trait + cfg-gated method + cfg-gated impls

The cleanest single-file demonstration of feature-flag-thinking is a sealed marker
trait with capability methods gated at the method level and impls gated at the
impl-block level, each block matching exactly one feature:

```rust
pub trait RawMetaData {
    private! {}  // sealed — downstream can't impl without seal! permission

    #[cfg(feature = "json")]
    fn into_json(self) -> serde_json::Value
    where Self: Sized + serde::Serialize {
        serde_json::to_value(self).expect("...")
    }
}

#[cfg(feature = "hashbrown")]
impl<K, V, S> RawMetaData for hashbrown::HashMap<K, V, S> { seal! {} }

#[cfg(feature = "alloc")]
impl<K, V> RawMetaData for alloc::collections::BTreeMap<K, V> { seal! {} }

#[cfg(feature = "std")]
impl<K, V> RawMetaData for std::collections::HashMap<K, V> { seal! {} }

#[cfg(feature = "json")]
impl RawMetaData for serde_json::Value {
    seal! {}
    fn into_json(self) -> serde_json::Value { self }  // specialization via cfg
}
```

The rules this enforces:
- Trait defined exactly once.
- Capability methods gated at method level — trait stays minimal when feature off.
- Impls of foreign types gated at impl-block level — each block names its required feature.
- Each `cfg(feature = "X")` matches one feature flag (not `any(...)`); features compose by union.
- Sealed traits use `private!{}` + `seal!{}` for self-documenting protection.
- Specialization-style overrides done via cfg-gated impl, not runtime branching.

Verify each feature combination compiles independently:
```bash
cargo check -p <crate> --no-default-features
cargo check -p <crate> --no-default-features --features alloc
cargo check -p <crate> --no-default-features --features "alloc,json"
cargo check -p <crate> --features full
```

When you want to add a new capability or impl, this is the template. A live reference
file matching this exact pattern in any workspace's `crates/traits/src/meta.rs`-style
foundational crate runs ~50 lines and covers all of the above.

---

## IX. Parallel Agent Build Workflows

When multiple agents run concurrently in the same workspace (or in git worktrees derived
from it), Cargo's file locking and CPU saturation are the primary failure modes. This
section covers the isolation and throttling patterns that keep agents from deadlocking or
overwhelming the machine.

### The core problem: `target/` contention

Cargo holds a file lock on `target/` during any build operation. Two agents pointing at
the same `target/` directory simultaneously produce one of three outcomes:

1. **Silent wait** — Cargo queues; looks like a hang.
2. **Error** — `could not acquire package cache lock`.
3. **Artifact corruption** — rare but possible with a partial write racing a read.

The fix is always: **give each agent its own `target/` directory.**

### Isolation via `CARGO_TARGET_DIR`

```bash
# Pattern 1: branch-scoped target (recommended for git worktrees)
export CARGO_TARGET_DIR="$(git rev-parse --show-toplevel)/target-$(git rev-parse --abbrev-ref HEAD | tr '/' '-')"
cargo check -p axiom-bots

# Pattern 2: /tmp ephemeral (transient agent tasks; no residue after reboot)
export CARGO_TARGET_DIR="/tmp/axiom-target-agent-$(date +%s)"
cargo check -p axiom-node --features serve,native

# Pattern 3: named lane path (for conductor-dispatched sprint lanes)
export CARGO_TARGET_DIR="/tmp/axiom-target-lane-A"
cargo check -p axiom-engine --features full
```

**Never set `CARGO_TARGET_DIR` globally in `~/.cargo/config.toml`** — it would redirect
the main session's builds too. Set it per-agent shell or per-invocation.

### Worktree isolation (git worktree + per-worktree target)

Git worktrees share the repository object store but give each branch its own working
tree. Combined with a per-worktree `CARGO_TARGET_DIR`, agents get full isolation:

```bash
# Create a worktree for a lane
git worktree add /tmp/wt-lane-a feature/lane-a

# In the worktree shell — set a unique target dir
cd /tmp/wt-lane-a
export CARGO_TARGET_DIR=/tmp/target-lane-a
cargo check -p axiom-bots --features full
```

The worktree shares `Cargo.lock` and the workspace `Cargo.toml` from the main checkout,
so dep versions stay consistent across lanes.

### Throttle cargo's internal parallelism

`cargo check` spawns N compilation threads where N = logical CPU count. On a 16-core
machine, 4 agents each running full-workspace checks spawn 64 threads — 4× capacity.
Pass `-j` to limit:

```bash
# Rule of thumb: floor(total_cores / num_simultaneous_agents)
# 8 cores, 4 agents → -j 2 per agent
cargo check -p axiom-node --features serve,native -j 2
```

Or via env (applies to all cargo invocations in the shell):

```bash
export CARGO_BUILD_JOBS=2
```

### Prefer crate-scoped checks over `--workspace`

`cargo check --workspace` compiles every crate. An agent touching only `crates/bots/`
doesn't need to check `bin/gui/` or `crates/math/`. Scope the check to affected crates:

```bash
# Agent modifying axiom-bots and axiom-engine only:
cargo check -p axiom-bots -p axiom-engine --features full

# Agent modifying bin/node:
cargo check -p axiom-node --features serve,native

# Wave-gates are the ONLY time the full workspace check runs:
cargo check --workspace --features full           # workspace gate
cargo check -p axiom-node --features serve,native # node gate
cargo check -p axiom-worker --features serve      # worker gate
```

### Wave-gate vs. in-lane checks

| Context | Command | Parallelism |
|---|---|---|
| **In-lane validation** (agent verifying its own changes) | `cargo check -p <crate> -j N` with per-agent `CARGO_TARGET_DIR` | Full parallel — all agents concurrent |
| **Wave-gate** (conductor validating all lanes) | Three canonical gates, one at a time, main `target/` | Serial — cargo-serial doctrine |
| **Pre-commit / pre-push hook** | `cargo check -p <changed_crate>` | Fast, scoped, single invocation |

The cargo-serial doctrine applies to **wave-gates only**. Coders run `cargo check`
freely inside their own lane.

### Shared compiler cache with `sccache`

When agents repeatedly compile the same external crates (tokio, serde, axum), `sccache`
acts as a shared object cache and turns redundant compilations into cache hits:

```bash
# Install once
cargo binstall sccache

# Enable per-agent (or set in .env / shell profile for all agents)
export RUSTC_WRAPPER=sccache

# Inspect hit rate
sccache --show-stats
```

`sccache` handles its own internal locking — safe across concurrent agents. The final
linking step still runs per-agent independently. High payoff on machines where agents
share hardware but compile overlapping dependency graphs.

### Machine-readable output for agent pipelines

When an agent needs to parse results programmatically (count errors, extract spans,
gate on zero-error exit):

```bash
# JSON lines on stderr — each diagnostic is a structured object
cargo check -p axiom-bots --message-format=json 2>&1 \
  | jq 'select(.reason == "compiler-message" and .message.level == "error")'

# Simplest gate: exit code only (0 = clean)
cargo check -p axiom-bots --features full -j 2 >/dev/null 2>&1 \
  && echo "PASS" || echo "FAIL"
```

### Canonical parallel-agent shell preamble

Paste this at the top of every agent shell invocation — sets isolation and throttling,
cleans up on exit:

```bash
set -euo pipefail
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')
export CARGO_TARGET_DIR="/tmp/axiom-target-${BRANCH}-$$"   # $$ = PID for uniqueness
export CARGO_BUILD_JOBS=2                                    # tune: floor(cores / agents)
trap "rm -rf ${CARGO_TARGET_DIR}" EXIT                       # cleanup ephemeral target
```

`trap ... EXIT` ensures no multi-GB artifact directories accumulate in `/tmp` after
agent sessions complete.

---

## X. Patterns & Idioms

### Newtype Pattern

```rust
#[derive(Debug, Clone, Copy, PartialEq, PartialOrd)]
pub struct Confidence(pub f64);

impl Confidence {
    pub fn new(value: f64) -> Self {
        Self(value.clamp(0.0, 1.0))
    }
}
```

### Builder Pattern

```rust
pub struct ConfigBuilder {
    timeout: Option<Duration>,
    retries: Option<u32>,
}

impl ConfigBuilder {
    pub fn new() -> Self { Self { timeout: None, retries: None } }
    pub fn timeout(mut self, t: Duration) -> Self { self.timeout = Some(t); self }
    pub fn retries(mut self, n: u32) -> Self { self.retries = Some(n); self }
    pub fn build(self) -> Config {
        Config {
            timeout: self.timeout.unwrap_or(Duration::from_secs(30)),
            retries: self.retries.unwrap_or(3),
        }
    }
}
```

### Type-State Pattern

```rust
pub struct Connection<S> { inner: TcpStream, _state: PhantomData<S> }

pub struct Disconnected;
pub struct Connected;

impl Connection<Disconnected> {
    pub fn connect(self) -> Result<Connection<Connected>> { /* ... */ }
}

impl Connection<Connected> {
    pub fn send(&self, data: &[u8]) -> Result<()> { /* ... */ }
}
// Can't call .send() on Disconnected — compile error
```

### Interior Mutability (when needed)

```rust
// Single-threaded: RefCell
use std::cell::RefCell;
let data = RefCell::new(vec![1, 2, 3]);
data.borrow_mut().push(4);  // panics if already borrowed!

// Multi-threaded: RwLock or Mutex
use std::sync::{Arc, RwLock};
let shared = Arc::new(RwLock::new(State::default()));
```

More on static-vs-dynamic, object safety, GATs, variance: `typespace.md`.

---

## XI. Module Organization & Visibility

Modules are how Rust scopes names AND code. Sloppy organization → endless nesting
(`crate::a::b::c::d::e::Item`) → unreadable code. Disciplined organization → flat,
extractable, testable subsystems. The doctrine connects WHAT to make a module from,
WHERE to put it, and HOW visible to make each item.

### The four-tier pattern: `crate | mod.rs | file | inline`

| Tier | Manifest | When |
|---|---|---|
| **crate** | `Cargo.toml` + `src/lib.rs` | A subsystem with stable public API, ≥ 2 consumers, independent compile/test/version cadence — see §XI |
| **mod.rs** | `src/foo/mod.rs` declares `pub mod a; pub mod b;` and provides a `pub use` facade | A directory of cohesive submodules; the natural extraction-candidate boundary |
| **file** | `src/foo/a.rs` is the body of `foo::a` | Single-file leaf — types, impls, helpers in one place |
| **inline** | `mod impls { … } mod types { … }` within ONE file | Compromise: partition a file's interfaces without exposing them; namespace is real, items are private unless `pub`-marked |

The progression is deliberate. Inline → file when the inline module exceeds ~200 LOC
or grows cohesive sub-groupings. File → `mod.rs` when sibling submodules form a
sub-system. `mod.rs` → crate per §XI's criteria. Promoting a tier is cheap; demoting
later (to fold back) is also cheap. The cost is in the unwritten promote that should
have happened — endless nested files paper over a missing crate boundary.

### The inline `mod impls / types / traits / utils` convention

```rust
// src/foo.rs

pub mod types {
    //! Public types — re-exported at parent via #[doc(inline)]
    pub struct Decision { /* ... */ }
    pub struct DecisionBuilder { /* ... */ }
}

pub mod traits {
    pub trait Decide { fn decide(&self) -> bool; }
}

mod impls {
    //! PRIVATE — never exports anything. Hosts impl blocks for crate::foo::types::*
    //! and crate::foo::traits::*. Connected to the lib only by the impls it provides.
    use super::types::Decision;
    impl Decision { pub fn new() -> Self { /* ... */ } }
    impl super::traits::Decide for Decision { fn decide(&self) -> bool { true } }
}

mod utils {
    //! Private helpers used by impls/.
    pub(super) fn helper(n: u32) -> u32 { n + 1 }
}

#[cfg(test)]
mod tests { /* inline tests for pub(crate) items */ }
```

At the parent (`lib.rs` or `mod.rs`):
```rust
pub mod foo;
#[doc(inline)] pub use foo::types::*;
#[doc(inline)] pub use foo::traits::*;
```

Why `mod impls` is private and never exports: implementations are an artifact of
the type/trait, not a public concept. Exposing `crate::foo::impls::*` adds a useless
re-export path that consumers would never reach for. Keeping it private flattens
the public surface AND lets you add/remove impl files without breaking downstream.

### Visibility ladder — `pub(crate)` is the default

| Visibility | Reach | When |
|---|---|---|
| `pub` | Anywhere via the crate's public API | Items that ARE the crate's contract — `pub fn serve()`, public types, public traits |
| `pub(crate)` | Anywhere within THIS crate | **The default for cross-module helpers.** Survives module reorganization. Reachable from inline `#[cfg(test)] mod tests` |
| `pub(super)` | Parent module only | Rare. Only for items genuinely sibling-scoped — used by exactly one parent's other children |
| `pub(in path)` | A specific named module subtree | Rarer still. Fine-grained lockdown for sensitive internals |
| (private) | The defining module + descendants | The default. Most items live here |

**The discipline:** prefer `pub(crate)` over `pub(super)`. `pub(super)` is brittle —
moving the file breaks every reference. `pub(crate)` survives reorgs because the
visibility scope is the whole crate, not a relative parent.

**Test visibility split:**
- `pub(crate)` items are visible to inline `#[cfg(test)] mod tests` co-located with the code.
- `pub(crate)` items are NOT visible from `crates/<name>/tests/*.rs` — those exist outside the crate's privacy boundary, treating the crate as an external consumer.
- Tests of internals → inline. Tests of the public API → dedicated `tests/` directory. The split is enforced by the visibility system itself.

### Path discipline — absolute over relative

```rust
// DO
use crate::types::DecisionRecord;
use crate::supervisor::bots::quad_tick;

// DO NOT
use super::super::super::types::DecisionRecord;
use super::super::supervisor::bots::quad_tick;
```

`super::` is for genuinely-local references (one level up to a sibling). The moment a
path needs more than ONE `super::`, switch to absolute `crate::`. The grep test:
`rg -n "super::super::"` should approach zero across the workspace.

### Naming-depth as a code smell — std's own pattern

`Type::Path::Components::Item` with > 4 `::` separators is a smell. This is
grounded in std itself: **almost every std item lives at depth 2 or 3** in the
canonical `{crate}::{module}::{submodule}::{Item}` shape:

- Depth 2: `core::fmt::Display`, `core::ops::Add`, `core::iter::Iterator`, `std::time::Duration`, `std::process::Command`
- Depth 3: `std::collections::hash_map::HashMap`, `std::sync::atomic::AtomicU32`, `std::sync::mpsc::channel`
- Depth 4 (rare, principled): `std::os::unix::fs::OpenOptionsExt` — platform-specific extension traits

Five-level paths essentially don't exist in std. If your workspace path is
deeper than std nests anywhere, the response is one of:

1. **Should `b` or `c` be its own crate?** Promote it (per §XI). Std does this — `alloc::vec::Vec` was promoted from `std` to `alloc` so it became reachable in no_std contexts.
2. **Should the parent flatten via `pub use`?** Std does this aggressively — `Vec` is re-exported from `alloc` and `std` even though its canonical home is `alloc::vec::Vec`. `pub use crate::a::b::c::*` at the `a` level gives consumers a flat surface.
3. **Should the type re-home?** It probably lives too deep relative to where it's used.

The rule is std-observed, not opinion: `{crate}::{module}::{submodule}::{Item}` is the canonical shape, and anything beyond it is a refactor signal.

### Reference

Deep dive with worked examples, refactoring patterns, and migration recipes:
`module-organization.md`.

---

## XII. When to Extract a Crate

A module wants to be its own crate when any of:

- Its public API is stable and consumed by ≥2 other workspace members.
- Its compile cost dominates the build and gating it behind a feature isn't sufficient.
- Its test suite is large enough to meaningfully slow the parent crate's iteration.
- It has an independent versioning story (serde, for example, ships on its own cadence).
- It has a clear `pub fn serve()` / `pub fn start()` entry point — a service boundary.

Extraction is reversible. If a split stops paying for itself, fold it back. The unit of
reasoning is "does this have a life of its own" — not "is it big enough yet."

---

## XIII. Unsafe

Rust lets you opt out of compile-time safety checks inside `unsafe` blocks. The contract:
the compiler stops proving safety; you prove it, in the surrounding comment, by hand.

```rust
// SAFETY: `ptr` is non-null because we just allocated it above;
// `len` is 8 bytes matching the layout; no other reference aliases `ptr`
// for the duration of this block (we hold the only &mut).
let value = unsafe { *ptr };
```

Rules for `unsafe`:

- **Every `unsafe` block must have a `// SAFETY:` comment** explaining the invariants you are
  upholding by hand. If you can't write the comment, the unsafe is unjustified.
- **Keep unsafe surfaces minimal.** Wrap unsafe behind a safe API at the crate boundary; callers
  should never need `unsafe`.
- **Prefer safe abstractions** (`std::slice::from_raw_parts_mut`, `Pin`, `NonNull`) over hand-
  rolled pointer arithmetic. They exist because safe idioms lose less often than you'd think.
- **`unsafe impl Send for X`** means you are asserting `X` is thread-transferable — a claim the
  compiler would otherwise reject. Document why it's sound (no interior `Rc`, no pthread state, …).
- **FFI requires `unsafe`.** Generated bindings (`bindgen`, `cxx`) wrap the unsafe surface with
  safer Rust wrappers. Consumers of your FFI crate should only need the safe surface.

Advanced material: `advanced-traps.md`.

---

## XIV. Macros

Two macro systems, both running at compile time. Neither bypasses the type system — they
generate code that the compiler then checks as normal Rust.

### Declarative (`macro_rules!`)

Pattern-match on syntax fragments. Fast to write, partially hygienic (local bindings don't
leak, but paths use the caller's namespace). Key fragment specifiers: `$x:expr`, `$x:ty`,
`$x:ident`, `$x:tt` (universal fallback), `$x:pat`, `$x:path`, `$x:vis`. Repetition:
`$(...)*` (zero+), `$(...)+` (one+), `$(...)? ` (optional). Use `$crate` for paths that
must resolve from the defining crate.

```rust
macro_rules! hash_map {
    ($($key:expr => $val:expr),* $(,)?) => {{
        let mut map = hashbrown::HashMap::new();
        $(map.insert($key, $val);)*
        map
    }};
}
```

### Procedural Macros

Rust code that transforms a `TokenStream` into a new `TokenStream`. Lives in a dedicated
crate (`proc-macro = true` in Cargo.toml). The **syn + quote + proc-macro2** triad is the
standard toolkit: `syn` parses token streams into structured AST nodes (`DeriveInput`,
`ItemFn`), `quote!{ ... }` turns Rust-like syntax back into tokens, and `proc-macro2`
enables unit-testing outside the proc-macro context.

**Three flavors:**

| Flavor | Signature | Power |
|--------|-----------|-------|
| `#[derive(X)]` | `fn(TokenStream) -> TokenStream` | **Appends** an impl block. Cannot modify the original item. |
| `#[attribute]` | `fn(attr: TokenStream, item: TokenStream) -> TokenStream` | **Replaces** the annotated item — can modify or wrap it. |
| `function_like!()` | `fn(TokenStream) -> TokenStream` | Full control — input can be any token stream, not necessarily valid Rust. |

**Error reporting:** `syn::Error::new_spanned(tokens, "message")` produces a compiler error
pointing at the exact span in the user's code. Always use this over `panic!()` in proc macros.

**Testing:** `cargo +nightly expand` to see expansions; `trybuild` crate for snapshot compile
tests; factor logic into `proc_macro2::TokenStream` functions for unit-testability.

### Rules of Thumb

- **Prefer a function over a macro** unless you need syntactic positions a function can't reach
  (new bindings, control flow, type-level manipulation, repetition).
- **`macro_rules!` for** variadic calls, table-driven test generation, compile-time assertions,
  DSL construction (routing tables, SQL templates).
- **Proc macros for** deriving trait implementations, code-generation from schemas, annotating
  functions with instrumentation/routing/validation.
- **Document macro-generated names.** A `#[derive(Builder)]` that introduces a `FooBuilder` type
  should say so in its doc comment — readers can't see the synthesis otherwise.
- **Don't hide control flow.** A macro that silently `return`s or `break`s is invisible at the
  call site — readers can't reason about the surrounding function.

Deep dive: `macros.md` — fragment specifier table, recursive macros, proc-macro crate
structure, `syn` field iteration patterns, helper attributes, re-export convention, the
full decision matrix.

---

## XV. Common Compiler Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `value moved here` | Used after move | Clone or borrow |
| `cannot borrow as mutable` | Already borrowed | Restructure or interior mutability |
| `missing lifetime specifier` | Ambiguous reference | Add `<'a>` annotations |
| `the trait bound is not satisfied` | Missing impl | Check trait bounds, add derives |
| `type annotations needed` | Can't infer type | Turbofish `::<T>` or explicit binding |
| `cannot move out of borrowed content` | Deref moves | Clone or pattern match with `ref` |
| `temporary value dropped while borrowed` | Ref to temp | Bind to variable first |
| `expected X, found Y` | Type mismatch | Check From/Into impls, add conversion |
| `the size for values of type ... cannot be known at compilation time` | `dyn Trait` without indirection | `Box`, `Arc`, or `&dyn` |
| `future cannot be sent between threads safely` | Held non-`Send` across await | Drop guard before await, or use `tokio::Mutex` |

---

## XVI. Testing

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic() {
        let result = add(2, 3);
        assert_eq!(result, 5);
    }

    #[test]
    #[should_panic(expected = "overflow")]
    fn test_panic() {
        add(u32::MAX, 1);
    }

    #[tokio::test]
    async fn test_async() {
        let price = fetch_price().await.unwrap();
        assert!(price > 0.0);
    }
}
```

Testing discipline:

- **Unit tests live next to the code** (`#[cfg(test)] mod tests`) and can see private items.
- **Integration tests live in `tests/`** at the crate root and exercise only the public API.
- **Compile-time assertions** (`static_assertions`) catch regressions at `cargo check` time —
  cheap, proactive.
- **Doc tests** for every non-trivial public function. Hidden setup uses `#` prefix.

---

## XVII. Performance Quick Hits

- **Release builds are 10–100× faster** than debug. Always `--release` for benchmarks.
- `Vec::with_capacity(n)` when you know the size — avoids reallocations.
- `&[T]` over `&Vec<T>` in function params — more general, same perf.
- `Box<dyn Trait>` for dynamic dispatch, `impl Trait` for static dispatch (monomorphized).
- `#[inline]` on small hot-path functions — but don't cargo-cult it, the compiler is usually right.
- `Arc::clone()` is cheap (atomic increment) — don't contort code to avoid it.
- Profile before optimizing. `cargo flamegraph` for CPU, `dhat` for allocations.

---

## Anti-Patterns to Avoid

| Anti-Pattern | Better Approach |
|---|---|
| Over-cloning to bypass the borrow checker | Use references `&T` or restructure ownership |
| `Arc<Mutex<T>>` everywhere | Single owner + `&mut`, or channels for message-passing |
| `.unwrap()` in library code | Return `Result<T, E>` and let the caller handle it |
| Sync I/O in `async fn` | Use `tokio::fs`, `tokio::net`, or `spawn_blocking` |
| `Box<dyn Error>` at library boundaries | `thiserror`-derived concrete error enum |
| `.clone()` as a fix for a borrow error | Ask whether the design wants different ownership |

---

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
- **`macros.md`** — declarative macro patterns (`macro_rules!` fragment specifiers, repetition,
  recursion, hygiene), procedural macros (derive/attribute/function-like, syn/quote/proc-macro2
  triad, field iteration, error reporting, testing with trybuild), proc-macro crate structure,
  re-export convention, decision matrix.

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

### WebAssembly (Rust side)

`webassembly/` (sibling skill) owns the language-agnostic layer — WIT syntax, component
model semantics, WASI capability model, binary format. Cross to it for any "what does this
WIT contract MEAN" / "what capabilities does this component need" question.

These two files cover the Rust-side integration only:

- **`wasm.md`** — entry point: target choice (`wasm32-wasip2` etc.), `cargo-component` vs
  `wasm-pack`, `wit-bindgen` vs `wasm-bindgen` distinction, single-file component crate
  layout, dual native+wasm32 build pattern, feature structure. Cross-references to
  `webassembly/` for the conceptual layer.
- **`wasmtime-host.md`** — host-side embedding recipe: `Engine`/`Store`/`Linker`/`Component`,
  `bindgen!` macro, WASI capability grants, `&self` ergonomics via `Mutex`. The canonical
  pattern for any Rust-hosted WASM runtime.

For everything else (target flags, cargo-component CLI, wit-bindgen macro syntax,
wasm-bindgen browser interop, allocator/CI patterns) — go to docs.rs for the crate or to
the `webassembly` skill for conceptual material. No per-tool cheatsheets.

### Related skills

- **`code-style`** (sibling skill) — personal preferences layer (e.g. MSRV floor, hashbrown
  over std HashMap, the user's preferred module convention, naming idioms). Load it whenever
  producing Rust the user will read — this skill stays project- and style-agnostic.
- **`webassembly`** (sibling skill) — WIT syntax, component model semantics, WASI capability
  model, binary format. Reference from any of the WASM files above when the question is
  language-agnostic.
