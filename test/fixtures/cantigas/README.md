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
