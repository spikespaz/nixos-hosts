---
name: session-continuity
description: Boot sequence after compaction, skill preservation across context boundaries, session indexes for handoff. Read this skill FIRST after any compaction or session start — it tells you how to load everything else.
---

# Session Continuity

## The bootstrapping problem

After compaction, the agent has a narrative summary (what was decided) but no procedural knowledge (how to work). Skills contain the procedure, but the agent must know to read them — and know WHERE to read them, since skills may live on a PR branch, not the current branch.

The anchor point is `MEMORY.md` — it's loaded into context automatically. Everything else requires deliberate action.

## Skill reload tiers

The cost of not reading a skill you need (hours of rework, user trust lost) far exceeds the cost of re-reading one you already know (~2k tokens). Bias toward re-reading.

| Trigger | Action | Cost |
|---|---|---|
| Compaction or fresh session | Full boot: reload ALL skills | ~17k tokens |
| Branch switch | Re-read skills relevant to next task | ~2-5k tokens |
| Before multi-step operation | Re-read that specific skill | ~2k tokens |
| Continuous work, no context break | Don't re-read | 0 |

After compaction, memory can't tell you which skills you've "forgotten" — the continuation summary preserves decisions, not procedure. Full reload is the only safe option.

Within a session, the decision of *which* skills to re-read is driven by what task is next, not by what you remember having read. About to rebase? Re-read branch-rebase. About to commit? Re-read pathwise-commit.

## Full boot (after compaction or session start)

Before touching any code, before answering any user request, execute this sequence. ~17k tokens — non-negotiable.

### 1. Read MEMORY.md (automatic)

Already in context. Scan for session index, feedback entries, and supplementary notes (tacit knowledge, trust journals).

### 2. Identify the skills branch

Skills may not be on the current branch. Check memory files for the skills PR branch name, or:

```bash
git log --all --oneline -- '.claude/skills/*/skill.md' | head -10
```

### 3. Read ALL skills from the skills branch

```bash
git show <skills-branch>:.claude/skills/<name>/skill.md
```

Read every skill — the full files, not the one-line descriptions in the system prompt. The descriptions tell you a skill exists; the content tells you how to follow it.

### 4. Read CLAUDE.md from the skills branch

The working branch may have a stale copy.

```bash
git show <skills-branch>:CLAUDE.md
```

### 5. Read session index and supplementary notes

The session index is in the memory directory (branch-independent). Supplementary notes (tacit knowledge, trust journals) may also be in the memory directory. These encode the predecessor's judgment — read them as context, not directives.

### 6. Now begin work

Only after steps 1–5 should you switch to the working branch, read review comments, or make code changes.

## Branch switch reload

When switching branches, re-read the skills relevant to the work you're about to do on the new branch. You don't need all skills — just the ones for your next task. Also update the session index (in the memory directory) with a topic boundary entry logging the switch.

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

Write the session index in the **memory directory** — the same directory as `MEMORY.md`. This is branch-independent: it survives branch switches, is auto-loaded into context, and doesn't pollute git history with ephemeral session state.

```
<memory-directory>/session_index_active.md
```

Add an entry to `MEMORY.md` pointing to it. One active index at a time — overwrite the previous session's index when starting a new one.

Git-committed indexes (`.claude/notes/session-index-*.md`) are for archival handoff only — they become inaccessible after branch switches, which is when the index is needed most.

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

### Degradation and escalation

Attention loss is not forgetting facts. It is **stopping the self-check loop.** At full attention, every action goes through: "what does the skill say? → does my plan match? → execute." Under load, the loop collapses to just "execute."

Signs the loop has collapsed:

- You're confident about a fact but can't point to where you learned it
- You're about to rebase or push without checking the skill procedure
- You're reaching for `--amend` or `--force` under time pressure
- You're "cleaning up" code without verifying what the cleanup removes
- You're batching changes because doing them individually feels slow

When you notice these, escalate through the reload tiers:

**1. Micro-boot (re-read the skill).** Before any multi-step operation — rebase, review resolution, branch split — re-read the relevant skill from the file, not from recall. ~2k tokens, 30 seconds. This prevents cascading errors from degraded procedure recall. Especially important after branch switches, which clear working state.

**2. Delegate.** If you aren't confident you'll execute each step precisely even after re-reading, delegate to a fresh subagent. Delegation isn't just for parallelism — it's for context isolation. A fresh agent with only the relevant skill loaded follows procedure more reliably than a fatigued agent.

When to delegate:
- The task follows a multi-step skill and you notice shortcuts creeping in
- You're holding concurrent state (multiple review threads, commit graphs, thread IDs)
- The task is self-contained — the subagent can complete it without conversation history

When NOT to delegate:
- The task requires judgment from this conversation that the subagent won't have
- Re-reading the skill is sufficient to restore confidence
- You need the result immediately

What to give the subagent:
- The full skill content inline (it can't read from other branches)
- Exact files, branch, commit range, expected outcome
- Constraints from the conversation (e.g., "rebase into affected commits, not new ones")

What NOT to give:
- The entire session history — defeats isolation
- Vague instructions — if you can't specify the task clearly, you haven't understood it

The delegation decision is itself a self-check: writing the prompt forces the planning that shortcuts would skip. Sometimes you write the delegation prompt and realize you can just follow it yourself.

**3. Verify.** Subagent output needs the same audit as your own output. After delegation, check what changed — don't trust the report. Memory files aren't git-tracked, so there's no diff to review; read the files and verify against ground truth (`gh pr list`, `git branch`, etc.). A subagent that introduces a small inaccuracy into a memory file corrupts every future agent that reads it.

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
