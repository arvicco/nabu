# CBDB fixtures (cbdb-project/cbdb_sqlite, CC BY-NC-SA 4.0)

`person_sample.sql` — REAL rows cut 2026-09-11 from the held
`canonical/cbdb/cbdb_20260905.sqlite3` (sha-pinned upstream artifact):
the `BIOG_MAIN` / `ALTNAME_DATA` / `DYNASTIES` schemas verbatim plus
three persons — Wang Anshi 王安石 (1762; three alt names of distinct
type codes), Su Shi 蘇軾 (3767; no alt names), and Wu Shi 吳氏(王安石妻)
(38653; the 0-birthyear + index-year shape, female flag) — and the
Song dynasty row (c_dy 15). Tests load it into in-memory SQLite.

Re-cut recipe: select the same ids from the current canonical
artifact (schemas via sqlite_master, rows verbatim).
