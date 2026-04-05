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

3. **Agent fetches and checks all open branches.** Before rebasing any single branch, fetch origin and compare every open PR branch against the new master. This ensures no branch is missed.
   ```bash
   git fetch origin --prune
   # for each open PR branch:
   git log --oneline origin/<branch> --not origin/master | wc -l   # branch-only commit count
   git diff origin/master..origin/<branch> --stat                  # branch-only file changes
   ```
   Report the full picture before starting rebases. Rebase all affected branches, not just the one the user asked about.

4. **Agent rebases each branch.**
   ```bash
   git checkout <branch>
   git rebase origin/master
   ```
   Commits from the just-merged PR should be skipped automatically (patch-id matching). If any branch shows conflicts or retains commits that should have been absorbed, stop and report before continuing.

5. **Agent verifies.** Both checks are required — log for commit correctness, diff stat for file correctness.
   ```bash
   git log --oneline HEAD --not origin/master   # only branch-specific commits should remain
   git diff origin/master..HEAD --stat           # only branch-specific files should differ
   ```

6. **Agent pushes if clean.**
   ```bash
   git push origin <branch> --force-with-lease
   ```
   Only force-push after verifying the rebase is clean. If anything looks wrong, report to the user and wait.

7. **Agent checks PR title and body.** After every push, read the PR title, body, and checkboxes. Verify they match the current branch state — commit counts, file references, renamed identifiers, stale PR cross-references. Update automatically and notify the user of changes.

8. **Repeat** from step 2 until all PRs are merged.

These steps are a default sequence, not rigid. The user may jump to any step, skip steps, or invoke other skills (e.g., `pathwise-audit`, `wsl-nix-bridge`) mid-procedure. Follow the user's lead.

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

4. **Check PR titles and bodies.** After each push, verify the PR title, body, and checkboxes match the rebased branch state. Update automatically and notify the user of changes.

5. **Report.** List each branch with its commit count and diff stat. The user merges them in the agreed order.

### When to use

- All PRs are reviewed and approved
- The merge order is fixed and agreed
- The user wants hands-off preparation for a merge sequence

### Constraints

- **Strict order required.** If PR B depends on PR A, A must be rebased and merged first. Rebasing B before A merges produces incorrect results.
- **No merging.** The agent prepares branches but does not merge. The user or CI merges.
- **Abort on conflict.** If any rebase produces conflicts that don't auto-resolve, stop and report. Do not resolve conflicts silently in automatic mode — that requires user judgment.

## Interactive git history editing

The user may switch to rapid-fire chat mode to drive git history edits directly — rebases, rewords, reorders, drops. During this mode:

- **Policy check first.** Before executing any git operation — whether prompted by the user or planned by the agent — check the request against the policy documentation (`branch-rebase`, `wsl-nix-bridge`, `pathwise-commit`, this skill). If the request would violate a policy (e.g., manual re-creation instead of cherry-pick, reset instead of rebase, force-push without prior rebase), flag it before executing. This applies equally to user requests and agent plans.
- Stay responsive and brief. Confirm what was asked, flag problems immediately, no unsolicited elaboration.
- Execute exactly what the user asks. Do not batch or reinterpret multiple instructions into one operation.
- After each operation, report the result concisely (new commit list, conflict if any).
- PR text updates still apply — after any push during interactive editing, verify titles and bodies are still accurate.

## PR review process

PRs are reviewed bidirectionally — the user reviews agent work, and the agent reviews its own work (via pathwise-audit or spot-check). Review comments on GitHub must be attributable.

### Reading reviews

When reading PR reviews and comments, pay attention to timestamps. Comments may be stale if the branch has been force-pushed since the review was written.

GitHub reviews can be in a `PENDING` state — the user wrote comments but hasn't submitted the review yet. The GitHub API returns submitted reviews but not pending ones. If review threads appear empty or the user mentions they left comments that the agent cannot find, ask: "I don't see submitted review comments — do you have a pending review that needs to be submitted first?"

### Comment attribution

Every PR review comment must be signed with the author's initials or identity. When reviewing:

- The agent signs its comments using `<sub>` for small text and inline code for the checkout: `<sub>- Claude on \`<branch-or-worktree>\`</sub>`.
- The user signs their comments with their initials. If the user forgets, the agent edits the comment to append the user's initials.

This prevents ambiguity when multiple agents or the user leave comments on the same PR.

### Resolving threads after context breaks

After a context break, read all unresolved review threads. For each thread that claims to be fixed, verify the fixing commit exists on both the local branch and `origin/`. A SHA that is only local (not pushed) or only on origin (lost to a force-push) means the thread is not actually resolved. Flag before resolving.

### PR title and body maintenance

Keep PR titles and bodies current as content changes. Titles must reflect the actual commits on the branch — not what the branch had when the PR was opened. Bodies must accurately describe included and deferred content.

**Checkboxes:** Update test plan checkboxes incrementally as tests pass or fail. Prefer running checks after each relevant change rather than batching all checks at the end — incremental checks only need to be re-run when affected code changes. When checking or unchecking a box, notify the user of the change.

**Periodic checks during finalization:** During the merge procedure, verify titles and bodies after each rebase or force-push. Rebasing can change commit counts, drop absorbed commits, or surface new conflicts — the PR description must stay consistent with the branch state.

### Batch mode review cycle

1. Agent opens PR or pushes updates.
2. User reviews on GitHub — leaves comments, requests changes.
3. Agent reads review comments (`gh api`), addresses each one with a commit, replies with the fixing commit SHA, and resolves the thread.
4. User re-reviews. Cycle repeats until approved.
5. User merges. Agent rebases remaining branches (see batch mode above).

### Automatic mode review cycle

1. Agent runs pathwise-audit on each branch before presenting the merge order.
2. Agent fixes any issues found, pushes, and reports the audit results.
3. User reviews the audit report and the PR diffs. Approves or requests changes.
4. Once all approved, agent rebases in order and force-pushes (see automatic mode above).
5. User merges in the agreed sequence.

## After all merges

Sync all clones (WSL, Windows worktrees) by fetching origin and rebasing local branches. For WSL sync, follow the `wsl-nix-bridge` skill — rebase WSL branches (never reset), update worktree-checked-out branches from inside the worktree, use heredocs to avoid path mangling. Delete merged branches only after verifying content reached master (see `branch-rebase` skill).
