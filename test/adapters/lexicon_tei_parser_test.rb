# frozen_string_literal: true

require "test_helper"

# The lexicon-tei parser family (P11-4): streams Perseus dictionary TEI
# (P4, PersDict — entryFree entries under div0 alphabetic letters) into
# Nabu::DictionaryEntry values. Exercised against the real trimmed LSJ /
# Lewis & Short fixtures.
class LexiconTeiParserTest < Minitest::Test
  FIXTURES = File.join(Nabu::TestSupport.fixtures("lexica"), "CTS_XML_TEI/perseus/pdllex")
  LSJ_MU = File.join(FIXTURES, "grc/lsj/grc.lsj.perseus-eng13.xml")
  LSJ_LAMBDA = File.join(FIXTURES, "grc/lsj/grc.lsj.perseus-eng12.xml")
  LS = File.join(FIXTURES, "lat/ls/lat.ls.perseus-eng2.xml")

  def parse(path, language:, betacode: false)
    Nabu::Adapters::LexiconTeiParser.new.entries(path, language: language, betacode: betacode)
  end

  def test_parses_the_lsj_mu_fixture_into_two_entries
    entries = parse(LSJ_MU, language: "grc", betacode: true)
    assert_equal %w[n67485 n67486], entries.map(&:entry_id).sort
  end

  def test_decodes_betacode_headwords_and_folds_them
    menis = parse(LSJ_MU, language: "grc", betacode: true).find { |e| e.key_raw == "mh=nis" }
    assert_equal "μῆνις", menis.headword
    assert_equal "μηνισ", menis.headword_folded # grc fold: marks stripped, ς→σ
    assert_equal "grc", menis.language
  end

  def test_extracts_the_first_tr_as_gloss
    menis = parse(LSJ_MU, language: "grc", betacode: true).find { |e| e.key_raw == "mh=nis" }
    assert_equal "wrath", menis.gloss
  end

  def test_body_is_plain_text_with_decoded_greek_and_no_markup
    menis = parse(LSJ_MU, language: "grc", betacode: true).find { |e| e.key_raw == "mh=nis" }
    assert_includes menis.body, "wrath"
    assert_includes menis.body, "μήνιος" # betacode quote decoded
    refute_includes menis.body, "<"
    assert menis.body.unicode_normalized?(:nfc)
  end

  def test_extracts_cts_citations_with_work_prefix_and_dot_citation
    menis = parse(LSJ_MU, language: "grc", betacode: true).find { |e| e.key_raw == "mh=nis" }
    iliad = menis.citations.find { |c| c.label == "Il. 1.1" }
    refute_nil iliad, "expected the Il. 1.1 citation"
    assert_equal "urn:cts:greekLit:tlg0012.tlg001.perseus-grc1:1:1", iliad.urn_raw
    assert_equal "urn:cts:greekLit:tlg0012.tlg001", iliad.cts_work
    assert_equal "1.1", iliad.citation
  end

  def test_urn_less_bibls_stay_in_the_body_but_mint_no_citation
    menis = parse(LSJ_MU, language: "grc", betacode: true).find { |e| e.key_raw == "mh=nis" }
    assert_includes menis.body, "AP 9.168" # kept as text
    assert(menis.citations.none? { |c| c.label.include?("AP") })
  end

  def test_the_logos_entry_parses_whole_with_sense_labels
    logos = parse(LSJ_LAMBDA, language: "grc", betacode: true).find { |e| e.key_raw == "lo/gos" }
    assert_equal "λόγος", logos.headword
    assert_operator logos.body.length, :>, 10_000 # the stress entry, kept whole
    assert_match(/^I\. computation/, logos.body) # sense labels start their own lines
  end

  def test_parses_the_lewis_short_fixture_without_betacode
    entries = parse(LS, language: "lat", betacode: false)
    assert_equal %w[Aaron a officium virtus], entries.map(&:headword).map { |h|
      Nabu::Normalize.fold_diacritics(h)
    }.sort
    officium = entries.find { |e| e.key_raw == "officium" }
    assert_equal "offĭcĭum", officium.headword # orth kept pristine
    assert_equal "officium", officium.headword_folded
  end

  def test_lewis_short_gloss_falls_back_to_the_first_italic_run
    entries = parse(LS, language: "lat", betacode: false)
    assert_equal "a service", entries.find { |e| e.key_raw == "officium" }.gloss
    # The first italic run of virtus is the abbreviation "gen. plur." — the
    # fallback must skip abbreviation runs and land on the real gloss.
    assert_equal "manliness", entries.find { |e| e.key_raw == "virtus" }.gloss
  end

  def test_officium_cites_de_officiis_with_the_edition_token_folded_to_the_work
    officium = parse(LS, language: "lat", betacode: false).find { |e| e.key_raw == "officium" }
    cite = officium.citations.find { |c| c.urn_raw == "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4" }
    refute_nil cite
    assert_equal "urn:cts:latinLit:phi0474.phi055", cite.cts_work
    assert_equal "1.2.4", cite.citation
  end

  def test_malformed_upstream_urns_are_kept_without_crashing
    virtus = parse(LS, language: "lat", betacode: false).find { |e| e.key_raw == "virtus" }
    bad = virtus.citations.find { |c| c.urn_raw.include?("Orat::") }
    refute_nil bad, "the malformed virtus urn must still mint a citation row"
    assert_equal "urn:cts:latinLit:phi0474.phi037", bad.cts_work
  end

  def test_cross_namespace_citations_survive
    aaron = parse(LS, language: "lat", betacode: false).find { |e| e.key_raw == "Aaron" }
    assert(aaron.citations.any? { |c| c.cts_work == "urn:cts:greekLit:tlg0527.tlg002" })
  end

  def test_homograph_key_digits_fold_away_but_stay_in_key_raw
    a2 = parse(LS, language: "lat", betacode: false).find { |e| e.key_raw == "a2" }
    assert_equal "a", a2.headword_folded
    assert_nil a2.gloss # two-line cross-reference entry: nothing to gloss
  end
end
