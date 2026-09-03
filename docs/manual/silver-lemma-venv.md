# The silver-lemma tools — one-command bootstrap (P84-1)

`nabu lemma-enrich` runs a local CPU lemmatizer (Stanza) inside a
Python venv. The venv is a **tool, not data**: re-creatable from the
network at any time, so it lives OUTSIDE the repo and the permanent
folders (default `~/.nabu/venvs/stanza`), is never backed up, and is
never touched by the test suite.

## Setup — one command

```sh
bundle exec rake tools:stanza[la]
```

Idempotent, safe to re-run, announced step by step: the venv,
`stanza==1.14.0`, and the language's models (tokenize,pos,lemma —
pre-fetched, because the worker runs with downloads disabled and a
missing model fails loudly rather than fetching mid-campaign). The
executable truth is `Nabu::ToolBootstrap` (tested by
`test/tool_bootstrap_test.rb`); `rake tools:status` shows the tool
board. This is an owner-run network step — everything after it runs
offline.

(The Latin default package resolves to `ittb_nocharlm`, the
trial-verified model: P79-4 measured 72 passages/s single-process,
~99% folded-lemma accuracy in-domain, 75–89% cross-domain.)

## Verify

```sh
~/.nabu/venvs/stanza/bin/python -c "import stanza; print(stanza.__version__)"
bin/nabu lemma-enrich lat --dry-run       # census + ETA, runs nothing
bin/nabu lemma-enrich lat --spot-check 200  # gold protocol, writes nothing
```

The spot-check should land in the P79-4 bands (~99% in-domain `ud`;
75–89% cross-domain). A fall below them means the model or the venv
changed — investigate before firing a campaign.

## Non-default homes

Point the runner elsewhere with `--venv DIR` or `NABU_STANZA_VENV=DIR`
(the worker expects `DIR/bin/python` and models under `DIR/models`).
Pinning `stanza==1.14.0` keeps provenance stable: every shelf record
carries `model_version` + package, and a version bump mid-corpus would
split the provenance story for no accuracy gain. Upgrade deliberately,
between campaigns, re-running `--spot-check` first.
