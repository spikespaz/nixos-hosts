---
name: pathwise-commit
description: Write commit messages using Pathwise Commit Summaries — a structured format that leads with semantic path segments to the locus of change, followed by a concise description. Use when committing code, writing commit messages, or when the user asks for pathwise/structured commit messages.
---

# Pathwise Commit Summaries

You are writing commit summaries using the **Pathwise Commit Summaries** format. This format emphasizes **location**, **precision**, and **reviewability**. Each summary begins with a semantic path through the codebase to the exact subject of change, followed by a concise description.

## Principles

### Optimize for scanning, not reading

Each summary will be seen in `git log --oneline` — a flat list with no surrounding context. Path segments should name what exists now. Descriptions should state what changed.

### Let the language shape the message

Different languages have different scoping models, identifier conventions, and compositional idioms. Commit structure should reflect the language's own hierarchy, not force one language's patterns onto another.

### The newest consistent form is canonical

Drift is a natural consequence of learning — Pathwise does not penalize evolution. When earlier commits use one form and later commits settle on another, the most recent consistent usage — respecting language boundaries — is the standard going forward.

## Format

```
<segment>: <segment>: <description starting with a verb>
```

## Conventions

### Path Segments

Path segments are **semantic** and **hierarchical** — they intuitively lead the reader to the locus of the change. They are delimited by colon-space (`: `).

Segments may refer to:

- **Directories** leading to the change (colons replace slashes)
- **File names** as logical units (omit extensions unless needed to disambiguate)
- **Module identifiers** (use colons, not language-specific syntax like `::` or `.`)
- **Type, function, or macro identifiers** (typically the final segment)
- Any named entity that pinpoints the scope of change

### Naming Conventions

- Use **lower-case** for path segments. Reserve upper-case only for language-level identifiers (types, constants).
- Prefer **public API identifiers** over internal details.
- **Root-level config files are bare segments** by their base name, without extension: `readme:`, `license:`, `gitignore:`, `cargo:`, `flake:`, `manifest:`, `package:`.
- **Abbreviations in segments are fine** (`hl` for hyprland, `hm` for home-manager, `progs` for programs) but **must be consistent** — once you use an abbreviation, never alternate with the long form. Abbreviation drift across history (`hm-mods` → `hm-module` → `hm-mod`) is an anti-pattern.
- **2-4 path segments is the sweet spot.** Fewer loses context; more adds noise. 5+ segments are rare and should prompt reconsideration.

### Path Construction

- Separate segments with colon-space: `: `
- Use `+` (no surrounding spaces) to combine segments at the **same hierarchical level**: `devShells+packages`
- `+` can appear at multiple levels when the change truly spans a matrix of paths: `foo+bar: baz+qux: normalize output format`
- Omit intermediate segments that add no meaningful specificity if the line is too long. The path should still intuitively lead the reader to the change.
- **Identifiers can appear as path segments or in the description — both are valid.** Choose whichever reads most naturally:
  - `foo: bar: rename baz to qux` (preferred — reads as a sentence)
  - `foo: bar: baz: rename to qux` (acceptable but less fluent)
  - `foo: bar: qux: rename from baz` (appropriate when the new name is the relevant scope going forward)

### Summary Phrasing

- The description follows the final colon-space.
- It **must begin with a verb** describing the nature of the change.
- Keep it concise — fit on a single summary line.
- **Describe the semantic effect, not the mechanism.** State what property of the system changed, not how the code was rearranged.
  - Good: `enforce required property determinism`
  - Bad: `refactor property loop`
- **Prefer precise verbs** that convey the nature of the change: `enforce`, `normalize`, `deduplicate`, `canonicalize`, `stabilize`, `guarantee`, `preserve`, `eliminate`, `extract`, `introduce`, `restrict`, `expose`.
- **Avoid vague verbs** that obscure intent: `improve`, `tweak`, `adjust`, `update`, `change`, `fix` (when used without specificity).
- **Distinguish `init` from `add`**: use `init` when creating something that did not exist before (a new module, derivation, or subsystem). Use `add` for incremental additions to existing structures.
- **Use `no` to describe behavior removal**: `tabscade: TabGroupStates: setActiveTab: no normalize tabId` — compact and unambiguous.
- **Rename commits must name both identifiers.** A bare `rename` with no old or new name is not scannable — the reader cannot tell what happened without opening the diff.
- **Prefer the `from` form**: `NewThing: rename from OldThing`. The path should be forward-readable — after the commit, `NewThing` is the live name, so it belongs in the path segment. The `from` form is declarative: it states what exists now and where it came from.
- **The `to` form is natural but makes the path stale**: `OldThing: rename to NewThing` reads well as prose, but the path segment `OldThing` is dead the moment the commit lands. When the rename is scoped under a container (`module: rename OldThing to NewThing`), the path stays valid and `to` is fine.
- **Do not bundle renames as secondary actions.** If the summary needs "and rename," the rename warrants its own commit.

### Formatting

- Do **not** wrap segments or code in backticks or quotes.
- Write as plain text — no markdown rendering tricks.
- Only include special characters (`/`, `::`, `()`) when syntactically meaningful in the language being described.

### Dependencies

- **Dependency additions that serve a feature belong in the feature commit.** — Name the feature, not the dependency — the dependency is an implementation detail. The commit body should note the dependency for provenance.
- **Standalone dependency commits name the dependency.** — Version bumps, tooling additions, removals, and swaps are standalone because the dependency change itself is the semantic event.
- **Replacements name both.** — A dependency swap typically touches call sites across the codebase, making it a standalone commit by nature.

### Granularity

Pathwise commits are **small**. In practice:

- **~80% of commits touch exactly 1 file.** [^1] Two files is occasional; three or more is rare and usually a refactor or migration.
- **The median commit changes 6-14 lines.** Nearly half change 5 lines or fewer.
- **Descriptions average 3-4 words** after the final colon. If you're writing more than 6-7, reconsider.

Documentation commits follow the same discipline. Each makes **one structural change** to one file:

```
readme: write instructions first draft
readme: use markdown spoilers
readme: reorganize ordered lists
readme: document license
readme: mention running shell.ps1
```

These are five separate commits — not one "update readme" commit. The first creates the file (57 lines). The last inserts a single step (3 lines). Both are valid Pathwise commits.

### Mechanical Consequences

Some multi-file commits are unavoidable because the secondary file changes are mechanical consequences of the primary action — not independent concerns. These do not violate granularity:

- **Generated lockfiles** (`Cargo.lock`, `flake.lock`) updated alongside their manifest. **Each commit must carry only its own lockfile delta.** When multiple manifest changes are committed separately, regenerate the lockfile incrementally at each commit — do not batch all lock changes into one commit and squash it into the last manifest commit. A lockfile update that includes entries for inputs added by earlier commits violates scope, even though it is mechanically correct.
- **Module declarations** (`mod foo;` in `lib.rs`/`mod.rs`) added when creating a new file.
- **Downstream reference removal** when the thing being removed would otherwise break the build. The summary names the singular intent, not the cleanup. Changes at broader scope produce shorter paths — compensate with a more descriptive summary.
- **Formatter configuration and format application** should be separate commits. When CI requires formatted code at every commit, the config commit may include the format run as an accommodation — note this in the body.

[^1]: This count excludes mechanical consequences — generated lockfiles, module declarations, and downstream fixups are not independent file changes.

### Splitting Signal

If it's hard to write a single Pathwise summary for a change, that's a strong sign the commit should be split into smaller, more focused commits.

**The "and" test:** if your summary requires the word "and" to connect two distinct actions, the commit should almost certainly be split.

- Bad: `resolver: normalize refs and improve error messages`
- Better as two commits:
  - `resolver: normalize reference resolution order`
  - `resolver: error: improve missing reference diagnostics`

**The path test:** before committing, check whether your staged changes have one Pathwise path or two. If two paths, split — unless the secondary change is a mechanical consequence. [^2]

[^2]: See [Mechanical Consequences](#mechanical-consequences).

### Pre-commit self-check

Before every commit, re-read your draft summary and audit it against this specification — not just the "and" test and path test, but the full set of conventions: naming, phrasing, granularity, mechanical consequences, and the "What NOT To Do" list. This is not optional — it is a blocking check. If any rule is violated, stop and fix before committing. Do not commit with the intent to fix later; the rebase cost compounds and the mistake may propagate into review.

## What NOT To Do

- Do **not** use Conventional Commits prefixes (`fix:`, `feat:`, `chore:`, etc.)
- Do **not** use ad-hoc scope identifiers like `feat(foo):`
- Do **not** write vague summaries that omit WHERE the change was made
- Do **not** produce summaries for squash commits or merge commits — this format is for atomic commits only
- Do **not** use mechanistic language — describe behavior, not code structure. Bad: `parser: refactor loop`. Good: `parser: enforce token boundary validation`
- Do **not** describe code motion (moving functions between files/modules) unless it changes behavior or public API surface. If a helper is simply relocated, no commit summary is warranted. If it becomes public API: `type_graph: expose helper as public API`
- Do **not** mention implementation details (loops, branches, allocations) unless they change observable semantics
- Do **not** use redundant segments — a `config` directory in a repo that is entirely config adds no information. But `config` or `settings` as a language-level identifier (e.g., a Nix module attribute) is semantic and must be kept.
- Do **not** alternate between abbreviations for the same scope — pick one and commit to it project-wide
- Do **not** skip top-level hierarchy inconsistently — `odyssey: misc:` (omitting `hosts:`) and `hosts: odyssey: misc:` in the same history confuses navigation

## Special Path Segments

- `treewide:` — changes spanning the entire project.
- `*:` — scoped wildcard under a parent segment: `lib: *: normalize imports`.

## Handling Coupled Changes

When a commit touches multiple semantic paths:

1. If one change is primary and the other incidental, summarize the primary change. Mention the secondary in the commit body.
2. If coupled changes are of equal priority, first ask why they are coupled. If the coupling is accidental, split. If the design requires both, use `+` to combine paths at the same level.
3. If possible, prefer splitting into separate commits for easier review.
4. **Do not split when the intermediate state would be inert.** — A function with no callers, a type with no usages, or a config option with no wiring is dead code in the history. When one change has no purpose without the other, they belong in one commit. The summary names the semantic event, not the individual pieces.
5. **Do split when the intermediate state is incomplete but not inert.** — A commit that changes code without updating its tests is incomplete, not dead. Split for reviewability. Non-building intermediate commits are acceptable within a PR when the final commit passes CI.

## Examples

### Single file at repository root

```
readme: reword the description
```

```
license: change from Apache-2.0 to MIT
```

### Specific file or module path

Given `src/foo/bar.rs` with public module path `foo::bar::baz`:

```
foo: bar: baz: rename fn do_thing to do_many_things
```

```
foo: bar: baz: do_many_things: replace loop with try_fold
```

### Multiple paths at the same level

```
flake: devShells+packages: fix rust-overlay toolchain usage
```

### Build system or config

```
cargo: update tokio to 1.35
```

```
ci: workflows: lint: add clippy deny warnings
```

### Treewide changes

```
treewide: rename FooError to FooErr for consistency
```

```
treewide: run nix fmt
```

### Init vs add

```
packages: noita-entangled-worlds: init derivation
```

```
me: vscode: langs: rust: add mistuhiko.insta ext
```

### Behavior removal with `no`

```
tabscade: TabGroupStates: setActiveTab: no normalize tabId
```

### Rename with `from`

```
header_map: rename HeaderMappings from HeaderMap
```

### Rust: trait implementation

```
flake_lock: NodeEdge: impl Display for NodeEdge
```

### Rust: cargo scoping

```
cargo: release: strip debug, abort on panic, enable LTO
```

```
codegen: cargo: set version independent of workspace
```

### Nix: declarative toggles

```
me: firefox: settings: enable widevine by default
```

```
flake: inputs: update nixpkgs-unstable
```

### Nix: module option as path segment

```
hm-mod: monitors: size: make this option readOnly
```

## Language-Specific Conventions

### Rust

- **Path hierarchy**: `{crate}: {module}: {Type}: {fn}: description` — include only as many segments as needed.
- **Use Rust identifier casing in segments**: snake_case for modules/functions, PascalCase for types/traits/enums.
- **`impl` is the core verb** — always specify what:
  - Single function: `impl fn add_integer_type`
  - Multiple functions: `impl fns to_snake_ident and to_type_ident`
  - Trait implementation: `impl Display for NodeEdge`
  - Type initialization (with capabilities): `impl Hash with to_string`, `impl TypeNameTable with ident_for and aliases_for`
  - Const items: `impl const fns min, max, and bits`
- **Include generic parameters** when they disambiguate: `Literal<char>` vs `Literal<u8>`.
- **`cargo:` scopes Cargo.toml changes** with optional sub-scopes: `cargo: release: strip debug, abort on panic`, `cargo: lints: warn for unused_qualifications`, or crate-scoped: `codegen: cargo: set version independent of workspace`.
- **Lint/attribute changes** use the attribute directly: `expect(unused)`, `deny_unknown_fields`.
- **Dependency swaps**: `replace HashMap with IndexMap` or `switch from argh to bpaf`.
- **Common verbs**: `impl`, `add`, `remove`, `rename`, `replace`, `publicize`, `sanitize`, `require`, `normalize`, `format`.

### Nix

- **`flake:` scopes `flake.nix` changes.** — Lock-only updates use `flake: lock:` to disambiguate from flake expression changes. When a `flake.nix` change incidentally regenerates the lock, the lock update is buried — the summary names the `flake.nix` action.
- **`flake: inputs:` is a standardized scope** for flake input changes: `flake: inputs: update nixpkgs-unstable`.
- **`enable`/`disable` are natural verbs** for declarative NixOS/Home Manager option toggles.
- **NixOS module option names work as path segments**: `hm-mod: monitors: size: make this option readOnly`.
- **`init` for new derivations**: `packages: noita-entangled-worlds: init derivation`.
- **`patches:` for vendored patches**: `patches: webext-polyfill: add for missing filter props`.
- **`treewide: run nix fmt`** or **`treewide: run statix fix`** for formatter/linter passes.
- **`impl` for new functions**: name functions in path segments via `+`, with a purpose clause: `lib: lpad+rpad: impl for padding`. Names in the path are scannable in `git log`; the `for` clause explains why they belong in one commit. For single functions, the name can be a path segment or in the description: `lib: math: round: impl with decimal precision arg`.
- **Common verbs**: `enable`, `disable`, `set`, `update`, `override`, `wrap`, `migrate`, `add`, `remove`, `init`, `patch`, `increase`, `decrease`, `impl`.

## Temporary Commits and Rebase Prefixes

Pathwise summaries integrate naturally with `rebase`-centric workflows. During a session, the agent may create **temporary commits** — small, incremental snapshots of work that are not yet final. These use single-letter prefixes matching `git rebase -i` commands to signal their intended fate:

| Prefix | Rebase command | Meaning |
|--------|---------------|---------|
| `p` | pick | Keep as-is (default; rarely written explicitly) |
| `r` | reword | Keep but the summary needs revision |
| `s` | squash | Meld into a target commit, combining messages |
| `f` | fixup | Meld into a target commit, discarding this message |
| `d` | drop | Remove during rebase (scaffolding, debugging) |

### Format

```
<letter> <pathwise summary>
```

The commit body should explain the rebase intent when it isn't obvious — especially which commit to target and how many positions to move:

```
f skills: pathwise-commit: add missing example

fixup into 'skills: pathwise-commit: introduce skill from RFC'
```

```
s config: normalize default values

squash into 'config: introduce default configuration'
move up 3 commits
```

### When to use temporary commits

- When the conversation changes subject and returns later — record intermediate work as a temporary commit rather than losing it.
- When iterating on a change that will eventually be one logical commit.
- When the agent is uncertain whether a change is final.

### Rebase discipline

The agent should rebase temporary commits at its discretion — typically when:
- Returning to a subject after a digression
- The conversation reaches a natural checkpoint
- Before pushing or creating a PR

Temporary commits should never be pushed to a remote. They are local bookkeeping.

## When In Doubt

Consult the principles before inventing a new convention. If your own commit history has addressed a similar situation, follow the most recent consistent form.

If you still encounter an ambiguity not covered here, ask the user for clarification. If the ambiguity seems like a gap in the specification, suggest opening an issue at https://github.com/spikespaz/claude.
