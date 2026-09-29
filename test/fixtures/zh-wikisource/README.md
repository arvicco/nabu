# zh-wikisource fixtures

Real api.php captures from zh.wikisource.org, retrieved 2026-09-29,
stored in the adapter's own envelope shape (`pages/<pageid>.json`:
title/pageid/ns/revid/timestamp/wikitext + "work"/"part" provenance;
transcluded works add a "transclusions" title → wikitext map):

- `109484.json` — 元朝秘史/卷15 (whole, 1,196 bytes): direct text,
  the Ming 總譯 layer (language zho).
- `41615.json` — 續資治通鑑/卷001: direct text, TRIMMED to the first
  ~3,000 bytes at a line boundary (14,279 → 2,998).
- `63644.json` — 全唐文/卷0001: the transclusion-shell shape, TRIMMED
  to the Collection header + front matter + the first 3 sections;
  the "transclusions" map carries those 3 piece pages' wikitext whole
  (授老人等官教 · 徒隸等準從本色授官教 · 授逸民道士等官教).

Re-cut: fetch each title's (and piece title's) current revision via
api.php and re-apply the stated trims.
