# aclt fixtures

Three REAL per-inscription Tsakorpus JSON files, copied WHOLE from the
corpus archive Timofey Arkhangelskiy delivered by email 2026-09-29
(`luwian_aclt.7z`, the `luwian_aclt/json/` tree; the same bytes the
manual drop ingests into `canonical/aclt/`). Small by nature — each is
a short inscription:

- `json/luwian-hieroglyph-en_244.json` — YALE seal (region Seals):
  one clause, the two paired representations (lang 0 broad
  transcription with morphology + English glosses; lang 1 sign-by-sign
  hieroglyphic transliteration).
- `json/luwian-hieroglyph-en_224.json` — TRAGANA (LOCRIS) (region
  Miscellaneous): the parenthetical-title slug case.
- `json/luwian-hieroglyph-en_56.json` — KARKAMIŠ B39a: upstream's own
  tombstone ("[KARKAMIŠ B39a - delete]", zero analyzed words — the
  corpus's only such file, censused 2026-09-30) — the skip-by-rule pin.

Re-cut: extract the held archive (`bsdtar -xf
canonical/aclt/luwian_aclt.7z`) and copy the three files whole.
