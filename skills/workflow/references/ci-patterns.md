---
type: reference
parent: workflow
---

# CI/CD Workflow Patterns (Rust Workspace Projects)

Reference templates for Rust workspace CI. Derived from the production
pzzld-rs implementation; the axiom family of workspaces follows these
patterns. **Drop-in starting point — adapt names, matrices, and registry
secrets to the project.**

This file is the template library. The skill's SKILL.md §V lists the
workflow set and the standing patterns; this file ships the YAML.

> Note: this marketplace itself uses only `release.yml` (see SKILL.md §IV) —
> it has no compilable code. The patterns below are for Rust workspaces.

## Standard Workflow Header

```yaml
name: Workflow Name

on:
  pull_request:
    branches: [main, master]
    types: [synchronize]
  push:
    branches: [main, master, "releases/**/*"]
    tags: [latest, "v*", "*-nightly"]
  repository_dispatch:
    types: [workflow-name]
  workflow_dispatch:
    inputs:
      features:
        default: full
        description: Feature flags
        required: false
        type: string
      target:
        default: x86_64-unknown-linux-gnu
        description: Target triple
        required: false
        type: string
      toolchain:
        default: stable
        description: Rust toolchain
        required: false
        type: string

concurrency:
  cancel-in-progress: false
  group: ${{ github.workflow }}-${{ github.ref }}

env:
  CARGO_TERM_COLOR: always
  RUST_BACKTRACE: full

permissions:
  contents: read
```

## Clippy (cargo-clippy.yml)

Must trigger on PRs. Upload SARIF to GitHub code scanning.

```yaml
permissions:
  actions: read
  contents: read
  security-events: write
  statuses: write

jobs:
  clippy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          components: clippy
          toolchain: stable
      - run: cargo clippy --workspace --features full --message-format=json | clippy-sarif | tee results.sarif | sarif-fmt
        continue-on-error: true
      - uses: github/codeql-action/upload-sarif@v3
        if: ${{ github.event.repository.public }}
        with:
          sarif_file: results.sarif
          wait-for-processing: true
```

## Test (cargo-test.yml)

Two jobs: stable + nightly. Nightly tests no_std and alloc combos.

```yaml
jobs:
  stable:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        features: [full, default]
        target: [x86_64-unknown-linux-gnu]
        toolchain: [stable]
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          toolchain: ${{ matrix.toolchain }}
      - run: cargo build --release --features ${{ matrix.features }} --target ${{ matrix.target }}
      - run: cargo test --workspace --features ${{ matrix.features }} --target ${{ matrix.target }}

  nightly:
    if: github.event_name == 'workflow_dispatch'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        target: [x86_64-unknown-linux-gnu]
        features: [all, no_std, "alloc,nightly"]
        package: [axiom-core, axiom-traits]
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          toolchain: nightly
      - run: cargo test -p ${{ matrix.package }} --features ${{ matrix.features }} --target ${{ matrix.target }}
```

## Build (cargo-build.yml)

Two jobs: native std builds + WASM component builds.

```yaml
jobs:
  std:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        features: [full, default]
        target: [x86_64-unknown-linux-gnu]
        toolchain: [stable]
    steps:
      - uses: actions/checkout@v4
      - run: sudo apt-get update && sudo apt-get install -y pkg-config libssl-dev build-essential
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          toolchain: ${{ matrix.toolchain }}
          target: ${{ matrix.target }}
      - run: cargo build --release --features ${{ matrix.features }} --target ${{ matrix.target }}

  components:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        target: [wasm32-wasip2]
        package: [axiom-btc, axiom-sports, axiom-weather]
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
        with:
          toolchain: stable
          target: ${{ matrix.target }}
      - run: cargo build --release -p ${{ matrix.package }} --target ${{ matrix.target }}
```

## Publish (cargo-publish.yml)

Sequential publishing to crates.io. Order matters — dependencies first.

```yaml
on:
  release:
    types: [published]
  workflow_dispatch: {}

jobs:
  publish:
    runs-on: ubuntu-latest
    strategy:
      max-parallel: 1
      matrix:
        package:
          # SDK crates in dependency order
          - axiom-traits
          - axiom-math
          - axiom-core
          - axiom-config
          - axiom-circuits
          - axiom-drivers
          - axiom-watch
          - axiom-sim
          - axiom-engine
          - axiom-bot
          - axiom-cron
          - axiom
          # Clients
          - rschainlink
          - rspm
          - erspn
          - rsupa
          - rsclaude
    steps:
      - uses: actions/checkout@v4
      - uses: actions-rust-lang/setup-rust-toolchain@v1
      - run: cargo publish -p ${{ matrix.package }} --token ${{ secrets.CARGO_REGISTRY_TOKEN }}
        continue-on-error: true
```

## Release (release.yml)

Generate release notes and append crates.io/docs.rs links.

```yaml
on:
  release:
    types: [published]
  workflow_dispatch:
    inputs:
      draft:
        default: true
        type: boolean
      prerelease:
        default: false
        type: boolean
      tag:
        required: true
        type: string

permissions:
  contents: write
  discussions: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: softprops/action-gh-release@v2
        with:
          append_body: true
          body: |
            ## Links
            - [crates.io](https://crates.io/crates/axiom)
            - [docs.rs](https://docs.rs/axiom)
          draft: ${{ github.event.inputs.draft || false }}
          generate_release_notes: true
          prerelease: ${{ github.event.inputs.prerelease || false }}
          tag_name: ${{ github.event.inputs.tag || github.ref_name }}
```

## Docker (docker.yml)

Multi-container builds. One matrix entry per Dockerfile.

```yaml
on:
  push:
    branches: [main, master]
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      registry:
        default: docker.io
        description: Container registry
        type: choice
        options:
          - docker.io
          - ghcr.io

jobs:
  docker:
    runs-on: ubuntu-latest
    strategy:
      max-parallel: 1
      matrix:
        include:
          - file: .docker/node.dockerfile
            image: jo3mccain/axiom-node
          - file: .docker/mcp.dockerfile
            image: jo3mccain/axiom-mcp
          - file: .docker/axiom.dockerfile
            image: jo3mccain/axiom-cli
          - file: .docker/app.dockerfile
            image: jo3mccain/axiom-ui
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ matrix.image }}
          tags: |
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
      - uses: docker/build-push-action@v6
        with:
          cache-from: type=gha
          cache-to: type=gha,mode=max
          file: ${{ matrix.file }}
          platforms: linux/amd64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

## Cleanup (cleanup.yml)

```yaml
on:
  pull_request:
    types: [closed]

jobs:
  cleanup:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "PR #${{ github.event.pull_request.number }} closed"
```

## Cross-references

- `SKILL.md §V` — the recommended workflow set and standing patterns.
- `rust/cargo.md §1` — `cargo build`, `cargo test`, `cargo clippy`, `cargo publish`
  command flags used by the matrices above.
- `rust/cargo.md §4` — feature gates and the `no_std`/`alloc`/`std` tier
  system referenced by the nightly test matrix.
- `rust/cargo.md §6` — registries and publishing (token setup, yanking,
  semver discipline) for the `cargo-publish.yml` flow.
