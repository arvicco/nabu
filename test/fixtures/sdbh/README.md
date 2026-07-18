# sdbh fixtures

Byte-verbatim sample of the UBS Dictionary of Biblical Hebrew (the
open-license extract of the Semantic Dictionary of Biblical Hebrew, SDBH)
XML, English edition v0.9.2.

- Retrieved: 2026-07-18
- URL: <https://raw.githubusercontent.com/ubsicap/ubs-open-license/main/dictionaries/hebrew/XML/UBSHebrewDic-v0.9.2-en.XML>
- Upstream commit: `ubsicap/ubs-open-license@3a6edd8212df2e1189037ad39687726990c80d56`
  (main, committed 2026-07-09)
- Full-file sha256: `f80096ea874a7c4a08f7c5dfaf99f67db76c5c71524fbf8aa1dd44ac5ba94a71`
  (37,001,017 bytes / ~35 MiB — SAX/Reader territory, never DOM)
- License: CC BY-SA 4.0 — `dictionaries/hebrew/README.md` verbatim: "This
  work is licensed under a Creative Commons Attribution-ShareAlike 4.0
  International License. … (UBS Dictionary of Biblical Hebrew © United
  Bible Societies, 2023. Adapted from Semantic Dictionary of Biblical
  Hebrew © 2000-2023 United Bible Societies.)"

## Trimming

XML declaration + `<Lexicon>` root line verbatim, then ELEVEN complete
`<Lexicon_Entry>` elements sliced byte-for-byte from the full file (no
edits inside any entry), then `</Lexicon>`. Full-file census at retrieval
time: 7,932 entries / 16,220 non-empty DefinitionShort / 23,879 non-empty
Gloss / 260,813 LEXReference / 16,686 LEXDomain (380 distinct labels) /
9,079 Strong.

| Id (entry_id)     | Lemma        | exercises |
|-------------------|--------------|-----------|
| `000001000000000` | אֵב          | H+A StrongCodes (H0003, A0004), three meanings, semantic domains (Vegetation/Stage/Fruits), a collocation, Aramaic Daniel refs |
| `000002000000000` | אַב          | Aramaic-only StrongCodes (A0002) → entry language `arc` |
| `000095000000000` | אָגוּר       | MeaningsOfName present but EMPTY (`<MeaningOfName LanguageCode="en" />`) — measured: ALL 1,607 MeaningOfName elements upstream are empty in v0.9.2, so there is no name-meaning lane to extract |
| `000856000000000` | בֹּהוּ       | refs Gen 1:2 / Isa 34:11 / Jer 4:23 — the oshb resolution-shape probe (hit, book-miss, verse-miss) |
| `002328000000000` | חַלָּשׁ      | LEXSynonyms + LEXAntonyms |
| `002346000000000` | חָמֹוץ       | EMPTY `<DefinitionShort />` (4 exist upstream) — gloss still present |
| `003359000000000` | כִּנְעָה     | single ref Jer 10:17 — second positive resolution book |
| `003363000000000` | כנף          | LEXReference with trailing footnote marker `{N:001}` (2,697 exist upstream); unpointed lemma |
| `003803000000000` | מֹופַעַת     | smallest entry with `<Notes>` — Note Content with `{A:…}` version markers + Note References |
| `006318000000000` | צְפַתָה      | upstream quirk: bare-digit `<Strong>6318</Strong>` (2 exist) |
| `006756000000000` | רְחֹבֹת עִיר | upstream quirk: `<Strong>Reinier de Blois</Strong>` — an author name inside StrongCodes (3 exist); kept verbatim, canonical means canonical |

3,217 of 7,932 upstream lemmas are NOT NFC-stable (Masoretic mark order:
dagesh ccc 21 written before vowel points ccc 10–19) — the hbo/arc NFC
exemption (architecture §3) therefore governs this shelf's headwords and
bodies, exactly as it governs oshb passages. אֵב's pointed forms in this
fixture include such sequences; the adapter test asserts byte-honesty.

Scripture-reference encoding (upstream `dictionaries/hebrew/README.md`):
`BBBCCCVVVSSWWW` — Book (001–039, Protestant OT order = MT order), Chapter,
Verse, Segment (always 00 for Hebrew, measured), Word ("counted using even
numbers only" — word element = WWW/2). Versification is Masoretic (measured:
אֵב's Aramaic refs are Dan 4:9/4:11/4:18 MT, not the English 4:12/14/21),
i.e. the same versification as oshb/WLC osisIDs.
