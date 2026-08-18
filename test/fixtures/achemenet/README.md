# achemenet fixtures

Trimmed REAL slices of the "Linguistically Annotated Achemenet
Babylonian Texts" dataset (Alstola, Sahala, Valk & Ong, University of
Helsinki), Zenodo record 19067652, version 1.1.1, retrieved
2026-08-17 from https://zenodo.org/records/19067652/files/Achemenet.zip
(license: CC BY 4.0 per the Zenodo deposit; the in-zip Readme.md
carries no license line — the deposit page is the grant's authority,
verified 2026-08-17).

- `Murashu.conllu` — the two `# global.*` headers + four complete real
  documents from the Murašû archive: P261571 (BE 9, 2), P261572
  (BE 9, 3), P261494 (BE 9, 3a — the id order is NOT monotonic
  upstream, kept verbatim), and X000428 (BE 9, 28 — an X-id: a text
  with no CDLI P-number; both id shapes are real upstream).
- `YOS7.conllu` — headers + P307862 (YOS 7 1), one complete Eanna
  temple text.

Format quirks these fixtures pin: BabyLemmatizer CoNLL-U-Plus with a
17-column `# global.columns` declaration (id form lemma upos xpos
feats head deprel deps misc eng norm lang formctx xposctx score
lock); documents delimited ONLY by `# <id> = <designation>` comment
lines (no blank lines, no sent_id/newdoc); head/deprel are dummy
(root/child-1 — no real syntax); number tokens carry `_` lemmas with
`num_cardinal` in deps; `score` is the lemmatizer confidence class
(0.0–5.0); lemmatization is SEMI-AUTOMATIC (BabyLemmatizer + partial
manual correction) — the lemma layer rides silver tier.
