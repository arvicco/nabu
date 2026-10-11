# prakrit-texts fixtures (P118-3)

Real upstream samples from the Prakrit Digital Texts Project,
<https://github.com/aso2101/prakrit_texts>, retrieved **2026-10-11** at
`master` HEAD `67f68d87f99c89abeabd8918cd4cc29a5ce1e210`. Laid out under
`tei/<author>/` exactly as upstream (discovery globs `tei/**/*.xml`);
trimmed files carry suffixed stems so fixture urns never collide with the
real corpus urns.

| file | case | exercises |
|---|---|---|
| `tei/Vākpatirāja/GaüḍVa-1-3.xml` | ingested | āryā meters, the Sanskrit chāyā `note` (annotations, not text), `app/lem/rdg`, body-level labels, the closing trailer with its own chāyā |
| `tei/Hēmacandra/DēNāMā-1-2.xml` | ingested | `quote type="base-text"` stanzas + untagged commentary `p`s, nested div paths, the example `lg` that repeats the base-text number (`:b2`) |
| `tei/Bappabhaṭṭi/Tārā-1-3.xml` | ingested | n-less sections (ordinals never reset), the san-Latn ṭīkā, `pb ed="b"`/`ed="bh"` page breaks |
| `tei/Śvētāmbarāgama/Agam_44_…_Nandisuyam_003787-s1-3.xml` | ingested | pka-Latn, section divs, the `<back>` appendix (`back.` citations) |
| `tei/Śvētāmbarāgama/Agam_01_…_Aayaro_003701-s1-2.xml` | EXCLUDED | the template availability `<p><!-- add whatever license you like: --></p>` — no grant: skipped by rule at discovery, refused by the parser's license gate |
| `tei/Pravarasēna/Sētu.xml` | EXCLUDED | SARIT's Sētubandha (authority SARIT, CC BY-SA 3.0), held as `urn:nabu:sarit:pravarasena-setubandha` — the declared overlap (kept at its upstream path, which the rule keys on); also the kulaka `lg`-of-`lg`s container |
| `quarantine/ācāraniryukti-1-66.xml` | QUARANTINE | outside `tei/` so discovery never yields it: upstream's not-well-formed gāthā 66 (`<lg n="66"` unclosed, `<|vaï|>`), the malformed-XML ParseError |

Grant of every ingested file, verbatim: "Prakrit Digital Texts Project.
Distributed under a Creative Commons Attribution-ShareAlike 4.0 license."

## Recipe

Clone the repo; for each file keep the listed 1-based line ranges of the
upstream file verbatim, in order (ranges in each manifest entry's `trim`),
and check the result is well-formed XML (except the quarantine sample,
which must stay malformed). The Āyāraṅga trim closes its open divs with
upstream's own closing-tag lines taken from later in the same file.
