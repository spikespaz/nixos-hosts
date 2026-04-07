---
name: session-continuity
description: Preserve session context across compaction boundaries. Write memory files with transcript source references, create session indexes, and enable selective transcript recovery for the next agent.
---

# Session Continuity

## Problem

When a session exhausts context, the next agent gets a lossy summary. Memories exist but lack provenance — the next agent doesn't know why a decision was made or what conversation produced it. The full transcript is available but too large to read whole, and the next agent doesn't know what to search for.

## Protocol

### During the session

When creating memory files, add a `source` block to the frontmatter:

```yaml
---
name: <name>
description: <description>
type: <type>
source:
  transcript: <session-id>.jsonl
  search: "<grep-able string from the conversation that produced this memory>"
---
```

The `search` field should be a distinctive quote from the user's message that triggered the memory — not the agent's interpretation. This is the grep target for transcript recovery.

### Before context exhaustion

Write a session index at `.claude/notes/session-index-<session-id>.md` containing:

1. **Memories created/updated** — each with its grep target
2. **Key decisions** — grep-able quotes for significant choices, with one-line rationale
3. **Skills created/modified** — list of files changed
4. **Open threads** — PRs, issues, branches with current state
5. **Next steps (prioritized)** — ordered by urgency, with rationale for ordering
6. **Blockers** — things the next agent should know before starting

### When continuing a session

The next agent should:

1. Read `MEMORY.md` index as usual
2. Check for session index files in `.claude/notes/session-index-*.md`
3. For the most recent session index, read the "Next steps" and "Blockers" sections
4. When a memory's `source` field is present and the current task relates to that memory, grep the transcript for surrounding context (±50 lines) rather than trusting the memory body alone

### Selective transcript recovery

```bash
# Find the conversation that produced a memory
grep -n "<search term>" <transcript>.jsonl | head -5

# Read surrounding context
sed -n '<line-50>,<line+50>p' <transcript>.jsonl
```

The transcript is the authoritative record. Memories are summaries. When they conflict, the transcript wins.

## What the session index is NOT

- Not a summary of the conversation (that's what compaction produces)
- Not a replacement for memories (memories are the persistent store)
- Not comprehensive (it indexes significant decisions, not every message)

It is a **map** — it tells the next agent where to look, what to prioritize, and what to avoid. A table of contents is insufficient; the index must include rationale and priority.

## Quality signal

The `context_pct` field (optional) in memory source blocks records how full context was when the memory was written:

- Low % (10-30%): fresh context, high fidelity, full conversation history available
- Mid % (30-60%): good context, reliable memories
- High % (60-80%): compressed context, memories may miss nuance
- Very high % (80%+): near exhaustion, memories are most-important-only

This lets the next agent weight memories by reliability.
