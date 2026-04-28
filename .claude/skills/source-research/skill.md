---
name: source-research
description: Research upstream source code with citable permalink evidence. General methodology for any GitHub-hosted dependency, plus nixpkgs-specific conventions.
---

# Source Research

## Principle

Every claim about upstream behavior must be backed by a permalink to the exact line in the exact revision. Never cite `master` or `main` — those move.

## 1. Pin the revision

Find the commit hash for the version of the dependency in use locally.

**Lock files:**

```bash
jq -r '.nodes.<input>.locked.rev' flake.lock         # Nix flakes
jq -r '.packages["<pkg>"].resolved' package-lock.json # npm
grep -A1 '<dep>' Cargo.lock | grep 'source'           # Rust (registry or git)
```

**Tags:** If the project uses semver tags, map the local version to a tag:

```bash
gh api "repos/<owner>/<repo>/git/refs/tags/v<version>" --jq '.object.sha'
```

**Installed copy:** When the source is available locally (nix store, node_modules, vendor/), read it directly — but still cite the pinned rev in permalinks.

## 2. Construct permalinks

```
https://github.com/<owner>/<repo>/blob/<rev>/<path>#L<start>-L<end>
```

For blame:

```
https://github.com/<owner>/<repo>/blame/<rev>/<path>#L<line>
```

For commits:

```markdown
[`<sha-short>`](https://github.com/<owner>/<repo>/commit/<sha>) (<author>, <date>): <message>
```

## 3. Trace provenance

Use git blame to understand *why* code exists, not just *what* it does:

```bash
# Recent commits touching a file
gh api "repos/<owner>/<repo>/commits?path=<path>&per_page=5" \
  --jq '.[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0]) (\(.commit.author.date[0:10]))"'
```

Then read the commit for full context (message, diff, linked PR).

## 4. Search for usage patterns

Confirm intended usage — check who else uses an API or sets a config value:

```bash
gh search code "<pattern>" --repo <owner>/<repo> --limit 20
```

## 5. Verify live behavior

After reading source, confirm with runtime checks. The source tells you what *should* happen; evaluation tells you what *does* happen. Discrepancies reveal overrides, conditionals, or version mismatches.

## Checklist

- [ ] Revision pinned — all permalinks use a specific commit, not a branch
- [ ] Live values confirmed (runtime evaluation matches source reading)
- [ ] Usage patterns checked (how does upstream or the ecosystem use this?)
- [ ] Blame traced for non-obvious defaults or behaviors

---

## Nix / nixpkgs

### Reading source

Resolve the exact store path for the flake's pinned nixpkgs:

```bash
wsl.exe -- bash -c "nix eval --raw nixpkgs#path"
```

This returns the store path matching the flake.lock revision. Read files directly from there. Common nixpkgs paths are documented in CLAUDE.md.

### Evaluating config

```bash
# Single attribute
nix eval .#nixosConfigurations.<name>.config.<path>

# Multiple attributes
nix eval --apply 'x: { a = x.config.foo; b = x.config.bar; }' \
  .#nixosConfigurations.<name>

# Image variant (derivation, not config — use drv attrs)
nix eval --apply 'x: { isoName = x.isoName; }' \
  .#nixosConfigurations.<name>.config.system.build.images.<variant>
```

### Module priority

| Assignment | Priority | Override with |
|---|---|---|
| `default = ...` in option declaration | 1500 | Bare (100) or `mkDefault` (1000) |
| `mkDefault value` | 1000 | Bare (100) |
| Bare `option = value` | 100 | `mkForce` (50) or `mkOverride N` (N < 100) |
| `mkForce value` | 50 | `mkOverride N` (N < 50) |

Same-priority conflict between two modules is an error.
