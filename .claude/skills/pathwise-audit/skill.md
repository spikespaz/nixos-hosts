---
name: pathwise-audit
description: Audit a PR branch for Pathwise Commit Summaries compliance. Run this when asked to spot-check, audit, or review commit history on a branch. Produces a structured report with format compliance, scope/file alignment, structural issues, and rebase recommendations.
---

# Pathwise Commit Audit

You are auditing a git branch for compliance with the **Pathwise Commit Summaries** specification (see `pathwise-commit` skill). This is a spot-check — not a full rewrite. You produce a structured report and actionable rebase plan.

## Procedure

### 1. Gather context

Determine the base branch (usually `main` or the PR target). Then run:

```bash
git log --oneline <base>..HEAD
git log --stat <base>..HEAD
```

Read each commit's full message (`git log --format=full <base>..HEAD`) to check bodies and co-author lines.

### 2. Audit each commit

For every commit in the range, evaluate:

#### Format compliance
- Does the summary follow `<segment>: <segment>: <verb> <description>`?
- Are segments lower-case (except language-level identifiers)?
- Does the description start with a verb?
- Is the verb precise (not vague: `update`, `change`, `fix` without specificity)?
- Are root-level config files bare segments without extension (`flake:`, `readme:`, not `flake.nix:`)?
- Is `+` used correctly for same-level multi-path changes?
- Are rebase prefixes (`f`, `s`, `r`, `d`) used correctly if present?
- 2-4 path segments? If 5+, is it justified?
- Description 3-4 words median, ≤7?

#### Scope and file alignment
- Do the files touched match the path segments claimed?
- Is each commit single-purpose (one semantic change)?
- Does the "and" test pass (no hidden conjunctions)?
- Does the "path" test pass (one Pathwise path, or justified multi-path)?
- Are mechanical consequences (lockfiles, mod declarations, downstream fixups) correctly bundled vs. separated?

#### Naming consistency
- Are abbreviations consistent across the branch? (No drift: `hm-mods` → `hm-mod` → `hm-module`)
- Are intermediate segments omitted consistently?
- Does the branch follow `init` vs `add` correctly?
- Are renames handled properly (both identifiers named, `from` form preferred)?

### 3. Structural issues

Look at the branch as a whole:

- **Redundant history**: Are there commits that are fully superseded by later commits? (e.g., commit A adds X, commit B rewrites X entirely)
- **Dangling refs**: Are there orphaned branches or refs visible in `--all --graph` from split/rebase operations?
- **Temporary commits**: Are there unpacked rebase-prefix commits (`f`, `s`, `r`, `d`) that should have been folded?
- **Ordering**: Could commits be reordered for a cleaner narrative? (Independent changes should not interleave)
- **Build bisectability**: Would `git bisect` hit a broken state at any intermediate commit? (Acceptable within a PR if final commit passes CI, but flag it)

### 4. Produce the report

Structure your output as:

```
## Pathwise Audit: <branch-name>

### Per-commit review

| Commit | Summary | Verdict | Notes |
|--------|---------|---------|-------|
| <short-hash> | <summary> | ✅ / ⚠️ / ❌ | <issue if any> |

### Format issues
- <list specific violations with commit hash>

### Scope issues
- <list scope/alignment problems>

### Structural issues
- <list branch-level problems>

### Recommended rebase plan
<concrete rebase instructions: which commits to squash, reorder, reword, drop>
```

### 5. Severity levels

- **✅ Pass**: Fully compliant.
- **⚠️ Minor**: Technically non-compliant but understandable — e.g., slightly long description, borderline verb choice. Mention but don't block.
- **❌ Violation**: Breaks a MUST-level rule — vague verb, wrong scope, bundled independent changes, missing rename identifiers, abbreviation drift. Must fix before push.

## Notes

- This audit is advisory. The user decides which recommendations to act on.
- When the branch includes work-in-progress (rebase-prefix commits), audit the *intended* final state, not the raw temporary history.
- If the branch mixes multiple hosts or concerns that should be separate PRs per project policy, flag that as a structural issue.
- Reference specific rules from the pathwise-commit skill by section name when citing violations.
