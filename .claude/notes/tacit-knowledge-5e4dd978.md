# Tacit Knowledge from Session 5e4dd978

Things the agent knew from context that aren't in any skill or memory file.

## User preferences observed but not codified

- Prefers em-dash `—` for formal text, tilde `~` for informal signatures
- Wants inline code for branch names in PR comments: `claude/branch-name`
- Uses `<sub>` tags for small text signatures on GitHub
- Signs comments with `~ JMB` (initials, not full name)
- Dislikes apologies in PR comments — just state facts
- Wants concise communication — "intelligence often finds succinct representations"
- Will push back on unnecessary PRs for small changes — "do not create pr for small format commit"
- Reads nix source code himself — provide GitHub permalink citations with line numbers
- Values the discovery history over clean squashed commits — "reviewability is the deliverable of pathwise"

## Working patterns observed

- Reviews PRs while the agent works, submitting comments asynchronously
- Sometimes forgets to submit pending reviews — agent should check
- Switches between repos (nixos-hosts, colemak-dh-windows-arm64, claude) during one session
- Uses "balance" as shorthand for "fetch, rebase all branches, push, update PR text"
- Uses "sync local" as shorthand for "update master, rebase branches, clean merged"
- Uses "reviewed" or "commented" to signal the agent should read new review threads
- Tests agent understanding by asking questions with known answers
- Asks "is policy broken?" to check if the agent's behavior contradicts its own documented rules

## Technical knowledge the agent accumulated

- `hosts/birdboot/default.nix` on master has the nixfmt-collapsed single-line imports — don't expand it in PRs that don't touch that file
- The `birdboot-portable-aarch64` line in flake.nix is too long for nixfmt-classic but is on master — a pre-existing gap
- WSL main worktree gets behind easily — always `git reset --hard origin/master` before evaluating
- `gh api repos/.../pulls/comments/<id>/replies` uses REST IDs, not GraphQL node IDs — GraphQL IDs (PRRC_...) don't work for the REST reply endpoint
- Force-pushing doesn't invalidate REST comment IDs on PRs — the comments persist
- `nix eval` with `.drvPath` takes ~20-25s in CI, which is the bottleneck for dedup checks
- GitHub Actions `env:` blocks on caller workflows don't propagate to reusable workflow_call jobs
- `pull_request: types: [synchronize]` fires for draft PRs — can't prevent the workflow from triggering, only skip jobs with `if:`
