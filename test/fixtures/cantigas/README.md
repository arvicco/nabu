# Cantigas fixtures

Real pages from Cantigas Medievais Galego-Portuguesas
(<https://cantigas.fcsh.unl.pt>; Projeto Littera, Instituto de Estudos
Medievais, FCSH/NOVA Lisbon — coordinators Graça Videira Lopes and Manuel
Pedro Ferreira). Retrieved 2026-07-31 (the P55-1 scout, 11 bounded
probes). License: free with attribution — the coordinator's grant
(G. V. Lopes, 2026-07-27, license thread №45-2): "Our site is free for
all. So, with full attribution, you can do whatever you like with the
data."

**Encoding (the corpus's key quirk, preserved deliberately): every file
keeps its raw Windows-1252 bytes — do NOT transcode fixtures.** The
Content-Type header carries no charset, the in-page meta claims
ISO-8859-1, and the actual bytes are Windows-1252: `cantiga-1400.html`
carries 0x92 (’) in its rubric, `fetch/cantiga-1-with-notes.html`
carries 0x93/0x94 (“ ”) and 0x96 (–) in its notes. Line endings are
CRLF. Medieval nasals (ũ ẽ) arrive as numeric character entities.

The site is a Classic ASP application on IIS: `cantiga.asp?cdcant=N` is
one page per cantiga (cdcant ids are SPARSE — letter A alone reaches
1713; an invalid id answers HTTP **500**, not 404), enumerated only via
the 23 alphabetical incipit indexes `listacantigas.asp?letra=A`…`Z` (no
K/W/Y; Z is valid but empty). The fetch uses `semanotacoes=true`
(verified: strips the note spans/icons for clean verse lines while
keeping author, rubric, sidebar metadata and the Nota geral) and drops
the cosmetic `pv` parameter (byte-diff-verified no-op).

## Document pages (crawl filenames, discovered by the adapter)

- `cantiga-1.html` — cantiga 1 (Anónimo, **Lai**, the first text of the
  Cancioneiro da Biblioteca Nacional): rubric, 43 verse lines in 11
  stanzas (10 cobras + 3-line finda), sidebar sigla "B 1, L 1" and
  "(C 1)", Nota geral with references. Fetched WITH
  `semanotacoes=true` — the variant the crawl lands, so it sits at the
  crawl filename as the primary parse fixture
  (URL: `cantiga.asp?cdcant=1&semanotacoes=true`).
- `cantiga-600.html` — cantiga 600 (D. Dinis, **Cantiga de Amigo**,
  "- Amigo, queredes-vos ir?"): 24 lines / 4 stanzas, no rubric, sigla
  "B 575/576, V 179" + "(C 575)". Fetched WITHOUT `semanotacoes` (the
  scout's probe shape, noted honestly) — glossary/nota icons and inline
  `span.refN` word wrappers present; the parser must tolerate both
  variants (URL: `cantiga.asp?cdcant=600&pv=sim`).
- `cantiga-1400.html` — cantiga 1400 (Martim Soares, **Cantiga de
  Escárnio e maldizer**, "Ũa donzela jaz [preto d]aqui,"): 21 lines /
  3 stanzas, composite rubric carrying the raw 0x92 (’) byte —
  "…fez d’escarnho…" — the Windows-1252 regression exemplar. Fetched
  WITHOUT `semanotacoes`, as above
  (URL: `cantiga.asp?cdcant=1400&pv=sim`).

## The P56-1 quirk pages (the first sync's 7 quarantines, all REAL)

The 2026-07-31 first sync (1,683 pages) quarantined 7; every page was
investigated against its real bytes (retrieved 2026-07-31 with the
crawl; copied byte-identically from `canonical/cantigas/` on
2026-08-02, raw Windows-1252 preserved). Six are edition-intended
shapes the parser now tolerates WITH annotations; one is genuinely
textless upstream and stays quarantined.

**The printed-number gap pages** — `cantiga-475.html` (Afonso X,
Escárnio e Maldizer), `cantiga-959.html` (João Airas de Santiago,
Amor), `cantiga-1025.html` (João Airas de Santiago, Amigo),
`cantiga-1706.html` (Alvaro Afonso, Espúria/Fragmento, with rubric):
the edition's printed every-5th line numbers run AHEAD of the display
ordinal, and the offset grows ONLY across stanza-break rows. All four
are sidebar-marked **Refrão**: the edition's numbering counts refrain
lines the page display merges or elides (475's single displayed
refrain line answers two counted edition lines per cobra; 959 counts
one extra per cobra plus two before the finda — printed "25" pins the
finda at edition 23–26; 1025 opens one gap after cobra 1 and the later
printed "15" proves the offset then holds; 1706 counts one extra line
its fragment display omits). The parser adopts the edition's numbering
(urn line = edition line, gaps visible: 475 → 1–5, 7–11, 13–17),
annotates the first line after each gap with `"number_gap" => d`, and
totals them in document metadata `"number_gaps"`. A printed number
that mismatches mid-stanza, or runs BEHIND, still quarantines.

- `cantiga-562.html` (D. Dinis, Amor, Refrão): the verse table's row
  20 is **numbered "20" but textless** — the edition counts a final
  line (after the one-line finda "ou de me quererdes valer.") whose
  text the page does not display. The row consumes its edition number,
  cross-checks like any other, yields no passage, and is recorded in
  document metadata `"empty_lines" => [20]` (19 passages).
- `cantiga-1241.html` (Amigo): `p.titulo-autor` carries the literal
  label **"[Sem autor atribuído]"** and no `autor.asp` link — the
  corpus's one unattributed cantiga (upstream's own shape, distinct
  from "Anónimo" pages, which have a real author entry with a cdaut
  id). Recorded honestly as metadata `"unattributed" => true`; no
  author is minted. Any other linkless author paragraph still
  quarantines.
- `quirks/cantiga-1066.html` (João Airas de Santiago) — **stays
  quarantined**, which is why it sits outside the discover path: the
  page carries `<p class="discreto">Texto ainda não disponível</p>`
  where the verse table would be. Per its Nota geral the cantiga is
  doubly transcribed in the apógrafos italianos and Littera has not
  published a text for this entry. Nothing to ingest; the quarantine
  message names the marker, and the page waits on upstream.

Corpus census after the heal (verified 2026-08-02 by a read-only
reparse of all 1,683 canonical pages): **1,682 documents / 34,162
verse passages, 1 quarantine (1066)**; the tolerance annotations fire
on exactly the six pages above and nowhere else.

## Fetch fixtures (`fetch/`, invisible to discover)

- `fetch/listacantigas-A.html` — the letter-A incipit index WHOLE: 326
  `cantiga.asp?cdcant=` links (incipit link + music-icon duplicates) →
  244 unique ids, min 1 / max 1713 (the sparse-id proof; matches the
  scout's id census exactly). 4-column rows: incipit, music icons,
  author, genre — the genre column shows BOTH "Escárnio e maldizer" and
  "Escárnio e Maldizer" (the case-variance the parser normalizes)
  (URL: `listacantigas.asp?letra=A`).
- `fetch/listacantigas-Z.html` — the valid-but-empty letter page: zero
  cantiga links, the honest-empty marker "Não existem cantigas…"
  (URL: `listacantigas.asp?letra=Z`).
- `fetch/cantiga-9999-500.html` — the IIS "500 - Internal server error"
  body an invalid cdcant answers (HTTP status 500). The fetch treats a
  500 on a LISTED id as a real error (retry then FetchError), never a
  parse quarantine (URL: `cantiga.asp?cdcant=9999`).
- `fetch/cantiga-1-with-notes.html` — cantiga 1 fetched WITHOUT
  `semanotacoes` (`pv=sim` variant): the note-icon/tooltip apparatus in
  full, plus the 0x96/0x93/0x94 Windows-1252 bytes in the Nota geral.
  Paired with `cantiga-1.html` to prove both page variants parse to
  identical verse text (URL: `cantiga.asp?cdcant=1&pv=sim`).
