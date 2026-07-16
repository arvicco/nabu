# damaskini fixtures — Annotated Corpus of Pre-Standardized Balkan Slavic Literature 1.1

Trimmed real slices of the Damaskini 1.1 distribution (Škrabal/Derksen/
Kopřivová et al.; CLARIN.SI). Extracted **2026-07-15** from the two data
bitstreams the deposit serves (auth-free DSpace bitstreams):

    https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1441/Damaskini.CoNNL-U.zip
    https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1441/Damaskini.TSV.zip
    (handle: http://hdl.handle.net/11356/1441 — v1.0 = 11356/1368 is GPL-3
    and superseded; 1.1 only. NB the upstream zip filename really spells
    "CoNNL-U", sic.)

Trimming = whole sentence blocks / token rows removed; every retained line
is byte-identical to upstream.

## License chain (verified 2026-07-15)

- Deposit record verbatim (`dc.rights`, REST + record page): "Creative
  Commons - Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)";
  `dc.rights.uri` <https://creativecommons.org/licenses/by-sa/4.0/>;
  access label PUB (no auth).
- The bundle's own `license.txt` bitstream is the depositor→CLARIN.SI
  distribution agreement, NOT the public grant — the CC BY-SA grant lives
  on the record page.

→ CC BY-SA 4.0 → `license_class: attribution`. Attribution: Annotated
Corpus of Pre-Standardized Balkan Slavic Literature 1.1, CLARIN.SI
(hdl 11356/1441).

## Files

| fixture | trimmed to | exercises |
|---|---|---|
| `conllu/damaskini.conllu` | 3 of the 23 `# newdoc id` blocks, first 12 sentences each | the one corpus-wide CoNLL-U file; corpus-CONTINUOUS sentence numbering (`berlinski….1–12`, `nedelnik1806….3487–3498`, `veles….5601–5612`); gold lemma + MULTEXT-East `msd-bg-dam` XPOS + UD deps; `# text_en` on every sentence; mixed Latin/Cyrillic diplomatic text (ъ everywhere; ѯ in `nedelnik1806….3488`, ѳ in `veles….5603`) |
| `tsv/berlinski--slovo-petki.txt` | header block + first 31 token rows | regular header (name / "Pleven?, 1791" / scribe "pop Georgi" / folio span / title); 16-col layout with `cyrillic` column (`Слнце+`, `свѣ́тъ,` — combining accents, NFC-mixed) |
| `tsv/nedelnik1806--skazanie-paraskevy.txt` | header block + first 31 token rows | print-era witness ("Râmnic, 1806", Sofronii ep. Vračanskii); two-line title (last line wins, rest → header notes) |
| `tsv/veles--trojanskata.txt` | header block + first 31 token rows | Church Slavonic witness; century-only date ("XV c.", no place); NO scribe line; two `S1:`/`S2:` edition-locus lines |

## Format notes (upstream reality, do not "fix")

- The CoNLL-U is ONE corpus-wide file: 23 `# newdoc id` blocks / 6,036
  sentences / 53,257 tokens. Comment keys are exactly `newdoc id`,
  `sent_id`, `text`, `text_en` (censused; no per-doc metadata comments).
  100% NFC; 100% `text_en` coverage; FEATS and MISC are `_` on every
  token; no multiword-token ranges.
- `sent_id` = `<newdoc-id>.<n>` where n is CORPUS-continuous (berlinski
  ends at 453, ioan starts at 454). The passage citation is the numeric
  tail — upstream's own sentence number, unique within a document.
- Surface text = the corpus's "diplomatic" transliteration layer: Latin
  letters PLUS real Cyrillic for sounds without Latin equivalents —
  ъ (8,030×), ѳ, ѯ, ѵ, ѱ, ћ, џ, ь, ꙫ. The fully Cyrillic and the accented
  layers live in the TSV token columns (phase-2; see backlog P23-1).
- TSV files (one per document, filename = newdoc id VERBATIM, case
  included: `xrulev--za-sv-Paraskeva.txt`): a free-text header block, then
  a column-header row whose first cell is `text`, then token rows. Column
  layout VARIES per file (15–20 columns; 3 files — nbkm1064, raikovski,
  nbkm1423 — have NO `cyrillic` column) — the per-file header row is
  authoritative. The adapter reads ONLY the header block (source name,
  place+date, optional scribe, locus/edition refs, title); token rows are
  retained here as phase-2 layer evidence (accented | cyrillic |
  diplomatic | folio | translation | chunk | ref).
- Header date formats censused across all 23: `1791` · `1580s` ·
  `1650-1670s` · `17th` · `XV c.`/`XVII c.` · `19th (post 1817)`; xrulev
  has no date line (year 1856 rides in "ed. T. Xrulev 1856"). Places
  carry honest question marks ("Pleven?", "Etropol?") — kept verbatim.
- TSV sentence numbering RESTARTS per file and 5 files differ from the
  CoNLL-U by 1–3 sentences (jankul 293 vs 296, kievski 579 vs 580,
  krcovski 316 vs 317, raikovski 315 vs 316, veles 182 vs 183) — why
  token-layer merging is a phase-2 alignment job, not a rider.
- Language: the deposit is tagged `bul, mkd` COLLECTIVELY; no per-document
  machine tag exists. The philological description (deposit PDF) classes
  each source by Norm: Church Slavonic (veles, vukovic, kievski), simple
  Bulgarian (14), Slavenobulgarian (5), standard Bulgarian (xrulev), with
  dialectal Origin (Macedonia/Rhodopes/Serbia-Torlak/West/East Bulgaria)
  as a separate axis, and states (fn. 7) the glottonym "Bulgarian" is used
  "for historical reasons - the included sources do not use 'Macedonian'
  or 'Serbian'". The adapter maps Norm → language: chu for the three
  Church Slavonic witnesses, bul for the rest; Norm and Origin ride as
  document facets.
- Corpus: 23 samples ("damaskini" and other Balkan Slavic manuscripts and
  prints, 15th–19th c.), ~10 of them independent witnesses of Euthymius
  of Tarnovo's *Life of St. Petka*.
