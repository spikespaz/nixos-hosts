---
name: pr-minification-split
description: Split a PR branch into a minimal mergeable subset and a full branch. Use when a PR contains untested variants, blocked features, or scope that should ship incrementally. Produces a strict-subset branch with only the working/tested content, preserving infrastructure for future additions.
---

# PR Minification Split

You are splitting a PR branch into two: a **minimal branch** containing only the tested, working subset, and the **full branch** which retains everything. The minimal branch is a strict subset — once merged, the full branch rebases on top to add remaining content.

## When to use

- A PR has multiple variants/features but only some are tested or buildable
- Review feedback suggests shipping incrementally
- Build environment limitations block some configurations but not others
- The PR scope grew beyond what's mergeable in one pass

## Procedure

### 1. Identify the working subset

Determine which outputs are tested and passing. Everything else is deferred. Note which commits are:
- **Keep as-is**: prerequisites, infrastructure, tested features
- **Edit**: commits that mix tested and untested content
- **Drop**: commits that only touch untested features

### 2. Create the minimal branch

```bash
git checkout -b <branch>-minimal <base>
```

### 3. Cherry-pick each commit from the original

Walk the original branch commit-by-commit. For each commit, decide:

| Original commit | Action on minimal branch |
|----------------|------------------------|
| Pure prerequisite (inputs, shared config) | `cherry-pick` as-is |
| Adds a tested feature only | `cherry-pick` as-is |
| Adds an untested feature only | **Drop** |
| Mixes tested and untested | `cherry-pick --no-commit`, edit to remove untested content, commit |
| Modifies only untested features (labels, sizing, docs) | **Drop** |
| Infrastructure used by both tested and untested | `cherry-pick` as-is or edit to remove untested references |

When editing a cherry-pick:
- Remove untested variant configurations, but keep the infrastructure that enables future variants (factory functions, output patterns, file tree structure)
- Update documentation to only reference what's present
- Preserve commit message style — adjust the body to reflect the reduced scope, keep the same pathwise summary if it still fits

### 4. Handle conflicts from skipped context

Reordering or dropping commits may cause conflicts when later commits expect skipped content. Resolve by taking the minimal branch's state and applying only the relevant parts of the cherry-picked change.

### 5. Verify both branches

After splitting:
- **Minimal branch**: must eval/build independently. All referenced outputs exist.
- **Full branch**: unchanged. Still the complete PR.
- **Relationship**: `git diff <minimal-tip> <full-tip>` shows only the deferred content.

### 6. Create the minimal PR

Reference the full PR in the body. Explain:
- What's included and why (tested, buildable)
- What's deferred and where (full PR number)
- That the full PR will rebase on top once the minimal merges

## Principles

- **The minimal branch is the mergeable unit.** It must stand alone — no forward references to deferred content.
- **Retain infrastructure, defer configuration.** Factory functions, output patterns, and file tree structure cost nothing and prevent rework. Only defer the variant-specific configuration that isn't tested.
- **Don't rewrite history on the full branch.** The full branch stays as-is. After the minimal merges, the full branch rebases to add remaining content — commits that are now redundant with the minimal branch will drop naturally.
- **Each commit on the minimal branch should be a valid edit of its counterpart.** Don't invent new commits — each one traces back to a specific original commit, possibly edited. This preserves provenance and makes the split auditable.

## Naming convention

```
claude/<topic>           # full branch (existing PR)
claude/<topic>-minimal   # minimal subset branch (new PR)
```
