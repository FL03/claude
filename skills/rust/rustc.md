---
name: rustc
description: |
  Practical rustc reference for the daily-driver knobs that change build
  output: codegen flags, RUSTFLAGS precedence, target triples and tiers,
  lint levels and groups, editions, sanitizers, conditional compilation,
  --print queries, and useful debug flags. Companion to the rust skill —
  open this when the task involves compiler behavior beyond what cargo
  exposes directly.
type: reference
version: 5.1.0
---

# rustc — Practical Compiler Knobs

This file covers what an engineer needs to drive rustc (usually through
cargo) without reading the full Rustc Book. Every flag here is sourced
from **The Rustc Book** (`https://doc.rust-lang.org/rustc/`), **The Rust
Reference** (`https://doc.rust-lang.org/reference/`), or the **Unstable
Book** for nightly-only flags — not memory.

Compiler internals (MIR/HIR phases, the pass pipeline, the borrow
checker's internal stages) are out of scope. See the Rustc Dev Guide at
`https://rustc-dev-guide.rust-lang.org/` for those.

---

## §1. Invocation basics

Most rustc work happens through `cargo` — cargo computes the right flags
from `Cargo.toml`, the active profile, and `.cargo/config.toml`, then
invokes rustc once per crate. Direct rustc is for:

- **One-off scripts:** `rustc script.rs && ./script` is faster than
  setting up a cargo project.
- **Inspecting codegen:** when you need `--emit=llvm-ir` or `--emit=asm`
  for a specific source file (see §10).
- **Debugging cargo:** `cargo build -vv` shows the exact rustc command
  cargo invoked — useful when reproducing a build outside cargo.
- **Build-script targets:** rare, but `build.rs` sometimes shells out to
  rustc directly.

### Flag groups

| Group | Flag prefix | Purpose | Stability |
|---|---|---|---|
| Codegen | `-C` | Influence the generated code (opt level, LTO, target CPU). | Stable |
| Lints | `-W`/`-A`/`-D`/`-F` | Set lint levels (warn/allow/deny/forbid). | Stable |
| Emit | `--emit` | Choose what artifacts to produce (`link`, `metadata`, `llvm-ir`, `asm`, `mir`, `dep-info`). | Stable |
| Print | `--print` | Query the compiler (target list, cfg, sysroot, etc.). | Stable |
| Unstable | `-Z` | Nightly-only experimental flags. | Unstable |

`rustc -C help`, `rustc -W help`, `rustc -Z help` (nightly) print the full
flag inventory for each group.

---

## §2. Codegen flags (`-C`)

Passed to rustc as `-C <flag>=<value>`. Through cargo, they're set via
`[profile.<name>]` in `Cargo.toml` or `[build] rustflags = [...]` /
`[target.<triple>] rustflags = [...]` in `.cargo/config.toml`. See the
Rustc Book chapter "Codegen options" for the authoritative list:
`https://doc.rust-lang.org/rustc/codegen-options/index.html`.

| Flag | Valid values | Effect |
|---|---|---|
| `opt-level` | `0`, `1`, `2`, `3`, `s`, `z` | 0 = no optimization (default for `dev`); 1 = basic; 2 = some; 3 = all (default for `release`); `s` = size-optimized; `z` = aggressive size optimization. |
| `lto` | `false`/`off`, `true`/`fat`, `thin`, `n`/`y` | Link-time optimization across crates. `thin` is the recommended balance (close to `fat` quality, much faster). Default is local thin LTO on the current crate only. |
| `codegen-units` | integer > 0 | Splits a crate into N parallel LLVM units. Higher = faster compile but potentially slower output. Defaults: 16 (non-incremental), 256 (incremental). Set to `1` for max-quality release builds (slower compile). |
| `panic` | `unwind`, `abort`, `immediate-abort` | Panic strategy. `abort` produces smaller binaries and forbids `catch_unwind`. `immediate-abort` skips drop glue too. Must be set workspace-wide; mixing `unwind` and `abort` crates fails to link. |
| `strip` | `none`, `debuginfo`, `symbols`, `true`/`false` | Strip at link time. `symbols` strips both debug info and the symbol table — smallest binaries. |
| `debuginfo` | `0`/`none`, `1`/`limited`, `2`/`full`, `line-tables-only` | Debug info generation. Default: 2 for `dev`, 0 for `release`. `line-tables-only` gives backtraces with line numbers but no variable inspection — cheap and useful for release. |
| `target-cpu` | CPU name, `native`, `generic` | Codegen for a specific CPU. `native` = host CPU (binary won't run on older hardware). List options with `rustc --print target-cpus`. |
| `target-feature` | `+<feat>` / `-<feat>` comma-separated | Enable or disable specific ISA features (e.g., `+avx2`, `+bmi2`). Marking some features `+` is `unsafe` — the binary will SIGILL on hardware that lacks them. List with `rustc --print target-features`. |
| `incremental` | path to directory | Cache compilation state between invocations for faster rebuilds. Cargo manages this automatically; rarely set directly. |
| `link-arg` | string | Append one argument to the linker invocation. Repeat for multiple. Common: `-C link-arg=-fuse-ld=lld` to use the LLD linker. |
| `link-args` | quoted string | Multiple args as a single space-separated string. Less common than repeating `link-arg`. |
| `relocation-model` | `static`, `pic`, `pie`, `dynamic-no-pic`, `ropi`, `rwpi`, `ropi-rwpi`, `default` | Position-independence model. Default is `pic` for hosted targets; `static` is common for bare-metal/embedded. |
| `code-model` | `tiny`, `small`, `kernel`, `medium`, `large` | Address-range model. `small` is default for most targets. `large` for binaries that exceed 2GB address space. |
| `force-frame-pointers` | `true`, `false` | Force omission/inclusion of frame pointers. Default depends on the target; set `true` when profiling tools need stack walks. |
| `overflow-checks` | `true`, `false` | Enable runtime integer-overflow checks. Default: true in `dev`, false in `release`. |
| `linker` | path to linker binary | Use a non-default linker. Cargo's `[target.<triple>] linker = "..."` is the normal way to set this. |

Per-crate codegen-units overrides for release:

```toml
[profile.release]
codegen-units = 1                 # max optimization, slowest compile

[profile.release.package."*"]
codegen-units = 16                # restore default for deps
```

This pattern optimizes the local crate fully without paying the linker
cost for every transitive dep.

---

## §3. RUSTFLAGS — sources & precedence

`RUSTFLAGS` is the env-var path to set rustc flags for an entire cargo
invocation. The Cargo Book documents the precedence order at
`https://doc.rust-lang.org/cargo/reference/config.html#buildrustflags`.

### Where rustc flags can be set

Cargo collects rustc flags from up to five sources. It uses **only the
highest-priority source that has flags set** — sources do not merge:

1. `--config 'build.rustflags=["..."]'` on the cargo command line.
2. `RUSTFLAGS` environment variable.
3. `[target.<triple>] rustflags` in `.cargo/config.toml`. All matching
   triple/cfg sections merge.
4. `[target.<cfg>] rustflags` in `.cargo/config.toml` (cfg-keyed sections).
5. `[build] rustflags` in `.cargo/config.toml`.

The highest-priority source with a non-empty value wins; the rest are
ignored. Surprisingly common mistake: setting `RUSTFLAGS` in CI clobbers
`.cargo/config.toml` rustflags entirely.

### Common RUSTFLAGS values

```bash
# Treat all warnings as errors
export RUSTFLAGS="-D warnings"

# Compile for the host CPU (only run on identical hardware)
export RUSTFLAGS="-C target-cpu=native"

# Use the LLD linker for faster link times
export RUSTFLAGS="-C link-arg=-fuse-ld=lld"

# Combine multiple flags (space-separated in env)
export RUSTFLAGS="-D warnings -C target-cpu=native -C link-arg=-fuse-ld=lld"
```

### Per-target rustflags in config.toml

The clean way to keep flags survivable across CI/local without env-var
fragility:

```toml
# .cargo/config.toml
[build]
rustflags = ["-D", "warnings"]    # workspace-wide, applies to host builds

[target.x86_64-unknown-linux-gnu]
rustflags = ["-C", "link-arg=-fuse-ld=lld"]

[target.aarch64-apple-darwin]
rustflags = ["-C", "target-cpu=apple-m1"]

[target.'cfg(target_arch = "wasm32")']
rustflags = ["-C", "target-feature=+bulk-memory,+sign-ext"]
```

Each flag is its own array element. Don't pack multiple flags into one
string (`["--D warnings"]` is wrong; use `["-D", "warnings"]`).

### Cache-busting gotcha

Changing `RUSTFLAGS` invalidates the entire incremental cache for the
current target. Toggling `RUSTFLAGS` between `cargo check` runs forces a
full recompile each time — surprising on first encounter. To avoid this
in a dual-mode workflow, use distinct `CARGO_TARGET_DIR` paths per flag
profile.

---

## §4. Target triples & tiers

A target triple is the platform identifier for codegen. The canonical
form is `<arch>-<vendor>-<os>-<env>`. The Rustc Book's "Platform Support"
page is the authoritative tier list:
`https://doc.rust-lang.org/rustc/platform-support.html`.

### Anatomy

- **arch:** instruction set (`x86_64`, `aarch64`, `riscv64gc`, `wasm32`, `thumbv7em`, ...).
- **vendor:** `unknown`, `apple`, `pc`, `fortanix`, etc. Often opaque
  metadata; some targets care.
- **os:** `linux`, `darwin`, `windows`, `none` (bare metal), `wasi`, `fuchsia`, `android`.
- **env:** the C/system ABI variant: `gnu`, `musl`, `msvc`, `eabi`,
  `eabihf`, `wasip2`. Optional — some triples omit it.

### Tier system

| Tier | Guarantee | Host tools | Notes |
|---|---|---|---|
| **Tier 1 with Host Tools** | Guaranteed to work; tested every change. | Yes — can run `rustc` + `cargo` on the target. | The safest deploy targets. |
| **Tier 1** | Same as above; today every Tier 1 has host tools. | (Currently equivalent.) | — |
| **Tier 2 with Host Tools** | Guaranteed to build; tested less aggressively. | Yes. | Suitable for production but verify on a representative machine. |
| **Tier 2 without Host Tools** | Std library + `core` guaranteed to build; tests not always run. | No. | Most cross-compile targets; WASM lives here. |
| **Tier 3** | Codebase has support, but no automated build or test. | No. | May or may not work; ride at your own risk. |

### Canonical triples by tier

| Triple | Tier | Use case |
|---|---|---|
| `x86_64-unknown-linux-gnu` | Tier 1 + Host | Linux servers, the default development target. |
| `aarch64-unknown-linux-gnu` | Tier 1 + Host | ARM64 Linux (AWS Graviton, Raspberry Pi 4+). |
| `aarch64-apple-darwin` | Tier 1 + Host | Apple Silicon macOS. |
| `x86_64-apple-darwin` | Tier 2 + Host | Intel macOS. |
| `x86_64-pc-windows-msvc` | Tier 1 + Host | Native Windows (links MSVC C runtime). |
| `x86_64-pc-windows-gnu` | Tier 1 + Host | Windows via MinGW (links GCC C runtime). |
| `x86_64-unknown-linux-musl` | Tier 2 + Host | Static Linux binaries (no glibc dependency). |
| `aarch64-unknown-linux-musl` | Tier 2 + Host | Static ARM64 Linux. |
| `wasm32-unknown-unknown` | Tier 2 | Browser-side WASM via `wasm-bindgen`. |
| `wasm32-wasip1` | Tier 2 | Server-side WASM (WASI Preview 1; legacy). |
| `wasm32-wasip2` | Tier 2 | WASM Component Model (current preferred WASI target). |
| `thumbv7em-none-eabi` | Tier 2 | Cortex-M4/M7 bare-metal embedded (no_std). |

### Managing targets with rustup

```bash
# What's installed?
rustup target list --installed

# Add a target (downloads the std/core library for it)
rustup target add wasm32-wasip2
rustup target add aarch64-unknown-linux-musl

# Remove
rustup target remove wasm32-unknown-unknown
```

A target's `std` is only available if it's been added. Building for an
uninstalled target produces `can't find crate for 'std'`.

### Cross-compilation essentials

For most Tier 2 cross-compiles, you need three pieces:

1. **`rustup target add <triple>`** — fetches `core`/`std` for the target.
2. **`[target.<triple>] linker = "..."`** in `.cargo/config.toml` —
   points cargo at a cross-linker (e.g., `aarch64-linux-gnu-gcc`).
3. **Optional `runner = "..."`** — qemu wrapper for `cargo run`/`cargo test`.

Tools like `cross` (`cargo install cross`) automate this by running the
build inside a containerized cross-toolchain. Worth it for anything
beyond linux-musl.

### Inspecting targets

```bash
rustc --print target-list                # every supported triple
rustc --print target-spec-json --target wasm32-wasip2  # full spec JSON
rustc --print cfg --target wasm32-wasip2  # the cfg flags this target sets
rustc --print target-cpus                 # for the current target
rustc --print target-features             # for the current target
```

---

## §5. Lints

Rust ships hundreds of lints organized into categories called groups.
The Rustc Book lists them at `https://doc.rust-lang.org/rustc/lints/`.

### Lint levels

| Level | Effect | Set via |
|---|---|---|
| `allow` | Suppress reporting entirely. | `#[allow(<lint>)]`, `-A <lint>` |
| `warn` | Report a warning; compile continues. | `#[warn(<lint>)]`, `-W <lint>` (default for most) |
| `expect` | Expect the lint to fire here; warn if it doesn't (catches drift). | `#[expect(<lint>)]` |
| `deny` | Report an error; compile fails. | `#[deny(<lint>)]`, `-D <lint>` |
| `forbid` | Same as `deny` AND any inner `#[allow]` is rejected. | `#[forbid(<lint>)]`, `-F <lint>` |

`forbid` is the only level downstream code cannot override. Use it for
project-wide invariants like `unsafe_code`.

### Built-in lint groups

| Group | What it catches |
|---|---|
| `warnings` | All lints currently at `warn` level (the catch-all). |
| `unused` | Unused imports, vars, results, mut, lifetimes, etc. |
| `future-incompatible` | Code that compiles today but is scheduled to break. |
| `nonstandard-style` | `non_camel_case_types`, `non_snake_case`, `non_upper_case_globals`. |
| `rust-2018-idioms` | Suggestions to modernize 2015-era code. |
| `rust-2021-compatibility` | Migration helpers for the 2021 edition. |
| `rust-2024-compatibility` | Migration helpers for the 2024 edition. |
| `let-underscore` | Wildcard `let _ = ...` that drops important values (e.g., `MutexGuard`). |
| `refining-impl-trait` | Trait impls that narrow an `impl Trait` return type. |
| `deprecated-safe` | Functions retroactively marked `unsafe`. |

A group name in `-W`/`-D`/etc. is equivalent to listing every lint it
contains.

```bash
# CI gate: every warning is an error
RUSTFLAGS="-D warnings" cargo check --workspace
# Or via clippy (broader lint set):
cargo clippy --workspace --all-features -- -D warnings
```

### `--cap-lints`

`--cap-lints <level>` caps every lint in the current invocation at that
level. Cargo automatically passes `--cap-lints allow` when compiling
third-party dependencies — that's why warnings in your deps don't break
your build. The Rustc Book documents this at
`https://doc.rust-lang.org/rustc/lints/levels.html#capping-lints`.

### Centralized lint config (Rust 2024+)

```toml
# [workspace] or [package] Cargo.toml
[lints.rust]
unsafe_code = "deny"
missing_docs = "warn"

[lints.clippy]
all = "warn"
pedantic = "warn"
```

Cleaner than `#![deny(...)]` at every crate root.

---

## §6. Editions

An edition is an opt-in language version that may introduce
backwards-incompatible changes (new keywords, new defaults, new
desugarings). All editions interop at the crate level — a 2015 crate can
depend on a 2024 crate and vice versa.

```toml
[package]
edition = "2024"          # opt this crate in
```

### Edition summary

| Edition | Headline changes |
|---|---|
| **2015** | The original. No keyword reservation; no `dyn` keyword; older module/path rules. |
| **2018** | `async`/`await` keywords reserved. Cleaner module path system (no `extern crate` needed for deps). `dyn Trait` syntax (vs bare `Trait`). |
| **2021** | Disjoint closure captures (closures borrow only the fields they touch). `IntoIterator` for arrays (`for x in [1,2,3]`). Or-patterns inside macro fragment specifiers. New prelude items (`TryFrom`, `TryInto`, `FromIterator`). Reserved syntax `#"..."#`. |
| **2024** | New RPIT lifetime capture rules (return-position `impl Trait` now captures all in-scope lifetimes by default — use `use<>` to scope). Never-type fallback to `!` instead of `()`. `unsafe` attributes (`unsafe(no_mangle)`). `gen` blocks for iterator generators. Refined `if let` temporary scope. New prelude items. |

### Migrating editions

```bash
# Automated migration (recommended starting point)
cargo fix --edition --allow-dirty --allow-staged

# Update Cargo.toml edition = "2024"
# Then run the optional idiom cleanup (post-migration warnings)
cargo fix --edition-idioms
```

`cargo fix` applies most lints automatically. Some cases require manual
intervention — the tool tells you which. The `--edition-idioms` pass is
optional cleanup that nudges code toward the new edition's preferred
style.

The full migration guide:
`https://doc.rust-lang.org/edition-guide/editions/transitioning-an-existing-project-to-a-new-edition.html`.

---

## §7. Sanitizers

Compile-time instrumentation that traps memory bugs, races, and CFI
violations at runtime. **Nightly only.** The Unstable Book chapter is
`https://doc.rust-lang.org/unstable-book/compiler-flags/sanitizer.html`.

### Enabling

```bash
# Pattern: RUSTFLAGS env + nightly + --target
export RUSTFLAGS="-Zsanitizer=address"
cargo +nightly run -Zbuild-std --target x86_64-unknown-linux-gnu
```

`--target` is required to avoid instrumenting build scripts and proc
macros (they run on the host). `-Zbuild-std` rebuilds `core` and `std`
with the sanitizer enabled — without it, calls into std are blind spots.

### Testing-only sanitizers

| Sanitizer | Catches | Common targets |
|---|---|---|
| `address` | Heap/stack OOB, use-after-free, double-free, leaks. | linux-gnu, apple-darwin (x86_64 + aarch64), fuchsia. |
| `hwaddress` | Same as address but lower memory overhead (uses hardware tagging). | aarch64-linux-gnu, aarch64-linux-android. |
| `leak` | Memory leaks at process exit. | linux-gnu, apple-darwin (x86_64). |
| `memory` | Reads from uninitialized memory. | linux-gnu, freebsd. |
| `thread` | Data races in multithreaded code. | linux-gnu, apple-darwin (x86_64 + aarch64). |

Run these in test/fuzzing CI — they slow execution 2–10× and aren't
production-safe.

### Production-hardening sanitizers

| Sanitizer | Protection | Notes |
|---|---|---|
| `cfi` | Control-Flow Integrity: forward-edge call verification. | Requires LTO; pair with `-Clinker-plugin-lto`. |
| `kcfi` | CFI variant designed for kernel use. | Linux kernel modules. |
| `safestack` | Backward-edge protection by splitting safe/unsafe stack regions. | x86_64-linux-gnu only. |
| `shadow-call-stack` | Backward-edge protection via shadow stack for return addresses. | aarch64-linux-android, aarch64-fuchsia. |
| `memtag` | Armv8.5-A memory-tagging extension. | aarch64-linux-gnu, aarch64-linux-android. |

These add modest overhead and are suitable for shipped binaries when the
target platform supports them.

---

## §8. Conditional compilation (`cfg`)

The `cfg` predicate language gates code at compile time on target
properties, feature flags, and custom user flags. Defined in **The Rust
Reference** at
`https://doc.rust-lang.org/reference/conditional-compilation.html`.

### `#[cfg(...)]` attribute vs `cfg!(...)` macro

```rust
// Attribute — compile-time gate; code is removed entirely when false
#[cfg(target_os = "linux")]
fn linux_only() { ... }

// Macro — runtime expression that evaluates to a bool at compile time
let is_linux = cfg!(target_os = "linux");
```

The attribute *deletes* the item when the condition is false; the macro
keeps the surrounding code but evaluates to a constant.

### Predicate atoms

| Predicate | Examples | Notes |
|---|---|---|
| `feature = "..."` | `cfg(feature = "json")` | Cargo features. Set when the feature is enabled. |
| `target_os = "..."` | `linux`, `macos`, `windows`, `ios`, `android`, `freebsd`, `none` | The target OS. |
| `target_arch = "..."` | `x86_64`, `aarch64`, `wasm32`, `arm`, `riscv64` | Instruction set. |
| `target_pointer_width = "..."` | `"32"`, `"64"` | Pointer size; useful for portable hash/index code. |
| `target_endian = "..."` | `"little"`, `"big"` | Byte order. |
| `target_env = "..."` | `"gnu"`, `"musl"`, `"msvc"` | Linkage environment. |
| `target_family = "..."` | `"unix"`, `"windows"`, `"wasm"` | Coarser-grained than `target_os`. |
| `panic = "..."` | `"unwind"`, `"abort"` | Active panic strategy. |
| `debug_assertions` | (boolean — no value) | Set when `cfg(debug_assertions)` — default in `dev` profile, off in `release`. |
| `test` | (boolean) | Set when compiling tests. |
| `unix` / `windows` | (boolean shortcuts) | Equivalent to `target_family = "unix"` / `"windows"`. |
| `<custom>` | `cfg(my_flag)` | Custom — set via `--cfg my_flag` (rustc) or `[build] rustflags = ["--cfg", "my_flag"]`. |

### Combinators

```rust
#[cfg(all(unix, target_pointer_width = "64"))]
#[cfg(any(target_os = "linux", target_os = "macos"))]
#[cfg(not(feature = "no-std")))]
```

### `cfg_attr` — conditionally apply an attribute

```rust
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
struct Config { ... }
```

The attribute applies only when the predicate is true. Useful for
feature-gated derives without doubling the struct definition.

### `--check-cfg` — prevent typo-driven dead code

A `#[cfg(my_flagg)]` with a typo silently disables the code forever.
`--check-cfg` makes rustc warn when an unknown cfg name or value is
referenced:

```toml
# Cargo.toml
[lints.rust]
unexpected_cfgs = { level = "warn", check-cfg = ['cfg(my_flag, values("a", "b"))'] }
```

Cargo automatically check-cfgs all declared `[features]` since Rust 1.80
— typos in `cfg(feature = "...")` are now warnings by default.

---

## §9. `--print` queries

`rustc --print <query>` returns metadata about the compiler or active
target. No compilation happens; output goes to stdout. Useful in build
scripts, CI bootstrap, and quick diagnostic checks.

| Query | What you get |
|---|---|
| `cfg` | All cfg flags the active target sets (`target_os="..."`, `target_arch="..."`, `unix`, etc.). |
| `target-list` | Every supported target triple. |
| `target-spec-json` | Full target-spec JSON for `--target <triple>`. Use with custom-target work. |
| `sysroot` | The Rust installation root. |
| `target-libdir` | Where the target's libstd lives. |
| `rustc-commit-hash` | The git SHA of the rustc build. |
| `rustc-commit-date` | When this rustc was built. |
| `host-tuple` | The triple of the machine rustc is running on. |
| `target-cpus` | All CPU options valid for `-C target-cpu` on the current target. |
| `target-features` | All feature options valid for `-C target-feature`. |
| `code-models` | All values valid for `-C code-model`. |
| `relocation-models` | All values valid for `-C relocation-model`. |
| `crate-name` | Resolves the crate name from `Cargo.toml`/source. |
| `file-names` | Output file names for the current crate. |

Examples:

```bash
# What cfg flags does the wasi target set?
rustc --print cfg --target wasm32-wasip2

# What CPUs can I target on macOS?
rustc --print target-cpus

# Where is the std library installed?
rustc --print sysroot
ls "$(rustc --print sysroot)/lib/rustlib/$(rustc -vV | sed -n 's/host: //p')/lib"
```

The full query list:
`https://doc.rust-lang.org/rustc/command-line-arguments.html#--print-print-compiler-information`.

---

## §10. Debug & profiling flags

When a compile is slow, a binary is fat, or a type is mysteriously huge,
these flags expose what rustc is doing.

### `--emit` — choose output artifacts

```bash
# Show LLVM IR for the current crate
rustc --emit=llvm-ir my.rs

# Show generated assembly (after optimization)
rustc -C opt-level=3 --emit=asm my.rs

# Show MIR (rustc's mid-level IR) — useful for understanding borrow checking
rustc --emit=mir my.rs

# Multiple emits at once
rustc --emit=llvm-ir,asm,link my.rs
```

Through cargo:

```bash
# Forces a rebuild; emits go alongside normal artifacts in target/
cargo rustc -- --emit=llvm-ir
```

### `cargo build -v` / `-vv`

```bash
cargo build -v       # show the rustc commands cargo invokes
cargo build -vv      # also show stderr from invoked tools (linkers, build scripts)
```

`-v` is the right starting point when "why is my flag not applying" —
you see what cargo actually passed.

### `-Z time-passes` (nightly)

```bash
cargo +nightly rustc -- -Z time-passes 2>&1 | sort -k2 -nr | head
```

Prints how long each compilation pass took. The output shape changes
across rustc versions; check `rustc +nightly -Z time-passes --help`.

### `-Z print-type-sizes` (nightly)

```bash
cargo +nightly rustc --release -- -Z print-type-sizes 2>&1 \
  | sort -k2 -nr | head -50
```

Shows the size and alignment of every type the crate uses. Essential for
embedded targets and for noticing accidental `Box<dyn Trait>` blowups.

### `-Z self-profile` (nightly)

```bash
cargo +nightly rustc -- -Z self-profile -Z self-profile-events=default
# Outputs a `<crate>-<pid>.mm_profdata` file
# Visualize with `measureme`:
cargo install measureme
crox <crate>-<pid>.mm_profdata > flame.json
# Open flame.json in chrome://tracing or perfetto
```

The most precise way to find which queries dominate compile time.

### Quick reference card

| Goal | Flag |
|---|---|
| See the rustc command line cargo invoked. | `cargo build -v` |
| Strip optimization and re-emit IR. | `RUSTFLAGS="-C opt-level=0" cargo rustc -- --emit=llvm-ir` |
| Find the biggest types in your crate. | `cargo +nightly rustc -- -Z print-type-sizes` |
| Find which pass dominates. | `cargo +nightly rustc -- -Z time-passes` |
| Find which item dominates. | `cargo +nightly rustc -- -Z self-profile` |
| Check what cfg flags are active. | `rustc --print cfg` |
| Find max optimization (slow). | `[profile.release] lto = "fat" codegen-units = 1` |
| Find smallest binary. | `[profile.release] opt-level = "z" strip = "symbols" lto = "fat"` |

---

## Source attribution

Operational facts in this file were sourced from:

- **The Rustc Book** — `https://doc.rust-lang.org/rustc/` (canonical
  reference for codegen options, lints, and `--print` queries).
- **The Rust Reference** — `https://doc.rust-lang.org/reference/`
  (canonical reference for `cfg` predicates and editions; Context7 ID
  `/rust-lang/reference`).
- **The Rust Edition Guide** —
  `https://doc.rust-lang.org/edition-guide/` (canonical edition
  transition material).
- **The Unstable Book** —
  `https://doc.rust-lang.org/unstable-book/` (`-Z` flags and
  sanitizers).

When a fact here disagrees with the canonical source, the canonical
source wins. Open an issue or correct this file.
