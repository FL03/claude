---
name: cargo
description: |
  The full cargo surface for any Rust workspace: commands, Cargo.toml schema,
  workspaces, feature gates, .cargo/config.toml, registries, the subcommand
  ecosystem, sccache, parallel-agent build workflows, and machine-readable
  output. Companion reference to the rust skill — open this when the task
  is about cargo invocations, the manifest, or the build pipeline.
type: reference
version: 5.1.0
---

# Cargo — The Build System and Package Manager

Cargo is the workspace coordinator. It owns dependency resolution, the
compilation pipeline, the feature graph, and the toolchain interface.
Operational facts here are sourced from **The Cargo Book**
(`https://doc.rust-lang.org/cargo/`) — not memory.

The sections progress: daily commands → manifest reference → workspace
orchestration → feature/config nuance → ecosystem subcommands → parallel
build patterns → machine-readable output. Skim for the relevant section,
then read deep.

When a flag or key isn't documented here, the canonical lookup is
`https://doc.rust-lang.org/cargo/commands/<command>.html` for commands and
`https://doc.rust-lang.org/cargo/reference/manifest.html` for the manifest.

---

## §1. Commands

Cargo groups its commands by purpose. The flags listed below are the ones
worth memorizing; the full surface for any command is `cargo <cmd> --help`
or the corresponding Cargo Book page.

### Build & develop

| Command | Purpose | Key flags |
|---|---|---|
| `cargo build` | Compile a package and its dependencies. | `-p <crate>`, `--workspace`, `--release`, `--profile <name>`, `--features <list>`, `--no-default-features`, `--all-features`, `--target <triple>`, `--target-dir <dir>`, `--bin <name>`, `--example <name>`, `--lib`, `-j <N>` |
| `cargo check` | Compile without producing artifacts — fast feedback loop. | Same flags as `build`. The default workflow command during development. |
| `cargo test` | Build and run tests. | `--lib`, `--bins`, `--tests`, `--doc`, `--no-run`, `--test-threads=<N>` (after `--`), `--nocapture` (after `--`), `--ignored` (after `--`) |
| `cargo run` | Compile then execute a `[[bin]]` target. | `--bin <name>`, `--example <name>`, `--release`. Args after `--` go to the binary. |
| `cargo doc` | Build the rustdoc HTML output. | `--no-deps`, `--open`, `--document-private-items`, `--workspace` |
| `cargo bench` | Run `#[bench]` benchmarks (nightly toolchain, or use `criterion`). | Same shape as `test`. |
| `cargo fix` | Apply rustc suggestions automatically. | `--edition` (migrate edition), `--edition-idioms`, `--allow-dirty`, `--allow-staged`. |
| `cargo clean` | Delete the `target/` directory. | `-p <crate>` to clean one package's artifacts only. |

### Dependency management

| Command | Purpose | Key flags |
|---|---|---|
| `cargo add` | Add a dependency to `Cargo.toml`. | `--features <list>`, `--no-default-features`, `--optional`, `--dev`, `--build`, `--target <triple>`, `--path <path>`, `--git <url>`, `--rev`/`--tag`/`--branch` |
| `cargo remove` | Remove a dependency. | `--dev`, `--build`, `--target <triple>` |
| `cargo update` | Refresh `Cargo.lock` to newer compatible versions. | `-p <crate>` to update one dep, `--precise <version>` to pin, `--breaking` (in newer cargo) to bypass semver. |
| `cargo tree` | Display the dependency graph. | `-i <crate>` (invert: who depends on it), `-d` (show duplicates), `-e features` (annotate features), `--workspace` |
| `cargo fetch` | Download deps without building. | `--target <triple>` |
| `cargo vendor` | Copy all dependency sources into a local `vendor/` directory. | `--respect-source-config`, `--locked` |
| `cargo generate-lockfile` | Create `Cargo.lock` without building. | (rarely needed — `cargo build` does it.) |

### Discovery & metadata

| Command | Purpose | Notes |
|---|---|---|
| `cargo search <term>` | Search crates.io. | Honors `--limit <N>` (default 10). |
| `cargo info <crate>` | Display crate metadata (versions, deps, features). | Added in cargo 1.79. |
| `cargo metadata` | Emit JSON describing the workspace, members, deps, targets. | `--format-version=1` (the only supported format today). Essential for tooling. |
| `cargo locate-project` | Print the path to `Cargo.toml`. | `--workspace` to locate the workspace root. |
| `cargo pkgid <spec>` | Print the canonical package ID for a spec. | Useful for resolving ambiguous `-p` arguments. |

### Project scaffolding

| Command | Purpose |
|---|---|
| `cargo new <path>` | Create a new package in a new directory. `--lib` or `--bin` (default). `--vcs <none\|git\|hg\|pijul\|fossil>`. |
| `cargo init [<path>]` | Same as `new`, but operates on the current (or named) directory. |

### Publishing

| Command | Purpose |
|---|---|
| `cargo login [<token>]` | Save a registry token to `~/.cargo/credentials.toml`. |
| `cargo logout` | Remove the saved token. |
| `cargo package` | Build a `.crate` tarball locally. `--list` shows what would be included, `--allow-dirty` skips the clean-tree check. |
| `cargo publish` | Upload to crates.io (or an alt registry via `--registry <name>`). `--dry-run` is the safety net. |
| `cargo yank --vers <X.Y.Z> <crate>` | Mark a version unresolvable for new builds. Reversible with `--undo`. |
| `cargo owner` | Manage who can publish a crate. `--add`/`--remove`/`--list`. |

### Installation (binaries)

| Command | Purpose |
|---|---|
| `cargo install <crate>` | Compile and install a binary from a registry/path/git. `--locked` to honor the crate's `Cargo.lock`. `--git`/`--path`/`--registry`/`--version`/`--features` all supported. |
| `cargo uninstall <crate>` | Remove an installed binary. |

### Universal flags

These work on most build/check/test commands and are worth knowing globally:

- `-v` / `-vv` — verbose / very verbose; `-vv` shows the actual rustc invocations.
- `-q` — quiet (suppress progress).
- `--offline` — disallow network access; fail fast if a dep needs downloading.
- `--frozen` — require `Cargo.lock` to be up-to-date AND `--offline`.
- `--locked` — require `Cargo.lock` to be up-to-date (network allowed).
- `--color <auto|always|never>`.
- `--manifest-path <Cargo.toml>` — work against a manifest other than the current directory's.
- `--config <KEY=VAL>` — override a `.cargo/config.toml` key for this invocation.
- `--message-format <human|json|json-diagnostic-rendered-ansi|...>` — see §10.

---

## §2. Cargo.toml schema

The manifest is a TOML file rooted at the package directory. The Cargo Book's
**Manifest Format** page is the canonical reference:
`https://doc.rust-lang.org/cargo/reference/manifest.html`.

### `[package]`

```toml
[package]
name           = "my-crate"            # required; kebab-case
version        = "0.1.0"               # required; semver
edition        = "2024"                # 2015 | 2018 | 2021 | 2024
rust-version   = "1.75"                # MSRV; cargo refuses older toolchains
description    = "..."                 # required for crates.io
license        = "MIT OR Apache-2.0"   # SPDX expression; or use license-file
license-file   = "LICENSE"             # alternative to `license`
repository     = "https://github.com/..."
homepage       = "https://..."
documentation  = "https://docs.rs/my-crate"
readme         = "README.md"
keywords       = ["wasm", "actor"]     # ≤5; alphanumeric, kebab-allowed
categories     = ["asynchronous"]      # see https://crates.io/category_slugs
authors        = ["Name <email>"]      # optional in 2018+
include        = ["src/**/*.rs", "Cargo.toml", "LICENSE", "README.md"]
exclude        = ["tests/data/*.bin"]
publish        = true                  # set false to forbid `cargo publish`
default-run    = "my-bin"              # which `[[bin]]` `cargo run` picks by default
metadata       = { ... }               # opaque per-tool; used by docs.rs, cross, etc.
```

Most fields can inherit from the workspace via `field.workspace = true` —
see §3.

### `[dependencies]`, `[dev-dependencies]`, `[build-dependencies]`

All three use the same shape; scopes differ.

```toml
[dependencies]
# Simplest: registry, version requirement
serde = "1.0"

# Inline table — needed when more than version
tokio = { version = "1", features = ["rt-multi-thread", "macros"], default-features = false }

# Workspace inheritance
clap = { workspace = true, features = ["derive"] }
anyhow.workspace = true                  # shorthand for `= { workspace = true }`

# Path dependency (intra-workspace; not published)
my-utils = { path = "../utils" }

# Git dependency
tracing = { git = "https://github.com/tokio-rs/tracing", rev = "abc123" }
# Also accepts tag = "..." or branch = "..."

# Optional dependency — enables a feature via dep: syntax (see §4)
serde_json = { version = "1", optional = true }

# Renamed dependency (use a different name locally)
old-name = { version = "0.5", package = "real-crate-name" }

# Target-specific dependency (cfg-gated)
[target.'cfg(unix)'.dependencies]
nix = "0.27"

[target.'cfg(target_arch = "wasm32")'.dependencies]
wasm-bindgen = "0.2"
```

When inheriting from `[workspace.dependencies]`, only `features`,
`default-features`, and `optional` may be set alongside `workspace = true` —
not `version`, `path`, or `git` (those are workspace-fixed).

### `[features]`

```toml
[features]
default = ["std"]                  # what `cargo build` enables by default
std     = ["serde?/std"]            # `?/` propagates only if serde is enabled
json    = ["dep:serde_json", "serde/derive"]
http    = ["dep:reqwest", "tokio/rt-multi-thread"]
full    = ["json", "http"]
```

Rules:
- **Additive only.** Cargo unifies features across the dep graph; "feature A
  XOR feature B" breaks downstream.
- **`dep:<name>`** activates an optional dependency without exposing a
  feature with that name to downstream crates.
- **`<dep>?/<feat>`** forwards `<feat>` to `<dep>` *only if* `<dep>` is
  enabled by some other feature.
- **`default = []`** is the no-features-by-default convention for libraries.

### `[profile.*]`

Built-in profiles: `dev` (used by `cargo build`), `release` (used by `cargo
build --release`), `test` (inherits `dev`), `bench` (inherits `release`).
Custom profiles inherit from one of these via `inherits = "..."`.

```toml
[profile.<name>]
inherits         = "dev"     # required for custom profiles
opt-level        = 0          # 0|1|2|3|"s"|"z" — see rustc.md §2
debug            = true       # 0|1|2|true|false|"limited"|"line-tables-only"
split-debuginfo  = "..."      # platform-dependent: "off"|"packed"|"unpacked"
strip            = "none"     # "none"|"debuginfo"|"symbols"|true|false
debug-assertions = true
overflow-checks  = true
lto              = false      # false|true|"off"|"thin"|"fat"
panic            = "unwind"   # "unwind"|"abort"
incremental      = true
codegen-units    = 16
rpath            = false

# Per-dependency override
[profile.release.package."*"]
opt-level = 3                  # apply to all deps but not the local crate

[profile.release.package.serde]
opt-level = 3                  # apply only to serde
```

### `[patch]` / `[patch.crates-io]`

```toml
[patch.crates-io]
serde = { git = "https://github.com/serde-rs/serde", branch = "master" }

[patch."https://github.com/example/foo"]
foo = { path = "../foo-fork" }
```

`[patch]` replaces a dependency *transitively* across the entire graph.
Only the workspace-root manifest's `[patch]` table is honored — patches in
member manifests are silently ignored.

### `[lib]` and `[[bin]]`

```toml
[lib]
name              = "my_crate"          # default: package name with `-` → `_`
path              = "src/lib.rs"
crate-type        = ["lib"]             # "lib"|"rlib"|"dylib"|"cdylib"|"staticlib"|"proc-macro"
test              = true
doctest           = true
bench             = true
doc               = true
harness           = true                # set false for criterion-style custom test harness
required-features = []                  # bin/example only

[[bin]]
name              = "my-tool"
path              = "src/bin/my-tool.rs"
test              = false
required-features = ["cli"]
```

### `[[example]]`, `[[test]]`, `[[bench]]`

Same shape as `[[bin]]`. By default, `examples/*.rs`, `tests/*.rs`, and
`benches/*.rs` are auto-discovered; explicit `[[…]]` tables are only needed
when overriding `name`, `path`, or `required-features`.

### `[workspace]`

See §3 for the full treatment. The minimal shape:

```toml
[workspace]
members          = ["crates/*", "bin/*"]
default-members  = ["crates/core"]
exclude          = ["crates/legacy"]
resolver         = "2"                  # "1" | "2" | "3"
```

---

## §3. Workspaces

A workspace is a set of related packages sharing a single `Cargo.lock`, a
single `target/`, and (usually) a coordinated dep graph. Two manifest
shapes:

- **Root-package workspace:** the workspace root is itself a package. It
  has both `[package]` and `[workspace]` tables.
- **Virtual manifest:** the root has only `[workspace]` (no `[package]`).
  Common for repos where the "primary" crate isn't obvious or doesn't
  exist.

```toml
# [PROJECT_DIR]/Cargo.toml  (virtual manifest)
[workspace]
members          = ["crates/*", "bin/*"]
default-members  = ["crates/core"]
exclude          = ["crates/legacy"]
resolver         = "3"
```

### `members`, `default-members`, `exclude`

- `members` — packages explicitly part of the workspace. Globs (`crates/*`)
  expand at the directory level.
- `default-members` — packages targeted by `cargo build` (and friends) when
  invoked from the root without a `-p` flag. If unset, all members.
- `exclude` — paths to ignore even if a glob would otherwise include them.
  Useful for vendored/legacy directories.

### Resolver versions

The resolver controls how cargo unifies features across the dep graph.

| Resolver | Default for | Notable behavior |
|---|---|---|
| `"1"` | edition 2015/2018 packages | Features unified globally — building `dev-dependencies` activates their features for the main build too. |
| `"2"` | edition 2021 packages | Features for build-deps, dev-deps, and per-target deps no longer leak into the main build graph. The right choice for most modern workspaces. |
| `"3"` | edition 2024 packages | Adds MSRV-aware version selection: cargo prefers compatible versions over latest when `rust-version` is set. |

Set `resolver = "3"` at the workspace root explicitly — the edition field
on the root crate is ignored for resolver selection in workspaces.

### `[workspace.package]` — field inheritance

```toml
# Root Cargo.toml
[workspace.package]
version       = "0.4.2"
edition       = "2024"
rust-version  = "1.75"
authors       = ["FL03 <j3mccain@gmail.com>"]
license       = "Apache-2.0"
repository    = "https://github.com/example/repo"
```

```toml
# crates/foo/Cargo.toml
[package]
name           = "foo"
version.workspace      = true
edition.workspace      = true
rust-version.workspace = true
authors.workspace      = true
license.workspace      = true
repository.workspace   = true
```

Member crates opt in field-by-field — no automatic inheritance.

### `[workspace.dependencies]` — version centralization

```toml
# Root Cargo.toml
[workspace.dependencies]
serde   = { version = "1", default-features = false }
tokio   = { version = "1", default-features = false }
my-core = { path = "crates/core" }       # intra-workspace
```

```toml
# crates/bar/Cargo.toml
[dependencies]
serde   = { workspace = true, features = ["derive"] }
tokio   = { workspace = true, features = ["rt-multi-thread", "macros"] }
my-core = { workspace = true }
```

Members inherit `version`, `source` (path/git/registry), and any
non-overridden flags. Members may add `features` and override `optional`
and `default-features`. Other keys (`version`, `path`, `git`) are
workspace-fixed.

### `[workspace.lints]` — centralized lint config

```toml
# Root Cargo.toml
[workspace.lints.rust]
unsafe_code = "deny"
missing_docs = "warn"

[workspace.lints.clippy]
all = "warn"
pedantic = "warn"
```

```toml
# Member Cargo.toml
[lints]
workspace = true
```

Cleaner than scattering `#![deny(...)]` across every crate root. Members
opt in by adding `[lints] workspace = true`.

### `[workspace.metadata]`

Opaque to cargo; tools (docs.rs, `cargo-release`, `cross`, etc.) use this
as a config bucket. Schema is per-tool.

---

## §4. Feature gates

Features are cargo's compile-time dependency-injection mechanism. The
mechanics are described in `[features]` (§2); the discipline that keeps
them sane is below.

### Rules of the additive feature model

- **Features are additive.** When two crates in the dep graph both enable
  `foo`, the result is `foo` enabled — never a conflict. If two features
  encode mutually-exclusive *behavior* (different impls of the same
  trait, different transport layers), the design is wrong. Reshape into
  additive flags or runtime config.
- **Every new dependency gets its own named feature.** Use `dep:` to
  activate optional deps without exposing them as features:

  ```toml
  [dependencies]
  serde = { version = "1", optional = true }

  [features]
  json = ["dep:serde", "dep:serde_json"]
  ```

  Without `dep:`, cargo auto-creates a feature with the same name as the
  optional dep — a leak that downstream code can accidentally rely on.
- **`<dep>?/<feat>`** forwards `<feat>` to `<dep>` only when `<dep>` is
  already enabled by some other feature. Without `?`, the feature
  unconditionally enables the dep.

### The `no_std` / `alloc` / `std` three-tier system

Library crates aiming for maximum reach support all three tiers:

| Tier | Available | Use case |
|---|---|---|
| `core` only | core | Bare-metal, embedded without heap |
| `alloc` | core + alloc | Heap available, no OS services |
| `std` | core + alloc + std | Hosted OS — the default tier |

```rust
#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(feature = "alloc")]
extern crate alloc;
```

```toml
[features]
default = ["std"]
std     = ["alloc"]
alloc   = []
```

Libraries meant to be reused aim for `no_std + alloc` by default; add
`std` as the ergonomic path. Binaries are always `std`. If the dep graph
is hopelessly tied to `std`, drop the `no_std` claim rather than leave
broken feature combinations.

### Verifying feature matrices

`cargo build` with default features only exercises one path. The full
matrix needs `cargo-hack`:

```bash
cargo install cargo-hack
cargo hack check --feature-powerset --no-dev-deps
cargo hack check --each-feature --no-dev-deps
```

`--feature-powerset` checks every combination (expensive; for small
feature sets). `--each-feature` checks every feature in isolation
(faster; catches the common "this feature alone doesn't compile" bug).

### Canonical sealed-trait pattern with cfg-gated impls

The cleanest demonstration of feature discipline is a sealed marker
trait whose methods are gated at the method level and whose impls are
gated at the impl-block level:

```rust
pub trait RawMetaData {
    private! {}  // sealed — downstream can't impl without `seal!` permission

    #[cfg(feature = "json")]
    fn into_json(self) -> serde_json::Value
    where Self: Sized + serde::Serialize {
        serde_json::to_value(self).expect("infallible for owned values")
    }
}

#[cfg(feature = "alloc")]
impl<K, V> RawMetaData for alloc::collections::BTreeMap<K, V> { seal! {} }

#[cfg(feature = "std")]
impl<K, V> RawMetaData for std::collections::HashMap<K, V> { seal! {} }

#[cfg(feature = "json")]
impl RawMetaData for serde_json::Value {
    seal! {}
    fn into_json(self) -> serde_json::Value { self }  // specialization via cfg
}
```

Rules this enforces: trait defined once; capability methods gated at the
method; impls of foreign types gated at the impl block; each `cfg(feature = "X")`
matches exactly one feature flag; features compose by union. Verify each
combination compiles:

```bash
cargo check -p <crate> --no-default-features
cargo check -p <crate> --no-default-features --features alloc
cargo check -p <crate> --no-default-features --features "alloc,json"
cargo check -p <crate> --features full
```

---

## §5. `.cargo/config.toml`

Cargo reads configuration from a hierarchical search: `./.cargo/config.toml`
in the current directory, then walking up to the workspace root, then
`$CARGO_HOME/config.toml` (default `~/.cargo/config.toml`). Keys merge with
inner overriding outer.

### `[build]`

```toml
[build]
jobs               = 1            # parallel jobs; defaults to # of CPUs
rustc              = "rustc"      # the rust compiler tool
rustc-wrapper      = "sccache"    # wrapper around rustc — see §8
rustc-workspace-wrapper = "…"     # wrapper for workspace members only
rustdoc            = "rustdoc"
target             = "x86_64-unknown-linux-gnu"  # default target triple
target-dir         = "target"     # artifact output (also CARGO_TARGET_DIR env)
rustflags          = ["-D", "warnings"]
rustdocflags       = ["..."]
incremental        = true
dep-info-basedir   = "…"
```

### `[target.<triple>]` and `[target.<cfg>]`

```toml
[target.aarch64-apple-darwin]
linker    = "/usr/local/bin/lld"
runner    = "qemu-aarch64"
rustflags = ["-C", "target-cpu=apple-m1"]

[target.'cfg(all(target_arch = "wasm32", target_os = "unknown"))']
runner    = "wasmtime"
rustflags = ["-C", "target-feature=+bulk-memory"]
```

Triple-keyed and cfg-keyed sections compose: cargo applies all matching
sections.

### `[net]`, `[registries]`, `[source]`

```toml
[net]
retry              = 3
git-fetch-with-cli = true        # use the `git` CLI for credentials/HTTPS
offline            = false

[registries.crates-io]
protocol = "sparse"               # the default since cargo 1.74

[registries.my-private]
index             = "sparse+https://my-registry.example.com/"
credential-provider = "cargo:token"

[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
```

`[source]` enables source replacement — point crates.io at a vendored
mirror or a local directory. Pair with `cargo vendor` to ship a fully
offline build.

### `[alias]`, `[term]`, `[env]`

```toml
[alias]
c   = "check"
b   = "build"
t   = "test --workspace"
xc  = "hack check --each-feature --no-dev-deps"

[term]
verbose   = false
color     = "auto"            # "auto"|"always"|"never"
quiet     = false
hyperlinks = true
unicode    = true
progress.when  = "auto"        # "auto"|"always"|"never"
progress.width = 80

[env]
RUST_BACKTRACE = "1"           # set when cargo runs any subprocess
DATABASE_URL   = { value = "postgres://localhost/dev", force = true }
```

`[env]` keys with `force = true` override the inherited environment. The
shorthand `KEY = "value"` is equivalent to `{ value = "value", force = false }`.

### `[host]` — flags for build-script and proc-macro builds

```toml
[host]
linker    = "/path/to/host-linker"
rustflags = ["-C", "link-arg=--verbose"]

[host.x86_64-unknown-linux-gnu]
rustflags = ["..."]            # more specific overrides the generic
```

Use when cross-compiling — `[target.<triple>]` flags apply to the *target*
artifacts; `[host]` applies to anything that must run on the build machine
(build scripts, proc macros). Without `[host]`, host builds use the
target's `rustflags`, which is almost always wrong for cross builds.

---

## §6. Registries & publishing

The default registry is `crates.io`. Alternative registries are configured
in `.cargo/config.toml` under `[registries.<name>]` (see §5).

### One-time setup

```bash
cargo login                              # crates.io token
cargo login --registry my-private        # alt registry token
# tokens saved to ~/.cargo/credentials.toml
```

### Publishing flow

```bash
# 1. Verify what will ship
cargo package --list

# 2. Dry run — builds the .crate tarball and uploads-but-doesn't-commit
cargo publish --dry-run

# 3. Real publish
cargo publish
# Or to an alt registry:
cargo publish --registry my-private
```

Pre-flight checklist: `Cargo.toml` has `description`, `license`,
`repository`; the working tree is clean (use `--allow-dirty` only when you
mean it); `cargo doc --no-deps` succeeds; tests pass. `cargo publish`
implicitly runs `cargo package` which compiles the crate fresh — if that
fails, the upload aborts.

### Yanking and ownership

```bash
cargo yank --version 0.4.2 my-crate         # prevent new resolves
cargo yank --version 0.4.2 my-crate --undo  # reverse it
cargo owner --add github:my-org:publishers my-crate
cargo owner --list my-crate
cargo owner --remove user-name my-crate
```

Yanked versions still resolve for existing `Cargo.lock` files — yanking
is not a recall. To pull a leaked secret, contact the crates.io team.

### Semver discipline

Cargo enforces semver via the version requirement syntax in `[dependencies]`.
The semver compatibility rules for Rust APIs are documented at
`https://doc.rust-lang.org/cargo/reference/semver.html`. Highlights:

- Adding a new pub item is a minor bump.
- Removing or renaming a pub item is a major bump.
- Adding a trait method without a default is a major bump.
- Adding an enum variant to a non-`#[non_exhaustive]` enum is a major bump.
- Tightening generic bounds is a major bump.

Pre-publish, verify with `cargo install cargo-semver-checks` and
`cargo semver-checks check-release`.

### `cargo-release` for orchestration

`cargo install cargo-release` adds `cargo release` for the
version-bump → tag → publish → push pipeline. The Cargo Book mentions
this tool in its publishing chapter; full docs at the crate.

---

## §7. Subcommand ecosystem

Cargo's plugin model: any binary named `cargo-<sub>` on `PATH` becomes
`cargo <sub>`. The Rust toolchain ships clippy, rustfmt, and a few more
via `rustup component add`; the rest are third-party crates installed
through `cargo install` or `cargo binstall`.

**Lookup pattern:** for any subcommand named below, the canonical
reference is `https://docs.rs/<crate>/latest/` or
`https://github.com/<owner>/<crate>`. Flags change across versions; this
table captures the daily-driver invocation and one-line purpose.

### Toolchain-bundled (via `rustup component`)

| Tool | Purpose | Install | Canonical invocation |
|---|---|---|---|
| `clippy` | ~700 lints; the workhorse linter. `-D warnings` for CI gating. Configure via `clippy.toml` or `[lints.clippy]` in `Cargo.toml`. | `rustup component add clippy` | `cargo clippy --workspace --all-features -- -D warnings` |
| `rustfmt` | Deterministic formatter. Configure via `rustfmt.toml` (`edition`, `max_width`, `imports_granularity`, etc.). | `rustup component add rustfmt` | `cargo fmt --all` |
| `rustdoc` | Doc generator (used by `cargo doc`). Tests `///` examples by default. | bundled with toolchain | `cargo doc --no-deps --workspace --open` |
| `cargo-miri` | Run code under the Miri UB interpreter. Catches undefined behavior in unsafe code. | `rustup +nightly component add miri` | `cargo +nightly miri test -p my-crate` |

### Test / verify

| Tool | Purpose | Install | Canonical invocation |
|---|---|---|---|
| `cargo-nextest` | Faster test runner. Per-test process isolation, retries, parallelism, JUnit output, partition support for distributed CI. Drop-in for `cargo test`. | `cargo binstall cargo-nextest` | `cargo nextest run --workspace` |
| `cargo-hack` | Feature-matrix verification. `--each-feature` checks each feature in isolation; `--feature-powerset` checks every combination. Essential for `no_std + alloc + std` libraries. | `cargo install cargo-hack` | `cargo hack check --feature-powerset --no-dev-deps` |
| `cargo-mutants` | Inject code mutations and rerun tests; uncaught mutations flag weak coverage. | `cargo install cargo-mutants` | `cargo mutants --jobs 4` |
| `cargo-llvm-cov` | Code coverage via LLVM instrumentation. Outputs lcov/html/json. | `cargo install cargo-llvm-cov` | `cargo llvm-cov --workspace --lcov --output-path lcov.info` |

### Dependency hygiene

| Tool | Purpose | Install | Canonical invocation |
|---|---|---|---|
| `cargo-audit` | Cross-check `Cargo.lock` against the RustSec advisory DB. CI-ready. | `cargo install cargo-audit` | `cargo audit` |
| `cargo-deny` | Audit licenses, ban specific crates, detect duplicate deps, check advisories. Configure via `deny.toml`. | `cargo install cargo-deny` | `cargo deny check` |
| `cargo-machete` | Fast unused-dependency finder (static analysis, stable toolchain). | `cargo install cargo-machete` | `cargo machete` |
| `cargo-udeps` | Deeper unused-dep finder (uses unstable rustc features; nightly only). Slower but catches more. | `cargo install cargo-udeps` | `cargo +nightly udeps --workspace --all-targets` |
| `cargo-outdated` | Show out-of-date deps (compares manifest reqs against crates.io latest). | `cargo install cargo-outdated` | `cargo outdated --workspace` |
| `cargo-msrv` | Find the minimum Rust version that compiles a crate. Set the result as `rust-version` in `[package]`. | `cargo install cargo-msrv` | `cargo msrv find -p my-crate` |
| `cargo-semver-checks` | Detect breaking API changes between published versions. Pre-publish gate. | `cargo install cargo-semver-checks` | `cargo semver-checks check-release` |

### Performance / observability

| Tool | Purpose | Install | Canonical invocation |
|---|---|---|---|
| `cargo-flamegraph` | CPU flamegraph via `perf` (Linux) or `dtrace` (macOS). Always use `--release`. | `cargo install flamegraph` (note: package name `flamegraph`) | `cargo flamegraph --bin my-app -- --some-arg` |
| `cargo-bloat` | Show which functions take the most binary space. Useful for `cdylib`/`wasm32` size optimization. | `cargo install cargo-bloat` | `cargo bloat --release -n 50` |
| `cargo-asm` | Disassemble a specific Rust function. Inspect codegen without dropping to `objdump`. | `cargo install cargo-show-asm` (binary: `cargo asm`) | `cargo asm my_crate::path::function_name --rust` |

### Build / workflow

| Tool | Purpose | Install | Canonical invocation |
|---|---|---|---|
| `cargo-expand` | Expand declarative + procedural macros and print the result. Essential for debugging derives and `macro_rules!`. Requires nightly. | `cargo install cargo-expand` | `cargo +nightly expand --lib -p my-crate` |
| `cargo-watch` | Re-run a cargo command on file change. Useful for tight TDD loops. | `cargo install cargo-watch` | `cargo watch -x "check --workspace"` |
| `cargo-binstall` | Download pre-built binaries instead of compiling from source. 10–100× faster for any tool that publishes prebuilts. | `cargo install cargo-binstall` | `cargo binstall ripgrep cargo-nextest cargo-deny` |
| `cargo-release` | Version-bump → tag → publish → push pipeline. Config via `release.toml`. | `cargo install cargo-release` | `cargo release patch --execute` (dry-run is default) |
| `cargo-component` | Build WebAssembly Components (not raw modules) from Rust crates with WIT bindings. The bridge to the WASM component model — see the `wasmtime` and `webassembly` sibling skills. | `cargo install cargo-component` | `cargo component build --release` |
| `cargo-edit` | `cargo add`/`cargo rm`/`cargo upgrade` from CLI. Note: `add` and `rm` are now built into cargo itself; `upgrade` still requires this crate. | `cargo install cargo-edit` | `cargo upgrade --workspace` |
| `wasm-tools` | Inspect/validate/compose `.wasm` files. Not a cargo plugin but always installed alongside. | `cargo install wasm-tools` | `wasm-tools validate my-component.wasm` |

### `rustup` itself

`rustup` manages toolchains, targets, and components. The verbs:

```bash
# Toolchains
rustup toolchain list
rustup toolchain install nightly
rustup toolchain install 1.75.0
rustup default stable
rustup override set nightly                # per-directory pin

# Targets (cross-compilation)
rustup target list --installed
rustup target add wasm32-wasip2
rustup target add aarch64-unknown-linux-musl
rustup target remove <triple>

# Components
rustup component list --installed
rustup component add rust-src              # needed for `-Z build-std` etc.
rustup component add rust-analyzer

# Run a command under a specific toolchain
rustup run nightly cargo build
# Or shorthand:
cargo +nightly build
```

### docs.rs feature inspection

Before adding a dependency, check its feature matrix:
`https://docs.rs/crate/<name>/latest/features`. Shows every feature flag,
what deps each pulls in, and which are default — faster than reading
`Cargo.toml` on GitHub.

---

## §8. sccache — shared compilation cache

`sccache` (Mozilla) caches `rustc` invocations and serves cache hits
transparently. The standard activation:

```bash
cargo install sccache              # or: cargo binstall sccache
export RUSTC_WRAPPER=sccache
cargo build
sccache --show-stats               # cache hit rate, requests, errors
```

Set per-shell (recommended for agent isolation) or persistently in
`.cargo/config.toml`:

```toml
[build]
rustc-wrapper = "sccache"
```

### What sccache caches

- `rustc` compilation of a single crate (the input is the source files +
  the full set of compiler flags + the dep graph hashes).

### What it does NOT cache

- The final link step (each output binary is rebuilt locally).
- Build-script outputs (`build.rs` runs each invocation).
- Incremental compilation artifacts (sccache and incremental are
  largely independent caches; both can be on simultaneously).
- `cargo check` to the same extent as `cargo build` — `check` already
  skips codegen, so the win is smaller.

### Backends

| Backend | Use case | Env var setup |
|---|---|---|
| Local disk (default) | Single developer, single machine. | `SCCACHE_DIR=/var/cache/sccache` `SCCACHE_CACHE_SIZE=10G` |
| Shared S3 | Team or CI cluster with overlapping dep graphs. | `SCCACHE_BUCKET=team-cache` `SCCACHE_REGION=us-east-1` + AWS creds |
| Shared Redis | Lower-latency than S3 for hot dep graphs. | `SCCACHE_REDIS_ENDPOINT=redis://cache.internal:6379` |
| Multi-level | Disk-then-Redis-then-S3 chain; warm tier becomes the L0 cache. | `SCCACHE_MULTILEVEL_CHAIN=disk,redis,s3` plus per-level env |

### Concurrency safety

sccache handles its own internal locking — multiple cargo invocations
(across parallel agents, CI runners, or git worktrees) can use the same
cache simultaneously without coordination. This is why it pairs well
with the parallel-agent build workflow in §9.

### When the payoff is high

- Multiple agents/workspaces share the same dependency graph (the deps
  compile once, then every other agent hits cache).
- CI cold starts where ~80% of build time is third-party deps.
- Frequent `cargo clean` cycles (sccache survives `clean`; `target/`
  does not).

### When it's not worth setting up

- Single-developer single-workspace flow with stable deps. Incremental
  compilation already covers most of the win.
- Tiny dep graphs (<10 crates total). The wrapper overhead can dominate.

---

## §9. Parallel-agent build workflows

When multiple agents run concurrently in the same workspace (or in git
worktrees derived from it), cargo's file locking and CPU saturation are
the primary failure modes. This section covers the isolation and
throttling patterns that keep agents from deadlocking or overwhelming
the machine.

### The core problem: `target/` contention

Cargo holds a file lock on `target/` during any build operation. Two
agents pointing at the same `target/` simultaneously produce one of
three outcomes:

1. **Silent wait** — cargo queues; looks like a hang.
2. **Error** — `could not acquire package cache lock`.
3. **Artifact corruption** — rare but possible with a partial write
   racing a read.

The fix is always: **give each agent its own `target/` directory.**

### Isolation via `CARGO_TARGET_DIR`

```bash
# Pattern 1: branch-scoped target (recommended for git worktrees)
export CARGO_TARGET_DIR="$(git rev-parse --show-toplevel)/target-$(git rev-parse --abbrev-ref HEAD | tr '/' '-')"
cargo check -p my-bots

# Pattern 2: /tmp ephemeral (transient agent tasks; no residue after reboot)
export CARGO_TARGET_DIR="/tmp/my-target-agent-$(date +%s)"
cargo check -p my-node --features serve,native

# Pattern 3: named lane path (for conductor-dispatched sprint lanes)
export CARGO_TARGET_DIR="/tmp/my-target-lane-A"
cargo check -p my-engine --features full
```

**Never set `CARGO_TARGET_DIR` globally in `~/.cargo/config.toml`** — it
would redirect the main session's builds too. Set it per-agent shell or
per-invocation.

### Worktree isolation (git worktree + per-worktree target)

Git worktrees share the repository object store but give each branch
its own working tree. Combined with a per-worktree `CARGO_TARGET_DIR`,
agents get full isolation:

```bash
# Create a worktree for a lane
git worktree add /tmp/wt-lane-a feature/lane-a

# In the worktree shell — set a unique target dir
cd /tmp/wt-lane-a
export CARGO_TARGET_DIR=/tmp/target-lane-a
cargo check -p my-bots --features full
```

The worktree shares `Cargo.lock` and the workspace `Cargo.toml` from the
main checkout, so dep versions stay consistent across lanes.

### Throttle cargo's internal parallelism

`cargo check` spawns N compilation threads where N = logical CPU count.
On a 16-core machine, 4 agents each running full-workspace checks spawn
64 threads — 4× capacity. Pass `-j` to limit:

```bash
# Rule of thumb: floor(total_cores / num_simultaneous_agents)
# 8 cores, 4 agents → -j 2 per agent
cargo check -p my-node --features serve,native -j 2
```

Or via env (applies to all cargo invocations in the shell):

```bash
export CARGO_BUILD_JOBS=2
```

### Prefer crate-scoped checks over `--workspace`

`cargo check --workspace` compiles every crate. An agent touching only
`crates/bots/` doesn't need to check `bin/gui/` or `crates/math/`. Scope
the check to affected crates:

```bash
# Agent modifying my-bots and my-engine only:
cargo check -p my-bots -p my-engine --features full

# Agent modifying bin/node:
cargo check -p my-node --features serve,native

# Wave-gates are the ONLY time the full workspace check runs:
cargo check --workspace --features full           # workspace gate
cargo check -p my-node --features serve,native   # node gate
cargo check -p my-worker --features serve         # worker gate
```

### Wave-gate vs. in-lane checks

| Context | Command | Parallelism |
|---|---|---|
| **In-lane validation** (agent verifying its own changes) | `cargo check -p <crate> -j N` with per-agent `CARGO_TARGET_DIR` | Full parallel — all agents concurrent |
| **Wave-gate** (conductor validating all lanes) | Canonical gates, one at a time, main `target/` | Serial — cargo-serial doctrine |
| **Pre-commit / pre-push hook** | `cargo check -p <changed_crate>` | Fast, scoped, single invocation |

The cargo-serial doctrine applies to **wave-gates only**. Coders run
`cargo check` freely inside their own lane.

### Shared compiler cache

See §8 for full sccache setup. The headline: `export RUSTC_WRAPPER=sccache`
in every agent shell. sccache's internal locking is safe across concurrent
agents; redundant compilations of shared deps turn into cache hits.

### Canonical parallel-agent shell preamble

Paste this at the top of every agent shell invocation — sets isolation
and throttling, cleans up on exit:

```bash
set -euo pipefail
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null | tr '/' '-')
export CARGO_TARGET_DIR="/tmp/my-target-${BRANCH}-$$"   # $$ = PID for uniqueness
export CARGO_BUILD_JOBS=2                                # tune: floor(cores / agents)
export RUSTC_WRAPPER=sccache                             # share dep compilations
trap "rm -rf ${CARGO_TARGET_DIR}" EXIT                   # cleanup ephemeral target
```

`trap ... EXIT` ensures no multi-GB artifact directories accumulate in
`/tmp` after agent sessions complete.

---

## §10. Machine-readable output

When an agent or CI pipeline needs to parse cargo's output programmatically
(count errors, extract spans, gate on zero-error exit), use
`--message-format=json`.

### The JSON output schema

Each line of cargo's stderr is a JSON object. The `reason` field
discriminates record types:

| `reason` | When emitted | Useful fields |
|---|---|---|
| `compiler-message` | rustc emits a diagnostic. | `message.level` (`"error"`/`"warning"`/`"note"`/`"help"`), `message.message`, `message.spans[]`, `message.rendered` (pre-rendered ANSI string). |
| `compiler-artifact` | cargo finished building a crate. | `target.name`, `target.kind[]`, `filenames[]` (paths to produced artifacts), `fresh` (bool — cache hit?). |
| `build-script-executed` | A `build.rs` ran. | `package_id`, `linked_libs[]`, `linked_paths[]`, `cfgs[]`, `env[]`. |
| `build-finished` | Build complete. | `success` (bool). The terminal record. |

### Common extraction patterns

```bash
# Extract only errors (drop warnings and notes)
cargo check --message-format=json 2>&1 \
  | jq -c 'select(.reason == "compiler-message" and .message.level == "error")'

# Count errors across the workspace
cargo check --workspace --message-format=json 2>&1 \
  | jq -c 'select(.reason == "compiler-message" and .message.level == "error")' \
  | wc -l

# Get the path of every produced binary
cargo build --release --message-format=json 2>&1 \
  | jq -r 'select(.reason == "compiler-artifact" and (.target.kind | contains(["bin"]))) | .filenames[]'

# Detect dirty (non-fresh) recompiles — diagnostic for cache miss
cargo build --message-format=json 2>&1 \
  | jq -c 'select(.reason == "compiler-artifact" and .fresh == false) | .target.name'

# Simplest binary-pass/fail gate (exit code only)
cargo check -p my-crate --features full -j 2 >/dev/null 2>&1 && echo PASS || echo FAIL

# Pre-rendered ANSI output preserved (useful for re-displaying)
cargo check --message-format=json-diagnostic-rendered-ansi 2>&1 \
  | jq -r 'select(.reason == "compiler-message") | .message.rendered'
```

### `cargo metadata` for static workspace inspection

For dep graph and workspace introspection without compiling:

```bash
# Full workspace structure as JSON
cargo metadata --format-version=1 --no-deps | jq '.workspace_members'

# Resolve every dependency (slow — fetches the full graph)
cargo metadata --format-version=1 | jq '.packages[] | {name, version}'

# Find the path to a specific package
cargo metadata --format-version=1 --no-deps \
  | jq -r '.packages[] | select(.name == "my-crate") | .manifest_path'
```

`cargo metadata` is the right tool for tooling (linters, ci scripts,
graph analyzers) — it does not invoke rustc.

---

## Source attribution

Operational facts in this file were sourced from:

- **The Cargo Book** — `https://doc.rust-lang.org/cargo/` (Context7 ID:
  `/websites/doc_rust-lang_cargo`).
- **sccache documentation** — `https://github.com/mozilla/sccache`
  (Context7 ID: `/mozilla/sccache`).
- Per-subcommand: `https://docs.rs/<crate>/latest/` and each crate's
  `README.md`.

When a fact here disagrees with the canonical source, the canonical
source wins. Open an issue or correct this file.
