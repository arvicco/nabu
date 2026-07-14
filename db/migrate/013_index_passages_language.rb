# frozen_string_literal: true

# P18-4 follow-up, part 2: migration 012 indexed the reflex and document
# language lookups, but the card's passage count joins passages BY
# LANGUAGE over 4.27M unindexed rows — the remaining ~9 s of the
# owner-measured 11.6 s card. (Separate migration because 012 was
# already applied to the live catalog when this scan surfaced; applied
# migrations are never edited.)
Sequel.migration do
  change do
    alter_table(:passages) do
      add_index :language
    end
  end
end
