# frozen_string_literal: true

# Code-keyed rows on the AED sign census. Signs the per-text stand-off
# files cannot write as a codepoint appear only as
# <w><note>Keine Entsprechung in Unicode für D31A-A1</note></w> — a
# Gardiner-coded spelling. Store::HieroPostingsBuilder tallies each
# coded member into a row keyed by +code+ beside the glyph-keyed rows,
# same grain (texts, signs, words, unclear). Exactly one of glyph/code
# keys a row: a code is never stuffed into +glyph+ (readers call
# +.ord+ on it). The table is drop-and-reproject derived data, so the
# next rebuild or aed sync fills the code rows.
Sequel.migration do
  up do
    alter_table(:hiero_postings) do
      set_column_allow_null :glyph
      add_column :code, String
    end
    alter_table(:hiero_postings) do
      add_constraint(:hiero_postings_one_key) do
        Sequel.|(Sequel.&({ glyph: nil }, Sequel.~(code: nil)),
                 Sequel.&(Sequel.~(glyph: nil), { code: nil }))
      end
      add_index :code, unique: true
    end
  end

  down do
    self[:hiero_postings].where(glyph: nil).delete
    alter_table(:hiero_postings) do
      drop_index :code
      drop_constraint :hiero_postings_one_key
      drop_column :code
      set_column_not_null :glyph
    end
  end
end
