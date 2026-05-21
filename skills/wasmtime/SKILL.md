---
name: wasmtime
slug: wasmtime
version: 5.1.0
description: |
  Rust-side host embedding of the wasmtime WebAssembly runtime. Covers the
  Engine / Store / Linker / Component lifecycle, the `bindgen!` macro for
  WIT-generated host bindings, WASI capability grants (clocks, fs, net,
  stdio, env, args), `&self` ergonomics via `Arc<Mutex<...>>`, hot-swap
  patterns, error handling and trap diagnosis, AOT precompilation, async
  support, and debug surfaces (core dumps, backtraces). Companion to the
  `webassembly` skill (language-agnostic: WIT, component model, WASI
  semantics) and the `rust` skill (idioms, cargo, rustc). Reach for this
  skill for any "how do I load and call a `.wasm` from Rust?" question.
metadata:
  openclaw:
    emoji: "🧩"
    requires:
      bins: ["cargo"]
    os: ["linux", "darwin", "win32"]
---

# wasmtime — Rust Host Embedding

Embedding `wasmtime` in a Rust application lets the host load and invoke WASM
components at runtime. This is the standard mechanism for any Rust host that
wants to run hot-swappable WASM components.

This SKILL.md is the primer + index. Read it end-to-end when attached; jump to
the matching section for depth. For language-agnostic WIT / component model /
WASI semantics see the `webassembly` skill. For Rust idioms (ownership, async,
`Arc<Mutex<...>>`, error handling shape) see the `rust` skill.

---

## 0. Version Pinning — Read This First

Wasmtime ships a major release roughly every month. The component model ABI
between minor versions is stable; **the host crate's Rust API is not**. The
WasiView trait, linker helpers, and `wasmtime_wasi` module layout have all
been reshaped multiple times. **Always check docs.rs for the version you are
pinning** before copying examples from any skill, blog, or training-data
memory — including this one.

```toml
[dependencies]
wasmtime       = "44"   # check https://crates.io/crates/wasmtime for current
wasmtime-wasi  = "44"   # match the wasmtime major; optional for pure-compute
anyhow         = "1"
```

Canonical references (open these first):

- <https://docs.wasmtime.dev/> — project docs (user-facing).
- <https://docs.rs/wasmtime/latest/wasmtime/> — Rust API reference (per-version).
- <https://docs.rs/wasmtime-wasi/latest/wasmtime_wasi/> — WASI host integration.
- <https://github.com/bytecodealliance/wasmtime> — source.

Pin the major version in the workspace `Cargo.toml`. A major bump can move
modules (`wasmtime_wasi::preview2::*` → `wasmtime_wasi::p2::*`), change the
WasiView trait shape, or rename `add_to_linker*` helpers. Component binaries
themselves remain loadable across major host versions — the ABI break is on
the host-Rust side.

For pure-compute components (no WASI), `wasmtime-wasi` is optional. A
pure-compute driver omits it when the component has no filesystem, network,
clock, env, or stdio imports.

---

## 1. The Four Core Types

The wasmtime embedding stack is four types. Memorize their roles and lifetimes.

**`Engine`** — global configuration and compilation settings. Create once per
process. Expensive to create (initializes Cranelift); cheap to clone (`Arc`
internally). `Engine` is `Send + Sync`. Share it across threads, instances,
and stores.

**`Component`** — the parsed and compiled WASM component binary. Shallow-clone
is cheap (just a new `Arc` reference). Compile once via `Component::from_file`
or `Component::new`, then instantiate into many stores. For
production, precompile to bytes via `Component::serialize` and load via
`Component::deserialize` (unsafe — see §7).

**`Linker<T>`** — the set of host functions and WASI interfaces the component
can import. Built once per `Engine`; `T` is the host-state type that imports
will see. Adding the same import twice is an error. WASI is wired via
`wasmtime_wasi::p2::add_to_linker_sync(&mut linker)` (or `_async` variant).

**`Store<T>`** — per-instance execution context. Holds **all** instance state
(linear memory, tables, host data of type `T`). `T` can be `()` for stateless
hosts. Every call into a guest function requires `&mut Store<T>`. A store is
not `Send` unless `T: Send`. After a trap, the store is poisoned — do not
reuse it; drop and re-create.

---

## 2. Loading Flow — Six Steps

### Step 1. Create the engine

```rust
use wasmtime::{Config, Engine};

let engine = Engine::default();
```

For component-model components, no explicit feature flag is required on
recent wasmtime majors (it is on by default). For AOT compilation caching:

```rust
let mut config = Config::new();
config.cache_config_load_default()?;  // uses ~/.cache/wasmtime by default
config.cranelift_opt_level(wasmtime::OptLevel::Speed);
let engine = Engine::new(&config)?;
```

For async hosts, enable async support on the config:

```rust
config.async_support(true);
```

This switches the `*_async` variants on at the type level — see §8.

### Step 2. Load the component

```rust
use wasmtime::component::Component;

let component = Component::from_file(&engine, "/path/to/driver.wasm")?;
```

`from_file` reads, parses, validates, and JIT-compiles the component. This is
the expensive step (Cranelift codegen). Cache the resulting `Component` and
reuse it across instantiations. `Component::clone()` is cheap.

### Step 3. Build the linker

```rust
use wasmtime::component::Linker;

let mut linker: Linker<HostState> = Linker::new(&engine);
```

For pure-compute components (no WASI imports), leave the linker empty. For
WASI-using components, see §3.

### Step 4. Generate host bindings via `bindgen!`

The `bindgen!` macro from `wasmtime::component` generates host-side client
structs from a `.wit` file. Two forms — pick by ergonomics:

**Shorthand form** (positional `"world" in "path"`):

```rust
wasmtime::component::bindgen!("drivers" in "./wit");
```

**Block form** (named keys, multiple options):

```rust
mod wit {
    wasmtime::component::bindgen!({
        path: "./wit",
        world: "drivers",
        // async: true,                  // generate async bindings
        // with: { "wasi:io/poll": ... }, // type sharing across worlds
    });
}
```

Both generate a struct named after the world (UpperCamelCase) with
`instantiate` (or `instantiate_async`) and `call_<name>` methods.

For WIT files that **import** host interfaces, `bindgen!` also generates a
`Host` trait per interface. The host implements it and wires it in:

```rust
use wasmtime::component::HasSelf;

impl host::Host for MyState { /* implement each imported function */ }

host::add_to_linker::<_, HasSelf<_>>(&mut linker, |state| state)?;
```

`HasSelf<_>` is the generic helper that says "the state passed to the closure
is the host state itself" (the most common case). For projections through a
wrapper, use a custom `HasData` impl.

### Step 5. Instantiate

```rust
let mut store = Store::new(&engine, HostState { /* fields */ });
let bindings = wit::Drivers::instantiate(&mut store, &component, &linker)?;
```

Instantiation wires the component's imports to the linker's exports, runs the
component's initialization (start function, if any), and returns the
generated bindings struct. **Every import must be satisfied** — missing
imports surface here as a link error, not at the call site.

### Step 6. Call exported functions

```rust
let name   = bindings.call_name(&mut store)?;
let signal = bindings.call_drive(&mut store, &context)?;
```

Generated method names are `call_<wit_function_name>` in snake_case. The
first argument is always `&mut store`. WIT `list<T>` parameters are copied
across the boundary; `record` parameters are laid out by the component model
canonical ABI (not host repr).

### Complete minimal example

```rust
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

wasmtime::component::bindgen!("my-world" in "wit");

struct HostState;

fn run_component(wasm_path: &str, input: f64) -> anyhow::Result<f64> {
    let engine    = Engine::default();
    let component = Component::from_file(&engine, wasm_path)?;
    let linker    = Linker::<HostState>::new(&engine);
    let mut store = Store::new(&engine, HostState);

    let bindings = MyWorld::instantiate(&mut store, &component, &linker)?;
    let result   = bindings.call_compute(&mut store, input)?;
    Ok(result)
}
```

---

## 3. WASI Capability Grants

WASI gives the component a sandboxed, **capability-based** view of the host.
Default is **nothing** — every capability is an explicit grant. There is no
ambient authority.

**API shape (wasmtime ~44):**

```rust
use wasmtime::component::ResourceTable;
use wasmtime_wasi::{WasiCtx, WasiCtxView, WasiView};

struct HostState {
    wasi:  WasiCtx,
    table: ResourceTable,
}

impl WasiView for HostState {
    fn ctx(&mut self) -> WasiCtxView<'_> {
        WasiCtxView { ctx: &mut self.wasi, table: &mut self.table }
    }
}
```

> **Version note.** Older wasmtime versions used a two-method `WasiView`
> (`fn table()` + `fn ctx()`) and exposed builder under `WasiCtxBuilder::new()`.
> Recent versions consolidate into a single `ctx()` returning a `WasiCtxView<'_>`
> struct, with the builder under `WasiCtx::builder()`. Check docs.rs for your
> pinned major.

**Building the context** — every capability is opt-in:

```rust
let wasi = WasiCtx::builder()
    .inherit_stdio()                          // stdout/stderr/stdin from host
    .inherit_env()                            // pass through host env (or use .env(k, v))
    .env("LOG_LEVEL", "info")
    .args(&["driver", "--mode", "fast"])
    .preopened_dir(
        "/host/data",                         // host path
        "/data",                              // guest path
        wasmtime_wasi::DirPerms::READ,
        wasmtime_wasi::FilePerms::READ,
    )?
    .build();

let state = HostState { wasi, table: ResourceTable::new() };
let mut store = Store::new(&engine, state);

wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;   // wire WASI into linker
```

**Capability catalog** (each is a separate WIT interface in the
`wasi:cli` / `wasi:filesystem` / `wasi:clocks` / `wasi:random` / `wasi:sockets`
packages):

| Capability      | What the guest can do                | Builder method (typical)        |
|---|---|---|
| `wasi:clocks`   | Read monotonic + wall clocks         | granted by default with builder |
| `wasi:random`   | Read CSPRNG                          | granted by default              |
| `wasi:cli/stdin/stdout/stderr` | Read/write standard streams | `.inherit_stdio()` or `.stdout(p)` |
| `wasi:cli/environment` | Read env vars + argv          | `.env(k,v)`, `.inherit_env()`, `.args(&[...])` |
| `wasi:filesystem` | Open/read/write inside a preopen   | `.preopened_dir(host, guest, dir_perms, file_perms)` |
| `wasi:sockets`  | TCP/UDP connect+listen               | `.allow_tcp(true)`, `.allow_udp(true)` (gated; check version) |

The guest sees **only** what was granted. A misbehaving `.wasm` cannot escape
its preopens, see un-listed env vars, or open sockets the host did not enable.
Even a malicious component is bounded by the grants.

For a deeper picture of WASI worlds and the preview1-vs-preview2 distinction,
see `webassembly/wasi.md`. The current `wasm32-wasip2` target produces
component-model components that consume the interfaces above.

---

## 4. `&self` Ergonomics — `Arc<Mutex<Inner>>` Pattern

Calling into a component requires `&mut Store<T>`. Most host APIs want the
driver method to take `&self` so it can be invoked from many call sites
concurrently. Wrap the store + bindings in a `Mutex` and expose the driver
as `Arc<Self>`:

```rust
use std::sync::Mutex;
use anyhow::Result;

pub struct WasmDriver {
    name:    String,                      // cached at load time
    version: String,                      //
    inner:   Mutex<Inner>,                // hot state, locked per-call
}

struct Inner {
    store:    Store<HostState>,
    bindings: MyWorld,
}

impl WasmDriver {
    pub fn load(engine: &Engine, path: &str) -> Result<Self> {
        let component = Component::from_file(engine, path)?;
        let mut linker = Linker::<HostState>::new(engine);
        wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;

        let state = HostState { wasi: WasiCtx::builder().build(), table: ResourceTable::new() };
        let mut store = Store::new(engine, state);
        let bindings = MyWorld::instantiate(&mut store, &component, &linker)?;

        // Read metadata once, cache.
        let name    = bindings.call_name(&mut store)?;
        let version = bindings.call_version(&mut store)?;

        Ok(Self { name, version, inner: Mutex::new(Inner { store, bindings }) })
    }

    pub fn name(&self) -> &str { &self.name }
    pub fn version(&self) -> &str { &self.version }

    pub fn drive(&self, ctx: &Context) -> Result<f64> {
        let mut g = self.inner.lock().expect("driver mutex poisoned");
        Ok(g.bindings.call_drive(&mut g.store, ctx)?)
    }
}
```

Key decisions worth noting:

- **`Mutex<Inner>` (not `RwLock`).** Every call mutates the store (linear memory
  is touched on the canonical ABI lower/lift). No reader-writer split exists.
- **Cache metadata at load time.** `name()`, `version()`, `features()` etc.
  are called once and stored on the outer struct. Don't pay a lock + ABI
  cross every time someone reads the driver's name.
- **Leaked `&'static str` for stable string IDs.** If `feature_names()` should
  return `&[&'static str]`, load once and `Box::leak` the strings. For a
  small fixed set this is acceptable; lifetimes stay clean.
- **`Arc<WasmDriver>` for shared ownership.** The outer type is `Send + Sync`
  if `HostState: Send`. Wrap in `Arc` for use across tasks / threads.
- **Lists copy across the boundary.** A WIT `list<f64>` is copied on every
  call. For high-throughput inference, batch.
- **`parking_lot::Mutex` for hot paths.** Avoids std's poisoning and is
  slightly faster. The mutex is held for the entire WASM call, so contention
  is the throughput bottleneck — see §6 (hot-swap) for a copy-on-swap pattern
  that avoids serializing reads behind writes.

---

## 5. Error Handling

Two categories of failure.

**`wasmtime::Error`** — re-export of `anyhow::Error`. Returned from
`Component::from_file`, `Linker::*`, `*::instantiate*`, and every `call_*`
method. Use `.context(...)` for adding host-side context; use `downcast_ref`
to inspect the inner cause.

**`wasmtime::Trap`** — an enum of WASM-level traps (memory OOB, integer
divide-by-zero, `unreachable`, stack overflow, etc.). When a guest traps,
`call_*` returns `Err(wasmtime::Error)` whose **root cause** downcasts to
`Trap`. The store is now poisoned: **do not reuse it.** Re-instantiate from
the cached `Component`.

```rust
match self.drive(ctx) {
    Ok(score) => score,
    Err(e) => {
        if let Some(trap) = e.downcast_ref::<wasmtime::Trap>() {
            tracing::error!(?trap, "WASM driver trapped — store poisoned");
            // optional: re-instantiate from cached Component
        } else {
            tracing::error!(error = ?e, "WASM driver error (non-trap)");
        }
        0.0    // neutral default for compute drivers; surface for control flow
    }
}
```

Common control-flow pattern for compute drivers: on **any** call error,
return a neutral default (`0.0`, empty vec, `None`) so the host loop keeps
running rather than aborting. Reserve `?` propagation for setup-time errors
(`load`, `from_file`, `instantiate`) where failure is fatal.

For richer trap diagnostics, downcast to `wasmtime::WasmBacktrace` from the
same error to recover the guest call stack at trap time. Backtraces require
no special config — they are captured automatically when a trap occurs.

---

## 6. Hot-Swap Patterns

Swapping a loaded component for a new `.wasm` without restarting the host.
Two flavors.

### Lock-and-replace (simple, brief stall)

```rust
pub fn swap(&self, engine: &Engine, new_path: &str) -> Result<()> {
    let component = Component::from_file(engine, new_path)?;       // expensive (off-lock)
    let mut linker = Linker::<HostState>::new(engine);
    wasmtime_wasi::p2::add_to_linker_sync(&mut linker)?;

    let state = HostState { wasi: WasiCtx::builder().build(), table: ResourceTable::new() };
    let mut new_store = Store::new(engine, state);
    let new_bindings = MyWorld::instantiate(&mut new_store, &component, &linker)?;

    // Replace inner under the lock — fast.
    let mut g = self.inner.lock().expect("poison");
    *g = Inner { store: new_store, bindings: new_bindings };
    Ok(())
}
```

The expensive work (compilation, instantiation) happens outside the lock.
Only the pointer-swap is serialized.

### Copy-on-swap via `ArcSwap` (zero-contention reads)

For hot paths where readers must not block on writers, wrap the inner in
`arc_swap::ArcSwap<Mutex<Inner>>` (or use `arc_swap::ArcSwapAny`) and
publish a new `Arc<Mutex<Inner>>` on swap. Readers take the current `Arc`
in a single atomic load, then lock the per-instance mutex. Old instances
drop when the last reader releases the Arc.

**No guest state survives a swap** — the new `.wasm` starts with fresh
linear memory. If state must persist across swaps, serialize it through the
host (e.g. the old guest's last `serialize_state()` export → bytes → new
guest's `restore_state()`).

---

## 7. AOT — Precompilation & Caching

JIT compilation on first load is fast but not free. For deployment, precompile
ahead of time.

```rust
// At build / deploy time:
let bytes = component.serialize()?;
std::fs::write("driver.cwasm", bytes)?;

// At runtime, much faster:
// SAFETY: bytes must come from Component::serialize or Engine::precompile_component
//         on a wasmtime version + Config compatible with this Engine.
let component = unsafe { Component::deserialize(&engine, std::fs::read("driver.cwasm")?)? };
```

`Component::deserialize` is **unsafe** because the bytes are trusted to be a
valid precompiled artifact for this engine + config. Mismatched engines, OS,
or wasmtime versions will UB. The contract: deserialize bytes that **you**
produced from **the same engine config and wasmtime version** on the same
target triple.

For host-managed caching (compile once on first run, reuse compiled artifact
on subsequent runs), use `Config::cache_config_load_default()` — wasmtime
hashes the input bytes + config and caches compiled output under
`~/.cache/wasmtime` automatically. No deserialize-unsafe surface; the cache
trusts only its own writes.

For zero-trust deployment of precompiled artifacts, sign the bytes with the
host's keypair and verify at load time before calling `deserialize`.

---

## 8. Async Support

For hosts built on tokio/async-std, enable async at the engine level:

```rust
let mut config = Config::new();
config.async_support(true);
let engine = Engine::new(&config)?;
```

This switches the type-level surface: `instantiate_async`, `call_async`
become available; the sync variants of `*_async`-only operations become
unavailable on the same engine. **The engine is statically sync-or-async** —
you cannot mix on the same `Config`.

Pair with the async WASI linker:

```rust
wasmtime_wasi::p2::add_to_linker_async(&mut linker)?;

let bindings = MyWorld::instantiate_async(&mut store, &component, &linker).await?;
let result   = bindings.call_drive_async(&mut store, ctx).await?;
```

For async-generated bindings, pass `async: true` to `bindgen!`:

```rust
wasmtime::component::bindgen!({
    path: "./wit",
    world: "drivers",
    async: true,
});
```

Stores under async support are not `Send` by default (host data may not be).
For multi-threaded async runtimes, ensure `T: Send` on `Store<T>`.

---

## 9. Debug Surfaces

Wasmtime gives the host several diagnostic levers:

**Core dumps on trap.** Set `config.coredump_on_trap(true)` to attach a
`WasmCoreDump` to any trap error. Downcast and serialize for post-mortem
inspection:

```rust
if let Err(e) = bindings.call_drive(&mut store, ctx) {
    if let Some(dump) = e.downcast_ref::<wasmtime::WasmCoreDump>() {
        let bytes = dump.serialize(&mut store, "driver.wasm");
        std::fs::write("crash.coredump", bytes)?;
    }
}
```

**Backtraces.** `WasmBacktrace` attaches automatically on trap; downcast from
the error to read frame names + offsets.

**DWARF.** Compile the guest with `-C debuginfo=2` (or via `cargo component
build` with `[profile.*.debug = true]`) and enable
`config.debug_info(true)` on the host to expose source-level debugging.

**Profiling.** `config.profiler(ProfilingStrategy::JitDump)` (Linux) or
`PerfMap` produce profiler-readable maps for `perf`. `VTune` is the
intel-flavored variant.

**Fuel metering.** `config.consume_fuel(true)` plus `store.set_fuel(n)`
caps total instructions per call — useful for untrusted-component
deployments where you must bound CPU.

**Epoch interruption.** `config.epoch_interruption(true)` + a background
thread bumping `engine.increment_epoch()` lets the host preempt long-running
guest calls without consuming fuel on every instruction.

**`wasmtime explore`.** CLI command rendering a `.wasm` as a clickable
HTML cross-reference of WAT ↔ Cranelift IR ↔ machine code. Indispensable
for diagnosing codegen pathologies.

---

## 10. Performance Considerations

**Component caching.** Keep one `Component` shared across all instances of
the same `.wasm`. Compilation runs once; instantiation is cheap.

**Engine sharing.** One `Engine` per process is the right default. Two
engines means two compilers running side-by-side for no win.

**Store reuse.** Creating a `Store` is cheap relative to component compilation,
but creating one per call is still wasteful. A typical driver creates one
`Store` per loaded component and holds it for the driver's lifetime.

**Boundary cost.** Crossing the WASM/host boundary copies list data. For
periodic / coarse-grained calls this is negligible. For nanosecond-latency
hot paths, redesign the interface: use resource handles for large state,
batch calls for high frequency, or reconsider whether WASM is the right
boundary at all (in-process traits may fit better).

**Cranelift opt level.** `OptLevel::Speed` is the default. `OptLevel::None`
shortens compile time at runtime cost — useful for dev loops, not for
production.

**AOT precompile.** §7. The lowest steady-state startup latency.

---

## 11. Security Model

Wasmtime implements capability-based security. A component has **no ambient
authority**:

- Cannot read files unless a preopen is explicitly granted.
- Cannot make network connections unless a socket factory is provided.
- Cannot access environment variables unless listed in `WasiCtx` builder.
- Cannot read clocks unless `wasi:clocks` is wired.
- Cannot read host memory — the component model ABI copies data at the
  boundary.

A misbehaving component can only affect what the host explicitly granted.
For pure-compute drivers, the grant is zero: no capabilities. Even a
malicious `.wasm` cannot access the host's internal state, the filesystem,
or the network. Combine with fuel metering (§9) and an epoch interrupt
budget for time-bound execution.

---

## Cross-Skill References

- **`webassembly`** (sibling) — language-agnostic. WIT syntax (`wit.md`),
  component model semantics (`wasm-components.md`), WASI preview1 vs
  preview2 (`wasi.md`), raw WASM (`wasm.md`). Reach there for "what does
  this WIT contract MEAN" or "what is a component, conceptually."
- **`rust`** (sibling) — Rust idioms, `cargo.md`, `rustc.md`. Reach there
  for ownership / lifetime / async questions that surface in host code,
  and for building the host binary itself (target triples, features,
  workspace layout). Rust-side **guest** toolchain (`cargo-component`,
  `wit-bindgen` macro for guests) is documented at the corresponding
  docs.rs pages — not in this skill (this skill is host-side).
- **`code-style`** (sibling) — personal-preference layer (MSRV floor,
  module convention). Apply when writing code the user will read.

## Canonical Docs (open these before answering)

- <https://docs.wasmtime.dev/> — user docs, tutorials, design.
- <https://docs.rs/wasmtime/latest/wasmtime/> — Rust API per-version.
- <https://docs.rs/wasmtime-wasi/latest/wasmtime_wasi/> — WASI host integration.
- <https://docs.rs/wasmtime/latest/wasmtime/component/macro.bindgen.html> — `bindgen!` reference.
- <https://github.com/bytecodealliance/wasmtime/tree/main/examples> — runnable host examples.

Use Context7 (`/bytecodealliance/wasmtime` or `/websites/rs_wasmtime`) to
fetch current API snippets before answering any version-specific question.
