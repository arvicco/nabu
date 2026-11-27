# dbbe fixture

A schema-intact trim of the Database of Byzantine Book Epigrams archive
(Ghent University, dbbe.ugent.be), "Database of Byzantine Book Epigrams -
Archive" — Zenodo concept record 19435533 (doi:10.5281/zenodo.19435533).

- **Record resolved**: `GET https://zenodo.org/api/records/19435533/versions/latest`
  on 2026-11-27 → record **23008642** (doi:10.5281/zenodo.23008642),
  `publication_date` 2026-09-28, record updated 2026-11-16, license field
  `{"id": "cc-zero"}` (CC0 1.0 Universal).
- **File**: `dbbe_archive.sqlite`, retrieved 2026-11-27 from
  <https://zenodo.org/api/records/23008642/files/dbbe_archive.sqlite/content>
  (60,125,184 bytes, `Last-Modified: Mon, 16 Nov 2026 10:42:29 GMT`).
- **Full-file md5** (the record's published checksum, verified on download):
  `85b0abf7ed8801d5524a58d0e159abce`
- `zenodo-latest.json` is that API response trimmed to the fields the
  adapter reads and a few identifying ones (ids, DOIs, dates, license,
  files, links) — every value verbatim, the long description and creator
  list dropped.

The file is SQLite with the WAL header bytes set (offsets 18/19 = 2); the
trim keeps that, so the tests pin the reader's immutable open (a plain
read-only open writes `-wal`/`-shm` beside the file).

## Grains upstream serves (whole-file census, 2026-11-27)

The record serves one file. Inside it, upstream's six concepts and what
the adapter takes:

| Grain | Rows | Taken as |
|---|---:|---|
| `occurrence` | 13,050 | **document** — 12,928 with text; the **122 with no transcribed text** (blank `text_original`, no verses) are **skipped by rule** |
| `verses` | 53,898 | the occurrence's passages (2 blank rows = gaps) |
| `type` | 5,226 | **document** (passages = lines of the normalized text) |
| `type_translation` | 2,504 | **sibling document** `-tr<id>` (translations: true) |
| `manuscript` | 4,560 | metadata on its occurrences (not a document) |
| `person` | 3,726 | metadata (historical roles only; not a document) |
| bibliography (`article`, `book`, `book_chapter`, `blog`, `blog_post`, `bib_varia`, `online_source`, `phd`) | 2,640 | not carried (citation records) |

## The trim

Eight occurrences, the nine types they and two extras name, and every row
hanging off them (verses, link tables, manuscripts, persons, catalogue
identifications, the bibliography items they cite); the lookup tables
(genre, metre, roles, language, location, library, content, keyword, tag …)
whole; every table and its DDL kept. 342 KB.

| Record | Pins |
|---|---|
| occurrence 24315 | Messina S. Salv. 117, f. 239r, dated 1116; origin Calabria → Southern Italy → Italy; scribe Leon; witnesses type 1865 (poet Ignatios Methymnaeos; English ×2 + Latin ×2 translations); verse groups |
| occurrence 16897 | dated 1001–1100; a scribal title (`· :· ἄλλο :-`); two genres |
| occurrence 17332 | 17 verses with one blank row (verse 7); month-precise dates (1057-09-01/1058-08-31); origin the Stoudios monastery; German + English translations of its type 2095 |
| occurrence 28432 | one occurrence linked to two types (2175, 3753); origin Istanbul (Konstantinoupolis) |
| occurrence 20028 | undated (blank date bounds), with text |
| occurrence 18852 | no type |
| occurrence 24466 | type 6372 with English + upstream-"Greek" (Modern Greek) translations |
| occurrence 17280 | **rejected grain**: no transcribed text (text completely unknown) |
| type 6043 | a translation stored with CRLF line ends |
| type 4494 | a type with no occurrence |

The rejected record classes that are not documents (manuscripts, persons,
bibliography) are present as rows of their own tables.

Recipe (run from a scratch directory outside the repo against the full
downloaded file: `ruby trim.rb <dbbe_archive.sqlite> <out path>`):

```ruby
require "fileutils"
require "sqlite3"

src, out = ARGV
OCCURRENCES = [24315, 16897, 17332, 28432, 20028, 18852, 17280, 24466].freeze
EXTRA_TYPES = [6043, 4494].freeze

work = "#{out}.work"
FileUtils.rm_f([work, out, "#{work}-wal", "#{work}-shm"])
FileUtils.cp(src, work)
db = SQLite3::Database.new(work)
db.execute("PRAGMA journal_mode=DELETE")
db.execute("PRAGMA foreign_keys=OFF")

tables = db.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
columns = tables.to_h { |t| [t, db.execute("PRAGMA table_info(\"#{t}\")").map { |r| r[1] }] }

occ = OCCURRENCES.join(",")
types = (db.execute("SELECT DISTINCT type_id FROM type_occurrence WHERE occurrence_id IN (#{occ})").flatten +
         EXTRA_TYPES).uniq.join(",")
db.execute("DELETE FROM occurrence WHERE id NOT IN (#{occ})")
db.execute("DELETE FROM type WHERE id NOT IN (#{types})")
mss = db.execute("SELECT DISTINCT manuscript_id FROM occurrence").flatten.join(",")
db.execute("DELETE FROM manuscript WHERE id NOT IN (#{mss})")

# Link tables keyed on the three kept entities (both ends of the relation tables).
tables.each do |t|
  cols = columns[t]
  next if %w[occurrence type manuscript].include?(t)

  db.execute("DELETE FROM \"#{t}\" WHERE occurrence_id NOT IN (#{occ})") if cols.include?("occurrence_id")
  db.execute("DELETE FROM \"#{t}\" WHERE related_occurrence_id NOT IN (#{occ})") if cols.include?("related_occurrence_id")
  db.execute("DELETE FROM \"#{t}\" WHERE type_id NOT IN (#{types})") if cols.include?("type_id")
  db.execute("DELETE FROM \"#{t}\" WHERE related_type_id NOT IN (#{types})") if cols.include?("related_type_id")
  db.execute("DELETE FROM \"#{t}\" WHERE manuscript_id NOT IN (#{mss})") if cols.include?("manuscript_id") && t != "verses"
end

# Persons: only those still linked.
persons = %w[occurrence_person_role type_person_role manuscript_person_role]
          .flat_map { |t| db.execute("SELECT DISTINCT person_id FROM #{t}").flatten }.uniq.join(",")
db.execute("DELETE FROM person WHERE id NOT IN (#{persons})")
tables.select { |t| t.start_with?("person_") }.each do |t|
  db.execute("DELETE FROM \"#{t}\" WHERE person_id NOT IN (#{persons})") if columns[t].include?("person_id")
end

# Bibliography: keep only the items still linked from a kept occurrence/type/manuscript/person.
bib = { "article" => "article_id", "book" => "book_id", "book_chapter" => "book_chapter_id",
        "blog" => "blog_id", "blog_post" => "blog_post_id", "bib_varia" => "bib_varia_id",
        "online_source" => "online_source_id", "phd" => "phd_id", "journal" => "journal_id",
        "journal_issue" => "journal_issue_id" }
bib.each do |table, key|
  linkers = tables.select { |t| t != table && columns[t].include?(key) && t =~ /\A(occurrence|type|manuscript|person)_/ }
  kept = linkers.flat_map { |t| db.execute("SELECT DISTINCT #{key} FROM \"#{t}\"").flatten }.uniq
  list = kept.empty? ? "NULL" : kept.map { |v| "'#{v}'" }.join(",")
  db.execute("DELETE FROM \"#{table}\" WHERE CAST(id AS TEXT) NOT IN (#{list})")
  tables.select { |t| t.start_with?("#{table}_") }.each do |t|
    db.execute("DELETE FROM \"#{t}\" WHERE CAST(#{key} AS TEXT) NOT IN (#{list})") if columns[t].include?(key)
  end
end
db.execute("DELETE FROM book_cluster") if tables.include?("book_cluster")
db.execute("DELETE FROM book_series") if tables.include?("book_series")

# identification: only rows naming a kept entity.
db.execute(<<~SQL)
  DELETE FROM identification WHERE NOT (
    (entity_type = 'manuscript' AND entity_id IN (#{mss})) OR
    (entity_type = 'type' AND entity_id IN (#{types})) OR
    (entity_type = 'person' AND entity_id IN (#{persons})))
SQL
db.execute("DELETE FROM acknowledgement WHERE id NOT IN (SELECT acknowledgement_id FROM occurrence_acknowledgement " \
           "UNION SELECT acknowledgement_id FROM type_acknowledgement UNION SELECT acknowledgement_id FROM " \
           "manuscript_acknowledgement UNION SELECT acknowledgement_id FROM person_acknowledgement)")
db.close
db = SQLite3::Database.new(work)
# ~200 tables at one page minimum each: a 512-byte page keeps the trim small.
db.execute("PRAGMA page_size=512")
db.execute("VACUUM")
db.execute("VACUUM INTO '#{out}'")
db.close
FileUtils.rm_f(work)
o = SQLite3::Database.new(out)
o.execute("PRAGMA journal_mode=WAL") # restore upstream's WAL header
o.close
```

Result sha256: `1720dc66a7475f26bfb61886da9c10ad2a035ab8448ca4ae3deb4e54b1212d5e`.
