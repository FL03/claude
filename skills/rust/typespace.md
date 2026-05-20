# Typespace — Generics, Dynamic Dispatch, and Type-Level Design in Rust

This file is the reference for Rust's *typespace*: the dial between static and dynamic
dispatch, the way types encode invariants, and the mechanisms Rust gives you to move behavior
from run-time to compile-time (and back). If the SKILL.md told you *that* `impl Trait` and
`dyn Trait` are different, this file tells you *why* they're different and when each is correct.

---

## The Dispatch Axis

Every call to a trait method sits on an axis:

```
static ◄─────────────── impl Trait ─────────────── dyn Trait ─────► dynamic
monomorphized                                                       vtable
per call site                                                       one per trait
zero runtime cost                                                   one pointer indirection
bloats binary                                                       keeps binary small
```

- **Static dispatch (`<T: Trait>`, `impl Trait` in argument position)**: the compiler generates
  one version of the function per concrete `T`. Zero runtime overhead. Compile time and binary
  size go up. Inlining is possible.

- **Dynamic dispatch (`&dyn Trait`, `Box<dyn Trait>`, `Arc<dyn Trait>`)**: one version of the
  function, plus a vtable lookup per method call. Small binary, stable ABI, runtime cost of
  one pointer indirection. Required when the concrete type is unknown at compile time (plugin
  systems, heterogeneous collections, runtime-chosen strategies).

**The default is static.** Reach for `dyn` when you genuinely need one of:

- A heterogeneous `Vec<Box<dyn Trait>>`.
- A plugin system that loads implementations at runtime.
- An API that must have stable ABI (FFI).
- A case where monomorphization is prohibitively expensive (common with large closures in
  deeply nested generics).

---

## `impl Trait` — Two Different Things

`impl Trait` means different things in different syntactic positions. This trips people up
constantly.

### `impl Trait` in argument position (APIT)

```rust
fn feed(source: impl Iterator<Item = f64>) { ... }
```

This is syntactic sugar for a generic parameter. Equivalent to:

```rust
fn feed<I: Iterator<Item = f64>>(source: I) { ... }
```

The caller picks the concrete type. Each call site gets its own monomorphization.

### `impl Trait` in return position (RPIT)

```rust
fn numbers() -> impl Iterator<Item = i32> {
    (0..10).filter(|n| n % 2 == 0)
}
```

This is *opaque existential*: the function promises to return *some* type implementing
`Iterator<Item = i32>`. The caller doesn't know which type and can't name it. The function
picks the concrete type.

**Why RPIT matters:** you cannot write the return type of a complicated iterator chain by
hand. `Filter<Map<Take<Range<i32>>, ...>>` is the actual type of `(0..10).take(5).map(f).filter(g)`
— naming it is impractical. RPIT lets the compiler keep the name private.

**Rust 2024 edition** made RPIT capture everything in scope by default; before, you had to
annotate `impl Trait + 'a` explicitly. Be aware of this if reading older code.

### Gotchas

- **You can only return one concrete type per RPIT.** `if cond { iter_a() } else { iter_b() }`
  fails if `iter_a` and `iter_b` return different concrete iterators. Fix with `Box<dyn Iterator>`
  (dynamic) or an explicit enum (static).
- **RPIT in traits is recent.** Called RPITIT (return-position impl trait in trait). Stable
  since Rust 1.75. For older MSRVs you needed `async-trait` macros or explicit associated types.
- **APIT and named generics don't mix.** You can't write `fn f<T>(x: impl Trait<T>)` and refer
  to the APIT type parameter from the signature — use a named generic instead.

---

## Associated Types vs Generic Parameters

Both let a trait refer to "some type the implementer picks." The difference is **who gets to
choose** and **whether multiple choices coexist**.

### Generic parameter: caller chooses, multiple impls coexist

```rust
pub trait Container<T> {
    fn put(&mut self, item: T);
}

impl Container<i32> for MyBox { ... }
impl Container<String> for MyBox { ... }  // both coexist for MyBox
```

Use when a single implementer meaningfully supports multiple `T`s.

### Associated type: implementer chooses, exactly one per impl

```rust
pub trait Iterator {
    type Item;
    fn next(&mut self) -> Option<Self::Item>;
}

impl Iterator for VecIter {
    type Item = i32;
    // ...
}
```

Use when the `Item` type belongs *to the iterator* — it's an output of the implementer, not a
dial the caller turns.

### Rule of thumb

If the caller wants to vary it, generic parameter. If the type is a *consequence* of the
implementer, associated type. `Iterator::Item` is associated because "what kind of thing does
this iterator yield" is not something the caller gets to override — it's what makes this
iterator *this* iterator.

---

## Object Safety (What Can Be `dyn`)

A trait is **object-safe** (more precisely: dyn-compatible) iff all of its methods are
dyn-compatible. A method is dyn-compatible iff:

1. It does not have generic type parameters. `fn foo<T>(x: T)` on a trait makes the whole
   trait non-dyn-compatible.
2. It does not return `Self` by value (or have `Self` in parameter position, unless behind
   a pointer). `fn clone(&self) -> Self` disqualifies `Clone` from being `dyn`.
3. It does not use `Self` in a generic constraint (`where Self: Sized` marks a method
   *excluded* from the vtable, a useful escape hatch).

### The `where Self: Sized` escape hatch

```rust
pub trait MyTrait {
    fn method_that_can_be_dyn(&self);

    fn method_that_uses_self_by_value(self) -> Self
    where
        Self: Sized,  // exclude from vtable; callable only through generics
    {
        self
    }
}
```

This lets a trait be `dyn`-compatible *as a whole* while still having methods that wouldn't
qualify on their own — the disqualifying methods are simply not callable through `&dyn MyTrait`.

### Workarounds when a trait is not dyn-compatible

- **Split the trait.** Put the dyn-compatible parts in one trait (`Core`), the generic/self-
  returning parts in an extension trait (`Ext: Core`).
- **Wrap in an enum.** If the set of concrete implementers is small and known, an enum gives
  you static dispatch with heterogeneous storage.
- **`erased_serde`-style erasure.** A manual technique: write a helper trait whose methods
  take `&mut dyn io::Write` instead of a generic writer, implement it for any `T: Serialize`,
  then carry `&dyn HelperTrait`. Used by `serde_json` and others.

---

## GATs — Generic Associated Types

GATs let an associated type take its own generic parameters:

```rust
pub trait LendingIterator {
    type Item<'a> where Self: 'a;
    fn next(&mut self) -> Option<Self::Item<'_>>;
}
```

The use case: iterators that *lend* references to their own state (can't be done with plain
`Iterator` because `Iterator::Item` has no lifetime tied to `&mut self`).

Before GATs (stable 1.65, 2022), this pattern needed HKT hacks or was outright impossible.

GATs are still evolving. Practical guidance:

- **Use GATs when you need lending iteration, lifetime-generic collections, or async
  iterator-style traits.**
- **Lean on `async fn` in traits (stable 1.75)** instead of hand-rolled GATs for async code —
  the compiler is generating GAT-style code under the hood anyway.
- **Error messages with GATs can be noisy.** If the compiler complains about `where Self: 'a`,
  the fix is usually to add that bound on the associated type declaration.

---

## Const Generics

Const generics parameterize types over *values*, not just types:

```rust
pub struct Vec3<const N: usize>([f64; N]);

impl<const N: usize> Vec3<N> {
    pub fn zero() -> Self { Self([0.0; N]) }
    pub fn dim(&self) -> usize { N }
}

let v: Vec3<3> = Vec3::zero();
```

Two tiers:

### `min_const_generics` (stable since 1.51)

- Allows integer, `bool`, `char` parameters.
- Allows simple expressions over them (`[T; N]`, `[T; N + 1]` with limitations).
- Sufficient for most ergonomic type-level sizing.

### `generic_const_exprs` (nightly)

- Full arithmetic on const generic parameters (`[T; N * 2]`, `Matrix<M, N, P>` where the product
  depends on `M, N, P`).
- Required for serious type-level dimensional analysis.
- Unstable. Track progress on the tracking issue before building on it.

**At MSRV 1.94**, stable const generics are rich enough for:
- Fixed-size arrays as type parameters.
- Compile-time-sized embedded buffers.
- Matrix/vector libraries with dimension-checking.

Not yet stable: full const-generic expression evaluation, complex associated const types, and
const generic defaults in many positions.

---

## Variance and `PhantomData`

Variance answers the question: "if `T` is a subtype of `U`, when is `F<T>` a subtype of `F<U>`?"

Rust has three kinds:

| Variance | `T <: U` ⇒ | Example |
|---|---|---|
| **Covariant** (`+T`) | `F<T> <: F<U>` | `&'a T` is covariant in `T`; `Box<T>` is covariant in `T` |
| **Contravariant** (`-T`) | `F<U> <: F<T>` | `fn(T)` is contravariant in `T` (stricter input is fine) |
| **Invariant** | no subtyping | `&'a mut T` is invariant in `T`; `Cell<T>` is invariant |

You rarely write variance annotations directly in Rust — they're inferred from the *positions*
in which you use the type parameter. But when you use `PhantomData`, you *choose* the variance:

```rust
use std::marker::PhantomData;

struct CovariantInT<T>(PhantomData<T>);              // covariant
struct ContravariantInT<T>(PhantomData<fn(T)>);      // contravariant
struct InvariantInT<T>(PhantomData<fn(T) -> T>);     // invariant
struct AlsoInvariant<T>(PhantomData<*mut T>);        // invariant (shared ref? unsafecell-like)
```

**Why it matters:** variance is almost always inferred correctly. The exception is when you
hold a `*const T` or `*mut T` in a struct that *conceptually* owns a `T`, but the compiler
can't see that ownership. Then you add `PhantomData<T>` to get the right variance and drop-
check behavior.

`PhantomData` also tells the drop checker "I own a `T`" even though no `T` is physically stored —
critical for soundness in types like `Vec<T>` (internally holds `RawVec<T>` which has
`PhantomData<T>`).

---

## Type-State as Design Tool

Type-state encodes *what operations are valid right now* in the type itself. The canonical
example:

```rust
pub struct Request<State> {
    url: String,
    _state: PhantomData<State>,
}

pub struct Unbuilt;
pub struct Built;

impl Request<Unbuilt> {
    pub fn new(url: impl Into<String>) -> Self {
        Self { url: url.into(), _state: PhantomData }
    }

    pub fn build(self) -> Request<Built> {
        Request { url: self.url, _state: PhantomData }
    }
}

impl Request<Built> {
    pub fn send(&self) -> Response { /* ... */ }
}
```

Calling `.send()` on an `Unbuilt` request is a compile error, not a runtime error. The type
system is used as a proof-carrying notation: the caller *must* have built the request.

### When to reach for type-state

- **Multi-step protocols** where skipping a step is a bug (connection → authenticated →
  active → closed).
- **Builder-to-finished transitions** where some methods only make sense after validation.
- **Resource lifecycle** where the same object acts differently before and after acquisition.

### When not to

- **When the state is data, not a phase.** `User { logged_in: bool }` is clearer than
  `User<LoggedIn>` vs `User<LoggedOut>` if the rest of the code treats them uniformly.
- **When the state transitions are dynamic.** If the state changes based on user input or
  external events, keep it in a field and use `match`.

---

## Newtype as Type-Level Invariant

```rust
pub struct NonEmpty<T>(Vec<T>);

impl<T> NonEmpty<T> {
    pub fn new(first: T) -> Self { Self(vec![first]) }
    pub fn push(&mut self, item: T) { self.0.push(item); }
    pub fn first(&self) -> &T { &self.0[0] }  // never panics
}
```

The invariant "non-empty" is enforced at the type boundary. Consumers of `NonEmpty<T>` never
need to check for emptiness.

**Rules for newtype invariants:**

- **Private inner field.** `pub struct Foo(pub Inner)` leaks the escape hatch — anyone can
  construct a broken instance.
- **No `impl Deref<Target = Inner>`** unless you're sure all inner methods preserve the
  invariant. Most don't.
- **Implement only the surface you need.** Every method you expose is a method you're
  responsible for not breaking the invariant.

---

## Sealed Traits

Sometimes a trait is for *your* use in your crate, but you want external implementations
forbidden:

```rust
mod sealed {
    pub trait Sealed {}
}

pub trait MyTrait: sealed::Sealed {
    fn method(&self);
}

// Implementations — can do this internally because sealed::Sealed is pub(self)
impl sealed::Sealed for i32 {}
impl MyTrait for i32 { /* ... */ }
```

External crates can't `impl MyTrait for ...` because they can't construct `impl sealed::Sealed`.

Use sealed traits when:

- You want a closed set of implementations.
- You want future-compatibility: adding methods later without breaking downstream.
- The trait encodes a property only certain library-internal types satisfy.

---

## Higher-Ranked Trait Bounds (HRTB)

`for<'a>` binds a lifetime universally:

```rust
fn apply<F>(f: F)
where
    F: for<'a> Fn(&'a str) -> &'a str,
{
    // F must work for ALL possible lifetimes, not just one fixed one
}
```

Without `for<'a>`, the bound would fix a specific lifetime `'a` chosen by the caller, which is
often wrong — a closure used repeatedly with different input lifetimes needs to accept all of
them.

HRTBs show up naturally in closure-taking APIs. Most of the time the compiler infers them;
you only write them explicitly when passing a closure through multiple generic layers.

---

## Choosing the Right Tool — Decision Checklist

Given a design question "how should this type/function be parameterized?", walk the checklist:

1. **Does the caller choose the type, or does the implementer?**
   - Caller → generic parameter (`fn f<T>` or associated type in trait generic position).
   - Implementer → associated type.

2. **Is the set of types known at compile time?**
   - Yes, and small (< 5) → consider an enum instead of a trait.
   - Yes, but large or open → trait with static dispatch.
   - No (plugins, runtime config) → `dyn Trait`.

3. **Do I need heterogeneous storage?**
   - Yes → `Box<dyn Trait>` in a `Vec`.
   - No → generic, one type per collection.

4. **Am I returning a closure or complex iterator chain?**
   - Can I name the type? If no → RPIT (`impl Trait` return).
   - Do I need to store it? Then probably `Box<dyn Fn…>` or a named wrapper.

5. **Is the type parameter a *value* (like a size)?**
   - Yes → const generic (`<const N: usize>`).

6. **Am I hiding an invariant that the compiler should enforce?**
   - Static phase → type-state (`PhantomData<State>`).
   - Runtime constraint on a value → newtype with private inner.

7. **Do I want to close the trait to external impls?**
   - Yes → sealed trait pattern.

---

## Cross-references

- **SKILL.md** — Section IV "Traits & Generics" for the lightweight version of this material.
- **`advanced-traps.md`** — drop checking, `PhantomData` variance edge cases.
- **`concurrency-memory.md`** — how `Send`/`Sync` auto-traits interact with `PhantomData`.
- **`code-style/rust.md`** (if loaded) — the service-lifecycle pattern uses type-state implicitly.
