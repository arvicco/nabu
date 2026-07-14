# local-library fixtures

One fixture collection for the second canonical-memory shelf (P19-4,
architecture §16): `shelf/` stands in for `canonical/local-library/`, with
one collection dir (`slavistics/`) whose `manifest.yml` is the source of
record — the manifest format is nabu's OWN (there is no upstream to
snapshot), exercising every accounting story at once:

- `leskien-1871-handbuch.pdf` — a REAL 2-page PDF **with a text layer**,
  CONSTRUCTED locally (2026-07-14) because no trimmed public-domain scan was
  at hand: an abridged excerpt of A. Leskien, *Handbuch der altbulgarischen
  Sprache* (Weimar 1871, public domain), rendered text→PDF with macOS
  `cupsfilter`; the text layer was verified by PDFKit extraction (2 pages,
  349/227 chars). mutool's exact whitespace may differ from the injected
  test extractor's — the live-mutool test asserts substrings, not bytes.
  Manifest entry carries NO `license_class` → pins the research_private
  DEFAULT. `related:` carries one urn (→ reference edge) + one language
  code (→ metadata only).
- `jagic-notes.txt` — an owner-note text file (UTF-8 with OCS Cyrillic,
  NFC), explicit `license_class: open`; paragraphs become passages.
- `scan-plate.pdf` — a REAL PDF with NO text layer (cupsfilter over a PNG):
  metadata-only document, `text_layer: none`, never quarantined.
- `codex-plate.png` — image: metadata-only, awaiting the HTR era
  (improvements §3.4).
- `missing-notes.txt` — manifested but ABSENT on disk: discover yields no
  ref, the census reports it, LocalFetch/health carry the vanished story.
- `stray-unfiled.txt` — on disk but UNMANIFESTED: unrecognized in the
  discovery census (awaiting `nabu ingest`).

The shelf lives under `shelf/` (not this dir's root) so the P5-4 fixture
manifest below never collides with the shelf's own collection manifests.
