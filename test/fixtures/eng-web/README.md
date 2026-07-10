# World English Bible (eng-web) fixtures

Real upstream sample from the seven1m/open-bibles collection — the World
English Bible (WEB) via eBible.org, in USFX XML (CLAUDE.md fixture rules).

## Fixture gate (inherited approval, P11-8)

This is the SAME repo, SAME pinned sha, and SAME public-domain assertion
mechanism as the Vulgate fixtures, whose plan the owner approved for P11-5
(2026-07-09). Trimming 2–3 book slices of the WEB edition from that already
vendored, pinned repo is in scope under that approval — nothing is fetched
from outside the pinned open-bibles repo.

- **Retrieved:** 2026-07-10, from the already-vendored open-bibles checkout
  at `canonical/vulgate/eng-web.usfx.xml`, repo HEAD pinned
  `8c31c380a9f7af19fbe04e8eaaa6fa74601083d7` (2026-06-05).
- **License:** Public Domain → `license_class: open`. Verbatim evidence:
  - repo `README.md` translation table row:
    `| eng-web.usfx.xml | English | USFX | WEB | World English Bible | Public Domain |`
  - the file's own preface (`<book id="FRT">`): "Because the World English
    Bible is in the Public Domain (not copyrighted), it can be freely copied,
    distributed, and redistributed without any payment of royalties."
  - eBible.org copyright page (`ebible.org/Scriptures/copyright.php`):
    "No person, company, or organization may claim any kind of copyright or
    restriction on this version of the Bible... even if they make changes."
  - WEB is an update of the 1901 American Standard Version, itself public
    domain; the update was released to the public domain by its editor. NB
    the open-bibles repo carries no repo-wide LICENSE file — licensing is
    asserted per file in its README.

## Why WEB over KJV / DRA

WEB is modern, complete (OT + NT + deuterocanon), and unambiguously public
domain worldwide. The KJV is public domain in the US but remains under Crown
copyright (letters patent) in the UK; the Douay-Rheims is archaic. WEB avoids
both snags while giving the fullest canon — the readable English witness for
both alignment-hub works.

## Files

| Path | Bytes | Contents |
|---|---|---|
| `eng-web.usfx.xml` | 16,481 | **Trimmed** from the whole-bible upstream file: three WHOLE small scripture books byte-identical from the pinned blob — `<book id="JON">` (Jonah, 4 ch, 48 vv), `<book id="OBA">` (Obadiah, 1 ch, 21 vv), and `<book id="PHM">` (Philemon, 1 ch, 25 vv) — plus two TRIMMED non-scripture peripheral books `<book id="FRT">` (front matter/preface, first) and `<book id="GLO">` (glossary, last), all wrapped in the `<usfx>` root + `<languageCode>eng</languageCode>`. Scripture books need no mid-book trimming (unlike the Vulgate slice); parses strict (Nokogiri). |

Books chosen: JON aligns with the LXX/Vulgate Old Testament witness (the
packet's demo verse family, `align "JON 1"`); OBA gives a second one-chapter
OT book; PHM gives New Testament coverage — all small, all whole. FRT + GLO
(P11-10) are the file's two structural non-scripture books, kept so the
skipped-by-rule path has real (if trimmed) upstream shapes to test against.

## Structure notes (UsfxParser, P11-8)

- USFX is MILESTONE markup: `<book id="JON"><h>Jonah</h>` then `<c id="1"/>`
  chapter milestones and `<v id="1"/>text<ve/>` verse spans. Book ids are
  OSIS/Paratext 3-letter codes (JON, OBA, PHM); `<h>` carries the display
  name (Jonah, Obadiah, Philemon).
- Unlike the Clementine Vulgate, WEB carries INLINE `<f>` footnote apparatus
  (e.g. Jonah 1:1 `Now Yahweh’s<f caller="+">…rendered “LORD”…</f> word`).
  That text is editorial, not scripture: `UsfxParser` skips the `<f>`/`<x>`/
  `<fe>` note subtrees (`UsfxParser::NOTE_ELEMENTS`) so only the verse reading
  survives. Regression: `test/adapters/usfx_parser_test.rb`.
- Text is kept verbatim (WEB uses “Yahweh” for the divine Name), NFC at the
  boundary.
- **Non-scripture books (P11-10).** `FRT` (front matter) and `GLO` (glossary)
  are USFX/Paratext PERIPHERAL books: structural matter with zero `<v>` verses.
  `discover` still lists them (honest inventory), but `UsfxParser#parse`
  declines them by rule with `Nabu::DocumentSkipped`
  (`UsfxParser::NON_SCRIPTURE_BOOKS`) — the P11-7 skip signal the loader counts
  as skipped-by-rule, never a quarantine (those are for damaged scripture).
  Regression: `test/adapters/usfx_parser_test.rb`,
  `test/adapters/eng_web_test.rb`.
