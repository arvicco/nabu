# Old Tibetan Corpus fixture (tibetan-nlp/old-tibetan-corpus)

Real bytes from github.com/tibetan-nlp/old-tibetan-corpus, HEAD
`17c01c96a024604b86911a3b707ac73d4757f7c6` (2021-06-30), retrieved
2026-07-28: the *Old Tibetan Annals* (OTA, OTDO Pt_1288) and the *Old
Tibetan Chronicle* (OTC, OTDO Pt_1287) — Dunhuang-manuscript Old Tibetan,
Wylie from Old Tibetan Documents Online converted to Unicode, segmented,
POS-tagged, then hand-corrected in BRAT (segmentation + POS + verb-argument
dependencies) by Faggionato/Garrett/Meelen (AHRC "Lexicography in Motion",
2017–2020). The CoNLL-U export "denormalizes" back to the original Old
Tibetan orthography (ྀ reversed gi-gu and friends); the LEMMA column keeps
the ot2ct-NORMALIZED Classical Tibetan citation form (with `√` markers:
`ནས་√cv`, `འཇིག་√2`) — a pipeline product the README's hand-correction claim
does NOT cover, hence `lemma_tier: silver` on the registry row.

Censused 2026-07-28 over the two `conllu/` files: otannals 546 sentences /
~5.6k syllable-tokens, EVERY sentence with a `# text_en` (Dotson 2009's
aligned English translation — the `-en` sibling document); otchronicle
1,577 sentences / ~11.8k tokens, ZERO `text_en` (its `-en` ref skips by
rule). sent_ids (`otannals:000:T55`) are unique per file but NOT ordinal —
they carry the source section + the BRAT id of the sentence's first token;
file order is the passage sequence, and the adapter's citation hook strips
the redundant `<stem>:` prefix (the damaskini mold).

## Layout (mirrors the cloned repo)

- `conllu/otannals.conllu` — TRIMMED: the REAL first 5 of 546 sentence
  blocks (sections 000 + the first of 001). Documents `text_en`, the MWT
  range line (`26-27 བཀུམོ` — orthographic fusion split into verb + final
  particle), lacuna `[---]` X tokens, `√`-marked lemmas, and the bespoke
  verb-argument deprels (`arg1`, `arg2`, `arg2:lvc`, `obl`) on an
  otherwise all-`0 root` HEAD lane.
- `conllu/otchronicle.conllu` — TRIMMED: the REAL first 3 of 1,577 blocks
  (opening punctuation-only sentence ༆།༔། + two prose sentences). No
  `text_en` anywhere in the full file — pins the DocumentSkipped rule for
  `otchronicle-en`.
- `archive/otannals-normalized.conllu` — TRIMMED: the first block of the
  legacy NORMALIZED export ("The archive directory contains files in
  legacy or unmaintained formats" — upstream README). Present so the
  discovery-skip census has real bytes to count; never a DocumentRef
  (it would double-load the Annals in the wrong orthography).

The `cg3/`, `brat/`, `text/` lanes (constraint grammar, BRAT standoff,
plain text) are non-CoNLL-U renderings of the same texts and are simply
outside discover's glob.

## License

Repo `LICENSE`, verbatim head: "MIT License / Copyright (c) 2018 Tibetan
NLP" → attribution (notice-preserving). RECORDED CHOICE: the Zenodo twin
of this dataset lists only "Other (Open)" — the MIT grant in this GitHub
repo is the license basis for this lane, and the fetch takes this repo,
not the Zenodo zip. The upstream README also stamps each text CC BY 4.0
in its metadata table ("Licensing | Creative Commons Attribution 4.0
International License (CC-BY)") — both grants are attribution-class, no
conflict. Cite Christian Faggionato, Edward Garrett, Marieke Meelen (the
repo's own citation line) + Dotson 2009 for the Annals translation.
