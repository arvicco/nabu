# sr-wikisource fixtures

Real api.php captures from sr.wikisource.org, retrieved 2026-10-10
(action=query prop=revisions|categories rvslots=main cllimit=max), stored in the
adapter's own envelope shape (`pages/<pageid>.json`: title/pageid/ns/revid/
timestamp/wikitext verbatim + the fetch's "cone" labels and the page's full
"categories" list). Texts PD; transcription layer CC BY-SA 4.0. One envelope
per censused page class:

- `22093.json` — Опет то, али друкчије (Мати невјерница) — a Vuk volume-III song: {{Поезија|…}} verse wrapper, Erlangen-style 0001 numbering, {{стих|N}} markers, centered title + provenance subtitle, the === Избор === source line (whole).
- `28813.json` — Ја заволех драгу надалеко — an Erlangen-manuscript page: {{заглавље}} header with the editors' statement, Интервенције/Напомене/Коментар/Извори apparatus sections (whole).
- `15002.json` — Високи Стеван и цар Бајазит — <poem> verse + {{Квалитет|100%}}; TRIMMED to the first 22 + last 4 lines (25,301 → 1,174 bytes; the <poem> closes).
- `45771.json` — Marko Kraljević oženio vilu — a Latin-script (Croatian-collected) song, the hrv-by-script class (whole).
- `32083.json` — * * * (Вино пия петдесет дружини) — a Bulgarian-source song (Народне песме из бугарских извора): skip by rule (whole).
- `35120.json` — Вук Стефановић Караџић: Српске народне пјесме, књига друга — a Vuk volume index page (title rule); TRIMMED to the first 14 + last 3 lines.
- `10666.json` — Ерлангерски рукопис старих српскохрватских народних песама — the Erlangen table of contents (link-list index class); TRIMMED to the first 8 + last 4 lines.

Re-cut: fetch each title's current revision + categories via api.php,
wrap it with the adapter's write_envelope! (cone label as noted above) and
re-apply the stated line trims.
