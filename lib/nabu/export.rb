# frozen_string_literal: true

require_relative "export/types"
require_relative "export/axes"
require_relative "export/writer"
require_relative "export/documents"
require_relative "export/links"
require_relative "export/lemmas"
require_relative "export/align_hub"
require_relative "export/align_pairs"
require_relative "export/collation_readings"
require_relative "export/passage_sample"

module Nabu
  # The research exporter (P121-1, architecture §18): `nabu export <table>`
  # streams one DOCUMENTED query out of the library as CSV (default) or
  # JSONL, and writes `<table>.manifest.yml` beside the data file — the
  # generation time, the filters applied, the row total, and every source
  # drawn on with its license class. Default exports include everything
  # (local research use); `--license-class open,attribution` narrows a set
  # to what may be redistributed, and the manifest always names what was
  # drawn either way.
  #
  # == The table contract
  #
  # A table is a plain class registered in TABLES below (explicit — one
  # name, one line; no autoloading). It declares NAME and SUMMARY, and its
  # instances answer:
  #
  #   columns   [Column] — name + one-line description each (the manifest
  #             documents every column it ships)
  #   filters   { "name" => value } — the table's own filters, echoed into
  #             the manifest (the frame appends license_class)
  #   each_row(license_classes: nil) { |Row| } — streams rows in a stable
  #             order, paging through Sequel datasets; never materializes
  #             the table. +license_classes+ is a push-down hint: the frame
  #             re-checks every row's draws regardless.
  #   notes     { "name" => value } — table-specific manifest facts, read
  #             after the stream ends
  #
  # Every table is READ-ONLY on every database it touches.
  #
  # == Outside the derivation core
  #
  # Producer-only code (it reads the catalog and the links journal and
  # writes files under exports/) — excluded from the shared derivation
  # digest like data_build, so an exporter change never dirties a source
  # stamp; derivation_fingerprint_test guards the inward direction.
  module Export
    # The table registry: a further table (the lemma rollup) is one file
    # under export/ plus one line here and one CLI command.
    TABLES = {
      Documents::NAME => Documents,
      Links::NAME => Links,
      Lemmas::NAME => Lemmas,
      AlignPairs::NAME => AlignPairs,
      CollationReadings::NAME => CollationReadings,
      PassageSample::NAME => PassageSample
    }.freeze

    module_function

    def names = TABLES.keys

    def table(name)
      TABLES.fetch(name.to_s) do
        raise Error, "unknown export table #{name.to_s.inspect} (known: #{names.join(', ')})"
      end
    end
  end
end
