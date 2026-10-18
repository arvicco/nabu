# AES fixture — Ancient Egyptian Sentences (P28-0)

Trimmed, real samples of the AES corpus: `github.com/simondschweitzer/aes`,
the TLA/BBAW January-2018 snapshot ("Teilauszug der Datenbank des Vorhabens
'Strukturen und Transformationen des Wortschatzes der ägyptischen Sprache'
vom Januar 2018", via AED-TEI).

- **Retrieved:** 2026-07-18, from commit
  `35276d2527cca1a055e31ed5f6683e777717170f` (master), via a blobless partial
  clone (`git clone --filter=blob:none`).
- **Layout:** the fixture mirrors the sparse workdir the adapter fetches:
  `files/aes/{_aes_<subcorpus>.json,aesschema.json}`. The repo's ROOT
  `README.md` (the license grant) is part of the production sparse cone but
  is NOT included here — its path would collide with this fixture README;
  the grant is quoted verbatim below and the fetch test builds it into its
  local upstream repo.

## Upstream census (at the pinned commit, whole-corpus)

- `files/aes/`: **16 subcorpus JSON files** (~342 MB): 101,796 sentences /
  13,026 texts / 815,026 tokens. Sentences are CONTIGUOUS per text in file
  order in all 16 files; a text never spans subcorpora; sentence ids are
  globally unique; owner/date/findspot are constant per text (0 conflicts).
- Token field coverage: written_form 815,026/815,026 (always present);
  lemmaID+lemma_form 779,011 (95.6%); cotext_translation 783,161;
  mdc 814,335; hiero 253,844; hiero_unicode 241,414; hiero_inventar 267,042;
  morphology 22,523. sentence_translation (German): 100,633/101,796 = 98.9%.
- **THE TRAP:** every one of the 241,414 `hiero_unicode` values is
  HTML-entity-encoded (`&#x13099;` — all hex-numeric; zero literal
  hieroglyphs, zero named entities, zero entities in any other field).
- **13,682 written forms are non-NFC**: the deprecated U+2329/U+232A math
  angle brackets (editorial supplements), which NFC canonically maps to
  U+3008/U+3009.
- `date` takes SIX values corpus-wide: "OK & FIP" ×36,326 / "NK" ×33,177 /
  "TIP - Roman times" ×16,426 / "MK & SIP" ×14,205 / "unknown" ×1,660 /
  degenerate "k" ×2 (both in bbawarchive). `findspot` takes 8 coarse values.
- **3 token-less sentences** corpus-wide (never a whole text) — no citable
  Egyptian surface; two carry a German translation.
- `files/relANNIS/` (~114 MB of zips) is the same data re-exported for
  ANNIS — outside the adapter's sparse cone, not fixtured.

## License (verbatim, repo README `## licence`)

> All files: [CC-BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/)

→ `license_class: attribution`.

## Files and trims

Trims are BYTE-VERBATIM whole-sentence blocks (CRLF line endings and all)
cut from the upstream files, re-wrapped in the original `{`/`}` — the only
non-verbatim byte is a trailing comma adjusted on each slice's last block.

| file | trim |
|---|---|
| `files/aes/aesschema.json` | whole (byte-verbatim) |
| `files/aes/_aes_tuebingerstelen.json` | texts `3F5KUVWQG5EPBM7GMQ6ZFVO5OQ` (12 sentences, NK, Upper Egypt — entity-encoded hieroglyphs incl. `&#x13099;`, U+2329 brackets) + `5YVC3WZOGZHSBGXTIEM7ZUG2UA` (2 sentences, TIP - Roman times, lemma-less tokens) — 823,861 B → 74,184 B |
| `files/aes/_aes_bbawarchive.json` | texts `26BP5JT5RZEDHDDU2R5TMUBD24` (4 sentences, OK & FIP, Middle Egypt) + `IMLY3YQIZFHHNJUGOZXVPOJTGU` (1 sentence, the real degenerate date "k", findspot unknown) + `NS6BAIQRENELJM2A2LDNHIYK6E` (3 sentences, one TOKEN-LESS with a German translation) — 5,855,067 B → 8,330 B |
| `files/aes/_aes_sawlit.json` | texts `2PD2OKCZCRELBGQD6NCAMOFEWA` (8 sentences, one WITHOUT sentence_translation) + `YSJ3UHIOBJEILCD7KFQIGVOCLY` (2 sentences, MK & SIP, U+2329 brackets + lemma-less token) — 90,848,753 B → 32,099 B |

Re-trim recipe: parse the upstream file, map sentence id → text id, keep the
raw lines of every sentence block whose text id is listed above (blocks are
contiguous per text), fix the final block's trailing comma, re-wrap in the
original first line + `}`.

## The AED header join fixtures (`aed/files/`)

`aed/files/<text-id>_hiero.xml` are the WHOLE, byte-verbatim AED per-text
stand-off files for the seven AES fixture texts above, copied from the
`canonical/aed` sparse clone (aed-tei, commit
`462c722e0323e05641aea2eee8cdf1e27303d939`), retrieved 2026-10-18. The
directory mirrors the aed workdir shape, so tests build a canonical root
with `aes/` → this fixture and `aed/` → `aed/` here. They drive
Nabu::AedTextHeaders, Nabu::AesAedTitles and the AED grain of
Store::TimelineBuilder::AesDates. What they cover:

| text | title | origDate label (grain) | origPlace |
|---|---|---|---|
| 26BP5JT5RZEDHDDU2R5TMUBD24 | pBerlin P 21002 verso (99 E) | Djedkare Asosi (reign) | Abusir |
| 3F5KUVWQG5EPBM7GMQ6ZFVO5OQ | Stele des Hai … | 18. Dyn. (dynasty) | Abydos |
| 5YVC3WZOGZHSBGXTIEM7ZUG2UA | Stele der Tadithor … | Makedonen, Ptolemäer (period; `-0332` zero-padded) | Achmim |
| 2PD2OKCZCRELBGQD6NCAMOFEWA | Eine Sammlung von Verboten (?) | 19. Dyn. / 20. Dyn. (differing labels) | westliches Ufer (a three-ref sub-site) |
| YSJ3UHIOBJEILCD7KFQIGVOCLY | 〈Stele des Nebanch (aus Abydos)〉 (bracketed editorial title, U+2329) | Sebekhotep IV. (reign) | Abydos |
| NS6BAIQRENELJM2A2LDNHIYK6E | 〈TEXT〉 placeholder | 6. Dyn. | Qubbet el Hawa |
| IMLY3YQIZFHHNJUGOZXVPOJTGU | 〈TEXT〉 placeholder | the 0001/0001 placeholder pair, empty labels | "3 = Fundstellen" (thesaurus root) |

Refresh recipe: copy `canonical/aed/files/<id>_hiero.xml` for each id.
