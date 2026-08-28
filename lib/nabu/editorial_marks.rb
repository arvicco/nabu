# frozen_string_literal: true

require "yaml"

module Nabu
  # The library's own editorial/house marks (config/editorial_marks.yml):
  # what ⟦ ⌈ ⸀ ⿰ … MEAN in a Nabu passage. Read by `nabu char` (the :marks
  # lane, Nabu::CharDispatch) so a single mark answers with its convention
  # instead of a Han-shelf shrug — the one card no external Unicode tool can
  # supply, because the meaning is Nabu's own, not a universal character fact.
  #
  # These are project definition (config/, git-shared), NOT the universal
  # curated overlay (nabu-data) — the brackets are Nabu's display conventions,
  # authored here and shipped identically to every install (P85, №R-47).
  module EditorialMarks
    PATH = File.join(Nabu::Config::PROJECT_ROOT, "config", "editorial_marks.yml")

    Mark = Data.define(:glyph, :codepoint, :name, :meaning, :display_rule, :seen_in)

    # The whole table, memoized per path: glyph => raw row hash.
    def self.table(path: PATH)
      (@table ||= {})[path] ||= YAML.safe_load_file(path)
    end

    # The codepoints this table documents — the char-dispatch :marks set must
    # match these exactly (a test pins the agreement).
    def self.codepoints(path: PATH)
      table(path: path).values.to_set { |row| Integer(row.fetch("codepoint").delete_prefix("U+"), 16) }
    end

    # One mark's card, or nil when the glyph is not a documented house mark.
    def self.lookup(glyph, path: PATH)
      row = table(path: path)[glyph] or return nil
      Mark.new(glyph: glyph, codepoint: row["codepoint"], name: row["name"],
               meaning: row["meaning"].to_s.strip, display_rule: row["display"], seen_in: row["seen_in"])
    end
  end
end
