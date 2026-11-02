# Comenius fixtures — TEI editions of J. A. Komenský (LINDAT/CLARIAH-CZ)

Real upstream files downloaded **2026-11-02** from the LINDAT/CLARIAH-CZ
repository (DSpace 7 REST: item → ORIGINAL bundle → bitstream content),
deposited by Filosofický ústav AV ČR (TEI encoding Tomáš Havelka) on the
text of *Dílo Jana Amose Komenského* 3 (Praha 1978). Twelve items, all
accessioned 2026-10-22, dc.type "annotated text".

## Delivery grains

Each item serves ONE bitstream (local.files.count 1, "1;TEI XML") — the
work's TEI file; the adapter fetches it into `<handle suffix>/<filename>`
(the layout mirrored here). Inside a file: `front/titlePage` (the
historic print's title page → metadata), `body` p/head (the text → one
passage per block), `back` (the 1978 editors' "Informace o díle" and
Latin notes — modern editorial prose, rejected from the text; specimen:
the `<back>` of every fixture file). The apparatus `<rdg>`, footnote
`<note>`s and marginal `<add place="margin">` notes ride annotations.
The `DJAK.xsl` stylesheet the files reference is not deposited.
Reconciliation: 12 items = 12 files = 12 documents (1,384 passages).

## Files (all WHOLE, byte-verbatim)

- `1-6288/06_DJAK_03_Pres_Bozi.xml` — hdl 20.500.12800/1-6288, bitstream
  5695f6cd-95fd-443b-b9bb-2a2d5ebe934b (42,520 B). Pres boží (1624): the
  DJAK lemma vs the Strahov print's readings (`wit="#St"`), footnote
  glosses, marginalia, the print's own page breaks (`ed="#St" break="no"`).
- `1-6283/02_DJAK_03_Listove.xml` — hdl 20.500.12800/1-6283, bitstream
  7c75478a-f1ae-42e7-9c67-319c3fc03c28 (115,178 B). Listové do nebe
  (1619), `docDate when="1619"` with the printed "LÉTA PÁNĚ MDCXIX".
- `1-6285/09_DJAK_03_Bazuine.xml` — hdl 20.500.12800/1-6285, bitstream
  74a305ab-c0df-4a64-a23c-6e95f2a133b3 (84,204 B). Bazuine des genaden
  jaar (1632), the one Dutch work (`TEI xml:lang="nl"`).

## License

Every item's dc.rights, verbatim: "Creative Commons - Attribution 4.0
International (CC BY 4.0)", dc.rights.uri
http://creativecommons.org/licenses/by/4.0/, rights label PUB (verified on
all twelve, 2026-11-02). → class `attribution`.
