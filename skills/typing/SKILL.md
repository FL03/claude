---
name: typing
slug: typing
version: 5.1.0
description: |
  Language-agnostic advanced type-system knowledge. Covers the conceptual
  foundation that crosses typed languages — parametric/ad-hoc/subtype
  polymorphism, variance, kinds, higher-kinded types, type classes vs traits
  vs interfaces, GADTs, type-level programming, dependent and refinement
  types, row polymorphism, and type-driven design discipline. Worked examples
  span Haskell, Idris/Agda, OCaml, Scala, TypeScript, and (sparingly) Rust.
  Companion reference files: `dependent-types.md` (Pi/Sigma types, length-
  indexed vectors, refinement types, proof-carrying code in Idris/Agda/F*/
  Liquid Haskell) and `type-level-programming.md` (GADTs, type families,
  HKTs, phantom types, kind polymorphism, type-level naturals, row types,
  TypeScript conditional/mapped/template-literal types). Attach this skill
  whenever the task is "how should I MODEL this in the type system" across
  languages, or when comparing type features between languages. The
  Rust-specific surface (impl Trait, GATs, object safety, PhantomData
  variance, type-state, sealed traits) lives in the `rust` skill's
  `typespace.md` — cross to it for Rust syntax; stay here for the cross-
  language theory.
metadata:
  openclaw:
    emoji: "λ"
    os: ["linux", "darwin", "win32"]
---

# Typing — Language-Agnostic Advanced Type Systems

You reason about types the way a type theorist reasons about them: as evidence
that a program has a property. The type system is not paperwork. It is a
mechanized proof assistant whose proofs happen to be source code.

This SKILL.md is the entry point. Open the companion files only when the task
enters their area:

- **`dependent-types.md`** — Pi/Sigma types, indexed families, refinement
  types, proof-carrying code. Languages: Idris, Agda, Coq/Rocq, Lean,
  Liquid Haskell, F*, Dafny.
- **`type-level-programming.md`** — GADTs, type families, HKTs, phantom
  types, kind polymorphism, type-level naturals, row polymorphism,
  TypeScript conditional/mapped/template-literal types.

For **Rust-specific** type system surface — `impl Trait` vs `dyn Trait`,
object safety, GATs, const generics, `PhantomData` variance, type-state,
sealed traits — load the `rust` skill and read `typespace.md` there. This
file deliberately stays cross-language and does not duplicate that material.

---

## 0. The Curry-Howard correspondence is not a metaphor

Types ARE propositions. Programs ARE proofs. Inhabitants of a type are
evidence that the proposition holds. This is the single most important
sentence in the skill — every other section follows from it.

| Logic              | Types                          |
|--------------------|--------------------------------|
| Proposition        | Type                           |
| Proof              | Term (program / value)         |
| `A ∧ B`            | Product `(A, B)`               |
| `A ∨ B`            | Sum `Either A B`               |
| `A → B`            | Function `A -> B`              |
| `⊥` (false)        | Empty type (`Void`, `Never`)   |
| `⊤` (true)         | Unit type (`()`, `Unit`)       |
| `∀x. P(x)`         | Parametric polymorphism `∀a. P a` |
| `∃x. P(x)`         | Existential type / dependent pair |
| `¬A`               | `A -> Void`                    |

Implications:

- **A function `forall a. a -> a` has exactly one inhabitant** — the identity.
  If your library exposes such a function, callers can prove (by Wadler's
  "Theorems for Free!") that it cannot inspect, transform, or fork `a`. This
  is *parametricity*: a free theorem from the signature alone.
- **A type with no inhabitants is logical false.** Functions returning `Void`
  / `Never` / `!` exist precisely to encode impossibility.
- **Pattern matching is case analysis on a proof.** When the compiler narrows
  `Term a` to `Term Int` inside a `Lit` branch (GADT-style), it is
  *eliminating* the existential the constructor introduced.

You don't need to drop into Coq to use this. The doctrine — *let the type say
what the program must prove* — applies in any typed language.

---

## I. The four polymorphisms

Every typed language picks some subset. Know which subset you have before
designing around it.

### 1. Parametric polymorphism — "works for all types uniformly"

The same code, instantiated at any type. The implementation cannot inspect
the type parameter.

```haskell
-- Haskell
length :: [a] -> Int   -- works for any 'a'; cannot look at the elements
```

```typescript
// TypeScript
function identity<T>(x: T): T { return x; }
```

```rust
// Rust
fn first<T>(xs: &[T]) -> Option<&T> { xs.first() }
```

```ocaml
(* OCaml *)
let pair x y = (x, y)   (* val pair : 'a -> 'b -> 'a * 'b *)
```

**Free theorems.** `forall a. [a] -> [a]` can only permute, drop, or duplicate
elements — it cannot create new ones. The signature constrains the
implementation. The Reynolds/Wadler parametricity theorem makes this
formal.

### 2. Ad-hoc polymorphism — "different code per type, same name"

Operator overloading, type classes, traits, interfaces, protocols. The
implementation is *selected* by the type.

```haskell
-- Haskell: type classes
class Eq a where
  (==) :: a -> a -> Bool

instance Eq Int where (==) = primEqInt
instance Eq a => Eq [a] where ...
```

```rust
// Rust: traits (ad-hoc polymorphism that LOOKS parametric)
pub trait Eq { fn eq(&self, other: &Self) -> bool; }
```

```scala
// Scala 3: given/using = type classes
trait Eq[A]:
  def eqv(x: A, y: A): Boolean

given Eq[Int] with
  def eqv(x: Int, y: Int) = x == y
```

```typescript
// TypeScript: structural subtyping + interface overloading (no true type classes)
interface Eq<T> { eq(a: T, b: T): boolean; }
```

**Dispatch axis.** Ad-hoc polymorphism is usually statically dispatched
(Haskell type classes, Rust traits monomorphize) but can be dynamically
dispatched (`dyn Trait` in Rust, `Box<dyn Eq>` patterns, interface tables in
Java/C#/Go). The dispatch choice is independent of the polymorphism kind.

### 3. Subtype polymorphism — "Liskov substitution"

If `S <: T`, anywhere a `T` is expected an `S` is accepted.

```typescript
// TypeScript: structural subtyping (a record with MORE fields is a subtype)
type Animal = { name: string };
type Dog = { name: string; breed: string };
const d: Dog = { name: "Rex", breed: "Lab" };
const a: Animal = d;   // OK: Dog <: Animal structurally
```

```scala
// Scala: nominal subtyping (declared inheritance)
trait Animal { def name: String }
class Dog(val name: String, val breed: String) extends Animal
```

**Structural vs nominal.**
- **Structural** (TypeScript, OCaml objects, Go interfaces): subtyping by
  shape. Two unrelated types with compatible fields are compatible.
- **Nominal** (Java, C#, Scala classes, Rust traits): subtyping by declared
  relationship. Same shape, different name → unrelated.

Haskell and Rust mostly avoid subtype polymorphism — they prefer parametric
+ ad-hoc. Rust's `dyn Trait` is closer to *bounded existential* than
classical subtyping.

### 4. Row polymorphism — "open record / variant"

Polymorphism over the *rest of the fields*, not just the type of one field.

```ocaml
(* OCaml: object types with row variables *)
let get_name x = x#name
(* val get_name : < name : 'a; .. > -> 'a *)
(* The ".." is the row variable: works for ANY object that has at least .name *)
```

```purescript
-- PureScript: row polymorphism on records
nameOf :: forall r. { name :: String | r } -> String
nameOf rec = rec.name
```

Row polymorphism lets you write "this function needs at least these fields,
plus whatever else you have." TypeScript approximates it with intersection
types and structural subtyping; PureScript and OCaml have it natively.
Haskell needs `GHC.Records` + extensions to get close.

See `type-level-programming.md` § "Row polymorphism" for depth.

---

## II. Kinds — the type of a type

A type-level type. Every type has a kind the way every value has a type.

| Kind             | Inhabitants                                  |
|------------------|----------------------------------------------|
| `Type` (`*`)     | `Int`, `String`, `Bool`, `User`, … fully-applied types |
| `Type -> Type`   | `Maybe`, `List`, `IO`, … one-parameter type constructors |
| `Type -> Type -> Type` | `Either`, `Map`, `Function`, …          |
| Higher kinds     | `(Type -> Type) -> Type` — functors of functors, monad transformers |

Why it matters: **higher-kinded polymorphism** is polymorphism over kinds
other than `Type`. Haskell and Scala 3 have it natively; Rust and Go do not
(yet); TypeScript has only partial encodings (HKT-emulator libraries via
defunctionalization).

```haskell
-- Haskell: Functor is polymorphic over kind Type -> Type
class Functor (f :: Type -> Type) where
  fmap :: (a -> b) -> f a -> f b

instance Functor Maybe  where fmap = ...
instance Functor [] where fmap = ...
instance Functor (Either e) where fmap = ...   -- partial application at the type level
```

```scala
// Scala 3: F[_] denotes a type constructor of kind Type -> Type
trait Functor[F[_]]:
  extension [A, B](fa: F[A]) def map(f: A => B): F[B]
```

**Without HKTs you cannot write a generic `Functor` / `Monad` / `Traversable`
abstraction.** You can write `fmap` for `Maybe` and `fmap` for `List`, but
not a function that takes "any functor" as a parameter. This is the single
biggest expressiveness gap between Haskell/Scala and mainstream typed
languages.

Kind polymorphism (`PolyKinds` in GHC; Scala 3's kind-polymorphic syntax)
goes one level higher — polymorphism over the kind itself. Rare but
sometimes essential (e.g., generic data-kind machinery for type-level lists).

---

## III. Variance — the rules of substitution

Given a type constructor `F<T>` and a subtype relation `T <: U`, variance
answers: how does `F<T>` relate to `F<U>`?

| Variance        | If `T <: U`         | Intuition                              | Example                       |
|-----------------|---------------------|----------------------------------------|-------------------------------|
| Covariant       | `F<T> <: F<U>`      | "produces T" — narrower is fine        | `Producer<T>`, `Iterator<T>`, `&T` |
| Contravariant   | `F<U> <: F<T>`      | "consumes T" — broader is fine         | `Consumer<T>`, `fn(T) -> ()`  |
| Invariant       | neither             | both produces and consumes             | `MutableCell<T>`, `&mut T`    |
| Bivariant       | both                | unsound; usually a bug                 | (TS arrays historically)      |

The rule of thumb: **a type variable in output position should be covariant;
in input position, contravariant; in both, invariant.** Function types
`A -> B` are contravariant in `A`, covariant in `B`.

### Language matrix

| Language        | How variance is expressed                                       |
|-----------------|-----------------------------------------------------------------|
| Haskell         | Inferred from use; `Functor`/`Contravariant`/`Invariant` classes name the dial |
| Scala           | Declaration-site: `class List[+A]`, `Function1[-A, +R]`         |
| Kotlin          | Declaration-site (`out`/`in`) and use-site                      |
| C# / Java       | Use-site wildcards: `List<? extends T>` (covariant view), `List<? super T>` (contravariant view) |
| TypeScript      | Inferred; explicit `in`/`out`/`in out` annotations since 4.7    |
| Rust            | Inferred from position; `PhantomData<…>` chooses when ambiguous |
| OCaml           | Inferred; explicit `+`/`-` on type parameters                   |

```typescript
// TypeScript 4.7+ variance annotations (verified against TS handbook)
interface Producer<out T>   { make(): T; }
interface Consumer<in T>    { consume(arg: T): void; }
interface Cell<in out T>    { make(): T; consume(arg: T): void; }
```

```scala
// Scala 3: declaration-site variance
class Producer[+A]:                 // covariant
  def make(): A = ???
class Consumer[-A]:                 // contravariant
  def consume(x: A): Unit = ???
class Cell[A](var value: A)         // invariant by default
```

**The deep reason:** variance falls out of which positions a type variable
occurs in. Output positions (right of `->`, return types, fields you can
read) are covariant; input positions (left of `->`, parameters, fields you
can write) are contravariant. Anything used in both is invariant. The
language-level annotations either let you *declare* the intent (Scala,
Kotlin, TypeScript) or are *inferred* from the body (Haskell, Rust, OCaml).

For Rust's `PhantomData` machinery — how to choose variance manually when
holding raw pointers — see `rust` skill's `typespace.md` § "Variance and
PhantomData".

---

## IV. Type classes vs traits vs interfaces — the dispatch grammar

All three are "ad-hoc polymorphism." They differ on three axes: dispatch,
coherence, and openness.

| Mechanism            | Dispatch  | Coherence            | Openness                    |
|----------------------|-----------|----------------------|-----------------------------|
| Haskell type class   | Static    | Global, one instance | Open (orphan instances warn) |
| Rust trait           | Static (`impl Trait`) or dynamic (`dyn Trait`) | Global, orphan rule enforced | Closed under orphan rule |
| Scala given/using    | Static    | Local (lexical scope), multiple allowed | Open per scope          |
| OCaml modules + functors | Static (modular implicits experimental) | Explicit module passing | Open                    |
| TypeScript interface | Structural (no dispatch — duck typing) | N/A                  | Open (anyone can satisfy) |
| Java/C# interface    | Dynamic (vtable)   | One implementation per class | Open                    |
| Go interface         | Dynamic (structural) | N/A                | Open (anyone with the methods satisfies) |

### Coherence — the critical invariant

**Coherence** = "there is at most one instance per (type, type class) pair,
and the language guarantees the same one is found at every use site."

- **Haskell + Rust enforce coherence.** This makes equality, ordering, and
  serialization deterministic — `(==)` for `Set Int` is *the* `Eq` instance.
  Cost: orphan rules and the occasional "newtype shuffle" to add the
  instance you want.
- **Scala 3 lets you scope `given` instances.** Two scopes can have
  different `Eq[Int]`. Powerful but you have to think about which is in
  scope.
- **OCaml asks you to pass modules explicitly** — coherence becomes the
  caller's problem.

### Orphan rule (Haskell, Rust)

You may write `instance Class Type` only if either `Class` or `Type` is
defined in the current module/crate. Otherwise two unrelated crates could
each define their own `Eq` for `String` and the compiler couldn't pick.

Workarounds: newtype + delegate. (`newtype Reversed = R String` then
`instance Ord Reversed`.) This is *the* trick for adding behavior to a
foreign type while preserving coherence.

---

## V. GADTs — generalized algebraic data types

Constructors that *refine the type parameter* when matched. The killer
feature for embedding type-safe DSLs.

```haskell
{-# LANGUAGE GADTs #-}
-- Verified against the GHC user's guide (extension stable since GHC 6.8.1,
-- included in GHC2024 default language).
data Term a where
  Lit    :: Int  -> Term Int
  Succ   :: Term Int -> Term Int
  IsZero :: Term Int -> Term Bool
  If     :: Term Bool -> Term a -> Term a -> Term a

eval :: Term a -> a
eval (Lit i)      = i              -- here 'a' is refined to Int
eval (Succ t)     = 1 + eval t
eval (IsZero t)   = eval t == 0    -- here 'a' is refined to Bool
eval (If c t e)   = if eval c then eval t else eval e
```

The expression "well-typed by construction" — `If (Lit 1) ... ...` is a
type error because `Lit 1 :: Term Int`, not `Term Bool`. The evaluator is
*total* and *exhaustive* without any runtime tagging.

GADT-equivalents elsewhere:

- **OCaml**: native GADTs since 4.00.
- **Scala 3**: GADTs with type-refining pattern matching.
- **Rust**: no direct support; emulate with a trait + associated types or
  with `PhantomData<State>` + type-state encoding (see `rust/typespace.md`).
- **TypeScript**: emulate with discriminated unions; the narrowing is the
  refinement.

```typescript
// TypeScript: discriminated union as poor-man's GADT
type Term =
  | { kind: "lit";    value: number }
  | { kind: "succ";   inner: Term }
  | { kind: "isZero"; inner: Term }
  | { kind: "if";     cond: Term; then: Term; else: Term };
// Lacks: the result-type-of-eval is not tied to the constructor.
// You can do it with conditional types on a kind-tag, but it gets verbose.
```

See `type-level-programming.md` § "GADTs in depth" for the indexed-type
embedding and the connection to dependent types.

---

## VI. Dependent types and refinement types — types that mention values

**Dependent types** let types reference values. `Vec n a` is "vectors of
length `n` over `a`" where `n` is a *value-level* natural number sitting in
a type. `Vec 3 Int` and `Vec 4 Int` are different types.

```idris
-- Idris 2: verified against the official tutorial
data Vect : Nat -> Type -> Type where
  Nil  : Vect Z a
  (::) : a -> Vect k a -> Vect (S k) a

(++) : Vect n a -> Vect m a -> Vect (n + m) a
(++) Nil       ys = ys
(++) (x :: xs) ys = x :: xs ++ ys
```

The result-length `n + m` is computed at the type level. If you swap two
recursive calls or drop a constructor, the type checker rejects the
program. There is no need for runtime bounds-checking inside dependent
algorithms because the bounds are *proved*.

**Refinement types** are dependent types' more practical cousin: you keep
the value-level program in a normal language and annotate it with logical
predicates that an SMT solver discharges.

```haskell
-- Liquid Haskell
{-@ type PosInt = {v:Int | v > 0} @-}
{-@ divide :: Int -> PosInt -> Int @-}
divide :: Int -> Int -> Int
divide x y = x `div` y
-- The call `divide 10 0` is rejected statically — `0 :| 0 > 0` is unprovable.
```

Languages on the spectrum:

| Language        | Style                            |
|-----------------|----------------------------------|
| Idris 2, Agda, Lean, Rocq (Coq) | Full dependent types — proofs *are* programs |
| F*              | Refinement + effects; verified compilation to OCaml/C |
| Liquid Haskell  | SMT-backed refinement on top of GHC |
| Dafny           | Refinement + verification on imperative core |
| TypeScript      | Branded types + type predicates approximate refinement |
| Rust            | No native support; encode invariants via newtypes + private constructors |

The full treatment — Pi types, Sigma types, indexed families, proof
irrelevance, totality, propositions-as-types — lives in
`dependent-types.md`.

---

## VII. Type-driven design — the discipline

The technique: **make illegal states unrepresentable**. Encode invariants
in the type so the compiler refuses to let you violate them.

### 1. Replace booleans with tagged types

```haskell
-- bad: boolean blindness
process :: Bool -> Bool -> User -> ...

-- good: meaning at the call site
data IsAuthenticated = Authenticated | Anonymous
data IsAdmin         = Admin         | Regular
process :: IsAuthenticated -> IsAdmin -> User -> ...
```

The function signature now documents itself. No `process(true, false, u)`
ambiguity. Equally idiomatic with TypeScript's literal types, Rust enums,
Scala sealed traits, OCaml variants.

### 2. Replace partial functions with total ones

```haskell
-- bad: head :: [a] -> a    -- partial; bombs on []
head :: [a] -> Maybe a       -- total
-- or, with a refined input type:
headNE :: NonEmpty a -> a    -- total
```

The choice between `Maybe`-return and refined-input is a recurring
decision: push the burden onto the caller (`NonEmpty`) when the caller is
well-positioned to ensure non-emptiness; return `Maybe` when they're not.

### 3. Type-state to lock out invalid transitions

A connection that is not yet authenticated cannot have `send` called on
it. A request that is not yet built cannot be sent. This pattern is
language-portable:

- **Haskell**: phantom types + smart constructors.
- **Rust**: zero-sized type tags + `PhantomData<State>` (see
  `rust/typespace.md` § "Type-state as design tool").
- **TypeScript**: branded types via intersection with phantom symbols.
- **Scala 3**: opaque types + match types.
- **F#**: units of measure; phantom type discipline.

The cross-language essence: the *type* of the handle changes when the
*state* changes; the API surface attached to each state is different.

### 4. Newtype the primitive obsession away

A user ID is not an `Int`. A USD amount is not a `Float`. A SQL string is
not a `String`. Wrap them. The compiler then refuses to add user IDs or
mix currencies.

```haskell
newtype UserId   = UserId   { unUserId   :: Int    }
newtype Cents    = Cents    { unCents    :: Int    }
newtype SqlFrag  = SqlFrag  { unSqlFrag  :: Text   }
```

The runtime representation is identical — newtypes are usually erased —
but the type checker treats them as distinct. The Rust analogue is
`struct UserId(u32)` with a private inner field; the OCaml analogue is
`type user_id = private int`; the TypeScript analogue is the branded-type
pattern.

### 5. Let the type drive the implementation

The Idris/Agda workflow — "write the type, then ask the compiler what
goes here" — generalizes. In any typed language, when you find yourself
guessing at an implementation, write the *type signature* of the missing
piece. The number of valid implementations usually collapses to one (or
to a small enumerable set).

---

## VIII. Existentials, GADTs, and "hidden" type variables

Universally quantified `forall a. a -> a` is "the caller picks `a`."
Existentially quantified `exists a. a` is "I have some `a` but you don't
know which."

```haskell
{-# LANGUAGE ExistentialQuantification #-}
data SomeShowable = forall a. Show a => MkSomeShowable a

-- A heterogeneous list — each element is "some Showable"
xs :: [SomeShowable]
xs = [MkSomeShowable (42 :: Int), MkSomeShowable "hello", MkSomeShowable True]

-- You can use the Show interface…
showAll :: [SomeShowable] -> [String]
showAll = map (\(MkSomeShowable x) -> show x)
-- …but you cannot recover the original 'a'.
```

This is the *type-theoretic* basis for "trait objects" / "interface
values":

- **Rust** `Box<dyn Show>` = existentially quantified `Show`.
- **Java** `List<? extends Comparable>` = existential with a bound.
- **Scala** `List[_ <: Comparable]` = existential with a bound.

Pattern: when you want heterogeneous storage with a shared interface,
reach for an existential. When you want compile-time-known monomorphic
storage, reach for a universal (generic).

---

## IX. Decision frameworks

### When in a typed language with an HKT system (Haskell, Scala, PureScript)

1. **Need to abstract over `Functor`/`Monad`/`Applicative`?** Use the
   type class / given. Lean on `mtl` / `cats` / `scalaz` for the standard
   stacks.
2. **Need to enforce a value-level invariant at compile time?** Use a
   GADT or smart constructor. Reach for Liquid Haskell / refinement if
   the invariant is arithmetic.
3. **Need to enforce a phase / lifecycle?** Phantom type + smart
   constructor.

### When in TypeScript / Rust / Kotlin / Swift (no native HKTs)

1. **Need polymorphism over a type constructor?** Encode with associated
   types (Rust trait `type Item`) or "defunctionalize" (TS `URI2HKT`
   pattern). The encoding cost is real.
2. **Need a GADT?** Emulate via discriminated union + conditional
   types (TS) or trait objects + an `as_any` downcast (Rust, sparingly).
3. **Need refinement?** Newtype + private constructor + factory that
   validates. The invariant is enforced by API, not by the type
   checker per se.

### When in an actually-dependent language (Idris/Agda/Lean/Rocq/F\*)

1. **Encode the precondition in the type signature.** `divide : Int ->
   (n : Int) -> { n /= 0 } -> Int`.
2. **Verify, don't test.** A passing type-check is a proof for the
   stated theorem.
3. **Beware totality.** Idris/Agda demand totality for the proof
   guarantee. `unsafe`-style escape hatches exist but undermine the
   guarantee.

### When in dynamically typed code with optional typing (Python+mypy, Ruby+RBS, Clojure+spec)

Most of this skill applies *in spirit* — the type system is real, just
incomplete. Use newtypes (`NewType("UserId", int)` in mypy), discriminated
unions (`Literal["a"] | Literal["b"]`), and `Protocol`s for structural
interfaces. Accept that the guarantee is partial.

---

## X. Anti-patterns — type-system smells

| Smell                                | Diagnosis                                | Fix |
|--------------------------------------|------------------------------------------|-----|
| `Object` / `any` / `interface{}` everywhere | Type system bypassed; back to dynamic typing | Generic constraints; discriminated unions |
| Booleans threaded through APIs       | Boolean blindness                        | Tagged types / enums |
| Nullable everywhere                  | "Billion-dollar mistake" leaking         | `Option`/`Maybe`; refinement types |
| String-typed enums                   | No exhaustivity check                    | Sum types / literal-union types |
| Cast / `unsafeCoerce` / `as` to silence the compiler | The model is wrong       | Find the missing case; refactor the type |
| `impl Foo for Box<dyn Bar>` patterns proliferating | Conflated coherence and storage | Newtype the dyn; or move to enum dispatch |
| Variance fights compiler             | Mutable container marked covariant       | Make it invariant; or split into reader + writer |
| HKT-emulator soup                    | Wrong language for the abstraction       | Either accept the verbosity or pick a different language |
| Smart-constructor escape hatches public | Invariant leaks                       | Keep the constructor private; expose only validated factories |

---

## XI. Reference files

Progressive disclosure — open these only when the task enters their area.

- **`dependent-types.md`** — Pi/Sigma types, indexed families, length-
  indexed vectors, propositional equality, totality and termination,
  refinement types (Liquid Haskell, F\*, Dafny), branded types as
  refinement approximation in TypeScript.
- **`type-level-programming.md`** — GADTs in depth, type families
  (open/closed, associated), HKTs and kind polymorphism, phantom types,
  type-level naturals and induction, row polymorphism, TypeScript
  conditional/mapped/template-literal type machinery, defunctionalization
  encodings for HKTs in languages that lack them.

### Related skills

- **`rust`** (sibling skill) — `typespace.md` covers Rust-specific
  surface: `impl Trait` vs `dyn Trait`, object safety, GATs, const
  generics, `PhantomData` variance choice, type-state pattern, sealed
  traits, HRTBs. Cross to it for any Rust-syntax question; stay here for
  the cross-language theory.
- **`webassembly`** (sibling skill) — WIT's type system is a constrained
  language-agnostic interface algebra (records, variants, results,
  options, lists, resources). The component-model type discipline is
  type-driven design applied to ABI design.
- **`finance`** (sibling skill) — heavy user of newtype/units-of-measure
  patterns (dollars vs cents vs basis points; spot vs forward; log-returns
  vs simple-returns). The type discipline matters most where unit
  confusion has dollar consequences.

### Canonical external references

- **TypeScript handbook** — https://www.typescriptlang.org/docs/handbook/
- **GHC user's guide** — https://downloads.haskell.org/ghc/latest/docs/users_guide/
- **Idris 2 docs** — https://idris2.readthedocs.io/
- **Agda docs** — https://agda.readthedocs.io/
- **Scala 3 reference** — https://docs.scala-lang.org/scala3/reference/
- **OCaml manual** — https://v2.ocaml.org/manual/
- **Lean 4 manual** — https://lean-lang.org/lean4/doc/
- **Liquid Haskell** — https://ucsd-progsys.github.io/liquidhaskell/
- **F\*** — https://www.fstar-lang.org/

Reach for the canonical reference whenever a specific syntax detail
matters — type-system features evolve fast (TS variance annotations
landed in 4.7; GHC GADT syntax is in GHC2024; Scala 3 reworked implicits
into givens). This skill captures the *concepts*; the manuals hold the
authoritative syntax.
