# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Concord (P8-3) — the KWIC formatter over Search/LemmaSearch.
  # Same rig as SearchTest: an in-memory catalog + a separate in-memory
  # fulltext rebuilt with the real Indexer, so the fold-both-sides fold that
  # the keyword-location relies on is exercised end to end.
  class ConcordTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @open = Nabu::Store::Source.create(
        slug: "open", name: "Open", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- helpers -------------------------------------------------------------

    def make_document(source: @open, urn: "urn:d:1", title: "Iliad", language: "grc",
                      license_override: nil)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        license_override: license_override, content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    def make_passage(document, urn:, text:, sequence:, language: "grc", lemmas: nil)
      annotations = if lemmas
                      JSON.generate({ "tokens" => lemmas.map { |l, f| { "lemma" => l, "form" => f } } })
                    else
                      "{}"
                    end
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        annotations_json: annotations, content_sha256: "x", revision: 1
      )
    end

    def rebuild!
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext)
    end

    def concord(query = nil, **)
      Nabu::Query::Concord.new(catalog: @catalog, fulltext: @fulltext).run(query, **)
    end

    # -- text mode: keyword located in pristine text -------------------------

    # THE mapping test: an UNACCENTED query locates the keyword inside a Greek
    # passage carrying combining marks, and the row shows the PRISTINE accented
    # spelling — not the folded form.
    def test_text_mode_locates_the_pristine_accented_keyword
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", text: "θεὰ μῆνιν ἄειδε", sequence: 0)
      rebuild!

      rows = concord("μηνιν", width: 6)
      assert_equal 1, rows.size
      row = rows.first
      assert_equal "μῆνιν", row.keyword, "the pristine accented keyword, not the folded μηνιν"
      assert_equal "θεὰ ".rjust(6), row.left
      assert_equal " ἄειδε".ljust(6), row.right
    end

    def test_text_mode_carries_urn_language_and_license
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν ἄειδε", sequence: 0)
      rebuild!

      row = concord("μηνιν").first
      assert_equal "urn:d:1:1", row.urn
      assert_equal "grc", row.language
      assert_equal "open", row.license_class
    end

    # -- width trimming + ellipses -------------------------------------------

    def test_width_trims_both_sides_with_ellipses
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1",
                        text: "ααααααααα ββββββββββ μῆνιν γγγγγγγγγγ δδδδδδδδδ", sequence: 0)
      rebuild!

      row = concord("μηνιν", width: 8).first
      assert_equal 8, row.left.length, "left trimmed to width"
      assert_equal 8, row.right.length, "right trimmed to width"
      assert row.left.start_with?("…"), "clipped left context marked with a leading ellipsis"
      assert row.right.end_with?("…"), "clipped right context marked with a trailing ellipsis"
    end

    def test_short_context_is_padded_not_ellipsized
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", text: "θεὰ μῆνιν ἄειδε", sequence: 0)
      rebuild!

      row = concord("μηνιν", width: 20).first
      assert_equal 20, row.left.length
      refute_includes row.left, "…"
      assert row.left.end_with?("θεὰ ")
    end

    # -- alignment: keyword column identical across rows ---------------------

    def test_keyword_column_is_aligned_across_varying_length_matches
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", text: "alpha μῆνιν beta", sequence: 0)
      make_passage(doc, urn: "urn:d:1:2", text: "gamma μῆνις delta epsilon", sequence: 1)
      rebuild!

      # Two different pristine keywords (μῆνιν vs μῆνις): a prefix query hits both.
      rows = concord("μηνι*", width: 12)
      assert_equal 2, rows.size
      assert_equal [12], rows.map { |r| r.left.length }.uniq,
                   "every left context is exactly width chars → the keyword column lines up"
      assert_equal %w[μῆνιν μῆνις], rows.map(&:keyword)
    end

    # -- occurrence policy: first occurrence per passage ---------------------

    def test_multiple_occurrences_in_one_passage_yield_one_row_at_the_first
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", text: "μῆνιν πρώτη καὶ μῆνιν δευτέρα", sequence: 0)
      rebuild!

      rows = concord("μηνιν", width: 40)
      assert_equal 1, rows.size, "one row per passage, not one per occurrence"
      assert rows.first.left.strip.empty?, "the keyword is located at the FIRST occurrence"
    end

    # -- corpus order, not rank order ----------------------------------------

    def test_rows_come_in_corpus_urn_order_not_rank_order
      doc = make_document
      # A denser match would rank first in Search; concord must not use that order.
      make_passage(doc, urn: "urn:d:1:a", text: "μῆνιν once", sequence: 0)
      make_passage(doc, urn: "urn:d:1:b", text: "μῆνιν μῆνιν μῆνιν thrice", sequence: 1)
      rebuild!

      assert_equal %w[urn:d:1:a urn:d:1:b], concord("μηνιν").map(&:urn)
    end

    # -- lemma mode: surface form located ------------------------------------

    def test_lemma_mode_locates_the_matched_surface_form
      doc = make_document(urn: "urn:d:tb", title: "Treebank")
      make_passage(doc, urn: "urn:d:tb:1", text: "σὺ δὲ εἶπας τάδε", sequence: 0,
                        lemmas: [%w[λέγω εἶπας]])
      rebuild!

      rows = concord(nil, lemma: "λέγω", width: 6)
      assert_equal 1, rows.size
      assert_equal "εἶπας", rows.first.keyword, "the inflected surface form is the located keyword"
      assert_equal "σὺ δὲ ".rjust(6), rows.first.left
    end

    # -- filters --------------------------------------------------------------

    def test_lang_filter_scopes_the_concordance
      grc = make_document(urn: "urn:d:grc", language: "grc")
      make_passage(grc, urn: "urn:d:grc:1", text: "aurora surgit", sequence: 0, language: "grc")
      lat = make_document(urn: "urn:d:lat", language: "lat")
      make_passage(lat, urn: "urn:d:lat:1", text: "aurora venit", sequence: 0, language: "lat")
      rebuild!

      assert_equal %w[urn:d:lat:1], concord("aurora", lang: "lat").map(&:urn)
    end

    def test_license_filter_is_exact_class
      doc = make_document(urn: "urn:d:1", license_override: "nc")
      make_passage(doc, urn: "urn:d:1:1", text: "libertas μῆνιν", sequence: 0)
      rebuild!

      assert_empty concord("μηνιν", license: "open")
      assert_equal %w[urn:d:1:1], concord("μηνιν", license: "nc").map(&:urn)
    end

    def test_limit_caps_the_row_count
      doc = make_document
      5.times { |i| make_passage(doc, urn: "urn:d:1:#{i}", text: "aurora #{i}", sequence: i) }
      rebuild!

      assert_equal 3, concord("aurora", limit: 3).size
    end

    def test_no_match_returns_empty
      doc = make_document
      make_passage(doc, urn: "urn:d:1:1", text: "aurora", sequence: 0)
      rebuild!

      assert_empty concord("nonexistentword")
    end

    # -- diplomatic line-break rejoining (P14-5, conventions §9) --------------
    #
    # A ccmh-txt hyphen line indexes the COMPLETED word (text_normalized is
    # the fold of the rejoined derivation) while the pristine display keeps
    # the fragment + hyphen. Concord must highlight HONESTLY: the keyword is
    # the visible "mOdrova-" up to the line end — the appended tail maps to
    # the hyphen/EOL position — never fabricated display text.

    def make_hyphen_line(doc, urn:, text:, join:, sequence:)
      source = Nabu::Adapters::CcmhTxtParser.search_source(text, { "hyphen_join" => join })
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: urn, sequence: sequence, language: "chu",
        text: text,
        text_normalized: Nabu::Normalize.search_form(source, language: "chu"),
        annotations_json: JSON.generate({ "hyphen_join" => join }),
        content_sha256: "x", revision: 1
      )
    end

    def test_hyphen_split_keyword_highlights_the_visible_fragment_to_eol
      doc = make_document(title: "Suprasliensis", language: "chu")
      make_hyphen_line(doc, urn: "urn:d:1:1", text: ")i do s&mr)$ti . ne dobr@ mOdrova-",
                            join: { "tail" => "ti" }, sequence: 0)
      rebuild!

      rows = concord("mOdrovati", width: 10)
      assert_equal 1, rows.size, "the split word must be findable"
      row = rows.first
      assert_equal "mOdrova-", row.keyword,
                   "the keyword is what the line actually shows — fragment + hyphen, tail mapped to EOL"
      assert_equal "…ne dobr@ ", row.left
      assert_equal " " * 10, row.right, "nothing follows the hyphen on the pristine line"
    end

    def test_hyphen_continuation_line_locates_its_real_words_normally
      doc = make_document(title: "Suprasliensis", language: "chu")
      make_hyphen_line(doc, urn: "urn:d:1:2", text: "ti na c@lomOdrovanije k& bogu .",
                            join: { "orphan" => "ti" }, sequence: 0)
      rebuild!

      row = concord("bogu", width: 8).first
      refute_nil row
      assert_equal "bogu", row.keyword, "words on the continuation line locate via the normal path"
    end

    def test_hyphen_line_without_a_tail_annotation_falls_back_to_the_whole_line
      # A display ending in "-" whose passage carries NO hyphen_join tail
      # (e.g. a document-final fragment) keeps the defensive empty-keyword
      # fallback: the line renders, nothing is invented.
      doc = make_document(title: "Suprasliensis", language: "chu")
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "urn:d:1:3", sequence: 0, language: "chu",
        text: "kon)$C$no slo- mOdrovati", # a real word makes it findable; the "-" is mid-line
        text_normalized: Nabu::Normalize.search_form("kon)$C$no slo- mOdrovati", language: "chu"),
        annotations_json: "{}", content_sha256: "x", revision: 1
      )
      rebuild!

      row = concord("mOdrovati").first
      assert_equal "mOdrovati", row.keyword
    end
  end
end
