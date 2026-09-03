# The embed venv — one-time bootstrap (P93-4)

`nabu embed` runs the semantic-vector encoder (sentence-transformers,
`intfloat/multilingual-e5-base` — the P79-5 trial model) inside a Python
venv. The venv is a **tool, not data**: re-creatable from the network at
any time, so it lives OUTSIDE the repo and outside the permanent folders
(default `~/.nabu/venvs/embed`), is never backed up, and is never
touched by the test suite. This bootstrap is a one-time, owner-run,
network step — everything after it runs offline.

## Bootstrap (once per box)

```sh
python3 -m venv ~/.nabu/venvs/embed
~/.nabu/venvs/embed/bin/pip install sentence-transformers
```

Then pre-fetch the model — the worker itself runs with
`local_files_only=True`, so a missing model fails loudly rather than
fetching silently mid-campaign:

```sh
~/.nabu/venvs/embed/bin/python - <<'PY'
from sentence_transformers import SentenceTransformer
import os
SentenceTransformer("intfloat/multilingual-e5-base",
                    cache_folder=os.path.expanduser("~/.nabu/venvs/embed/models"))
PY
```

(~1.1 GB download; MPS is used automatically on Apple Silicon.)

## The vec0 step — the query-side scan engine

`search --similar` scans the store with the **sqlite-vec** loadable
extension (same tool class as the venv; NOT a gem — the rubygems
arm64-darwin build is a 2024 alpha predating int8 support). One-time
install of the prebuilt loadable:

```sh
mkdir -p ~/.nabu/tools/sqlite-vec && cd ~/.nabu/tools/sqlite-vec
curl -sL -o vec.tar.gz "https://github.com/asg017/sqlite-vec/releases/download/v0.1.9/sqlite-vec-0.1.9-loadable-macos-aarch64.tar.gz"
tar xzf vec.tar.gz && rm vec.tar.gz   # leaves vec0.dylib
```

A different location works via `$NABU_SQLITE_VEC=/path/to/vec0.dylib`.
Without it, `search --similar` refuses with this doc's name — never a
slow fallback scan.

## Verify

```sh
nabu embed --status       # census + ETA, no model
nabu embed --limit 100    # bounded smoke run through the real worker
```

A different venv location works via `--venv DIR` or `$NABU_EMBED_VENV`.
Re-running the bootstrap is always safe; the store keys vectors by
model, so upgrading the MODEL is a deliberate act (a new model builds
beside the old rows, never over them).
