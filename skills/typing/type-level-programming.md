---
type: reference
parent: typing
---

# Type-Level Programming

This file is the reference for **computing with types**: GADTs, type
families, higher-kinded types, kinds, phantom types, type-level naturals,
row polymorphism, and the TypeScript conditional/mapped/template-literal
machine. If `SKILL.md` told you *that* HKTs and GADTs exist, this file
tells you *how* to wield them.

The unifying idea: types and values inhabit a single computational world.
A type-level program is a function whose inputs and outputs happen to live
one level up.

---

## I. GADTs in depth

A **generalized algebraic data type** is an ADT whose constructors are
allowed to *constrain* the type parameters they inhabit. Pattern matching
then *refines* those parameters in each branch.

```haskell
{-# LANGUAGE GADTs #-}
-- Pragma verified against the GHC user's guide.
-- Extension stable since GHC 6.8.1; included in GHC2024 by default.

data Expr a where
  ILit  :: Int  -> Expr Int
  BLit  :: Bool -> Expr Bool
  Add   :: Expr Int  -> Expr Int  -> Expr Int
  And   :: Expr Bool -> Expr Bool -> Expr Bool
  If    :: Expr Bool -> Expr a    -> Expr a -> Expr a

eval :: Expr a -> a
eval (ILit i)    = i                                 -- a ~ Int here
eval (BLit b)    = b                                 -- a ~ Bool here
eval (Add x y)   = eval x + eval y                   -- needs Num a; GADT gives a ~ Int
eval (And x y)   = eval x && eval y                  -- a ~ Bool
eval (If c t e)  = if eval c then eval t else eval e -- a unrefined; propagates from branches
```

What's happening:

1. Each constructor specifies which *index* of `Expr` it inhabits.
2. Pattern-matching on `ILit i` *learns* that the local `a` is `Int`.
3. The body of that branch can then use `a`-as-`Int` operations.

This is the same mechanism that *eliminates* the existential a regular ADT
constructor would introduce. With a plain ADT you would need a runtime
case discrimination plus an unsafe coercion to recover the type. With a
GADT the discrimination *is* the type refinement.

### Indexed GADTs — the dependent-type bridge

```haskell
{-# LANGUAGE GADTs, DataKinds, KindSignatures #-}
-- DataKinds promotes data declarations to the kind level:
-- after `data Nat = Z | S Nat`, you can use 'Z and 'S as kind-level constants.

data Nat = Z | S Nat

data Vec (n :: Nat) a where
  VNil  :: Vec 'Z a
  VCons :: a -> Vec n a -> Vec ('S n) a

vhead :: Vec ('S n) a -> a
vhead (VCons x _) = x
-- Crucially: the pattern `VNil` is NOT considered by the totality checker
-- here, because VNil :: Vec 'Z, and 'Z /= 'S n.
```

This is GHC's encoding of length-indexed vectors — the same `Vect` from
`dependent-types.md`, expressed at the type-family level rather than as
genuine dependent types. The compiler reasons about `'Z` and `'S` as
kind-level constants.

### Cross-language GADT story

| Language    | GADT support                                                 |
|-------------|---------------------------------------------------------------|
| Haskell (GHC) | Native, via `{-# LANGUAGE GADTs #-}`                         |
| OCaml       | Native since 4.00 — different syntax, same semantics          |
| Scala 3     | Pattern matching refines type parameters; cleaner than Scala 2 |
| Idris/Agda  | GADTs are degenerate dependent types — every datatype is "GADT-like" |
| Rust        | No direct support; emulate via trait + associated type, or via discriminated enum + unsafe downcast |
| TypeScript  | Approximated via discriminated unions + conditional types     |
| Java/C\#/Kotlin | No support; the pattern requires reified generics             |

```ocaml
(* OCaml GADT *)
type _ term =
  | ILit  : int  -> int term
  | BLit  : bool -> bool term
  | Add   : int term * int term -> int term
  | If    : bool term * 'a term * 'a term -> 'a term

let rec eval : type a. a term -> a = function
  | ILit i      -> i
  | BLit b      -> b
  | Add (x, y)  -> eval x + eval y
  | If (c,t,e)  -> if eval c then eval t else eval e
```

Note the `type a.` syntax: OCaml needs a *locally abstract type* annotation
to convince the type checker that `a` may be different in each branch.

---

## II. Type families — functions at the type level

A **type family** is a function whose domain and codomain are types. GHC
distinguishes:

- **Closed type families** — pattern-matched at the type level, like a
  type-level `case`.
- **Open type families** — extensible; instances added in any module.
- **Associated type families** — type families inside a type class.

```haskell
{-# LANGUAGE TypeFamilies, DataKinds #-}

-- Closed type family: type-level addition
type family Plus (n :: Nat) (m :: Nat) :: Nat where
  Plus 'Z      m = m
  Plus ('S n)  m = 'S (Plus n m)

-- Now we can give VAppend a precise return type:
vappend :: Vec n a -> Vec m a -> Vec (Plus n m) a
vappend VNil         ys = ys
vappend (VCons x xs) ys = VCons x (vappend xs ys)
```

GHC reduces `Plus ('S ('S 'Z)) ('S 'Z)` to `'S ('S ('S 'Z))` during
type-checking by following the equations. **This is type-level computation.**
It is decidable iff your type-family definitions are terminating and
non-overlapping; GHC checks this for closed families.

### Associated type families — the Rust-trait analogue

```haskell
class Container c where
  type Elem c :: Type
  empty :: c
  insert :: Elem c -> c -> c

instance Container [a] where
  type Elem [a] = a
  empty = []
  insert = (:)
```

This is the conceptual ancestor of Rust's
`trait Iterator { type Item; ... }`. The implementer picks `Elem`; callers
get to refer to it as `Elem c`.

### Type families vs functional dependencies

Before type families, Haskell encoded "X determines Y" via *functional
dependencies* (`class C a b | a -> b`). Type families are strictly more
expressive and have largely superseded fundeps in new code, though both
mechanisms coexist. The pragmatic guidance: prefer type families for new
work; understand fundeps when reading older code or the `mtl` /
`monad-control` ecosystems.

---

## III. Higher-kinded types

Most languages let you abstract over types (`<T>`). HKT lets you abstract
over *type constructors* — things of kind `Type -> Type` (or higher).

```haskell
class Functor (f :: Type -> Type) where
  fmap :: (a -> b) -> f a -> f b

instance Functor Maybe       where fmap g Nothing  = Nothing
                                   fmap g (Just x) = Just (g x)
instance Functor []          where fmap = map
instance Functor (Either e)  where fmap g (Left e)  = Left e
                                   fmap g (Right x) = Right (g x)
```

The parameter `f` of `Functor` is *not* a type — it's a *type
constructor*. `Functor Int` is ill-kinded; `Functor Maybe` is fine.

```scala
// Scala 3: F[_] is HKT syntax
trait Functor[F[_]]:
  extension [A, B](fa: F[A]) def map(f: A => B): F[B]

given Functor[Option] with
  extension [A, B](fa: Option[A]) def map(f: A => B): Option[B] = fa.map(f)
```

### Languages with native HKTs

- **Haskell** — first-class.
- **Scala (2 + 3)** — `F[_]` syntax. The reason `cats` and `scalaz` exist.
- **PureScript** — first-class.
- **Idris / Agda / Lean** — trivially (everything is dependent).

### Languages without

- **Rust** — `trait` + associated types is *almost* HKT, but you can't
  abstract over the trait constructor itself. Workaround: GATs (generic
  associated types) plus the "lending" pattern; or defunctionalization
  via type-level keys.
- **TypeScript** — no native HKT; the `fp-ts`/`Effect` ecosystem
  defunctionalizes via a URI-to-type registry (the "HKT encoding").
- **Kotlin, Swift, Java, C#, Go** — no.

### The defunctionalization encoding

The trick: represent each type constructor as a *type-level key*, and
have a *type-level function* that maps `(Key, Arg)` to the applied type.

```typescript
// Pseudo-code from fp-ts-style libraries
interface HKT<URI, A> { readonly _URI: URI; readonly _A: A; }

interface URI2HKT<A> {
  Option: Option<A>;
  List:   List<A>;
  Either: Either<unknown, A>;
}
type URIS = keyof URI2HKT<unknown>;
type Kind<URI extends URIS, A> = URI2HKT<A>[URI];

interface Functor<F extends URIS> {
  map<A, B>(fa: Kind<F, A>, f: (a: A) => B): Kind<F, B>;
}
```

This is verbose but works. The cost is real — most TS codebases either
accept the verbosity (Effect-TS style) or stay at the type-class-per-type
level and forgo the abstraction.

### Kind polymorphism

Polymorphism over the *kind* itself.

```haskell
{-# LANGUAGE PolyKinds #-}
data Proxy (a :: k) = Proxy
-- Proxy :: forall k. k -> Type
-- Works for any kind k: Proxy Int (k = Type), Proxy 'True (k = Bool), …
```

Rare in application code; essential in generic-programming libraries
(`generics-sop`, `singletons`, anything that lifts data to the type level).

---

## IV. Phantom types — the zero-cost discipline

A phantom type is a type parameter that **never appears in any field**.
Its sole job is to tag the type for the compiler.

```haskell
-- Validated vs Raw input — same runtime representation, different type
data Validated
data Raw

newtype UserInput a = UserInput String

raw :: String -> UserInput Raw
raw = UserInput

validate :: UserInput Raw -> Maybe (UserInput Validated)
validate (UserInput s)
  | isValid s = Just (UserInput s)
  | otherwise = Nothing

submit :: UserInput Validated -> IO ()
submit (UserInput s) = ...

-- submit (raw "hi")          -- type error: needs Validated
-- submit =<< validate (raw "hi")  -- monadic chain works
```

The runtime payload is just `String`. The compiler refuses to let you
call `submit` until you've passed through `validate`. **Zero runtime
overhead, full compile-time discipline.**

### Type-state — phantom types with a transition function

The pattern at scale: a state-machine where the *type* of the handle
records the current state, and methods are available only in the
appropriate states.

```haskell
data Closed
data Open
data Authenticated

newtype Conn s = Conn { socket :: Socket }

open      :: Address -> IO (Conn Open)
authenticate :: Credentials -> Conn Open -> IO (Conn Authenticated)
send      :: Conn Authenticated -> ByteString -> IO ()
close     :: Conn s -> IO (Conn Closed)
```

The Rust cousin uses `PhantomData<State>` plus `impl<S> Conn<S>` blocks
gated on `S`. See `rust/typespace.md` § "Type-state as design tool" for
the Rust-side discipline. The cross-language essence is in `SKILL.md`
§ VII.3.

---

## V. Type-level naturals and singletons

Linking value-level data to type-level data so the compiler can reason
about both simultaneously.

```haskell
{-# LANGUAGE DataKinds, GADTs, KindSignatures #-}

data Nat = Z | S Nat

-- Singleton: one inhabitant per type-level Nat
data SNat (n :: Nat) where
  SZ :: SNat 'Z
  SS :: SNat n -> SNat ('S n)

-- Pattern matching on SNat n LEARNS what 'n' is.
plusS :: SNat n -> SNat m -> SNat (Plus n m)
plusS SZ     m = m
plusS (SS n) m = SS (plusS n m)
```

The `singletons` library automates this for any algebraic data type. The
discipline is the canonical "lift value-level data to types so both
levels share a story" technique in non-dependently-typed Haskell.

GHC's `KnownNat`/`SomeNat` machinery in `GHC.TypeLits` gives you
type-level `Nat` and `Symbol` (type-level strings) with reflection back
to values.

---

## VI. Row polymorphism — open records and open variants

Row polymorphism lets a function require *at least* certain fields, but
accept records that have more.

```ocaml
(* OCaml: structural object types with row variables *)
let name_length x = String.length x#name
(* val name_length : < name : string; .. > -> int *)
(* The ".." is the row variable. Any object with at least a name : string works. *)
```

```purescript
-- PureScript: explicit row polymorphism on records
nameOf :: forall r. { name :: String | r } -> String
nameOf rec = rec.name

-- This function works for { name :: String }, { name :: String, age :: Int }, etc.
```

Row polymorphism cleanly subsumes:

- **Width subtyping** (you can pass a wider record where a narrower one is
  expected) — *without* losing access to the extra fields if you keep them
  in the row variable.
- **Update polymorphism** (`{ rec | x = e }` updates a field while
  preserving the rest of the row).

```purescript
-- Updating one field while preserving the rest of the row
setName :: forall r. String -> { name :: String | r } -> { name :: String | r }
setName n rec = rec { name = n }
```

### Row polymorphism by language

| Language       | Row polymorphism                                         |
|----------------|----------------------------------------------------------|
| OCaml          | Native, via object types `< field : t; .. >`             |
| PureScript     | Native, on records and variants                          |
| Elm            | Limited (`{ rec | f = v }`); extensible records removed in 0.19 |
| Haskell        | Not native; encoded via `vinyl`, `rio`'s `Has` pattern, or first-class records (in progress) |
| TypeScript     | Approximated via intersection types and `Pick`/`Omit`/`Partial` utility types |
| Rust           | None; structs are closed                                 |

### Open variants (polymorphic variants)

```ocaml
(* OCaml: polymorphic variants — sums whose tag set is inferable per use *)
let classify = function
  | `Pos -> "positive"
  | `Zero -> "zero"
  | `Neg -> "negative"
(* val classify : [< `Neg | `Pos | `Zero ] -> string *)
```

The `[< ...]` syntax expresses *subset* polymorphism: this function
accepts any subset of the listed tags. Useful for tag-based APIs where
the producer and consumer don't want to agree on the full enum.

---

## VII. TypeScript's conditional / mapped / template-literal type machine

TypeScript's type system, despite being unsound at the value level, is
**Turing-complete at the type level**. Used heavily in library APIs
(`react`, `zod`, `drizzle`, `effect`). The machinery is built from three
primitives.

### Conditional types

```typescript
type IsString<T> = T extends string ? "yes" : "no";
type A = IsString<"hello">;   // "yes"
type B = IsString<42>;        // "no"
```

The `extends ? :` form is a type-level ternary. Distributes over unions:

```typescript
type ToArray<T> = T extends any ? T[] : never;
type R = ToArray<string | number>;
// = (string extends any ? string[] : never) | (number extends any ? number[] : never)
// = string[] | number[]
```

Use `[T] extends [...]` to *suppress* distribution when you want the
union as a whole.

### `infer` keyword

```typescript
type ReturnType<F> = F extends (...args: any[]) => infer R ? R : never;
type ElementOf<A> = A extends (infer E)[] ? E : never;

type R1 = ReturnType<() => number>;        // number
type E1 = ElementOf<string[]>;              // string
```

`infer X` binds a fresh type variable inside the `extends` clause to
whatever appears in that position. This is *higher-order type-level
pattern matching*.

### Mapped types

```typescript
// Make every field optional
type Partial<T> = { [K in keyof T]?: T[K] };

// Strip readonly from every field
type Mutable<T> = { -readonly [K in keyof T]: T[K] };

// Filter fields by their value type
type StringKeys<T> = { [K in keyof T]: T[K] extends string ? K : never }[keyof T];
type Names = StringKeys<{ id: number; name: string; email: string }>;
// "name" | "email"
```

Combined with `as` clauses you can *rename* keys:

```typescript
type Getters<T> = {
  [K in keyof T as `get${Capitalize<K & string>}`]: () => T[K]
};
type G = Getters<{ id: number; name: string }>;
// { getId: () => number; getName: () => string }
```

### Template-literal types

```typescript
type Greeting<N extends string> = `Hello, ${N}!`;
type G = Greeting<"world">;   // "Hello, world!"

// Parse a route into its params (verified pattern in router libs):
type Params<S extends string> =
  S extends `${infer _Before}:${infer Param}/${infer Rest}` ? Param | Params<Rest> :
  S extends `${infer _Before}:${infer Param}`              ? Param :
  never;

type P = Params<"/users/:id/posts/:postId">;   // "id" | "postId"
```

Template-literal types compose with `Uppercase` / `Lowercase` /
`Capitalize` / `Uncapitalize` intrinsic types and with `infer` for
parsing.

### Variance annotations — `in`, `out`, `in out`

TypeScript 4.7 added explicit variance annotations:

```typescript
// Verified against the TypeScript handbook.
interface Producer<out T>     { make(): T; }                       // covariant
interface Consumer<in T>      { consume(arg: T): void; }           // contravariant
interface ProducerConsumer<in out T> { make(): T; consume(arg: T): void; } // invariant
```

These are *checked* by the compiler — if you annotate `out T` but use `T`
in input position, the compiler flags it. Useful in performance-sensitive
code (TS spends real time on variance inference in large unions; explicit
annotations let it skip the work).

### The cost — type-checker performance

Real-world TypeScript types can be slow to check (multi-second
inference, "type instantiation excessively deep" errors). The standard
mitigations:

1. Cache intermediate types in `type` aliases (TS memoizes by alias).
2. Annotate variance when you know it.
3. Replace deeply recursive conditional types with tail-recursive
   accumulator-style equivalents.
4. Use `// @ts-expect-error` sparingly to short-circuit pathological
   computations that don't affect correctness.

---

## VIII. Singletons, finally-tagless, and the "extensible interpreter" patterns

Once you have GADTs + type families, two patterns recur:

### Finally-tagless

Instead of a GADT, parameterize the *interpretation* by a type class:

```haskell
class Expr repr where
  ilit :: Int -> repr Int
  blit :: Bool -> repr Bool
  add  :: repr Int -> repr Int -> repr Int
  if_  :: repr Bool -> repr a -> repr a -> repr a

-- One interpreter: evaluate
newtype Eval a = Eval { runEval :: a }
instance Expr Eval where
  ilit i = Eval i
  blit b = Eval b
  add (Eval x) (Eval y) = Eval (x + y)
  if_ (Eval c) t e = if c then t else e

-- Another: pretty-print
newtype Pretty a = Pretty { runPretty :: String }
instance Expr Pretty where
  ilit i = Pretty (show i)
  blit b = Pretty (show b)
  add x y = Pretty (runPretty x ++ " + " ++ runPretty y)
  if_ c t e = Pretty ("if " ++ runPretty c ++ " then " ++ runPretty t ++ " else " ++ runPretty e)
```

The GADT defines the *syntax* once and lets you *add interpreters*
without touching the AST. Finally-tagless defines the *interface* and
lets you *add interpreters AND new operations* without touching either.

The Scala 3 / cats-effect ecosystem leans heavily on finally-tagless for
effect abstraction (the `F[_]` you see everywhere). Rust's trait+impl
pattern is structurally similar (define `trait Repr` with associated
output type, write multiple impls).

### Free monads — the GADT cousin

```haskell
data Free f a = Pure a | Free (f (Free f a))
-- f is the "instruction set"; Free f is the program; a is the result.
```

Free monads pair with GADTs for the instruction set, giving the same
"separate syntax from interpretation" benefit. The trade-off vs
finally-tagless is mostly performance and ergonomics; both encode the
same algebra.

---

## IX. Decision matrix — type-level tool by problem

| Problem                                                        | Reach for                                          |
|----------------------------------------------------------------|-----------------------------------------------------|
| Embed a typed DSL whose return type depends on the AST node    | GADT                                               |
| Compute a return type from input types (e.g., zip length)      | Type family (closed for arithmetic, associated for trait-attached) |
| Abstract over `Maybe` / `Either` / `IO` / etc. uniformly       | HKT (Functor/Monad type class)                     |
| Tag a value with compile-time-only state                       | Phantom type                                       |
| Refuse to let `send` be called before `authenticate`           | Type-state (phantom + lifecycle methods)            |
| Encode "at least these fields"                                 | Row polymorphism (PureScript/OCaml) or structural subtyping (TS) |
| Parse a string at the type level                               | Template-literal type + `infer` (TS) / type families + Symbols (Haskell) |
| Reflect value-level data to types                              | Singletons (Haskell) / proof terms (Idris/Agda)    |
| Add an interpreter without touching the AST                    | Finally-tagless, or GADT + new fold                |
| Statically forbid certain instances                            | Sealed trait (Rust) / closed type family (Haskell) |

---

## X. Anti-patterns specific to type-level programming

| Smell                                                  | Why it's a smell                                                            |
|--------------------------------------------------------|-----------------------------------------------------------------------------|
| 200-line conditional-type chains (TS)                  | Type checker turns into a Prolog interpreter; build times tank              |
| `unsafeCoerce` to "fix" a GADT mismatch                | The GADT contract is wrong; restructure                                     |
| Type families that don't terminate                     | Compiler hangs; or a "type family application is stuck" error               |
| Phantom types with no smart constructor                | Anyone can produce a "validated" value; the tag is meaningless              |
| HKT encoding everywhere in TS                          | You're fighting the language; either accept the cost or switch              |
| GADT + GADT + GADT for what could be a discriminated union | The type refinement is being paid for and not used                      |
| Singletons reinvented per data type                    | Use `singletons-th` to derive them                                          |

---

## XI. Canonical external references

- **GHC user's guide — extensions chapter** —
  https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/
  (covers `GADTs`, `TypeFamilies`, `DataKinds`, `PolyKinds`, `KindSignatures`)
- **GHC2024 language description** —
  https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/control.html
- **TypeScript handbook — advanced types** —
  https://www.typescriptlang.org/docs/handbook/2/types-from-types.html
- **Scala 3 reference — type lambdas, match types, kind polymorphism** —
  https://docs.scala-lang.org/scala3/reference/new-types/
- **OCaml manual — polymorphic variants, GADTs, modules** —
  https://v2.ocaml.org/manual/
- **PureScript — row polymorphism, records** —
  https://book.purescript.org/
- **`singletons` library** — https://hackage.haskell.org/package/singletons
- **`cats` (Scala HKT ecosystem)** — https://typelevel.org/cats/
- **`fp-ts` (TS HKT encoding)** — https://gcanti.github.io/fp-ts/
- **Wadler, "Theorems for Free!"** — the parametricity reference

Type-level programming syntax and semantics evolve fast — GHC adds
extensions every release, TypeScript adds language features every quarter,
Scala 3 reworked the implicit/given story. Use the canonical references
when a specific feature claim matters; this skill captures the patterns.
