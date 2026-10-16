# sga/form-lemma fixtures

The sga/form-lemma builder joins TWO editions of the same St Gall Priscian
glosses on their Thesaurus Palaeohibernicus reference. The St Gall side is
the stgall-priscian adapter fixture as-is (`test/fixtures/stgall-priscian`);
the CorPH adapter fixture (`test/fixtures/corph`) carries no St Gall text,
so this directory holds a second, independent trim of the same real CorPH
dump, cut to the units that pair with the St Gall fixture.

## corph/chronhibdev_2020.sql

A line-verbatim TRIM of CorPH's canonical dump `chronhibdev_2020.sql`
(39,102,512 bytes) from github.com/chronhib-MU/Chronhib-Website at the
pinned commit `e7ef75d5f9a6ea97210f028b7389fa9539fbe8c0` (2021-05-11; the
sha the corph adapter pins). Cut 2026-10-16 from the box's canonical/corph.

License — the repository LICENSE, verbatim header: "MIT License /
Copyright (c) 2020 [Chronologicon Hibernicum]" (covers the dump). These rows
are redistributed under that license.

Kept (every kept tuple line byte-verbatim; per table only the first INSERT
header is kept and the last kept tuple carries the `;` terminator):

- the dump preamble and the CREATE TABLE blocks of the five tables below;
- `TEXT`: row `0007` (St_Gall_Priscian — Bernhard Bauer's St Gall unit of
  CorPH; "Thes. II, 49–224");
- `SENTENCES`: the 16 text-0007 units whose `Locus1` (the Thesaurus
  Palaeohibernicus reference) is one of
  Sg 001a01–001a06, Sg 002a01, Sg 002a03, Sg 002a09, Sg 050,
  Sg 051a01, Sg 051a03, Sg 051b02, Sg 051b04, Sg 051b10, Sg 051b13 —
  every reference the stgall-priscian fixture's glosses carry except
  its malformed `105`, plus `Sg 001a06` (no St Gall fixture gloss: the
  CorPH-only side of the reference census);
- `MORPHOLOGY`: the 83 analyses of those units;
- `LEMMATA`: the 57 rows whose `Lemma` those analyses cite;
- `BIBLIOGRAPHY`: the 3 rows text 0007's Edition/Reference cite.

Dropped: SEARCH (a derived concordance), TEAM/USERS (personal data),
VARIATIONS (the adapter does not read it), and the index/AUTO_INCREMENT
trailer.

What the selection documents: the reference shapes on both sides
(`Sg 001a01` vs St Gall's display `1a1`, the shared malformed `50`), an
exact-lemma pair (`méit`), folded-only agreements (`días`/`diäs`,
`so`/`-so`), real convention divergences (`lebarda`/`lebardae`,
`a 4`/`3pl.poss.pron.`), CorPH's Latin and particle tokens inside an Irish
gloss (`(Latin letters and suffixes)`, `.i.`), and the empty-form
`∅ len.rel.particle` token that can never align.

Re-cut: clone the repository at the pinned commit and keep the listed
SENTENCES rows; the dependent MORPHOLOGY/LEMMATA/BIBLIOGRAPHY rows follow.
