# Menota fixtures — the Medieval Nordic Text Archive (clarino.uib.no)

Real upstream responses snapshotted **2026-08-23** from the Corpuscle
(korpuskel) REST API behind the Menota catalogue SPA
(https://clarino.uib.no/menota/catalogue/menota) and from menota.org.
The API flow (all endpoints verified live that day):

    GET <base>/rest?command=get-session                       → {"sessionId": …}
    GET <base>/rest?command=list-catalogue-documents
        &session-id=<s>&corpus=menota&start=<a>&end=<b>       → {"documents": […], "documentCount": 91}
    GET <base>/rest?command=download-document
        &session-id=<s>&corpus=menota&document-id=<id>        → {"data": "<TEI …>"}

with `<base>` = https://clarino.uib.no/korpuskel-api. Every endpoint is
session-gated (ephemeral session-id), so no static raw GET reproduces those
bytes — the session-gated entries are `refetchable: false` (the menotec/
iness-api posture). NOTE: clarino.uib.no's robots.txt says `User-agent: *`
/ `Disallow: /`; the crawl is nonetheless upstream-blessed — Stegmann
(2026-08-20, the №77-1 grant): "we will not keep you from scraping 😉"
until their bulk endpoint lands.

## texts/ — three Menota-TEI documents (the landed form)

What `Nabu::MenotaFetch` lands: the download-document envelope's `data`
string, UTF-8, byte-verbatim (CRLF line ends included). Chosen to cover
the three structural shapes of the archive (91-document census 2026-08-23):

- `texts/AM-1056-IX-4to.xml` — WHOLE (242 words). A fragment of Konungs
  skuggsjá, Old Norwegian (`textLang mainLang="nor"`), c. 1300. The full
  three-level shape: every `<w>`/`<pc>` carries `<choice>` with
  `<me:facs>`/`<me:dipl>`/`<me:norm>`, lemma + `me:msa` morphology,
  `pb/cb/lb` milestones (folio 1r–2v, columns A/B), `<lb>` breaks INSIDE
  word levels (`þur<lb/>fu`), `<c type="littNot">` initials, MUFI entities
  (&inodot; &vins; &trot; …), structured `<origDate notBefore="1280"
  notAfter="1310">`.
- `texts/NRA-norrfragm-60-A.xml` — WHOLE (120 words). A fragment of
  Stjórn, Old Icelandic (`mainLang="isl"`), c. 1350. `xml:id` on every
  token (`w100`, `w200`, …), heavy `<supplied>`/`<gap>` damage markup,
  all three levels.
- `texts/Holm-A-80.xml` — DOCUMENTED TRIM (3,755,022 B → 133,382 B).
  Birgitta Andersdotters bönbok, Old Swedish (NO `textLang`; langUsage
  `<language ident="swe">`), c. 1518–1532. The FACS-ONLY shape: plain
  `<w><me:facs>…</me:facs></w>` without `<choice>`, no dipl/norm, no
  lemma, `<me:punct>` punctuation. Trim: teiHeader + `<body>` byte-intact
  up to the token before `<pb ed="ms" n="3r"/>` (pages 2r–2v, 414 `<w>`,
  49 lines), then a synthetic `</p></div></body></text></TEI>` tail.

## texts/ — the P82-r1 quarantine-recovery trims

Five more DOCUMENTED TRIMS cut 2026-08-24 from the 2026-08-23 canonical
sync (`canonical/menota/texts/`, same session-gated korpuskel downloads —
`refetchable: false`). These are the five shapes the first live sync
QUARANTINED (8 of 91 documents); each trim keeps the offending bytes.
Every trim = DOCTYPE + teiHeader byte-intact, body slices cut at token
boundaries (splice points and synthetic structural glue documented per
file in manifest.yml):

- `texts/AM-242-fol.xml` — Codex Wormianus (Snorra Edda), isl, `dipl
  facs` levels. DOCTYPE INTERNAL SUBSET declaring 17 runic entities
  (`&urun;` → U+16A2 …) plus the empty `<!ENTITY none "">`, runic
  `<w type="runic-character">` usage, and entity references that occur
  ONLY inside editorial comments (`&aum;`/`&aumL;`, transcriber's ä —
  per the XML spec not references at all).
- `texts/AM-677-4to.xml` — Gregory homilies etc., isl, three levels.
  Internal-subset entities BUILT FROM table entities (`&BAR;` =
  `&#x200A;&bar;`, `&escapacute;` = `&escap;&combacute;`, `&THlig;` =
  `&#x2E24;TH&#x2E25;`, `&gnlig;`/`&nglig;` → U+A77F) — the recursive-
  resolution regression.
- `texts/AM-132-fol-Laxdaela-saga.xml` — Laxdæla saga (Möðruvallabók
  copy), isl, three levels. The SINGLE-QUOTED internal-subset
  declaration `<!ENTITY aacutenscapbllig '&#xF542;'>` (MUFI PUA).
- `texts/DG-4at7-Elis.xml` — Elíss saga ok Rósamundar, nor. The
  SINGLE-LEVEL shape: bare text straight in `<w>`/`<pc>` (no
  me:facs/dipl/norm anywhere), level claimed by the header's own
  `<normalization me:level="dipl">`; editorial `<note>` INSIDE a word
  (`o<note>…</note>ckarr`), abbreviation `<choice><am>ih&bar;c</am>
  <ex>ieso</ex></choice>`, `<supplied>`/`<add>` in-word.
- `texts/DG-4at7-Pamph.xml` — Pamphilus saga, nor, single-level dipl
  like Elis; `<choice><sic>gera</sic><corr resp="HP">gefa</corr>
  </choice>` emendations, mid-word `gaf<lb/>lak` with XML layout
  whitespace, `<seg type="nb">` groups, `<unclear>` readings.

Catalogue census pinned by the tests (2026-08-23): 91 documents, license
column `CC-BY-SA 4.0` on ALL 91; per-file `<availability status="free">
<licence target="http://creativecommons.org/licenses/by-sa/4.0/">CC-BY-SA
4.0</licence>` (all three fixtures). Languages: isl 57, nor 27, swe 4,
dan 2, non 1. 86/91 carry the dipl level; the 5 without (incl. Holm A 80)
are facs-only.

## texts/ — the Q45 mixed-level trims

Three more fixtures cut/copied 2026-08-27 from the 2026-08-23 canonical
sync (same session-gated korpuskel downloads — `refetchable: false`).
The Q45 census (91 canonical documents): 30 mixed-level documents leave
98,575 tokens bare (no me: level children) — 98,496 punctuation, 79
real `<w>` words — and 11 documents interleave OTHER layouts (printed
editions, another hand, the transcriber's lacuna markers, a parallel
manuscript) with the manuscript's own `ed="ms"` milestones:

- `texts/DG-4at7-Streng.xml` — DOCUMENTED TRIM (4,599,784 B → 20,490 B).
  Strengleikar, nor, declared `me:level="dipl"`. DOCTYPE + teiHeader +
  body byte-intact through canonical line 444 (ms lines 17va.6–12,
  w00001–w00047), then a synthetic `</p></div></div></body></text></TEI>`
  tail. The EDITION-MILESTONE shape: `<pb ed="Unger" n="0001"/>` +
  `<lb ed="Unger" n="3"/>` immediately after `<lb ed="ms" n="6"/>`, a
  mid-word Unger break (`skyn<lb ed="Unger" n="5"/>semdo<ex>m</ex>`),
  bare `<me:punct>.</me:punct>` between level-bearing words.
- `texts/AM-243-b-alfa-fol.xml` — DOCUMENTED TRIM (11,113,642 B →
  75,571 B). Konungs skuggsjá, nor, declared `me:level="dipl"`. DOCTYPE
  + teiHeader + body byte-intact through canonical line 663 (a `</s>`
  sentence close), same synthetic tail. THREE edition layouts
  (`ed="AM"`, `ed="FJ_utg"`, `ed="H-O"`) interleaved with `ed="ms"`,
  bare `<pc xml:id="w600">.</pc>` punctuation, and fully supplied bare
  words (`<w xml:id="w24400"><supplied>missir</supplied></w>`).
- `texts/NRA-norrfragm-55-B.xml` — WHOLE (142,234 B). A fragment of
  Hákonar saga Hákonarsonar, isl, c. 1275–1350, all three levels on
  every word (`me:level="facs dipl norm"`) with 28 bare
  `<pc xml:id>.</pc>` — bare punctuation in a three-level document.

## menota-entities.txt — the MUFI entity table

https://www.menota.org/menota-entities.txt, WHOLE (156,805 B, version of
10 December 2025, ~1,977 entities). The DOCTYPE of every Menota-TEI file
pulls it as an external entity set; the fetch lands it beside `texts/` and
the parser resolves `&inodot;` → ı, `&slong;` → ſ, `&vins;` → ꝩ (many map
into the MUFI Private Use Area). Refetchable — a stable public URL.

## catalogue/ — the API envelopes

- `catalogue/get-session.json` — WHOLE. `{"sessionId":"261913323160349",
  "userId":null,"userName":null}` (the sessionId is minted per request —
  a refetch can never byte-match).
- `catalogue/list-page-0-2.json` — WHOLE: a real `start=0&end=2` page
  (3 document rows, `documentCount` 91) — the envelope-shape pin, incl.
  per-row documentId/signature/title/license/language/origDate/wordCount
  and the facs/dipl/norm availability flags.
- `catalogue/download-AM-1056-IX-4to.json` — WHOLE: one real
  download-document envelope (`{"data": …}`, \uXXXX-escaped), whose
  decoded data is byte-identical to `texts/AM-1056-IX-4to.xml`.

## License

The catalogue license column (the quotable record, per the №77-1 grant) and
every sampled teiHeader: **CC BY-SA 4.0** → source class `attribution`.
