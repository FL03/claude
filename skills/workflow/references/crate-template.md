# Crate Cargo.toml Template

Complete template for any new crate within `crates/*`. Copy and adapt — do not deviate.

## Full Template

```toml
[package]
authors.workspace = true
build = "build.rs"
categories.workspace = true
description = "SHORT_DESCRIPTION"
edition.workspace = true
homepage.workspace = true
keywords.workspace = true
license.workspace = true
name = "axiom-NAME"
readme.workspace = true
repository.workspace = true
rust-version.workspace = true
version.workspace = true

[lib]
bench = false
# crate-type = ["cdylib", "rlib"]  # only for WASM components

[features]
default = ["std"]
full = [
  "default",
  # all optional features listed here
  # propagate full to axiom deps:
  # "axiom-core/full",
  # "axiom-engine?/full",
]

# ── environment features (MANDATORY) ──
std = [
  "alloc",
  # propagate std to all deps:
  # "axiom-core/std",
  # "serde?/std",
]
alloc = [
  # "axiom-core/alloc",
]
nightly = []
wasm = [
  "std",
  # "axiom-core/wasm",
]
wasi = [
  # "axiom-core/wasi",
]

# ── capability features ──
# Group by purpose. Common ones:
# json = ["dep:serde_json", "serde"]
# serde = ["dep:serde", "dep:serde_derive"]
# tokio = ["dep:tokio"]
# tracing = ["dep:tracing"]
# chrono = ["dep:chrono"]

# ── dependency activation features ──
# For optional axiom-* deps:
# config = ["dep:axiom-config", "axiom-config?/serde"]

[dependencies]
# Required axiom deps (non-optional):
# axiom-core = { workspace = true }

# Optional axiom deps:
# axiom-config = { optional = true, workspace = true }

# Required external deps:
# thiserror = { workspace = true }

# Optional external deps:
# serde = { optional = true, workspace = true }
# serde_json = { optional = true, workspace = true }
# tokio = { optional = true, workspace = true }
# tracing = { optional = true, workspace = true }

[dev-dependencies]
# criterion = { workspace = true }
# tokio = { features = ["full"], workspace = true }

[package.metadata.docs.rs]
all-features = false
features = ["default"]
rustc-args = ["--cfg", "docsrs"]
version = "v{{version}}"

[package.metadata.release]
no-dev-version = true
tag-name = "{{version}}"
```

## build.rs Template

```rust
fn main() {
    println!("cargo::rerun-if-changed=build.rs");
}
```

## lib.rs Template

```rust
//! axiom-NAME
//!
//! SHORT_DESCRIPTION

#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(feature = "alloc")]
extern crate alloc;

// Module declarations
// pub mod types;
// pub mod error;

// Re-exports
// pub use self::types::*;
```

## Feature Gate Rules

1. **`default` must be minimal.** Usually just `["std"]`. Foundation crates (traits, math, core)
   NEVER include heavy deps in defaults.

2. **`full` must include everything.** All optional features + `/full` propagation to all axiom deps.
   This is what CI tests against.

3. **`std` must propagate.** Every dependency that has a `std` feature gets `"dep/std"` in the
   `std` feature list. Use `"dep?/std"` for optional deps.

4. **Conditional propagation.** Use `?/` for optional dependencies:
   ```toml
   std = ["axiom-config?/std"]  # only propagate if axiom-config is enabled
   ```

5. **`dep:` syntax for optional activation.** When a feature enables an optional dependency:
   ```toml
   config = ["dep:axiom-config"]  # activates the optional dependency
   ```

6. **No underscore feature names.** Use kebab-case or single words: `config`, `json`, `tokio`.
   Never `axiom_config` (underscore).

## Checklist for New Crates

- [ ] `name` and `description` are crate-specific, everything else inherits workspace
- [ ] `[lib] bench = false` declared
- [ ] `build = "build.rs"` declared with build script created
- [ ] `[package.metadata.docs.rs]` section present
- [ ] `[package.metadata.release]` section present
- [ ] `default`, `full`, `std`, `alloc`, `nightly`, `wasm`, `wasi` features defined
- [ ] `std` propagates to all deps, `full` propagates `/full` to axiom deps
- [ ] Optional deps use `optional = true`
- [ ] Feature activation uses `dep:` syntax
- [ ] Conditional propagation uses `?/` syntax
- [ ] Registered in workspace `Cargo.toml` under `[workspace.dependencies]`
- [ ] Registered in umbrella `crates/axiom/Cargo.toml` behind feature gate
- [ ] Re-exported in `crates/axiom/lib.rs` with `#[cfg(feature = "...")]`
- [ ] `wit/` directory created with at least `types.wit`, interface `.wit`, `world.wit`
