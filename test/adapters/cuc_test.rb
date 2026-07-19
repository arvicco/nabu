# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Cuc (P31-4) — the Copenhagen Ugaritic Corpus over the
  # text-fabric family: THIRD registrant, document = tablet (KTU number),
  # passage = column + line (the corpus's own tablet/column/line citation
  # grain), tokens at word grain carrying the per-sign transliteration +
  # cuneiform lanes with the text-critical flags (cert/emen/alt/cont)
  # verbatim. Fixtures are byte-verbatim tf/0.2.8 slices of ten tablets at
  # upstream commit 0408967b — see test/fixtures/cuc/README.md for the trim
  # recipe and why each tablet was chosen.
  class CucTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("cuc")

    def conformance_adapter
      Nabu::Adapters::Cuc.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "cuc"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_cuc_disabled_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["cuc"]
      refute_nil entry, "cuc must be registered in config/sources.yml"
      refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
      assert_equal "manual", entry.sync_policy
      assert_equal "cuc", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_with_the_british_spelled_licence_header_verbatim
      manifest = Nabu::Adapters::Cuc.manifest
      assert_equal "nc", manifest.license_class, "CC BY-NC 4.0 in every .tf header → nc, the bhsa/dss posture"
      assert_includes manifest.license,
                      "@licence=Creative Commons Attribution-NonCommercial 4.0 International License",
                      "the machine-readable header grant verbatim — NB upstream's British spelling of the key"
      assert_includes manifest.license, "http://creativecommons.org/licenses/by-nc/4.0/"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census (otype.tf rides the fixture WHOLE — the census of record) -----

    def test_the_whole_otype_census_matches_the_briefed_numbers_exactly
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.2.8"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal 146_017, counts["sign"]
      assert_equal 27_770, counts["word"]
      assert_equal 7_616, counts["line"]
      assert_equal 334, counts["column"]
      assert_equal 279, counts["tablet"], "otype's count; upstream's README says '278 tablets' — otype wins"
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_tablet_with_ktu_numbers_in_the_urn
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:cuc:ktu-1.105
        urn:nabu:cuc:ktu-1.15
        urn:nabu:cuc:ktu-1.172
        urn:nabu:cuc:ktu-1.21
        urn:nabu:cuc:ktu-1.24
        urn:nabu:cuc:ktu-1.43
        urn:nabu:cuc:ktu-1.50
        urn:nabu:cuc:ktu-1.54
        urn:nabu:cuc:ktu-1.7
        urn:nabu:cuc:ktu-2.103
      ], refs.map(&:id), "tablet.tf names ('KTU 1.24', censused uniformly of that shape) mint ktu-<n>"
      assert_equal "KTU 1.24", refs.find { |r| r.id.end_with?("ktu-1.24") }.metadata["tablet"]
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- documents and passages ----------------------------------------------

    def test_documents_carry_the_tablet_column_line_grain
      assert_equal 136, parse_urn("urn:nabu:cuc:ktu-1.15").size, "Keret: 136 lines across columns I-VI"
      assert_equal 50, parse_urn("urn:nabu:cuc:ktu-1.24").size, "Nikkal"
      assert_equal 33, parse_urn("urn:nabu:cuc:ktu-2.103").size, "a letter — the KTU 2 epistolary lane"
      assert_equal 53, parse_urn("urn:nabu:cuc:ktu-1.7").size, "56 lines minus the 3 whitespace-only renders"
      assert_equal 13, parse_urn("urn:nabu:cuc:ktu-1.54").size, "14 lines minus 1 whitespace-only render"
    end

    def test_documents_are_uniformly_ugaritic
      %w[urn:nabu:cuc:ktu-1.15 urn:nabu:cuc:ktu-2.103].each do |urn|
        document = parse_urn(urn)
        assert_equal "uga", document.language, "language.tf says Ugaritic for every word (censused)"
        assert(document.all? { |passage| passage.language == "uga" })
      end
    end

    def test_passage_urns_cite_column_and_line
      keret = parse_urn("urn:nabu:cuc:ktu-1.15")
      assert_equal "urn:nabu:cuc:ktu-1.15:I.1", keret.passages.first.urn
      columns = keret.passages.map { |p| p.annotations["column"] }.uniq
      assert_equal %w[I II III IV V VI], columns, "the corpus's own roman-numeral column labels"
      danil = parse_urn("urn:nabu:cuc:ktu-1.21")
      assert_includes danil.passages.map(&:urn), "urn:nabu:cuc:ktu-1.21:II.1"
      assert_includes danil.passages.map(&:urn), "urn:nabu:cuc:ktu-1.21:V.1",
                      "line 1 exists in BOTH columns — the column citation disambiguates"
    end

    def test_the_trailing_space_column_label_is_stripped_in_the_urn_but_verbatim_in_annotations
      passage = passage_at("urn:nabu:cuc:ktu-1.50", "urn:nabu:cuc:ktu-1.50:I.1")
      assert_equal "I ", passage.annotations["column"],
                   "KTU 1.50's column label carries upstream's trailing space — kept verbatim"
      assert_equal 1, passage.annotations["line"]
    end

    def test_line_text_is_the_corpus_own_sign_stream_rendering
      passage = passage_at("urn:nabu:cuc:ktu-1.24", "urn:nabu:cuc:ktu-1.24:I.1")
      assert_equal "ašr  nkl w ib", passage.text,
                   "otext's text-orig-full = {sign} per slot, byte-verbatim, trailing whitespace stripped"
      damaged = passage_at("urn:nabu:cuc:ktu-1.7", "urn:nabu:cuc:ktu-1.7:I.1")
      assert_equal "                               xxx", damaged.text,
                   "leading spaces are tablet position, x is the corpus's illegible-sign letter — kept"
      dashes = passage_at("urn:nabu:cuc:ktu-2.103", "urn:nabu:cuc:ktu-2.103:I.27")
      assert_equal "---", dashes.text, "upstream's dash signs render as shipped"
    end

    def test_side_labels_ride_annotations_verbatim_including_upstream_whitespace_quirks
      assert_equal "rev.\t", passage_at("urn:nabu:cuc:ktu-1.43", "urn:nabu:cuc:ktu-1.43:I.1")
        .annotations["side"], "KTU 1.43's tab-suffixed side label, byte-verbatim"
      assert_equal "rev.?", passage_at("urn:nabu:cuc:ktu-1.172", "urn:nabu:cuc:ktu-1.172:I.17")
        .annotations["side"], "the uncertain-side label (lines 17-31 of the tablet), verbatim"
      assert_equal "le.e.", passage_at("urn:nabu:cuc:ktu-1.21", "urn:nabu:cuc:ktu-1.21:II.1")
        .annotations["side"]
    end

    # -- tokens: word grain over the sign-slot lanes --------------------------

    def test_tokens_carry_word_features_and_the_per_sign_lanes
      passage = passage_at("urn:nabu:cuc:ktu-1.24", "urn:nabu:cuc:ktu-1.24:I.1")
      token = passage.annotations["tokens"].find { |t| t["n"] == 166_592 }
      assert_equal "ašr", token["form"], "g_cons — the consonantal word"
      assert_equal ".", token["trailer"], "the transliterated word divider"
      assert_equal "𐎟", token["utrailer"], "the cuneiform word divider"
      signs = token["signs"]
      assert_equal [%w[a 𐎀], %w[š 𐎌], %w[r 𐎗], [" ", " "], [" ", " "]],
                   signs.map { |s| [s["sign"], s["usign"]] },
                   "every slot of the word rides, transliteration beside cuneiform, spaces included"
      assert_equal %w[False False True], signs.first(3).map { |s| s["cert"] },
                   "KTU's italic-uncertainty per sign, upstream's own True/False strings verbatim"
      refute signs.last.key?("cert"), "space slots carry no certainty — absent is absent"
    end

    def test_restored_signs_ride_the_emen_lane_verbatim
      passage = passage_at("urn:nabu:cuc:ktu-1.50", "urn:nabu:cuc:ktu-1.50:I.1")
      restored = passage.annotations["tokens"].flat_map { |t| t["signs"] }.filter_map { |s| s["emen"] }
      assert_includes restored, "restored", "bracket-restored signs carry emen=restored"
    end

    def test_the_rarer_emendation_degrees_ride_verbatim
      missing = passage_at("urn:nabu:cuc:ktu-1.24", "urn:nabu:cuc:ktu-1.24:I.15")
      assert_includes missing.annotations["tokens"].flat_map { |t| t["signs"] }.filter_map { |s| s["emen"] },
                      "missing", "KTU 1.24 line 15 carries emen=missing signs"
      remark = passage_at("urn:nabu:cuc:ktu-1.54", "urn:nabu:cuc:ktu-1.54:I.6")
      assert_includes remark.annotations["tokens"].flat_map { |t| t["signs"] }.filter_map { |s| s["emen"] },
                      "remark"
      redundant = passage_at("urn:nabu:cuc:ktu-1.105", "urn:nabu:cuc:ktu-1.105:I.11")
      assert_includes redundant.annotations["tokens"].flat_map { |t| t["signs"] }.filter_map { |s| s["emen"] },
                      "redundant"
    end

    def test_alternative_readings_and_line_continuations_ride_per_sign
      alt_line = passage_at("urn:nabu:cuc:ktu-1.21", "urn:nabu:cuc:ktu-1.21:II.8")
      alt_sign = alt_line.annotations["tokens"].flat_map { |t| t["signs"] }.find { |s| s["alt"] }
      assert_equal "l", alt_sign["sign"]
      assert_equal "b", alt_sign["alt"], "upstream's alternative reading for the sign, verbatim"
      cont_line = passage_at("urn:nabu:cuc:ktu-1.43", "urn:nabu:cuc:ktu-1.43:I.2")
      cont = cont_line.annotations["tokens"].flat_map { |t| t["signs"] }.filter_map { |s| s["cont"] }
      assert_equal %w[continued continued continued], cont,
                   "the ilm signs of line 2 are marked as a line continuation"
    end

    # -- whitespace-only lines (72 corpus-wide) -------------------------------

    def test_whitespace_only_lines_are_skipped_and_recorded_in_document_metadata
      damaged = parse_urn("urn:nabu:cuc:ktu-1.7")
      assert_equal ["I.48", "I.50", "I.53"], damaged.metadata["empty_lines"],
                   "fully illegible lines render whitespace-only via {sign}: skipped, never faked, listed"
      refute_includes damaged.passages.map(&:urn), "urn:nabu:cuc:ktu-1.7:I.48"
      assert_equal ["I.5"], parse_urn("urn:nabu:cuc:ktu-1.54").metadata["empty_lines"]
      refute parse_urn("urn:nabu:cuc:ktu-1.24").metadata.key?("empty_lines"),
             "a tablet with no such lines carries no key — absent is absent"
    end

    # -- tablet metadata ------------------------------------------------------

    def test_tablet_info_rides_document_metadata_verbatim
      damaged = parse_urn("urn:nabu:cuc:ktu-1.7")
      assert_includes damaged.metadata["info"], "Tablet KTU 1.7 is very damaged",
                      "upstream's tablet_info note (the Pardee citation) verbatim"
      refute parse_urn("urn:nabu:cuc:ktu-1.24").metadata.key?("info")
      assert_equal "KTU 1.7", damaged.metadata["tablet"]
      assert_equal "KTU 1.7", damaged.title
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = cuc_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 10, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "unchanged tablets must not fake content revisions"
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

    def cuc_source
      Nabu::Store::Source.create(
        slug: "cuc", name: "CUC (Copenhagen Ugaritic Corpus)",
        adapter_class: "Nabu::Adapters::Cuc", license_class: "nc"
      )
    end
  end
end
