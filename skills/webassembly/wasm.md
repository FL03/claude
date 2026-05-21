# WebAssembly Core — Binary Format and Execution Model

## What WASM Actually Is

WebAssembly is a binary instruction format targeting a portable, sandboxed stack machine. The key word is *binary*: `.wasm` files are not text, not bytecode for a specific OS, and not tied to any language runtime. They are a structured binary encoding of a deterministic computation.

The text format (`.wat`) is a human-readable 1:1 representation of the same structure — every `.wasm` file has an exact `.wat` equivalent. The binary format is what runtimes load; the text format is for inspection and hand-authoring.

WASM is not:
- A language (Rust, C, Go, etc. all compile to it)
- An OS or process model (that is WASI's job)
- A garbage-collected runtime (no GC in core WASM — there is a GC proposal but it is not yet universal)
- A replacement for the component model (components wrap modules — see `wasm-components.md`)

## Stack Machine Execution Model

The WASM virtual machine is a push-down stack machine. Every instruction either pushes values onto the stack or pops them off. There are no general-purpose registers.

```wat
;; Text format example: add two i32 values
(func $add (param i32) (param i32) (result i32)
  local.get 0  ;; push param 0
  local.get 1  ;; push param 1
  i32.add      ;; pop 2 values, push their sum
)
```

Execution is deterministic and validates structurally at load time — the runtime checks that every instruction sequence is type-safe before running a single instruction. This is why WASM runtimes can compile to native code (JIT or AOT) without runtime type checks.

## Value Types

Core WASM has exactly four numeric types:
- `i32` — 32-bit integer (also used for booleans, pointers)
- `i64` — 64-bit integer
- `f32` — 32-bit IEEE 754 float
- `f64` — 64-bit IEEE 754 float

There are also `v128` (SIMD proposal) and reference types (`funcref`, `externref`) in extended proposals, but the core four are what every runtime supports.

Note: "integer" in WASM is sign-agnostic. The same bits can be treated as signed or unsigned; the instruction suffix (`i32.div_s` vs `i32.div_u`) determines interpretation.

## Module Structure

A WASM module is a binary container with a defined sequence of sections. Sections appear in a fixed order (by index) and each has a specific purpose:

| Section | Purpose |
|---------|---------|
| Type | Function type signatures (parameter/result lists) |
| Import | External symbols the module requires (functions, tables, memories, globals) |
| Function | Maps function indices to type indices |
| Table | Indirect call tables (for function pointers) |
| Memory | Linear memory declarations (count and initial/max pages) |
| Global | Mutable/immutable global variables |
| Export | Names exported to the host |
| Start | Optional function called at instantiation |
| Element | Table initialization data |
| Code | Function body bytecode |
| Data | Linear memory initialization data |
| Custom | Arbitrary data (debug info, names, etc.) |

The Import and Export sections define the module's public contract with the host. Every import must be satisfied at instantiation. Every export is callable/readable by the host.

## Linear Memory

WASM memory is a flat byte array, indexed from 0. There is one memory per module (by convention — the multi-memory proposal allows more). Memory grows in 64 KiB pages via the `memory.grow` instruction.

Key properties:
- Memory is not shared between module instances by default.
- Reads and writes outside declared bounds trap immediately.
- The host can also read/write module memory directly (the host sees it as a `Vec<u8>` or equivalent).
- Memory is not zeroed automatically on growth — only on initial allocation.

`memory.grow` takes a page count delta and returns the previous page count, or -1 if growth fails. Growth can fail if the runtime imposes a memory cap or the OS cannot back the allocation.

Accessing memory across the component boundary (host reading guest memory, or vice versa) requires copying via the component model's canonical ABI. Do not attempt raw pointer sharing across the boundary.

## Tables and Indirect Calls

Tables hold references to functions (or externrefs). The primary use is indirect calls — equivalent to C function pointers. A `call_indirect` instruction pops a table index from the stack and calls the function at that index, validating the type signature first.

In practice, tables appear in modules compiled from languages with dynamic dispatch (Rust trait objects, C++ vtables, etc.). Direct function calls (`call $func_name`) are preferred when the target is statically known.

## Text Format (.wat)

The text format uses S-expression syntax:

```wat
(module
  (import "host" "log" (func $log (param i32 i32)))  ;; import from host
  (memory 1)                                           ;; 1 page = 64 KiB
  (data (i32.const 0) "hello world")                  ;; init memory at offset 0
  (func $main (export "main")
    i32.const 0   ;; string offset
    i32.const 11  ;; string length
    call $log     ;; call imported host function
  )
)
```

Use `wasm-tools print some.wasm` to disassemble a binary `.wasm` to `.wat`. This is the standard inspection tool — see `wasm-components.md` for component-aware inspection.

## Traps

A trap is an unrecoverable error in the WASM virtual machine. When a trap fires:
- Execution of the guest halts immediately.
- The stack unwinds to the host call boundary.
- The runtime surfaces the trap as an error to the host.
- The store/instance is typically considered poisoned — behavior on re-use is runtime-defined, but wasmtime marks the store as unusable after a trap.

Common trap causes:
- `unreachable` instruction executed (deliberate panic/abort)
- Out-of-bounds memory access
- Out-of-bounds table access
- Integer divide by zero (for `i32.div_s`, `i32.div_u`, etc.)
- Call stack overflow (recursion depth limit)
- Bad `call_indirect` type signature

**Practical implication:** any host wrapper holding the runtime state in a `Mutex` (typical pattern) will see the lock poisoned after a guest trap. Re-instantiate the component from the bytecode rather than attempting to re-lock.

## Security Model

WASM's security model is capability-based sandbox-by-default:

- A module cannot read or write host memory (only its own linear memory).
- A module can only call host functions that are explicitly imported and linked.
- A module cannot spawn threads, open files, or make network calls unless the host provides the relevant imports.
- All imports are visible in the module's Import section — no hidden dependencies.

This is different from native code, where a DLL can call any libc symbol. WASM modules have fully enumerable dependencies.

For wasmtime specifically: the `Linker` controls what is available to the guest. Add only what the guest legitimately needs. The WASI capability model (see `wasi.md`) builds on this: even within WASI, the host controls which directories are accessible, which environment variables are visible, etc.

## Runtime Landscape

The main server-side runtimes:

**wasmtime** (Bytecode Alliance, Rust) — Production-grade, actively developed. Full component model support. Default for server-side and embedded scenarios in the Rust ecosystem. Rust host-embedding details live in the `wasmtime` sibling skill.

**wasmer** — Alternative runtime, multiple backends (LLVM, Cranelift, Singlepass). Mature, good ecosystem. Component-model support is more recent than wasmtime's.

**v8 / SpiderMonkey** — Browser engines. Full core WASM support. Not component-model-aware natively; tools like `jco` transpile components to JS+module so browsers can run them.

**wasm3** — Interpreter, extremely small footprint (~64 KiB). No JIT. Good for embedded/microcontrollers where binary size or startup time matters more than throughput.

**WAMR** (WebAssembly Micro Runtime) — Another embedded-focused runtime from Intel/Bytecode Alliance.

**jco** — Not a runtime per se but a transpiler: takes a `.wasm` component and produces a JS ES module that runs anywhere V8/SpiderMonkey runs.

For component-model server scenarios, wasmtime is the canonical choice — it has the most mature component-model API surface.

## When to Use Raw Modules vs Components

Use raw WASM modules when:
- The host language already has a direct binding layer (e.g., wasm-bindgen for browsers).
- The interface is extremely simple (a handful of numeric functions).
- The toolchain for components is not available in the target environment.

Use components (see `wasm-components.md`) for all modern Rust-to-WASM scenarios:
- Rich types at the boundary (strings, records, results) without manual ABI glue.
- Composability — wiring one component's exports to another's imports.
- WIT-described interfaces that are tooling-inspectable and language-agnostic.
- Interoperability with any WIT-compatible host (wasmtime, jco, etc.).
