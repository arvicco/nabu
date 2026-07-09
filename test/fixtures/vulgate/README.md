# Vulgate (Clementine) fixtures

Real upstream sample from the seven1m/open-bibles collection — the Tweedale
Clementine Vulgate Project text via eBible.org, in USFX XML (CLAUDE.md
fixture rules; P11-5 fixture plan, owner-approved 2026-07-09).

- **Retrieved:** 2026-07-09, via ranged HTTP reads (no bulk fetch) from
  `https://raw.githubusercontent.com/seven1m/open-bibles/8c31c380a9f7af19fbe04e8eaaa6fa74601083d7/lat-clementine.usfx.xml`
  (repo HEAD pinned `8c31c380a9f7af19fbe04e8eaaa6fa74601083d7`, 2026-06-05;
  upstream file 4,652,377 bytes, blob `c0e65106…`).
- **License:** Public Domain → `license_class: open`. Verbatim evidence:
  - repo `README.md` translation table row:
    `| lat-clementine.usfx.xml | Latin | USFX | | Clementine Latin Vulgate | Public Domain |`
  - eBible.org details page for this edition (`ebible.org/find/details.php?id=latVUC`):
    "Public Domain".
  - eBible.org copyright page (`ebible.org/Scriptures/copyright.php`):
    "No person, company, or organization may claim any kind of copyright or
    restriction on this version of the Bible... even if they make changes."
  - The Sixto-Clementine text itself dates to 1592; the digital edition
    (Clementine Vulgate Project, ed. Michael Tweedale et al.) was released
    to the public domain by its editor. NB the open-bibles repo carries no
    repo-wide LICENSE file — licensing is asserted per file in its README.

## Files

| Path | Bytes | Contents |
|---|---|---|
| `lat-clementine.usfx.xml` | 14,425 | **Trimmed** from the 4.65 MB upstream file, slices byte-identical: `<book id="GEN">` chapter 1 whole (31 vv, upstream bytes 39–4,122) + `<book id="MRK">` chapters 1–2 whole (73 vv, upstream bytes 3,814,062–3,846,683) + `<book id="JHN">` chapter 1 verses 1–18 (upstream bytes 4,028,801–4,030,515). Trim closes: `</book>` appended after each sliced book (GEN cut before `<c id="2"/>`, MRK before `<c id="3"/>`, JHN before `<v id="19"/>`), `</usfx>` appended at the end. Parses strict (Nokogiri). |

## Structure notes (UsfxParser, P11-5)

- USFX is MILESTONE markup, not container: `<book id="GEN"><h>Genesis</h>`
  then `<c id="1"/>` chapter milestones and `<v id="1"/>text<ve/>` verse
  spans. Verse text is the character data between `<v>` and `<ve/>`.
- Book ids are OSIS/Paratext 3-letter codes (GEN, MRK, JHN…); `<h>` carries
  the display name (Genesis, Marcus, Joannes).
- Upstream spells Latin ligatures (`cælum`, `tenebræ`) and spaced French-style
  punctuation (` : `, ` ; `, ` ? `) — kept verbatim, canonical means canonical.
- The full file covers the complete Clementine canon: GEN…MAL, deuterocanon
  (TOB JDT WIS SIR BAR 1MA 2MA…), MAT…REV.
