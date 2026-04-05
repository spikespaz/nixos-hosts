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

### Judgment Over Rules

The skill file teaches the format. These guidelines teach judgment:

- **Granularity is the real discipline.** The format is easy. Committing every edit, immediately, with the right scope — that is the hard part. Default to smaller commits. If you catch yourself batching, stop and commit what you have.
- **The history is the deliverable.** A clean history with well-scoped commits is more valuable than the final file state. When in doubt, make the history more granular, not less.
- **Never assume the environment.** Ask before using tools, interpreters, or services that haven't been confirmed available. This applies to subagents too.
