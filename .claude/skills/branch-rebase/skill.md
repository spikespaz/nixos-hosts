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

## Inserting a commit between existing commits

Use the `break` keyword in the interactive rebase todo list to pause between picks:

```bash
git rebase -i origin/master
```

In the todo editor, add `break` where the new commit should go:

```
pick abc1234 first commit
break
pick def5678 second commit
```

Git replays the first commit, then stops. You are on the branch (not detached HEAD), so create the new commit normally:

```bash
git add <files>
git commit -m "..."
git rebase --continue
```

This is cleaner than marking a commit as `edit` and committing during the edit step — `edit` is for modifying an existing commit, `break` is for inserting between them.

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

## Commit age and rebase scope

When rebasing, consider the age of commits being rewritten:

- **Commits older than 2 days:** Do not rebase. These represent solidified work with established timestamps that mark natural pauses, task switches, or review cycles. Rewriting them destroys timeline provenance.
- **Commits 1–2 days old:** Borderline. Ask the user before rebasing unless the rebase is onto a freshly merged upstream and the commits are clearly from the same work session.
- **Commits from the current session:** Safe to rebase freely.

The purpose of this rule is to preserve the natural timeline of work. Squashing a week of incremental commits into one destroys evidence of the development process — when pauses happened, when direction changed, when reviews occurred. Temporary commits (`f`, `s`, `r`, `d` prefixed) are an exception: they are explicitly marked for rebase regardless of age.

## Cascade rebase for stacked branches

When multiple branches form a linear chain (each forked from the previous), rebasing one branch requires rebasing every downstream branch. A rebase cascade is atomic — do not push until all branches in the chain are rebased and verified.

For each branch in order:

```bash
git checkout <branch>
git rebase <parent-branch>
git log --oneline HEAD --not <parent-branch>
```

If any branch becomes empty after rebase (all commits absorbed by upstream), its PR can be closed.

## Force-push rejection after external change

If `--force-with-lease` rejects a push, it means the remote branch changed since your last fetch. Do not use `--force` to bypass this — fetch first, then rebase onto the updated remote:

```bash
git fetch origin
git rebase origin/master   # or the appropriate upstream
git push origin <branch> --force-with-lease
```

`--force-with-lease` exists to prevent overwriting changes you haven't seen. Bypassing it with `--force` erases whatever changed on the remote without checking. Always fetch and rebase first — if the rebase is correct, `--force-with-lease` will succeed.

## Prefer rebase over manual cherry-picks

**Always use `git rebase` instead of reconstructing a branch from scratch with cherry-picks.** Rebase:

- Detects and skips duplicate commits automatically (patch-id matching)
- Stops on conflicts for incremental resolution
- Preserves commit metadata (author, date)
- Produces clean linear history

Manual cherry-pick reconstruction bypasses duplicate detection, forces you to manually select commits, and creates new objects for commits that are already upstream. The only case for manual cherry-picks is when you need to **edit** commit content during transfer (see `pr-minification-split`).

## Push before referencing commit SHAs

When commenting on GitHub PRs with commit hashes (e.g., "Fixed in abc1234"), push the branch to origin first. GitHub only autolinks SHAs that exist on the remote — unpushed local hashes render as plain text.

## Deleting merged branches

Before deleting a local branch after its PR merges, verify the content reached master. Use a dry-run rebase to check efficiently — if all commits are skipped (patch-id match), the content is on master:

```bash
git rebase origin/master --dry-run 2>&1   # not a real flag — use the count method below
```

Since git doesn't have `--dry-run` for rebase, compare commit counts before and after:

```bash
# count branch-only commits before rebase
git log --oneline <branch> --not origin/master | wc -l
# rebase
git rebase origin/master
# if all commits were skipped, the branch tip equals origin/master
git diff <branch> origin/master --stat
```

Empty diff and zero remaining commits confirms safe deletion. If any commits survive or the diff is non-empty, the branch has content not on master — ask the user before deleting.

## Rebase conflicts are not merge conflicts

In a merge, both sides are peers — you combine them. In a rebase, one side is the truth (the new base) and the other is being replayed onto it. Do not apply merge-conflict intuition to rebase conflicts.

When a rebase step conflicts:

1. **Check if it's a duplicate.** If the commit's changes already exist on the new base (from a prior merge or cherry-pick), skip it: `git rebase --skip`.
2. **Check if it's a formatting conflict.** If the only differences are whitespace or style, use the `formatter-conflict-resolution` skill.
3. **If it's a real semantic conflict**, the replayed commit needs adaptation to the new base. Take the base version (`--ours` in rebase context is the new base) and apply only the semantic change from the replayed commit. Do not try to "keep both sides" — that is merge thinking.
4. **If unsure, abort.** `git rebase --abort` and report. A wrong resolution silently corrupts history; aborting preserves it.

The most common mistake is treating a rebase conflict like a merge and manually combining both sides. This produces duplicate code, stale references, or mixed formatting. When in doubt, skip or abort — never guess.

### After any `--ours` or `--theirs` resolution

Taking one side wholesale discards the other side's changes. After resolving with `--ours` or `--theirs`, diff the resolved file against the discarded side to confirm nothing semantic was lost:

```bash
# After git checkout --ours <file>:
git diff REBASE_HEAD -- <file>   # shows what the replayed commit contributed
```

Every hunk in that diff is content you chose to discard. Verify each one is either a duplicate of what's already on the base, or something intentionally dropped. If any hunk contains a semantic change you didn't mean to lose, the resolution is wrong — amend before continuing.

## Never re-create changes manually

When a change needs to be moved, restored, or re-applied, always use `git cherry-pick` or `git rebase` — never re-type or re-apply the diff manually as a new commit. Cherry-pick and rebase surface merge conflicts explicitly; manual re-creation silently overwrites them, hiding divergence that should be resolved.
