# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Hexapla — the Göttingen Hexapla Database (NAWG) in
  # Text-Fabric (R. Taylor, github.com/rdtaylorjr/hexapla tf/0.1) over the
  # text-fabric family: document = column × book (the LXX edition, Field's
  # Ο′, the MT, the Secunda, Aquila, Symmachus, Origen's Septuagint, Quinta,
  # Sexta, Theodotion, "the others", Field's Latin), passage = verse in the
  # database's Greek numbering. Fixtures are gap-anchored tf/0.1 slices —
  # Psalm 45 in all thirteen columns and 2 Samuel 0 + 9 — see
  # test/fixtures/hexapla/README.md.
  class HexaplaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("hexapla")
    URN = "urn:nabu:hexapla:"

    def conformance_adapter
      Nabu::Adapters::Hexapla.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "hexapla"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_hexapla_wired_on_its_first_sync_evidence
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["hexapla"]
      refute_nil entry, "hexapla must be registered in config/sources.yml"
      assert entry.wired, "wired on the first-sync evidence (landed exactly on census, 2026-11-02)"
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_is_nc_with_the_database_grant
      manifest = Nabu::Adapters::Hexapla.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "CC BY-NC-SA 4.0"
      assert_includes manifest.license, "Die Editio critica maior des griechischen Psalters"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census ---------------------------------------------------------------

    def test_the_whole_otype_census
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.1"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal 182_462, counts["word"]
      assert_equal 13, counts["text"], "thirteen database columns"
      assert_equal 21, counts["book"]
      assert_equal 18_048, counts["verse"]
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_column_book
      ids = conformance_adapter.discover(FIXTURES).map(&:id)
      assert_equal 18, ids.size, "the 20 column books of the slices less the two Notes books"
      assert_includes ids, "#{URN}lxx_edition:2_samuel"
      assert_includes ids, "#{URN}secunda:psalms"
      assert_includes ids, "#{URN}field_latin:psalms"
      refute(ids.any? { |id| id.include?(":notes:") })
    end

    def test_the_notes_column_is_skipped_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule, "Notes on 2 Samuel and on the Psalms"
      assert(skips.notes.all? { |note| note.include?("notes") })
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_an_unknown_column_is_a_parse_error_never_a_guess
      assert_raises(Nabu::ParseError) { Nabu::Adapters::Hexapla.column_info("septima") }
    end

    # -- documents and passages ----------------------------------------------

    def test_each_column_carries_its_own_language
      assert_equal "grc", parse_urn("#{URN}aquila:psalms").language
      assert_equal "hbo", parse_urn("#{URN}mt:psalms").language
      assert_equal "hbo-Grek", parse_urn("#{URN}secunda:psalms").language,
                   "Hebrew in Greek letters (upstream languageISO heb-Grek)"
      assert_equal "lat", parse_urn("#{URN}field_latin:psalms").language
      aquila = parse_urn("#{URN}aquila:psalms")
      assert_equal "Hexapla: Aquila — Psalms", aquila.title
      assert_equal "aquila", aquila.metadata["column"]
      assert_equal "Psalmi", aquila.metadata["book"], "the BHSA Latin book name, verbatim"
    end

    def test_passages_are_verses_in_greek_numbering
      lxx = parse_urn("#{URN}lxx_edition:psalms")
      assert_equal "#{URN}lxx_edition:psalms:45.0", lxx.passages.first.urn, "the psalm title is verse 0"
      assert_equal "ME’", lxx.passages.first.text
      inscriptio = parse_urn("#{URN}lxx_edition:2_samuel").passages.first
      assert_equal "#{URN}lxx_edition:2_samuel:0.0", inscriptio.urn, "the book's inscriptio is chapter 0, verse 0"
      assert_equal "ΒΑΣΙΛΕΙΩΝ Β´", inscriptio.text
    end

    def test_verse_text_is_the_corpus_own_rendering
      symmachus = parse_urn("#{URN}symmachus:psalms").find { |p| p.urn.end_with?(":45.1") }
      assert_equal "ἐπινίκιος τῶν υἱῶν κορὲ ὑπὲρ τῶν αἰωνίων ᾠδή", symmachus.text
      mt = parse_urn("#{URN}mt:psalms").find { |p| p.urn.end_with?(":45.1") }
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.1"))
      raw = mt.annotations["tokens"].map { |t| "#{dataset.feature('text').fetch(t['n'])}#{t['trailer']}" }.join.strip
      assert_equal raw, mt.text, "hbo rides byte-verbatim (the NFC exemption)"
      refute mt.text.unicode_normalized?(:nfc), "the database's Masoretic mark order is not NFC — kept as shipped"
    end

    def test_a_verse_of_bare_placeholders_is_omitted_and_named
      field = parse_urn("#{URN}field:psalms")
      refute(field.any? { |p| p.urn.end_with?(":45.8") })
      assert_equal ["45.8"], field.metadata["omitted_verses"]
      assert_equal %w[45.8 45.12], parse_urn("#{URN}field_latin:psalms").metadata["omitted_verses"]
    end

    def test_tokens_carry_the_reading_layer
      aquila = parse_urn("#{URN}aquila:psalms").find { |p| p.urn.end_with?(":45.1") }
      tokens = aquila.annotations["tokens"]
      assert(tokens.all? { |t| t.key?("n") && t.key?("rank") && t.key?("stichos") })
      alternative = tokens.find { |t| t["reading"] }
      refute_nil alternative, "Aquila Ps 45:1 holds a competing reading at one position"
      assert_operator alternative["reading"], :>, 0
      assert(tokens.any? { |t| t["siglum"] }, "the attesting witnesses ride the token")
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "hexapla", name: "Göttingen Hexapla Database",
        adapter_class: "Nabu::Adapters::Hexapla", license_class: "nc"
      )
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 18, first.added
      assert_equal 0, first.errored
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end
  end
end
