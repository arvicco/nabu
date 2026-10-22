# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Lasla — the LASLA corpus (Laboratoire d'Analyse
# Statistique des Langues Anciennes, Liège) as CIRCSE's LiLa-linked CoNLL-U
# Plus release (github.com/CIRCSE/LASLA): classical Latin from Plautus to
# the 2nd c. AD, semi-automatically lemmatized and morphologically
# annotated "with full manual verification" — GOLD tokens.
#
# Fixture: real upstream lines (test/fixtures/lasla/README.md) — three
# conllup files (CicQuaest whole; Catullus poem 1; Tacitus Hist. 4 trimmed)
# plus one rejected-grain specimen (a texts/*.ttl.gz RDF serialization).
module Adapters
  class LaslaTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("lasla")
    PREFIX = "urn:nabu:lasla:"
    KLASS = Nabu::Adapters::Lasla

    def conformance_adapter = KLASS.new

    def conformance_workdir = FIXTURES

    def conformance_expected_source_id = "lasla"

    def adapter = conformance_adapter

    # -- registry / manifest -------------------------------------------------------

    def test_manifest_records_the_verbatim_nc_grant
      manifest = KLASS.manifest
      assert_equal "lasla", manifest.id
      assert_equal "nc", manifest.license_class, "CC BY-NC-SA 4.0 → nc"
      assert_includes manifest.license,
                      "Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International License"
      assert_equal "lasla-conllup", manifest.parser_family
      assert_equal "https://github.com/CIRCSE/LASLA", manifest.upstream_url
    end

    # Lifecycle pin: the row ships wired: false and the gate's first real
    # sync flips it — flip this assertion together with the row.
    def test_registry_row_is_registered_unwired_manual_gold_on_the_classical_desk
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["lasla"]
      refute_nil entry, "lasla must be registered in config/sources.yml"
      assert entry.wired, "wired since the verified first sync (2026-10-21)"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "classical"
      assert_equal KLASS, entry.adapter_class
      assert_equal "gold", entry.lemma_tier, "hand-verified annotation → the default gold tier"
    end

    # -- discover -------------------------------------------------------------------

    def test_discover_yields_one_document_per_conllup_file_keyed_by_the_lasla_code
      refs = adapter.discover(FIXTURES).to_a
      assert_equal %W[#{PREFIX}Catul #{PREFIX}CicQuaest #{PREFIX}TLiv08 #{PREFIX}TacHist4], refs.map(&:id)
      tacitus = refs.last
      assert_equal({ "author" => "Tacitus", "work" => "TacHistoriae", "lasla_code" => "TacHist4" },
                   tacitus.metadata)
    end

    def test_rejected_grains_skip_by_rule_and_are_counted
      refute(adapter.discover(FIXTURES).any? { |ref| ref.path.end_with?(".ttl.gz") },
             "the texts/*.ttl.gz RDF serialization is never a document")
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_match(/ttl/, skips.notes.join)
    end

    def test_an_unexpected_file_in_the_conllup_cone_is_unrecognized
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, "conllup"))
        File.write(File.join(dir, "conllup", "notes.txt"), "stray")
        skips = adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        refute skips.clean?
      end
    end

    def test_discover_yields_nothing_on_an_empty_workdir
      Dir.mktmpdir { |dir| assert_empty adapter.discover(dir).to_a }
    end

    # -- parse ----------------------------------------------------------------------

    def test_a_document_titles_by_author_and_the_spaced_work_name
      document = parse("CicQuaest")
      assert_equal "lat", document.language
      assert_equal "Cicero — Cum Quaestor Lilybaeo Decederet Fragmenta (CicQuaest)", document.title
      assert_equal "Cicero", document.metadata["author"]
      assert_equal "CumQuaestorLilybaeoDecederetFragmenta", document.metadata["work"]
      assert_equal "CicQuaest", document.metadata["lasla_code"]
      assert_match(/BPN_t_\z/, document.metadata["lila_token_base"])
    end

    def test_passages_are_sentences_with_gold_lemmata
      document = parse("Catul")
      assert_equal 3, document.count
      first = document.first
      assert_equal "#{PREFIX}Catul:Catul-C-00-1", first.urn
      assert_equal "cui dono lepidum nouum libellum arida modo pumice expolitum", first.text
      assert_equal(%w[quis dono lepidus nouus libellus aridus modo pumex expolio],
                   first.annotations["tokens"].map { |token| token["lemma"] })
    end

    def test_no_document_carries_a_license_override
      adapter.discover(FIXTURES).each { |ref| assert_nil adapter.parse(ref).license_override }
    end

    # -- store: idempotent load + the gold lemma lane ---------------------------------

    def test_loads_idempotently_into_the_store
      db = store_test_db
      source = create_source
      first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 4, first.added
      assert_equal 0, first.errored
      assert_equal 10, db[:passages].count, "1 CicQuaest + 3 Catullus + 1 Livy + 5 Tacitus"
      second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: FIXTURES)
      assert_equal 4, second.skipped
      assert_equal 10, db[:passages].count
      assert_equal [1], db[:passages].distinct.select_map(:revision)
    ensure
      db&.disconnect
    end

    def test_lemma_rows_index_as_gold_and_morph_filters_on_ud_feats
      db = store_test_db
      Nabu::Store::Loader.new(db: db, source: create_source).load_from(adapter, workdir: FIXTURES)
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
      rows = fulltext[Nabu::Store::Indexer::LEMMA_TABLE]
      assert_equal ["gold"], rows.select_map(:tier).uniq
      search = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext)
      hits = search.run("libellus")
      assert_includes hits.map(&:urn), "#{PREFIX}Catul:Catul-C-00-1"
      token = parse("Catul").first.annotations["tokens"].find { |t| t["form"] == "libellum" }
      assert Nabu::Query::MorphFacets.match?(token, Nabu::Query::MorphFacets.parse("case=acc,number=sg"))
    ensure
      fulltext&.disconnect
      db&.disconnect
    end

    # -- fetch: sparse git cone (local git, no network) ----------------------------------

    def test_fetch_clones_only_the_conllup_cone
      Dir.mktmpdir("nabu-lasla-fetch") do |root|
        upstream = File.join(root, "upstream")
        build_upstream_repo(upstream)
        work = File.join(root, "canonical")
        lasla = adapter
        lasla.define_singleton_method(:repo_url) { upstream }
        report = lasla.fetch(work)
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert File.file?(File.join(work, "conllup", "Catullus_Catullus_Catul.conllup"))
        refute File.exist?(File.join(work, "texts")), "the ttl lane stays outside the cone"
        refute File.exist?(File.join(work, "complete_lasla.ttl.gz"))
        assert_equal ["#{PREFIX}Catul"], lasla.discover(work).map(&:id)
      end
    end

    private

    def parse(code)
      ref = adapter.discover(FIXTURES).find { |r| r.id == "#{PREFIX}#{code}" } || flunk("no ref #{code}")
      adapter.parse(ref)
    end

    def create_source
      Nabu::Store::Source.create(slug: "lasla", name: "LASLA", adapter_class: KLASS.name, license_class: "nc")
    end

    def build_upstream_repo(upstream)
      FileUtils.mkdir_p(File.join(upstream, "conllup"))
      FileUtils.cp(File.join(FIXTURES, "conllup", "Catullus_Catullus_Catul.conllup"), File.join(upstream, "conllup"))
      File.write(File.join(upstream, "README.md"), "repo readme (in the cone)")
      FileUtils.mkdir_p(File.join(upstream, "texts"))
      File.write(File.join(upstream, "texts", "Catullus.ttl.gz"), "outside the cone")
      File.write(File.join(upstream, "complete_lasla.ttl.gz"), "outside the cone")
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
    end
  end
end
