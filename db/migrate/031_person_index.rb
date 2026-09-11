# frozen_string_literal: true

# P97-2 (№R-62 option b): the derived person index — CBDB's persons
# projected into catalog tables at sync time, the place_index mold
# (021/026): keyed (authority, person_id), wholesale per-authority
# derivation, name keys folded in Ruby. No backfill: empty means "not
# yet derived", and readers degrade honestly.
Sequel.migration do
  change do
    create_table(:person_index) do
      String :authority, null: false
      String :person_id, null: false
      String :name              # transcribed (pinyin) full name
      String :name_han          # the Han-script full name
      Integer :birth_year
      Integer :death_year
      Integer :index_year       # CBDB's own floruit anchor
      String :dynasty           # resolved transcription ("Song")
      String :dynasty_han       # 宋
      TrueClass :female, default: false
      primary_key %i[authority person_id]
    end

    create_table(:person_index_names) do
      String :authority, null: false
      String :person_id, null: false
      String :name_key, null: false
      index %i[authority name_key]
      index %i[authority person_id]
    end
  end
end
