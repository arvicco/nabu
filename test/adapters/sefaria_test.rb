# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Sefaria adapter tests (P30-3): the Targum shelf from Sefaria's restructured
# export. Discovery is GLOB-DRIVEN over the fetched version files (each file
# is self-describing: title/versionTitle/license ride beside the text), so
# the attic rediscovers without the index; the index (books.json) only
# drives fetch selection. THE LICENSE GATE is the heart of the adapter:
# ingest NAMED versions only, license class per version, merged files and
# unlicensed versions never become refs.
class SefariaTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("sefaria")
  TARGUM = File.join(FIXTURES, "json/Tanakh/Targum")
  OBADIAH_FIXTURE = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Obadiah/" \
                                      "Hebrew/Mikraot Gedolot.json")

  def conformance_adapter
    Nabu::Adapters::Sefaria.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "sefaria"
  end

  def refs
    conformance_adapter.discover(FIXTURES).to_a
  end

  def ref(urn)
    refs.find { |r| r.id == urn } || flunk("expected discover to yield #{urn}")
  end

  # --- identity ---------------------------------------------------------------

  def test_discover_mints_title_slash_version_urns_sorted
    urns = refs.map(&:id)
    assert_equal urns.sort, urns
    assert_equal %w[
      urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot
      urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-to-the-yemenite-taj
      urn:nabu:sefaria:onkelos-numbers:sifsei-chachomim-chumash-metsudah-publications-2009
      urn:nabu:sefaria:targum-jerusalem:targum-jerusalem-on-torah
      urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot
      urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation
      urn:nabu:sefaria:targum-neofiti:sefaria-community-translation
      urn:nabu:sefaria:targum-sheni-on-esther:sefaria-community-translation
    ].sort, urns, "8 licensed named versions; merged, unlicensed and excluded titles never mint"
  end

  # --- THE LICENSE GATE (pinned per the P30-3 spec) ---------------------------

  def test_merged_files_are_never_ingested
    merged = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Jonah/Hebrew/merged.json")
    assert File.file?(merged), "the fixture must actually carry a real merged file"
    refute_nil JSON.parse(File.read(merged))["versions"], "a merged file lists its sources"
    assert_nil JSON.parse(File.read(merged))["license"], "a merged file carries NO license field"
    assert_empty(refs.select { |r| r.path == merged },
                 "merged.json carries no per-version license grant — NEVER a ref")
  end

  def test_a_named_version_without_a_license_field_is_skipped
    judges = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Judges/English/" \
                               "Sefaria Community Translation.json")
    assert File.file?(judges)
    assert_nil JSON.parse(File.read(judges))["license"],
               "the fixture pins the real upstream oddity: a named version with no license field"
    assert_empty(refs.select { |r| r.path == judges }, "no machine-readable grant → no ref")
  end

  def test_a_license_of_unknown_is_skipped
    lenihan = File.join(TARGUM, "Targum Jonathan/Prophets/Targum Jonathan on Obadiah/English/" \
                                "Targum Obadiah, translated by Thomas Lenihan.json")
    assert_equal "unknown", JSON.parse(File.read(lenihan))["license"]
    assert_empty(refs.select { |r| r.path == lenihan }, '"unknown" is not a grant → no ref')
  end

  def test_public_domain_and_cc0_inherit_the_open_source_class
    [ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"),
     ref("urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation")].each do |r|
      adapter = conformance_adapter
      assert_nil adapter.parse(r).license_override,
                 "#{r.id}: PD/CC0 match the source class — no override minted"
    end
  end

  def test_cc_by_sa_rides_an_attribution_override
    r = ref("urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-to-the-yemenite-taj")
    assert_equal "attribution", conformance_adapter.parse(r).license_override
  end

  def test_cc_by_nc_rides_an_nc_override
    r = ref("urn:nabu:sefaria:onkelos-numbers:sifsei-chachomim-chumash-metsudah-publications-2009")
    document = conformance_adapter.parse(r)
    assert_equal "nc", document.license_override, "the P10-4 per-document mechanics — MCP-excluded downstream"
    assert_equal "CC-BY-NC", document.metadata["license"], "the verbatim upstream grant rides the metadata"
  end

  def test_an_unmapped_license_string_stops_discovery_loudly
    with_version({ "license" => "Sefaria Community License 1.0" }) do |dir|
      error = assert_raises(Nabu::FetchError) { conformance_adapter.discover(dir).to_a }
      assert_match(/Sefaria Community License 1.0/, error.message)
      assert_match(/owner decision/, error.message, "mislabeled documents are worse than an aborted run")
    end
  end

  def test_tafsir_rasag_is_excluded_by_rule
    tafsir = File.join(TARGUM, "Tafsir Rasag/Tafsir Rasag/English/Sefaria Community Translation.json")
    assert File.file?(tafsir)
    assert_equal "CC0", JSON.parse(File.read(tafsir))["license"],
                 "the exclusion is NOT license-driven — Tafsir Rasag is Saadia's Judeo-Arabic " \
                 "tafsir, not an Aramaic targum (the blanket he→arc ruling would mislabel it)"
    assert_empty(refs.select { |r| r.path == tafsir })
  end

  # --- languages --------------------------------------------------------------

  def test_hebrew_column_maps_to_aramaic_and_english_to_eng
    assert_equal "arc", ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot")
      .metadata.fetch("language"),
                 "Sefaria's `Hebrew` axis on the Targum shelf IS the Aramaic column " \
                 "(upstream actualLanguage says `he` — the shelf ruling overrides)"
    assert_equal "eng", ref("urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation")
      .metadata.fetch("language")
  end

  def test_an_unknown_upstream_language_stops_discovery_loudly
    with_version({ "language" => "fr" }) do |dir|
      assert_raises(Nabu::FetchError) { conformance_adapter.discover(dir).to_a }
    end
  end

  # --- parse round-trip -------------------------------------------------------

  def test_parse_carries_shelf_metadata_and_facets
    document = conformance_adapter.parse(ref("urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"))
    assert_equal "Targum Jonathan on Obadiah", document.metadata["title"]
    assert_equal "Mikraot Gedolot", document.metadata["version_title"]
    assert_equal "Public Domain", document.metadata["license"]
    assert_equal ["Tanakh", "Targum", "Targum Jonathan", "Prophets"], document.metadata["categories"]
    assert_equal({ "value" => "targum-jonathan", "raw" => "Targum Jonathan" },
                 document.metadata.dig("facets", "subshelf"))
    assert_equal({ "value" => "prophets", "raw" => "Prophets" },
                 document.metadata.dig("facets", "division"))
    assert_equal "arc", document.language
    assert_equal 21, document.size
  end

  def test_the_ot_hub_witness_documents_parse_to_cts_verse_tails
    document = conformance_adapter.parse(ref("urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot"))
    assert_equal "urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot:1.1", document.first.urn,
                 "passage urn = doc urn + chapter.verse tail — what the registry's cts-verse " \
                 "extractor folds into 'RUT 1.1'"
    assert_equal 85, document.size
  end

  def test_expected_passage_censuses
    counts = refs.to_h { |r| [r.id, conformance_adapter.parse(r).size] }
    assert_equal({
                   "urn:nabu:sefaria:aramaic-targum-to-ruth:mikraot-gedolot" => 85,
                   "urn:nabu:sefaria:onkelos-genesis:targum-onkelos-vocalized-according-to-the-yemenite-taj" => 31,
                   "urn:nabu:sefaria:onkelos-numbers:sifsei-chachomim-chumash-metsudah-publications-2009" => 54,
                   "urn:nabu:sefaria:targum-jerusalem:targum-jerusalem-on-torah" => 39,
                   "urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot" => 21,
                   "urn:nabu:sefaria:targum-jonathan-on-jonah:sefaria-community-translation" => 48,
                   "urn:nabu:sefaria:targum-neofiti:sefaria-community-translation" => 8,
                   "urn:nabu:sefaria:targum-sheni-on-esther:sefaria-community-translation" => 7
                 }, counts)
  end

  # --- discovery census (P11-7) ----------------------------------------------

  def test_discovery_skips_census_the_gate
    skips = conformance_adapter.discovery_skips(FIXTURES)
    assert_equal 4, skips.skipped_by_rule,
                 "1 merged + 1 absent-license + 1 unknown-license + 1 excluded title"
    assert_predicate skips, :clean?
  end

  def test_a_json_tree_with_an_unreadable_file_is_censused_as_unrecognized
    with_version(nil, body: "{not json") do |dir|
      skips = conformance_adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      refute_empty skips.notes
      refute_predicate skips, :clean?
      assert_empty conformance_adapter.discover(dir).to_a
    end
  end

  # --- fetch ------------------------------------------------------------------

  def test_fetch_selects_named_targum_shelf_entries_only
    select = Nabu::Adapters::Sefaria.method(:shelf_entry?)
    targum = { "title" => "Onkelos Genesis", "versionTitle" => "Onkelos Genesis",
               "categories" => %w[Tanakh Targum Onkelos Torah], "json_url" => "https://b/x.json" }
    assert select.call(targum)
    refute select.call(targum.merge("versionTitle" => "merged")), "merged files are never fetched"
    refute select.call(targum.merge("title" => "Tafsir Rasag")), "the Judeo-Arabic tafsir stays out"
    refute select.call(targum.merge("categories" => %w[Tanakh Torah])), "only the Targum shelf this phase"
    refute select.call(targum.merge("json_url" => nil)), "an entry without a json file cannot be fetched"
  end

  def test_fetch_lands_index_and_shelf_through_sefaria_fetch
    Dir.mktmpdir do |workdir|
      index = JSON.generate(
        "base_url" => "https://bucket.example.org/sefaria-export",
        "books" => [
          { "title" => "Targum Jonathan on Obadiah", "language" => "Hebrew",
            "versionTitle" => "Mikraot Gedolot", "categories" => ["Tanakh", "Targum", "Targum Jonathan", "Prophets"],
            "json_url" => "https://bucket.example.org/sefaria-export/json/T/Hebrew/Mikraot Gedolot.json" },
          { "title" => "Targum Jonathan on Obadiah", "language" => "Hebrew", "versionTitle" => "merged",
            "categories" => ["Tanakh", "Targum", "Targum Jonathan", "Prophets"],
            "json_url" => "https://bucket.example.org/sefaria-export/json/T/Hebrew/merged.json" }
        ]
      )
      stub_request(:get, "https://index.example.org/books.json")
        .to_return(status: 200, body: index, headers: { "Last-Modified" => "Thu, 02 Jul 2026 07:03:07 GMT" })
      stub_request(:get, "https://bucket.example.org/sefaria-export/json/T/Hebrew/Mikraot%20Gedolot.json")
        .to_return(status: 200, body: File.read(OBADIAH_FIXTURE))

      adapter = conformance_adapter
      adapter.define_singleton_method(:index_url) { "https://index.example.org/books.json" }
      report = adapter.fetch(workdir)

      assert_equal Digest::SHA256.hexdigest(index), report.sha
      assert File.file?(File.join(workdir, "books.json")), "the index rides in canonical"
      assert File.file?(File.join(workdir, "json/T/Hebrew/Mikraot Gedolot.json"))
      refute File.exist?(File.join(workdir, "json/T/Hebrew/merged.json"))
      assert_match(/1 file/, report.notes.to_s)
      assert_equal ["urn:nabu:sefaria:targum-jonathan-on-obadiah:mikraot-gedolot"],
                   adapter.discover(workdir).map(&:id)
    end
  end

  def test_fetch_failure_wraps_as_fetch_error
    Dir.mktmpdir do |workdir|
      stub_request(:get, "https://index.example.org/books.json").to_return(status: 500)
      adapter = conformance_adapter
      adapter.define_singleton_method(:index_url) { "https://index.example.org/books.json" }
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  private

  # A minimal tmp workdir holding ONE version file derived from the real
  # Obadiah fixture with a single field changed (or raw +body+) — the gate's
  # error paths need shapes upstream does not currently ship.
  def with_version(overrides, body: nil)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "json/Tanakh/Targum/T/Hebrew/V.json")
      FileUtils.mkdir_p(File.dirname(path))
      if body
        File.write(path, body)
      else
        data = JSON.parse(File.read(OBADIAH_FIXTURE)).merge(overrides)
        File.write(path, JSON.generate(data))
      end
      yield dir
    end
  end
end
