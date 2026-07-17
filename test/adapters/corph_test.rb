# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::Corph (P25-0) — CorPH / Corpus PalaeoHibernicum: the
  # first Celtic source and the first sga GOLD lemmas. Fixtures are the REAL
  # trimmed dump (texts 0003 Baile Chuinn, 0008 Paris Priscian glosses, 0077
  # Einsiedeln Computus glosses, the sentence-less 0067 Epistle of Jesus, and
  # the stray Text_ID "6" sentence — an upstream data wart kept on purpose).
  class CorphTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("corph")

    def conformance_adapter
      Nabu::Adapters::Corph.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "corph"
    end

    # -- registry -------------------------------------------------------------

    def test_registry_resolves_corph_and_manifest_agrees
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["corph"]
      refute_nil entry, "corph must be registered in config/sources.yml"
      assert entry.enabled, "live (owner sign-off 2026-07-18: 76 docs / 17,942 gold sga passages, flipped)"
      assert_equal "manual", entry.sync_policy
      assert_equal "corph", entry.adapter_class.manifest.id
      assert_equal "attribution", entry.adapter_class.manifest.license_class,
                   "MIT (Copyright (c) 2020 Chronologicon Hibernicum) → attribution"
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_text_row_sorted_by_urn
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:corph:0003
        urn:nabu:corph:0008
        urn:nabu:corph:0067
        urn:nabu:corph:0077
      ], refs.map(&:id)
      refs.each { |ref| assert ref.path.end_with?("chronhibdev_2020.sql") }
    end

    def test_discover_titles_come_from_the_text_table
      refs = conformance_adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
      assert_equal "Baile Chuinn", refs["urn:nabu:corph:0003"].metadata["title"],
                   "upstream underscores render as spaces"
      assert_equal "Einsiedeln Computus Minor Glosses", refs["urn:nabu:corph:0077"].metadata["title"]
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_dump
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- P11-7 discovery accounting -------------------------------------------

    def test_discovery_skips_counts_the_stray_orphan_sentence_by_rule
      # The real dump carries ONE sentence whose Text_ID ("6") matches no
      # TEXT row — S0006-6, an upstream wart preserved in the fixture. It can
      # never attach to a document, so the census counts it, quietly.
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule
      assert_equal 0, skips.unrecognized
      assert_predicate skips, :clean?
    end

    def test_discovery_skips_counts_empty_textual_units_by_rule
      with_doctored_dump(from: "[Íb]thuss art ier cetharchait aidchi comhnart caur conbeba muccruime.",
                         to: "") do |dir|
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 2, skips.skipped_by_rule, "the blanked sentence joins the stray orphan in the census"
      end
    end

    # -- parse: passages ------------------------------------------------------

    def test_parse_builds_passages_from_sentences_in_sort_order
      document = parse_urn("urn:nabu:corph:0003")
      assert_equal "Baile Chuinn", document.title
      assert_equal "sga", document.language
      assert_equal 35, document.size
      first = document.first
      assert_equal "urn:nabu:corph:0003:S0003-1", first.urn
      assert_equal "[Íb]thuss art ier cetharchait aidchi comhnart caur conbeba muccruime.", first.text
      assert_equal "Art will drink it after forty nights, a mighty hero. He will die at Muccruime.",
                   first.annotations["translation"]
    end

    def test_parse_skips_a_blanked_textual_unit_instead_of_crashing
      with_doctored_dump(from: "[Íb]thuss art ier cetharchait aidchi comhnart caur conbeba muccruime.",
                         to: "") do |dir|
        ref = conformance_adapter.discover(dir).find { |r| r.id == "urn:nabu:corph:0003" }
        document = conformance_adapter.parse(ref)
        assert_equal 34, document.size
        refute_includes document.map(&:urn), "urn:nabu:corph:0003:S0003-1"
      end
    end

    def test_parse_carries_locus_and_latin_context_annotations
      document = parse_urn("urn:nabu:corph:0077")
      unit3 = document.find { |passage| passage.urn.end_with?("S0077-3") }
      assert_equal ["Bisagni_and_Warntjes_2008.97", "Einsiedeln_Computus.001"], unit3.annotations["locus"]
      assert_includes unit3.text, "De diebus menseis conputandis.\r\noin Kalendae",
                      "multi-line textual units keep their upstream CRLF verbatim (canonical means canonical)"
    end

    def test_parse_a_text_row_without_sentences_is_skipped_by_rule
      ref = conformance_adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:corph:0067" }
      error = assert_raises(Nabu::DocumentSkipped) { conformance_adapter.parse(ref) }
      assert_match(/no sentences/i, error.reason)
    end

    def test_parse_document_metadata_resolves_bibliography_references
      document = parse_urn("urn:nabu:corph:0003")
      assert_equal "0003", document.metadata["text_id"]
      assert_includes document.metadata["date"], "Date range 690-720 is used in ChronHib"
      assert_includes document.metadata["edition"], "Murray & Bhreathnach 2005"
      assert document.metadata["references"].any? { |ref| ref.include?("The Kingship and Landscape of Tara") },
             "the Edition abbreviation must resolve to the full BIBLIOGRAPHY reference"
      assert_equal "Fangzhe Qiu", document.metadata["contributor"]
    end

    # -- parse: tokens (the gold layer) ---------------------------------------

    def test_tokens_carry_lemma_dil_ids_and_language
      first = parse_urn("urn:nabu:corph:0003").first
      tokens = first.annotations.fetch("tokens")
      assert_equal 13, tokens.size
      caur = tokens.find { |token| token["form"] == "caur" }
      assert_equal "caur", caur["lemma"]
      assert_equal ["8406"], caur["dil"], "the dil.ie headword id — the eDIL bridge"
      assert_equal "sga", caur["lang"]
      assert_equal "nom.sg.", caur["analysis"]
    end

    def test_tokens_strip_homonym_indices_from_the_lemma_but_keep_them
      first = parse_urn("urn:nabu:corph:0003").first
      art = first.annotations.fetch("tokens").find { |token| token["form"] == "art" }
      assert_equal "art", art["lemma"], "upstream \"art 1\" must search as art"
      assert_equal "1", art["homonym"]
    end

    def test_tokens_carry_mutation_columns_verbatim
      document = parse_urn("urn:nabu:corph:0003")
      unit10 = document.find { |passage| passage.urn.end_with?("S0003-10") }
      tokens = unit10.annotations.fetch("tokens")
      fuath = tokens.find { |token| token["form"] == "fuath" }
      assert_equal "- Len.", fuath["mut"]
      fo = tokens.find { |token| token["form"] == "fo" }
      assert_equal "- Len.", fo["causing_mut"]
    end

    def test_tokens_carry_problematic_form_flags_verbatim
      document = parse_urn("urn:nabu:corph:0008")
      unit49 = document.find { |passage| passage.urn.end_with?("S0008-49") }
      gabrde = unit49.annotations.fetch("tokens").find { |token| token["form"] == "gabrde" }
      assert_equal "Y", gabrde["problematic"]
      assert_equal "gabordae", gabrde["expected"]
      # the gloss context rides along: the glossed Latin lemma + upstream notes
      assert_equal "caprinus", unit49.annotations["latin_text"]
      assert_equal "belonging to a goat", unit49.annotations["translation"]
    end

    def test_tokens_carry_the_verbal_feature_flags_when_annotated
      first = parse_urn("urn:nabu:corph:0003").first
      beba = first.annotations.fetch("tokens").find { |token| token["form"] == "beba" }
      assert_equal "Yes", beba["augm"]
      assert_equal "intrans.", beba["trans"]
      assert_equal "baïd", beba["lemma"]
    end

    def test_tokens_keep_an_unmapped_upstream_language_verbatim
      # The corpus carries Pictish/British/… lemmata (no honest ISO code);
      # those keep the upstream Lang verbatim instead of a guessed code.
      anchor = "'www.dil.ie/8406', 'noun', 't', 'masc.', '*karut-', '', "
      with_doctored_dump(from: "#{anchor}'Early Irish'", to: "#{anchor}'Pictish'") do |dir|
        ref = conformance_adapter.discover(dir).find { |r| r.id == "urn:nabu:corph:0003" }
        caur = conformance_adapter.parse(ref).first.annotations
                                  .fetch("tokens").find { |token| token["form"] == "caur" }
        assert_nil caur["lang"]
        assert_equal "Pictish", caur["lang_source"]
      end
    end

    # -- language honesty (per document AND per passage) ----------------------

    def test_document_language_is_the_majority_over_its_tokens
      assert_equal "sga", parse_urn("urn:nabu:corph:0003").language
      assert_equal "sga", parse_urn("urn:nabu:corph:0008").language, "108 sga vs 22 lat tokens"
      assert_equal "lat", parse_urn("urn:nabu:corph:0077").language,
                   "78 lat vs 30 sga tokens — glosses on a Latin computus, honestly Latin-primary"
    end

    def test_passage_language_is_the_majority_over_the_unit_tokens
      document = parse_urn("urn:nabu:corph:0077")
      langs = document.to_h { |passage| [passage.urn.split(":").last, passage.language] }
      assert_equal "lat", langs["S0077-1"]
      assert_equal "sga", langs["S0077-4"],
                   "a pure Old Irish gloss inside a Latin-primary document stays sga (the gold-index grain)"
    end

    # -- load: idempotency + the first sga gold lemmas ------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = corph_source(catalog)
      loader = Nabu::Store::Loader.new(db: catalog, source: source)
      first = loader.load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 3, first.added
      assert_equal 1, first.skipped_by_rule, "0067 has no sentences — skipped by rule, never quarantined"
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "an unchanged dump must not fake content revisions"
    end

    def test_fixture_load_produces_sga_gold_lemma_rows
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Loader.new(db: catalog, source: corph_source(catalog))
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      lemmas = fulltext[:passage_lemmas]
      assert_operator lemmas.where(language: "sga").count, :>, 0, "THE first sga gold rows"
      assert_operator lemmas.where(language: "lat").count, :>, 0, "the Latin code-mixing indexes honestly"

      row = lemmas.where(lemma_folded: Nabu::Normalize.search_form("caur", language: "sga")).first
      refute_nil row, "expected a passage_lemmas row for caur (warrior, hero)"
      assert_equal "caur", row[:lemma_raw]
      assert_equal "urn:nabu:corph:0003:S0003-1", row[:urn]
      assert_equal "sga", row[:language]

      # end to end: lemma search finds BOTH attestations of the citation
      # form — unit 1's caur and unit 13's cur (Caincur), the lemmatization
      # doing exactly the work surface search cannot
      hits = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext).run("caur")
      assert_equal ["urn:nabu:corph:0003:S0003-1", "urn:nabu:corph:0003:S0003-13"], hits.map(&:urn)
    ensure
      fulltext&.disconnect
    end

    # -- fetch (pinned commit; local repos, no network) ------------------------

    def test_fetch_accepts_the_pinned_commit
      with_local_upstream do |repo_url, sha|
        Dir.mktmpdir do |root|
          workdir = File.join(root, "work")
          adapter = Nabu::Adapters::Corph.new(repo_url: repo_url, pinned_sha: sha)
          report = adapter.fetch(workdir)
          assert_equal sha, report.sha
          assert File.file?(File.join(workdir, "chronhibdev_2020.sql"))
        end
      end
    end

    def test_fetch_stops_loudly_when_upstream_drifts_from_the_pin
      with_local_upstream do |repo_url, sha|
        Dir.mktmpdir do |root|
          adapter = Nabu::Adapters::Corph.new(repo_url: repo_url,
                                              pinned_sha: "0" * 40)
          error = assert_raises(Nabu::FetchError) { adapter.fetch(File.join(root, "work")) }
          assert_includes error.message, sha[0, 12], "the drift message names the fetched sha"
          assert_includes error.message, "pin", "…and points at the re-pin decision"
        end
      end
    end

    def test_reference_edges_are_declared_with_the_corph_producer
      assert Nabu::Adapters::Corph.reference_edges?
      producer = Nabu::Adapters::Corph.reference_producer(catalog: :catalog, journal: :journal)
      assert_instance_of Nabu::CorphDilReferences, producer
    end

    # -- helpers ---------------------------------------------------------------

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def corph_source(_catalog)
      Nabu::Store::Source.create(
        slug: "corph", name: "CorPH", adapter_class: "Nabu::Adapters::Corph",
        license_class: "attribution"
      )
    end

    # A tmp workdir whose dump is the real fixture with ONE surgical string
    # replacement (the with_doctored_license discipline: real bytes, one
    # deliberate defect/variant).
    def with_doctored_dump(from:, to:)
      Dir.mktmpdir do |dir|
        dump = File.read(File.join(FIXTURES, "chronhibdev_2020.sql"))
        assert_includes dump, from, "the doctoring anchor must exist in the fixture"
        File.write(File.join(dir, "chronhibdev_2020.sql"), dump.sub(from, to))
        yield dir
      end
    end

    # A local bare-ish upstream holding the fixture dump — GitFetch shells
    # real git against a path URL; no network.
    def with_local_upstream
      Dir.mktmpdir do |dir|
        upstream = File.join(dir, "upstream")
        FileUtils.mkdir_p(upstream)
        FileUtils.cp(File.join(FIXTURES, "chronhibdev_2020.sql"), upstream)
        Nabu::Shell.run("git", "-C", upstream, "init", "--quiet", "--initial-branch=main")
        Nabu::Shell.run("git", "-C", upstream, "add", ".")
        Nabu::Shell.run("git", "-C", upstream, "-c", "user.email=t@e.st", "-c", "user.name=t",
                        "commit", "--quiet", "-m", "dump")
        sha = Nabu::Shell.run("git", "-C", upstream, "rev-parse", "HEAD").strip
        yield upstream, sha
      end
    end
  end
end
