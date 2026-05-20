# WIT — WebAssembly Interface Types

## What WIT Is

WIT (WebAssembly Interface Types) is the IDL (Interface Definition Language) for the component model. A `.wit` file describes the types, functions, and structure of a component's interface in a language-agnostic way. From a single `.wit` definition, tooling can generate host-side and guest-side bindings in Rust, Python, JavaScript, Go, and any other language with WIT support.

WIT is not code. It has no runtime. It is a contract description that sits at the boundary between components. What makes it powerful — and dangerous if misused — is that it is agnostic about who holds the truth. This is **directionality**, and it is the most important concept in this document.

## Directionality — The Two Modes

WIT has no inherent direction. It is a description language, not an enforcement language. But in practice, every `.wit` file has a direction: either the implementation already exists and WIT describes it, or the WIT exists first and the implementation must satisfy it.

Confusing these two directions causes architectural errors that are invisible to the compiler.

---

### Direction 1 — WIT describes an existing API ("documentation direction")

The Rust type, trait, or module already exists. The WIT file is written to expose that existing API across the component boundary so external consumers can import it without depending on the Rust crate.

- **Source of truth:** The Rust code
- **WIT role:** Mirror, documentation, cross-language export
- **Who changes first:** Rust changes; WIT is updated to match
- **Placement:** WIT lives next to the Rust source it describes

Example: a host crate's `wit/types.wit` defines `record measurement { ... }` mirroring the host language's existing `Measurement` struct. External components import this WIT to be compatible with the host's data model. If the struct gains a new field, the WIT must be updated. The host code is the authoritative definition.

```wit
// host-crate/wit/types.wit
// Direction 1: mirrors existing host types.
// Source of truth is the host crate. Update WIT when host types change.
interface types {
    record measurement {
        value: f64,
        timestamp: u64,
        unit: string,
    }
    // ... context, result records
}
```

---

### Direction 2 — WIT defines a contract the implementation must satisfy ("enforcement direction")

The WIT world is written first, defining what a component must export. A Rust crate is then written to implement that world. If the WIT changes, the Rust code must update — compilation will fail until it does.

- **Source of truth:** The WIT file
- **WIT role:** Binding contract, specification
- **Who changes first:** WIT changes; Rust is updated to match
- **Placement:** WIT lives with the component that is being defined, not the implementer

Example: a host crate's `wit/world.wit` defines `world plugins { ... }` declaring what every plugin component must export. The world.wit is the contract; each plugin's `lib.rs` is the fulfillment.

```wit
// host-crate/wit/world.wit
// Direction 2: defines the contract that plugin components must export.
// Source of truth is this file. Changing it requires updating all implementing components.
world plugins {
    use types.{context, output};
    import plugin;
    import types;
}
```

---

### Choosing the right direction

| Question | Answer → Direction |
|----------|-------------------|
| Does the Rust code already exist? | Describe it → Direction 1 |
| Are multiple implementations expected (native, WASM, future)? | Define the contract → Direction 2 |
| Is this a shared type package (candle, tick, signal)? | Direction 1 — types live with their Rust source |
| Is this a component entry point (what a plugin must export)? | Direction 2 — world.wit owns the contract |
| Is this for internal in-process polymorphism? | Neither — use Rust traits, not WIT |

**Document the direction as a comment in the WIT file.** When an agent modifies a WIT file, they must know the direction before making any change. A Direction 1 file should say so; a Direction 2 file should say so. This prevents automated bulk generation from treating contract-defining files as safe to overwrite.

---

## Syntax Reference

### Package Declaration

Every WIT file belongs to a package. The package name is hierarchical.

```wit
package my-org:my-crate@0.1.0;
```

Format: `namespace:name@version`. The version is optional but recommended. All interfaces and worlds in a package share this namespace.

### Interface

An interface is a named collection of types and functions. It can be imported or exported by a world.

```wit
interface driver {
    use types.{context, signal};

    features: func() -> list<string>;
    name: func() -> string;
    version: func() -> string;
    drive: func(ctx: context) -> signal;
}
```

### World

A world is the top-level contract for a component. It declares what the component imports from the host and what it exports to the host.

```wit
world my-component {
    import wasi:clocks/monotonic-clock;   // needs clock from host
    import my-types;                       // needs types from host
    export compute;                        // provides compute to host
}
```

A component implements exactly one world. The world is the contract binding.

### Types

**Primitives:**
```wit
bool
u8  u16  u32  u64
s8  s16  s32  s64
f32  f64
char   // Unicode scalar value
string // UTF-8
```

**Compound:**
```wit
// record — named struct, all fields present
record candle {
    open: f64,
    high: f64,
    low: f64,
    close: f64,
    volume: f64,
    timestamp: u64,
}

// variant — tagged union, exactly one case
variant direction {
    up(f64),      // carries a payload
    down(f64),
    sideways,     // no payload
}

// enum — variant with no payloads
enum side {
    yes,
    no,
}

// option — nullable value
option<string>      // Some(string) or None

// result — success or error
result<signal, string>   // Ok(signal) or Err(string)
result<_, string>        // Ok(unit) or Err(string)
result                   // Ok(unit) or Err(unit)

// list — variable-length sequence
list<candle>

// tuple — fixed heterogeneous sequence
tuple<f64, u64>

// flags — bitset
flags permissions {
    read,
    write,
    execute,
}
```

**Type aliases:**
```wit
type score = f64;
type candles = list<candle>;
```

### Resource

Resources are opaque handles that cross the boundary by reference, not by value. They have a lifetime managed by the component model.

```wit
resource model {
    constructor(path: string);
    predict: func(ctx: context) -> signal;
    drop: static func(self: model);
}
```

Resources require more tooling care. For simple compute interfaces, pass data as records (value semantics) unless the object is genuinely expensive to copy.

### `use` — Importing Types from Other Interfaces

```wit
// Within the same package (no package qualifier needed):
use types.{candle, context, signal};

// Cross-package import:
use my-org:host-types/types.{measurement};
```

Imports connect across directory and package boundaries by package name — not by file path. The WIT toolchain resolves packages by name against the workspace's registered WIT paths (configured in `Cargo.toml` or via `wasm-tools`).

## Placement Rules

**1. Types go where they're defined.**

A type defined in some host crate has its WIT mirror in *that crate's* `wit/types.wit`. Do not duplicate the type definition in another crate's WIT just for convenience — use a cross-package `use` import instead.

**2. Worlds go where the contract is.**

If a guest component must satisfy a contract, the world defining that contract lives with the *contract author* (Direction 2) — typically the host crate that loads the guest. The guest component consumes that world via package import.

If a host crate is exposing its own existing API for external consumers (Direction 1), the world lives with the host's source.

**3. Imports cross boundaries via package names, not file paths.**

```wit
// In a guest component's wit/world.wit:
package my-org:my-plugin@0.1.0;

world my-plugin {
    import host-org:host-pkg/types;    // cross-package import
    export host-org:host-pkg/plugin;   // must export the plugin interface
}
```

The cross-package reference is resolved by the build toolchain against the registered WIT directories — not by relative file path.

## Package Naming Conventions

Common pattern:

- Namespace: organization or project name (e.g. `my-org`, `wasi`)
- Package name: matches the crate or contract name (`my-plugin`, `host-types`)
- Version: track meaningfully — match the crate version when the WIT and code release together; pin independently when the contract evolves on its own cadence

Examples:
```
my-org:host-types@0.1.0
my-org:plugin-contract@0.1.0
wasi:clocks@0.2.0
```

## Common Patterns

### Shared Types Package

A WIT package that only contains interface type definitions, no worlds. Other packages import from it.

```wit
// host-crate/wit/types.wit
package my-org:host-types@0.1.0;

interface types {
    record measurement { ... }
    record event { ... }
    type score = f64;
}
```

Other packages:
```wit
use my-org:host-types/types.{measurement, event};
```

### Plugin Interface Pattern

A contract-defining package (Direction 2) that specifies what plugin components must export:

```wit
// host-crate/wit/plugin.wit — the interface specification
interface plugin {
    use types.{context, output};
    features: func() -> list<string>;
    name: func() -> string;
    version: func() -> string;
    invoke: func(ctx: context) -> output;
}

// host-crate/wit/world.wit — the world contract
world plugins {
    use types.{context, output};
    import plugin;
    import types;
}
```

### Host-Guest World

A world where the host provides some imports and the guest provides some exports:

```wit
world compute-guest {
    // host provides these:
    import wasi:clocks/monotonic-clock;
    import logger;

    // guest must export these:
    export plugin;
}
```

## Anti-Patterns

**Over-WIT-ing.** Adding WIT to every Rust module creates maintenance overhead without benefit. WIT is for cross-runtime boundaries. In-process Rust code uses Rust traits. Only add WIT where a real cross-language or cross-runtime consumer exists.

**Bulk-generating WIT from code.** Automated generation from Rust structs produces Direction 1 WIT that looks like Direction 2 WIT. The resulting files are ambiguous — is this a mirror or a contract? Direction 2 files in particular must be hand-designed.

**Mirroring Rust traits in WIT.** Rust traits are the in-process interface layer. Do not create WIT interfaces that mirror every Rust trait. WIT is for the component boundary, not for Rust polymorphism.

**Bulk-adding WIT to component crates without review.** Component WIT files are Direction 2 contracts. Generating them from a script and then implementing them breaks the "WIT is the source of truth" invariant. Design `world.wit` files for components by hand; commit them as architectural decisions.

**Forgetting that WIT changes break implementing components.** A Direction 2 WIT change is a breaking change for every component that implements that world. The compiler will surface this only if the component is compiled against the new WIT. If the component is pre-compiled and shipped as a `.wasm` binary, the mismatch surfaces at runtime (link error at instantiation).

**Using `string` as a catch-all type.** Strings cross the component boundary via copy. Prefer specific record types for structured data. A `record side { yes: bool }` is cheaper and self-documenting compared to parsing `"yes"` or `"no"` strings.

## Code Generation Note

`wit-bindgen` generates guest-side Rust bindings from WIT (what the component must implement). `wasmtime::component::bindgen!` generates host-side bindings (how the host calls into the component). Both are Rust-specific — see the `rust` skill (`wasm.md`, `wasmtime-host.md`) for details on configuring and using these macros.

## Inspection Commands

```
# Show what WIT a compiled component declares
wasm-tools component wit path/to/my_component.wasm

# Validate a WIT package directory
wasm-tools component wit --dry-run path/to/wit/

# Resolve and dump all WIT from a package directory
wasm-tools component wit --all path/to/wit/
```
