# Rust ↔ WebAssembly

Rust's integration with WebAssembly. Language-agnostic material (what IS a component? what IS
WASI? WIT syntax?) lives in the **`webassembly`** sibling skill. This file covers the Rust
side: which target, which tool, how the Cargo crate is laid out, how features are structured.

For host-side embedding (loading a `.wasm` component from a Rust process), see
**`wasmtime-host.md`**.

---

## Four tools, four jobs

| Concern | Tool | Used for |
|---|---|---|
| Compilation target | `rustup target add wasm32-wasip2` | Which ABI the `.wasm` binary speaks |
| Component build | `cargo-component` | Produces the component-model `.wasm` artifact |
| Guest bindings | `wit-bindgen` (crate) | Generates Rust types/traits from WIT for the guest |
| Host embedding | `wasmtime` (crate) | Runs components inside a Rust process |

A fifth tool, `wasm-bindgen`, solves a **different** problem: JS interop for browsers. It has
nothing to do with the component model and is not used outside the browser. If you see it
mentioned in a server/CLI context, something is wrong.

Reference: `docs.rs/cargo-component`, `docs.rs/wit-bindgen`, `docs.rs/wasmtime`.

---

## Decision tree

**Building a WASM component for a server/runtime host?**
→ Target `wasm32-wasip2`. Build with `cargo-component`. Generate bindings with
`wit_bindgen::generate!`. See the Component crate pattern below.

**Embedding components into your Rust service?**
→ Add `wasmtime` + `wasmtime-wasi`. See `wasmtime-host.md` for the embedding recipe.

**Targeting the browser with JS bindings?**
→ Target `wasm32-unknown-unknown`. Use `wasm-bindgen` + `wasm-pack`. Completely separate
ecosystem from the component model. Check `docs.rs/wasm-bindgen` for API; this skill does
not cover browser-JS interop beyond saying "it's a different world".

**Targeting legacy WASI preview1 tooling?**
→ `wasm32-wasip1`. Prefer preview2 for anything new.

---

## Ecosystem splits — the ones that trip people up

**`cargo-component` vs `wasm-pack`:** different deployment worlds.
- `cargo-component` → component model, `wasm32-wasip2`, WIT-typed interfaces, server/runtime.
- `wasm-pack` → browser, `wasm32-unknown-unknown`, JS bindings via `wasm-bindgen`, npm.

Do not mix them. The build, the toolchain, and the output are incompatible.

**`wit-bindgen` vs `wasm-bindgen`:** named alike, solve unrelated problems.
- `wit-bindgen` → Rust code from WIT definitions; component model guests and hosts.
- `wasm-bindgen` → JS glue from `#[wasm_bindgen]` attrs; browser only.

Rule: if `.wit` or "component" is in the context, use `wit-bindgen`. If "browser" or
"JavaScript" is the target, use `wasm-bindgen`.

---

## Component crate pattern

Rust components typically follow a minimal single-file layout:

```
my-component/
├── Cargo.toml          # crate-type = ["cdylib", "rlib"]
└── lib.rs              # the entire component
```

No `src/` subdirectory. The path is explicit: `path = "lib.rs"` in `[lib]`. Single-file
components have a clean dep graph and predictable compile.

The WIT contract lives outside the component crate, typically in the driver/runtime layer:

```
crates/drivers/
└── wit/
    ├── driver.wit
    ├── types.wit
    └── world.wit
```

The component implements the WIT `world` — the WIT is the source of truth; the Rust must
satisfy it.

### Dual compilation target

Each component can build as both native (`rlib`) and WASM component (`cdylib`):

```bash
# Native — linked directly into the engine
cargo build -p my-component

# WASM component — hot-swappable at runtime
cargo build -p my-component --target wasm32-wasip2 --features component --no-default-features
```

`--no-default-features` strips `std` and other native-only deps that would fail on `wasm32`.

### Feature structure

```toml
[features]
default   = ["std"]
component = ["default", "witbind"]
wasi      = ["default", "<workspace-umbrella>/wasm", "witbind"]
wasm      = ["default", "<workspace-umbrella>/wasm"]
witbind   = ["dep:wit-bindgen"]

[dependencies]
wit-bindgen = { workspace = true, optional = true }
```

Gate `wit-bindgen` optional; enable only for `component` / `wasi` builds. A native build
that accidentally pulls `wit-bindgen` wastes compile time.

---

## Minimal component — `lib.rs`

```rust
#[cfg(feature = "component")]
mod bindings {
    wit_bindgen::generate!({
        world: "my-world",
        path:  "wit",
    });
}

#[cfg(feature = "component")]
use bindings::Guest;

pub struct MyComponent;

#[cfg(feature = "component")]
impl Guest for MyComponent {
    fn compute(input: f64) -> f64 {
        input * 2.0
    }
}

#[cfg(feature = "component")]
bindings::export!(MyComponent with_types_in bindings);
```

Minimal `Cargo.toml`:

```toml
[package]
name    = "my-component"
version = "0.1.0"
edition = "2024"

[lib]
crate-type = ["cdylib"]   # required for .wasm output; add "rlib" for native linking

[dependencies]
wit-bindgen = { version = "0.36", optional = true }

[features]
default   = ["std"]
std       = []
component = ["dep:wit-bindgen"]
```

---

## Conditional compilation — native vs wasm32

```rust
#[cfg(target_arch = "wasm32")]
fn now_ms() -> u64 {
    // host-injected clock via WASI
    wasi::clocks::monotonic_clock::now() / 1_000_000
}

#[cfg(not(target_arch = "wasm32"))]
fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
}
```

Feature-gate when the distinction is deployment-time; `target_arch` when it is
platform-intrinsic. They compose cleanly.

---

## Build commands

```bash
# Once: add the target
rustup target add wasm32-wasip2

# Once: install cargo-component
cargo install cargo-component

# Build
cargo component build -p my-component --release

# Inspect the exported WIT world
wasm-tools component wit target/wasm32-wasip2/release/my_component.wasm
```

---

## Cross-references

- **`wasmtime-host.md`** — full host-embedding recipe (Engine/Store/Linker/Component, WASI
  grants, `Mutex`-wrapped state, error handling).
- **`webassembly`** skill — WIT syntax, component-model semantics, WASI capabilities, binary
  format. Cross there for any language-agnostic question.
- **docs.rs** — `wit-bindgen`, `wasmtime`, `cargo-component` API references. Prefer the
  canonical source over a local cheatsheet.

Rule of thumb: **"how do I make this compile/build/link in Rust?"** stays here.
**"what does this WIT contract mean?"** or **"what WASI capabilities does X need?"** goes to
the `webassembly` skill.
