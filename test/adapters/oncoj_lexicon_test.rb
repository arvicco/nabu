# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# OncojLexicon adapter tests (P32-2): the ONCOJ lexicon.xml — the corpus's
# own dictionary database — as the ojp dictionary shelf, SIBLING of the
# oncoj corpus source (one content kind per adapter, the lexlep/lexlep-words
# precedent). Dictionary sources skip the passage conformance suite (the
# wiktionary-recon precedent); fixture blocks are line-byte-verbatim
# upstream (test/fixtures/oncoj-lexicon/README.md).
class OncojLexiconTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("oncoj-lexicon")

  def adapter
    Nabu::Adapters::OncojLexicon.new
  end

  # --- manifest / capabilities ------------------------------------------------

  def test_manifest_carries_the_verbatim_license_and_citation
    manifest = Nabu::Adapters::OncojLexicon.manifest
    assert_equal "oncoj-lexicon", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license,
                    "The corpus annotation (the grammatical analysis) is licensed under " \
                    "the Creative Commons Attribution 4.0 International License."
    assert_includes manifest.license,
                    "National Institute for Japanese Language and Linguistics (2021) " \
                    "“Oxford-NINJAL Corpus of Old Japanese” http://oncoj.ninjal.ac.jp/ " \
                    "(accessed 26 December 2021)"
    assert_equal "oncoj-lexicon", manifest.parser_family
  end

  def test_content_kind_routes_to_the_dictionary_loader
    assert_equal :dictionary, Nabu::Adapters::OncojLexicon.content_kind
  end

  # --- discover / parse -------------------------------------------------------

  def parsed
    refs = adapter.discover(FIXTURES).to_a
    assert_equal 1, refs.size
    assert_equal "oncoj-lexicon:lexicon.xml", refs.first.id
    adapter.parse(refs.first)
  end

  def entries_by_id
    parsed.to_h { |entry| [entry.entry_id, entry] }
  end

  def test_parse_yields_one_entry_per_lexicon_entry
    document = parsed
    assert_equal "oncoj-lexicon", document.slug
    assert_equal "ojp", document.language
    assert_equal 112, document.count, "the fixture trim carries 112 byte-verbatim entries"
  end

  def test_auxiliary_entry_renders_forms_pos_inflection_and_sense
    entry = entries_by_id.fetch("l000006a")
    assert_equal "-n-", entry.headword
    assert_equal "l000006a", entry.key_raw
    assert_equal "[negative]", entry.gloss
    assert_includes entry.body, "forms: -n- · -zu"
    assert_includes entry.body, "pos: auxiliary"
    assert_includes entry.body, "inflection: aStem irr — conclusive: -zu, -nu;"
    assert_includes entry.body, "1. [negative]"
    assert_includes entry.body, "upstream corresp: 19587"
    assert_empty entry.citations
    assert_empty entry.reflexes
  end

  def test_geo_usage_variants_ride_the_body
    entry = entries_by_id.fetch("l000006b")
    assert_equal "-nana", entry.headword
    assert_includes entry.body, "usage (geo): EOJ"
  end

  def test_def_less_entries_keep_a_nil_gloss_and_an_honest_body
    entry = entries_by_id.fetch("l000032")
    assert_equal "-kar-", entry.headword
    assert_nil entry.gloss
    assert_includes entry.body, "pos: secondary adjectival copula"
  end

  def test_compound_relations_name_their_members_with_lexicon_ids
    entry = entries_by_id.fetch("l050402")
    assert_equal "titipapa", entry.headword
    assert_equal "father and mother", entry.gloss
    assert_includes entry.body, "compound: titi (l050641) · papa (l051720)"
  end

  def test_the_corpus_join_headword_is_the_first_orth
    entry = entries_by_id.fetch("l050877")
    assert_equal "atwo", entry.headword, "the first orth is the headword the token join folds"
    assert_includes entry.body, "forms: atwo · ato"
  end

  def test_the_upstream_duplicate_entry_id_re_mints_with_a_stable_suffix
    entries = entries_by_id
    first = entries.fetch("l090819")
    second = entries.fetch("l090819-b")
    assert_equal "takigwikoru", first.headword, "first occurrence keeps the plain upstream id"
    assert_equal "takamiya", second.headword
    assert_equal "l090819", second.key_raw, "the upstream id rides verbatim as key_raw"
    assert_includes second.body, "upstream entry id l090819 also names another entry"
  end

  def test_headwords_fold_to_the_ojp_search_form
    entry = entries_by_id.fetch("l050877")
    assert_equal Nabu::Normalize.search_form("atwo", language: "ojp"), entry.headword_folded
  end

  # --- fetch (local git only, no network) -------------------------------------

  def test_fetch_clones_the_lexicon_cone_at_the_pinned_release_tag
    Dir.mktmpdir do |root|
      upstream = File.join(root, "upstream")
      make_tagged_repo(upstream)
      workdir = File.join(root, "canonical")
      lexicon_adapter = adapter
      lexicon_adapter.define_singleton_method(:repo_url) { upstream }
      report = lexicon_adapter.fetch(workdir)
      assert File.file?(File.join(workdir, "lexicon.xml"))
      assert File.file?(File.join(workdir, "README")), "the license source is in the cone"
      refute File.exist?(File.join(workdir, "xml")), "the corpus tree belongs to the oncoj sibling"
      tagged = Nabu::Shell.run("git", "-C", upstream, "rev-parse",
                               "#{Nabu::Adapters::OncojLexicon::RELEASE_TAG}^{commit}").strip
      assert_equal tagged, report.sha
    end
  end

  private

  # A local upstream shaped like ONCOJ/data (see OncojTest#make_tagged_repo).
  def make_tagged_repo(dir)
    FileUtils.mkdir_p(File.join(dir, "xml"))
    run = ->(*argv) { Nabu::Shell.run("git", "-C", dir, *argv) }
    Nabu::Shell.run("git", "init", "--quiet", dir)
    run.call("config", "user.email", "test@example.invalid")
    run.call("config", "user.name", "Test")
    FileUtils.cp(File.join(FIXTURES, "lexicon.xml"), File.join(dir, "lexicon.xml"))
    FileUtils.cp(File.join(FIXTURES, "README"), File.join(dir, "README"))
    File.write(File.join(dir, "xml", "BS.1.xml"), "<TEI/>\n")
    run.call("add", ".")
    run.call("commit", "--quiet", "-m", "release")
    run.call("tag", Nabu::Adapters::OncojLexicon::RELEASE_TAG)
    File.write(File.join(dir, "README"), "moved on\n")
    run.call("add", ".")
    run.call("commit", "--quiet", "-m", "post-release drift")
  end
end
