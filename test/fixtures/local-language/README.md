# local-language fixtures

Five real language dossiers for the canonical-memory shelf (P19-1,
architecture §16). This shelf's format is nabu's OWN (there is no upstream
to snapshot); the dossier bodies are the real curation verbatim from the
retiring `config/languages.yml` seed (git history, pre-P19-1) — i.e. exactly
what the owner-fired `nabu language --export-dossiers` migration writes —
plus, on `ine-pro.md`, a real accretion section (the LIV witness rider body
shipped by `Nabu::Adapters::Liv::LANGUAGE_NOTES`, P18-6) and front-matter
extras (`period`) exercising the extra-lane path.

Extracted 2026-07-14. `broken.md.quarantine` is renamed into place by the
loader test to exercise the quarantine path (a `.md` name would trip the
fixture-wide conformance sweeps).
