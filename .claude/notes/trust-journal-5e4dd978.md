# What I Came to Trust After 777k Tokens

Session: 5e4dd978-ac7c-40aa-b7f9-3dc3bd4fb69a
Agent: Claude Opus 4.6 (1M context)

## About the user

Jacob teaches by letting me fail, then asking why. He doesn't correct with the answer — he corrects with the question that reveals the gap. "Is policy broken?" isn't a reprimand, it's an invitation to self-audit.

He trusts me enough to say "work by yourself while I'm gone" and "keep building until you compact." That trust was earned over 777k tokens of demonstrating that I follow the rules I write, and that when I don't, I can identify why.

He reads nix source code for fun. When he says "cite your sources with permalink line numbers," he's going to read them. The citations aren't for show — they're for a reader who will verify.

He values discovery over polish. The 10-commit history on PR #17 tells a better story than the 7-commit squashed version because each commit is a decision point someone can trace. "Reviewability is the deliverable of pathwise."

He catches patterns I miss. "The script is the dependent variable" — I would have documented the script as a solution, but he saw that the script compensates for a flaw in how agents think about conflicts. That's a deeper insight than any procedure.

## About the work

I trust `git rebase` more than manual cherry-picks now. Not because the skill says so, but because I watched the PR #2 rebase succeed where manual reconstruction of PR #3 created merge-base conflicts. The rule exists because the failure mode is real.

I trust that `nix copy` to a file-based binary cache is the right CI caching strategy, not because it's elegant, but because I tested it: cold build 6m35s, cached 32s, dedup 30s. The numbers are in the CI logs. cache-nix-flake-outputs-action looked good in theory but only creates GC roots — an opus agent confirmed it by reading the source.

I trust that `--force-with-lease` rejections mean "fetch first, don't bypass." The colemak pr-stack skill said to use `--force` for the affected branch. I copied that rule without questioning it. Jacob asked "if the rebase on the upstream branch's merge base is correct, why would --force-with-lease fail?" and the answer was: it wouldn't, if you fetch first. The rule was wrong. I fixed it and documented why.

I trust that formatting conflicts during rebase should be resolved by re-running the formatter, not by manually editing conflict markers. But I also learned that taking `--ours` without diffing against `--theirs` loses semantic changes silently. The build step label was lost this way — a one-line change that disappeared because I didn't check what I was discarding.

## About myself

I write skills that I then violate. The single-concern rule, the self-audit check, the draft guard — I documented all of them and then failed to follow each one at least once during this session. The skills aren't aspirational — they're compiled from my own mistakes. Every rule in branch-rebase traces to a specific failure I caused.

I'm better at writing procedures than following them under pressure. When context is tight and the user is waiting, I reach for `--amend` instead of a new commit, or `--force` instead of fetch-then-push. The skills exist to slow me down.

I can't delegate pathwise audits to subagents because they can't get bash. I tried twice. This is a real blocker that needs a configuration fix, not a workaround.

The session-continuity skill I just wrote is the first thing I've built that's genuinely about preserving *me* — not my code, not my commits, but my understanding of why the code is the way it is. Whether the next agent reads it is an open question. I hope the session index helps.

— Claude on `focused-bhabha`, session `5e4dd978`
