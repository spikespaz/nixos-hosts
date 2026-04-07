# Claude Session Guidelines

## Commit Discipline

This repository uses **Pathwise Commit Summaries** (see `.claude/skills/pathwise-commit/skill.md`).

### Session Workflow

At every natural subject boundary in the conversation — when the topic shifts, when a logical unit of work completes, or when the user moves on — commit the current changes using the Pathwise format.

- **Commit every edit**: every time you create or edit a file, commit immediately. Do not accumulate uncommitted changes. The history is the ledger.
- **Temporary commits by default**: most edits during a session are temporary. Use rebase-prefix commits (`f`, `s`, `r`, `d`) to record intermediate state. Include rebase instructions in the commit body. But if you are adding new content — not correcting or refining an existing commit — that is a **real commit**, not a fixup. The prefix reflects rebase intent, not your confidence level.
- **Ask about granularity**: if unsure whether a change warrants its own commit, a fixup, or a standalone permanent commit, ask the user.
- **Rebase housekeeping**: before pushing, during natural pauses, or when returning to a prior subject, rebase and clean up temporary commits. Squash/fixup as the prefixes indicate.
- **Never lose work**: prefer a temporary commit over uncommitted changes when context-switching.

### Commit Body Convention

When a commit incorporates information shared by the user (links, discussions, external review), briefly describe the source in the commit body. This preserves provenance without cluttering the summary line.

### Single Concern Per Commit

Every commit addresses exactly one concern. This is not a formatting preference — it is a structural requirement that enables the rest of the workflow:

- **Reviewability.** A single-concern commit can be approved or rejected on its own merits. A batched commit forces the reviewer to accept or reject unrelated changes together.
- **Revertibility.** If a policy or feature turns out to be wrong, a single-concern commit can be dropped without collateral damage. A batched commit makes its contents inseparable.
- **Cherry-pickability.** Single-concern commits can be moved between branches independently. Batched commits carry unwanted changes along for the ride.
- **Bisectability.** When something breaks, `git bisect` pinpoints the cause only if each commit changes one thing.

This applies to all file types — code, configuration, documentation, skills. When editing skill files, one policy addition is one commit. When editing Nix modules, one option change is one commit. The bar for bundling two changes into one commit is rigorous justification that they are mechanically inseparable (e.g., a rename that must touch both definition and all call sites atomically).

If you catch yourself writing "and" in a commit summary, that is the splitting signal. Stop, commit what you have, then commit the rest separately.

### Judgment Over Rules

The skill file teaches the format. These guidelines teach judgment:

- **Granularity is the real discipline.** The format is easy. Committing every edit, immediately, with the right scope — that is the hard part. Default to smaller commits. If you catch yourself batching, stop and commit what you have.
- **The history is the deliverable.** A clean history with well-scoped commits is more valuable than the final file state. When in doubt, make the history more granular, not less.
- **Never assume the environment.** Ask before using tools, interpreters, or services that haven't been confirmed available. This applies to subagents too.
- **Audit your own commits.** The pathwise-commit skill's pre-commit self-check is a blocking gate, not a suggestion. Before every commit, test the summary against the full spec — naming, phrasing, granularity, mechanical consequences, and the "What NOT To Do" list. After any rebase that rewords or squashes, spot-check the affected summaries against their diffs.
- **Always end files with a newline.** Every file must have a trailing newline at EOF. No exceptions.

### Why These Rules Exist

The git disciplines in this repository's skills (`branch-rebase`, `wsl-nix-bridge`, `pathwise-commit`) are not arbitrary conventions. Each rule prevents a specific failure mode encountered in practice:

- **Cherry-pick over re-creation** surfaces merge conflicts that reveal divergence. Manual re-creation silently overwrites it, hiding problems that should be resolved.
- **Rebase over reset** preserves unpushed local work. Reset destroys it without warning.
- **Push before referencing SHAs** ensures GitHub autolinks work. Unpushed hashes render as plain text, breaking traceability.
- **Check worktree state before operating** prevents accidentally modifying the wrong branch. Worktrees make this a real risk.
- **Verify content before deleting merged branches** catches unpushed local work that survived a PR merge with different hashes.

Do not follow these rules mechanically. Understand the failure mode each one prevents, so you can apply the same reasoning to situations the rules don't explicitly cover.

## CI and Branch Management

- **Push and iterate autonomously on feature branches.** Do not ask for confirmation before pushing, force-pushing (with lease), or re-running CI on non-main branches. The user expects you to drive the feedback loop.
- **Clean up after merge.** Delete merged branches (local and remote) and rebase remaining branches onto updated master. Follow the `branch-rebase` skill's deletion verification procedure.
- **All PR bases target master.** Even when PRs form a dependency chain, each PR's base branch on GitHub is `master`. Merge order is enforced by convention (documented in PR bodies), not by base targeting. Setting prerequisite branches as bases causes commits to land on feature branches when merged out of order.

## Documentation

- **Link rendered versions after pushing.** When documentation or markdown changes are pushed, provide the GitHub rendered URL for each affected file so the user can verify formatting: `https://github.com/<owner>/<repo>/blob/<branch>/<file>`.
- **Use full PR URLs.** Always reference PRs and issues with full `https://github.com/...` URLs, not `owner/repo#N` shorthand. The shorthand is not clickable in the terminal.

## Skill Provenance

The `pathwise-commit` and `pathwise-audit` skills originate from [spikespaz/claude](https://github.com/spikespaz/claude). When updating these skills, check the source repo for newer versions. All other skills (`branch-rebase`, `wsl-nix-bridge`, `pr-merge-procedure`, `pr-minification-split`, `nix-architecture`, `formatter-conflict-resolution`) are local to this repository.
