---
name: formatter-conflict-resolution
description: Resolve merge conflicts caused by formatter differences during cherry-pick or rebase. Works for any language with a configured formatter. Instead of manually resolving formatting hunks, check out the conflicting files unformatted, run the formatter, then verify.
---

# Formatter Conflict Resolution

When a cherry-pick or rebase step conflicts because the source and target branches have different formatting (e.g., a `treewide: run nix fmt` commit was merged between them), do not manually resolve the formatting hunks.

## Procedure

### 1. Accept the incoming content, discard formatting

For each conflicting file, check out the version from the commit being applied (theirs during cherry-pick, the rebased commit during rebase):

```bash
# During rebase: take the commit's version
git checkout --theirs <file>

# During cherry-pick: take the cherry-picked commit's version
git checkout --theirs <file>
```

If the conflict mixes semantic changes with formatting, and `--theirs` would lose semantic changes from HEAD, use `--ours` instead and let the formatter fix the style.

### 2. Run the formatter

Run the project's formatter on the conflicting files:

```bash
# Nix
nix fmt -- <file>

# Or for other languages, use the project's configured formatter
```

The formatter produces the correct style for the target branch regardless of which version was checked out.

### 3. Stage and verify

```bash
git add <file>
```

Before continuing the rebase or cherry-pick, spawn a haiku-class agent to verify the resolution:

```
Verify this formatter conflict resolution did not mangle semantic content:
- File: <file>
- Operation: <rebase step N of M / cherry-pick of <hash>>
- The file was checked out from <ours/theirs> and reformatted.

Run these checks:
1. Diff the resolved file against HEAD (pre-conflict). Identify every
   non-whitespace difference. Each one must correspond to a semantic
   change from the incoming commit — if any HEAD semantic content is
   missing from the resolved file, the resolution LOST content.
2. Diff the resolved file against the incoming commit's version.
   Every semantic change from that commit must be present — if any
   is missing, the resolution DROPPED the commit's intent.
3. If EITHER check fails, report the lost content and ABORT. Do not
   continue the rebase.
```

The verification agent must **abort the rebase** if semantic content was lost. Formatting-only differences are expected and safe. Any behavioral difference — added lines, removed lines, changed identifiers, altered logic — is a failure that requires manual resolution.

### 4. Continue

```bash
git rebase --continue
# or
git cherry-pick --continue
```

## When to use

- Conflict markers contain only whitespace, indentation, or line-wrapping differences
- The conflict is between a formatted and unformatted version of the same semantic content
- A `treewide: run <formatter>` commit was merged between the source and target branches

## When NOT to use

- The conflict involves semantic changes (new code, removed code, renamed identifiers)
- Both sides of the conflict have different semantic content that happens to also differ in formatting — in that case, resolve semantics first, then format
