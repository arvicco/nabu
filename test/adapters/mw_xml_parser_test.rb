# frozen_string_literal: true

require "test_helper"

module Adapters
  # The mw-xml parser family (P17-4): line-streamed Cologne MW records,
  # grouped H1–H4 + lettered continuations → DictionaryEntry values with
  # IAST headwords, tiered <ls> citations and the cognate-note reflex layer.
  # Exercised against the trimmed real fixture (test/fixtures/mw/README.md).
  class MwXmlParserTest < Minitest::Test
    FIXTURE = File.join(Nabu::TestSupport.fixtures("mw"), "mw.xml")

    def entries
      @entries ||= parse
    end

    def parse
      Nabu::Adapters::MwXmlParser.new.entries(File.foreach(FIXTURE))
    end

    def entry(id)
      entries.find { |candidate| candidate.entry_id == id } or flunk "no entry L=#{id}"
    end

    # -- grouping ---------------------------------------------------------------

    def test_groups_26_records_into_11_entries_keyed_by_the_main_l_id
      records = File.foreach(FIXTURE).count { |line| line.start_with?("<H") }
      assert_equal 26, records
      assert_equal %w[10 20 26 27 27.1 44 87 88 313 150479 150481], entries.map(&:entry_id)
    end

    def test_continuation_records_fold_into_the_preceding_main_entry
      amsa = entry("88") # H2 main + A 89-90 + B 91-92 + E 92.1
      assert_includes amsa.body, "corner of a quadrangle"           # H2A 89
      assert_includes amsa.body, "the two shoulders or angles"      # H2B 91
      assert_includes amsa.body, "cf. Goth. amsa"                   # H2E 92.1
    end

    def test_a_continuation_before_any_main_record_is_a_parse_error
      orphan = ["<H1A><h><key1>x</key1><key2>x</key2></h><body>y</body>" \
                "<tail><L>9</L><pc>1,1</pc></tail></H1A>\n"]
      assert_raises(Nabu::ParseError) { Nabu::Adapters::MwXmlParser.new.entries(orphan) }
    end

    # -- transcode at the boundary (survey §2) -----------------------------------

    def test_headwords_are_iast_of_key1_with_key2_kept_verbatim
      amsha = entry("10")
      assert_equal "aṃśa", amsha.headword
      assert_equal "a/MSa", amsha.key_raw, "key2 verbatim: SLP1 with the accent apparatus"
      assert_equal "bhāṣ", entry("150479").headword
      assert_equal "aṃśa—karaRa".gsub("aṃśa", "aMSa"), entry("20").key_raw # seam verbatim
    end

    def test_headword_folded_is_the_generic_fold_that_joins_gretil
      # The survey's verified join: fold("aṃśa") = fold(IAST of "aMSa") = "amsa".
      assert_equal "amsa", entry("10").headword_folded
      assert_equal "amsa", entry("88").headword_folded, "aṃśa and aṃsa meet at the fold — homograph reality"
      assert_equal "bhas", entry("150479").headword_folded
    end

    def test_in_body_sanskrit_is_transcoded_with_accents_composed
      assert_includes entry("10").body, "áṃśa m."
      assert_includes entry("150479").body, "bhā́ṣate"
      assert_includes entry("26").body, "aṃśa—bhū́"
    end

    # -- gloss ------------------------------------------------------------------

    def test_gloss_is_the_first_sense_with_leading_apparatus_stripped
      assert_equal "a share, portion, part, party", entry("10").gloss,
                   "the leading parenthetical etymology is stripped"
      assert_equal "the shoulder, shoulder-blade", entry("88").gloss
      assert_equal "unbounded", entry("313").gloss
      assert_equal "the act of speaking, talking, speech, talk", entry("150481").gloss
    end

    def test_verb_gloss_starts_at_the_first_sense_break
      assert_equal "to speak, talk, say, tell (with acc. of thing or person, " \
                   "sometimes also with acc. of thing and person)", entry("150479").gloss
    end

    def test_gloss_is_honestly_nil_for_cross_reference_stubs
      assert_nil entry("87").gloss
    end

    # -- the grammar apparatus ----------------------------------------------------

    def test_gender_apparatus_decodes_with_feminine_stem_suffix
      assert_equal "grammar: m", entry("10").body.lines.last.strip
      assert_equal "grammar: m, f, n", entry("27").body.lines.last.strip
      assert_equal "grammar: f(-ā), n", entry("150481").body.lines.last.strip
    end

    def test_verb_apparatus_decodes_class_pada_and_root_references
      assert_equal "grammar: verb genuineroot, class-pada 1Ā,1P · " \
                   "Westergaard Dhātup. bhāṣa 16.11 · Whitney roots bhāṣ 110",
                   entry("150479").body.lines.last.strip
      assert_equal "grammar: verb genuineroot", entry("87").body.lines.last.strip,
                   "an EMPTY cp attribute renders no class-pada"
    end

    # -- citations (survey §3) -----------------------------------------------------

    def test_the_fixture_citations_tally_by_tier
      labels = entries.flat_map(&:citations).map(&:label)
      assert_equal 32, labels.size
      tiers = labels.group_by { |label| Nabu::Adapters::MwSigla.classify(label) }
      assert_equal 3, tiers.fetch(:passage).size    # the three RV. citations
      assert_equal 9, tiers.fetch(:document).size   # Bhaṭṭ. Mn.×2 Nir.×2 Pāṇ. MārkP. R. Sāh.
      assert_equal 7, tiers.fetch(:authority).size  # L.×2 Br.×2 ib.×2 Kāv.
      assert_equal 13, tiers.fetch(:unheld).size    # MBh.×4, TS., Dhātup., Suśr., …
    end

    def test_the_verified_rv_citation_normalizes_to_the_gretil_shape
      # "RV. v, 86, 5" → 5.086.05 — the survey's end-to-end verified
      # resolution (urn:nabu:gretil:sa_Rgveda-edAufrecht:5.086.05a lives in
      # the live catalog; the pada suffix is Define's query-time probe).
      rv = entry("10").citations.find { |c| c.label == "RV. v, 86, 5" }
      assert_equal "urn:nabu:gretil:sa_Rgveda-edAufrecht", rv.cts_work
      assert_equal "5.086.05", rv.citation
    end

    def test_elliptical_continuation_citations_are_restored_from_the_n_attribute
      labels = entry("313").citations.map(&:label)
      assert_equal ["RV. v, 39, 2", "RV. x, 109, 1"], labels,
                   '<ls n="RV.">x, 109, 1</ls> restores its elided siglum'
      assert_equal %w[5.039.02 10.109.01], entry("313").citations.map(&:citation)
    end

    def test_held_document_grain_citations_carry_the_urn_without_a_citation
      pan = entry("150479").citations.find { |c| c.label == "Pāṇ. vii, 4, 3" }
      assert_equal "urn:nabu:gretil:sa_pANini-aSTAdhyAyI", pan.cts_work,
                   "Pāṇini is held but single-blob — document grain by design"
      assert_nil pan.citation
      sah = entry("150481").citations.find { |c| c.label == "Sāh." }
      assert_equal "urn:nabu:gretil:sa_vizvanAthakavirAja-sAhityadarpaNa", sah.cts_work
    end

    def test_authority_labels_and_unheld_works_stay_honest_nil
      day = entry("10").citations.find { |c| c.label == "L." }
      assert_nil day.cts_work, "L. is a lexicographer label, never a work"
      mbh = entry("150479").citations.select { |c| c.label == "MBh." }
      assert_equal 3, mbh.size
      assert_equal [nil], mbh.map(&:cts_work).uniq, "the Mahābhārata is not in GRETIL's TEI corpus"
    end

    # -- the cognate-note reflex layer (survey §4) ---------------------------------

    def test_the_amsa_etymology_record_mints_five_language_tagged_comparanda
      reflexes = entry("88").reflexes
      triples = reflexes.map { |r| [r.lang_code, r.language, r.word] }
      assert_equal [%w[Goth. got amsa], ["Gk.", "grc", "ὦμος"], ["Gk.", "grc", "ἄσιλλα"],
                    %w[Lat. lat humerus], %w[Lat. lat ansa]], triples
      omos = reflexes.find { |r| r.word == "ὦμος" }
      assert_equal "ωμοσ", omos.word_folded, "the generic fold — final sigma stays (grc rule is query-side)"
    end

    def test_register_markers_mint_no_reflexes
      assert_empty entry("150479").reflexes, "<lang>ep.</lang> is a usage register, not a cognate language"
      assert_empty entry("10").reflexes
    end

    # -- hygiene -------------------------------------------------------------------

    def test_output_is_nfc_everywhere
      entries.each do |e|
        assert e.headword.unicode_normalized?(:nfc)
        assert e.body.unicode_normalized?(:nfc)
        e.reflexes.each { |r| assert r.word.unicode_normalized?(:nfc) }
      end
    end

    def test_entries_are_stable_across_independent_parses
      snapshot = ->(list) { list.map { |e| [e.entry_id, e.headword, e.body] } }
      assert_equal snapshot.call(parse), snapshot.call(parse)
    end
  end
end
