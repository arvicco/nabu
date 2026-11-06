# stationers-register fixture

Retrieved 2026-11-05 by direct HTTP from
`https://raw.githubusercontent.com/gbergel/SRO_data/562db00188362aa37db5f3ca202c81138c4908fb/<path>`
— the master head of github.com/gbergel/SRO_data (Stationers' Register
Online; last push 2019-08-27; the SRO_Arber_data repo name redirects to
the same repository, same head sha). Paths below are upstream's own,
including the trailing space in the directory name `Register `.

## Delivery grains (every grain upstream serves)

| grain | where | taken? |
|---|---|---|
| the repository | github.com/gbergel/SRO_data, 64 files, 248.5 MB working tree | TAKEN — depth-1 git clone |
| register file | `Register /CURRENT Register/reg_{A,B,C,D}-updated.xml` (3.9 / 6.3 / 10.4 / 9.4 MB) | TAKEN — the four current registers |
| copy entry | `<div type="entry" xml:id="SRO<n>">` inside each register file (A 1,391 · B 2,356 · C 3,530 · D 3,176 = 10,453) | TAKEN — document = entry |
| entry block | the entry div's element children: `<head>`, `<p>`, `<desc>`, `<list>`, a register `<note>` | TAKEN — passage = block |
| Arber rendering | `Arber/` (19 files: "Arber Book Entries only", "Arber Entries with metadata", "Arber full text" — Arber's 1875–94 Transcript, the older encoding of the same entries, REUSING the SRO ids) | REJECTED — skipped by rule; one specimen pinned |
| superseded version | `Register /OLD Register/` (27 files: earlier working versions of the same registers) | REJECTED — skipped by rule; one specimen pinned |
| schema / stylesheet | `sro-transcription.rng`, `sro-proofing-view.xsl` (CURRENT Register/ and Register /, 4 files) | REJECTED — skipped by rule; the CURRENT stylesheet pinned whole |
| project documents | `README.md`, `JC-changes-actually-made.pdf` | REJECTED — skipped by rule (this README occupies the upstream README's path; the PDF is not pinned) |
| Finder litter | `.DS_Store` × 8 | REJECTED — skipped by rule (not pinned) |
| the website | stationersregister.online (an eXist-db front end over the same TEI) | not fetched — the GitHub TEI is the published data |

## Files

Register files are byte-verbatim TRIMS: the whole original prolog and
teiHeader, a handful of complete entry divs sliced at their own start
tags (byte-identical, inter-entry indentation normalized), and the
file's own closing tail (`</body>` on, including upstream's closing
comment). Every entry is real and whole.

- `Register /CURRENT Register/reg_A-updated.xml` — SRO1 (the first entry,
  William Pekerynge's ballad "a Ryse and wake", 1557, company-year span),
  SRO4 (a `<del>`), SRO8 (Wallye and Toye's 32 ballads — 34 paragraphs,
  33 reading blocks,
  Arber's notes inline and in the metadata block, an editorial note, the
  Clerk's `resp="#register"` sum line, a note-only paragraph), SRO218 (a
  head-only entry whose whole text is the register's own `<note>`, with
  `<space><desc>` and an Arber note inside).
- `Register /CURRENT Register/reg_B-updated.xml` — SRO1679 (a cancelled,
  struck-through entry: Dodoens's herbal), SRO1688 (marginal `<desc>`
  names between the copies), SRO2203 (head-only; a `<placeName>` inside a
  persName).
- `Register /CURRENT Register/reg_C-updated.xml` — SRO4539 (a `<list>`
  of sermons, title parts), SRO5992 (a Dutch `<foreign>` copy-title).
- `Register /CURRENT Register/reg_D-updated.xml` — SRO8024 (a register
  note with BH's `<supplied>`, an Arber note in the head, a reassigned
  copy), SRO9195 (`<choice>` sic/corr inside `<unclear>`), SRO10453 (the
  last entry, John Stafford, 1640). Register D's teiHeader is the older
  Arber-volume shape (licence text broken over two lines).
- `Register /CURRENT Register/sro-proofing-view.xsl` — whole (13,234
  bytes): the stylesheet grain's specimen.
- `Register /OLD Register/reg_A-JC-updates-2017-10-30.xml` — trimmed to
  its header + SRO1: the superseded-version grain's specimen (same SRO
  ids as the CURRENT file — the reason it must never be discovered).
- `Arber/Arber Entries with metadata/arber 1 29-1-2017.xml` — the first
  134 lines whole (header + the first folio div: the Clerk's heading and
  Arber's entry for SRO1, which merges what SRO splits as SRO1–SRO2) +
  the file's closing tail: the Arber grain's specimen.

## Census of the whole asset (through the adapter, 2026-11-05)

Discover: 10,453 refs = 10,453 documents / 26,047 passages (p 15,745 ·
head 10,285 · desc 11 · note 5 · list 1), 0 errors, 0 skipped; ~10 s
on this box. Register dates: when 9,111 · notBefore/notAfter 1,342;
SortDate 1557–1640 on every entry. Persons on 10,439 entries; places on
559 (1,157 `<placeName>`). Licence target
`http://creativecommons.org/licenses/by/4.0/` in all four headers.
Discovery skips over the 64-file tree: 60 by rule, 0 unrecognized.

Recipe to re-cut: fetch the files above from the pinned sha, keep the
prolog + teiHeader, the named entry divs (start tag to the next entry's
start tag) and the tail from `</body>`.
