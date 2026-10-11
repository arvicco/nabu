# sl-wikisource fixtures

Real api.php captures from sl.wikisource.org, retrieved 2026-10-10
(action=query prop=revisions|categories rvslots=main cllimit=max), stored in the
adapter's own envelope shape (`pages/<pageid>.json`: title/pageid/ns/revid/
timestamp/wikitext verbatim + the fetch's "cone" labels and the page's full
"categories" list). Texts PD; transcription layer CC BY-SA 4.0. One envelope
per censused page class:

- `18712.json` — Zemlja se okoli osi vrti (Dela leta 1855) — {{naslov}} header with spisano/vir, prose; TRIMMED to the first 16 + last 5 lines.
- `36499.json` — CANTICULA LUTHERI … (Dela leta 1584) — the Dalmatin/Trubar hymnal page (whole).
- `35136.json` — Erazem iz Jame (Dela leta 1845) — Dela v bohoričici, {{naslov-mp}}, == headings; TRIMMED to the first 24 + last 4 lines (47,535 → 1,414 bytes).
- `22746.json` — Kdor drugim jamo koplje sam vanjo pade (Dela leta 1892) — <poem> with ':'-indented lines, izdano with {{mp}}; TRIMMED to the first 25 + last 8 lines (the <poem> closes).
- `37864.json` — Afričanka (Dela leta 1895, Kategorija:Prevodi) — a translation: skip by rule; TRIMMED to the first 15 + last 6 lines.

Re-cut: fetch each title's current revision + categories via api.php,
wrap it with the adapter's write_envelope! (cone label as noted above) and
re-apply the stated line trims.
