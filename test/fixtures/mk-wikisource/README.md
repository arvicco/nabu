# mk-wikisource fixtures

Real api.php captures from mk.wikisource.org, retrieved 2026-10-10
(action=query prop=revisions|categories rvslots=main cllimit=max), stored in the
adapter's own envelope shape (`pages/<pageid>.json`: title/pageid/ns/revid/
timestamp/wikitext verbatim + the fetch's "cone" labels and the page's full
"categories" list). Texts PD; transcription layer CC BY-SA 4.0. One envelope
per censused page class:

- `3686.json` — Зборник на Миладиновци/ 25 песна — {{Заглавје}} with забелешки "на современ македонски правопис" (the modernized class) (whole).
- `7691.json` — Слогница речовска/ Глава I — Pulevski in ORIGINAL orthography, the text inside the header's текст= param, author <ref> notes, Поврзано list; line 44 of 61 dropped.
- `3453.json` — Чудеса пресвјатија Богородици — Krčovski prose inside текст=, забелешки with the 1817 print year; TRIMMED to the first 41 + last 7 lines (78,938 → 19,660 bytes; the template still closes).
- `3552.json` — Браќа Миладиновци — an {{Автор}} author page: skip by rule (whole).
- `5517.json` — Слогница речовска (современ правопис) — the modern-orthography duplicate: skip by rule (whole).

Re-cut: fetch each title's current revision + categories via api.php,
wrap it with the adapter's write_envelope! (cone label as noted above) and
re-apply the stated line trims.
