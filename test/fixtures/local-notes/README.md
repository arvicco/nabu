# local-notes fixtures

Two real topic files for the owner-annotation shelf (P24-1, architecture
§16). This shelf's format is nabu's OWN (there is no upstream to snapshot):
one YAML list of note records per topic under `canonical/local-notes/`,
exactly what the `Nabu::NoteShelf` gateway (`nabu note`) appends — including
a deliberately dangling `--force` note on a not-yet-held urn
(`reading-log.yml`), the planned-material use the design sanctions.

Written 2026-07-16. `broken.yml.quarantine` is renamed into place by the
loader test to exercise the quarantine path (a `.yml` name would trip the
fixture-wide conformance sweeps).
