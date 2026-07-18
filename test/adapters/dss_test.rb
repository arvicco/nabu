# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Dss (P30-5) — the ETCBC Dead Sea Scrolls over the
  # text-fabric family: second registrant, document = scroll, passage =
  # fragment + line, tokens at word grain, upstream's text-critical
  # cluster nodes riding annotations verbatim. Fixtures are byte-verbatim
  # tf/2.0 slices (3Q15 the Copper Scroll, 4Q156 the Aramaic Targum of
  # Leviticus, BOTH same-named 4Q483 scroll nodes, 4Q567 for the alt
  # cluster, 4Q143 for the line-crossing rem2 cluster) at upstream commit
  # 2403d166 — see test/fixtures/dss/README.md for the trim recipe.
  class DssTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("dss")

    def conformance_adapter
      Nabu::Adapters::Dss.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "dss"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_dss_disabled_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["dss"]
      refute_nil entry, "dss must be registered in config/sources.yml"
      refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
      assert_equal "manual", entry.sync_policy
      assert_equal "dss", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_with_both_license_grants_verbatim
      manifest = Nabu::Adapters::Dss.manifest
      assert_equal "nc", manifest.license_class, "CC BY-NC 4.0 data grant → nc, the bhsa/proiel posture"
      assert_includes manifest.license,
                      "@license=Creative Commons Attribution-NonCommercial 4.0 International License",
                      "the machine-readable .tf header grant, verbatim"
      assert_includes manifest.license,
                      "Martin Abegg graciously gave permission to Jarod Jacobs to use his data and to " \
                      "distribute the results under a CC-BY-NC license",
                      "the docs/about.md Abegg grant, verbatim"
      assert_includes manifest.license, "MIT grant covers \"the program code\" only"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census (otype.tf rides the fixture WHOLE — the census of record) -----

    def test_the_whole_otype_census_matches_the_briefed_numbers_exactly
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "2.0"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal 1_430_241, counts["sign"]
      assert_equal 500_995, counts["word"]
      assert_equal 52_895, counts["line"]
      assert_equal 11_182, counts["fragment"]
      assert_equal 1_001, counts["scroll"]
      assert_equal 10_450, counts["lex"]
      assert_equal 101_099, counts["cluster"]
      assert_equal 125, counts["clause"], "the v2.0 ML extras — silver, deliberately not ingested"
      assert_equal 315, counts["phrase"]
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_scroll_node_with_dup_names_suffixed
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:dss:3q15
        urn:nabu:dss:4q143
        urn:nabu:dss:4q156
        urn:nabu:dss:4q483
        urn:nabu:dss:4q483-2
        urn:nabu:dss:4q567
      ], refs.map(&:id), "scroll names downcased verbatim; the second same-named node (in node order) gets -2"
      assert_equal(%w[3Q15 4Q143 4Q156 4Q483 4Q483 4Q567], refs.map { |ref| ref.metadata["scroll"] })
      four83 = refs.select { |ref| ref.metadata["scroll"] == "4Q483" }
      assert_equal four83.map { |ref| ref.metadata["node"] }.sort, four83.map { |ref| ref.metadata["node"] },
                   "the plain urn belongs to the FIRST node in node order — the pin the -2 suffix rests on"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_corpus_fragment_line_grain
      assert_equal 181, parse_urn("urn:nabu:dss:3q15").size, "the Copper Scroll has 181 lines in 12 columns"
      assert_equal 14, parse_urn("urn:nabu:dss:4q156").size
      assert_equal 5, parse_urn("urn:nabu:dss:4q483").size
      assert_equal 2, parse_urn("urn:nabu:dss:4q483-2").size
      assert_equal 3, parse_urn("urn:nabu:dss:4q567").size
      assert_equal 15, parse_urn("urn:nabu:dss:4q143").size
    end

    def test_passage_urns_ride_the_line_nodes_own_fragment_and_line_labels
      copper = parse_urn("urn:nabu:dss:3q15")
      assert_equal "urn:nabu:dss:3q15:1.1", copper.passages.first.urn
      targum = parse_urn("urn:nabu:dss:4q156")
      assert_equal %w[urn:nabu:dss:4q156:f1.1 urn:nabu:dss:4q156:f1.2], targum.passages.first(2).map(&:urn)
      deut = parse_urn("urn:nabu:dss:4q143")
      assert_equal "urn:nabu:dss:4q143:f1R.1", deut.passages.first.urn,
                   "fragment labels keep their case verbatim — f1R, never folded"
      assert_equal %w[urn:nabu:dss:4q483-2:f1.4 urn:nabu:dss:4q483-2:f1.5],
                   parse_urn("urn:nabu:dss:4q483-2").passages.map(&:urn),
                   "the second 4Q483 node carries f1:4-5 — the un-reunited biblical-file remainder"
    end

    def test_line_text_is_the_corpus_own_text_orig_full_rendering
      passage = passage_at("urn:nabu:dss:3q15", "urn:nabu:dss:3q15:1.1")
      assert_equal "בחרובא שבעמק עכור תחת", passage.text,
                   "{glyph}{punc}{after} per sign, byte-verbatim, trailing whitespace stripped"
      assert_equal "hbo", passage.language
      four83 = passage_at("urn:nabu:dss:4q483", "urn:nabu:dss:4q483:f1.1")
      assert four83.text.end_with?("╱"), "upstream's end-of-line token is kept as shipped"
      assert_includes four83.text, "׃", "sof pasuq signs render in place"
      targum = passage_at("urn:nabu:dss:4q156", "urn:nabu:dss:4q156:f1.2")
      assert_equal "יהוה ומלא חפנו׳הי כש ε", targum.text,
                   "ε = upstream's missing-sign glyph, byte-verbatim; geresh = morpheme break"
      assert_equal "arc", targum.language
    end

    def test_tokens_carry_the_word_grain_features_verbatim
      passage = passage_at("urn:nabu:dss:4q156", "urn:nabu:dss:4q156:f1.2")
      token = passage.annotations["tokens"].find { |t| t["n"] == 1_657_371 }
      assert_equal "חפנו׳הי", token["form"], "glyph — letters only"
      assert_equal "ח##פנו?׳ה##[ י ]", token["full"],
                   "the flagged transcription VERBATIM — uncertainty flags, brackets, inner spaces"
      assert_equal "חפן", token["lex"]
      assert_equal "arc", token["lang"]
      assert_equal "ncmdcX3ms", token["morpho"], "Abegg's original tag rides beside the decomposition"
      assert_equal "suff", token["sp"]
      assert_equal "glyph", token["type"]
      assert_equal " ", token["after"]
    end

    def test_empty_transcription_words_keep_their_token_place
      passage = passage_at("urn:nabu:dss:4q156", "urn:nabu:dss:4q156:f1.2")
      token = passage.annotations["tokens"].find { |t| t["n"] == 1_657_373 }
      refute token.key?("form"), "a word with no glyph keeps its place with no form key (bhsa precedent)"
      assert_equal "ε", token["full"]
      assert_equal " # ", token["lex"], "upstream's uncertainty placeholder lexeme, verbatim spaces and all"
    end

    def test_punct_and_numeral_words_ride_their_own_types
      copper = parse_urn("urn:nabu:dss:3q15")
      sof = copper.find { |p| p.urn == "urn:nabu:dss:3q15:1.4" }
                  .annotations["tokens"].find { |t| t["n"] == 1_655_476 }
      assert_equal "punct", sof["type"]
      refute sof.key?("form"), "a sof pasuq word has no glyph"
      assert_equal "׃", sof["punc"]
      numeral = copper.find { |p| p.urn == "urn:nabu:dss:3q15:1.6" }
                      .annotations["tokens"].find { |t| t["n"] == 1_655_485 }
      assert_equal "numr", numeral["type"]
      assert_equal "א֜ק֜", numeral["form"], "paleo-Hebrew numeral glyphs, byte-verbatim"
      assert_equal "paleohebrew", numeral["script"]
    end

    # -- languages ------------------------------------------------------------

    def test_language_rides_upstream_absent_a_g_encoding
      assert_equal "hbo", parse_urn("urn:nabu:dss:3q15").language
      assert_equal "arc", parse_urn("urn:nabu:dss:4q156").language, "the Targum votes Aramaic"
      assert_equal "arc", parse_urn("urn:nabu:dss:4q567").language
      greek_line = passage_at("urn:nabu:dss:3q15", "urn:nabu:dss:3q15:1.4")
      assert_equal "hbo", greek_line.language, "5 Hebrew vs 1 Greek token — majority vote"
      greek = greek_line.annotations["tokens"].find { |t| t["n"] == 1_655_475 }
      assert_equal "grc", greek["lang"], "3Q15's Greek letter clusters map g → grc, honestly"
      assert_equal "ΚΕΝ", greek["form"]
      assert_equal "greekcapital", greek["script"]
    end

    # -- the biblical lane ----------------------------------------------------

    def test_biblical_scrolls_carry_the_facet_and_word_grain_references
      four83 = parse_urn("urn:nabu:dss:4q483")
      assert_equal 1, four83.metadata["biblical"], "scroll-level biblical rides document metadata verbatim"
      token = four83.passages.first.annotations["tokens"].find { |t| t["n"] == 1_802_285 }
      assert_equal "Gen", token["book"]
      assert_equal "1", token["chapter"]
      assert_equal "27", token["verse"]
      assert_equal 2, token["biblical"],
                   "4Q483 f1:1 is one of the 14 lines shipped in BOTH source files — biblical=2, verbatim"
      deut = parse_urn("urn:nabu:dss:4q143")
      first = deut.passages.first.annotations["tokens"].first
      assert_equal %w[Deut 10 22], [first["book"], first["chapter"], first["verse"]]
      refute parse_urn("urn:nabu:dss:3q15").metadata.key?("biblical"),
             "a non-biblical scroll carries no biblical key — absent is absent"
    end

    # -- clusters: the text-critical layer (verbatim, never flattened) --------

    def test_reconstruction_clusters_ride_annotations_with_token_index_ranges
      passage = passage_at("urn:nabu:dss:4q156", "urn:nabu:dss:4q156:f1.2")
      clusters = passage.annotations["clusters"]
      rec = clusters.select { |c| c["type"] == "rec" }
      assert_equal [[[0, 2]], [[3, 3]], [[5, 5]]], rec.map { |c| c["ranges"] },
                   "0-based inclusive token-index ranges into this passage's tokens"
      assert_equal [1_437_217, 1_437_218, 1_437_219], rec.map { |c| c["node"] },
                   "the TF cluster node is the stable identity"
      assert(rec.none? { |c| c["partial"] }, "line-contained clusters carry no partial flag")
      full = passage.annotations["tokens"].map { |t| t["full"] }.join(" ")
      assert_includes full, "[", "sub-token bracket placement is never flattened — it rides the full bytes"
    end

    def test_cluster_types_keep_upstream_degrees_verbatim
      doc = parse_urn("urn:nabu:dss:4q567")
      alt = doc.flat_map { |p| p.annotations.fetch("clusters", []) }.find { |c| c["type"] == "alt" }
      refute_nil alt, "4Q567 carries the fixture's alt (alternative-reading) cluster"
      assert_equal 1_491_352, alt["node"]
      copper_types = parse_urn("urn:nabu:dss:3q15")
                     .flat_map { |p| p.annotations.fetch("clusters", []) }.map { |c| c["type"] }.uniq.sort
      assert_equal %w[cor cor3 rec rem vac], copper_types,
                   "the Copper Scroll's own mix, degrees intact — cor3 rides beside cor, never folded"
      deut_types = parse_urn("urn:nabu:dss:4q143")
                   .flat_map { |p| p.annotations.fetch("clusters", []) }.map { |c| c["type"] }.uniq.sort
      assert_equal %w[alt cor2 rec rem2], deut_types,
                   "4Q143 attests the ancient-editor degrees verbatim — cor2/rem2 never fold to cor/rem"
    end

    def test_a_vacat_cluster_is_a_positioned_gap_with_empty_ranges
      passage = passage_at("urn:nabu:dss:3q15", "urn:nabu:dss:3q15:1.15")
      vac = passage.annotations["clusters"].find { |c| c["node"] == 1_436_791 }
      assert_equal "vac", vac["type"]
      assert_equal [], vac["ranges"],
                   "a vacat contains only an empty sign belonging to NO word — an empty unwritten space"
      refute vac["partial"]
    end

    def test_line_crossing_cluster_is_clipped_per_passage_and_flagged_partial
      deut = parse_urn("urn:nabu:dss:4q143")
      pieces = deut.passages.first(3).map do |passage|
        passage.annotations["clusters"].find { |c| c["node"] == 1_525_404 }
      end
      assert_equal %w[rem2 rem2 rem2], pieces.map { |c| c["type"] },
                   "cluster 1525404 (removed-by-ancient-editor) spans f1R:1-3"
      assert_equal [[[0, 7]], [[0, 19]], [[0, 8]]], pieces.map { |c| c["ranges"] },
                   "each passage carries its own clipped token ranges"
      assert(pieces.all? { |c| c["partial"] }, "every clipped side flags partial")
      assert_equal [1_525_404], pieces.map { |c| c["node"] }.uniq, "the shared node id joins the pieces"
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = dss_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 6, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "unchanged DSS scrolls must not fake content revisions"
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def passage_at(document_urn, passage_urn)
      passage = parse_urn(document_urn).find { |p| p.urn == passage_urn }
      refute_nil passage, "expected #{passage_urn} in #{document_urn}"
      passage
    end

    def dss_source
      Nabu::Store::Source.create(
        slug: "dss", name: "DSS (Abegg/ETCBC)",
        adapter_class: "Nabu::Adapters::Dss", license_class: "nc"
      )
    end
  end
end
