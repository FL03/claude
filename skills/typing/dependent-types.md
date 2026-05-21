---
type: reference
parent: typing
---

# Dependent Types and Refinement Types

This file is the reference for **types that mention values**. If `SKILL.md`
told you *that* dependent and refinement types exist, this file tells you
*how* they work, *which* languages give you which slice, and *when* the
investment pays.

The big picture, on one axis:

```
simply-typed lambda        types ⊥ values
       ↓
parametric polymorphism    types depend on TYPES (forall a. …)
       ↓
type operators (Fω)        types compute on TYPES   (HKTs, type families)
       ↓
DEPENDENT TYPES            types depend on VALUES   (Vec n a)
       ↓
refinement types           types carry predicates over values
       ↓
full theorem proving       types ARE propositions; programs ARE proofs
```

Everything below sits on the bottom three rungs.

---

## I. Pi types and Sigma types — the two pillars

Every dependent type system bottoms out in two binders:

- **Pi type** `(x : A) -> B(x)` — "for every `x : A`, a `B(x)`." Generalizes
  the function arrow `A -> B` (which is the special case where `B` does not
  mention `x`). The universal quantifier of Curry-Howard.
- **Sigma type** `(x : A) * B(x)` — "some `x : A` together with a `B(x)`."
  Generalizes the product `(A, B)`. The existential quantifier of
  Curry-Howard.

```idris
-- Idris 2

-- Pi: depending on a value-level Nat n, return a Vect n Int
zeros : (n : Nat) -> Vect n Int
zeros Z     = []
zeros (S k) = 0 :: zeros k

-- Sigma: package a length n with a vector of that length
SizedVec : Type -> Type
SizedVec a = (n : Nat ** Vect n a)

mkSized : Vect 3 Int -> SizedVec Int
mkSized xs = (3 ** xs)
```

In Agda/Lean/Rocq the syntax differs (`∀`, `Π`, `Σ`) but the semantics are
the same. **The whole rest of dependent-type machinery is special cases of
Pi and Sigma.**

---

## II. Indexed families — types as predicates

A *family* `F : I -> Type` is a function from values to types. `F i` is "the
type of things proved by index `i`." This is the workhorse of dependent
programming.

```idris
-- Verified against the Idris 2 tutorial.
data Vect : Nat -> Type -> Type where
  Nil  : Vect Z a
  (::) : a -> Vect k a -> Vect (S k) a
```

`Vect : Nat -> Type -> Type` says: indexed over a `Nat` and a `Type`. The
constructors *each declare* which index they inhabit:

- `Nil` inhabits `Vect Z a` — empty vector is precisely length zero.
- `::` takes a `Vect k a` and produces a `Vect (S k) a` — length increments.

The type checker uses this to refuse ill-formed combinations:

```idris
-- Compiles:
ex1 : Vect 3 Int
ex1 = 1 :: 2 :: 3 :: []

-- Type error: Vect 2 Int /= Vect 3 Int
-- ex2 : Vect 2 Int
-- ex2 = 1 :: 2 :: 3 :: []
```

Indexed family pattern is everywhere in dependent code:

```idris
-- "Finite numbers below n" — Fin n has exactly n inhabitants
data Fin : Nat -> Type where
  FZ : Fin (S k)
  FS : Fin k -> Fin (S k)

-- Safe indexing: by construction, the index cannot be out of bounds
index : Fin n -> Vect n a -> a
index FZ     (x :: _)  = x
index (FS i) (_ :: xs) = index i xs
-- No "index out of range" case is reachable. The compiler verifies exhaustivity.
```

This is *the* signature pattern: **eliminate the partial function by
refining the input type.** `head : Vect (S n) a -> a` (head of a *non-empty*
vector) cannot be called on `Nil` because `Nil : Vect Z a` and `Z /= S n`.

---

## III. Propositional equality — `a = b` is a type

Equality is not a primitive. It's a type with one constructor:

```idris
data (=) : a -> b -> Type where
  Refl : x = x
```

`Refl : x = x` is the *only* way to produce a value of `x = y`, and it only
works when `x` and `y` are *definitionally equal* (reduce to the same
normal form). Equality proofs are then values you pass around:

```idris
-- A proof that 2 + 2 = 4
twoPlusTwo : 2 + 2 = 4
twoPlusTwo = Refl
-- The type checker reduces 2 + 2 to 4 and accepts Refl.

-- Substitution: if x = y, then any P x can become P y.
sym : x = y -> y = x
sym Refl = Refl

trans : x = y -> y = z -> x = z
trans Refl Refl = Refl
```

**Why this matters:** dependent code routinely produces vectors whose
indices the type checker cannot reduce on its own (e.g., `n + 0` vs `n`).
You then *prove* the rewrite and `replace` it. This is the day-to-day
craft of dependent programming — and the reason it's labor-intensive.

```idris
-- The type checker does not automatically know n + 0 = n. We must prove it.
plusZeroRightNeutral : (n : Nat) -> n + 0 = n
plusZeroRightNeutral Z     = Refl
plusZeroRightNeutral (S k) = cong S (plusZeroRightNeutral k)
```

In Lean 4 / Rocq this is the bulk of "proof engineering." Idris 2 tries to
automate more via *elaborator reflection* and `auto`.

---

## IV. Universes, totality, and the propositions-as-types soundness story

Two technicalities that bite if you ignore them:

### Universes

If `Type : Type` (the type of types is itself a type), Girard's paradox
makes the logic inconsistent. So dependent systems stratify:

```
Type 0 : Type 1 : Type 2 : …
```

You usually let universe polymorphism (Agda: `Set ω`, Lean: `Sort u`)
handle this implicitly. The hazard is libraries that mix universe levels
and produce "universe inconsistency" errors that are hard to read.

### Totality

For proofs to be sound, every function must terminate on every input. Idris
and Agda check termination by structural recursion (each recursive call
must be on a structurally smaller argument). Non-total functions are
allowed (Idris: marked `partial`) but their use *invalidates the
type-as-proof reading*.

Example that breaks the proof reading:

```idris
-- Loops forever; "inhabits" every type.
partial
diverge : a
diverge = diverge

-- If you accept this as a value of (1 = 2), the logic is inconsistent.
```

In Rocq / Agda totality is mandatory by default. In Idris 2 you opt in
with `%default total`.

---

## V. The major dependently-typed languages

| Language    | Style                              | Sweet spot                                |
|-------------|------------------------------------|-------------------------------------------|
| **Agda**    | Pure dependent functional; Unicode-heavy | Pedagogy; formalized math; "type theory laboratory" |
| **Idris 2** | Practical dependent + linearity + effects | Real programs with embedded proofs   |
| **Lean 4**  | Dependent + powerful tactic language | Mathlib (largest formalized math lib); program verification |
| **Rocq** (Coq) | Tactic-driven; extracted to OCaml/Haskell | CompCert; Iris; serious verification         |
| **F\***     | Refinement + effects + SMT backend  | Verified low-level code (HACL\*, EverCrypt) |
| **ATS**     | Dependent + linear + theorem-prover surface | Systems programming with proofs              |

### Lean 4 — the practical workhorse

```lean
-- Lean 4
def append : {α : Type} → {n m : Nat} → Vector α n → Vector α m → Vector α (n + m)
  | _, _, ⟨xs, hxs⟩, ⟨ys, hys⟩ => ⟨xs ++ ys, by simp [List.length_append, hxs, hys]⟩
```

Lean 4 is becoming the de facto choice for new dependently-typed work
because of `mathlib`'s scale and the tactic ergonomics. Worth tracking
when picking a tool.

### F\* — pragmatic refinement + SMT

```fstar
val divide : int -> y:int{y <> 0} -> int
let divide x y = x / y
// Calls like (divide 10 0) fail at type-check time, discharged by SMT.
```

F\* compiles to OCaml, F#, or Low\* (a verified C subset). Used in
production for the verified cryptographic library `HACL*` shipping in
Mozilla NSS, Linux kernel, etc.

---

## VI. Refinement types — the practical 80%

A **refinement type** is a base type plus a logical predicate. SMT solvers
discharge the proof obligations. You keep your normal language and gain
verified preconditions / postconditions.

### Liquid Haskell

```haskell
-- {-@ refinement annotations @-} are Liquid-Haskell pragmas, ignored by GHC.
{-@ type Pos = {v:Int | v > 0} @-}
{-@ type Nat = {v:Int | v >= 0} @-}

{-@ divide :: Int -> Pos -> Int @-}
divide :: Int -> Int -> Int
divide x y = x `div` y

{-@ measure len :: [a] -> Nat @-}
{-@ head :: {xs:[a] | len xs > 0} -> a @-}
head :: [a] -> a
head (x:_) = x
-- head []  -- rejected by Liquid Haskell
```

The pragma syntax (`{-@ … @-}`) is a Liquid-Haskell DSL the tool parses
out of comments. GHC sees ordinary Haskell. SMT (typically Z3) discharges
the implications.

### Dafny

```dafny
method Divide(x: int, y: int) returns (q: int)
  requires y != 0
{
  q := x / y;
}
```

Dafny is imperative + refinement + Hoare-logic-style verification.
Microsoft Research's workhorse for verified-program teaching and the IronFleet
production systems work.

### TypeScript — branded types as refinement approximation

TypeScript has no SMT backend, but the **branded-type** pattern gives you
nominal refinement at the API boundary:

```typescript
// A phantom 'brand' makes Email and string distinct at the type level.
type Brand<T, B> = T & { readonly __brand: B };
type Email = Brand<string, "Email">;

// The only way to construct an Email is through validate(); the brand can't
// be forged outside the module that defines it.
function validate(raw: string): Email | null {
  return /^[^@]+@[^@]+\.[^@]+$/.test(raw) ? (raw as Email) : null;
}

function send(to: Email, body: string): void { /* ... */ }

// send("not-an-email", "hi") — type error at compile time
// const e = validate(userInput); if (e) send(e, "hi");  — OK
```

The invariant is enforced by *encapsulation* (only `validate` produces
`Email`s) rather than by the type checker per se. The cross-language pattern
is the same: private constructor + factory + downstream code typed against
the refined type.

### Refinement vs full dependent — pragmatic guidance

| Choose…             | When…                                                                |
|---------------------|----------------------------------------------------------------------|
| Refinement (Liquid, F\*, Dafny) | The invariants are arithmetic / first-order; you want SMT to do the work; you need the result to compile to a normal language |
| Full dependent (Idris, Agda, Lean, Rocq) | The invariants involve higher-order structure (e.g., theorems about polymorphic functions, formalized math); you accept hand-written proofs |
| Refinement-by-encapsulation (TS brand, Rust newtype) | You want *some* of the guarantee with zero verification cost; the trust boundary is the module |

---

## VII. Encoding dependent-type-flavored patterns in mainstream languages

You don't always get to pick the language. The dependent-style discipline
still helps.

### TypeScript: literal types + template literals + conditional types

TypeScript's type system, despite being unsound at runtime (any-cast, etc.),
is Turing-complete at compile time. You can encode surprising things:

```typescript
// "Number of bits in a binary string literal" — at the type level
type Length<S extends string> =
  S extends `${infer _}${infer Rest}` ? [unknown, ...Length<Rest>] : [];

// Length<"hello">["length"] is 5 at the type level.
```

Combined with template-literal types, you get a path toward route-typed
APIs:

```typescript
type Params<S extends string> =
  S extends `${infer _}:${infer P}/${infer Rest}` ? P | Params<Rest> :
  S extends `${infer _}:${infer P}`               ? P :
  never;

// Params<"/users/:id/posts/:postId">  =>  "id" | "postId"
```

This is `type-level-programming.md` territory more than dependent-type
territory, but it scratches the same itch.

### Rust: newtype + private constructor + smart factories

```rust
pub struct NonEmpty<T>(Vec<T>);                    // private inner

impl<T> NonEmpty<T> {
    pub fn new(first: T) -> Self { Self(vec![first]) }
    pub fn first(&self) -> &T { &self.0[0] }       // never panics by construction
}
```

The invariant "non-empty" is enforced by *visibility* — no public way to
construct an empty one. Rust's compiler does not verify the predicate;
the *module boundary* does. Pair with property tests if the invariant is
non-trivial. See `rust/typespace.md` § "Newtype as Type-Level Invariant"
for the Rust-specific discipline.

### Const generics as poor-man's value-dependent types

```rust
// Rust 1.51+: types parameterized by a const value.
pub struct Vec3<const N: usize>([f64; N]);

impl<const N: usize> Vec3<N> {
    pub fn dot(&self, other: &Vec3<N>) -> f64 { /* same N enforced */ ... }
}

// Vec3<3>.dot(&Vec3<4>{...})  // compile error: mismatched const param
```

You get value-level dependence *at compile time* for `usize`, `bool`, and
`char`. Full arithmetic over const generics (`Matrix<M, N> * Matrix<N, P>
= Matrix<M, P>`) is `generic_const_exprs`, unstable as of MSRV 1.94.

C++ has had this since templates. Zig generalizes it (comptime values are
first-class). It is the most commonly available dependent-type *flavor* in
mainstream systems languages.

---

## VIII. When to reach for dependent / refinement types

The investment is real. Apply the dial deliberately.

### Pays off

- **Cryptographic and protocol code.** F\* / HACL\* and Project Everest
  ship verified TLS, Curve25519, and AEAD primitives in production
  browsers and OS kernels.
- **Operating system kernels.** seL4 (Isabelle/HOL) and CertiKOS (Coq) are
  proven correct.
- **Compiler correctness.** CompCert (Coq) — a verified C compiler shipped
  in safety-critical systems.
- **Mathematical formalization.** Mathlib (Lean 4) is the largest
  formalized library of mathematics.
- **APIs with arithmetic invariants.** Indexed-vector libraries, dimension-
  checked matrix code, units-of-measure systems.

### Usually doesn't pay off

- **CRUD applications.** Newtype + tests cover the invariant burden at a
  fraction of the cost.
- **Code with non-deterministic dependencies** (network, filesystem,
  user input). The proof boundary stops at the IO.
- **Codebases where the team won't maintain proofs.** A dead proof is
  worse than no proof — it falsely advertises invariants.

### The intermediate sweet spot

Refinement-by-encapsulation (branded types, newtypes with private
constructors, smart factories) gives you 80% of the practical benefit at
near-zero cost. It is the right default in mainstream typed languages.
Reach for full dependent types only when:

1. The invariant is *load-bearing* (correctness, safety, money), AND
2. You can amortize the proof cost across many uses, AND
3. The team has the expertise and the time horizon.

---

## IX. Canonical external references

- **Idris 2 tutorial** — https://idris2.readthedocs.io/en/latest/tutorial/
  (the Vect/append example in this file is verified against it)
- **Agda docs** — https://agda.readthedocs.io/en/latest/
- **Lean 4 manual** — https://lean-lang.org/lean4/doc/
- **The Lean Mathlib** — https://leanprover-community.github.io/mathlib4_docs/
- **Liquid Haskell tutorial** — https://ucsd-progsys.github.io/liquidhaskell/
- **F\* tutorial** — https://www.fstar-lang.org/tutorial/
- **Dafny reference** — https://dafny.org/dafny/DafnyRef/DafnyRef
- **Software Foundations** (Pierce et al.) — https://softwarefoundations.cis.upenn.edu/
  — the canonical learning sequence for Rocq and dependent types
- **The HoTT book** — https://homotopytypetheory.org/book/ — for the
  univalent / cubical extensions of dependent type theory
