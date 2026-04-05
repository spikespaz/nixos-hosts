---
name: branch-rebase
description: Rebase PR branches onto upstream, split branches by topic, and recover from bad rebases. Default procedure for keeping branches current — not just for recovery.
---

# Branch Rebase

## Rebasing onto upstream

### 1. Fetch upstream (don't switch branches)

```bash
git fetch origin master
```

Do not `git checkout master && git pull` — fetch updates the remote tracking ref, which is all `rebase` needs.

### 2. Rebase

```bash
git rebase origin/master
```

Git automatically skips commits whose patch content already exists upstream (detected via `git patch-id`). Commits that were part of the branch but are now on master are dropped with a `skipped previously applied commit` warning. Only genuinely new commits are replayed.

If conflicts arise, git stops at each one:

```bash
# resolve conflicts in the file
git add <resolved-files>
git rebase --continue
```

### 3. Verify

```bash
git log --oneline HEAD --not origin/master   # should show only new commits
```

## Splitting a branch by topic

When a branch mixes two independent topics:

1. Rebase the full branch onto `origin/master` first (drops duplicates)
2. Create the second branch from the same base:
   ```bash
   git checkout -b <topic-b-branch> origin/master
   git cherry-pick <commits-for-topic-b>
   ```
3. Drop topic B commits from the original branch:
   ```bash
   git checkout <topic-a-branch>
   git rebase -i origin/master   # delete the topic-b lines
   ```

Both branches now cleanly extend master with only their own commits.

## Splitting a commit

When a commit bundles two independent changes (fails the "and" test), split it during interactive rebase:

```bash
git rebase -i origin/master   # mark the commit as 'edit'
```

When git stops at the commit:

```bash
git reset HEAD~1              # unstage the commit's changes
git add <files-for-concern-A>
git commit -m "..."
git add <files-for-concern-B>
git commit -m "..."
git rebase --continue
```

This replaces the single commit with two properly scoped ones. Works for any number of splits.

## Check worktree state before operating

Before rebasing, switching, or force-pushing a branch, verify which branches are checked out where:

```bash
git worktree list
git branch -vv
```

A branch checked out in a worktree cannot be updated from outside that worktree. Operations on the wrong worktree silently affect a different branch than intended.

## Diagnosing merge-base divergence

When a PR shows conflicts with its target branch:

```bash
git merge-base HEAD origin/master
git log --oneline HEAD --not origin/master   # branch-only commits
git log --oneline origin/master --not HEAD   # master-only commits
```

If the branch has commits that are content-identical to master but with different hashes (from a reorder, cherry-pick, or manual rebuild), `git rebase origin/master` resolves this automatically — the duplicates are detected and skipped.

## Recovery via reflog

When a rebase or manual operation has gone wrong:

```bash
git reflog <branch> --oneline -20
```

Find the state before the bad operation (typically before a `branch: Reset to` or unexpected `cherry-pick` sequence), then restore:

```bash
git checkout -B <branch> <good-ref>
```

The bad state remains in the reflog if you need it later.

## Prefer rebase over manual cherry-picks

**Always use `git rebase` instead of reconstructing a branch from scratch with cherry-picks.** Rebase:

- Detects and skips duplicate commits automatically (patch-id matching)
- Stops on conflicts for incremental resolution
- Preserves commit metadata (author, date)
- Produces clean linear history

Manual cherry-pick reconstruction bypasses duplicate detection, forces you to manually select commits, and creates new objects for commits that are already upstream. The only case for manual cherry-picks is when you need to **edit** commit content during transfer (see `pr-minification-split`).

## Deleting merged branches

Before deleting a local branch after its PR merges, verify the content reached master. GitHub merge strategies (squash, rebase) create different commit hashes, so check by diffing files — not by matching SHAs:

```bash
git diff <local-branch> origin/master -- <files-changed-by-branch>
```

Empty diff confirms the content is on master. If the diff is non-empty, the branch has unpushed work — ask the user before deleting.

## Never re-create changes manually

When a change needs to be moved, restored, or re-applied, always use `git cherry-pick` or `git rebase` — never re-type or re-apply the diff manually as a new commit. Cherry-pick and rebase surface merge conflicts explicitly; manual re-creation silently overwrites them, hiding divergence that should be resolved.
