# OSHB fixtures

Real upstream samples from openscriptures/morphhb — the Open Scriptures
Hebrew Bible: the Westminster Leningrad Codex as OSIS XML with the complete
OSHM morphology layer (CLAUDE.md fixture rules; P26-3, owner-authorized
single clone 2026-07-18).

- **Retrieved:** 2026-07-18, from a clone of
  `https://github.com/openscriptures/morphhb` at HEAD
  `3d15126fb1ef74867fc1434be1942e837932691f`. Full clone ≈ 174 MB
  (`wlc/` itself ≈ 27 MB; the rest is git history and site/tooling).
- **License per layer (verbatim, in-repo):**
  - WLC text — Public Domain. `LICENSE.md`: "This work is based on *The
    Westminster Leningrad Codex*, which is in the public domain."
  - Lemma/morphology — CC BY 4.0. `README.md`: "Lemma and morphology data
    are licensed under a Creative Commons Attribution 4.0 International
    license. For attribution purposes, credit the Open Scriptures Hebrew
    Bible Project." `LICENSE.md` attribution wording: "Original work of the
    Open Scriptures Hebrew Bible available at
    https://github.com/openscriptures/morphhb".
  - → source `license_class: open`, the CC BY credit carried in the
    manifest license text.
- **The anti-NFC warning (upstream `README.md`, "Hebrew Normalization"):**
  "any uses of the OSHB should avoid NFC normalization." Measured true:
  Ruth 1:1's words carry dagesh/shin-dot BEFORE vowel points (the WLC mark
  order); NFC canonical ordering would reorder them. These fixtures are the
  byte-verbatim ground truth for the P26-3 per-language NFC exemption
  (owner ruling 2026-07-18).

## Files (under `wlc/`, mirroring the upstream layout)

All slices are **byte-verbatim**: upstream line ranges kept intact
(header + selected whole `<chapter>` blocks + closing tags), nothing
re-serialized.

| Path | Contents |
|---|---|
| `wlc/Gen.xml` | **Trimmed**: header + Gen 1 (31 verses) + Gen 31 (54 verses — 31:47 has Laban's two Aramaic words, `ANp` morphs, the token-grain language pin) |
| `wlc/Ruth.xml` | **Trimmed**: header + Ruth 1 (22 verses — the NFC-instability pin at 1:1, a ketiv/qere at 1:8, chapter-end BHS/BHQ apparatus notes) |
| `wlc/Ps.xml` | **Trimmed**: header + Ps 23 (Hebrew numbering; Greek/LXX Psalm 22 — the psalms `numbering:` table exercise book; bare `KJV:Ps.23.1` mapping note) |
| `wlc/Jer.xml` | **Trimmed**: header + Jer 10 (25 verses — 10:11 is the book's one whole-verse Aramaic sentence, the passage-majority exercise; maqqef/sof-pasuq/samekh joining) |
| `wlc/VerseMap.xml` | **Trimmed**: header comment + the Gen `<book>` block — the upstream WLC↔KJV versification concordance, pinned as a NON-book (discover excludes it) |

## Structure notes (OshbOsisParser, P26-3)

- One `<div type="book">` per file; container `<chapter>`/`<verse>` with
  native Masoretic osisIDs (`Gen.1.1`).
- `<w lemma="b/7225" morph="HR/Ncfsa" id="01xeN">` — lemma is an
  **augmented Strong's number** (prefix morphemes slash-joined, homograph
  letters suffixed: `1254 a`); morph is an **OSHM code** whose first letter
  is the language (`H` Hebrew, `A` Aramaic); id is the immutable OSHB word
  id. Word character data uses `/` as OSHB's morpheme divider — markup,
  not WLC text.
- Top-level `<seg>` marks: `x-maqqef` `־`, `x-sof-pasuq` `׃`, `x-paseq`
  `׀`, parashah `x-samekh`/`x-pe`; letter-size/suspended segs ride inside
  `<w>`.
- `<note type="variant">` = ketiv/qere (`<w type="x-ketiv">` in the running
  text, qere in `<rdg type="x-qere">`); `<note type="alternative">` =
  BHS/BHQ accent variants; bare notes = verse-mapping/apparatus prose.
