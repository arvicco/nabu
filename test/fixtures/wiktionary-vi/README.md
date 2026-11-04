# wiktionary-vi fixture

Trimmed REAL excerpt of the kaikki.org Vietnamese extraction. Retrieved
2026-11-04 from
https://kaikki.org/dictionary/Vietnamese/kaikki.org-dictionary-Vietnamese.jsonl
(83,424,329 bytes, Last-Modified 2026-10-30, ETag "6ae52287-4f8f449",
sha256 `186cd0a62d876dada70c9761bc05e598c8cf7b9a48e0aa518bab6c649e28d945`;
the index page states "45519 distinct words"). The whole file was read
for the census below; only the nine lines listed are kept here.

License, verbatim from kaikki.org/dictionary/ "Copyright and license":
"This data is made available under the same licenses as Wiktionary -
both CC-BY-SA and GFDL." (+ the wiktextract citation request: Ylönen,
LREC 2022.)

## Delivery grains

kaikki serves one artifact per language: the per-language JSONL, one
wiktextract record per line (a word × part-of-speech × etymology
section). The adapter takes the WHOLE FILE as its one document (a
dictionary shelf) and each record as an entry candidate. The site's HTML
pages and the all-languages dump are other deliveries of the same data,
not fetched. Inside the file, ONE record shape is rejected by rule: the
**empty stub** — no gloss, no reading, no script form, no etymology text.

## Census (the whole file, through the adapter)

52,167 records, lang_code uniformly `vi`, 0 non-NFC, 0 headwordless.

| grain | records |
|---|---:|
| glossed (kept) | 46,660 |
| glossless, carrying readings or Hán-Nôm forms (kept) | 5,435 |
| glossless, etymology text only (kept) | 12 |
| empty stub — character (skipped by rule) | 45 |
| empty stub — word (skipped by rule) | 15 |
| **entries** | **52,107** |

The Nôm layer: 9,112 `character` records carrying **11,850 senses**
(the survey figure, exact). Readings arrive in two shapes:

- `related` items tagged `nom-reading` (8,418) / `han-viet-reading`
  (2,881) — record or sense level, 3,559 records (all character
  records save 5 word records);
- `forms` tagged `Hán-Nôm` on character records (9,698 rows; 2 more on
  word records) — the older shape: the values are quốc ngữ readings
  (犭 → khuyển), not spellings.

Spellings: `forms` tagged `CJK` on word records — 13,537 rows (13,529
after per-record repeats fold), the Han/Nôm spellings of quốc ngữ
headwords (chó → 㹥 𤝹 𤠚 𦢞 犬). 5,882 reflex rows (descendants +
etymons) through the family parser.

The glossless records are mostly the Nôm data itself (馬 as a
character is glossless and carries seven readings), so the wiktionary-ar
"glossless skips" rule would have dropped the shelf's reason for
existing; only the records with nothing at all skip.

## Cut

9 complete JSONL lines, byte-verbatim in upstream order (0-based
upstream line numbers):

1. 犬 (character) — line 6: glossed "chữ Nôm form of chó", readings as
   `related` (han-viet khuyển; nom khuyển, chó). KEPT.
2. 馬 (character) — line 7: glossless (`no-gloss`), seven nom-readings
   + one Hán-Việt reading. KEPT.
3. 馬 (noun, etymology 1) — line 8: "chữ Hán form of mã". KEPT.
4. 犭 (character) — line 21: glossless, the older shape — reading as a
   `Hán-Nôm`-tagged form (khuyển). KEPT.
5. toe (verb) — line 90: glossless, one `CJK` spelling 𡄪. KEPT.
6. sung (adj, etymology 2) — line 232: glossless, etymology text only
   ("Sino-Vietnamese word from 充."). KEPT.
7. 丂 (character) — line 393: the empty character stub. SKIPPED by rule.
8. ken (adj) — line 7892: the empty word stub. SKIPPED by rule.
9. chó (noun) — line 11087: glossed "dog", five `CJK` spellings, the
   Proto-Vietic / Proto-Austroasiatic `inh` etymons. KEPT.

## Refresh

Re-fetch the URL above and re-select the same `word`/`pos`/
`etymology_number` triples. NOTE the upstream deprecation caveat
(WiktionaryKaikki class note): if the per-language JSONL is gone, filter
the full wiktextract dump by `lang_code == "vi"`.
