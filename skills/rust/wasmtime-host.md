# wasmtime Host Embedding

Embedding `wasmtime` in a Rust application lets the host load and invoke WASM components at runtime. This is the standard mechanism for any Rust host that wants to run hot-swappable WASM components.

---

## Dependencies

```toml
[dependencies]
wasmtime       = "28"
wasmtime-wasi  = "28"   # only needed if the component uses WASI interfaces
```

For components that are pure compute (no WASI), `wasmtime-wasi` is optional. A pure-compute driver omits it when the component has no filesystem or network imports.

Pin the wasmtime version in the workspace `Cargo.toml`. A minor version bump can change the component model ABI and silently break loading of `.wasm` files compiled against a different version.

---

## Core Types

Four types form the wasmtime embedding stack:

**`Engine`** — global configuration and compilation settings. Create once per process. Expensive to create; cheap to clone (it's behind an `Arc` internally).

**`Store<T>`** — per-instance execution context. Holds all instance state, including memory and table data. `T` is your host-state type (can be `()` for stateless hosts). Every call into the component requires a `&mut Store<T>`.

**`Component`** — the parsed and compiled WASM component binary. Can be created once and instantiated multiple times across multiple `Store`s. Cloning is cheap.

**`Linker<T>`** — the set of host functions and WASI interfaces the component can import. Built once per `Engine`; shared across instantiations.

---

## The Loading Flow

### 1. Create the engine

```rust
use wasmtime::{Config, Engine};

let engine = Engine::new(&Config::new())?;
```

For AOT compilation and performance, configure caching:

```rust
let mut config = Config::new();
config.cache_config_load_default()?;  // uses ~/.cache/wasmtime by default
let engine = Engine::new(&config)?;
```

### 2. Parse the component

```rust
use wasmtime::component::Component;

let component = Component::from_file(&engine, "/path/to/driver.wasm")?;
```

`from_file` reads, parses, and JIT-compiles the component. This is the expensive step. Cache the `Component` and reuse it across instantiations.

### 3. Build the linker

```rust
use wasmtime::component::Linker;

let linker: Linker<StoreData> = Linker::new(&engine);
```

For components that import WASI interfaces, add them:

```rust
wasmtime_wasi::add_to_linker_sync(&mut linker)?;
```

For pure-compute components (no WASI), leave the linker empty.

### 4. Generate host bindings

Use the `bindgen!` macro from `wasmtime::component` to generate the host-side client structs:

```rust
mod wit {
    wasmtime::component::bindgen!({
        path: "./wit",
        world: "drivers",
    });
}
```

This generates a `wit::Drivers` struct (named after the world) with `instantiate` and `call_*` methods.

### 5. Instantiate

```rust
let mut store = Store::new(&engine, StoreData);

let bindings = wit::Drivers::instantiate(&mut store, &component, &linker)?;
```

This wires the component's imports to the linker's exports and prepares the instance for calls.

### 6. Call exported functions

```rust
let name = bindings.call_name(&mut store)?;
let signal = bindings.call_drive(&mut store, &context)?;
```

The generated method names follow `call_<wit_function_name>` in snake_case. The first argument is always `&mut store`.

---

## Complete Minimal Example

```rust
use wasmtime::component::{Component, Linker};
use wasmtime::{Config, Engine, Store};

mod wit {
    wasmtime::component::bindgen!({
        path: "wit",
        world: "my-world",
    });
}

struct HostState;

fn run_component(wasm_path: &str, input: f64) -> anyhow::Result<f64> {
    let engine   = Engine::new(&Config::new())?;
    let component = Component::from_file(&engine, wasm_path)?;
    let linker   = Linker::<HostState>::new(&engine);
    let mut store = Store::new(&engine, HostState);

    let bindings = wit::MyWorld::instantiate(&mut store, &component, &linker)?;
    let result   = bindings.call_compute(&mut store, input)?;
    Ok(result)
}
```

---

## WASI Capability Delegation

For components that use WASI (filesystem, env, stdio), build a `WasiCtx` and store it in the host state:

```rust
use wasmtime_wasi::{WasiCtx, WasiCtxBuilder, WasiView};

struct HostState {
    wasi: WasiCtx,
    table: wasmtime::component::ResourceTable,
}

impl WasiView for HostState {
    fn table(&mut self) -> &mut wasmtime::component::ResourceTable { &mut self.table }
    fn ctx(&mut self) -> &mut WasiCtx { &mut self.wasi }
}

// Build with explicit grants — capability-based, default is nothing
let wasi = WasiCtxBuilder::new()
    .inherit_stdio()
    .env("LOG_LEVEL", "info")
    .preopened_dir("/data", "/data", wasmtime_wasi::DirPerms::READ, wasmtime_wasi::FilePerms::READ)?
    .build();

let state = HostState { wasi, table: Default::default() };
let mut store = Store::new(&engine, state);

// Wire WASI into the linker
wasmtime_wasi::add_to_linker_sync(&mut linker)?;
```

The component gets only the capabilities explicitly granted via `WasiCtxBuilder`. No ambient filesystem access. No environment variables unless listed.

---

## Production Pattern: a Generic `WasmDriver` Wrapper

A typical Rust host-side driver wraps `wasmtime` runtime state and exposes a `&self`-receiver method that internal code can call without holding `&mut`. Key decisions worth noting:

**`Mutex<Inner>` for `&self` ergonomics.** Calling into the component requires `&mut Store`. The driver's public method usually takes `&self` (so it can be called from many places). Wrapping the store + bindings in a `Mutex` makes the driver `Sync` while satisfying both constraints.

**Metadata read at load time.** `name()`, `version()`, `features()` and the like are called once during `from_file`, not on every invocation. The results are cached in the struct.

**Leaked `&'static str` for stable string IDs.** Methods like `feature_names()` can return `&[&'static str]` to avoid lifetime complexity. The names are loaded once at startup and live for the process lifetime, so leaking is acceptable for a small fixed set.

**Lists are copied across the boundary.** A WIT `list<f64>` is copied when the host calls the guest. For high-throughput inference, batch calls or reduce boundary-crossing frequency.

**No WASI, empty linker — for pure-compute components.** When the components have no imports beyond their declared interface, use an empty linker. Add WASI capabilities only when the WIT explicitly imports them.

---

## Error Handling

Two error categories:

**`wasmtime::Error`** — wraps `anyhow::Error`. Returned from `Component::from_file`, `instantiate`, and all `call_*` methods. Check the inner error for diagnostics.

**Traps** — when the WASM guest panics or hits an `unreachable`. Manifests as a `wasmtime::Error` with a trap description. The `Store` is poisoned after a trap — do not attempt to reuse it. Re-instantiate the component from the cached `Component`.

```rust
match bindings.call_drive(&mut store, features) {
    Ok(score)  => score,
    Err(e) if e.downcast_ref::<wasmtime::Trap>().is_some() => {
        // Component trapped — store is poisoned, log and return neutral
        tracing::error!("WASM driver trapped: {e}");
        0.0
    }
    Err(e) => return Err(e.into()),
}
```

A common pattern for compute drivers: return a neutral default (e.g. `0.0`) on any call error so the host loop keeps running rather than aborting.

---

## Performance Considerations

**AOT compilation.** Precompile components at startup rather than JIT-compiling per call:

```rust
let engine = Engine::new(Config::new().cranelift_opt_level(wasmtime::OptLevel::Speed))?;
// Component::from_file already JIT-compiles on load.
// For AOT ahead of deployment:
let bytes = component.serialize()?;                    // serialize compiled artifact
// later:
let component = Component::deserialize(&engine, &bytes)?;  // skip recompilation
```

**Component caching.** Keep the `Component` in a shared `Arc` and clone it per `Store`. Parsing and compilation happen once; instantiation is fast.

**Minimize store creation.** Creating a `Store` is cheap relative to component parsing, but creating one per inference call is wasteful. For hot paths, reuse the `Store` across multiple calls. A typical driver creates one `Store` per loaded component and holds it for the lifetime of the driver.

**Boundary cost.** Crossing the WASM/host boundary copies list data. For periodic / coarse-grained call patterns this is negligible. For nanosecond-latency scenarios, redesign the interface to minimize list transfers (e.g. resource handles for large state, batched calls for high frequency).

---

## Security Model

wasmtime implements capability-based security. A component has no ambient authority:
- Cannot read files unless a preopen is explicitly granted.
- Cannot make network connections unless a socket factory is provided.
- Cannot access environment variables unless listed in `WasiCtxBuilder::env`.
- Cannot read host memory — the component model ABI copies data at the boundary.

A misbehaving component can only affect what the host explicitly granted. For pure-compute drivers, the grant is zero: no capabilities. Even a malicious `.wasm` cannot access the host's internal state, the filesystem, or the network.
