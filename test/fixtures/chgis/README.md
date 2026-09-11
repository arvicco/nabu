# CHGIS/TGAZ fixtures (Harvard Dataverse doi:10.7910/DVN/H3OB28, CC0 1.0)

Retrieved 2026-09-04 from `tgaz_bak_2018.zip` (file id 3370559; the
122 MB TGAZ MySQL dump). TRIMMED to the `mv_pn_srch` CREATE TABLE
block + TWO insert samples, byte-verbatim with the statement closes
(`);`) reinstated — everything else removed:

- tuples 83147–83148 of the TBRC block (re-cut 2026-09-10): TWO
  identical tuples for sys_id `TBRC_G1KR100` differing only in the
  surrogate `id` — the real dump loads its TBRC block 11× over
  (127 sys_ids × 11 tuples), which blew the place_index
  (gazetteer, place_id) unique key at first sync;
- the first INSERT statement's first TEN tuples (`hvd_1`…`hvd_10`).

Documents: the plain-mysqldump INSERT shape (NO column list — the
walker is fed CREATE TABLE order), both written forms per place
(hanzi 霸州 + pinyin "Ba Zhou"), x-before-y WGS84 coordinates, the
1820-snapshot year spans, feature types in both scripts, the hvd_
parent chain, and the duplicated-sys_id upstream quirk the derive
must coalesce.
