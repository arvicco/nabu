# bu-ajami fixtures

Real samples of Boston University's NEH Ajami collection
(https://sites.bu.edu/nehajami/, PI Fallou Ngom), retrieved 2026-10-13,
laid out as `canonical/bu-ajami/` holds them.

**License.** Every item page states, verbatim: "These materials are
subject to copyright and are distributed under the terms of the Creative
Commons Attribution-Non-Commercial 4.0 License, which permits
non-commercial use, distribution, and reproduction in any medium, provided
the original author and source are credited. For use, distribution or
reproduction beyond these terms, contact Professor Fallou Ngom
(fngom@bu.edu)." These fixtures are redistributed non-commercially under
that license; each item's required citation is on its page (the
"Required citation information" row).

## Files

- `items/<lang>/<slug>.html` — the item pages, WHOLE and byte-verbatim, from
  `https://sites.bu.edu/nehajami/the-four-languages/<lang>/<lang>-manuscripts/<slug>/`:
  - `hausa/falke-2729-wakar-sarkin-kano` — "A Poem in Honor of the Emir of
    Kano" (Falke collection, Northwestern University Libraries); 1-page
    transcription; the composition-date case (the page states the poem was
    composed during the Emir's 1953 trip).
  - `wolof/bakk-wi` — "Song of the Champion, Sëriñ Fallu" by Serigne Moussa
    Ka; 15-page transcription; its PDF href is **NFD** (`Ba` + U+0300) — the
    request-bytes case.
  - `mandinka/mandinkakan-leetaroolu-3` — "Letters in Mandinka 3"; 5 pages;
    the `[Document N: Page M]` marker case; no stated date.
  - `fula/coora` — "Acts of Worship"; the page ONLY (its PDF is not checked
    in): the discover-skips-a-PDF-less-item case.
- `files/<yyyy>/<mm>/<name>_Transcription.pdf` — the three transcription
  PDFs, WHOLE and byte-verbatim, from
  `https://sites.bu.edu/nehajami/files/<yyyy>/<mm>/<name>_Transcription.pdf`
  (held under the NFC file name; Bàkk-wi is requested as `Ba%CC%80kk-wi…`).
- `textlayers/<name>_Transcription.txt` — the RECORDED mutool 1.28 text
  layer of each PDF (`mutool draw -F text -o <txt> <pdf>`), so the suite
  never depends on mutool; a guarded live test pins agreement.
- `rest/pages-{1,2}.json` — the wp-json listing
  (`https://sites.bu.edu/nehajami/wp-json/wp/v2/pages?per_page=100&page=N&_fields=id,link,slug,modified`,
  X-WP-TotalPages: 2) TRIMMED to 7 of its 111 rows (the four fixture items
  + three non-item pages) and re-serialized compactly; row content verbatim.
