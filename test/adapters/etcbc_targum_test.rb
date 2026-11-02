# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::EtcbcTargum — the ETCBC Targum Corpus (Text-Fabric
  # tf/0.1, github.com/ETCBC/targum) over the text-fabric family:
  # document = text node (one manuscript witness under one editorial
  # view), passage = verse, text = upstream's own verse line (line_utf8)
  # byte-verbatim (arc rides the hbo/arc NFC exemption). Fixtures are
  # gap-anchored tf/0.1 slices — three whole texts (Fragment Targum N,
  # Cairo Genizah fragments DD and X) and Genesis 2 of both Neofiti views
  # — see test/fixtures/etcbc-targum/README.md for the trim recipe.
  class EtcbcTargumTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("etcbc-targum")
    URN = "urn:nabu:etcbc-targum:"

    def conformance_adapter
      Nabu::Adapters::EtcbcTargum.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "etcbc-targum"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_etcbc_targum_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["etcbc-targum"]
      refute_nil entry, "etcbc-targum must be registered in config/sources.yml"
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
      assert_equal "etcbc-targum", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_with_the_readme_and_feature_header_grant
      manifest = Nabu::Adapters::EtcbcTargum.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "CC BY-NC 4.0"
      assert_includes manifest.license, "@license=Attribution-NonCommercial 4.0 International",
                      "every tf/0.1 feature header carries the grant verbatim"
      assert_equal "text-fabric", manifest.parser_family
    end

    # -- census (otype.tf rides the fixture WHOLE — the census of record) -----

    def test_the_whole_otype_census
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "0.1"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal 624_612, counts["word"]
      assert_equal 47, counts["text"], "47 manuscript texts — Neofiti counted twice (two views)"
      assert_equal 91, counts["book"]
      assert_equal 25_447, counts["verse"]
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_text_node
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %W[
        #{URN}cairo_genizah_targum_fragment_dd
        #{URN}cairo_genizah_targum_fragment_x
        #{URN}fragment_targum_n
        #{URN}neofiti_base
        #{URN}neofiti_full
        #{URN}pseudo_jonathan
      ], refs.map(&:id), "text names verbatim"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_text_names_mint_url_safe_slugs
      assert_equal "cairo_genizah_targum_fragment_aa_2",
                   Nabu::Adapters::EtcbcTargum.slug("cairo_genizah_targum_fragment_aa(2)"),
                   "the one parenthesized text name folds to an underscore suffix"
      assert_equal "neofiti_full", Nabu::Adapters::EtcbcTargum.slug("neofiti_full")
    end

    # -- documents ------------------------------------------------------------

    def test_documents_carry_witness_metadata
      full = parse_urn("#{URN}neofiti_full")
      assert_equal "arc", full.language
      assert_equal "Targum Neofiti 1 (full text)", full.title
      assert_equal "neofiti_1", full.metadata["manuscript"], "manuscript.tf verbatim"
      assert_equal "full_text", full.metadata["view"], "view.tf verbatim"
      assert_equal "MS Neofiti, no. 1", full.metadata["shelfmark"]
      assert_equal ["Genesis"], full.metadata["books"]
      base = parse_urn("#{URN}neofiti_base")
      assert_equal "base_raw", base.metadata["view"]
      assert_equal "Targum Neofiti 1 (base text)", base.title
    end

    def test_genizah_fragments_name_their_findspot_and_base_edition
      dd = parse_urn("#{URN}cairo_genizah_targum_fragment_dd")
      assert_equal "Cairo Genizah Targum Fragment DD", dd.title
      assert_equal "Cairo Genizah", dd.metadata["place"], "the fragments' findspot, upstream's own collection name"
      assert_equal "Klein, 1992", dd.metadata["base_edition"]
      refute parse_urn("#{URN}neofiti_full").metadata.key?("place"), "no findspot claim without upstream's"
      assert_equal "Klein, 1980", parse_urn("#{URN}fragment_targum_n").metadata["base_edition"]
      assert_equal "Nürnberg Stadtbibliothek, Solg. 2,2",
                   parse_urn("#{URN}fragment_targum_n").metadata["shelfmark"]
    end

    def test_an_unknown_text_name_is_a_parse_error_never_a_guess
      assert_raises(Nabu::ParseError) { Nabu::Adapters::EtcbcTargum.witness_info("targum_sheni") }
    end

    # -- passages -------------------------------------------------------------

    def test_passages_are_verses_with_book_chapter_verse_urns
      full = parse_urn("#{URN}neofiti_full")
      assert_equal 25, full.size, "Genesis 2 — 25 verses"
      assert_equal "#{URN}neofiti_full:genesis.2.1", full.passages.first.urn
      assert_equal "#{URN}neofiti_full:genesis.2.25", full.passages.last.urn
      assert_equal 7, parse_urn("#{URN}fragment_targum_n").size
    end

    def test_verse_text_is_upstreams_own_line_byte_verbatim
      passage = passage_at("#{URN}neofiti_base", "#{URN}neofiti_base:genesis.2.1")
      assert_equal "ואשׁלמו ברית שׁמיא וארעא וכל חלוותהון", passage.text
      assert_equal "arc", passage.language
      full = passage_at("#{URN}neofiti_full", "#{URN}neofiti_full:genesis.2.1")
      assert_equal "ואשׁלמו בריתחילוות שׁמיא וארעא וכל חלוותהון", full.text,
                   "the full view's interlinear variant rides inline exactly as line_utf8 ships it"
      assert_equal "W>CLMW BRJTXJLWWT CMJ> W>R<> WKL XLWWTHWN", full.annotations["line"],
                   "the ETCBC-transliterated twin rides annotations verbatim"
    end

    def test_a_repeated_address_gets_the_collision_suffix
      dd = parse_urn("#{URN}cairo_genizah_targum_fragment_dd")
      urns = dd.map(&:urn)
      assert_includes urns, "#{URN}cairo_genizah_targum_fragment_dd:deuteronomy.24.6"
      assert_includes urns, "#{URN}cairo_genizah_targum_fragment_dd:deuteronomy.24.6:b2",
                      "the second record at one address (crossref same_witness) is kept, never merged"
      assert_equal 28, dd.size
    end

    def test_a_fragment_interleaving_books_keeps_slot_order
      x = parse_urn("#{URN}cairo_genizah_targum_fragment_x")
      assert_equal %w[exodus.13.17 genesis.49.18 genesis.38.25],
                   x.first(3).map { |p| p.urn.split(":").last },
                   "a festival compilation alternates Exodus and Genesis — order is the manuscript's"
      assert_equal %w[Exodus Genesis], x.metadata["books"]
    end

    def test_tokens_carry_the_word_grain_features_verbatim
      passage = passage_at("#{URN}neofiti_full", "#{URN}neofiti_full:genesis.2.1")
      variant = passage.annotations["tokens"].find { |t| t["n"] == 339_251 }
      assert_equal "חילוות", variant["form"]
      assert_equal "חיל", variant["lex_utf8"], "the gold lemma"
      assert_equal "force, army", variant["gloss"]
      assert_equal "subs", variant["sp"]
      assert_equal "variant", variant["segment_type"], "the editorial layer rides the token"
      assert_equal 1, variant["reading"], "a competing reading's rank, 0 being the printed one"
      first = passage.annotations["tokens"].first
      refute first.key?("segment_type"), "unmarked_text is the default — absent"
      refute first.key?("reading"), "reading 0 is the default — absent"
      assert_equal 339_248, first["n"], "the stable TF slot"
    end

    def test_an_ellipsis_only_verse_record_is_skipped_by_rule_and_named
      # 17 verse records corpus-wide (PJ 8, Neofiti full 9) hold nothing
      # but the edition's omission dots: their line is "..." and the
      # converter rendered each "." as U+05BC (the ETCBC dagesh letter), so
      # line_utf8 is a bare run of dageshes with no letter to carry them.
      pj = parse_urn("#{URN}pseudo_jonathan")
      assert_equal %W[#{URN}pseudo_jonathan:genesis.1.21 #{URN}pseudo_jonathan:genesis.1.23], pj.map(&:urn)
      assert_equal ["genesis.1.22"], pj.metadata["omitted_verses"],
                   "the skipped address is named on the document, never dropped silently"
      refute parse_urn("#{URN}neofiti_full").metadata.key?("omitted_verses")
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "etcbc-targum", name: "ETCBC Targum Corpus",
        adapter_class: "Nabu::Adapters::EtcbcTargum", license_class: "nc"
      )
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 6, first.added
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

    def passage_at(document_urn, passage_urn)
      passage = parse_urn(document_urn).find { |p| p.urn == passage_urn }
      refute_nil passage, "expected #{passage_urn} in #{document_urn}"
      passage
    end
  end
end
