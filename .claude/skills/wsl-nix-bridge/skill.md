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

The bridge uses a WSL-native clone of the same repository, connected via bidirectional git remotes. Nix operations run in a dedicated git worktree inside `.claude/worktrees/` on the WSL clone — never on the main working tree.

### Prerequisites

- A clone of the repository exists at `~/nixos-hosts` inside WSL (distro: `NixOS`)
- The Windows git config includes `safe.directory` entries for the WSL path:
  ```
  git config --global --add safe.directory '//wsl$/NixOS/home/jacob/nixos-hosts'
  ```

### Adding remotes (once per clone)

From the Windows worktree, add a remote pointing to the WSL clone:

```
git remote add wsl '//wsl$/NixOS/home/jacob/nixos-hosts'
```

From the WSL clone, add a remote pointing to the Windows worktree:

```
git remote add windows '/mnt/c/Users/Jacob/Projects/nixos-hosts'
```

Both sides can now push and pull directly using native filesystem translation.

### Creating a WSL worktree (once per branch)

Mirror the Windows worktree branch into a `.claude/worktrees/` directory on the WSL clone:

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts && git worktree add .claude/worktrees/<name> <branch-name>'
```

All nix operations happen in this WSL worktree. The user's main WSL working tree is never touched.

## Workflow

### Windows → WSL: push via temporary branch

Direct `git push wsl <branch>` fails with `receive.denyCurrentBranch` when the branch is checked out in a WSL worktree. Work around this by pushing to a temporary ref, then fast-forwarding the worktree.

From the Windows worktree:

```
git push wsl +HEAD:refs/heads/tmp/bridge-sync
```

Then update the WSL worktree and run nix commands:

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts/.claude/worktrees/<name> && git merge --ff-only tmp/bridge-sync && <nix command>'
```

If the WSL worktree has local commits that Windows doesn't (e.g., a nix-generated lockfile commit), rebase instead:

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts/.claude/worktrees/<name> && git rebase tmp/bridge-sync'
```

Clean up the temporary branch after syncing:

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts && git branch -d tmp/bridge-sync'
```

If the WSL worktree doesn't exist yet, create it first (see Setup).

Common nix operations:

- `nix eval .#<attr>` — evaluate an attribute (verify config)
- `nix flake lock` — regenerate lockfile after input changes
- `nix build .#<target>` — build a derivation
- `nix fmt` — format with the flake's formatter

### WSL → Windows: fetch and fast-forward

```
git fetch wsl <branch-name>
git merge wsl/<branch-name> --ff-only
```

Always use `--ff-only` to avoid divergent histories.

### Bringing nix-generated files back to Windows

When nix modifies files (e.g., `flake.lock`), prefer copying via the UNC mount:

```
cp '//wsl$/NixOS/home/jacob/nixos-hosts/.claude/worktrees/<name>/flake.lock' flake.lock
git add flake.lock
```

This keeps commits on the Windows side with the correct identity and co-author trailers. Only commit from WSL when necessary (e.g., if the nix command produces many scattered file changes).

## Pitfalls

### Git Bash path mangling

When invoking `wsl -d NixOS -- bash -c '...'` from Git Bash, absolute Linux paths starting with `/` are rewritten (e.g., `/nix/store/...` becomes `C:/Program Files/Git/nix/store/...`). Use a heredoc so the shell content is interpreted inside WSL:

```
wsl -d NixOS -- bash <<'WSL'
RESULT=$(nix build .#foo --no-link --print-out-paths)
"$RESULT/bin/foo"
WSL
```

### Updating branches checked out in worktrees

`git branch -f <branch> origin/<branch>` fails if that branch is checked out in a worktree. Update from inside the worktree instead:

```
wsl -d NixOS -- bash -c 'cd ~/nixos-hosts/.claude/worktrees/<name> && git merge --ff-only origin/<branch>'
```

## Syncing WSL branches

When syncing WSL branches with origin, always rebase — never `git reset --hard origin/<branch>`. Rebase surfaces conflicts between unpushed local work and origin; reset silently discards local commits.

```bash
# correct: rebase preserves local work
git rebase origin/<branch>

# wrong: reset destroys unpushed commits
git reset --hard origin/<branch>
```

## Notes

- The `+` prefix in the push refspec force-updates the temp branch, which is safe since it exists only for synchronization.
- Commits made from WSL will use WSL's git identity — ensure it matches or amend afterward.
- This bridge is bidirectional: changes flow Windows → WSL via temp branch push, and WSL → Windows via `fetch`/`ff-only`.
