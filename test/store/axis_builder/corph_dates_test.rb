# frozen_string_literal: true

require "test_helper"

module Store
  # Nabu::Store::AxisBuilder::CorphDates (P25-0): TEXT.Date → date-axis rows,
  # run against the REAL fixture dump. The honest parse ladder (censused on
  # the full dump 2026-07-17: 73/78 texts dated, 5 honest residues):
  #   1. the ChronHib phrase "[Dd]ate range(s) … is/are used …", preferring a
  #      "(for text)"-tagged range, else the envelope of every range named;
  #   2. the "Text: N-M" / "Text: N X M" text-date fallback.
  # Anything else (the Annals of Ulster's annalistic spread, prose-only MS
  # dates) is counted undated, never guessed.
  class CorphDatesTest < Minitest::Test
    include StoreTestDB

    FIXTURES_ROOT = File.expand_path("../../fixtures", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "corph", name: "CorPH", adapter_class: "C", license_class: "attribution"
      )
    end

    def seed(urn, language: "sga")
      Nabu::Store::Document.create(
        source_id: @source.id, urn: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def build!
      Nabu::Store::AxisBuilder::CorphDates.build(catalog: @db, canonical_dir: FIXTURES_ROOT)
    end

    def test_the_chronhib_range_phrase_becomes_an_honest_range_row
      baile = seed("urn:nabu:corph:0003")
      outcome = build!
      assert_equal 1, outcome[:documents]
      row = @db[:document_axes].where(document_id: baile.id).first
      assert_equal 690, row[:not_before]
      assert_equal 720, row[:not_after]
      assert_equal "range", row[:precision]
      assert_includes row[:date_raw], "Date range 690-720 is used in ChronHib",
                      "date_raw keeps the upstream prose verbatim"
      assert_equal "corph", row[:axis_source]
    end

    def test_the_text_date_fallback_parses_ms_vs_text_prose
      einsiedeln = seed("urn:nabu:corph:0077")
      build!
      row = @db[:document_axes].where(document_id: einsiedeln.id).first
      assert_equal 689, row[:not_before], "\"MS: 867-900, Text 689-719.\" dates the TEXT, not the MS"
      assert_equal 719, row[:not_after]
      assert_equal "range", row[:precision]
    end

    def test_documents_without_a_parseable_date_are_counted_never_guessed
      # Doctor the real 0008 Date down to its unparseable MS half — the
      # Annals-of-Ulster shape (prose only, no ChronHib range).
      seed("urn:nabu:corph:0008")
      dir = doctored_root("MS: 9th c. Date range 825-851 is used in ChronHib.", "MS: 9th c.")
      outcome = Nabu::Store::AxisBuilder::CorphDates.build(catalog: @db, canonical_dir: dir)
      assert_equal 0, outcome[:documents]
      assert_equal 1, outcome[:undated]
      assert_equal 0, @db[:document_axes].count
    ensure
      FileUtils.remove_entry(dir) if dir
    end

    def test_documents_we_do_not_hold_contribute_nothing
      outcome = build!
      assert_equal 0, outcome[:documents]
      assert_equal 0, outcome[:undated], "undated counts only documents the catalog holds"
      assert_equal 0, @db[:document_axes].count
    end

    def test_a_missing_dump_reads_as_empty
      Dir.mktmpdir do |dir|
        outcome = Nabu::Store::AxisBuilder::CorphDates.build(catalog: @db, canonical_dir: dir)
        assert_equal({ documents: 0, undated: 0 }, outcome)
      end
    end

    # -- the range ladder on real upstream prose ------------------------------

    def test_extract_range_prefers_the_for_text_tagged_range
      # Milan Glosses (TEXT 0006), Date verbatim from the full dump.
      range = Nabu::Store::AxisBuilder::CorphDates.extract_range(
        "Text 8th c. MS: first quarter of 9th c. Date ranges 785-825 (for text), " \
        "800-825 (for MS) are used in ChronHib."
      )
      assert_equal [785, 825], range
    end

    def test_extract_range_envelopes_untagged_alternatives
      range = Nabu::Store::AxisBuilder::CorphDates.extract_range(
        "MS: 885-915? Date range for text 800-900 is used in ChronHib."
      )
      assert_equal [800, 900], range, "the capture starts AFTER \"Date range\" — the MS range never leaks in"
    end

    def test_extract_range_reads_the_x_style_text_date
      # Vita Columbae (TEXT 0002), Date verbatim from the full dump.
      range = Nabu::Store::AxisBuilder::CorphDates.extract_range("MS: 692 X 713; Text: 688 X 692")
      assert_equal [688, 692], range
    end

    def test_extract_range_returns_nil_for_annalistic_prose
      # Annals of Ulster (TEXT 0001), Date verbatim from the full dump.
      assert_nil Nabu::Store::AxisBuilder::CorphDates.extract_range(
        "Trinity MS: end of 15th c.; Rawlin. MS: beginning of 16th c."
      )
    end

    # The frozen-minting drift pin (the damaskini precedent): the extractor's
    # urn mint must equal the adapter's discover mint over the shared fixture.
    def test_extractor_urn_mint_matches_the_adapter
      adapter_urns = Nabu::Adapters::Corph.new.discover(File.join(FIXTURES_ROOT, "corph")).map(&:id).sort
      dump = File.join(FIXTURES_ROOT, "corph", "chronhibdev_2020.sql")
      extractor_urns = Nabu::Adapters::CorphSqlParser.new(dump).each_row("TEXT").map do |row|
        Nabu::Store::AxisBuilder::CorphDates.document_urn(row)
      end.sort
      assert_equal adapter_urns, extractor_urns
    end

    private

    # A canonical root whose corph dump is the real fixture with one
    # surgical replacement.
    def doctored_root(from, to)
      dir = Dir.mktmpdir
      FileUtils.mkdir_p(File.join(dir, "corph"))
      dump = File.read(File.join(FIXTURES_ROOT, "corph", "chronhibdev_2020.sql"))
      raise "anchor missing" unless dump.include?(from)

      File.write(File.join(dir, "corph", "chronhibdev_2020.sql"), dump.sub(from, to))
      dir
    end
  end
end
