# theatre-classique fixtures

Real upstream samples from **Théâtre Classique** (Paul Fièvre,
theatre-classique.fr) as mirrored verbatim by the DraCor project at
github.com/dracor-org/theatre-classique, branch `main` @
d6ed03d8844f4be19f83a78d00ebf3cf7c86b95e (pushed 2024-09-02), retrieved
2026-10-28, laid out as the repository lays them out (`xml/<FILE>.xml`).

Three files are TRIMMED real files: `teiHeader` and `front` verbatim; the
body keeps act 1 scene 1 (its first speeches), act 2 scene 1 (its first two
speeches) and — for SAND_MOLIERE — act 3 scene 8 cut to the speech carrying
a loose stage direction and its two neighbours. The trim was done with
Nokogiri (node removal, re-serialized as UTF-8). BARY_BELLESMAINS is the
whole upstream file, byte-identical. Nothing is hand-written.

| File | Why |
|---|---|
| `xml/MOLIERE_MISANTHROPE.xml` | verse comedy (1667 print); a line shared across speakers (`<l id="1" part="i">` / `part="f"`); full front: privilege, imprint, first performance 1666-06-04, preface and a contemporary letter, cast list, setting |
| `xml/SAND_MOLIERE.xml` | prose drama (1851) — `<p>` speeches of `<s>` sentences; stage directions; an untagged stage direction loose inside an `<sp>`; upstream numbers BOTH of its first two acts `n="1"`; no `<idno>` |
| `xml/ABEILLE_CORIOLAN.xml` | verse tragedy (1676, La Haye imprint); the P4-era `<TEI.2>` root (3 files), no `xml:lang` |
| `xml/BARY_BELLESMAINS.xml` | whole file: a one-act prose dialogue (1662) with the all-lowercase `titlestmt`/`publicationstmt` spelling (35 files lowercase `titlestmt`, 40 `publicationstmt`), "16..-16.." author years, the imprint inside `docImprint/editor`, a front `<note>` |

## Delivery grains (enumerated 2026-10-28)

What the mirror serves, and what the adapter takes:

- **`xml/*.xml` — one TEI file per play: the document (ACCEPTED).** 1,940
  files (1,939 `.xml` + 1 `.XML`), all well-formed; one
  (CORNEILLET_LAODICE) declares `encoding="iso-8859-1"` and carries
  Latin-1 bytes — it quarantines at the UTF-8 encoding belt (the adapter
  test rebuilds that case from a transcoded fixture in a temp dir).
- `README.md`, `update`, `new-id-entries`, `.gitignore` — repository
  tooling, outside the text; the sparse cone fetches only `xml/` +
  `README.md`.
- The `dracor` and `jjokisch` branches — DraCor's edited derivatives (the
  FreDraCor pipeline input), not upstream's files; never fetched.

The live site serves further grains the adapter never touches (its
robots.txt disallows `/pages/documents/` to every agent): the per-play
HTML/print views and statistics pages, and the "textes polémiques ou
théoriques" around the corpus.

Rejected-by-rule within the accepted grain: plays whose textual author died
after the life + 70 cutoff (1955). The 2026-10-28 census finds NONE in the
mirror (latest textual death 1951), so there is no real specimen to pin;
the adapter test exercises the rule on a copy of a fixture whose author
years are rewritten in a temp dir.

## License

Each file's header: `<rights>Creative Commons BY-NC-SA</rights>`
(1,854 of 1,940; 9 spell it "BY-NC-sA"; 95 carry no rights element). The
site's rights page (pages/droits.html) makes personal, pedagogical and
non-commercial reuse free with the source credited; commercial reuse
needs prior agreement → license class `nc`.
