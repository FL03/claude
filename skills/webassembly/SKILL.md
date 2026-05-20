---
name: WebAssembly
description: This skill should be used when the user asks about "wasm", "WebAssembly", "wasi", "wasm components", "wit", "component model", "wasm32-wasip2", or when working with .wasm/.wat/.wit files, cargo-component, wasmtime, wit-bindgen, wasm-tools, wac, or any WebAssembly runtime, toolchain, or interface question. Language-agnostic WebAssembly guidance — Rust-specific toolchain topics (cargo-component usage, wit-bindgen codegen, wasm-bindgen) belong in the rust skill.
---

# WebAssembly

## Overview

WebAssembly (WASM) is a binary instruction format for a stack-based virtual machine. It is a compilation target — not a language — designed for near-native execution with strong sandboxing guarantees. A WASM module cannot access the host filesystem, network, or system calls unless the host explicitly grants those capabilities.

Three properties make WASM useful at runtime boundaries:

1. **Isolation** — a misbehaving guest traps the component, not the host process.
2. **Portability** — the same `.wasm` runs on any host with a compatible runtime, regardless of OS or architecture.
3. **Hot-swap** — a new `.wasm` can replace a running one by re-instantiating the component in a fresh store.

This skill is **language-agnostic**. WIT syntax, component model semantics, WASI capabilities, and the binary format live here. **Rust-side integration** (target choice, `cargo-component`, `wit-bindgen` macro, `wasmtime` host embedding, dual native+wasm32 build) lives in the `rust` sibling skill (`wasm.md`, `wasmtime-host.md`).

## The Four Pillars

### 1. Core WASM (`wasm.md`)

The binary format itself: stack machine execution, linear memory, modules, traps, runtime landscape (wasmtime/wasmer/wasmi/v8). Read this for a grounding in what a `.wasm` file actually is and how runtimes execute it.

### 2. WASI (`wasi.md`)

WebAssembly System Interface — how a sandboxed module talks to the host OS. Critical distinction: **preview1** (legacy) vs **preview2** (component-model-based). The `wasm32-wasip2` target produces preview2 components. Read this before touching any capability grants or host linker setup.

### 3. Component Model (`wasm-components.md`)

The layer above raw modules. A component wraps a module and annotates its imports and exports with WIT types (strings, records, variants, results) instead of raw i32/i64. Composition — wiring one component's exports to another's imports — happens here. Read this before designing any component interface or using `wasm-tools`/`wac`.

### 4. WIT (`wit.md`)

WebAssembly Interface Type language — the IDL for the component model. Defines worlds, interfaces, types. Most importantly: **directionality**. Every WIT file is either describing existing code (Direction 1) or enforcing a contract on yet-to-be-written code (Direction 2); confusing the two breaks the architectural invariant. Read this before writing or modifying any `.wit` file.

## When to Reach for WASM

Use WASM when the code satisfies at least one of:

- It is a computational unit that should be hot-swappable without restarting the host process.
- It must run as an isolated guest with no direct memory access to the host.
- Multiple language implementations need to satisfy the same interface contract (a WIT world).
- The artifact needs to be distributed and loaded by a runtime that may not share the host's architecture.

Do NOT use WASM when:

- The code runs entirely in-process and the boundary is a host-language trait. Use traits for in-process polymorphism; WIT for cross-runtime boundaries.
- The performance budget cannot absorb the serialization cost of crossing the component boundary on every call. For hot-path inner loops, keep the computation in the host.
- The module needs unrestricted filesystem or network access. WASI capabilities cover common cases, but full POSIX is not available.

## Common Gotchas

**Traps are unrecoverable.** When a WASM guest traps (out-of-bounds memory access, integer divide by zero, explicit `unreachable`), the store is poisoned. Re-instantiate the component from the same bytecode — do not attempt to resume the same store.

**Linear memory is flat and bounded.** There is no garbage collector in core WASM. Strings and lists passed across the component boundary are copied, not shared. For high-frequency calls, batch data or reduce crossing frequency.

**Clock and random are not free.** WASM has no built-in access to the system clock or a CSPRNG. The host must explicitly wire in the WASI `wasi:clocks` and `wasi:random` interfaces. A component compiled expecting these and running under a linker that doesn't provide them will trap at instantiation time, not at the first call.

**`wasm32-wasip2` is not `wasm32-unknown-unknown`.** The `wasip2` target produces a component, not a raw module. Tooling that expects a flat `.wasm` module (`wasm-bindgen`, some older toolchains) may not handle it correctly. The `wasm32-unknown-unknown` target is for browser/bindgen scenarios; `wasm32-wasip2` is for server-side component model scenarios. Mixing them is the most common source of "why won't this load?" errors.

**WIT types are not host-language types.** Strings in WIT are UTF-8, length-prefixed, and copied at the boundary. A guest's `&str` is not the same pointer as the host sees. `record` fields are laid out by the component model ABI, not by the host language's repr rules. Never assume memory layout compatibility across the boundary.

**Imports must all be satisfied.** A component that declares any import — function, type, or WASI interface — must have every import linked before instantiation. Missing imports cause a link error at instantiation time, not at the call site.

## Typical Architecture

WASM lives at exactly one boundary in most systems: between a host process (compiled native) and a hot-swappable guest (compiled to `.wasm`). Every other boundary is in-process polymorphism using the host language's native facilities (Rust traits, Python protocols, etc.).

```
host process (native)
    │
    │  driver.invoke(ctx) -> result
    │  [component boundary — WIT types cross here]
    ▼
my-component.wasm (guest, WASM component)
    ├── implements: <namespace>:<package>/<world>
    ├── imports:    <namespace>:<package>/<types>
    └── pure computation; no I/O; no shared memory
```

The WIT contract that governs this boundary typically lives next to whichever side **owns** the contract:

- **Host-owns-contract** (Direction 2): the host defines what guests must export. WIT lives with the host. Multiple guest implementations satisfy the same world.
- **Guest-owns-API** (Direction 1): the guest exposes its existing API. WIT mirrors the guest's types/functions. The host imports the WIT to consume.

For the full direction model and decision tree, see `wit.md`.

## Hot-swap Mechanics

The host typically holds a mutex around runtime state containing the `Store` and bindings. On each guest call:

1. Lock the mutex.
2. Lower the input into the component's linear memory via the canonical ABI.
3. Call the exported function.
4. Lift the returned value back into host types.
5. Unlock.

Hot-swap is a re-instantiation: compile the new `.wasm` bytes into a `Component`, create a new `Store`, instantiate new bindings, replace the runtime-state contents. The old store and bindings are dropped. **No state survives a swap** — guests are stateless across instantiations unless the host explicitly persists state.

Rust-side embedding details (Engine/Store/Linker/Component, `bindgen!` macro, WASI capability grants, `Mutex`-wrapped state) live in the `rust` skill's `wasmtime-host.md`.

## WIT Directionality Quick Reference

This concept is covered fully in `wit.md`. The one-line summary:

- **Direction 1 (describe):** code exists first. WIT mirrors it. Change code first, then update WIT.
- **Direction 2 (enforce):** WIT exists first. Code must satisfy it. Change WIT first, then update code.

Before writing or modifying any `.wit` file, identify which direction it is. If ambiguous, add a comment to the file declaring the direction. Bulk-generating Direction 2 files breaks the architectural contract.

| WIT file role | Direction |
|---|---|
| Shared-types package mirroring existing host types | 1 |
| World defining what plugin/guest components must export | 2 |
| Component-side `world.wit` consuming an upstream contract | 2 (component is the implementer) |

## Inspection Workflow

Before modifying any `.wasm` or `.wit` file, inspect it first:

```bash
# Is the built artifact a component or a raw module?
wasm-tools validate --features component-model path/to/my_component.wasm

# What WIT interface does the compiled component declare?
wasm-tools component wit path/to/my_component.wasm

# Disassemble to text format for reading
wasm-tools print path/to/my_component.wasm | head -100

# Validate a WIT package directory
wasm-tools component wit path/to/wit/
```

For runtime errors:

- **Link error at instantiation** — a required import is missing from the linker. Check the WIT `import` declarations vs what the linker provides.
- **Trap on first call** — the component is instantiated but a runtime operation failed (memory bounds, divide by zero, explicit `unreachable`). The store is now poisoned.
- **Type mismatch** — the component's exported function signature does not match the bindgen-generated bindings. Rebuild after any WIT change.

The most common source of silent failures: changing a WIT file without recompiling the component that implements it. The host bindgen re-runs at build time, but the `.wasm` binary must also be rebuilt against the updated WIT. If the WIT and the component binary diverge, the link error surfaces at runtime instantiation.

## Reference Files

Four flat reference files live alongside this skill:

- **`wasm.md`** — Stack machine, linear memory, module structure, text/binary format, traps, runtime landscape, security model.
- **`wasi.md`** — WASI capabilities, preview1 vs preview2 distinction, `wasm32-wasip2` target, capability model, adapters.
- **`wasm-components.md`** — Component vs module, composition, interface types vs core types, resources, `wasm-tools`, `wac`.
- **`wit.md`** — WIT syntax reference, worlds, interfaces, types, **directionality** (the most important concept), placement rules, anti-patterns.

Read the pillar file that matches the question before answering. For WIT questions, `wit.md` is authoritative. For capability/sandbox questions, `wasi.md`. For composition questions, `wasm-components.md`.

## Cross-references to other skills

- **`rust`** (sibling skill) — Rust-side integration: `wasm.md` (target choice, cargo-component, wit-bindgen guest pattern), `wasmtime-host.md` (host embedding recipe). Reach there for any "how do I make this compile/build/link in Rust?" question.
- **`code-style`** (sibling skill) — personal-preference layer for whichever host language is involved. Project-specific component layouts (which directory holds the `.wasm` builds, naming conventions, dependency rules) live in the project's own docs, not here.
