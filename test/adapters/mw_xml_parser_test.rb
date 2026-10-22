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
      assert_equal 4, tiers.fetch(:passage).size    # the three RV. citations + Pāṇ. vii, 4, 3
      assert_equal 8, tiers.fetch(:document).size   # Bhaṭṭ. Mn.×2 (bare) Nir.×2 MārkP. R. Sāh.
      assert_equal 5, tiers.fetch(:authority).size  # L.×2 Br.×2 Kāv.
      assert_equal 15, tiers.fetch(:unheld).size    # MBh.×4 + its two ib. (= MBh.), TS., Dhātup., Suśr., …
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
      assert_equal "urn:nabu:gretil:sa_pANini-aSTAdhyAyI", pan.cts_work
      assert_equal "7,4.3", pan.citation, "the re-split Aṣṭādhyāyī resolves at sūtra grain"
      manu = entry("150479").citations.select { |c| c.label == "Mn." }
      assert_equal ["urn:nabu:gretil:sa_manusmRti"], manu.map(&:cts_work).uniq
      assert_equal [nil], manu.map(&:citation).uniq, "a bare Mn. names the work — document grain"
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
      assert_equal [%w[got got amsa], %w[grc grc ὦμος], %w[grc grc ἄσιλλα],
                    %w[lat lat humerus], %w[lat lat ansa]], triples,
                   "P57-5: lang_code is now the RESOLVED catalog tag — MW's own dotted abbreviation " \
                   "(Goth./Gk./Lat.) used to leak through verbatim even though `language` already " \
                   "resolved it"
      omos = reflexes.find { |r| r.word == "ὦμος" }
      assert_equal "ωμοσ", omos.word_folded, "the generic fold — final sigma stays (grc rule is query-side)"
    end

    # P57-5: the ten-entry abbreviation table (mw-survey §4 census), unit-pinned
    # directly against MwXmlParser::COGNATE_LANGS since the fixture only exercises
    # three of the ten labels (Goth./Gk./Lat.) end to end. Eight resolve to an
    # unambiguous ISO code; the two family/period-ambiguous labels get an honest
    # macro-level call, documented here rather than left display-only (nil), per
    # the P57-5 packet spec.
    def test_cognate_lang_abbreviation_table_resolves_all_ten_mw_front_matter_labels
      table = Nabu::Adapters::MwXmlParser::COGNATE_LANGS
      assert_equal({
                     "Gk." => "grc", "Lat." => "lat", "Germ." => "de", "Lith." => "lit",
                     "Goth." => "got", "Eng." => "en", "Zd." => "ae", "Angl.Sax." => "ang",
                     "Russ." => "ru", "Armen." => "hy",
                     # Family-level, per P57-5: MW's "Slav." names no single Slavic language —
                     # map to the ISO 639-5 Slavic collective rather than guess a specific one
                     # (mw-survey §4 flagged "usually but not reliably Church Slavonic").
                     "Slav." => "sla",
                     # Period-ambiguous, per P57-5: "Hib." unambiguously means Irish (the
                     # report's own diagnosis) but MW does not fix a period. Eng./Germ./Russ./
                     # Armen. above are all mapped to their MODERN national-language code, not
                     # an older attested stage — Hib. follows the same pattern here (gle,
                     # general/modern Irish) rather than sga (Old Irish), since nothing in the
                     # fixture or front matter pins it to the older stage.
                     "Hib." => "gle"
                   }, table)
    end

    def test_register_markers_mint_no_reflexes
      assert_empty entry("150479").reflexes, "<lang>ep.</lang> is a usage register, not a cognate language"
      assert_empty entry("10").reflexes
    end

    # -- P124-3: the mechanically-safe "cf." / "q.v." pointers --------------------

    SLICE = File.join(Nabu::TestSupport.fixtures("mw"), "crossrefs-slice.xml")

    def slice_entry(id)
      @slice ||= Nabu::Adapters::MwXmlParser.new.entries(File.foreach(SLICE))
      @slice.find { |candidate| candidate.entry_id == id } or flunk "no slice entry L=#{id}"
    end

    def test_cf_adjacent_to_an_s_mints_a_headword_keyed_crossref
      assert_equal 1, slice_entry("10608").crossrefs.size
      crossref = slice_entry("10608").crossrefs.first
      assert_equal "cf.", crossref.kind
      assert_equal "a-pratistabdha", crossref.target, "the <s> SLP1 rendered as display IAST"
      assert_equal "cf. a-pratistabdha", crossref.label
      assert_equal "apratistabdha", crossref.target_folded, "compound seams drop — the headword fold"
      assert_nil crossref.target_id
    end

    def test_qv_after_an_s_and_only_the_first_cf_item_are_extracted
      # L 1702: "(for <s>aNguli</s>, <ab>q.v.</ab>) … (<ab>cf.</ab> <s>an-aNguri</s>,
      # <s>pa/YcA<srs/>Nguri</s>, <s>sv-aNguri/</s>.)" — the q.v. binds to the
      # <s> right before it; the cf. list's later items are prose, not taken.
      crossrefs = slice_entry("1702").crossrefs
      assert_equal([["q.v.", "aṅguli q.v.", "anguli"], ["cf.", "cf. an-aṅguri", "ananguri"]],
                   crossrefs.map { |c| [c.kind, c.label, c.target_folded] })
    end

    def test_entries_without_the_safe_shapes_carry_no_crossrefs
      assert_empty slice_entry("1715").crossrefs
      assert(entries.flat_map(&:crossrefs).none? { |c| %w[cf. q.v.].include?(c.kind) },
             "the main fixture carries no cf./q.v. adjacency")
      # Its only pointers are structural: aṃsa (H2) printed under √aṃs,
      # bhāṣaṇa (H2) under √bhāṣ.
      assert_equal({ "88" => [%w[root 87]], "150481" => [%w[root 150479]] },
                   entries.reject { |e| e.crossrefs.empty? }
                          .to_h { |e| [e.entry_id, e.crossrefs.map { |c| [c.kind, c.target_id] }] })
    end

    # -- the mining slice (test/fixtures/mw/README.md) ------------------------------

    MINING = File.join(Nabu::TestSupport.fixtures("mw"), "mining-slice.xml")

    def mining_entry(id)
      @mining ||= Nabu::Adapters::MwXmlParser.new.entries(File.foreach(MINING))
      @mining.find { |candidate| candidate.entry_id == id } or flunk "no mining entry L=#{id}"
    end

    def citation_rows(id)
      mining_entry(id).citations.map { |c| [c.urn_raw, c.label, c.cts_work, c.citation] }
    end

    PANINI = "urn:nabu:gretil:sa_pANini-aSTAdhyAyI"

    # -- ibid propagation: "ib." inherits the preceding citation's work --------------

    # L 37642 ul-√lī: "Kāś. on Pāṇ. i, 3, 70 … ib.; … ib." — the first ib.
    # takes the IMMEDIATELY preceding <ls> (Pāṇ.), the second chains through
    # the first. The work is inherited, never the passage (MW's ib. names the
    # same text, not the same sūtra): document grain. urn_raw keeps the print.
    def test_ib_inherits_the_preceding_work_and_chains
      assert_equal [["Kāś.", "Kāś.", nil, nil],
                    ["Pāṇ. i, 3, 70", "Pāṇ. i, 3, 70", PANINI, "1,3.70"],
                    ["ib.", "ib. (= Pāṇ.)", PANINI, nil],
                    ["ib.", "ib. (= Pāṇ.)", PANINI, nil]], citation_rows("37642")
    end

    # L 62023 kheṭa: the chain follows the print mechanically — an ib. after
    # "Kāś." inherits Kāś. (not held: the work is named, the urn stays nil),
    # and propagation crosses the entry's continuation records.
    def test_ib_follows_the_nearest_citation_across_continuation_records
      rows = citation_rows("62023").last(6)
      assert_equal([["Pāṇ. vi, 2, 126", PANINI], ["ib. (= Pāṇ.)", PANINI], ["Kāś.", nil],
                    ["ib. (= Kāś.)", nil], ["Kāś.", nil], ["Bālar. ii", nil]],
                   rows.map { |_raw, label, work, _cit| [label, work] })
    end

    # Entry boundaries reset the chain: an ib. that OPENS an entry points (in
    # print) into the previous entry, which the desk never shows beside it —
    # it stays the bare authority label, unresolved (L 101473 after L 101471's
    # MBh.; L 25656.1, whose print predecessor is its parent's Pāṇ.).
    def test_ib_resets_at_entry_boundaries
      assert_equal [["ib.", "ib.", nil, nil]], citation_rows("101473")
      assert_equal [["ib.", "ib.", nil, nil]], citation_rows("25656.1")
      assert_equal(["Pāṇ.", "ib. (= Pāṇ.)"], citation_rows("25656").map { |row| row[1] })
    end

    def test_inherited_ib_labels_classify_by_the_inherited_siglum
      sigla = Nabu::Adapters::MwSigla
      assert_equal "Pāṇ.", sigla.siglum_of("ib. (= Pāṇ.)")
      assert_equal :document, sigla.classify("ib. (= Pāṇ.)")
      assert_equal :unheld, sigla.classify("ib. (= MBh.)")
      assert_equal :authority, sigla.classify("ib. (= L.)")
      assert_equal :authority, sigla.classify("ib."), "an unpropagated ib. stays a label"
      assert_equal [PANINI, nil], sigla.resolve("ib. (= Pāṇ.)")
    end

    # -- phw parent/child ties: entry-to-entry edges, both ways ------------------------

    def id_crossrefs(id, kind)
      mining_entry(id).crossrefs.select { |c| c.kind == kind }
                                .map { |c| [c.label, c.target, c.target_id] }
    end

    # Cologne manufactures an entry for every headword MW prints
    # PARENTHETICALLY inside another (mw-meta2: <info phwchild="LC"/> in the
    # parent record, <info phwparent="LP,HWP"/> in the child). Each tie
    # becomes two id-keyed pointers — the AED vocabulary: the parent
    # "contains" the child, the child is "partOf" the parent.
    def test_phw_ties_mint_contains_and_part_of_pointers
      assert_equal [["contains āmraguptāyani", "āmraguptāyani", "25656.1"],
                    ["contains āmragupti", "āmragupti", "25656.2"]], id_crossrefs("25656", "contains")
      assert_equal [["partOf āmragupta", "āmragupta", "25656"]], id_crossrefs("25656.1", "partOf")
      assert_equal [["partOf āmragupta", "āmragupta", "25656"]], id_crossrefs("25656.2", "partOf")
    end

    # The tie names RECORD ids; a parent record that is a continuation
    # (L 150484, an H2B gender block of bhāṣaṇa L 150481) maps onto its
    # grouped entry, so the pointer lands on an entry_id that exists. The
    # displayed target is the headword upstream names (bhāṣaṇī, the record's
    # key), the id the entry it lives in.
    def test_phw_record_ids_map_onto_their_grouped_entries
      assert_equal [["partOf bhāṣaṇī", "bhāṣaṇī", "150481"]], id_crossrefs("150484.1", "partOf")
      assert_equal [["contains bhāṣaṇīkṣaulema", "bhāṣaṇīkṣaulema", "150484.1"]],
                   id_crossrefs("150481", "contains")
    end

    # -- root families: MW's own print hierarchy + the prefixed-root seam ------------

    # MW prints a root (H1, <info verb="root|genuineroot">) followed by its
    # primary derivatives as H2 sub-headwords until the next H1: each H2
    # points "root" at the root entry, id-keyed. H3/H4 compounds belong to
    # their H2 head, not to the root family (deliberately coarse); a non-root
    # H1 (2. bhāṣ, L 150550) closes the block and joins no family.
    def test_h2_derivatives_point_at_the_root_they_are_printed_under
      %w[150480 150481 150485].each do |id|
        assert_equal [["root bhāṣ", "bhāṣ", "150479"]], id_crossrefs(id, "root"), "L #{id}"
      end
      assert_equal [["root lī", "lī", "182753"]], id_crossrefs("182789", "root")
      %w[150479 150484.1 150550 62023 101471 182753].each do |id|
        assert_empty id_crossrefs(id, "root"), "L #{id} is no root-family member"
      end
    end

    # A prefixed verb (<info verb="pre" parse="ud+lI"/>, printed ul-√lī)
    # joins the family of its root — the parse's last member — resolved
    # among the dictionary's ROOT entries only, by key, never by a fold that
    # could land on a noun homograph.
    def test_prefixed_verbs_join_the_family_of_their_root
      assert_equal [["root lī", "lī", "182753"]], id_crossrefs("37642", "root")
    end

    # Homonym roots share a key (√1.as "be", √2.as "throw"); the √ mark in
    # the prefixed verb's printed headword carries the number
    # (<s>aDy-</s>√ <hom>2.</hom> <s>as</s>), matched against the root
    # entry's own <hom>.
    def test_the_root_mark_homonym_number_picks_among_homonym_roots
      assert_equal [["root as", "as", "20354"]], id_crossrefs("4624", "root")
      assert_empty id_crossrefs("20353", "root")
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
