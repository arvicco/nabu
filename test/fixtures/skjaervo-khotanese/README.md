# skjaervo-khotanese fixtures

Retrieved 2026-09-28 from Zenodo doi 10.5281/zenodo.3372682 (CC BY
4.0): "Khotanese Manuscripts from Chinese Turkestan in the British
Library (XML records)" — Skjærvø's revised 2014 online edition as ONE
TEI.2 XML (4.3 MB, 2,357 msDescription records, 20,596 <l> lines).
The record's own caveat: DRAFT, unproofed against physical holdings.
Fixture = the file's real header + the first 3 msDescription records
+ closing tags, verbatim.

Shape: msDescription[@n] → msIdentifier (settlement/repository/
collection + idno current/old) → msContents/msItem[@n @type] with an
English <note> (apparatus) and <q lang="khot-Latn"
type="transliteration"> holding <l n="N"> lines — the text layer.
