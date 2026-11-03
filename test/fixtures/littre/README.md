# littre fixture

Trimmed REAL excerpts of the oeuvres/littre TEI P5 edition of Littré's
*Dictionnaire de la langue française*. Retrieved 2026-11-02 from
https://github.com/oeuvres/littre (default branch master, pushed
2020-11-10), files under `xml/`:

| File | Bytes | sha256 |
|---|---|---|
| a.xml | 7,074,469 | 627d2e8ffc713b6cde0ee8787cad9ef1b7fd12b392da4f042cf2a7666267099d |
| b.xml | 4,471,269 | 60d581fab438b576a3837a05a6ecce2bbb81bb55bd4e4a35255c2bd67e8b17c9 |
| g.xml | 3,853,751 | 92b268d4b50fec73ecbf186cb9bc6d4f6c75bfd3986cb4f9eebf309593e1e2d8 |
| i.xml | 4,042,325 | be8adba4493a8cc4c303a8209f2420b044494e6c4e9217dc25922c826188ba3e |
| s.xml | 7,966,627 | 0e81b01c0d9cfb7269521cc6ceab86f2ef834986de220391cf8d0b3380d51d97 |
| preface.html | 124,379 | 1a04d0d1674fef16fe58012ca4f3dabe4b571a3df5d06b2ab93c225ee223d10c |
| causerie.html | 95,732 | 7fae2d72dc7b76c09c2d29e980258869a620990c548df5ce1d0f2df85f4a050e |
| test.tei | 95,841 | 02c9028c904ef837b0db5cf4f4fd73abe21d1af3e0018ec1f008ad6977a25fa1 |

License (every letter file's teiHeader `<availability>`): "Licence
Creative Commons : Paternité – Partage des Conditions Initiales à
l'Identique – 2.0 France".

## Delivery grains

The repo is a servlet application around the dictionary. `xml/` serves:

- `a.xml` … `z.xml` — the dictionary, one TEI file per letter, each
  article an `<entry>` or `<entryFree>` — **ACCEPTED**, one document
  per file on one shelf.
- `preface.html`, `causerie.html` — Littré's preface and his causerie
  on writing the dictionary, front-matter prose — **REJECTED** by rule
  (specimens pinned).
- `test.tei` — a 4-article test sample duplicating letter-file
  articles — **REJECTED** by rule (specimen pinned).
- `littre.rng`, `schema.html` — the schema and its documentation; the
  rest of the repo (`web-app/`, `transform/`, `doc/`, `nuances/`) is
  application code — not data grains.

Reconciliation (no advertised total upstream): 78,394 `<entry>` + 89
`<entryFree>` = 78,483 articles parsed over the 26 files; one more
`<entry>` sits inside an XML comment (an editor's deletion in e.xml).

## Cut

Byte-verbatim articles in upstream order inside each file's own
header and closing tags:

- `xml/a.xml` — `able.2` (an `<entryFree>`: the suffix article).
- `xml/b.xml` — `b` (senses, a citation, a HISTORIQUE with XIIIe/XVe
  labels, etymology), `baal` (a nested sense, a Racine citation).
- `xml/g.xml` — the `gommeux` pair: the main article (numbered senses)
  and the supplement article sharing its xml:id (an upstream repeat;
  the parser numbers it `gommeux:2`).
- `xml/i.xml` — `ignoramment`, the home article.
- `xml/s.xml` — `salleran` and the second `ignoramment` printed in the
  S file (the parser files it as `ignoramment@s`).
- `xml/preface.html`, `xml/causerie.html` — each file's head through
  its first paragraph, re-closed (`</body></html>`).
- `xml/test.tei` — its header and first article, re-closed.

## Refresh

Re-fetch the files from the repo's master branch and re-select the same
xml:ids (for g.xml both occurrences of `gommeux`).
