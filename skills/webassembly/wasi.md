# WASI — WebAssembly System Interface

## What WASI Solves

A plain WASM module is computation-only. It can do arithmetic, manipulate its linear memory, and call imported host functions — nothing else. No clocks, no filesystem, no random numbers, no environment variables.

WASI defines a standard set of host imports for operating-system-like capabilities. Instead of every host inventing its own "give the guest access to a file" convention, WASI is the convention. A module compiled against WASI can run on any WASI-compliant host without modification.

The critical design constraint: WASI is opt-in and capability-based. The host decides which capabilities to grant, not the guest. A module can declare it needs `wasi:filesystem/types` but it only gets filesystem access if the host linker provides it with a pre-opened directory. Declaring an import does not grant it.

## preview1 vs preview2 — the Critical Distinction

WASI has gone through two major versions with fundamentally different designs. Getting this wrong breaks toolchains.

### WASI preview1 (legacy)

- Introduced 2019, standardized ~2020
- Designed before the component model existed
- Interface: a flat set of C-style syscall functions exported as imports to the module (`fd_read`, `path_open`, `clock_time_get`, etc.)
- No WIT — the interface is described in a `witx` format (a precursor), not in WIT
- Types at the boundary are raw i32/i64 — handles, pointers into linear memory, errno codes
- Target: `wasm32-wasi` (in Rust toolchains)
- Status: Frozen. No new capabilities will be added. Many runtimes still support it for compatibility.

Signature style in preview1:
```
// Host import expected by a preview1 module:
// (import "wasi_snapshot_preview1" "fd_write" (func ...))
```

### WASI preview2 / 0.2 (current stable)

- Introduced 2023, stabilized 2024
- Built entirely on the component model and WIT
- Interface: a set of WIT interfaces and worlds (`wasi:io`, `wasi:filesystem`, `wasi:clocks`, `wasi:random`, `wasi:sockets`, `wasi:cli`, `wasi:http`)
- Types are WIT types: `result<T, E>`, `option<T>`, `record`, `resource` handles (`own<T>`/`borrow<T>`) — not raw integers
- The module must itself be a **component** (see `wasm-components.md`) to use preview2
- Target: `wasm32-wasip2` (Tier 2 in Rust; stabilized in Rust 1.82)
- Status: Stable. WASI 0.2 is the current release.

The seven core APIs of WASI 0.2, all currently at Phase 3:

| Package | What it provides |
|---------|-----------------|
| `wasi:io/streams` | Byte streams (read/write) |
| `wasi:io/poll` | Pollable readiness |
| `wasi:filesystem/types` | Files, directories, metadata |
| `wasi:filesystem/preopens` | Pre-opened directory handles |
| `wasi:clocks/wall-clock` | Wall clock time |
| `wasi:clocks/monotonic-clock` | Monotonic timestamps, timers |
| `wasi:random/random` | CSPRNG |
| `wasi:random/insecure` | Non-cryptographic random |
| `wasi:sockets/tcp` | TCP sockets |
| `wasi:sockets/udp` | UDP datagrams |
| `wasi:sockets/ip-name-lookup` | DNS resolution |
| `wasi:cli/environment` | Environment variables |
| `wasi:cli/exit` | Process exit |
| `wasi:cli/stdin`/`stdout`/`stderr` | Standard streams |
| `wasi:http/types`, `wasi:http/outgoing-handler`, `wasi:http/incoming-handler` | HTTP client + server (proxy world) |

Other proposals are still working through earlier phases (Phase 2: `wasi:nn`, clocks timezone, gfx; Phase 1: `wasi:crypto`, `wasi:logging`, `wasi:keyvalue`, `wasi:sql`, `wasi:url`, etc.). Check `https://wasi.dev/interfaces` for the current phase table before depending on anything outside the 0.2 core.

### WASI preview3 / 0.3 (in development)

- Iterates on the same 0.2 core APIs (draft versions live in their respective repos)
- Headline addition: native **async** support via `future<T>` / `stream<T>` at the WIT level — operations that block today become first-class futures
- Target: `wasm32-wasip3` (Tier 3 in Rust)
- Status: Drafts; do not depend on the surface stabilizing yet. Production code should still target `wasm32-wasip2` and WASI 0.2.

## Rust WASM Targets — the Current Map

| Target | Tier | What it produces | Use for |
|---|---|---|---|
| `wasm32-unknown-unknown` | 2 | Raw module, no WASI | Browser interop via `wasm-bindgen` |
| `wasm32-wasip1` | 2 | Raw module, preview1 WASI imports | Legacy WASI, adapter-bridged components |
| `wasm32-wasip2` | 2 | **Component**, preview2 WASI | Server-side component model — the default |
| `wasm32-wasip3` | 3 | **Component**, preview3 WASI (async) | Experimental — WASI 0.3 drafts |

The original `wasm32-wasi` target was **renamed** to `wasm32-wasip1`; the old name is deprecated. `wasm32-wasip2` produces a **component**, not a raw module — its binary has component magic, and a component-model-aware runtime (e.g. wasmtime) loads it via the component API.

To add the target and build:
```
rustup target add wasm32-wasip2
cargo build --target wasm32-wasip2 -p my-component
```

The output `target/wasm32-wasip2/debug/my_component.wasm` carries the component binary magic (`\0asm\x0a...` with component sections) rather than the raw module magic. Inspect with `wasm-tools component wit` to confirm.

For browser/JS interop, target `wasm32-unknown-unknown` and use `wasm-bindgen` — that path produces raw modules, not components, and is mutually exclusive with `cargo-component`.

## Capability Model in Practice

The host grants capabilities by adding them to the `Linker` before instantiating a component. With wasmtime:

```rust
// Example: add all WASI preview2 capabilities
use wasmtime_wasi::WasiCtxBuilder;

let wasi = WasiCtxBuilder::new()
    .inherit_stdio()           // pass through host stdout/stderr
    .inherit_env()             // pass all env vars (use sparingly)
    .preopened_dir(dir, ".")   // grant access to one specific directory
    .build();
```

Each added capability is explicit. A component that imports `wasi:clocks/monotonic-clock` but runs under a linker that doesn't provide it will fail at instantiation with a link error, not at runtime.

**Minimum-grant principle:** add only the capabilities the component's WIT explicitly imports. Pure-computation components (no filesystem, no network, no clocks) need no WASI capabilities at all. Adding unnecessary capabilities widens the attack surface without benefit.

## Common Pitfalls

**Expecting full POSIX.** WASI is not POSIX. There is no `fork`, no signals, no process model, no ioctl, no mmap with arbitrary permissions. Code that uses POSIX abstractions directly (e.g., openssl's entropy gathering, certain libc calls) may fail to compile or trap at runtime.

**Confusing preview1 and preview2.** A preview1 module is NOT a component. Running a preview1 module through the component model linker will fail — the binary format is different. Use `wasm-tools component wit some.wasm` to inspect which WASI version a component declares.

**Not providing required WASI imports.** If a Rust crate (or one of its transitive dependencies) imports any WASI symbol, the host linker must provide it. The `std` library on `wasm32-wasip2` uses `wasi:clocks` for `std::time::Instant`. If the driver uses `std::time`, add `wasi:clocks` to the linker.

**Preopened directories and paths.** WASI filesystem access is restricted to preopened directory handles. Absolute paths are not available inside the guest unless the host preopens root (`/`), which is equivalent to no sandboxing. Always preopened specific subdirectories.

**Environment variable leakage.** `inherit_env()` passes all host environment variables — including secrets — to the guest. Use `.env("KEY", "value")` to pass only what is needed.

## Preview1 → Preview2 Adapter

Existing preview1 modules can run under a preview2 host via an adapter. The Bytecode Alliance maintains a `wasi_snapshot_preview1.wasm` adapter that wraps a preview1 module into a component, translating preview1 syscalls to preview2 interfaces.

The adapter is used by tools like `cargo-component` automatically. For manual use:
```
wasm-tools component new my-module.wasm \
  --adapt wasi_snapshot_preview1=wasi_snapshot_preview1.wasm \
  -o my-component.wasm
```

This is a migration path, not a permanent solution. New code should target `wasm32-wasip2` directly.
