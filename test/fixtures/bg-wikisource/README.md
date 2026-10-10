# bg-wikisource fixtures

Real api.php captures from bg.wikisource.org, retrieved 2026-10-10
(action=query prop=revisions|categories rvslots=main cllimit=max), stored in the
adapter's own envelope shape (`pages/<pageid>.json`: title/pageid/ns/revid/
timestamp/wikitext verbatim + the fetch's "cone" labels and the page's full
"categories" list). Texts PD; transcription layer CC BY-SA 4.0. One envelope
per censused page class:

- `6326.json` — Рилска грамота (1378) — {{Script/Slavonic|cu|2=…}} original with </br> paragraph breaks (whole).
- `6194.json` — Душанова грамота за село Потолино (1348) — Средновековни сръбски текстове; the edition footnote on the Оригинал heading (whole).
- `6045.json` — Брашовска грамота на цар Иван Срацимир (1369–1380) — the original inside the facsimile caption + a modern-rendering section (whole).
- `2142.json` — История славянобългарска/2 — Paisiy as a modern-literary rendering, the бележки edition note (whole).
- `5459.json` — Закон за съдене на хората — Bobchev's translation, no original: skip by rule; TRIMMED to the first 13 + last 3 lines.

Re-cut: fetch each title's current revision + categories via api.php,
wrap it with the adapter's write_envelope! (cone label as noted above) and
re-apply the stated line trims.
