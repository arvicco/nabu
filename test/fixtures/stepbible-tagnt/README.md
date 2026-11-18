# stepbible-tagnt fixtures

Retrieved 2026-11-18 from STEPBible-Data (github.com/STEPBible/STEPBible-Data),
directory `Translators Amalgamated OT+NT`, pinned at commit
`5de0a47f35f0fc13dfe1430d104e5db8a4285f9c` (master, 2026-11-02, "Licence
summary clarified" — the repo's only git tag is unrelated to these files, so
the pin is by SHA). Raw URL shape:

    https://raw.githubusercontent.com/STEPBible/STEPBible-Data/5de0a47f35f0fc13dfe1430d104e5db8a4285f9c/Translators%20Amalgamated%20OT%2BNT/<file>

License: CC BY 4.0 — repo README ("STEPBible Data Repository CC BY 4.0";
credit "STEP Bible" linked to www.STEPBible.org) and every file header ("Data
created by www.STEPBible.org based on work at Tyndale House Cambridge (CC BY
4.0)"). The header also asks: "Please do not post copies of this data file
elsewhere, so that this remains the single up-to-date source". These trims are
small test excerpts kept for the parser's regression suite, not copies of the
data files.

## Delivery grains upstream serves (directory listing at the pin)

| Grain | Files | Taken? |
|---|---|---|
| TAGNT — Greek NT amalgam, word per row | `TAGNT Mat-Jhn - …CC-BY.txt` (14.2 MB), `TAGNT Act-Rev - …CC-BY.txt` (15.9 MB) | **accepted**: one document per BOOK (27), one passage per NRSV verse |
| TAHOT — Hebrew OT amalgam | `TAHOT Gen-Deu`, `Jos-Est`, `Job-Sng`, `Isa-Mal` (…CC BY.txt) | rejected by rule (OT Hebrew, outside this source) |
| OLD format TOTHT — older Hebrew OT tagging | subdirectory `OLD format TOTHT/`, four files | rejected by rule (same) |

Inside a TAGNT file the grains are: the documentation header, per-verse
summary blocks (`# Mat.1.1`, `#_Translation`, `#_Word=Grammar`,
`#_Significant variant` — a derived restatement of the word rows, not
ingested), a per-verse column-header row (`Word & Type …`), and the word rows
(`Mat.1.1#01=NKO …`) — the accepted grain.

## Files (byte-identical excerpts, upstream line order kept)

- `Mat-Jhn/TAGNT Mat-Jhn - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt`
  — the full header (lines 1–88) plus the verse blocks for Mat 1:1–2
  (spelling variants, multi-form dictionary entry Δαυείδ), Mat 6:13 (the TR
  doxology: K/KO words in TR+Byz only, the `^` extra-text note), Mat 15:6
  (the `{15.5}` versification bracket on half the verse), Mat 17:20–21
  (an N(K)O meaning variant; 17:21 is a whole KO verse absent from NA), and
  John 1:1–2 (the second book of the file).
- `Act-Rev/TAGNT Act-Rev - Translators Amalgamated Greek NT - STEPBible.org CC-BY.txt`
  — the full header (lines 1–90) plus Act 1:1, Act 5:39 (joined words
  μήποτε with two-part Strong/dictionary fields), Jas 5:3 (the homograph
  mark `ἰός (2)`), 3 John WHOLE (15 verses, `[1.14]` KJV bracket on 1:15),
  and Rev 22:21 (the file's last verse, through end of file).
- `TAHOT-Job-Sng/TAHOT Job-Sng - Translators Amalgamated Hebrew OT - STEPBible.org CC BY.txt`
  — the REJECTED-grain specimen: the first 103 lines of the TAHOT Job–Song
  file (header + Job 1:1). The adapter's discovery_skips counts it skipped
  by rule; #fetch never downloads it.

## Reconciliation (full pinned files, censused 2026-11-18)

Upstream's header claims 142,036 words (133,608 NKO-class + 3,084 + 4,164
+ 896 + 284). The two files carry 142,095 word rows in 7,958 NRSV verses
over 27 books (SBLGNT has 7,939 verses: TAGNT also prints the TR-only
verses such as Mat 17:21). The 59-row residue is upstream's own — spelling-
and order-only differences are "recorded below but are not counted in these
totals".

File sha256 at the pin: Mat-Jhn
`d4c0c820fdf9f2b450c9f96ce6103d6875028affd2e44094d753f1329ca1fd85`, Act-Rev
`122040eeeaeba50d6abbf67b39cacaff687211bda69b080e5d53927c830d9968`.
