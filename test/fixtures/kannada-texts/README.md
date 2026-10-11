# kannada-texts fixtures (P118-3)

Real upstream samples from the Kannada Digital Texts Project,
<https://github.com/aso2101/kannada_texts>, retrieved **2026-10-11** at
`main` HEAD `dff1190846306ac5852f0b25422854d2ee87051a`. Every file carries
its in-file grant, verbatim: "Kannada Digital Texts Project. Distributed
under a Creative Commons Attribution-ShareAlike 4.0 license." (the repo
README's default reads "Unless specified otherwise, the data provided in
this repository is made available under a CC-BY 4.0 license.").

Four files, each a TRIM of the upstream file named in `manifest.yml`, laid
out under `tei/<author>/` exactly as upstream (discovery globs
`tei/**/*.xml`). Trimmed files carry suffixed stems so fixture urns never
collide with the real corpus urns.

| file | exercises |
|---|---|
| `tei/Pampa/pampa-ādipurāṇaṁ-a1.xml` | `lg/@met` meters, `div/@n` + `lg/@n` citations, a prose `p` with `lb break="no"`, page breaks, the āśvāsa and closing `trailer`s; siglum `Ādi` → the README's date 941 |
| `tei/Janna/janna-anantanāthapurāṇaṁ-a1.xml` | bottom-of-page `note`s (dropped), the `label type="metrical"` meter on an unmetered stanza (tripadi) and the "va." prose label |
| `tei/Honnamma/honnamma-hadibadeyadharma-iso-s1-9.xml` | the upstream `<text xml:lang="san-Latn">` on a Kannada work (the HaDha repair), a cited Sanskrit `lg` inside `cit/quote`, the commented-out sourceDesc |
| `tei/Nāgavarma II/nāgavarma-karṇāṭakabhāṣābhūṣaṇam-s1-4.xml` | a Sanskrit-language document (sūtra `ab` + commentary `p`) with kan-Latn example `list`s; siglum `KaBhāBhū` → "ca. 1042" |

## Recipe

Clone the repo; for each file keep the listed 1-based line ranges of the
upstream file verbatim, in order (ranges in each manifest entry's `trim`),
and check the result is well-formed XML. The ranges cut at element
boundaries, so no tag is synthesized.
