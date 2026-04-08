# Session Index: 5e4dd978 (post-compaction continuation)

Worktree: focused-bhabha
Model: claude-opus-4-6[1m]
Predecessor index: .claude/notes/session-index-5e4dd978.md (on claude/nix-architecture-v2)

## Boot instructions for next agent

- **Skills branch:** `claude/nix-architecture-v2` — read ALL skills from here, not from working branch
- **Active work branch:** `claude/birdboot-distroname` (PR #21)
- **Worktree:** focused-bhabha, checked out on skills branch currently
- **WSL clone:** ~/nixos-hosts, master is 13 commits ahead of origin (stale local state from predecessor)

## Memories created/updated

- `feedback_read_skills_first.md` — "after compaction, read ALL skills from skills branch before touching code"

## Key decisions

- "Birdboot" capitalized (distroName = "Birdboot") — user preference
- edition = "" — reserved for future feature-set shortcode, not redundant with distroName
- image.baseName derived from config via lib.concatStringsSep + lib.optional — replaces hardcoded "nixos"
- volumeID is ISO-specific, stays in iso-impermanent.nix — GPT variants use repart labels
- Boot flags (makeBiosBootable/makeUsbBootable/makeEfiBootable) are independent xorriso flags, not a dependency chain

## Skills created/modified

- `session-continuity` — boot sequence, incremental index, context budget, delegation heuristics (3 commits on claude/nix-architecture-v2)
- `source-research` — generalized from nixpkgs-specific, renamed directory (3 commits on claude/nix-architecture-v2)
- `branch-rebase` — commit age policy, break keyword (2 commits on claude/nix-architecture-v2)
- `CLAUDE.md` — nixpkgs source paths table (1 commit on claude/nix-architecture-v2)

## Issues created

- #23 — Network stack (IWD vs NM)
- #24 — Filesystem support (exfat, APFS, HFS+, UDF, bcachefs)
- #25 — VM guest support as optional module
- #26 — Rename portable-* files and flake keys
- #27 — ISO/image naming (edition semantics)

## Open threads

- **PR #21** (claude/birdboot-distroname) — 8 commits, all review threads resolved, CI should be running. Title: "hosts: birdboot: boot identity, USB hybrid ISO, hardware support"
- **PR #13** (claude/nix-architecture-v2) — skills synthesis draft, 25+ commits now. Latest review resolved (source-research skill comments).
- Physical boot test pending — ISO needs to be dd'd to USB and tested on real hardware

## Next steps (prioritized)

1. **Deliver PR #21 CI artifact** when build completes
2. **Physical boot test** — dd ISO to USB, boot on UEFI and BIOS hardware
3. **Review PR #13** — user needs to review the skills synthesis (largest open deliverable)
4. **Merge ready PRs** — #22 (one-line fix), #21 (after boot test), #20 (pathfinder-wsl)

## Blockers

- Subagent bash permission still unresolved — delegation heuristic can't be tested until this is fixed
- PR #21 distroName is now "Birdboot" — nix eval verification of isoName needed to confirm the toLower produces correct filename

## Chronological log

### Topic 1: ISO boot research and hybrid ISO fix
User returned from work asking how to flash the ISO to USB. Research revealed makeEfiBootable and makeUsbBootable both default false — the ISO wasn't USB-bootable. Added both flags, documented with source permalinks. Created PR comment with upstream precedent (installation-cd-base.nix blame).

### Topic 2: Hardware support, naming, filesystem research
enableAllHardware, variant_id, distroName simplification. Parallel research on filesystem support (exfat, APFS, HFS+) and network stack (IWD vs NM). Created 5 tracking issues. User scoped filesystem and VM support to separate PRs.

### Topic 3: image.baseName override
Researched module priority system. Replaced hardcoded "nixos" in baseName and volumeID with config-derived values using lib.concatStringsSep. Verified lib.optional prevents double separators with empty edition.

### Topic 4: Review cycles (multiple rounds)
User reviewed PR #21 three times. Each round required rebasing fixes into affected commits (not new commits). **This is where attention degradation occurred.** Batched fixes, stripped citations, missed top-level comment, broke rename detection. User corrected each failure.

### Topic 5: Session continuity skill rewrite
Diagnosed the attention loss. Root cause: skills not loaded after compaction, no boot sequence in the skill. Rewrote session-continuity with boot sequence, incremental index, context budget, delegation heuristics. The skill now documents the specific failures that motivated each section.

### Topic 6: Source-research skill generalization
Moved from nixpkgs-specific to general GitHub dependency research. Renamed directory. Moved nixpkgs path table to CLAUDE.md per review.
