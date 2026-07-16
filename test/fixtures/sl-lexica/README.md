# sl-lexica fixtures (P23-2 — the Slovenian historical dictionary shelf)

Real upstream samples from the THREE ZRC SAZU dictionary deposits on
CLARIN.SI (owner-approved 2026-07-15; scouted in docs/clarin-si-survey.md §2).
Every kept entry line is **byte-verbatim** upstream data (the extraction
asserted each emitted line is a substring of the raw file, line terminators
included); only the entry SET was trimmed. XSDs ship whole — they are the
upstream documentation of the element vocabulary.

## The three artifacts — retrieved 2026-07-15, one GET each

| dir | deposit | zip (verbatim size/MD5 = the record's own checkSum) |
|---|---|---|
| `pletersnik/` | **Slovenian-German Dictionary of Maks Pleteršnik (1894-1895)**, hdl [11356/1114](http://hdl.handle.net/11356/1114) | `Pletersnik.zip`, 4,807,154 bytes, MD5 `3576172230b582f8929d794263f98d01` → `Pletersnik.xml` (25 MB, 103,185 `<rc>` entries — the description's count exactly) + `pletersnik.xsd` |
| `jsv/` | **Dictionary of the Slovenian Language in the Works of Janez Svetokriški**, hdl [11356/1092](http://hdl.handle.net/11356/1092) | `JSV.zip`, 1,785,628 bytes, MD5 `e5f1f19336b7100149103ca53b39d61d` → `JSV.xml` (5.4 MB, **8,461** `<ge>` entries — the description says 8,540; the counted delta is upstream reality, reported honestly) + `JSV.xsd` |
| `besedje16/` | **Words of the 16th-Century Slovenian Literary Language**, hdl [11356/1127](http://hdl.handle.net/11356/1127) | `besedje16.zip`, 447,911 bytes, MD5 `d85b2493b81e4d6cdd4ffc8f7b45ee21` → `besedje16.xml` (4.7 MB, 27,759 `<Ges>` entries) + `besedje16.xsd` |

Download URLs (the xmlui bitstream pattern, the goo300k precedent —
verified live 2026-07-15):

- <https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1114/Pletersnik.zip>
- <https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1092/JSV.zip>
- <https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1127/besedje16.zip>

## License (verbatim, verified at fetch time 2026-07-15)

All three deposit records carry, in their DSpace item metadata
(`/repository/rest/handle/11356/<n>?expand=metadata`), the identical grant:

> `dc.rights = "Creative Commons - Attribution 4.0 International (CC BY 4.0)"`
> `dc.rights.uri = https://creativecommons.org/licenses/by/4.0/`
> `dc.rights.label = PUB`

→ `license_class: attribution`, MCP-safe. Attribution: Inštitut za
slovenski jezik Frana Ramovša ZRC SAZU / CLARIN.SI (per-deposit authors:
Pleteršnik ed. Furlan/Dobrovoljc/Šnajder; Snoj, *Slovar jezika Janeza
Svetokriškega*; Ahačič et al., *Besedje slovenskega knjižnega jezika
16. stoletja*).

## Upstream format reality (what these fixtures preserve)

- All three are flat ZRC SAZU dictionary XML (NOT TEI): one root element
  (`<P>` / `<JSV>` / `<besedje16>`), **one entry element per line**
  (`<rc>` / `<ge>` / `<Ges>`), each with a REQUIRED zero-padded
  `geslo-id` attribute — the stable entry id, adopted verbatim.
- Line terminators differ per file: Pletersnik.xml and JSV.xml are LF;
  **besedje16.xml is CRLF** — preserved here byte-exact.
- Pleteršnik: `<ge>` unaccented headword (matches the modernized gold
  lemmas of goo300k), `<oi>` accented form with Slovenian tonemes
  (abecę̑da) and schwa/ł orthography (ábəł), `<ei>` homograph number,
  `<or><kr>` POS, `<ra>` explanation with `<po>` German glosses,
  `<ov>` source-authority abbreviations (Cig., Jan., Levst.),
  `<gn>`/`<ko>` dialect/place tags, `<pr>` inflection, `<vi>` variants,
  `<pi>` etymology, `dodatek="da"` for the 663 Dodatki-in-popravki
  entries.
- JSV: `<iz>` headword (modernized), `<ho>` homograph number, `<za>`
  grammar (`<so>` inflection, `<sk>` category), `<pz>` sense block with
  `<sp>` sense numbers, `<po>` modern-Slovenian gloss, `<zg>` verbatim
  Baroque quotes (ǀ-separated, Bohorič ſ) with `<p>` grammatical labels
  and `<ct>` volume/page citations into Sacrum promptuarium —
  `(I/1, 207)`, with an `s.`-suffixed variant `(II, 194 s.)` — and
  `<op>` notes carrying loanword etymologies (`← it. a … < lat. ad`).
- besedje16: `<besed>` headword with `hom` and `zvezdica` attributes,
  `<bv>`/`<bvo>` POS, `<razl>` bracketed explanation, `<kaz>`/`<obl>`
  cross-references, `<prav>` orthographic variants, `<slov>`/`<zst>`
  grammar notes, `<itd>` "etc.", `<sku>` source count (`♦ P: n`) and
  `<skupk>` the per-word attestation sigla of the 1550–1603 editions
  (TA 1550, TT 1557, DB 1584 = Dalmatin's Biblia — the very document
  goo300k/IMP hold as zrc_00001-1584).

## Kept entries (chosen for quirk coverage, documented deviation from the
packet's "2–3 each": homograph sets and per-element variants cannot be
pinned with fewer)

- `pletersnik/Pletersnik.xml` — 7 of 103,185: the *a* homograph triple
  000001/000002/000003 (`<ei>`, `<gn>` dialect tags), 000005 *abeceda*
  (the toneme pin abecę̑da; German glosses; `<ov>` authorities), 000012
  *abel* (ábəł schwa/ł display form; `<pi>` etymology), 001934 *blažji*
  (`<vi>` variant, `<ko>` place tag), 102523 *apnariti*
  (`dodatek="da"`, no `<ra>`).
- `jsv/JSV.xml` — 5 of 8,461: homograph pair 000002/000003 (*a*/*à* —
  accented headword folds to the same key; `<op>` loanword etymologies;
  `<ct>` citations), 000007 *Abakuk* (`<l>` proper-noun label, `<za>`
  grammar), 000026 *Abramov* (`<sp>` sense numbers), 000033 *Abundij*
  (the `(II, 194 s.)` citation variant).
- `besedje16/besedje16.xml` — 6 of 27,759: 000004 *a* hom 4 (11 sigla
  incl. TA 1550 and DB 1584 — the goo300k crosswalk pin), 000010
  *aamoriterski* (`<kaz>` cross-reference), 000011 *aar* (`<razl>`
  gloss), 000021 *abecedaria* (`<itd>`, interleaved kaz/razl), 000125
  *ajratblago* (`<prav>` + a SECOND sku/skupk group), 000175 *aloa*
  (`zvezdica="da"`).

## Extraction recipe (one-shot, run 2026-07-15)

```python
lines = raw.split(newline)          # \n (pletersnik, jsv) / \r\n (besedje16)
keep  = [l for l in lines[1:-1] if geslo_id(l) in WANTED]
out   = lines[0] + NL + NL.join(keep) + NL + lines[-1]
assert all((NL + l + NL).encode() in raw for l in keep)   # byte-verbatim
```
