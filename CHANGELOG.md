# Changelog

All notable changes to this skill marketplace are documented here. Each skill also maintains its version in its own `plugin.json`.

## v5.0.4 — unreleased

### Added
- `plugin.json` manifest for every skill, enabling independent versioning and marketplace installation
- `.claude-plugin/plugin.json` — repo-level plugin metadata
- `scripts/install.sh` — local skill installer for development workflow
- Marketplace restructured: `skills` → `plugins` array with per-skill `git-subdir` sources
- Marketplace renamed `fl03` → `fl03-skills` to avoid conflict with the shepherd marketplace

### Changed
- `.claude-plugin/marketplace.json` now lists all eight skills as individually installable plugins

---

## Skills

Individual skill versions are tracked in each skill's `plugin.json`.

| Skill | Version | Notes |
|---|---|---|
| finance | 1.0.0 | Initial versioned release |
| polymarket | 1.0.0 | Initial versioned release |
| rust | 4.1.0 | Continued from prior versioning |
| trader | 1.0.0 | Initial versioned release |
| typing | 1.0.0 | Initial versioned release |
| wasmtime | 1.0.0 | Initial versioned release |
| webassembly | 1.0.0 | Initial versioned release |
| workflow | 1.1.0 | Continued from prior versioning |
