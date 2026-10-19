# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::StgallPriscian — the St Gall Priscian glosses (St
  # Gallen, Stiftsbibliothek 904, AD 850–1), the digital edition's MySQL
  # dump composed through the corph-sql parser family. Fixtures are the REAL
  # dump trimmed line-verbatim to 26 glosses on three manuscript pages (1, 2,
  # 51) with their Priscian lines, word analyses and the whole gloss-type
  # table (test/fixtures/stgall-priscian/README.md).
  class StgallPriscianTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("stgall-priscian")
    PREFIX = "urn:nabu:stgall-priscian:"

    def conformance_adapter
      Nabu::Adapters::StgallPriscian.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "stgall-priscian"
    end

    # -- registry ---------------------------------------------------------------

    def test_registry_resolves_the_source_wired_on_the_celtic_desk
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["stgall-priscian"]
      refute_nil entry, "stgall-priscian must be registered in config/sources.yml"
      assert entry.wired, "first real sync verified 2026-10-14 (239 docs / 13,395 passages)"
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "celtic"
      manifest = entry.adapter_class.manifest
      assert_equal "stgall-priscian", manifest.id
      assert_equal "attribution", manifest.license_class, "MIT (Copyright (c) 2023 Pádraic Moran) → attribution"
      assert_includes manifest.license, "Copyright (c) 2023 Pádraic Moran"
      assert_equal "corph-sql", manifest.parser_family, "composes the house SQL-dump walker"
    end

    # -- discover ---------------------------------------------------------------

    def test_discover_yields_one_document_per_manuscript_page_in_page_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %W[#{PREFIX}p1 #{PREFIX}p2 #{PREFIX}p51], refs.map(&:id)
      refs.each { |ref| assert ref.path.end_with?("db_priscian_v2.sql") }
      assert_equal 51, refs.last.metadata["ms_page"]
    end

    def test_discover_yields_nothing_without_the_dump
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    # -- parse: document grain --------------------------------------------------

    def test_a_page_document_carries_the_manuscript_dating_and_origin
      document = parse("p1")
      assert_equal "St Gall Priscian glosses, p. 1", document.title
      meta = document.metadata
      assert_equal 1, meta["ms_page"]
      assert_equal "St Gallen, Stiftsbibliothek, Cod. Sang. 904", meta["manuscript"]
      assert_equal({ "not_before" => 850, "not_after" => 851 },
                   meta["date"].slice("not_before", "not_after"),
                   "the manuscript's copying date, as upstream states it")
      assert_includes meta["date"]["raw"], "850–1"
      assert_equal "Ireland (?)", meta["orig_place"], "upstream's hedge: 'probably in Ireland'"
      assert_equal "St Gallen, Stiftsbibliothek", meta["repository"], "the holding library — metadata only"
      assert_equal "Latn", meta["script"]
      assert_equal "https://www.e-codices.unifr.ch/en/csg/0904/1", meta["images"]
      assert_equal [0], meta["priscian_books"]
    end

    def test_passages_are_the_page_glosses_in_edition_order_cited_by_upstream_id
      document = parse("p1")
      assert_equal [1, 2, 8, 9, 13, 18, 23, 31].map { |id| "#{PREFIX}p1:#{id}" }, document.passages.map(&:urn)
      assert_equal (0..7).to_a, document.passages.map(&:sequence)
    end

    def test_document_language_is_the_majority_of_its_lexical_glosses
      assert_equal "sga", parse("p1").language, "five Old Irish glosses against one Latin (symbols abstain)"
      assert_equal "lat", parse("p2").language, "five Latin glosses against three Old Irish (one symbol abstains)"
      assert_equal "sga", parse("p51").language
    end

    # -- parse: the gloss text --------------------------------------------------

    def test_an_old_irish_gloss_reads_as_the_gloss_with_expansions_inline
      gloss = passage("p1", 13)
      assert_equal "sga", gloss.language
      assert_equal "(m.l.): .i. attá di ṡeirc la laitnori inna grec co·seichetar cid a comroicniu", gloss.text
      a = gloss.annotations
      assert_equal ["imitari"], a["terms"], "the glossed Latin word rides annotations, never the text"
      assert_equal "i.e. the Latin grammarians have such love for the Greeks that they follow even their errors",
                   a["translation"]
      assert_equal "1a14", a["ms_ref"]
      assert_equal "f", a["code"]
      assert_equal 13, a["gloss_id"]
      assert_equal "1a2", a["thesaurus"], "Thesaurus Palaeohibernicus ii, upstream's display form of 001a02"
      assert_equal 49, a["thesaurus_page"]
      assert_equal "GL II 1,5", a["keil"]
      assert_equal "etiam quosdam errores eorum amore doctorum deceptos imitari, in quibus", a["priscian"]
      assert_equal ["543"], a["types"]
      assert_equal ["glosses elucidating the main text"], a["type_labels"]
      assert_equal 1, a["irish"], "upstream's flag, verbatim"
      assert_equal "https://www.stgallpriscian.ie/index.php?kV=2&kP=1&id=13#hi", a["url"]
    end

    def test_old_irish_word_analyses_become_gold_tokens
      tokens = passage("p1", 13).annotations["tokens"]
      assert_equal 14, tokens.size
      assert_equal({ "form" => "at", "lemma" => "ad", "homonym" => "1", "lang" => "sga",
                     "dil_headword" => "ad-", "wordclass" => "particle", "subclass" => "preverb",
                     "analysis" => "*ad-tā- (*bw-)" }, tokens.first,
                   "upstream homonym indices split off the lemma (the corph precedent)")
      assert_equal "ṡe(i)rc", tokens[3]["form"]
      assert_equal "serc", tokens[3]["lemma"]
      assert_equal "love", tokens[3]["meaning"]
    end

    def test_a_latin_flagged_gloss_whose_words_are_analysed_old_irish_is_old_irish
      gloss = passage("p1", 9) # ".i. libardaib" — irish=0 upstream, one analysed Old Irish word
      assert_equal "sga", gloss.language
      assert_equal ".i. libardaib", gloss.text
      assert_equal 0, gloss.annotations["irish"]
      assert_equal "analysis", gloss.annotations["language_basis"]
    end

    def test_a_latin_gloss_with_one_irish_word_stays_latin
      gloss = passage("p2", 92) # ".i. ut accentus. d hí c" — one analysed form among five words
      assert_equal "lat", gloss.language
      refute gloss.annotations.key?("language_basis")
      assert_equal 1, gloss.annotations["tokens"].size, "the Irish element still rides as a token"
    end

    def test_upstreams_irish_flag_wins_even_on_a_latin_looking_gloss
      gloss = passage("p51", 4227) # "parcus" on "frugi", flagged Irish upstream (Thes. ref "105")
      assert_equal "sga", gloss.language
      assert_equal "parcus", gloss.text
      assert_equal "105", gloss.annotations["thesaurus"], "a malformed upstream ref rides as given"
    end

    def test_a_construe_mark_gloss_reads_through_its_anchor_words
      gloss = passage("p1", 2)
      assert_equal "omnis: . → (ibid.) eloquentiae: .", gloss.text
      assert gloss.annotations["construe"], "no gloss words — the symbol links Priscian's words"
      assert_equal %w[omnis eloquentiae], gloss.annotations["terms"]
      assert_equal "lat", gloss.language
    end

    def test_editorial_braces_ride_as_notes_not_text
      gloss = passage("p1", 8)
      assert_equal "*inve[nio]: .- → (1a9=1,3) et: .-", gloss.text
      assert_equal ["= K 2r3-5 omnis .., > invenio .., > et ..,"], gloss.annotations["notes"]
      assert_equal "certis", passage("p2", 84).text
      assert_equal ["= E 3v21"], passage("p2", 84).annotations["notes"]
    end

    def test_scribal_deletions_and_editorial_supplements_keep_their_marks
      deleted = passage("p2", 71)
      assert_equal ".i. in⟦d⟧t airdircus", deleted.text, "the house erasure brackets"
      assert_equal "sga", deleted.language, "two words, two analysed Old Irish forms"
      assert_equal "(m.l.): issí tra in dias-sa ro·⟨s⟩echestar-som", passage("p1", 23).text
    end

    def test_a_term_only_gloss_reads_as_its_term
      gloss = passage("p51", 4200)
      assert_equal "cautéla", gloss.text
      assert gloss.annotations["construe"]
      refute gloss.annotations.key?("code")
    end

    def test_a_symbol_numeral_gloss_is_a_construe_gloss
      gloss = passage("p2", 120)
      assert_equal "tertius decimus: XIII", gloss.text
      assert gloss.annotations["construe"]
    end

    # The full dump's rarer shapes, on real fixture bytes with one variant
    # each (two <add hand="C"> tags; five {{212}}-style double-brace markers
    # inside a gloss; one stray "}" in gloss 7464 — upstream's typo for ")").
    def test_a_tag_with_attributes_unwraps_like_any_other
      with_doctored_dump(from: "<gloss>in méit-so</gloss>",
                         to: '<gloss>in <add hand="C">méit</add>-so</gloss>') do |dir|
        assert_equal "in méit-so", passage("p1", 18, workdir: dir).text
      end
    end

    def test_double_braces_inside_a_gloss_are_one_note_and_a_stray_closer_stays_text
      with_doctored_dump(from: "<gloss>certis</gloss>", to: "<gloss>certis {{212}} certa}</gloss>") do |dir|
        gloss = passage("p2", 84, workdir: dir)
        assert_equal "certis certa}", gloss.text, "an unmatched closer is upstream text, verbatim"
        assert_equal ["{212}", "= E 3v21"], gloss.annotations["notes"]
      end
    end

    # -- the known-gloss snippet -------------------------------------------------

    def test_the_known_gloss_in_meit_so
      gloss = passage("p1", 18)
      assert_equal "in méit-so", gloss.text
      assert_equal "so much", gloss.annotations["translation"]
      assert_equal ["tanto"], gloss.annotations["terms"]
      assert_equal "1a3", gloss.annotations["thesaurus"]
    end

    # -- load: idempotency + sga gold lemmas ------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = stgall_source
      Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true)
      counts = [catalog[:documents].count, catalog[:passages].count]
      assert_equal [3, 26], counts
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source).load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "an unchanged dump must not fake content revisions"
    end

    def test_fixture_load_produces_sga_gold_lemma_rows
      catalog = store_test_db
      fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      Nabu::Store::Loader.new(db: catalog, source: stgall_source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext)

      row = LemmaUrnView.of(fulltext, catalog)
                        .where(lemma_folded: Nabu::Normalize.search_form("serc", language: "sga")).first
      refute_nil row, "the analysed ṡe(i)rc indexes under its headword serc"
      assert_equal "#{PREFIX}p1:13", row[:urn]
      assert_equal "sga", row[:language]
    ensure
      fulltext&.disconnect
    end

    # -- fetch (local git only, no network) -------------------------------------

    def test_fetch_sparse_clones_only_the_dump_and_the_edition_prose
      Dir.mktmpdir("nabu-stgall-fetch") do |root|
        upstream = File.join(root, "upstream")
        FileUtils.mkdir_p(File.join(upstream, "images", "keil"))
        FileUtils.cp(File.join(FIXTURES, "db_priscian_v2.sql"), upstream)
        File.write(File.join(upstream, "LICENSE"), "MIT License\n")
        File.write(File.join(upstream, "home_text.php"), "<p>850–1</p>\n")
        File.write(File.join(upstream, "images", "keil", "Keil_v2_001.gif"), "GIF89a")
        Nabu::Shell.run("git", "init", "-q", upstream)
        git(upstream, "add", ".")
        git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "-c", "gc.auto=0",
            "-c", "maintenance.auto=false", "commit", "-q", "-m", "seed")

        work = File.join(root, "canonical")
        adapter = conformance_adapter
        adapter.define_singleton_method(:repo_url) { upstream }
        report = adapter.fetch(work)

        assert_equal git(upstream, "rev-parse", "HEAD"), report.sha
        assert File.file?(File.join(work, "db_priscian_v2.sql"))
        assert File.file?(File.join(work, "LICENSE"))
        assert File.file?(File.join(work, "home_text.php"))
        refute File.exist?(File.join(work, "images")), "the edition scans stay out"
        assert_equal %W[#{PREFIX}p1 #{PREFIX}p2 #{PREFIX}p51], adapter.discover(work).map(&:id)
      end
    end

    private

    def parse(page, workdir: FIXTURES)
      adapter = conformance_adapter
      ref = adapter.discover(workdir).find { |r| r.id == "#{PREFIX}#{page}" }
      adapter.parse(ref)
    end

    def passage(page, id, workdir: FIXTURES)
      parse(page, workdir: workdir).passages.find { |p| p.urn == "#{PREFIX}#{page}:#{id}" } or
        flunk "no gloss #{id} on #{page}"
    end

    # A tmp workdir whose dump is the real fixture with ONE surgical string
    # replacement (the corph with_doctored_dump discipline).
    def with_doctored_dump(from:, to:)
      Dir.mktmpdir do |dir|
        dump = File.read(File.join(FIXTURES, "db_priscian_v2.sql"))
        assert_includes dump, from, "the doctoring anchor must exist in the fixture"
        File.write(File.join(dir, "db_priscian_v2.sql"), dump.sub(from, to))
        yield dir
      end
    end

    def stgall_source
      Nabu::Store::Source.create(slug: "stgall-priscian", name: "St Gall Priscian Glosses",
                                 adapter_class: "Nabu::Adapters::StgallPriscian", license_class: "attribution")
    end

    def git(dir, *)
      Nabu::Shell.run("git", "-C", dir, *).strip
    end
  end
end
