---
name: nixpkgs-source-research
description: Research nixpkgs source code using the WSL nix store, nix eval, git blame, and GitHub permalinks. Produces citable findings with pinned commit hashes and line numbers.
---

# nixpkgs Source Research

## When to use

When investigating NixOS module behavior, option defaults, build logic, or upstream implementation details. The goal is **citable findings** — every claim backed by a permalink to the exact line in the exact revision.

## 1. Find the pinned nixpkgs revision

The flake.lock pins the exact nixpkgs commit. Extract it:

```bash
# From the repo's flake.lock
jq -r '.nodes.nixpkgs.locked.rev' flake.lock
```

This hash is the basis for all GitHub permalink URLs:

```
https://github.com/NixOS/nixpkgs/blob/<rev>/<path>#L<start>-L<end>
```

Never use `master` or `main` in permalink URLs — those move. Always use the pinned rev.

## 2. Read source from the WSL nix store

The nix store contains the full nixpkgs source tree. Locate it:

```bash
wsl.exe -- bash -c "find /nix/store -maxdepth 1 -name '*nixos*' -type d | head -5"
```

Then read files directly. The nixpkgs tree structure:

```
/nix/store/<hash>-nixos/nixos/
├── modules/
│   ├── installer/cd-dvd/     # ISO image builders
│   ├── hardware/             # Hardware detection
│   ├── profiles/             # base.nix, minimal.nix, etc.
│   ├── tasks/filesystems/    # Filesystem support modules
│   ├── system/boot/          # Boot, initrd, LUKS
│   ├── image/                # image.* options (file-options.nix, images.nix)
│   └── misc/                 # version.nix, nixos options
├── lib/
│   ├── make-iso9660-image.nix  # ISO derivation builder
│   ├── make-iso9660-image.sh   # xorriso invocation
│   └── eval-config.nix         # lib.nixosSystem internals
```

## 3. Evaluate live config values

Use `nix eval` to check what values options actually resolve to:

```bash
# Simple attribute
wsl.exe -- bash -c "cd ~/nixos-hosts && nix eval .#nixosConfigurations.<name>.config.<path>"

# Multiple attributes at once
wsl.exe -- bash -c "cd ~/nixos-hosts && nix eval --apply 'x: {
  a = x.config.foo;
  b = x.config.bar;
}' .#nixosConfigurations.<name>"
```

For image variant configs, the derivation attributes are accessible but `.config` is not (the image is a derivation, not a NixOS system):

```bash
# Image variant — use derivation attrs directly
nix eval --apply 'x: { isoName = x.isoName; volumeID = x.volumeID; }' \
  .#nixosConfigurations.<name>.config.system.build.images.<variant>
```

## 4. Determine option priority

When overriding upstream options, check how they are set:

| Assignment style | Priority | Override with |
|---|---|---|
| `option.default = ...` in option declaration | 1500 | Bare assignment (100) or `mkDefault` (1000) |
| `mkDefault value` in config | 1000 | Bare assignment (100) |
| Bare `option = value` in config | 100 | `mkForce` (50) or `mkOverride N` with N < 100 |
| `mkForce value` in config | 50 | `mkOverride N` with N < 50 |

Two modules setting the same option at the same priority (e.g., both bare) is a conflict error.

## 5. Trace provenance with git blame

For understanding *why* an option exists or has a particular default:

```bash
# GitHub blame UI (use pinned rev, not master)
https://github.com/NixOS/nixpkgs/blame/<rev>/<path>

# Or via gh CLI for recent commits touching a file
gh api "repos/NixOS/nixpkgs/commits?path=<path>&per_page=5" \
  --jq '.[] | "\(.sha[0:7]) \(.commit.message | split("\n")[0]) (\(.commit.author.date[0:10]))"'
```

Then fetch the commit for full context:

```bash
# Commit message + diff
https://github.com/NixOS/nixpkgs/commit/<sha>
```

## 6. Search for usage patterns

Verify intended usage by finding who sets an option across nixpkgs:

```bash
# GitHub code search via CLI
gh search code "makeEfiBootable = true" --repo NixOS/nixpkgs --limit 20

# Sourcegraph (broader, cross-repo)
https://sourcegraph.com/search?q=context:global+repo:NixOS/nixpkgs+<pattern>&patternType=standard
```

## 7. Construct permalink citations

Every finding must include a permalink. Format:

```markdown
[`option-name` L<start>-L<end>](https://github.com/NixOS/nixpkgs/blob/<rev>/<path>#L<start>-L<end>)
```

For blame-traced commits:

```markdown
[`<sha-short>`](https://github.com/NixOS/nixpkgs/commit/<sha>) (<author>, <date>): <message>
```

## Checklist

Before reporting findings:

- [ ] All source citations use the pinned nixpkgs rev, not `master`
- [ ] Option priorities identified (bare vs mkDefault vs option default)
- [ ] Live values confirmed via `nix eval`
- [ ] Usage patterns checked (who else sets this option?)
- [ ] Blame traced for non-obvious defaults or behaviors
