---
name: pr-merge-procedure
description: Procedures for finalizing and merging a set of PR branches. Two modes — batch (user-driven merge, agent rebases after each) and automatic (agent rebases all in planned order, then force-pushes). Use when the user says "merge PRs", "finalize branches", or asks to prepare branches for merge.
---

# PR Merge Procedure

## Batch mode (user-driven)

The user reviews and merges PRs one at a time. After each merge, the agent rebases all remaining branches onto the updated master to confirm that merged content disappears from diffs.

### Procedure

1. **Establish merge order.** List all open PRs and agree on the merge sequence. Independent PRs can go in any order; dependent PRs must follow their dependencies.

2. **User merges one PR.** The agent does not merge — the user clicks merge on GitHub or uses `gh pr merge`.

3. **Agent rebases remaining branches.**
   ```bash
   git fetch origin master
   # for each remaining PR branch:
   git checkout <branch>
   git rebase origin/master
   ```
   Commits from the just-merged PR should be skipped automatically (patch-id matching). If any branch shows conflicts or retains commits that should have been absorbed, stop and report before continuing.

4. **Agent verifies.**
   ```bash
   git log --oneline HEAD --not origin/master   # only branch-specific commits should remain
   git diff origin/master..HEAD --stat           # only branch-specific files should differ
   ```

5. **Agent pushes if clean.**
   ```bash
   git push origin <branch> --force-with-lease
   ```
   Only force-push after verifying the rebase is clean. If anything looks wrong, report to the user and wait.

6. **Repeat** from step 2 until all PRs are merged.

### When to use

- The user wants to review each PR before merging
- PRs have complex interdependencies that need human judgment
- The merge order is not fully determined in advance

## Automatic mode (agent-driven rebase)

The agent rebases all PR branches in a predetermined order, then force-pushes each one. This prepares all PRs for conflict-free merging in sequence. Requires strict merge order agreed in advance.

### Procedure

1. **Agree on merge order.** The user specifies the exact sequence. The agent confirms the order and any dependencies.

2. **Fetch and rebase in order.**
   ```bash
   git fetch origin master
   ```
   For each branch in merge order:
   ```bash
   git checkout <branch>
   git rebase origin/master   # or rebase onto previous branch if stacking
   ```
   After each rebase, verify:
   ```bash
   git log --oneline HEAD --not origin/master
   git diff origin/master..HEAD --stat
   ```

3. **Force-push all branches.**
   ```bash
   git push origin <branch> --force-with-lease
   ```
   Push in merge order. Each push is verified before the next.

4. **Report.** List each branch with its commit count and diff stat. The user merges them in the agreed order.

### When to use

- All PRs are reviewed and approved
- The merge order is fixed and agreed
- The user wants hands-off preparation for a merge sequence

### Constraints

- **Strict order required.** If PR B depends on PR A, A must be rebased and merged first. Rebasing B before A merges produces incorrect results.
- **No merging.** The agent prepares branches but does not merge. The user or CI merges.
- **Abort on conflict.** If any rebase produces conflicts that don't auto-resolve, stop and report. Do not resolve conflicts silently in automatic mode — that requires user judgment.

## After all merges

Sync all clones (WSL, Windows worktrees) by fetching origin and rebasing local branches. Delete merged branches only after verifying content reached master (see `branch-rebase` skill).
