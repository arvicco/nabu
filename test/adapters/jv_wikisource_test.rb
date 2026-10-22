# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # jv-wikisource (P140): the dated 19th-century Javanese cone. Fixture
  # envelopes are real api.php captures (2026-10-21): the Epistle of Jude
  # from Gericke's 1848 New Testament (aksara Jawa — measured jav-Java) and
  # Kern's 1875 Wṛttasañcaya (the year from the Index file name; Old
  # Javanese, pinned to kaw); the Gericke–Roorda Woordenboek root
  # (measured Dutch — foreign_language) and a 1927 Kajawen issue (after the
  # band — after_cone) skip.
  class JvWikisourceTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("jv-wikisource")

    def conformance_adapter = Nabu::Adapters::JvWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "jv-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def envelope(pageid) = JSON.parse(File.read(File.join(FIXTURES, "pages", "#{pageid}.json")))

    def test_discovery_census
      assert_equal %w[urn:nabu:jv-wikisource:21545 urn:nabu:jv-wikisource:676],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
      notes = conformance_adapter.discovery_skips(FIXTURES).notes
      assert(notes.any? { |note| note.start_with?("1 page(s) whose print year falls after LAST_PRINT_YEAR") })
      assert(notes.any? { |note| note.start_with?("1 page(s) MEASURED as foreign-language") })
    end

    def test_the_script_is_measured
      jude = doc(21_545)
      assert_equal "jav-Java", jude.language
      assert_equal "Java", jude.metadata["script"]
      assert jude.passages.first.text.start_with?("꧋ꦱꦼꦂꦫꦠ꧀ꦲꦶꦧꦼꦂꦫꦶꦧꦼꦂ")
      assert_equal "Year: 1848 (Sakathahipun serat Prajangjéyan Énggal.pdf)", jude.metadata["source_date"]
    end

    def test_the_old_javanese_treatise_is_pinned_to_kaw
      kakawin = doc(676)
      assert_equal "kaw", kakawin.language, "INDEX_LECTS: Mpu Tanakung's 14th-c. treatise, romanized"
      assert_equal "Year: 1875 (Wretansacaya (Kern 1875).pdf)", kakawin.metadata["source_date"],
                   "the Index states no year; its file name does"
    end

    def test_the_dutch_apparatus_is_measured_out
      adapter = conformance_adapter
      woordenboek = envelope(383)
      assert_equal :foreign_language, adapter.page_class(woordenboek)
      assert_operator adapter.foreign_share(adapter.send(:passages_for, woordenboek).map(&:text).join(" ")), :>, 0.15
      assert_equal :after_cone, adapter.page_class(envelope(476))
    end

    def test_an_uncensused_index_language_quarantines
      adapter = conformance_adapter
      foreign = envelope(21_545)
      foreign["indexes"].first["fields"]["Language"] = "ms"
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "pages"))
        File.write(File.join(dir, "pages", "21545.json"), JSON.generate(foreign))
        ref = adapter.discover(dir).first
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_match(/not censused/, error.message)
      end
    end

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(slug: "jv-wikisource", name: "Javanese Wikisource",
                                          adapter_class: "Nabu::Adapters::JvWikisource", license_class: "attribution")
      load = -> { Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true) }
      assert_equal 2, load.call.added
      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      load.call
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision)
    end
  end
end
