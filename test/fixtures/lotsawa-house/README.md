# Lotsawa House fixtures

Real pages from Lotsawa House (<https://www.lotsawahouse.org>, Lotsawa
House CIC, ISSN 2753-4812), retrieved 2026-10-21. License: CC BY-NC 4.0
(/about/terms: "All texts on Lotsawa House are covered by the Creative
Commons Attribution-NonCommercial 4.0 International License."; the same
terms license crawling "for indexing (subject to reasonable network usage
constraints)").

## Delivery grains (census 2026-10-21)

The site has no bulk export and no sitemap (/sitemap.xml 404; robots.txt
disallows only /app/, /search, /<lang>/search and /Cgi). It serves:

1. **Text pages** — `/<lang>/<collection>/<author>/<slug>` (collections
   `tibetan-masters`, `indian-masters`) and `/<lang>/words-of-the-buddha/
   <slug>`; en is unprefixed, the other eight languages (bo de es fr it nl
   pt zh) are `/<lang>/`. **Accepted**: one document per (language, text);
   the bo page is the original, the rest translations.
2. **Listing pages** — per language: the explore page, the Words of the
   Buddha page, one listing per author (the texts available in that
   language). **Rejected (catalog grain)**: crawled to enumerate the texts,
   persisted under `catalog/` as provenance, skipped by rule —
   `catalog/en/tibetan-masters/mipham.html` is the pinned specimen.
3. **Topic pages** (`/<lang>/topics/<slug>/`) — a second catalog over the
   same texts. Not crawled: every text page carries its own topic tags.
4. **EPUB/PDF** — generated on POST per page (`dl_dynamic`), derivative
   renderings of the same text. Not fetched.
5. `rss.xml`, about/project pages, images. Not texts; not fetched.

## Text pages (`pages/<lang>/…`, all WHOLE as served)

- `bo/tibetan-masters/mipham/instruction-on-point-of-mind.html` — a
  Markdown-converted Tibetan page (div.MDFile; one verse paragraph with
  `<br>` line breaks).
- `en/tibetan-masters/mipham/instruction-on-point-of-mind.html` — its
  English translation: footnote markers `[1]`–`[3]` and div.footnotes,
  the "| Translated by" credit, the h2.biblio Tibetan Edition block, the
  Version line.
- `bo/tibetan-masters/mipham/acala-sadhana.html` and
  `en/tibetan-masters/mipham/acala-sadhana.html` — a RESTRICTED sādhana
  (the site's `restricted: true` flag): the classed liturgy grammar
  (HeadingTib, TibetanVerse / EnglishPhonetics / EnglishText triples,
  TibetanExplanation / Explanation, EnglishMantra), p.Credit,
  h2.CreditTitle + p.Source.
- `bo/words-of-the-buddha/amitayus-dharani.html` and
  `en/words-of-the-buddha/amitayus-dharani.html` — the scripture
  collection (no author); the en page's `sup#backref1` marker and
  `ol.Footnote` notes.
- `nl/indian-masters/atisha/prayer-to-tara.html` — Dutch under upstream's
  English-named classes (EnglishText carries Dutch).
- `zh/indian-masters/tilopa/ganges-mahamudra-instruction.html` — Chinese
  (div.ChineseText), the translator's colophon in a `<small>` paragraph.
- `fr/tibetan-masters/alak-zenkar/patrul-biography.html` — French prose
  with a blockquote and footnotes.

## Catalog fixtures (`fetch/`, the LotsawaFetch test corpus)

Documented text-card SPLICES of the real listing pages — every
`<div class="text-card">` block dropped except the kept ones, the page
header, language switcher, navigation and footer untouched:

- `en-index.html` / `bo-index.html` — the en / bo explore pages, kept:
  the Mipham author card (of 687 / 685 cards).
- `en-mipham.html` / `bo-mipham.html` — Mipham's en / bo listings, kept:
  instruction-on-point-of-mind and acala-sadhana (of 141 cards).
- `en-wotb.html` / `bo-wotb.html` — the Words of the Buddha pages, kept:
  amitayus-dharani (of 58 cards).
