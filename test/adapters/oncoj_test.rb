# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Oncoj adapter tests (P32-2): the Oxford-NINJAL Corpus of Old Japanese at
# the pinned "release" tag — new oncoj-xml family, line-grain passages
# (upstream lb ids), romanized analysis as text with the man'yōgana original
# riding annotations, per-token lemma ids resolved to lexicon.xml headwords
# (the ojp lemma-index join). Includes the shared AdapterConformance suite;
# fetch runs against a local git repo carrying the pinned tag (no network —
# see test/fixtures/oncoj/README.md for the fixture provenance).
class OncojTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("oncoj")

  def conformance_adapter
    Nabu::Adapters::Oncoj.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "oncoj"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_carries_the_verbatim_license_and_citation
    manifest = Nabu::Adapters::Oncoj.manifest
    assert_equal "oncoj", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license,
                    "The corpus annotation (the grammatical analysis) is licensed under " \
                    "the Creative Commons Attribution 4.0 International License."
    assert_includes manifest.license,
                    "National Institute for Japanese Language and Linguistics (2021) " \
                    "“Oxford-NINJAL Corpus of Old Japanese” http://oncoj.ninjal.ac.jp/ " \
                    "(accessed 26 December 2021)"
    assert_equal "oncoj-xml", manifest.parser_family
    assert_equal "https://github.com/ONCOJ/data", manifest.upstream_url
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_with_the_urn_as_id
    ids = conformance_adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[urn:nabu:oncoj:BS.1 urn:nabu:oncoj:KK.6 urn:nabu:oncoj:MYS.1.1
                    urn:nabu:oncoj:MYS.10.2033 urn:nabu:oncoj:MYS.3.276b], ids.sort
  end

  # --- parse: document shape --------------------------------------------------

  def parsed(urn_tail)
    adapter = conformance_adapter
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:oncoj:#{urn_tail}" }
    refute_nil ref, "no DocumentRef for #{urn_tail}"
    adapter.parse(ref)
  end

  def test_bs1_parses_at_line_grain_with_both_writing_layers
    document = parsed("BS.1")
    assert_equal "ojp", document.language
    assert_equal "Bussokuseki-ka 1", document.title
    assert_equal({ "corpus" => "BS", "upstream_id" => "BS.1" }, document.metadata)
    assert_equal 6, document.size

    first = document.passages.first
    assert_equal "urn:nabu:oncoj:BS.1:0", first.urn
    assert_equal 0, first.sequence
    assert_equal "mi ato tukuru", first.text
    assert_equal "美阿止都久留", first.annotations["manyogana"]
    assert_equal "0", first.annotations["line"]
  end

  def test_tokens_carry_lemma_ids_resolved_to_lexicon_headwords
    tokens = parsed("BS.1").passages.first.annotations["tokens"]
    assert_equal 3, tokens.size
    mi, ato, tukuru = tokens
    assert_equal(
      { "form" => "mi", "pos" => "pfx-hon", "lemma_id" => "l000035", "lemma" => "mi",
        "segments" => [{ "text" => "mi", "script" => "phon" }] }, mi
    )
    # The lexicon headword is the lemma FORM the index folds — atwo, not the
    # surface ato: the join contract with the oncoj-lexicon sibling shelf.
    assert_equal "l050877", ato["lemma_id"]
    assert_equal "atwo", ato["lemma"]
    assert_equal "tukur", tukuru["lemma"], "vb-adc surface tukuru lemmatizes to the stem entry"
  end

  def test_lemma_bearing_compound_words_mint_a_token_above_their_parts
    line4 = parsed("BS.1").passages[4]
    assert_equal "titi papa ga tame ni", line4.text, "passage text joins LEAF forms only"
    forms = line4.annotations["tokens"].map { |token| token["form"] }
    assert_equal %w[titipapa titi papa ga tame ni], forms,
                 "the compound token precedes its parts (pre-order)"
    compound = line4.annotations["tokens"].first
    assert_equal "l050402", compound["lemma_id"]
    assert_equal "titipapa", compound["lemma"]
    assert compound["compound"]
    refute compound.key?("segments"), "segments belong to leaf tokens"
  end

  def test_mys11_parses_the_multi_sentence_wrapper_and_log_segments
    document = parsed("MYS.1.1")
    assert_equal "Man’yōshū 1.1", document.title
    assert_equal 17, document.size
    kwo = document.passages.first.annotations["tokens"].first
    assert_equal "kwo", kwo["form"]
    assert_equal [{ "text" => "kwo", "script" => "log" }], kwo["segments"],
                 "logographic segments keep their honest script status"
  end

  def test_token_less_crux_lines_carry_the_manyogana_as_text_and_are_flagged
    document = parsed("MYS.10.2033")
    assert_equal 5, document.size
    crux = document.passages.find { |p| p.annotations["line"] == "3" }
    assert_equal "神競者", crux.text,
                 "a line upstream declines to analyze keeps its attested script as text"
    assert crux.annotations["unanalyzed"]
    assert_equal [], crux.annotations["tokens"]
    assert document.passages[4].annotations["unanalyzed"], "磨待無 is the sibling crux line"
  end

  def test_a_line_break_inside_a_word_keeps_the_token_whole_on_its_starting_line
    document = parsed("KK.6")
    assert_equal 10, document.size, "the interior lb still opens its line"
    line8 = document.passages.find { |p| p.annotations["line"] == "8" }
    assert_equal "adisikwitakapwikwone", line8.text,
                 "the one censused straddling word (KK.6 lines 8/9) rides its starting line whole"
    assert_equal [{ "text" => "adisikwi", "script" => "phon" },
                  { "text" => "takapwikwone", "script" => "phon" }],
                 line8.annotations["tokens"].first["segments"]
    line9 = document.passages.find { |p| p.annotations["line"] == "9" }
    assert_equal "no kamwi so", line9.text,
                 "tokens after the interior break land on the following line"
  end

  def test_duplicate_upstream_line_ids_re_mint_with_a_stable_file_order_suffix
    document = parsed("MYS.3.276b")
    assert_equal %w[urn:nabu:oncoj:MYS.3.276b:0 urn:nabu:oncoj:MYS.3.276b:3
                    urn:nabu:oncoj:MYS.3.276b:4 urn:nabu:oncoj:MYS.3.276b:0-b
                    urn:nabu:oncoj:MYS.3.276b:1],
                 document.passages.map(&:urn)
    assert_equal (0..4).to_a, document.passages.map(&:sequence)
    re_minted = document.passages[3]
    assert_equal "0", re_minted.annotations["line"], "the upstream id rides verbatim"
  end

  # --- parse: defence ---------------------------------------------------------

  def test_missing_lexicon_is_a_loud_parse_error_not_a_silent_lemma_less_parse
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "xml"))
      FileUtils.cp(File.join(FIXTURES, "xml", "BS.1.xml"), File.join(dir, "xml", "BS.1.xml"))
      adapter = conformance_adapter
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/lexicon\.xml/, error.message)
    end
  end

  def test_unresolved_lemma_ids_keep_the_id_and_mint_no_lemma_form
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "xml"))
      FileUtils.cp(File.join(FIXTURES, "xml", "BS.1.xml"), File.join(dir, "xml", "BS.1.xml"))
      # A structurally intact lexicon that lacks the corpus's lemma ids (the
      # 10-of-5,802 unresolved case, censused in the fixture README).
      File.write(File.join(dir, "lexicon.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <div xmlns="http://www.tei-c.org/ns/1.0">
            <superEntry xml:id="l999999-main">
                <entry xml:id="l999999">
                    <form>
                        <orth>nonesuch</orth>
                    </form>
                </entry>
            </superEntry>
        </div>
      XML
      token = conformance_adapter.parse(conformance_adapter_for(dir))
                                 .passages.first.annotations["tokens"].first
      assert_equal "l000035", token["lemma_id"]
      refute token.key?("lemma"), "no invented lemma form for an unresolved id"
    end
  end

  def test_body_id_drifting_from_the_filename_quarantines
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "xml"))
      drifted = File.read(File.join(FIXTURES, "xml", "BS.1.xml"))
                    .sub('xml:id="BS.1"', 'xml:id="BS.2"')
      File.write(File.join(dir, "xml", "BS.1.xml"), drifted)
      FileUtils.cp(File.join(FIXTURES, "lexicon.xml"), File.join(dir, "lexicon.xml"))
      adapter = conformance_adapter
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
    end
  end

  # --- fetch (local git only, no network) -------------------------------------

  def test_fetch_clones_the_sparse_cone_at_the_pinned_release_tag
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_tagged_repo(upstream)
      workdir = File.join(root, "canonical")
      adapter = conformance_adapter
      adapter.define_singleton_method(:repo_url) { upstream }
      report = adapter.fetch(workdir)
      assert File.file?(File.join(workdir, "xml", "BS.1.xml"))
      assert File.file?(File.join(workdir, "lexicon.xml")), "the lemma-resolution file is in the cone"
      assert File.file?(File.join(workdir, "README")), "the license source is in the cone"
      refute File.exist?(File.join(workdir, "oncoj.csv")), "the csv derivative stays outside the cone"
      tagged = Nabu::Shell.run("git", "-C", upstream, "rev-parse",
                               "#{Nabu::Adapters::Oncoj::RELEASE_TAG}^{commit}").strip
      assert_equal tagged, report.sha, "fetch must land on the pinned tag, not the moving default branch"
    end
  end

  private

  # The ref for the one text in +dir+ (helper for the defence tests).
  def conformance_adapter_for(dir)
    conformance_adapter.discover(dir).first
  end

  # A local upstream shaped like ONCOJ/data: commit 1 tagged "release",
  # commit 2 ahead of it on the default branch (the project site moves on —
  # the pin must not follow).
  def make_tagged_repo(dir)
    FileUtils.mkdir_p(File.join(dir, "xml"))
    run = ->(*argv) { Nabu::Shell.run("git", "-C", dir, *argv) }
    Nabu::Shell.run("git", "init", "--quiet", dir)
    run.call("config", "user.email", "test@example.invalid")
    run.call("config", "user.name", "Test")
    FileUtils.cp(File.join(FIXTURES, "xml", "BS.1.xml"), File.join(dir, "xml", "BS.1.xml"))
    FileUtils.cp(File.join(FIXTURES, "lexicon.xml"), File.join(dir, "lexicon.xml"))
    FileUtils.cp(File.join(FIXTURES, "README"), File.join(dir, "README"))
    File.write(File.join(dir, "oncoj.csv"), "\"CP-FINAL\"\n")
    run.call("add", ".")
    run.call("commit", "--quiet", "-m", "release")
    run.call("tag", Nabu::Adapters::Oncoj::RELEASE_TAG)
    File.write(File.join(dir, "README"), "moved on\n")
    run.call("add", ".")
    run.call("commit", "--quiet", "-m", "post-release drift")
  end
end
