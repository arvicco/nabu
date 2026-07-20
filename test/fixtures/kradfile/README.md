# KRADFILE fixture

Trimmed slice of the EDRDG `kradfile` — the kanji→component decomposition
index behind Jisho's multi-radical search.

- **Source URL:** http://ftp.edrdg.org/pub/Nihongo/kradfile.gz
  (unpacked to plain `kradfile` for the fixture)
- **Retrieved:** 2026-07-20 (base pair, JIS X 0208, 6,355 kanji upstream)
- **Encoding:** EUC-JP (preserved byte-verbatim — `file` reports "Non-ISO
  extended-ASCII text"; the adapter transcodes EUC-JP → UTF-8 NFC at the
  boundary, which is the encoding regression this fixture guards).
- **License:** the SAME EDRDG document the `edrdg` (KANJIDIC2 + JMdict)
  fixture cites — CC BY-SA 4.0, edrdg.org/edrdg/licence.html: *"The
  dictionary files are made available under a Creative Commons
  Attribution-ShareAlike Licence (V4.0)."*, scope §2 naming
  RADKFILE/KRADFILE → registry class `attribution`, zero new licence
  surface. © Michael Raine, James Breen and the EDRDG.

## Trim

The real `#`-comment header is kept verbatim, followed by 10 real kanji
lines: the acceptance character 棄 (`棄 : 一 木 亠 凵 厶`) plus 木-containing
kanji (本 林 材 村 校) and non-木 controls (一 世 天 愛), so the component
index and `--char-component 木` flat-containment filter have real coverage.
The lines preserve upstream's non-Unicode-clean elements verbatim
(材's `ノ`, 世's `｜`) — honest members of the index.

The companion RADKFILE (component → kanji, `$`-header groups) is the
transpose of this same bipartite graph and is recovered by scanning these
per-kanji component lists; the base KRADFILE alone backs both the card's
component-index row and the flat containment filter, so it is the only
member ingested in v1.
