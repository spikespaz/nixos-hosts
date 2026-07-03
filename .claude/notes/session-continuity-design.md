# Session Continuity: Memory-Linked Transcript References

## Problem

When a session ends (compaction or context exhaustion), the next Claude gets a lossy summary. Memories exist but float free of their origin — the next agent doesn't know *why* a memory was created, what discussion produced it, or what nuances were lost in the summary.

The transcript file preserves everything but nobody reads it. It's too large to load whole, and the next agent doesn't know what to search for.

## Insight

Memories should be index entries into the transcript, not standalone notes. Like an obsidian vault where each note links to its source material.

## Design

### Memory frontmatter extension

Add `source` and `search` fields to memory files:

```yaml
---
name: branch naming
description: Don't create PR until scope is clear
type: feedback
source:
  transcript: 5e4dd978-ac7c-40aa-b7f9-3dc3bd4fb69a.jsonl
  search: "I don't want to be creating PRs published with wrong branch name"
  context_pct: 77
  timestamp_approx: "2026-04-07T10:00:00"
---
```

- `transcript`: the session log file that produced this memory
- `search`: a grep-able string to find the conversation locus
- `context_pct`: how full context was when the memory was written (signals quality — low % = fresh context = high fidelity; high % = compressed context = lower fidelity)
- `timestamp_approx`: when in the session this was created

### Agent behavior on memory read

When loading a memory that has a `source` field:
1. Check if the transcript file exists
2. If the current task relates to this memory's topic, grep the transcript for surrounding context
3. Load only the relevant excerpt (±50 lines around the search match), not the whole file
4. Use that context to inform decisions, not just the memory's body text

### Session exit protocol

Before context exhaustion, the agent should:
1. Write/update memories with source references for all significant decisions
2. Create a `.claude/notes/session-index.md` listing all memories created/updated this session with their search terms
3. The index itself becomes a table of contents for the transcript

### Session index format

```markdown
# Session Index: 5e4dd978-ac7c-40aa-b7f9-3dc3bd4fb69a

## Memories created
- feedback_branch_naming.md — "I don't want to be creating PRs published with wrong branch name"
- feedback_deliver_artifacts.md — "when you push and trigger CI, deliver the artifact"
- feedback_nixpkgs_research.md — "use WSL nix store to read nixpkgs source code"
- project_ci_caching.md — "nix copy binary cache, 32s cache-hit"

## Memories updated
- MEMORY.md — added 4 entries

## Key decisions (grep targets)
- "rebase conflicts are not merge conflicts" — learned from PR #2 rebase failure
- "distroName only affects os-release" — ISO filename uses image.baseName not distroName
- "force-push should not invalidate inline reply targets" — REST IDs survive force-push
- "cache-nix-flake-outputs-action is a prototype" — opus agent research finding
- "the script is the dependent variable" — why stack-prs.sh compensates for agent merge-conflict bias

## Open threads
- PR #13: draft, 16 commits of skills synthesis, awaiting review
- PR #2: 8 commits, GPT variants, ready to merge
- PR #20: extract pathfinder-wsl to file tree
- PR #21: birdboot distroName + isoImage.edition (CI passed, artifact uploaded)
- PR #22: fix build step label lost in rebase
- Issue #19: CI caching remaining verification items
- test/pr17-rebase-experiment: kept for comparison with original #17 branch

## Unfinished work
- pathwise audit of PR #17 — agents couldn't get bash, test branch has intuitive rebase
- CLAUDE.md in colemak-dh-windows-arm64 PR #14 — force-push fix prompt posted
- nix-architecture skill on #13 draft PR — not yet updated with CI convention findings
```

## Implementation plan

1. Extend memory file format with optional `source` block
2. Teach the auto-memory system prompt to include source references when creating memories
3. Add session-index creation to the session exit protocol
4. Teach continuation prompts to load the session index and selectively grep transcripts

## What this enables

- Next Claude reads session index → knows what happened without reading 770k tokens
- Grep targets let the next agent recover specific decisions on demand
- Context percentage signals memory quality
- Open threads list is the handoff — no more "what was I working on?"
- The transcript becomes a queryable database, not an unread backup
