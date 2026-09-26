# frozen_string_literal: true

# P104-1 (Q77; №R-70 ruled 2026-09-26): the date CLASS lane on the axes —
# what a row's envelope is a date OF. NULL (the default, and every row
# minted before this migration) = an artifact/typed date the source itself
# asserts about the object or witness: a findspot dating, a manuscript
# origDate, a print year. "composition" = author-era composition dating
# (№R-70 grade 2): the envelope brackets when the WORK was composed —
# diorisis creation_date, glaux start/end_date, croala's year ranges,
# disco's author birth/death-century bands — honestly labeled as its own
# class so a timeline consumer can always tell an object's date from an
# author's era. A labeling column, not a behavior switch: every bounds
# reader treats the interval identically.
Sequel.migration do
  change do
    alter_table(:document_axes) do
      add_column :date_class, String
    end
  end
end
