# The git hook pack — one-command install

Three commit-time checks for anyone committing to this repository. They
compile disciplines that used to live only in prose — and were each
broken more than once — into the one path every change takes.

## Setup — one command

```sh
bundle exec rake tools:hooks
```

Idempotent and safe to re-run: each hook is announced and skipped when
already linked. `rake tools:status` shows the hooks beside the other
tools. No network, nothing outside the repository's own hooks
directory.

What the task does (the executable truth is `Nabu::Ops::GitHooks`,
exercised by `test/ops/git_hooks_test.rb`): it symlinks the tracked
scripts `script/git-hooks/pre-commit` and `script/git-hooks/commit-msg`
into the hooks directory (`git rev-parse --git-path hooks`). Linked
worktrees share that directory, so the links always point at the MAIN
checkout's scripts — run the task from any checkout; a worktree's own
copy would dangle once the worktree is removed. A hook file that is
already there and is not ours is never replaced; the task says so and
leaves it.

## What the hooks refuse

| Hook | Refuses | Why |
|---|---|---|
| pre-commit | a conflict marker in staged content — any of the three marker strings on a line of its own (`test/fixtures/` exempt: upstream bytes stay verbatim) | a resolved-by-hand merge can leave a lone separator line behind; a sweep for only the opening marker misses it |
| pre-commit | a staged change under `lib/nabu/` or `db/migrate/` while a `nabu rebuild` (any flavor except `--dry-run`) runs **from the same checkout** | the rebuild stamps derivation fingerprints from the bytes on disk at stamp time, hours after it loaded its code — a mid-run commit stales or falsifies every stamp it mints. A rebuild running from another checkout (the main tree, while you commit in a worktree) does not hold |
| commit-msg | AI-attribution trailers, footers and session links; internal workflow identifiers | commit messages are a public surface: technical content and license-provenance facts only (the tracked-file half is guarded by `test/public_hygiene_test.rb`) |

Every refusal prints the reason and the override. The override is git's
own: `git commit --no-verify` — a deliberate act, never a default.

## Cost

Both hooks together run in well under a second: one `git diff --cached`,
one `ps`, and an `lsof` only when a rebuild is actually running. The
scripts load nothing but the Ruby standard library.

## Removal

Delete the two symlinks from the hooks directory; nothing else was
touched.
