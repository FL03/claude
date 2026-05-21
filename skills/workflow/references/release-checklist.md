---
type: reference
parent: workflow
---

# Release Checklist

Pre-flight checklist for the squash-merge that fires `.github/workflows/release.yml`.
Pairs with SKILL.md §IV. **Read the workflow file itself if anything below
disagrees with reality — release.yml is canonical.**

> **Mental model.** The pipeline does almost all of the historical "release
> dance" automatically (tag, GH release, next patch branch, version bumps,
> dev.0, orphan sweep, milestone roll). Your job is to (a) ensure the inputs
> are clean and (b) verify the outputs landed.

---

## Phase A — On the patch branch `v{x}.{y}.{z}` (before squash)

### A.1 — All sprints merged into the patch branch

```bash
gh pr list --state open --base "v{x}.{y}.{z}"
# Should be empty. If not, finish or close the open sprint PRs first.

git fetch --prune origin
git branch -r | rg "v{x}.{y}.{z}-dev\."
# Any remote dev branches still around? They'll be swept by step 10
# of release.yml, but it's cleaner to merge or close them now.
```

### A.2 — `CHANGELOG.md` has a `## v{x}.{y}.{z}` section

```bash
rg "^## v{x}.{y}.{z}( |$)" CHANGELOG.md
```

**This is the hardest hard requirement.** Step 3 of release.yml extracts the
notes by `awk`-slicing this exact header. Missing or misspelled → the entire
pipeline fails with `::error::No '## v{CURRENT}' section found in CHANGELOG.md`.

The section runs from `## v{x}.{y}.{z}` to (but not including) the next
`## v...` header.

### A.3 — `.claude-plugin/plugin.json` `version` matches the patch

```bash
jq -r '.version' .claude-plugin/plugin.json
# Must equal "{x}.{y}.{z}". If not, step 1 (detect) will skip the run with
# a ::warning::, and you'll need to fix the mismatch and re-dispatch.
```

This is normally set automatically when the previous release cut this patch
branch — only intervene if you renumbered manually.

### A.4 — Quality gates (project-shaped)

**This marketplace (docs-only):**

```bash
./scripts/install.sh --status                # sanity-check installer
rg -l '^---$' skills/*/SKILL.md              # frontmatter present
jq -e '.version' skills/*/plugin.json        # every plugin.json parses
```

**Rust workspace project:**

```bash
cargo fmt --all --check
cargo clippy --workspace --features full -- -D warnings
cargo test  --workspace --features full
cargo doc   --workspace --features full --no-deps
```

### A.5 — Version consistency (Rust workspace projects only)

```bash
grep '^version' Cargo.toml
cargo metadata --no-deps --format-version=1 \
  | jq -r '.packages[] | "\(.name) \(.version)"' \
  | awk -v v="{x}.{y}.{z}" '$2 != v {print "MISMATCH: "$0}'
```

---

## Phase B — The release squash-merge

```bash
# Open the PR (if not already open — the previous release cut it as a draft)
gh pr edit "v{x}.{y}.{z}" --base main
gh pr ready "v{x}.{y}.{z}"

# Or create from scratch if needed:
gh pr create --base main --head "v{x}.{y}.{z}" \
  --title "v{x}.{y}.{z}" \
  --body "$(cat <<'EOF'
## Summary
- Release v{x}.{y}.{z}

## Changes
[auto-generated from squashed commits]
EOF
)"

# Squash-merge — this is what fires release.yml
gh pr merge "v{x}.{y}.{z}" --squash
```

**Title convention.** Bare `v{x}.{y}.{z}` (preferred) or `release: v{x}.{y}.{z}`.
gh appends ` (#N)` on squash — release.yml's regex tolerates that suffix.

---

## Phase C — Verify the pipeline ran (post-squash)

```bash
# Watch the run
gh run list --workflow=release.yml --limit 3
gh run watch                                  # interactive, optional

# Verify each output landed
gh release view "v{x}.{y}.{z}"                # step 5: GH release exists
git fetch --prune origin && git tag --list "v{x}.{y}.{z}"   # step 4: tag exists
gh pr view "v{next}"                          # step 8: draft PR for next patch
git branch -r | rg "v{next}-dev\.0"           # step 9: dev.0 branch present
gh issue list --milestone "v{next}"           # step 11: issues rolled forward
```

If a step failed mid-pipeline:

```bash
# Inspect logs
gh run view <run-id> --log-failed

# Fix the root cause on main (or by hand for one-shot fixes)
# Then re-dispatch:
gh workflow run release.yml --ref main
```

Every step is **idempotent** — re-runs skip already-done work. Safe by design.

---

## Phase D — Crates.io publication (Rust workspace projects only)

The mechanical pipeline above handles the GitHub side. For Rust workspaces,
the `release` event on `cargo-publish.yml` then sequentially publishes each
crate to crates.io:

```bash
# Watch publish progress
gh run list --workflow=cargo-publish.yml --limit 1

# Spot-check on crates.io (takes a few minutes per crate)
# https://crates.io/crates/<name>

# Docker images, if tag-triggered
docker pull jo3mccain/axiom-node:{x}.{y}.{z}

# Fly.io deploy, if applicable (manual dispatch)
gh workflow run fly-io.yml
```

---

## Phase E — Manual cleanup (rare)

The pipeline handles tag/release/branches/milestones/version-bumps. The only
manual tasks are:

1. **Project-memory updates.** If conventions changed during the cycle, edit
   `CLAUDE.md` and any per-skill memories.
2. **External announcements.** Discord, Twitter, blog — not the pipeline's job.
3. **Major-version rollovers.** When `Z=9, Y=9` triggers a major bump, double-check
   the `v{X+1}.0.0` plan file exists at `.artifacts/plans/v{X+1}00.plan.md`.
   The pipeline cuts the branch but doesn't write the plan.

---

## What you NEVER do manually anymore

These were on the old checklist; release.yml owns them now. Doing them by
hand will collide with the pipeline:

- ~~`git tag v{x}.{y}.{z}` + `git push origin v{x}.{y}.{z}`~~ (step 4)
- ~~`gh release create v{x}.{y}.{z} --generate-notes`~~ (step 5)
- ~~Bumping `version` in `.claude-plugin/plugin.json`, `marketplace.json`, every `skills/*/plugin.json`, every `SKILL.md` frontmatter, and `README.md`~~ (step 6)
- ~~`git checkout -b v{next}`~~ (step 6)
- ~~`gh pr create --base main --head v{next} --draft`~~ (step 8)
- ~~`git checkout -b v{next}-dev.0`~~ (step 9)
- ~~`gh api .../milestones --method POST -f title="v{next}"`~~ (step 11)
- ~~`gh issue edit <N> --milestone "v{next}"` for each open issue~~ (step 11)
- ~~`git push origin --delete v{x}.{y}.{z}-dev.<i>` for each sprint~~ (step 10)
