# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Vedaweb — the VedaWeb Rigveda (Cologne Center for
# eHumanities): the Zurich morphological annotation of the whole Rigveda,
# hymn = document, stanza = passage, the Leipzig labels mapped onto UD feats
# for the morph façade. Fixture: real upstream lines trimmed per hymn
# (test/fixtures/vedaweb/README.md).
module Adapters
  class VedawebTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("vedaweb")
    PREFIX = "urn:nabu:vedaweb:rv."
    KLASS = Nabu::Adapters::Vedaweb

    def conformance_adapter = KLASS.new

    def conformance_workdir = FIXTURES

    def conformance_expected_source_id = "vedaweb"

    def adapter = conformance_adapter

    # -- registry / manifest -------------------------------------------------------

    def test_manifest_records_the_zurich_layer_grant
      manifest = KLASS.manifest
      assert_equal "vedaweb", manifest.id
      assert_equal "attribution", manifest.license_class, "the zurich layer is CC BY 4.0"
      assert_includes manifest.license, "Distributed under a Creative Commons Attribution 4.0 International License."
      assert_includes manifest.license, "NonCommercial", "the excluded layers' grant is recorded too"
      assert_equal "vedaweb-tei", manifest.parser_family
    end

    # Lifecycle pin: the row ships wired: false and the gate's first real
    # sync flips it — flip this assertion together with the row.
    def test_registry_row_is_registered_unwired_manual_gold_on_the_indic_desk
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["vedaweb"]
      refute_nil entry, "vedaweb must be registered in config/sources.yml"
      refute entry.wired, "wired: false until the gate's first real sync verifies the expected counts"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "indic"
      assert_equal KLASS, entry.adapter_class
      assert_equal "gold", entry.lemma_tier, "the Zurich annotation is hand-made"
    end

    # -- discover -------------------------------------------------------------------

    def test_discover_yields_one_document_per_hymn_in_book_order
      refs = adapter.discover(FIXTURES).to_a
      assert_equal %W[#{PREFIX}1.1 #{PREFIX}1.2 #{PREFIX}2.1 #{PREFIX}2.2 #{PREFIX}8.49], refs.map(&:id)
      assert_equal({ "book" => 8, "hymn" => 49, "hymn_id" => "b08_h049", "grassmann_hymn" => 1018 },
                   refs.last.metadata)
    end

    def test_the_corpus_header_file_is_a_rejected_grain_skipped_by_rule
      refute(adapter.discover(FIXTURES).any? { |ref| ref.path.end_with?("vedaweb_corpus.tei") })
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_match(/vedaweb_corpus\.tei/, skips.notes.join)
    end

    def test_an_unexpected_tei_file_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "rigveda", "TEI"))
        File.write(File.join(dir, "rigveda", "TEI", "av_book_01.tei"), "<TEI/>")
        assert_equal 1, adapter.discovery_skips(dir).unrecognized
      end
    end

    def test_discover_yields_nothing_on_an_empty_workdir
      Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
    end

    # -- parse ----------------------------------------------------------------------

    def test_a_hymn_document_carries_its_dedication_and_numbering
      document = parse("1.1")
      assert_equal "san", document.language
      assert_equal "Rigveda 1.1 — Agni", document.title
      meta = document.metadata
      assert_equal [1, 1, 1], meta.values_at("book", "hymn", "grassmann_hymn")
      assert_equal "Agni", meta["addressee"]
      assert_equal "An Agni", meta["addressee_de"]
      assert_equal "Hymns of Madhucchandas", meta["group"]
      assert_equal "Lieder des Madhucchandas", meta["group_de"]
      assert_equal "1", meta["group_n"]
    end

    def test_passages_are_stanzas_whose_text_is_the_zurich_padas
      document = parse("1.1")
      assert_equal %W[#{PREFIX}1.1:1 #{PREFIX}1.1:2], document.map(&:urn)
      first = document.first
      assert_equal "agním īḷe puróhitaṃ\nyajñásya devám r̥tvíjam\nhótāraṃ ratnadhā́tamam", first.text
      assert_equal %w[a b c], first.annotations["padas"]
      assert_equal({ "label" => "MO", "strata" => "N" }, first.annotations["strata"]["a"])
    end

    def test_stanza_properties_ride_when_upstream_has_them
      stanza = parse("2.1").first
      assert_equal "#{PREFIX}2.1:16", stanza.urn
      assert_equal({ "grassmann" => "G" }, stanza.annotations["stanza_properties"])
      refute parse("1.1").first.annotations.key?("stanza_properties")
    end

    def test_tokens_map_the_leipzig_labels_onto_ud_feats_and_keep_them_verbatim
      token = parse("1.1").first.annotations["tokens"][1]
      assert_equal({ "id" => "a_02", "pada" => "a", "form" => "īḷe", "lemma" => "√īḍ- ~ īḷ-",
                     "lemma_ref" => "lemma_Iq_1824", "gramm" => "root",
                     "feats" => "Mood=Ind|Number=Sing|Person=1|Tense=Pres|Voice=Mid",
                     "lgr" => { "number" => "SG", "person" => "1", "mood" => "IND", "tense" => "PRS",
                                "voice" => "MED" } }, token)
    end

    def test_undecided_alternatives_map_to_ud_multivalues
      token = parse("2.2").first.annotations["tokens"].find { |t| t["form"] == "pātháḥ" }
      assert_equal "Case=Acc,Gen|Gender=Masc|Number=Plur,Sing", token["feats"]
      assert_equal({ "case" => "ACC/GEN", "gender" => "M", "number" => "SG/PL" }, token["lgr"])
    end

    def test_categories_without_a_ud_feature_ride_only_the_verbatim_record
      token = parse("2.1").first.annotations["tokens"].find { |t| t["form"] == "upasr̥jánti" }
      assert_equal "Mood=Ind|Number=Plur|Person=3|Tense=Pres|Voice=Act", token["feats"]
      assert_equal "LP", token["lgr"]["local particle"]
    end

    def test_the_morph_facade_answers_vedic_queries
      token = parse("1.1").first.annotations["tokens"][1]
      facets = Nabu::Query::MorphFacets
      assert facets.match?(token, facets.parse("mood=ind,voice=mid,person=1"))
      refute facets.match?(token, facets.parse("voice=act"))
    end

    # -- store: idempotent load + the gold lemma lane ---------------------------------

    def test_loads_idempotently_into_the_store
      db = store_test_db
      source = create_source
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 5, first.added
      assert_equal 0, first.errored
      assert_equal 6, db[:passages].count, "1.1 ×2 + 1.2 + 2.1 + 2.2 + 8.49 stanzas"
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 5, second.skipped
      assert_equal 6, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    def test_lemma_rows_index_as_gold
      db = store_test_db
      Nabu::Store::Loader.new(db: db, source: create_source).load_from(adapter, workdir: FIXTURES)
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
      refute_equal 0, rows.count
      assert_equal ["gold"], rows.select_map(:tier).uniq
      assert_equal ["san"], rows.select_map(:language).uniq
    ensure
      fulltext&.disconnect
      db&.disconnect
    end

    # -- fetch: sparse git cone (local git, no network) ----------------------------------

    def test_fetch_clones_only_the_tei_cone
      Dir.mktmpdir("nabu-vedaweb-fetch") do |root|
        upstream = File.join(root, "upstream")
        build_upstream_repo(upstream)
        work = File.join(root, "canonical")
        vedaweb = adapter
        vedaweb.define_singleton_method(:repo_url) { upstream }
        report = vedaweb.fetch(work)
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert File.file?(File.join(work, "rigveda", "TEI", "rv_book_08.tei"))
        refute File.exist?(File.join(work, "rigveda", "translations")), "the NC translation CSVs stay out"
        assert_equal ["#{PREFIX}8.49"], vedaweb.discover(work).map(&:id)
      end
    end

    private

    def parse(cite)
      ref = adapter.discover(FIXTURES).find { |r| r.id == "#{PREFIX}#{cite}" } || flunk("no ref #{cite}")
      adapter.parse(ref)
    end

    def create_source
      Nabu::Store::Source.create(slug: "vedaweb", name: "VedaWeb", adapter_class: KLASS.name,
                                 license_class: "attribution")
    end

    def build_upstream_repo(upstream)
      tei = File.join(upstream, "rigveda", "TEI")
      FileUtils.mkdir_p(tei)
      FileUtils.cp(File.join(FIXTURES, "rigveda", "TEI", "rv_book_08.tei"), tei)
      File.write(File.join(upstream, "README.md"), "repo readme (in the cone)")
      FileUtils.mkdir_p(File.join(upstream, "rigveda", "translations"))
      File.write(File.join(upstream, "rigveda", "translations", "griffith.csv"), "outside the cone")
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
    end
  end
end
