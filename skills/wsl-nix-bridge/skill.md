---
name: wsl-nix-bridge
description: Run nix commands from a WSL-native clone when working on Windows filesystem. Uses a git remote bridge between the Windows worktree and a WSL-local repo to avoid cross-filesystem git/nix path resolution failures.
---

# WSL Nix Bridge

When working on a NixOS flake repository from a Windows filesystem, `nix` commands fail because:

1. `nix` is not available natively on Windows
2. WSL cannot resolve git worktree metadata that uses Windows-style paths
3. `nix flake` commands require a valid git repository context

## Setup

The bridge uses a WSL-native clone of the same repository, connected as a git remote from the Windows side. Nix operations run in a dedicated git worktree inside `.claude/worktrees/` on the WSL clone — never on the main working tree.

### Prerequisites

- A clone of the repository exists at `~/nixos-hosts` inside WSL (distro: `NixOS`)
- The Windows git config includes `safe.directory` entries for the WSL path:
  ```
  git config --global --add safe.directory '//wsl$/NixOS/home/jacob/nixos-hosts'
  ```

### Adding the remote (once per Windows worktree)

From the Windows worktree:

```
git remote add wsl '//wsl$/NixOS/home/jacob/nixos-hosts'
```

### Creating a WSL worktree (once per branch)

Mirror the Windows worktree branch into a `.claude/worktrees/` directory on the WSL clone:

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts && git worktree add .claude/worktrees/<name> <branch-name>'
```

All nix operations happen in this WSL worktree. The user's main WSL working tree is never touched.

## Workflow

### 1. Push current state to WSL

From the Windows worktree:

```
git push wsl <branch-name>
```

### 2. Update and run nix commands in the WSL worktree

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts/.claude/worktrees/<name> && git pull && <nix command>'
```

If the WSL worktree doesn't exist yet, create it first (see Setup).

Common operations:

- `nix flake lock` — regenerate lockfile after input changes
- `nix flake check` — validate the flake
- `nix build .#<target>` — build a derivation
- `nix fmt` — format with the flake's formatter

### 3. Copy results back (preferred) or commit in WSL

When nix modifies files (e.g., `flake.lock`), prefer copying via the UNC mount:

```
cp '//wsl$/NixOS/home/jacob/nixos-hosts/.claude/worktrees/<name>/flake.lock' flake.lock
git add flake.lock
```

This keeps commits on the Windows side with the correct identity and co-author trailers. Only commit from WSL when necessary (e.g., if the nix command produces many scattered file changes).

### 4. If committed from WSL, fetch back

```
git fetch wsl <branch-name>
git merge wsl/<branch-name> --ff-only
```

Always use `--ff-only` to avoid divergent histories.

## Notes

- Commits made from WSL will use WSL's git identity — ensure it matches or amend afterward.
- This bridge is bidirectional: changes flow Windows → WSL via `push`, and WSL → Windows via `fetch`/`ff`.
