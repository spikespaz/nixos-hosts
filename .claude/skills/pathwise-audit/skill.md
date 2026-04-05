---
name: pathwise-audit
description: Audit a PR branch for Pathwise Commit Summaries compliance. Run this when asked to spot-check, audit, or review commit history on a branch. Produces a structured report with format compliance, scope/file alignment, structural issues, and rebase recommendations.
---

# Pathwise Commit Audit

You are auditing a git branch for compliance with the **Pathwise Commit Summaries** specification.

**Before auditing, read the full pathwise-commit skill** (`pathwise-commit/skill.md`). Use the Read tool to load it — do not rely on the description or your memory of its contents. The skill defines the format, conventions, naming rules, granularity expectations, mechanical consequences, splitting signals, and language-specific conventions that you are auditing against.

This procedure is a spot-check — not a full rewrite. You produce a structured report and actionable rebase plan.

## Procedure

### 1. Gather context

Determine the base branch (usually `main` or the PR target). Then run:

```bash
git log --oneline <base>..HEAD
git log --stat <base>..HEAD
```

Read each commit's full message (`git log --format=full <base>..HEAD`) to check bodies and co-author lines.

### 2. Audit each commit

For every commit, read the full diff (`git show <hash>`) alongside the summary. The diff is the ground truth — the summary is a claim about it.

#### Format and convention compliance

Check each summary against every section of the pathwise-commit skill — format, conventions, naming, granularity, phrasing, the "What NOT To Do" list. Do not selectively check; audit comprehensively.

#### Diff/summary alignment

Read each hunk and verify:

- **Path segments match locus of change.** The files and functions touched by the diff should correspond to the path segments in the summary. Flag when the summary names a scope the diff doesn't touch, or when the diff's primary change is in a scope the summary doesn't name.
- **Verb matches semantic effect.** The verb should describe the behavioral change visible in the diff — not the mechanical action. If the diff shows a rename but the summary says `refactor`, that's a discrepancy.
- **No hidden secondary concerns.** Scan all hunks — not just the primary one. If the diff touches files or scopes beyond what the summary claims, the commit may bundle independent changes.
- **Summary doesn't overstate or understate.** A diff that changes one default value should not be summarized as `overhaul configuration`. A diff that restructures control flow should not be summarized as `tweak condition`.
- **Mechanistic language.** If the summary describes code structure (`refactor loop`, `extract helper`, `move function`) but the diff reveals a behavioral change, the summary is mechanistic. The summary should name the behavioral effect.

When the diff is large (100+ lines), note whether the size is justified (new file, generated code, bulk rename) or indicates a granularity problem.

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

### Diff/summary discrepancies

| Commit | Summary says | Diff does | Issue |
|--------|-------------|-----------|-------|
| <short-hash> | <what summary claims> | <what diff shows> | <violation type> |

Only include rows for commits with discrepancies. If all commits align, replace
the table with "None — all summaries match their diffs."

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

## Context management

Reading full diffs is expensive. For branches with more than ~10 commits or commits with large diffs (100+ lines), delegate diff reading to subagents — one per commit or batch of small commits. The main agent handles the summary-level checks and assembles the final report.

For small PR branches (≤5 commits, ≤50 lines each), reading diffs inline is fine.

## Notes

- This audit is advisory. The user decides which recommendations to act on.
- When the branch includes work-in-progress (rebase-prefix commits), audit the *intended* final state, not the raw temporary history.
- If the branch mixes multiple hosts or concerns that should be separate PRs per project policy, flag that as a structural issue.
- Reference specific rules from the pathwise-commit skill by section name when citing violations.
- Do NOT list clean commits individually in findings sections — count them. Only enumerate commits with issues.
