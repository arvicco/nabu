# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::DtucphSp — the CACCHT Samaritan Pentateuch (Text-Fabric
  # tf/7.5.0, github.com/DT-UCPH/sp, pinned at release tag v7.5.0) over the
  # text-fabric family: document = book, passage = verse, text = the
  # corpus's own {sign} rendering (otext text-orig-full), tokens word-grain
  # (words are NON-slot nodes here — the slots are consonantal signs, the
  # cuc shape). Fixtures are gap-anchored tf/7.5.0 slices — see
  # test/fixtures/dtucph-sp/README.md for the slices and the trim recipe.
  class DtucphSpTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("dtucph-sp")
    URN = "urn:nabu:dtucph-sp:"
    DUBLIN = "MS Dublin Chester Beatty Library 751"
    GARIZIM = "MS Garizim 1"

    def conformance_adapter
      Nabu::Adapters::DtucphSp.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "dtucph-sp"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_dtucph_sp_unwired_until_its_first_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["dtucph-sp"]
      refute_nil entry, "dtucph-sp must be registered in config/sources.yml"
      refute entry.wired, "wired: false until the first real sync is verified (checklist step 6)"
      assert_equal "manual", entry.sync_policy
      assert_equal "dtucph-sp", entry.adapter_class.manifest.id
    end

    def test_manifest_is_nc_with_the_readme_and_feature_header_grant
      manifest = Nabu::Adapters::DtucphSp.manifest
      assert_equal "nc", manifest.license_class
      assert_includes manifest.license, "CC BY-NC 4.0"
      assert_includes manifest.license,
                      "@licence=Creative Commons Attribution-NonCommercial 4.0 International License",
                      "every tf/7.5.0 feature header carries the grant verbatim (British spelling of the key)"
      assert_includes manifest.license, "10.5281/zenodo.7734632"
      assert_equal "text-fabric", manifest.parser_family
    end

    def test_the_pin_is_the_release_tag_and_its_dataset_directory
      assert_equal "v7.5.0", Nabu::Adapters::DtucphSp::RELEASE_TAG
      assert_equal File.join("tf", "7.5.0"), Nabu::Adapters::DtucphSp::TF_DIR,
                   "the tag and the version directory move together — one re-pin, never two"
    end

    # -- census (otype.tf rides the fixture WHOLE — the census of record) -----

    def test_the_whole_otype_census
      dataset = Nabu::Adapters::TextFabric::Dataset.new(File.join(FIXTURES, "tf", "7.5.0"))
      counts = dataset.type_ranges.keys.to_h { |type| [type, dataset.type_count(type)] }
      assert_equal({ "sign" => 399_393, "book" => 5, "chapter" => 187, "verse" => 5_841,
                     "word" => 114_891, "clause" => 21_736, "clause_atom" => 22_530,
                     "phrase" => 66_043, "phrase_atom" => 69_905 }, counts)
      assert_equal 399_393, dataset.max_slot, "the slot type is the consonantal sign, not the word"
    end

    def test_every_upstream_feature_file_is_carried_or_declined_with_a_reason
      # The fixture keeps ALL 50 tf/7.5.0 files (trimmed), so this is the
      # reconciliation against upstream's own file list at the pin.
      files = Dir[File.join(FIXTURES, "tf", "7.5.0", "*.tf")].map { |path| File.basename(path, ".tf") }.sort
      assert_equal 50, files.size
      routed = Nabu::Adapters::DtucphSp::TOKEN_FEATURES + Nabu::Adapters::DtucphSp::DECLINED_FEATURES.keys
      assert_equal files, routed.sort, "a new upstream feature must be routed (token) or declined (reason)"
      assert_empty Nabu::Adapters::DtucphSp::TOKEN_FEATURES & Nabu::Adapters::DtucphSp::DECLINED_FEATURES.keys
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_book_node_on_osis_stems
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %W[#{URN}deut #{URN}gen], refs.map(&:id),
                   "the fixture keeps the Genesis and Deuteronomy book nodes; urns use the bhsa/oshb OSIS stems"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_pinned_dataset
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_an_unknown_book_name_is_a_parse_error_never_a_guess
      assert_raises(Nabu::ParseError) { Nabu::Adapters::DtucphSp.osis!("Jubilees", "test") }
    end

    # -- documents ------------------------------------------------------------

    def test_documents_carry_book_title_language_and_witnesses
      gen = parse_urn("#{URN}gen")
      assert_equal "Genesis", gen.title
      assert_equal "hbo", gen.language
      assert_equal [DUBLIN], gen.metadata["manuscripts"]
      assert_equal "Genesis", gen.metadata["book"]
      deut = parse_urn("#{URN}deut")
      assert_equal [DUBLIN, GARIZIM], deut.metadata["manuscripts"],
                   "Deuteronomy is the one book two manuscripts witness (the switch at 32:36)"
    end

    # -- passages -------------------------------------------------------------

    def test_passages_are_verses_with_chapter_verse_urns
      gen = parse_urn("#{URN}gen")
      assert_equal 19, gen.size
      assert_equal "#{URN}gen:1.1", gen.first.urn
      assert_equal "#{URN}gen:31.47", gen.passages.last.urn
      assert_equal %W[#{URN}deut:32.35 #{URN}deut:32.36 #{URN}deut:32.37 #{URN}deut:34.12],
                   parse_urn("#{URN}deut").map(&:urn)
    end

    def test_verse_text_is_the_sign_rendering_verbatim
      passage = passage_at("#{URN}gen", "#{URN}gen:1.1")
      assert_equal "בראשית ברא אלהים את השמים ואת הארץ", passage.text,
                   "otext text-orig-full = {sign}: the manuscript's consonants, no shin/sin dots"
      assert_equal "hbo", passage.language
      assert_equal passage.text.unicode_normalize(:nfc), passage.text
    end

    def test_tokens_are_words_whose_form_and_trailer_rebuild_the_text
      passage = passage_at("#{URN}gen", "#{URN}gen:1.1")
      tokens = passage.annotations["tokens"]
      assert_equal 11, tokens.size, "ETCBC segmentation: prefixed preposition, article and conjunction are words"
      assert_equal(%w[ב ראשית], tokens.first(2).map { |t| t["form"] })
      refute tokens.first.key?("trailer"), "the proclitic ב joins its host — no trailer"
      assert_equal passage.text, tokens.map { |t| "#{t['form']}#{t['trailer']}" }.join.rstrip
      word = tokens[1]
      assert_equal 405_428, word["n"], "the stable TF word node (slots are signs)"
      assert_equal "ראשית", word["form"]
      assert_equal "ראשׁית", word["g_cons_utf8"],
                   "the ETCBC dotted lane rides verbatim — U+FB2A presentation-form shin, hbo NFC-exempt"
      assert_equal "R>CJT/", word["lex"]
      assert_equal "beginning", word["gloss"]
      assert_equal "subs", word["sp"]
      assert_equal "rā̊šət", word["phono_transcr"], "the Samaritan reading tradition (Ben-Hayyim) per word"
      assert_equal "True", word["mt_feat"], "upstream's own flag: features imposed from the MT"
      assert_equal "hbo", word["lang"]
      refute word.key?("language"), "language rides as lang"
      verb = tokens[2]
      assert_equal "qal", verb["vs"], "verbal stem — upstream annotates it in Genesis only"
      assert_equal "perf", verb["vt"]
    end

    def test_the_two_aramaic_words_ride_arc_and_the_verse_stays_hebrew
      passage = passage_at("#{URN}gen", "#{URN}gen:31.47")
      aramaic = passage.annotations["tokens"].select { |t| t["lang"] == "arc" }
      assert_equal [422_873, 422_874], aramaic.map { |t| t["n"] }, "Jegar-sahadutha (Gen 31:47)"
      assert_equal "hbo", passage.language, "majority vote, the bhsa rule"
    end

    def test_tal_florentin_readings_ride_the_first_word_of_the_stretch
      passage = passage_at("#{URN}gen", "#{URN}gen:1.12")
      word = passage.annotations["tokens"].find { |t| t["n"] == 405_625 }
      assert_equal "ותוציא", word["var_ft_utf8"]
      assert_equal "WTWYJ>", word["var_ft"]
      assert_equal "plene_defective", word["var_ft_type"]
      assert_equal 2, word["var_ft_span"], "T&F's reading replaces two word nodes from here"
      assert_equal "ו", word["form"], "our text is unchanged — the reading is an annotation"
      lacking = passage_at("#{URN}gen", "#{URN}gen:26.7").annotations["tokens"].find { |t| t["n"] == 418_646 }
      assert_equal "-", lacking["var_ft_utf8"], "upstream's '-': T&F have no words here"
    end

    def test_tal_florentin_verse_numbering_rides_the_passage
      passage = passage_at("#{URN}gen", "#{URN}gen:6.20")
      assert_equal "6:19, 6:20", passage.annotations["verse_ft"]
      refute passage_at("#{URN}gen", "#{URN}gen:1.1").annotations.key?("verse_ft")
    end

    def test_grouped_additions_stay_one_verse
      passage = passage_at("#{URN}gen", "#{URN}gen:30.36")
      assert_equal 90, passage.annotations["tokens"].size,
                   "upstream groups the 30:36a-c additions under verse 36 (README)"
    end

    def test_grammar_notes_ride_tokens_and_spans
      word = passage_at("#{URN}gen", "#{URN}gen:2.23").annotations["tokens"].find { |t| t["n"] == 406_550 }
      assert_match(/\ASchorch 2004, p\. 89:/, word["grammar_note"])
      span = passage_at("#{URN}gen", "#{URN}gen:14.20").annotations["spans"].find { |s| s["node"] == 568_242 }
      assert_match(/\ASchorch 2004, p\. 127:/, span["grammar_note"])
    end

    # -- spans ----------------------------------------------------------------

    def test_clause_and_phrase_spans_index_into_the_word_tokens
      passage = passage_at("#{URN}gen", "#{URN}gen:1.7")
      spans = passage.annotations["spans"]
      assert_equal %w[clause phrase], spans.map { |s| s["type"] }.uniq.sort
      clause = spans.find { |s| s["node"] == 520_337 }
      assert_equal 2, clause["ranges"].size, "a discontinuous clause keeps both pieces"
      refute clause.key?("partial")
      phrase = spans.find { |s| s["node"] == 564_649 }
      assert_equal 2, phrase["ranges"].size
      assert phrase.key?("typ") && phrase.key?("function"), "phrase type and function ride the span"
      tokens = passage.annotations["tokens"].size
      assert(spans.all? { |s| s["ranges"].flatten.all? { |i| i.between?(0, tokens - 1) } })
    end

    def test_a_clause_crossing_verses_rides_both_as_partial
      first = passage_at("#{URN}gen", "#{URN}gen:6.19").annotations["spans"].find { |s| s["node"] == 520_891 }
      second = passage_at("#{URN}gen", "#{URN}gen:6.20").annotations["spans"].find { |s| s["node"] == 520_891 }
      assert first["partial"]
      assert second["partial"]
    end

    # -- witnesses ------------------------------------------------------------

    def test_deuteronomy_passages_name_their_manuscript_at_the_switch
      deut = parse_urn("#{URN}deut").to_h { |p| [p.urn.split(":").last, p.annotations["manuscripts"]] }
      assert_equal [DUBLIN], deut["32.35"]
      assert_equal [DUBLIN, GARIZIM], deut["32.36"], "Dublin to 32:36a, Garizim 1 from 32:36b"
      assert_equal [GARIZIM], deut["32.37"]
      assert_equal [GARIZIM], deut["34.12"]
      refute passage_at("#{URN}gen", "#{URN}gen:1.1").annotations.key?("manuscripts"),
             "a single-witness book names its manuscript on the document only"
    end

    def test_manuscript_header_drift_is_a_parse_error
      Dir.mktmpdir do |dir|
        tf = File.join(dir, "tf", "7.5.0")
        FileUtils.mkdir_p(tf)
        FileUtils.cp_r(Dir[File.join(FIXTURES, "tf", "7.5.0", "*.tf")], tf)
        otype = File.join(tf, "otype.tf")
        File.write(otype, File.read(otype).sub("MS Garizim 1 (Deut 32:36b-34)", "MS Garizim 1 (Deut 31-34)"))
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "#{URN}deut" }
        assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      end
    end

    # -- fetch (local git only, no network) -------------------------------------

    def test_fetch_clones_at_the_pinned_release_tag
      Dir.mktmpdir do |root|
        upstream = File.join(root, "upstream")
        make_tagged_repo(upstream)
        workdir = File.join(root, "canonical")
        adapter = conformance_adapter
        adapter.define_singleton_method(:repo_url) { upstream }
        report = adapter.fetch(workdir)
        assert File.file?(File.join(workdir, "tf", "7.5.0", "otype.tf"))
        refute File.exist?(File.join(workdir, "notebooks")), "the sparse cone keeps only the pinned dataset"
        tagged = Nabu::Shell.run("git", "-C", upstream, "rev-parse", "v7.5.0^{commit}").strip
        assert_equal tagged, report.sha, "fetch must land on the pinned tag, not the moving default branch"
      end
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = Nabu::Store::Source.create(
        slug: "dtucph-sp", name: "CACCHT Samaritan Pentateuch",
        adapter_class: "Nabu::Adapters::DtucphSp", license_class: "nc"
      )
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 2, first.added
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

    # A local upstream: commit 1 tagged v7.5.0, commit 2 ahead of it on the
    # default branch (upstream main moves between releases — the pin must
    # not follow it).
    def make_tagged_repo(dir)
      FileUtils.mkdir_p(File.join(dir, "tf", "7.5.0"))
      FileUtils.mkdir_p(File.join(dir, "notebooks"))
      run = ->(*argv) { Nabu::Shell.run("git", "-C", dir, *argv) }
      Nabu::Shell.run("git", "init", "--quiet", dir)
      run.call("config", "user.email", "test@example.invalid")
      run.call("config", "user.name", "Test")
      FileUtils.cp(File.join(FIXTURES, "tf", "7.5.0", "otype.tf"), File.join(dir, "tf", "7.5.0", "otype.tf"))
      %w[README.md LICENSE notebooks/x.ipynb].each { |path| File.write(File.join(dir, path), "x\n") }
      run.call("add", ".")
      run.call("commit", "--quiet", "-m", "release")
      run.call("tag", "v7.5.0")
      File.write(File.join(dir, "README.md"), "moved on\n")
      run.call("add", ".")
      run.call("commit", "--quiet", "-m", "post-release drift")
    end
  end
end
