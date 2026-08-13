# frozen_string_literal: true

# P76 U-6 (№R-6, survey E1): kaikki descendant nodes carry an `uncertain`
# raw_tag the parser used to drop — the only lexical-doubt carrier that
# never reached disk. Mirrors migration 010's borrowed flag exactly:
# parser-minted rows are true/false, NULL means "row predates the
# flag-aware reparse" (an honest absence the parser never mints; the next
# full rebuild backfills wholesale). Renders as the WOLD idiom —
# " (uncertain)" on etym/cognate lines, upstream word verbatim
# (conventions §12).
Sequel.migration do
  change do
    alter_table(:dictionary_reflexes) do
      add_column :uncertain, TrueClass, null: true
    end
  end
end
