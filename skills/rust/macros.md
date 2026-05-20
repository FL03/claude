# Macros — Compile-Time Code Generation

Rust has two macro systems. Both run at compile time and produce source code that the
compiler then type-checks as normal Rust. Macros don't bypass the type system — they
generate code that must pass every check a hand-written version would.

---

## I. Declarative Macros (`macro_rules!`)

Pattern-match on syntax fragments. The macro definition is a set of arms; the compiler
tries each arm top-to-bottom until one matches.

### Fragment Specifiers

| Specifier | Matches | Example |
|-----------|---------|---------|
| `$x:expr` | Any expression | `1 + 2`, `foo()`, `if c { a } else { b }` |
| `$x:ty` | A type | `i32`, `Vec<String>`, `&'a str` |
| `$x:ident` | An identifier | `my_var`, `MyStruct` |
| `$x:pat` | A pattern | `Some(x)`, `(a, b)`, `_` |
| `$x:path` | A type path | `std::io::Read`, `crate::MyTrait` |
| `$x:stmt` | A statement | `let x = 1;` |
| `$x:block` | A block | `{ println!("hi"); 42 }` |
| `$x:item` | A top-level item | `fn foo() {}`, `struct Bar;` |
| `$x:meta` | Attribute content | `derive(Debug)`, `cfg(test)` |
| `$x:tt` | Single token tree | Anything — the universal fallback |
| `$x:literal` | A literal value | `42`, `"hello"`, `true` |
| `$x:vis` | Visibility qualifier | `pub`, `pub(crate)`, (empty) |
| `$x:lifetime` | A lifetime | `'a`, `'static` |

### Repetition Operators

```rust
// Zero or more (*), one or more (+), zero or one (?)
// Separator: any token — comma, semicolon, =>, etc.

macro_rules! vec_of {
    ($($elem:expr),* $(,)?) => {{
        let mut v = Vec::new();
        $(v.push($elem);)*
        v
    }};
}

macro_rules! hash_map {
    ($($key:expr => $val:expr),* $(,)?) => {{
        let mut map = hashbrown::HashMap::new();
        $(map.insert($key, $val);)*
        map
    }};
}
```

### Recursive Macros

```rust
macro_rules! count {
    () => { 0usize };
    ($head:tt $($tail:tt)*) => { 1usize + count!($($tail)*) };
}
```

### Hygiene

Declarative macros are **partially hygienic**: local variables inside the macro don't
leak into the caller's scope, but type and path references use the caller's namespace.
`$crate` references items from the defining crate — resolves correctly whether the macro
is used locally or by a downstream consumer.

```rust
macro_rules! my_assert {
    ($cond:expr) => {
        if !$cond {
            $crate::panic_handler(stringify!($cond), file!(), line!());
        }
    };
}
```

### Common Patterns

- **Table-driven tests** — generate N test functions from `(input, expected)` pairs.
- **Enum dispatch** — match on enum, delegate to identically-named methods.
- **Compile-time assertions** — `const _: () = assert!(size_of::<T>() == 8);`
- **Variadic simulation** — `println!`-style variable argument lists.
- **DSL construction** — routing tables, SQL templates, HTML builders.

---

## II. Procedural Macros

Rust code that takes a `TokenStream`, manipulates it, and returns a new `TokenStream`.
Runs at compile time on the **host** machine (not the target). Lives in a dedicated crate
with `proc-macro = true` in `Cargo.toml` — this is non-negotiable; proc macros cannot
live in a regular library crate.

### The Triad: syn + quote + proc-macro2

| Crate | Role |
|-------|------|
| `proc-macro2` | Wrapper around `proc_macro::TokenStream` usable outside proc-macro crates (enables unit testing) |
| `syn` | Parser: `TokenStream` into structured AST — `DeriveInput`, `ItemFn`, `Expr`, etc. |
| `quote` | Code generator: `quote! { ... }` turns Rust-like syntax back into `TokenStream` |

```toml
# Proc-macro crate Cargo.toml
[lib]
proc-macro = true

[dependencies]
syn = { version = "2", features = ["full", "extra-traits"] }
quote = "1"
proc-macro2 = "1"
```

### Three Flavors

#### 1. Derive Macros — `#[derive(MyTrait)]`

**Appends** an impl block to the annotated struct/enum. Cannot modify the original item.
The most common flavor — serde, thiserror, sqlx all use derive macros.

```rust
use proc_macro::TokenStream;
use quote::quote;
use syn::{parse_macro_input, DeriveInput, Data, Fields};

#[proc_macro_derive(MyTrait, attributes(my_attr))]
pub fn derive_my_trait(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    let name = &input.ident;
    let (impl_generics, ty_generics, where_clause) = input.generics.split_for_impl();

    let expanded = quote! {
        impl #impl_generics MyTrait for #name #ty_generics #where_clause {
            fn name(&self) -> &'static str {
                stringify!(#name)
            }
        }
    };
    TokenStream::from(expanded)
}
```

**Field iteration** (the core of most derive macros):

```rust
match &input.data {
    Data::Struct(data) => match &data.fields {
        Fields::Named(fields) => {
            for field in &fields.named {
                let name = &field.ident;
                let ty = &field.ty;
                // Check for helper attributes
                let has_skip = field.attrs.iter().any(|a| a.path().is_ident("my_attr"));
            }
        }
        Fields::Unnamed(fields) => { /* tuple struct — index by position */ }
        Fields::Unit => { /* unit struct — no fields */ }
    },
    Data::Enum(data) => {
        for variant in &data.variants {
            let vname = &variant.ident;
            // Handle variant fields the same way as struct fields
        }
    },
    Data::Union(_) => { /* rarely supported — usually reject with compile_error! */ }
}
```

**Helper attributes** — `attributes(my_attr)` in the derive declaration registers `#[my_attr]`
as a recognized attribute on fields/variants. Without this, the compiler warns about unknown
attributes. Parse them with `field.attrs.iter().find(|a| a.path().is_ident("my_attr"))`.

#### 2. Attribute Macros — `#[my_attr(...)]`

Receives the attribute arguments AND the annotated item. **Can modify or replace** the
original — more powerful than derive, used for code-transformation patterns.

```rust
#[proc_macro_attribute]
pub fn traced(attr: TokenStream, item: TokenStream) -> TokenStream {
    let func = parse_macro_input!(item as syn::ItemFn);
    let func_name = &func.sig.ident;
    let func_block = &func.block;
    let func_sig = &func.sig;
    let func_vis = &func.vis;
    let func_attrs = &func.attrs;

    let expanded = quote! {
        #(#func_attrs)*
        #func_vis #func_sig {
            let _span = tracing::info_span!(stringify!(#func_name)).entered();
            #func_block
        }
    };
    TokenStream::from(expanded)
}
```

#### 3. Function-Like Macros — `my_macro!(...)`

Invoked like a function call. Full control over input parsing — the input can be any
token stream, not necessarily valid Rust syntax.

```rust
#[proc_macro]
pub fn sql(input: TokenStream) -> TokenStream {
    let query = parse_macro_input!(input as syn::LitStr).value();
    // Validate SQL at compile time, generate typed query struct
    let expanded = quote! {
        SqlQuery::new(#query)
    };
    TokenStream::from(expanded)
}
```

### Error Reporting

Use `syn::Error` for user-facing compile errors with precise source spans:

```rust
fn validate(input: &DeriveInput) -> syn::Result<proc_macro2::TokenStream> {
    if input.generics.lifetimes().count() > 0 {
        return Err(syn::Error::new_spanned(
            &input.generics,
            "MyTrait cannot be derived on types with lifetime parameters"
        ));
    }
    Ok(quote! { /* ... */ })
}

// In the proc_macro entry point:
#[proc_macro_derive(MyTrait)]
pub fn derive(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    match validate(&input) {
        Ok(tokens) => TokenStream::from(tokens),
        Err(err) => TokenStream::from(err.to_compile_error()),
    }
}
```

`new_spanned` attaches the error to the exact span in user code — the compiler
error message points at the user's struct, not inside your proc-macro crate.

### Testing Proc Macros

```bash
# See the full macro expansion (requires nightly)
cargo +nightly expand --lib -p my-crate

# Expand a single item
cargo +nightly expand --lib -p my-crate -- my_module::MyStruct
```

**`trybuild`** — snapshot testing for proc macros. Compile test cases, assert success or
specific error messages:

```rust
#[test]
fn compile_tests() {
    let t = trybuild::TestCases::new();
    t.pass("tests/expand/pass/*.rs");
    t.compile_fail("tests/expand/fail/*.rs");
}
```

**Unit testing with `proc-macro2`**: since `proc_macro::TokenStream` is only usable inside
a proc-macro crate, factor your logic into functions taking `proc_macro2::TokenStream` and
test those in a regular `#[cfg(test)]` module.

---

## III. Proc-Macro Crate Structure

```
my-macros/
  Cargo.toml          # [lib] proc-macro = true
  src/
    lib.rs            # Entry points: #[proc_macro_derive], #[proc_macro_attribute], #[proc_macro]
    derive_foo.rs     # Logic for #[derive(Foo)] — returns proc_macro2::TokenStream
    attr_bar.rs       # Logic for #[bar] attribute

my-crate/
  Cargo.toml          # depends on my-macros
  src/
    lib.rs            # Uses #[derive(Foo)] and #[bar]
```

The proc-macro crate is compiled for the **host** architecture (your dev machine), even
when the consumer targets `wasm32-wasip2` or `aarch64-unknown-linux-gnu`. This means:
- Proc macros can use `std`, filesystem, network — they run during compilation, not at runtime.
- Cross-compilation is transparent: the macro crate builds for host, the consuming crate builds for target.
- Build dependencies (`syn`, `quote`) only affect host compile time, never the final binary.

### Re-Export Pattern

Consumers shouldn't depend on both the proc-macro crate and the main crate. The main crate
re-exports the macros:

```rust
// In my-crate/src/lib.rs
pub use my_macros::Foo;   // re-export the derive macro
pub use my_macros::bar;   // re-export the attribute macro
```

Consumers write `use my_crate::Foo;` — they never mention `my-macros` directly.

---

## IV. Decision Matrix

| Need | Use |
|------|-----|
| Repetitive boilerplate, enum dispatch, variadic calls | `macro_rules!` |
| Generate impl blocks from struct/enum shape | `#[derive(X)]` |
| Transform/annotate functions or types | `#[attribute]` |
| Custom DSL syntax (embedded SQL, HTML, routing) | `function_like!()` |
| Avoid writing the same code twice | Regular function or generic first |

### When NOT to use macros

- A generic function, trait, or closure composes better and gives clearer error messages.
- 3-5 lines appearing twice is cheaper than a macro with worse error diagnostics.
- A macro that hides control flow (`?`, `return`, `break`) is invisible at the call site — readers
  can't see that the macro early-returns.
- A macro that only saves typing but doesn't enforce an invariant is net-negative:
  the abstraction cost exceeds the keystroke savings.
