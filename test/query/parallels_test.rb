# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Parallels (P15-1, docs/intertext-design.md §1). Same rig as
  # ProximityTest/SearchTest: a fresh in-memory catalog + fulltext, the index
  # rebuilt with the real Indexer, so the FTS phrase probes run over the true
  # fold-both-sides search forms and the lemma-echo path exercises the real
  # passage_lemmas index end to end.
  #
  # == Why the design's live goldens live HERE, not in golden_queries.yml
  #
  # golden_queries.yml is a SINGLE-passage membership suite (does query Q return
  # passage P from the assembled fixture corpus). A parallel is a RELATION
  # between two coordinated passages, and the trimmed per-adapter fixture corpus
  # holds no quotation pair (proiel = Cicero, ud = Greek NT, perseus/first1k
  # share no same-language work) — so the design's live probes (Odyssey 1.1 →
  # Polybius, Matthew 4:4 → LXX Deut 8:3, John 1:1 → the Fathers) cannot resolve
  # there without bloating fixtures. They are reproduced below as fixture-store
  # unit tests seeded with the REAL probe texts: deterministic, offline, and a
  # sharper golden than corpus membership — they pin the ALGORITHM (rarity
  # ranking, elision fold, document dedupe, anchor exclusion) on the actual
  # Greek the design measured.
  class ParallelsTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @open = Nabu::Store::Source.create(
        slug: "open", name: "Open", adapter_class: "TestAdapter", license_class: "open"
      )
      @nc = Nabu::Store::Source.create(
        slug: "nc", name: "NC", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers -------------------------------------------------------------

    def make_document(urn:, source: @open, title: "Doc", language: "grc", withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, text:, sequence:, language: "grc", lemmas: [], withdrawn: false)
      tokens = lemmas.map { |lemma, form| { "lemma" => lemma, "form" => form } }
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: JSON.generate({ "tokens" => tokens }),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def engine
      Nabu::Query::Parallels.new(catalog: @catalog, fulltext: @fulltext)
    end

    def parallels(urn, **)
      engine.run(urn, **)
    end

    # A little filler noise so folded common grams have >1 document-frequency —
    # rarity ranking only bites when df varies.
    def filler(text, seq)
      doc = make_document(urn: "urn:filler:#{seq}", title: "Filler #{seq}")
      make_passage(doc, urn: "urn:filler:#{seq}:1", text: text, sequence: 0)
    end

    # == GOLDEN 1: Odyssey 1.1 → Polybius (rarity ranks the fuller quote top) ==

    ODYSSEY_1_1 = "ἄνδρα μοι ἔννεπε, μοῦσα, πολύτροπον, ὃς μάλα πολλὰ"

    def test_golden_odyssey_proem_ranks_the_fuller_quotation_first
      homer = make_document(urn: "urn:homer:od", title: "Odyssey")
      make_passage(homer, urn: "urn:homer:od:1.1", text: ODYSSEY_1_1, sequence: 0)
      # Polybius quotes the whole proem line verbatim.
      polybius = make_document(urn: "urn:polyb:hist", title: "Histories")
      make_passage(polybius, urn: "urn:polyb:hist:12.27.10",
                             text: "καθάπερ Ὅμηρός φησιν· #{ODYSSEY_1_1}", sequence: 0)
      # A grammarian quotes only the opening hemistich.
      schol = make_document(urn: "urn:schol:x", title: "Scholia")
      make_passage(schol, urn: "urn:schol:x:1", text: "ἄνδρα μοι ἔννεπε μοῦσα λέγει", sequence: 0)
      rebuild!

      result = parallels("urn:homer:od:1.1")
      urns = result.hits.map(&:urn)
      assert_equal "urn:polyb:hist:12.27.10", urns.first,
                   "the verbatim full-line quotation outranks the partial one"
      assert_includes urns, "urn:schol:x:1"
      assert_operator result.hits.first.score, :>, result.hits.last.score, "rarity-weighted ranking"
      # The evidence is the shared PHRASE, grams merged back to contiguous text.
      assert_includes result.hits.first.evidence.join(" "), "ανδρα μοι εννεπε μουσα πολυτροπον"
    end

    # == GOLDEN 2: Matthew 4:4 → LXX Deuteronomy 8:3 (the elision fold) ========

    # SBLGNT writes the elision apostrophe U+02BC (a LETTER: ἐπʼ is one token);
    # the LXX edition writes U+2019 (punctuation: ἐπ’ tokenizes to bare ἐπ).
    MATT_4_4 = "Οὐκ ἐπʼ ἄρτῳ μόνῳ ζήσεται ὁ ἄνθρωπος, ἀλλʼ ἐπὶ παντὶ ῥήματι " \
               "ἐκπορευομένῳ διὰ στόματος θεοῦ"
    DEUT_8_3 = "οὐκ ἐπ’ ἄρτῳ μόνῳ ζήσεται ὁ ἄνθρωπος, ἀλλ’ ἐπὶ παντὶ ῥήματι " \
               "τῷ ἐκπορευομένῳ διὰ στόματος θεοῦ"

    def test_golden_matthew_finds_the_lxx_across_the_elision_encoding_gap
      matt = make_document(urn: "urn:nt:matt", title: "Matthew")
      make_passage(matt, urn: "urn:nt:matt:4.4", text: MATT_4_4, sequence: 0)
      deut = make_document(urn: "urn:lxx:deut", title: "Deuteronomy")
      make_passage(deut, urn: "urn:lxx:deut:8.3", text: DEUT_8_3, sequence: 0)
      rebuild!

      result = parallels("urn:nt:matt:4.4")
      hit = result.hits.find { |h| h.urn == "urn:lxx:deut:8.3" }
      refute_nil hit, "the LXX source is found DESPITE the U+02BC vs U+2019 elision encodings"
      assert_operator hit.shared_gram_count, :>=, 7,
                      "the long shared quotation survives the elision fold (measured 9 in the live corpus)"
    end

    # The load-bearing mechanic in isolation: the two elision encodings fold to
    # DIFFERENT search forms, but the gram builder's apostrophe strip unifies
    # them — without it, no gram spanning the apostrophe would ever match.
    def test_elision_strip_unifies_the_two_apostrophe_encodings
      u02bc = Nabu::Normalize.search_form("οὐκ ἐπʼ ἄρτῳ μόνῳ", language: "grc")
      u2019 = Nabu::Normalize.search_form("οὐκ ἐπ’ ἄρτῳ μόνῳ", language: "grc")
      refute_equal u02bc, u2019, "the raw folded forms still differ by the apostrophe encoding"

      builder = engine
      assert_equal builder.send(:gram_tokens, u02bc), builder.send(:gram_tokens, u2019),
                   "gram-build elision strip collapses both encodings to the same tokens"
      assert_equal %w[ουκ επ αρτω μονω], builder.send(:gram_tokens, u02bc)
    end

    # == GOLDEN 3: John 1:1 → the Fathers, with dedupe + anchor exclusion ======

    JOHN_1_1 = "Ἐν ἀρχῇ ἦν ὁ λόγος, καὶ ὁ λόγος ἦν πρὸς τὸν θεόν, καὶ θεὸς ἦν ὁ λόγος"

    def test_golden_john_dedupes_witnesses_and_excludes_the_anchor_document
      john = make_document(urn: "urn:nt:john", title: "Gospel of John")
      make_passage(john, urn: "urn:nt:john:1.1", text: JOHN_1_1, sequence: 0)
      # The next verse of the SAME document also shares the opening — must NOT
      # appear (anchor's own document is excluded wholesale).
      make_passage(john, urn: "urn:nt:john:1.2", text: "#{JOHN_1_1} οὗτος ἦν ἐν ἀρχῇ", sequence: 1)
      # Clement quotes the verse in TWO places of ONE work → one hit, loci: 2.
      clement = make_document(urn: "urn:father:clem", title: "Clement")
      make_passage(clement, urn: "urn:father:clem:1", text: "γέγραπται γάρ· #{JOHN_1_1}", sequence: 0)
      make_passage(clement, urn: "urn:father:clem:2", text: "πάλιν· #{JOHN_1_1} ὁ εὐαγγελιστής", sequence: 1)
      rebuild!

      result = parallels("urn:nt:john:1.1")
      urns = result.hits.map(&:urn)
      refute_includes urns, "urn:nt:john:1.2", "the anchor's own document is excluded, sibling verses too"
      clem = result.hits.find { |h| h.urn.start_with?("urn:father:clem") }
      refute_nil clem, "the Father quoting the verse is found"
      assert_equal 2, clem.loci, "the two loci in Clement group under one document hit"
    end

    # -- exclusion set, argued in code --------------------------------------

    def test_translations_self_exclude_by_language
      grc = make_document(urn: "urn:w:grc", title: "Greek")
      make_passage(grc, urn: "urn:w:grc:1", text: ODYSSEY_1_1, sequence: 0)
      # An English translation of the SAME line shares no folded Greek token.
      eng = make_document(urn: "urn:w:eng", title: "English", language: "eng")
      make_passage(eng, urn: "urn:w:eng:1", language: "eng",
                        text: "Tell me, O Muse, of the man of many devices who wandered far", sequence: 0)
      rebuild!

      assert_empty parallels("urn:w:grc:1").hits,
                   "a translation shares no surface grams — it self-excludes, no rule needed"
    end

    # -- filters compose (catalog side, shared with Search) -----------------

    def test_language_and_license_filters_scope_candidates
      homer = make_document(urn: "urn:h:od", title: "Odyssey")
      make_passage(homer, urn: "urn:h:od:1.1", text: ODYSSEY_1_1, sequence: 0)
      openq = make_document(urn: "urn:q:open", title: "Open quoter")
      make_passage(openq, urn: "urn:q:open:1", text: "φησιν #{ODYSSEY_1_1}", sequence: 0)
      ncq = make_document(urn: "urn:q:nc", source: @nc, title: "NC quoter")
      make_passage(ncq, urn: "urn:q:nc:1", text: "λέγει #{ODYSSEY_1_1}", sequence: 0)
      rebuild!

      open_only = parallels("urn:h:od:1.1", license: "open").hits.map(&:urn)
      assert_includes open_only, "urn:q:open:1"
      refute_includes open_only, "urn:q:nc:1", "the nc quoter is filtered out by --license open"

      assert_empty parallels("urn:h:od:1.1", lang: "lat").hits,
                   "no Latin candidate exists — the language filter empties the result"
    end

    def test_limit_caps_the_hit_list
      homer = make_document(urn: "urn:h:od", title: "Odyssey")
      make_passage(homer, urn: "urn:h:od:1.1", text: ODYSSEY_1_1, sequence: 0)
      5.times do |i|
        doc = make_document(urn: "urn:q:#{i}", title: "Quoter #{i}")
        make_passage(doc, urn: "urn:q:#{i}:1", text: "φησιν #{ODYSSEY_1_1}", sequence: 0)
      end
      rebuild!

      assert_equal 2, parallels("urn:h:od:1.1", limit: 2).hits.size
    end

    # -- second signal: rare-lemma co-occurrence ----------------------------

    def test_lemma_echoes_find_passages_sharing_two_rare_lemmas
      # Anchor carries gold lemmas but NO verbatim quoter exists — only echoes.
      anchor = make_document(urn: "urn:le:anchor", title: "Anchor")
      make_passage(anchor, urn: "urn:le:anchor:1", text: "ἄρτος ἐκπορεύεται στόμα θεός", sequence: 0,
                           lemmas: [%w[ἄρτος ἄρτος], %w[ἐκπορεύομαι ἐκπορεύεται],
                                    %w[στόμα στόμα], %w[θεός θεός]])
      # Shares TWO rare lemmas (ἄρτος, στόμα), re-inflected — a lemma echo.
      echo = make_document(urn: "urn:le:echo", title: "Echo")
      make_passage(echo, urn: "urn:le:echo:1", text: "ἄρτον καὶ στόματι", sequence: 0,
                         lemmas: [%w[ἄρτος ἄρτον], %w[στόμα στόματι]])
      # Shares only ONE — below the ≥2 threshold, no echo.
      one = make_document(urn: "urn:le:one", title: "One")
      make_passage(one, urn: "urn:le:one:1", text: "θεοῦ λόγος", sequence: 0,
                        lemmas: [%w[θεός θεοῦ], %w[λόγος λόγος]])
      rebuild!

      result = parallels("urn:le:anchor:1")
      echoes = result.lemma_echoes.map(&:urn)
      assert_includes echoes, "urn:le:echo:1", "sharing ≥2 rare lemmas is an echo"
      refute_includes echoes, "urn:le:one:1", "sharing one rare lemma is not"
      hit = result.lemma_echoes.find { |e| e.urn == "urn:le:echo:1" }
      assert_equal %w[στόμα ἄρτος], hit.shared_lemmas.sort, "the shared lemmas are reported (dictionary forms)"
    end

    # P26-4 (the P26-0 journaled decision, pinned): lemma echoes are a
    # HEURISTIC DISCOVERY signal, so they deliberately read BOTH tiers — a
    # silver (automatic) anchor still finds echoes and a silver passage still
    # echoes a gold anchor; that is exactly what the Diorisis layer buys for
    # the un-annotated Perseus canon. No attestation count is rendered here.
    def test_lemma_echoes_read_both_tiers
      silver = Nabu::Store::Source.create(
        slug: "diorisis", name: "Diorisis", adapter_class: "TestAdapter",
        license_class: "attribution"
      )
      anchor = make_document(urn: "urn:le:anchor", title: "Anchor", source: silver)
      make_passage(anchor, urn: "urn:le:anchor:1", text: "ἄρτος ἐκπορεύεται στόμα θεός", sequence: 0,
                           lemmas: [%w[ἄρτος ἄρτος], %w[στόμα στόμα]])
      echo = make_document(urn: "urn:le:echo", title: "Echo")
      make_passage(echo, urn: "urn:le:echo:1", text: "ἄρτον καὶ στόματι", sequence: 0,
                         lemmas: [%w[ἄρτος ἄρτον], %w[στόμα στόματι]])
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext,
                                    lemma_tiers: { "diorisis" => "silver" })

      echoes = parallels("urn:le:anchor:1").lemma_echoes.map(&:urn)
      assert_includes echoes, "urn:le:echo:1",
                      "a silver anchor still finds gold echoes — the discovery surface reads both tiers"
    end

    def test_no_lemma_echoes_for_a_non_lemmatized_anchor
      anchor = make_document(urn: "urn:nl:a", title: "Anchor")
      make_passage(anchor, urn: "urn:nl:a:1", text: ODYSSEY_1_1, sequence: 0) # no lemmas
      other = make_document(urn: "urn:nl:b", title: "Other")
      make_passage(other, urn: "urn:nl:b:1", text: ODYSSEY_1_1, sequence: 0,
                          lemmas: [%w[ἀνήρ ἄνδρα], %w[μοῦσα μοῦσα]])
      rebuild!

      assert_empty parallels("urn:nl:a:1").lemma_echoes,
                   "a non-lemmatized anchor yields no echoes (one cheap query, then skip)"
    end

    # -- honest boundaries ---------------------------------------------------

    def test_unknown_urn_returns_nil
      rebuild!
      assert_nil parallels("urn:does:not:exist"), "an unresolvable urn is nil, not an empty result"
    end

    def test_passage_too_short_for_grams_has_no_hits
      doc = make_document(urn: "urn:s:d", title: "Short")
      make_passage(doc, urn: "urn:s:d:1", text: "ἄνδρα μοι", sequence: 0) # 2 tokens < 4
      make_passage(doc, urn: "urn:s:d:2", text: ODYSSEY_1_1, sequence: 1)
      rebuild!

      result = parallels("urn:s:d:1")
      assert_equal 0, result.gram_count
      assert_empty result.hits
    end

    def test_withdrawn_candidates_are_not_returned
      homer = make_document(urn: "urn:wd:od", title: "Odyssey")
      make_passage(homer, urn: "urn:wd:od:1.1", text: ODYSSEY_1_1, sequence: 0)
      gone = make_document(urn: "urn:wd:gone", title: "Withdrawn")
      make_passage(gone, urn: "urn:wd:gone:1", text: "φησιν #{ODYSSEY_1_1}", sequence: 0, withdrawn: true)
      rebuild!

      assert_empty parallels("urn:wd:od:1.1").hits, "withdrawn passages never surface (two-level visibility)"
    end

    # == D36-a: corpus-relative common-gram / rare-lemma cutoffs ===============
    #
    # Owner ruling 2026-07-20: the two df cutoffs are a FRACTION of the live
    # passage count, snapshot once per run, not frozen absolutes — an absolute
    # cutoff narrows recall as the corpus grows. The tuning-era constants stay
    # as the numerators (and the floor / unavailable-count fallback).

    def test_the_ratios_reproduce_the_tuning_era_absolute_cutoffs
      tuning = 3_760_000
      assert_equal 500, (Nabu::Query::Parallels::COMMON_GRAM_DF_RATIO * tuning).round,
                   "500 grams of the 3.76M tuning corpus (≈133 ppm) — the ratio's numerator"
      assert_equal 2_000, (Nabu::Query::Parallels::RARE_LEMMA_DF_RATIO * tuning).round,
                   "2,000 lemmas of the 3.76M tuning corpus (≈532 ppm)"
    end

    def test_cutoffs_snapshot_the_live_corpus_by_the_tuning_ratio
      doc = make_document(urn: "urn:cr:d", title: "D")
      make_passage(doc, urn: "urn:cr:d:1", text: ODYSSEY_1_1, sequence: 0)
      rebuild!
      eng = engine
      # The settled live corpus (24,415,015 passages) → 133 ppm of it. (No
      # minitest/mock in this suite: override the count read on the instance.)
      eng.define_singleton_method(:corpus_passage_count) { 24_415_015 }
      eng.run("urn:cr:d:1")
      assert_equal 3_247, eng.instance_variable_get(:@common_gram_df),
                   "round(24.4M × 500/3.76M) — the relative cutoff tracks the grown corpus"
      assert_equal 12_987, eng.instance_variable_get(:@rare_lemma_df),
                   "round(24.4M × 2,000/3.76M)"
    end

    def test_cutoffs_hold_at_the_absolute_floor_below_the_tuning_size
      doc = make_document(urn: "urn:fl:d", title: "D")
      make_passage(doc, urn: "urn:fl:d:1", text: ODYSSEY_1_1, sequence: 0)
      rebuild!
      eng = engine
      eng.run("urn:fl:d:1") # a handful of passages: round(n×ratio) ≪ floor
      assert_equal Nabu::Query::Parallels::COMMON_GRAM_DF,
                   eng.instance_variable_get(:@common_gram_df),
                   "below the tuning size the tuning constant is the floor — small corpora stay unpruned"
      assert_equal Nabu::Query::Parallels::RARE_LEMMA_DF,
                   eng.instance_variable_get(:@rare_lemma_df)
    end

    def test_cutoffs_fall_back_to_the_floor_when_the_corpus_count_is_unavailable
      doc = make_document(urn: "urn:fb:d", title: "D")
      make_passage(doc, urn: "urn:fb:d:1", text: ODYSSEY_1_1, sequence: 0)
      rebuild!
      eng = engine
      eng.define_singleton_method(:corpus_passage_count) { nil }
      eng.run("urn:fb:d:1")
      assert_equal Nabu::Query::Parallels::COMMON_GRAM_DF,
                   eng.instance_variable_get(:@common_gram_df),
                   "an unreadable corpus count trips the absolute fallback, not a zero cutoff"
      assert_equal Nabu::Query::Parallels::RARE_LEMMA_DF,
                   eng.instance_variable_get(:@rare_lemma_df)
    end
  end
end
