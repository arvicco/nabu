# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "yaml"
require "support/adapter_conformance"

module Adapters
  # elizabeth-bible — the 1757 Elizabeth Bible in Church Slavonic, from
  # getBible's whole-translation JSON (csielizabeth: the rusbible.ru
  # electronic edition, modernized civil-script spelling, Synodal
  # versification). One document per book (urn …:<OSIS code downcased>),
  # passages <chapter>.<verse>. Fixture: the real envelope trimmed at book
  # boundaries (Genesis ch. 1, Prayer of Manasses, Jonah, 2 John).
  class ElizabethBibleTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("elizabeth-bible")
    URN = "urn:nabu:elizabeth-bible"
    URL = "https://api.getbible.net/v2/csielizabeth.json"

    def conformance_adapter = Nabu::Adapters::ElizabethBible.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "elizabeth-bible"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(code) = documents.find { |d| d.urn == "#{URN}:#{code}" } || flunk("#{code} missing")

    # --- discover ---------------------------------------------------------------

    def test_discovers_one_document_per_book_in_upstream_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %W[#{URN}:gen #{URN}:prman #{URN}:jonah #{URN}:2john], refs.map(&:id)
      assert_equal(%w[Gen PrMan Jonah 2John], refs.map { |r| r.metadata["book"] })
      assert_equal([1, 79, 32, 63], refs.map { |r| r.metadata["book_nr"] })
    end

    def test_discover_of_an_unfetched_workdir_yields_nothing
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # The per-book and per-chapter endpoint shapes are rejected delivery
    # grains — pinned as real specimens, counted by rule, never parsed.
    def test_rejected_getbible_grains_are_skipped_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 2, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
    end

    def test_a_book_number_outside_the_code_table_is_censused_unrecognized
      Dir.mktmpdir do |dir|
        data = JSON.parse(File.read(File.join(FIXTURES, "csielizabeth.json")))
        data["books"] << data["books"].last.merge("nr" => 99, "name" => "Unknown")
        File.write(File.join(dir, "csielizabeth.json"), JSON.generate(data))
        assert_equal 4, conformance_adapter.discover(dir).count, "the unknown book is not minted"
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_match(/99/, skips.notes.first)
      end
    end

    # --- parse ------------------------------------------------------------------

    def test_genesis_opens_with_the_known_verse_in_modernized_spelling
      gen = doc("gen")
      assert_equal "chu", gen.language
      assert_equal "Genesis", gen.title
      assert_equal "#{URN}:gen:1.1", gen.passages.first.urn
      assert_equal "В начале сотвори Бог небо и землю.", gen.passages.first.text
    end

    def test_verse_counts_per_fixture_book
      assert_equal({ "gen" => 31, "prman" => 11, "jonah" => 48, "2john" => 13 },
                   documents.to_h { |d| [d.urn.delete_prefix("#{URN}:"), d.size] })
    end

    # Synodal versification follows the Greek where the MT splits: the fish
    # verse is Jonah 2.1 (MT 2.1 is the prayer's opening at English 1.17).
    def test_jonah_cites_the_greek_scheme_fish_verse_at_two_one
      jonah = doc("jonah")
      per_chapter = (1..4).map { |c| jonah.count { |p| p.urn.start_with?("#{URN}:jonah:#{c}.") } }
      assert_equal [16, 11, 10, 11], per_chapter
      fish = jonah.find { |p| p.urn == "#{URN}:jonah:2.1" }
      assert_equal "И повеле Господь киту великому пожрети Иону. И бе Иона во чреве китове три дни и три нощи.",
                   fish.text
    end

    def test_trailing_and_doubled_spaces_collapse
      last = doc("gen").passages.last
      assert_equal "#{URN}:gen:1.31", last.urn
      refute_match(/\s\z|\s{2}/, last.text, "upstream's trailing space is whitespace, not text")
    end

    def test_rendering_versification_and_edition_ride_metadata
      meta = doc("prman").metadata
      assert_equal "PrMan", meta["book"]
      assert_equal "ot", meta["testament"]
      assert_equal "nt", doc("2john").metadata["testament"]
      assert_equal "modernized civil-script spelling", meta["rendering"]
      assert_equal "Cyrl", meta["script"]
      assert_equal "Synodal", meta["versification"]
      assert_includes meta["base_edition"], "features modernized spelling"
      assert_equal({ "not_before" => 1757, "not_after" => 1757, "class" => "edition" },
                   meta["date"].slice("not_before", "not_after", "class"))
    end

    def test_the_edition_year_rides_the_structured_lane
      assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["elizabeth-bible"]
      refute_includes Nabu::Store::TimelineBuilder::MetadataDates::COMPOSITION, "elizabeth-bible",
                      "an edition year, never a composition era"
    end

    def test_a_malformed_file_quarantines
      Dir.mktmpdir do |dir|
        FileUtils.cp(File.join(FIXTURES, "csielizabeth.json"), dir)
        ref = conformance_adapter.discover(dir).first
        File.write(File.join(dir, "csielizabeth.json"), "{ not json")
        assert_raises(Nabu::ParseError) { Nabu::Adapters::ElizabethBible.new.parse(ref) }
      end
    end

    # --- postures + registry --------------------------------------------------------

    def test_manifest_records_the_verbatim_distribution_license_and_open_class
      manifest = Nabu::Adapters::ElizabethBible.manifest
      assert_equal "open", manifest.license_class
      assert_includes manifest.license, "distribution_license: \"Public Domain\""
      assert_equal URL, manifest.upstream_url
      assert_equal "getbible-json", manifest.parser_family
    end

    def test_scripture_is_the_whole_source_kind
      kind_map = YAML.safe_load_file(File.expand_path("../../config/kind_map.yml", __dir__))
      assert_equal "scripture", kind_map.dig("sources", "elizabeth-bible", "source_kind")
    end

    # The Elizabeth Bible is the text the registry's chu:ncs node names as
    # fixing the Synodal standard — a whole-source override, tier certain.
    def test_chu_resolves_to_new_church_slavonic_for_this_source
      overrides = YAML.safe_load_file(File.expand_path("../../config/lect_overrides.yml", __dir__))
      assert_equal({ "lect" => "chu:ncs", "tier" => "certain" },
                   overrides.dig("sources", "elizabeth-bible", "chu"))
    end

    # No hub urn dangles: every elizabeth-bible document the alignment
    # registry names is one the adapter's book table mints.
    def test_every_alignment_urn_is_a_minted_book
      registry = Nabu::AlignmentRegistry.load(File.expand_path("../../config/alignments.yml", __dir__))
      urns = registry.works.flat_map { |work| work.witnesses.flat_map(&:document_urns) }
      urns = urns.select { |urn| urn.start_with?("#{URN}:") }
      minted = Nabu::Adapters::ElizabethBible::BOOKS.values.map { |code| "#{URN}:#{code.downcase}" }
      assert_equal 65, urns.size, "27 NT + 37 OT + the psalter"
      assert_empty urns - minted
    end

    def test_registry_row_resolves_the_adapter_on_a_manual_policy
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["elizabeth-bible"]
      refute_nil entry, "elizabeth-bible must be registered in config/sources.yml"
      assert_equal Nabu::Adapters::ElizabethBible, entry.adapter_class
      assert_equal "manual", entry.sync_policy
    end

    # --- idempotency ------------------------------------------------------------------

    def test_load_twice_is_idempotent
      db = store_test_db
      source = Nabu::Store::Source.create(slug: "elizabeth-bible", name: "Elizabeth Bible",
                                          adapter_class: "Nabu::Adapters::ElizabethBible", license_class: "open")
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, first.added
      passages = db[:passages].count
      assert_equal 103, passages
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: FIXTURES)
      assert_equal 4, second.skipped
      assert_equal passages, db[:passages].count
    ensure
      db&.disconnect
    end

    # --- fetch (WebMock only, no network) ---------------------------------------------

    def test_fetch_downloads_the_translation_file_and_a_304_keeps_the_pin
      body = File.binread(File.join(FIXTURES, "csielizabeth.json"))
      stub_request(:get, URL).to_return(status: 200, body: body,
                                        headers: { "Last-Modified" => "Sat, 12 Sep 2026 17:52:37 GMT" })
      Dir.mktmpdir do |workdir|
        adapter = conformance_adapter
        report = adapter.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_equal 4, adapter.discover(workdir).count, "the fetched file is discoverable in place"

        stub_request(:get, URL).to_return(status: 304)
        assert_equal report.sha, adapter.fetch(workdir).sha
      end
    end

    def test_fetch_wraps_http_failure_in_fetch_error
      stub_request(:get, URL).to_return(status: 500)
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) } }
    end

    def test_the_remote_probe_heads_the_translation_file
      target = Nabu::Adapters::ElizabethBible.http_probe_targets.first
      assert_equal URL, target.zip_url
      assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
    end
  end
end
