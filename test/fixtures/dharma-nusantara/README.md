# dharma-nusantara fixtures

Three whole real files from github.com/erc-dharma/tfc-nusantara-epigraphy
(master), retrieved 2026-09-01 from raw.githubusercontent.com, unmodified:

- `xml/DHARMA_INSIDENK00007.xml` — Old Malay (`omy-Latn`) charter of
  Śaka 1208: physical lines wrap the stone's faces mid-word
  (`<milestone unit="face" break="no"/>`, the ti|thi join) and continue
  across `<p>` boundaries — the line-assembly cases.
- `xml/DHARMA_INSIDENK00024.xml` — a short pure Old Malay record.
- `xml/DHARMA_INSIDENK00050.xml` — carries upstream's REAL
  `xml:lang="languageb-Latn"` template-placeholder bug (found in the
  2026-09-01 full-repo census) — the quarantine-net regression fixture.
- `xml/DHARMA_INSIDENKPasrujambe28.xml` — P120-R1 regression, copied
  whole and unmodified from the hub's canonical fetch at upstream commit
  65b4a426af7d: a three-line Old Javanese label ("baṭara hindra") whose
  edition div NESTS an English `<div type="translation">` ("Lord
  Indra"). Before the shared parser pruned nested editorial divs, the
  translation glued onto line 3 — the pin that it no longer mints.

License: in-file `<licence>` CC BY-SA 4.0 in all four.
