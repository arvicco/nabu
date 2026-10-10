# hr-wikisource fixtures

Real api.php captures from hr.wikisource.org, retrieved 2026-10-10
(action=query prop=revisions|categories rvslots=main cllimit=max), stored in the
adapter's own envelope shape (`pages/<pageid>.json`: title/pageid/ns/revid/
timestamp/wikitext verbatim + the fetch's "cone" labels and the page's full
"categories" list). Texts PD; transcription layer CC BY-SA 4.0. One envelope
per censused page class:

- `5889.json` — Judita/Libro drugo — Marulić, the ':'-indented couplet layout with the edition's (m)/(j) restorations; TRIMMED to the first 34 lines (13,488 → 1,115 bytes).
- `13006.json` — Povaljska listina (1250) — Hrvatski srednji vijek, <poem>-wrapped prose; TRIMMED to the first 14 + last 2 lines.
- `16190.json` — Moje drago srce — Zrinski's 1671 letter: prose with a trailing centered signature (whole).
- `11930.json` — Novela od Stanca/prizor drugi — Držić, drama in <poem> with speaker lines (whole).
- `12823.json` — Ah, da 'e meni na svijet dano — Bunić Vučić, filed under 16. AND 17. stoljeće; a bare [[sr:…]] interwiki (whole).

Re-cut: fetch each title's current revision + categories via api.php,
wrap it with the adapter's write_envelope! (cone label as noted above) and
re-apply the stated line trims.
