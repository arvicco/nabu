# vakk fixtures — VAKK, the Corpus of Old Written Estonian

Retrieved 2026-10-21 from https://vakk.ut.ee/ (University of Tartu) by
the adapter's own crawl, narrowed to six texts
(`Nabu::Adapters::Vakk.new(koods: [...]).fetch(dir)`), then the text
list trimmed. The older address www.murre.ut.ee/vakk/ no longer
completes a TLS handshake (the proxy serves no certificate for that
name, checked 2026-10-21); murre.ut.ee/vakk/ falls through to the
dialect-corpora application, which carries no VAKK.

License (META-SHARE record behind DOI
10.15155/1-00-0000-0000-0000-00075L, read 2026-10-21, verbatim):
"Availability: Available - Restricted Use", "Licence CC - BY - NC
Restrictions: Academic - Non Commercial Use", "Distribution
Access/Medium: Accessible Through Interface" → nc. Citation per the
site's guide (juhend.php): "VAKK (= Vana kirjakeele korpus. Tartu
Ülikool. https://vakk.ut.ee/)".

## Grains upstream serves (all enumerated 2026-10-21)

- **text list** — `tekstid.php`: one `<tr>` per text (3,052 rows,
  1,352,615 B): year, author, title (linked by `?kood=`), dialect basis
  (`eP` North / `eL` South Estonian, `ee` unspecified, empty for the
  German metatexts), class (`V` vaimulik, `I` ilmalik, `S` sõnastik,
  `M` metatekst, `H` vennastekogudus, `K` kohtuprotokoll — the labels
  from the page's own config), medium (`K` käsikiri / `T` trükis), and
  "all / Estonian / annotated" token counts. Kept as
  `map/tekstid.html`, here trimmed to the six fixture rows (head and
  tail verbatim).
- **text** (`kood`) — THE DOCUMENT.
- **info page** (`tekstid.php?lk=info&kood=…`) — the text's record:
  title/author, "Teksti allikas" (source edition) and commentary; the
  court protocols carry Teema / Vald / Kuupäev / Protokolli number /
  Kohtumehed paragraphs. Kept as `texts/<kood>/info.html.gz`.
- **reading page** (`tekstid.php?kood=…` = the first page;
  `?lk=<value>&kood=…` the others) — `select#lehekyljed` lists every
  page value (signed integers; front matter counts down from -1;
  values can be sparse: Gutslaff 49/258/362/363). Kept as
  `first.html.gz` and `p<value>.html.gz`.
- **sentence** (`div.lause`) — THE PASSAGE.
- **token** (`span.sone` + `span.soneinfo`: lemma, tahendus, liik,
  vorm, keel, kommentaar; `span.stiil` heading/margin styles).
- NOT fetched: the page facsimile JPEGs (`/pildid/<kood>-<n>.jpg`,
  beside some manuscript pages), the search view (`otsi.php`, the same
  tokens), the linked VAKS dictionary (sisu.ut.ee/vaks — a separate
  resource). Images are never requested, so nothing lands in the tree
  to skip.

Census (the full text list, 2026-10-21): 3,052 texts / 3,374,325
tokens (2,895,520 Estonian, 1,675,332 annotated); class K 2,856 · V 80
· I 67 · H 26 · M 22 · S 1; medium manuscript 2,949 · print 103;
196 corpus texts (2,977,185 tokens, 107 dated ≤ 1739) + 2,856 court
protocols 1866–1890s (397,140 tokens). Page counts read off eight
selectors: 1739 Old Testament 661, Stahl Leyen Spiegel I 545,
Lithander 745, Kõrv 264, Rossihnius 132, 1715 New Testament 506,
Müller sermon 1 12, a Moravian life story 11 (~411 tokens a page).

## The six texts

| kood | what | files |
|---|---|---|
| `1510-postilla` | marginal notes in a postil, 1510 (manuscript, eP, V) — one page, no selector, a facsimile beside it | info, first |
| `1535-Koell` | the Wanradt–Koell catechism, Wittenberg 1535 (print, eP, V) — ten pages, `[reconstruction]` brackets and `_marginalia_` marks, split compounds | info, first, p2–p10 |
| `1535-Wanradt-Koell` | the catechism's Low German afterword on Estonian dialects (print, M) — German tokens | info, first |
| `1644-Gutslaff` | Gutslaff's *Kurtzer Bericht* (print, eL, M) — German with South Estonian charms; sparse page values 49/258/362/363 | info, first, p258, p362, p363 |
| `1665-Horn` | Bengt Horn's decree (print, eP, I) — two pages | info, first, p2 |
| `1866-Kahkva-0001` | a Kahkva parish-court protocol, 1866 (manuscript, eL, K) — Vald/Kuupäev/protocol number/judges | info, first |

Every `.html.gz` is the response body byte-verbatim inside gzip (mtime
0). Re-cut recipe: run the adapter's fetch with `koods:` set to the six
ids into a scratch dir, copy `texts/`, and trim `map/tekstid.html` to
those six `<tr>` rows.
