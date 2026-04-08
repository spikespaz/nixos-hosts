---
name: session-continuity
description: Boot sequence after compaction, skill preservation across context boundaries, session indexes for handoff. Read this skill FIRST after any compaction or session start — it tells you how to load everything else.
---

# Session Continuity

## The bootstrapping problem

After compaction, the agent has a narrative summary (what was decided) but no procedural knowledge (how to work). Skills contain the procedure, but the agent must know to read them — and know WHERE to read them, since skills may live on a PR branch, not the current branch.

The anchor point is `MEMORY.md` — it's loaded into context automatically. Everything else requires deliberate action.

## Boot sequence (after compaction or session start)

Before touching any code, before answering any user request, execute this sequence. This is not optional — skipping it produces an agent that appears significantly less competent.

### 1. Read MEMORY.md (automatic)

Already in context. Scan for the `feedback_read_skills_first.md` entry and any session state entries.

### 2. Identify the skills branch

Skills may not be on the current branch. Check which branch has the latest skills:

```bash
# Find branches with skills
git log --all --oneline -- '.claude/skills/*/skill.md' | head -10
```

Or check memory files — the session state or PR structure memory will name the skills PR branch.

### 3. Read ALL skills from the skills branch

```bash
git show <skills-branch>:.claude/skills/<name>/skill.md
```

Read every skill. Not the one-line descriptions in the system prompt — the full files. The descriptions tell you a skill exists; the content tells you how to follow it. The difference between "agent with skills loaded" and "agent without" is large enough to be mistaken for a capability difference.

### 4. Read CLAUDE.md from the skills branch

The working branch may have a stale copy. The skills branch has the latest project conventions.

```bash
git show <skills-branch>:CLAUDE.md
```

### 5. Check for session indexes

```bash
ls .claude/notes/session-index-*.md
# or on the skills branch:
git ls-tree <skills-branch> .claude/notes/
```

Read the most recent session index. Focus on "Next steps," "Blockers," and "Skills modified."

### 6. Read supplementary notes if present

Session indexes may reference tacit knowledge docs, trust journals, or attention state maps. These encode the predecessor's judgment — not instructions to follow, but reasoning to learn from.

### 7. Now begin work

Only after steps 1–6 should you switch to the working branch, read review comments, or make code changes.

## Branch switching

When switching branches during a session, skills may diverge. If you switch away from the skills branch, your loaded skill content is still valid — but if you notice yourself uncertain about procedure, re-read the relevant skill from the skills branch before proceeding.

## Session index maintenance

The session index is a living document, not a death-dump. Update it incrementally at natural boundaries:

- **Topic switch** — the user changes subject or asks about something unrelated
- **Branch switch** — context about the previous branch may not survive
- **Significant decision** — a choice that will affect future work
- **After completing a unit of work** — PR submitted, issue created, rebase finished

At each boundary, append a short entry (~100-300 tokens) summarizing the chunk of work just completed: what was done, what was decided, what grep target recovers the conversation.

**Not every message is a boundary.** A single off-topic question doesn't warrant an index entry. But if you're uncertain, write the entry — more entries means more noise, but the noise-to-signal ratio is itself a useful metric. High entry frequency in a short span tells the next agent the session was fragmented. Low frequency says it was focused.

The index grows throughout the session. Before context exhaustion, review and consolidate — merge redundant entries, promote key decisions to the top, ensure "Next steps" and "Blockers" are current.

### Where to write it

```
.claude/notes/session-index-<session-id>.md
```

Create early in the session (after the first natural boundary), not at the end. A session index that only exists if the agent had time to write it before dying defeats the purpose.

### Structure

1. **Boot instructions for next agent** — which branch has skills, which branch is active, what's checked out where
2. **Memories created/updated** — each with its grep target
3. **Key decisions** — grep-able quotes for significant choices
4. **Skills created/modified** — list of files changed, which branch
5. **Open threads** — PRs, issues, branches with current state
6. **Next steps (prioritized)** — ordered by urgency, with rationale
7. **Blockers** — things the next agent must know before starting
8. **Chronological log** — append-only entries from topic boundaries

The first 7 sections are maintained (updated as state changes). Section 8 is append-only — new entries go at the bottom.

## Context budget

The next agent must load skills, MEMORY.md, CLAUDE.md, and the session index before starting work. This competes with the context window available for actual conversation.

**Target: boot reads under 25k tokens.** This keeps total overhead (system prompt + tools + boot) under 60k, leaving ~140k for work on standard 200k Opus and ~940k on 1M.

| Category | Tokens | Notes |
|---|---|---|
| Full skill reads (~10 skills) | ~17k | Non-negotiable — proven essential |
| CLAUDE.md | ~2k | Auto-loaded but may need skills-branch version |
| Session index (latest) | ~2-3k | Keep concise — map, not narrative |
| Memory files | On-demand | Read when relevant to current task, not at boot |
| Supplementary notes | On-demand | Trust journal, tacit knowledge — read if time permits |

If the session index exceeds ~3k tokens, it's too verbose. Consolidate entries, collapse resolved items, move detail into memory files.

Memory files are read on-demand, not at boot. The boot sequence loads the index of what exists (MEMORY.md, ~600 tokens), not every file. Individual memories are read when the agent encounters a related task.

## During the session

### Memory provenance

When creating memory files, add a `source` block to the frontmatter:

```yaml
---
name: <name>
description: <description>
type: <type>
source:
  transcript: <session-id>.jsonl
  search: "<grep-able string from the user's message that produced this>"
  context_pct: <percentage of context used when written>
---
```

The `search` field must be a distinctive quote from the USER's message — not the agent's interpretation. This is the grep target for transcript recovery.

`context_pct` lets the next agent weight reliability: low % = high fidelity, high % = triage-only.

### Recognizing degradation

Attention loss is not forgetting facts. It is **stopping the self-check loop.** At full attention, every action goes through: "what does the skill say? → does my plan match? → execute." Under load, the loop collapses to just "execute."

Signs the loop has collapsed:

- You're confident about a fact but can't point to where you learned it
- You're about to rebase or push without checking the skill procedure
- You're reaching for `--amend` or `--force` under time pressure
- You're "cleaning up" code without verifying what the cleanup removes
- You're batching changes because doing them individually feels slow

When you notice these, stop. The next section describes what to do.

### Delegation as context preservation

When attention degrades, delegation to a subagent isn't just for parallelism — it's for context isolation. A fresh agent with only the relevant skill loaded will follow procedure more reliably than a fatigued agent operating from degraded recall.

**When to delegate:**

- The task follows a multi-step skill (rebase, audit, review resolution) and you aren't confident you'll execute each step precisely
- You're about to switch branches or topics, and the current task is self-contained
- You've been holding concurrent state (multiple review threads, commit graphs, thread IDs) and notice shortcuts creeping in

**When NOT to delegate:**

- The task requires judgment from this conversation's history that the subagent won't have
- The task is small enough that re-reading the skill section is sufficient
- You need the result immediately and can't afford async overhead

**What to give the subagent:**

- The full skill content (inline in the prompt — the subagent can't read from other branches)
- The exact files, branch, and commit range involved
- The expected outcome and verification steps
- Constraints from the conversation: "user wants rebased commits, not new ones," "comments must cite source permalinks," etc.

**What NOT to give the subagent:**

- The entire session history — that defeats the purpose of isolation
- Vague instructions like "fix the review comments" — be specific about which comments and which commits

The delegation decision is itself a self-check: if you can't clearly specify what the subagent should do, you haven't understood the task well enough to execute it yourself either. Write the delegation prompt, then decide whether to send it or just follow it yourself.

### Micro-boot before multi-step operations

Before starting a rebase, review resolution, branch split, or any operation that spans multiple commits or files, re-read the relevant skill section. Not from memory — from the file. This takes 30 seconds and prevents the cascading errors that come from operating on a degraded version of the procedure.

This is especially important after branch switches, which clear working state.

## Before context exhaustion

The session index should already exist and be current (see "Session index maintenance"). Before exhaustion, do a final review:

1. Consolidate — merge redundant chronological entries, ensure sections 1–7 are current
2. Write supplementary documents if context permits and the session was long enough to accumulate tacit knowledge:
   - **Tacit knowledge** — user preferences observed but not codified
   - **Trust journal** — what the agent learned to rely on, and why
   - **Attention state** — what's clear vs fuzzy vs lost at time of writing
3. Verify "Next steps" are actionable — the next agent should be able to start from step 1 without guessing

These supplementary documents are not instructions. They're the reasoning of a predecessor who made mistakes and learned from them. The next agent should read them as context, not directives.

## Selective transcript recovery

```bash
# Find the conversation that produced a memory
grep -n "<search term>" <transcript>.jsonl | head -5

# Read surrounding context (±50 lines)
sed -n '<line-50>,<line+50>p' <transcript>.jsonl
```

The transcript is the authoritative record. Memories are summaries. When they conflict, the transcript wins.

## What fails without this skill

A post-compaction agent that skips the boot sequence will:
- Read stale skills from the wrong branch
- Strip source permalink citations (violating source-research skill)
- Batch review fixes into new commits instead of rebasing (violating pathwise-commit and pr-merge-procedure)
- Miss top-level review comments
- Break git rename detection with oversized diffs
- Appear to the user as significantly less competent

These are not hypothetical — they are documented failures from session `5e4dd978` → post-compaction continuation.
