# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Query
  # Nabu::Query::ScanAnchors: the define → reference-scan bridges. A print
  # citation a dictionary entry carries (BDB's "BDB p. 135", the AED's
  # "Wb 1, 2.8") resolves to the held local-library scan of the cited work
  # and the PDF leaf of the printed page, through the config/scan_anchors.yml
  # rows (siglum pattern → shelf item per volume + leaf offset). The
  # citations come from the REAL hebrew-lexicon and aed fixtures through the
  # real DictionaryLoader; the shelf items are catalog document rows in the
  # local-library urn shape, and the calibration rows are synthetic.
  class ScanAnchorsTest < Minitest::Test
    include StoreTestDB

    WB_PATTERN = '\AWb (?<volume>\d)(?: ?[,.] ?| )(?<page>\d+)(?:\. ?(?<line>\d+))?'
    BDB_PATTERN = '\ABDB p\. (?<page>\d+)\z'

    BDB_ITEM = "urn:nabu:local-library:dictionaries:bdb-1906"
    WB1_ITEM = "urn:nabu:local-library:dictionaries:wb-1"
    WB23_ITEM = "urn:nabu:local-library:dictionaries:wb-2-3"
    WB4_ITEM = "urn:nabu:local-library:dictionaries:wb-4"

    # Synthetic calibration: Wb II and III share one scan (the two-volumes-
    # in-one-PDF case) with their own offsets; Wb IV is configured but not
    # ingested; Wb V has no row at all.
    def table_doc
      {
        "works" => {
          "bdb" => { "title" => "Brown–Driver–Briggs (1906)", "pattern" => BDB_PATTERN,
                     "item" => BDB_ITEM, "leaf_offset" => 16 },
          "wb" => {
            "title" => "Wörterbuch der aegyptischen Sprache", "pattern" => WB_PATTERN,
            "volumes" => {
              "1" => { "item" => WB1_ITEM, "leaf_offset" => 10 },
              "2" => { "item" => WB23_ITEM, "leaf_offset" => 8 },
              "3" => { "item" => WB23_ITEM, "leaf_offset" => 680 },
              "4" => { "item" => WB4_ITEM, "leaf_offset" => 12 }
            }
          }
        }
      }
    end

    def table(doc = table_doc) = Nabu::Query::ScanAnchors.new(doc)

    def setup
      @catalog = class_template_db do |db|
        hebrew = Nabu::Store::Source.create(
          slug: "hebrew-lexicon", name: "OSHB Hebrew Lexicon",
          adapter_class: "Nabu::Adapters::HebrewLexicon", license_class: "attribution"
        )
        Nabu::Store::DictionaryLoader.new(db: db, source: hebrew)
                                     .load_from(Nabu::Adapters::HebrewLexicon.new,
                                                workdir: Nabu::TestSupport.fixtures("hebrew-lexicon"))
        aed = Nabu::Store::Source.create(slug: "aed", name: "AED", adapter_class: "Nabu::Adapters::Aed",
                                         license_class: "attribution")
        Nabu::Store::DictionaryLoader.new(db: db, source: aed)
                                     .load_from(Nabu::Adapters::Aed.new,
                                                workdir: Nabu::TestSupport.fixtures("aed"))
        Nabu::Store::Source.create(slug: "local-library", name: "Library",
                                   adapter_class: "Nabu::Adapters::LocalLibrary",
                                   license_class: "research_private")
      end
      @library = Nabu::Store::Source.first!(slug: "local-library")
    end

    # A held scan: the document row, plus page passages for +leaves+ (a
    # text-layer PDF mints `<urn>:p<leaf>`; a bare scan mints none).
    def shelve(urn, leaves: [])
      doc = Nabu::Store::Document.create(source_id: @library.id, urn: urn, title: urn, language: "deu",
                                         content_sha256: "x", revision: 1, withdrawn: false)
      leaves.each do |leaf|
        Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:p#{leaf}", sequence: leaf,
                                    language: "deu", text: "p", text_normalized: "p",
                                    content_sha256: "x", revision: 1)
      end
      doc
    end

    # The entry by the urn define prints (the by_urn path builds the same
    # Result run does — citations included).
    def entry(urn, scan_anchors: table)
      Nabu::Query::Define.new(catalog: @catalog, lects: nil, scan_anchors: scan_anchors).by_urn(urn) or
        flunk "no #{urn}"
    end

    def scan_of(urn, label, **)
      citation = entry(urn, **).citations.find { |c| c.label == label } or flunk "no citation #{label}"
      citation.scan
    end

    # -- matching (pure) ------------------------------------------------------

    def test_match_parses_volume_page_and_line
      match = table.match("Wb 1, 2.8")
      assert_equal %w[wb 1 2 8], [match.work, match.volume, match.page.to_s, match.line.to_s]
    end

    def test_match_takes_the_first_page_and_line_of_a_range
      match = table.match("Wb 2, 253.1-256.15")
      assert_equal [2, 253, 1], [match.volume.to_i, match.page, match.line]
    end

    def test_match_tolerates_upstream_s_dot_after_the_volume
      match = table.match("Wb 3. 293.2-6")
      assert_equal [3, 293, 2], [match.volume.to_i, match.page, match.line]
    end

    def test_match_page_only_citation_has_no_line
      match = table.match("Wb 1, 270")
      assert_equal 270, match.page
      assert_nil match.line
    end

    def test_match_single_volume_work_has_no_volume
      match = table.match("BDB p. 135")
      assert_equal "bdb", match.work
      assert_nil match.volume
      assert_equal 135, match.page
    end

    # Real malformed segments from the AED census ("Wb 635.5" — no such volume;
    # "Wb, passim" — no locus at all) and a page 0 match nothing.
    def test_malformed_citations_match_nothing
      ["Wb 635.5", "Wb, passim", "WbZ: DZA 30", "Wb 1, 0.3", "BDB p. ", "Meeks, AL 78.0031"].each do |label|
        assert_nil table.match(label), label
      end
    end

    # -- config validation ----------------------------------------------------

    def test_a_pattern_without_a_page_capture_is_a_config_error
      doc = { "works" => { "x" => { "pattern" => '\AX (\d+)', "item" => "urn:a", "leaf_offset" => 0 } } }
      error = assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(doc) }
      assert_match(/page/, error.message)
    end

    def test_volumes_need_a_volume_capture_and_single_items_must_not_have_one
      multi = { "works" => { "x" => { "pattern" => '\AX (?<page>\d+)',
                                      "volumes" => { "1" => { "item" => nil, "leaf_offset" => nil } } } } }
      assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(multi) }
      single = { "works" => { "x" => { "pattern" => '\AX (?<volume>\d+), (?<page>\d+)',
                                       "item" => nil, "leaf_offset" => nil } } }
      assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(single) }
    end

    def test_a_non_integer_leaf_offset_is_a_config_error
      doc = { "works" => { "x" => { "pattern" => '\AX (?<page>\d+)', "item" => "urn:a", "leaf_offset" => "16" } } }
      assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(doc) }
    end

    # -- offset breaks (a bound-in fascicle insert shifts the offset) ---------

    # The Wb I shape: a Belegstellen fascicle is bound in mid-volume, so
    # printed pages up to 244 sit at +10 and pages from 245 at +46. The row
    # declares the base offset plus a breaks list; the page picks its offset.
    def breaks_doc
      { "works" => { "x" => { "pattern" => '\AX (?<page>\d+)', "item" => "urn:nabu:local-library:dictionaries:x",
                              "leaf_offset" => 10,
                              "breaks" => [{ "from_page" => 245, "leaf_offset" => 46 }] } } }
    end

    def test_offset_breaks_pick_the_offset_by_printed_page
      item = "urn:nabu:local-library:dictionaries:x"
      shelve(item, leaves: [254, 291])
      resolver = table(breaks_doc).resolver(@catalog)
      below = resolver.anchor("X 244")
      assert_equal [:anchored, 254], [below.status, below.leaf], "page 244 rides the base offset"
      at = resolver.anchor("X 245")
      assert_equal [:anchored, 291], [at.status, at.leaf], "page 245 rides the break offset"
    end

    def test_breaks_rows_validate
      bad_page = breaks_doc
      bad_page["works"]["x"]["breaks"] = [{ "from_page" => "245", "leaf_offset" => 46 }]
      assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(bad_page) }
      bad_offset = breaks_doc
      bad_offset["works"]["x"]["breaks"] = [{ "from_page" => 245, "leaf_offset" => nil }]
      assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(bad_offset) }
      no_base = breaks_doc
      no_base["works"]["x"]["leaf_offset"] = nil
      assert_raises(Nabu::Query::ScanAnchors::ConfigError) { table(no_base) }
    end

    # The shipped rows parse (the orchestrator fills item/leaf_offset after
    # ingest — until then every row is honestly unconfigured).
    def test_the_shipped_config_loads_and_routes_the_wb_volumes
      shipped = Nabu::Query::ScanAnchors.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "scan_anchors.yml"))
      assert_equal "wb", shipped.match("Wb 4, 503.6").work
      assert_equal "bdb", shipped.match("BDB p. 135").work
    end

    def test_load_default_is_nil_when_the_file_is_absent
      Dir.mktmpdir do |dir|
        config = Nabu::Config.new(canonical_dir: dir, db_dir: dir, sources_path: File.join(dir, "s.yml"),
                                  config_path: File.join(dir, "config", "nabu.yml"))
        assert_nil Nabu::Query::ScanAnchors.load_default(config: config)
      end
    end

    # -- define → BDB page anchor --------------------------------------------

    # BDB p. 135 + 16 = leaf 151; the text-layer scan holds the page passage.
    def test_bdb_page_anchors_to_the_scan_leaf_passage
      shelve(BDB_ITEM, leaves: [151])
      scan = scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135")
      assert_equal :anchored, scan.status
      assert_equal 151, scan.leaf
      assert_equal "#{BDB_ITEM}:p151", scan.urn
      assert_equal BDB_ITEM, scan.item
    end

    # A scan without a text layer (no page passages) still anchors — to the
    # document, with the leaf to open.
    def test_bdb_page_on_a_bare_scan_points_at_the_document_and_leaf
      shelve(BDB_ITEM)
      scan = scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135")
      assert_equal :held, scan.status
      assert_equal BDB_ITEM, scan.urn
      assert_equal 151, scan.leaf
      assert_match(/leaf 151/, scan.pointer)
    end

    def test_absent_scan_is_an_honest_hint_never_a_link
      scan = scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135")
      assert_equal :not_held, scan.status
      assert_nil scan.urn
      assert_nil scan.leaf
      assert_match(/not held/, scan.pointer)
      assert_includes scan.pointer, BDB_ITEM
    end

    def test_withdrawn_scan_counts_as_absent
      shelve(BDB_ITEM, leaves: [151]).update(withdrawn: true)
      assert_equal :not_held, scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135").status
    end

    def test_unconfigured_item_and_uncalibrated_offset_say_so
      doc = table_doc
      doc["works"]["bdb"]["item"] = nil
      scan = scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135", scan_anchors: table(doc))
      assert_equal :unconfigured, scan.status
      assert_match(%r{config/scan_anchors\.yml}, scan.pointer)

      shelve(BDB_ITEM, leaves: [151])
      doc["works"]["bdb"]["item"] = BDB_ITEM
      doc["works"]["bdb"]["leaf_offset"] = nil
      scan = scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135", scan_anchors: table(doc))
      assert_equal :uncalibrated, scan.status
      assert_equal BDB_ITEM, scan.urn
      assert_nil scan.leaf
      assert_match(/printed p\. 135/, scan.pointer)
    end

    def test_a_leaf_before_the_scan_start_is_out_of_range
      shelve(BDB_ITEM)
      doc = table_doc
      doc["works"]["bdb"]["leaf_offset"] = -200
      scan = scan_of("urn:nabu:dict:bdb:b.cw.aa", "BDB p. 135", scan_anchors: table(doc))
      assert_equal :out_of_range, scan.status
      assert_nil scan.leaf
    end

    # -- define → Wb page.line bridge ----------------------------------------

    # Wb 1, 2.8 → volume 1's scan, leaf 2 + 10, the line carried along.
    def test_wb_citation_routes_to_its_volume_with_the_line
      shelve(WB1_ITEM, leaves: [12])
      scan = scan_of("urn:nabu:dict:aed:tla10", "Wb 1, 2.8")
      assert_equal :anchored, scan.status
      assert_equal ["wb", "1", 2, 8, 12], [scan.work, scan.volume, scan.page, scan.line, scan.leaf]
      assert_equal "#{WB1_ITEM}:p12", scan.urn
      assert_match(/line 8/, scan.pointer)
    end

    # Two volumes in one scan: same item, each volume its own offset.
    def test_volumes_sharing_one_scan_use_their_own_offsets
      shelve(WB23_ITEM, leaves: [260, 973])
      two = scan_of("urn:nabu:dict:aed:tla83460", "Wb 2, 252.12")
      three = scan_of("urn:nabu:dict:aed:tla118230", "Wb 3. 293.2-6")
      assert_equal ["#{WB23_ITEM}:p260", 260], [two.urn, two.leaf]
      assert_equal ["#{WB23_ITEM}:p973", 973], [three.urn, three.leaf]
    end

    def test_a_volume_without_a_row_names_the_volume
      scan = scan_of("urn:nabu:dict:aed:tla10130", "Wb 5, 371.14-16")
      assert_equal :unconfigured, scan.status
      assert_equal "5", scan.volume
      assert_match(/vol\. 5/, scan.pointer)
    end

    def test_a_configured_but_uningested_volume_is_not_held
      scan = scan_of("urn:nabu:dict:aed:tla100000", "Wb 4, 503.6")
      assert_equal :not_held, scan.status
      assert_includes scan.pointer, WB4_ITEM
    end

    # -- the lane-off and non-matching paths ---------------------------------

    def test_citations_outside_every_work_carry_no_scan
      result = entry("urn:nabu:dict:aed:tla100")
      assert(result.citations.none?(&:scan))
    end

    def test_no_table_means_no_scan_anywhere
      result = entry("urn:nabu:dict:aed:tla10", scan_anchors: nil)
      assert_equal ["Wb 1, 2.8"], result.citations.map(&:label)
      assert_nil result.citations.first.scan
    end

    # One document probe per held item per Define, however many citations.
    def test_held_items_are_probed_once_per_query
      shelve(WB23_ITEM, leaves: [261])
      resolver = table.resolver(@catalog)
      queries = 0
      @catalog.loggers << (logger = Object.new)
      logger.define_singleton_method(:info) { |msg| queries += 1 if msg.include?("documents") }
      %i[debug warn error].each { |level| logger.define_singleton_method(level) { |*| nil } }
      3.times { resolver.anchor("Wb 2, 253.1-256.15") }
      @catalog.loggers.delete(logger)
      assert_equal 1, queries
    end
  end
end
