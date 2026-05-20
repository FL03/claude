# Release Checklist

Step-by-step process for releasing a version. Execute in order — no skipping.

## Pre-Release (on version branch `v{x}.{y}.{z}`)

### 1. All phases merged

```bash
# Verify all dev branches are merged and closed
gh pr list --state open --head "v{x}.{y}.{z}-dev"
# Should return empty. If not, complete or close remaining phases.
```

### 2. Version consistency

```bash
# Workspace Cargo.toml version
grep '^version' Cargo.toml

# All crates must match
cargo metadata --no-deps --format-version=1 | python3 -c "
import json, sys
meta = json.load(sys.stdin)
for p in meta['packages']:
    if p['version'] != '${VERSION}':
        print(f'MISMATCH: {p[\"name\"]} = {p[\"version\"]}')"

# axiom.toml platform version
grep 'version' .axiom/config/axiom.toml
```

### 3. Quality gates

```bash
# Must all pass clean
cargo fmt --all --check
cargo clippy --workspace --features full -- -D warnings
cargo test --workspace --features full
cargo doc --workspace --features full --no-deps
```

### 4. Changelog / release notes

Review commits since last release:

```bash
git log v{prev}..HEAD --oneline
```

Draft release notes in the GH release body (done automatically by `--generate-notes`).

## Release

### 5. Squash merge into main

```bash
gh pr create --base main --head "v{x}.{y}.{z}" \
  --title "v{x}.{y}.{z}" \
  --body "$(cat <<'EOF'
## Summary
- Release v{x}.{y}.{z}

## Changes
[auto-generated from squashed commits]
EOF
)"

gh pr merge --squash
```

### 6. Tag and push

```bash
git checkout main
git pull origin main
git tag "v{x}.{y}.{z}"
git push origin "v{x}.{y}.{z}"
```

### 7. Create GitHub release

```bash
gh release create "v{x}.{y}.{z}" \
  --title "v{x}.{y}.{z}" \
  --generate-notes
```

This triggers:
- `release.yml` → appends crates.io/docs.rs links
- `cargo-publish.yml` → publishes to crates.io (sequential)
- `docker.yml` → builds and pushes Docker images (if tag-triggered)

### 8. Verify deployment

```bash
# Check workflow runs
gh run list --limit 5

# Verify crates.io publication
# (may take a few minutes for each crate)

# Verify Docker images
docker pull jo3mccain/axiom-node:latest

# Verify Fly.io (if auto-deployed)
# Otherwise trigger manually:
gh workflow run fly-io.yml
```

## Post-Release

### 9. Clean up version branch

```bash
# Should be auto-deleted by GH if using gh pr merge
# Verify:
gh api repos/{owner}/{repo}/branches | python3 -c "
import json, sys
for b in json.load(sys.stdin):
    if b['name'].startswith('v{x}.{y}.{z}'):
        print(f'STALE: {b[\"name\"]}')"
```

### 10. Close milestone

```bash
# Get milestone number
gh api repos/{owner}/{repo}/milestones | python3 -c "
import json, sys
for m in json.load(sys.stdin):
    if m['title'] == 'v{x}.{y}.{z}':
        print(m['number'])"

# Close it
gh api repos/{owner}/{repo}/milestones/{N} --method PATCH -f state=closed
```

### 11. Start next version

```bash
# Update workspace version
# Edit Cargo.toml: version = "{next}"
# Edit .axiom/config/axiom.toml if needed

# Create version branch
git checkout -b "v{next}"
git push -u origin "v{next}"

# Create first dev branch
git checkout -b "v{next}-dev.0"
git push -u origin "v{next}-dev.0"

# Create milestone
gh api repos/{owner}/{repo}/milestones --method POST -f title="v{next}"
```
