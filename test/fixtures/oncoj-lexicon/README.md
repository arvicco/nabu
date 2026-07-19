# ONCOJ lexicon fixtures — P32-2

Trimmed real upstream sample for the `oncoj-lexicon` dictionary adapter
(`Nabu::Adapters::OncojLexicon` / `OncojLexiconParser`) — the corpus's
own dictionary database (`lexicon.xml`, the ojp shelf), the SIBLING
source of `oncoj` (one content kind per adapter, the lexlep/lexlep-words
precedent): same repo, same pinned tag, its own registry row and fetch
tree. Retrieved **2026-07-19** by
`git clone --depth 1 --branch release https://github.com/ONCOJ/data`
(the **"release" tag**, commit
`fd34a1b284c5dd1e8008df9d3abcb28cfaf464bf`, 2021-12-26; re-pin is an
owner decision). Full `lexicon.xml`: 3,405,964 B, sha256
`b6c06d00e61c53325217b5494e64130297ad1f30aa9c9dd1347472b8a23b6d2f`.
`README` is the upstream corpus README, whole and byte-verbatim (sha256
`d16432c359500b40a7414e3e08dca67e6835468e59f80cf39de763e1ab27eef2`).

## License (verbatim, upstream `README` §D, at fixture time)

> The corpus annotation (the grammatical analysis) is licensed under
> the Creative Commons Attribution 4.0 International License. To view a copy
> of this license, visit http://creativecommons.org/licenses/by/4.0/ or send
> a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.

The lexicon is the annotation layer's dictionary database (upstream
README §B: "The 'lexicon.xml' file is the dictionary database for the
corpus") → class `attribution`. Prescribed citation (§C, verbatim,
carried in the manifest):

> National Institute for Japanese Language and Linguistics (2021)
> “Oxford-NINJAL Corpus of Old Japanese” http://oncoj.ninjal.ac.jp/
> (accessed 26 December 2021)

## Trim (same slice as test/fixtures/oncoj/lexicon.xml)

91 `<superEntry>` blocks / 112 entries kept **line-byte-verbatim** in
file order between the original 3-line header and `</div>`: the 87
superEntries covering every lemma id the five corpus-fixture texts
reference, plus the four exemplars —

- `l000006-main` — a/b entry pair; `l000006b` carries
  `<usg type="geo">EOJ</usg>` (Eastern Old Japanese variant) and the
  irregular-inflection `<iType>` text
- `l000032-main` — def-less entry (`-kar-`): nil gloss, honest body
- `l090819main` + `l090819-main` — the upstream **duplicate entry id**
  `l090819` (takigwikoru MK / takamiya noun, in two superEntries whose
  own ids also collide modulo a missing hyphen): pins the deterministic
  `-b` file-order re-mint (the starling collision precedent)

## Structure census at fixture time (full lexicon)

5,527 superEntries / 5,871 entries (5,870 distinct ids — the one dup
above); every entry has ≥1 `form/orth` (0 orth-less); 223 entries have
no `<def>`; 357 entries carry multiple direct orths; 464 carry multiple
senses; `<re>` relation types: compound 1,967 · related 595 ·
derivation 554 · transitivity 310 · untyped 10 · pfxverb 6 · semantic 5
· `transitivty` 1 · `relared` 1 (upstream typos, verbatim); `usg` is
always geo (EOJ 13 · SEOJ 2 · NEOJ/CEOJ/UEOJ 1 each); 1,079 entries
carry a numeric `@corresp` (project-internal ref, carried verbatim in
the body). POS census: noun 2,535 · verb 1,411 · place name 891 ·
adjective 331 · mk (makura-kotoba) 244 · adverb 151 · particle 63 ·
personal name 62 · pronoun 45 · …

Corpus join (measured on the full release): 5,792/5,802 distinct corpus
lemma ids resolve here (99.8%); 5,793/5,871 entries are cited by the
corpus (98.7%).
