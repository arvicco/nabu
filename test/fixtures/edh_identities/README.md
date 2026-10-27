# EDH identity fixture — one GODOT-dated altar

A real EDH record carrying every identity layer the adapter fixture
(`test/fixtures/edh/`) lacks, kept in its own tree so the shared adapter
fixture's counts stay put. Read **byte-identical** on 2026-10-22 from the
box's canonical tree (`canonical/edh/`, the 2021-12-16 dump zips unpacked by
the edh fetch); the two CSVs are trimmed to the header plus this record's
rows (whole physical lines, byte-identical).

Layout mirrors the canonical workdir (`edh/` is the source dir, so this
directory is a canonical root for the timeline extractor):

- `edh/epidoc/HD070001-HD080000/HD072020.xml` — the votive altar from
  Siscia (Pannonia superior) to Mars and Victoria by the beneficiarius
  consularis L. Domitius Constitutus, dated by the consuls of 217.
- `edh/text/edh_data_text.csv` — its row: `dat_tag` 22 / `dat_monat` 5 /
  `dat_jahr_a` 217 with `dat_jahr_e` empty (the EpiDoc says
  `when-custom="0217"` — a point year), the GODOT record
  `https://godot.date/id/p48LHaNtU64BgoQKhHgZyJ`, and the literature
  "AE 1901, 0234. (B) # CIL 03, 15180. (B) # … # PIR (2. Aufl.) B 166. #
  PIR (2. Aufl.) M 518. #".
- `edh/pers/edh_data_pers.csv` — its three persons: the dedicant with a
  romans1by1 `uri`, the two consuls (Praesens, Extricatus) with `pir`
  entries.

Exercised by `test/edh_citations_test.rb` (AE/CIL/GODOT reference edges),
`test/store/timeline_builder/edh_dates_test.rb` (day precision on a point
year), `test/edh_persons_test.rb` and `test/person_command_test.rb`
(identity refs).

License: CC BY-SA 4.0, the per-file `<licence>` element and the EDH
`/data` page grant (as `test/fixtures/edh/README.md`).
