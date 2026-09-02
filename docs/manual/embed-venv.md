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

## Verify

```sh
nabu embed --status       # census + ETA, no model
nabu embed --limit 100    # bounded smoke run through the real worker
```

A different venv location works via `--venv DIR` or `$NABU_EMBED_VENV`.
Re-running the bootstrap is always safe; the store keys vectors by
model, so upgrading the MODEL is a deliberate act (a new model builds
beside the old rows, never over them).
