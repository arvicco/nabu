# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Ppchy adapter tests: the Penn Parsed Corpus of Historical Yiddish
# (Santorini 2021, CC BY-NC-SA 4.0) on the penn-psd family's :ppche
# profile. Fixture: four real .psd files (one whole, three tree-trimmed),
# the upstream sources page trimmed to their entries (the metadata the
# adapter mines for date / dialect / place / genre), the in-repo grant,
# and the two rejected-grain specimens (a page-image PDF, the annotation
# manual's frameset page).
class PpchyTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("ppchy")
  LETTER = "urn:nabu:ppchy:1478w-letter-regensburg"
  LEV_TOV = "urn:nabu:ppchy:1620e-lev-tov-1-preface"
  GRINE = "urn:nabu:ppchy:1910e-grine-felder"
  COURT = "urn:nabu:ppchy:1xxxx-court-testimony"

  def conformance_adapter = Nabu::Adapters::Ppchy.new
  def conformance_workdir = FIXTURES
  def conformance_expected_source_id = "ppchy"

  def adapter = Nabu::Adapters::Ppchy.new

  def document(urn)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn } || flunk("discover must yield #{urn}")
    adapter.parse(ref)
  end

  # --- manifest + identity ------------------------------------------------------

  def test_manifest_records_the_verbatim_nc_grant
    manifest = adapter.manifest
    assert_equal "nc", manifest.license_class
    assert_includes manifest.license, "Attribution-NonCommercial-ShareAlike 4.0 International"
    assert_equal "penn-psd", manifest.parser_family
    assert_equal "https://github.com/beatrice57/penn-parsed-corpus-of-historical-yiddish", manifest.upstream_url
  end

  def test_discover_yields_one_document_per_psd_file_sorted
    assert_equal [LETTER, LEV_TOV, GRINE, COURT], adapter.discover(FIXTURES).map(&:id)
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a, "the pre-fetch state yields nothing" }
  end

  def test_passage_censuses_and_citations
    counts = adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref).size] }
    assert_equal({ LETTER => 10, LEV_TOV => 10, GRINE => 12, COURT => 16 }, counts)
    letter = document(LETTER)
    assert_equal "#{LETTER}:156.3", letter.first.urn, "the ID's PAGE.N after the comma"
    assert_equal "liebe froyndin, du liebe kron, ikh kasven dir fil,", letter.first.text
    assert_equal "yi", letter.language
    assert_equal "1478w-letter-regensburg", letter.title
  end

  # --- the mined axes: date / dialect / place / genre ------------------------------

  def test_the_sources_page_dates_every_text
    assert_equal({ "not_before" => 1478, "not_after" => 1478, "raw" => "1478" }, document(LETTER).metadata["date"])
    assert_equal({ "not_before" => 1910, "not_after" => 1910, "raw" => "Approx. 1910" },
                 document(GRINE).metadata["date"], "Approx. keeps the year, the qualifier rides raw (memis)")
    assert_equal({ "not_before" => 1413, "not_after" => 1686, "raw" => "Various, ranging from c1413 to 1686" },
                 document(COURT).metadata["date"])
  end

  def test_date_shapes_parse_conservatively
    dates = Nabu::Adapters::Ppchy.method(:date_for)
    assert_equal [1691, 1719], dates.call("Between 1691 and 1719").values_at("not_before", "not_after")
    assert_equal [1900, 1999], dates.call("19xx").values_at("not_before", "not_after"),
                 "19xxe-argentine: the century envelope"
    assert_equal({ "raw" => "sometime" }, dates.call("sometime"), "unparsed prose mints no bounds")
  end

  def test_the_dates_and_places_project_through_the_structured_metadata_lane
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["ppchy"],
                 "the date hash + the place string ride the catalog-metadata timeline lane"
  end

  def test_dialect_splits_into_the_classification_and_its_localization
    letter = document(LETTER).metadata
    assert_equal "West Yiddish", letter["dialect"]
    assert_equal "Regensburg", letter["dialect_localization"]
    assert_equal "Regensburg", letter["place"], "a town localization is the text's place claim"
    court = document(COURT).metadata
    assert_equal "East and West Yiddish", court["dialect"]
    assert_nil court["place"]
    split = Nabu::Adapters::Ppchy.method(:dialect_parts)
    assert_equal ["Probably West Yiddish (Erika Timm, pers. comm.)", nil],
                 split.call("Probably West Yiddish (Erika Timm, pers. comm.)"),
                 "the comma inside the parenthesis is not a localization"
    assert_nil Nabu::Adapters::Ppchy.place_for("Moravian"), "an adjectival dialect area is no place"
    assert_nil Nabu::Adapters::Ppchy.place_for('"halb-deytshish" (Dubnov 1929:32)')
    assert_equal "Northern Germany", Nabu::Adapters::Ppchy.place_for("Northern Germany")
  end

  def test_genre_resolves_the_preface_main_text_split_per_file
    lev_tov = document(LEV_TOV).metadata
    assert_equal "Prose", lev_tov["genre"], "\"Prose (preface), verse (main text)\" — this file is the preface"
    assert_equal "Prose (preface), verse (main text)", lev_tov["genre_raw"]
    assert_equal "Vernacular", document(GRINE).metadata["genre"]
    assert_equal "Letter", document(LETTER).metadata["genre"]
  end

  def test_the_sources_page_record_rides_verbatim
    letter = document(LETTER).metadata
    assert_match(/\AR\. Straus\. 1960\. Urkunden und Aktenstücke/, letter["source"], "entities decoded")
    assert_includes letter["notes"], "Oldest Yiddish letter of certain date."
    assert_equal "75", letter["words"]
    assert_equal "NO, BIRNBAUM", letter["page_images"], "upstream's own page-image flag"
    assert_equal "data/1478w-letter-regensburg.psd", letter["file"]
  end

  def test_court_testimony_items_carry_their_own_date_and_dialect
    court = document(COURT)
    first = court.first
    assert_equal "#{COURT}:1_c1413_w.3", first.urn
    assert_equal({ "item" => "1", "item_date" => "c1413", "item_year" => 1413, "item_dialect" => "w" },
                 first.annotations.slice("item", "item_date", "item_year", "item_dialect"))
    uncertain = court.find { |p| p.urn.end_with?(":27_c1460_w?.104") }
    assert_equal "w?", uncertain.annotations["item_dialect"], "upstream's trailing ? marks uncertainty"
    exact = court.find { |p| p.urn.end_with?(":37_1463_x.146") }
    assert_equal "1463", exact.annotations["item_date"]
    assert_equal "x", exact.annotations["item_dialect"], "x = the dialect cannot be established"
    refute document(LETTER).first.annotations.key?("item"), "only the court-item IDs carry the shape"
  end

  def test_the_tree_and_tokens_lanes_ride_every_passage
    passage = document(GRINE).first
    assert passage.annotations.fetch("tree").start_with?("((META (ADJ ershter)")
    assert_includes passage.text, "oyfn yishev", "the @-split rejoins on the surface"
    assert_equal "1910E-GRINE-FELDER,63.3", passage.annotations.fetch("id")
  end

  # --- discovery census: the rejected grains ------------------------------------

  def test_rejected_grains_skip_by_rule_and_strays_in_data_are_counted
    skips = adapter.discovery_skips(FIXTURES)
    assert_equal 2, skips.skipped_by_rule, "the page-image PDF and the annotation manual page"
    assert_equal 0, skips.unrecognized
    notes = skips.notes.join("\n")
    assert_match(%r{doc/pdf-images/1819e-khasid\.pdf: .*page images}, notes)
    assert_match(%r{doc/annotation-yiddish/index\.html: .*annotation manual}, notes)
    Dir.mktmpdir do |work|
      FileUtils.cp_r(File.join(FIXTURES, "data"), work)
      File.write(File.join(work, "data", ".DS_Store"), "junk")
      stray = adapter.discovery_skips(work)
      assert_equal 1, stray.skipped_by_rule, "upstream's own data/.DS_Store is not a parsed text"
      assert_equal 4, adapter.discover(work).count
    end
  end

  def test_a_psd_without_a_sources_entry_falls_back_to_its_file_name
    Dir.mktmpdir do |work|
      FileUtils.mkdir_p(File.join(work, "data"))
      FileUtils.cp(File.join(FIXTURES, "data", "1478w-letter-regensburg.psd"),
                   File.join(work, "data", "1478w-letter-regensburg.psd"))
      ref = adapter.discover(work).first
      metadata = adapter.parse(ref).metadata
      assert_equal({ "not_before" => 1478, "not_after" => 1478, "raw" => "1478w (file name)" }, metadata["date"])
      assert_equal "West Yiddish", metadata["dialect"], "the file name's w/e letter is upstream's own code"
    end
  end

  # --- store: idempotent double-load ------------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "ppchy", name: "PPCHY", adapter_class: "Nabu::Adapters::Ppchy",
                                        license_class: "nc")
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 4, first.added
    assert_equal 0, first.errored
    assert_equal 48, catalog[:passages].count
    second = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 4, second.skipped, "a byte-identical reload skips every document"
    assert_equal 48, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- registry + fetch --------------------------------------------------------

  def test_registry_resolves_ppchy_with_the_manifest
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["ppchy"]
    refute_nil entry, "ppchy must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::Ppchy, entry.adapter_class
    assert_equal Nabu::Adapters::Ppchy.manifest, entry.manifest
    assert_equal "manual", entry.sync_policy
  end

  def test_fetch_clones_the_sparse_cone_and_the_tree_is_discoverable
    Dir.mktmpdir("nabu-ppchy-fetch") do |root|
      upstream = File.join(root, "upstream")
      FileUtils.mkdir_p(upstream)
      %w[data doc LICENSE.rst README.rst].each { |entry| FileUtils.cp_r(File.join(FIXTURES, entry), upstream) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")

      ppchy = adapter
      ppchy.define_singleton_method(:repo_url) { upstream }
      workdir = File.join(root, "canonical")
      report = ppchy.fetch(workdir)
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert_equal 4, ppchy.discover(workdir).count
      refute File.exist?(File.join(workdir, "doc", "pdf-images")), "the page images stay outside the cone"
      assert File.file?(File.join(workdir, "doc", "sources", "yiddish-sources-contents.html"))
    end
  end
end
