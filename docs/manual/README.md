# docs/manual — human acquisition instructions

Some upstreams cannot be fetched by a machine: captcha interstitials,
POST-form dumps, account walls with a license checkbox. A human can
fetch them — and did, once. This folder makes each of those
acquisitions **replayable**: one document per source, written for any
Nabu user, with the exact steps, URLs, expected files and sizes, the
license-capture moment, and where the download goes afterwards.

**The convention (owner-ruled 2026-08-27):** every source whose
acquisition involves human steps gets a human-targeted instructions
document here — including acquisitions performed before this folder
existed, researched and recreated so they stay replayable. New
manual-acquisition sources mint their doc **with** the adapter, in the
same change.

## The two halves that must agree

Where an adapter exists, the acquisition contract lives **in code** as
a `Nabu::ManualDrop::Spec` (architecture §8): `nabu sync <slug>` prints
an instruction card while `incoming/<slug>/` is empty, then validates
and ingests the drop with full provenance (`.manual-fetch.json`,
per-file sha256, attic retention). These documents are the card's
human-readable companion — same URL, same steps, same file list — and
`test/docs/manual_acquisition_docs_test.rb` pins the agreement: a Spec
edit without a doc update is a red suite, and every ManualDrop source
without a doc here is too.

## The license-capture step

Manual acquisition routes are usually exactly where upstream shows its
terms — a dataset page's license field, a checkbox above a download
button. Every doc names that moment explicitly: **capture the license
name/text verbatim as displayed at acquisition time** (a screenshot or
copied text), because the library records the grant per source and per
passage, and the page's wording can drift between acquisitions. Where
this project has already observed such drift, the doc says so.

## What does NOT belong here

- **Owner-fired but automated syncs.** Most `sync_policy: manual` rows
  in `config/sources.yml` are ordinary unattended fetches that a human
  merely *initiates* (multi-GB clones, rarely-changing upstreams).
  No human steps, no doc.
- **Automated click-through consent.** bdcamoes and the CIPM-class
  sources (ruling №R-37) present a license form that
  `Nabu::LicenseAgreeFetch` reads, verifies against the declared
  license text, and agrees to mechanically. That is an automated
  acquisition with a consent guard, not a manual one — excluded by
  design, so the boundary stays legible.
- **The owner's own shelves.** `local/shelves/` intake (the library,
  dossiers, notes) goes through `nabu ingest` / `nabu note`; that
  workflow is documented in `docs/library.md` §Ingest, not here.

## The documents

Live sources whose acquisition is manual today:

- [trismegistos-geo.md](trismegistos-geo.md) — Trismegistos Geo table
  dump (captcha + POST form; the one true ManualDrop adapter).

Sources acquired by hand during their build (2026-08), now fetched
unattended by their adapters — kept replayable in case the automated
route breaks or a human wants the files directly:

- [achemenet.md](achemenet.md) — Zenodo deposit download.
- [burman-concordance.md](burman-concordance.md) — Zenodo CSV download.
- [sillok.md](sillok.md) — data.go.kr bulk XML (two datasets).
- [sjw.md](sjw.md) — data.go.kr bulk XML (the 2.4 GB one).
- [goryeosa.md](goryeosa.md) — data.go.kr bulk XML.
- [goryeosa-jeoryo.md](goryeosa-jeoryo.md) — data.go.kr bulk XML
  (license field drift observed; see the doc).
- [bibyeonsa.md](bibyeonsa.md) — data.go.kr bulk XML.
- [itkc.md](itkc.md) — data.go.kr bulk XML, seventeen datasets +
  the formal request path for the rest.

Pending acquisitions (adapter not built yet; the doc leads the code):

- [ivdnt-corpora.md](ivdnt-corpora.md) — the IvdNT/INT Dutch corpora
  behind the taalmaterialen registration wall (Corpus Gysseling,
  Corpus Oudnederlands; CRM14 and Corpus Oudfries tracked).

Tool bootstraps (a one-time local setup a human runs once, not a data
acquisition — kept here because it is the same "replayable human step"
class):

- [silver-lemma-venv.md](silver-lemma-venv.md) — the Python/Stanza
  venv `nabu lemma-enrich` needs (P84-1); a tool, re-creatable from
  the network, never data.
