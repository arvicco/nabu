# frozen_string_literal: true

require "test_helper"

# The lexicon-tei parser family (P11-4): streams Perseus dictionary TEI
# (P4, PersDict — entryFree entries under div0 alphabetic letters) into
# Nabu::DictionaryEntry values. Exercised against the real trimmed LSJ /
# Lewis & Short fixtures.
class LexiconTeiParserTest < Minitest::Test
  include StoreTestDB

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

  # -- P11-7 fix 5: work-level (empty-suffix) CTS urns mint nil, not "" -------

  # The α (eng1) and θ (eng9) LSJ files quarantined the WHOLE file on a bibl
  # whose @n is a work-level urn with a trailing colon
  # ("urn:cts:greekLit:tlg0027.tlg0088:"): the empty citation suffix built a
  # "" DictionaryCitation, which is rejected, ValidationError → ParseError. The
  # P11-7 census misread α/θ as "alternate editions"; they are the largest and
  # one ordinary letter sections. The parser now mints a work-level citation
  # (citation nil), so the file parses whole. Fixture: a real trimmed α slice.
  LSJ_ALPHA = File.join(
    Nabu::TestSupport.fixtures("lexica_p11_7"),
    "CTS_XML_TEI/perseus/pdllex/grc/lsj/grc.lsj.perseus-eng1.xml"
  )

  def test_work_level_cts_urn_with_trailing_colon_parses_whole
    entries = parse(LSJ_ALPHA, language: "grc", betacode: true)
    # Both entries survive — the trailing-colon bibl no longer quarantines.
    assert_equal %w[n4 n6454], entries.map(&:entry_id).sort

    offender = entries.find { |e| e.entry_id == "n6454" }
    work_only = offender.citations.find { |c| c.urn_raw == "urn:cts:greekLit:tlg0027.tlg0088:" }
    refute_nil work_only, "the work-level bibl must still mint a citation row"
    assert_equal "urn:cts:greekLit:tlg0027.tlg0088", work_only.cts_work
    assert_nil work_only.citation, "an empty citation suffix mints nil, not an empty string"
  end

  # P123-1: LSJ's <xr><lbl/><ref/></xr> pointers become crossrefs — kind
  # from the label, target decoded from betacode and folded like @key.
  def test_lsj_xr_pointers_mint_crossrefs_in_entry_order
    logos = parse(LSJ_LAMBDA, language: "grc", betacode: true).find { |e| e.entry_id == "n63772" }
    assert_equal([["variant", "v.l. λόγων", "λογων"],
                  ["equals", "= φύσει νόμος", "φυσει νομοσ"],
                  ["equals", "= ἁπλῶς, περὶ πάντων ἑνὶ λ.", "απλωσ, περι παντων ενι λ."],
                  ["equals", "= πρᾶγμα", "πραγμα"],
                  ["equals", "= μῦθος", "μυθοσ"]],
                 logos.crossrefs.map { |c| [c.kind, c.label, c.target_folded] })
    assert_equal "μῦθος", logos.crossrefs.last.target
  end

  def test_lewis_short_carries_no_xr_markup
    assert(parse(LS, language: "lat").all? { |e| e.crossrefs.empty? })
  end

  # --- <etym> mining (the lexica-etym fixtures: real entries) ---------------------

  ETYM = File.join(Nabu::TestSupport.fixtures("lexica-etym"), "CTS_XML_TEI/perseus/pdllex")
  ETYM_LSJ = File.join(ETYM, "grc/lsj/grc.lsj.perseus-eng13.xml")
  ETYM_LS = File.join(ETYM, "lat/ls/lat.ls.perseus-eng2.xml")

  def lsj_etym(path) = parse_etym(path, language: "grc", betacode: true, etym: :lsj)

  def ls_etym = parse_etym(ETYM_LS, language: "lat", etym: :lewis_short)

  def parse_etym(path, **)
    Nabu::Adapters::LexiconTeiParser.new.entries(path, **)
  end

  def test_etym_is_opt_in
    assert(parse(ETYM_LS, language: "lat").all? { |e| e.crossrefs.empty? && e.reflexes.empty? })
  end

  # LSJ's <etym lang="greek"> names the base word(s) the headword is
  # formed from — a crossref per comma item, betacode-decoded and folded
  # exactly like @key (the exact-headword resolution key).
  def test_lsj_etym_base_words_mint_etym_crossrefs
    metapsyxis = lsj_etym(ETYM_LSJ).find { |e| e.key_raw == "meta/yucis" }
    assert_equal([%w[etym μεταπνοή μεταπνοη]], metapsyxis.crossrefs.map { |c| [c.kind, c.target, c.target_folded] })
    assert_equal "etym μεταπνοή", metapsyxis.crossrefs.first.label
  end

  def test_lsj_etym_comma_lists_split_and_follow_the_xr_pointers
    logos = lsj_etym(LSJ_LAMBDA).find { |e| e.entry_id == "n63772" }
    etyms = logos.crossrefs.select { |c| c.kind == "etym" }.map(&:target)
    assert_equal ["ὁ λ.", "ἐπιστήμη", "ῥήσεις", "ἔπος", "λέξις", "ὄνομα", "ῥῆμα"], etyms,
                 "the leading '=' of '= e)pisth/mh' is the equation mark, not the word"
    assert_equal 5, logos.crossrefs.take_while { |c| c.kind != "etym" }.size, "the <xr> pointers come first"
  end

  # Lewis & Short's base-word shape: the whole <etym> is a Latin word or
  # hyphen compound ("bis-metrum") — one crossref per named base part.
  def test_lewis_short_compounds_point_at_each_named_base
    bimeter = ls_etym.find { |e| e.key_raw == "bimeter" }
    assert_equal([%w[bis bis], %w[metrum metrum]], bimeter.crossrefs.map { |c| [c.target, c.target_folded] })
    assert_equal ["etym bis-metrum"], bimeter.crossrefs.map(&:label).uniq
    assert_empty bimeter.reflexes
  end

  # The cognate-chain shape: language-labeled forms mint cognate reflex
  # rows — the label's held code where the closed table maps it, the label
  # verbatim (language nil) where it does not; Greek forms come from the
  # tagged <foreign lang="greek"> runs.
  def test_lewis_short_cognate_chains_mint_cognate_reflexes
    do2 = ls_etym.find { |e| e.key_raw == "do2" }
    assert_equal([%w[san san dhā-], %w[grc grc θε-], %w[grc grc τίθημι], %w[de de thun], %w[en en do]],
                 do2.reflexes.map { |r| [r.lang_code, r.language, r.word] })
    assert_equal ["cognate"], do2.reflexes.map(&:relation).uniq
    assert_equal "dha", do2.reflexes.first.word_folded, "the trailing root hyphen folds off"

    vespa = ls_etym.find { |e| e.key_raw == "vespa" }
    assert_equal([%w[grc σφήξ], %w[goh wefsa], %w[en wasp]], vespa.reflexes.map { |r| [r.lang_code, r.word] })

    ambactus = ls_etym.find { |e| e.key_raw == "ambactus" }
    assert_equal [["Celt.", nil, "amb"], %w[got got andbahti]],
                 ambactus.reflexes.map { |r| [r.lang_code, r.language, r.word] },
                 "an unmapped label stays verbatim in lang_code, display-only"
  end

  def test_lewis_short_greek_only_etym_is_the_derivation_source
    hydrius = ls_etym.find { |e| e.key_raw == "hydrius" }
    assert_equal([%w[grc ὕδωρ derived]], hydrius.reflexes.map { |r| [r.lang_code, r.word, r.relation] })
    assert_empty hydrius.crossrefs
  end

  def test_lewis_short_label_table_maps_every_row_to_a_valid_tag_or_nil
    Nabu::Adapters::LexiconTeiParser::LS_LANGUAGE_LABELS.each do |label, code|
      next if code.nil?

      assert_equal code, Nabu::Model::Validation.language!(code), label
    end
  end

  def test_etym_crossrefs_resolve_to_the_named_entry_on_load
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "lexica", name: "L", adapter_class: "X", license_class: "attribution")
    document = Nabu::DictionaryDocument.new(slug: "lewis-short", language: "lat", title: "L&S", canonical_path: ETYM_LS)
    ls_etym.each { |entry| document << entry }
    Nabu::Store::DictionaryLoader.new(db: db, source: source).load([document], full: false)
    metrum = db[:dictionary_entries].where(key_raw: "metrum").get(:id)
    resolved = db[:dictionary_crossrefs].where(kind: "etym").to_h { |row| [row[:target], row[:to_entry_id]] }
    assert_equal({ "bis" => nil, "metrum" => metrum }, resolved, "bis is not held in the fixture — honestly unresolved")
  end
end
