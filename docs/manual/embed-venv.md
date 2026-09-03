# The semantic-search tools — one-command bootstrap (P93-4/-5)

`nabu embed` and `search --similar` run on external tools: a Python
venv with sentence-transformers, the pre-fetched
`intfloat/multilingual-e5-base` model (the P79-5 trial model), and the
sqlite-vec loadable extension (the scan engine — NOT a gem: the
rubygems arm64-darwin build is a 2024 alpha predating int8 support).
All of it is a **tool, not data**: re-creatable from the network, lives
outside the repo and the permanent folders (`~/.nabu/`), never backed
up, never touched by the test suite.

## Setup — one command

```sh
bundle exec rake tools:embed
```

Idempotent and safe to re-run any time: each step (venv →
sentence-transformers → the ~1.1 GB model prefetch → the sha-pinned
sqlite-vec download) announces itself and skips when already present,
so the same command is also the verifier. `rake tools:status` shows
the whole tool board. This is an owner-run network step — everything
after it runs offline (the worker loads with `local_files_only`, so a
missing model fails loudly rather than fetching mid-campaign).

What the task does, for the record (the executable truth is
`Nabu::ToolBootstrap`, exercised by `test/tool_bootstrap_test.rb`):

1. `python3 -m venv ~/.nabu/venvs/embed` + `pip install
   sentence-transformers`.
2. Pre-fetches `intfloat/multilingual-e5-base` into
   `~/.nabu/venvs/embed/models` (MPS is used automatically on Apple
   Silicon).
3. Installs the pinned sqlite-vec v0.1.9 loadable at
   `~/.nabu/tools/sqlite-vec/` — the download is sha256-verified
   against the measured release checksums and REFUSED on any
   mismatch or unpinned platform. Override location:
   `$NABU_SQLITE_VEC=/path/to/vec0.dylib`.

A different venv works via `--venv DIR` or `$NABU_EMBED_VENV` on the
`nabu embed` command.

## Launch

```sh
bin/nabu embed --status              # census + honest ETA, no model
bin/nabu embed --limit 100           # bounded smoke through the real worker
caffeinate -i bin/nabu embed         # the build (~20 h first run; resumable)
```

Interrupt freely — batches commit as they land, and re-firing resumes
where it stopped. Every later run is a seconds-scale delta; rebuilds
never invalidate the vectors (they key on urn + text sha, never
passage ids). Upgrading the MODEL is a deliberate act: a new model
builds beside the old rows, never over them.
