# scripta-bulgarica fixtures

Retrieved 2026-09-28 from http://scripta-bulgarica.eu (plain HTTP —
HTTPS refuses; Drupal 7 on PHP 5.5, fragile upstream).

- `manuscript-0.html` — the «Писмени документи» listing, page 0 of
  the ?page=0..12 pager (fetch keeps each pager page as an index
  sidecar); rows link to /bg/sources/<slug>, mirrored under sources/.
- `sources/bitolski-nadpis-na-ivan-vladislav.html` — the Bitola
  inscription of Ivan Vladislav: `field-name-body` carries the FULL
  Old Bulgarian source text (combining titla preserved);
  `field-name-field-manuscript-transcript` carries the printed-
  edition citation (Заимов 1970) — the per-text provenance layer;
  `field-author`, `field-manuscript-biblio` metadata.
- `sources/vatopedska-gramota.html` — the Vatopedi charter, same
  field shape (+ `field-terms`), edition Даскалова/Райкова 2005.

License (site, Bulgarian, /bg/content/usloviya-za-polzvane):
«Свободен достъп при условията на лиценз Creative Commons (Creative
Commons Attribution-NonCommercial-ShareAlike 2.0 Generic licensе).»
