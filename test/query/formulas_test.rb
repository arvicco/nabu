# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::Formulas (P15-5, docs/intertext-design.md §5). Unlike Parallels,
  # the miner reads text_normalized STRAIGHT from the catalog (no fulltext index,
  # no Indexer rebuild) — so the rig is a bare in-memory catalog seeded with the
  # REAL formula shapes the design measured (the "saga hwaet ic hatte" riddle
  # refrain, a τὸν δ' … Homeric verse), scoped by slug and by urn prefix.
  class FormulasTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @aspr = Nabu::Store::Source.create(
        slug: "aspr", name: "ASPR", adapter_class: "TestAdapter", license_class: "open"
      )
      @greek = Nabu::Store::Source.create(
        slug: "perseus-greek", name: "Perseus", adapter_class: "TestAdapter", license_class: "open"
      )
    end

    # -- helpers -------------------------------------------------------------

    def make_document(urn:, source: @aspr, title: "Doc", language: "ang", withdrawn: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title, language: language,
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_passage(document, urn:, text:, sequence:, language: "ang", withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: language),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def formulas(scope, **)
      Nabu::Query::Formulas.new(catalog: @catalog).run(scope, **)
    end

    # A riddle document whose refrain "saga hwaet ic hatte" recurs, each line with
    # its own unique closing words (so only the refrain repeats).
    def seed_riddles(doc = make_document(urn: "urn:nabu:aspr:riddle"))
      ["foo bar", "baz qux", "alpha beta", "gamma delta"].each_with_index do |tail, i|
        make_passage(doc, urn: "#{doc.urn}:#{i}", sequence: i,
                          text: "saga hwaet ic hatte #{tail}")
      end
      doc
    end

    # == mining + ranking =====================================================

    def test_mines_the_recurring_formula
      seed_riddles
      result = formulas("aspr")
      top = result.formulas.first
      assert_equal "saga hwaet ic hatte", top.gram, "the refrain is the top formula"
      assert_equal 4, top.count, "it recurs once per riddle line"
      assert_equal 16, top.rank, "rank is count × gram length (4 × 4)"
    end

    def test_ranks_by_count_then_length
      seed_riddles # "saga hwaet ic hatte" × 4
      # A second refrain, rarer (×3) — must rank below the ×4 one.
      other = make_document(urn: "urn:nabu:aspr:gnomic")
      3.times do |i|
        make_passage(other, urn: "urn:nabu:aspr:gnomic:#{i}", sequence: i,
                            text: "wyrd bith ful araed uniq#{i} zzz")
      end
      grams = formulas("aspr").formulas.map(&:gram)
      assert_equal "saga hwaet ic hatte", grams.first
      assert_includes grams, "wyrd bith ful araed"
      assert_operator grams.index("saga hwaet ic hatte"), :<, grams.index("wyrd bith ful araed")
    end

    def test_min_count_filters_the_tail
      seed_riddles
      # A phrase appearing only twice is below the default floor of 3.
      pair = make_document(urn: "urn:nabu:aspr:pair")
      2.times do |i|
        make_passage(pair, urn: "urn:nabu:aspr:pair:#{i}", sequence: i,
                           text: "twice repeated phrase here #{i}")
      end
      default = formulas("aspr").formulas.map(&:gram)
      refute_includes default, "twice repeated phrase here", "×2 is below the default min-count 3"

      lowered = formulas("aspr", min_count: 2).formulas.map(&:gram)
      assert_includes lowered, "twice repeated phrase here", "--min-count 2 admits it"
    end

    def test_gram_size_controls_the_shingle_length
      seed_riddles
      result = formulas("aspr", gram_size: 3)
      top = result.formulas.first
      assert_equal "hwaet ic hatte", top.gram, "the 3-gram refrain (design measured this one, 16× live)"
      assert_equal 3, top.length
    end

    def test_no_stoplist_a_frequent_gram_is_never_silently_dropped
      # The stopword verdict, pinned: a repeated gram of common little words is
      # NOT filtered — it is simply ranked; nothing is hidden by a stoplist.
      doc = make_document(urn: "urn:nabu:aspr:common")
      4.times do |i|
        make_passage(doc, urn: "urn:nabu:aspr:common:#{i}", sequence: i,
                          text: "on the and to unique#{i} word#{i}")
      end
      grams = formulas("aspr").formulas.map(&:gram)
      assert_includes grams, "on the and to", "no stoplist — the ranking is the only filter"
    end

    # == scope ================================================================

    def test_scope_by_source_slug
      seed_riddles
      # A DIFFERENT source repeating another formula must not leak in.
      other_src = Nabu::Store::Source.create(
        slug: "iswoc", name: "ISWOC", adapter_class: "TestAdapter", license_class: "open"
      )
      od = make_document(urn: "urn:nabu:iswoc:x", source: other_src)
      3.times { |i| make_passage(od, urn: "urn:nabu:iswoc:x:#{i}", sequence: i, text: "elsewhere formula not mine") }

      grams = formulas("aspr").formulas.map(&:gram)
      assert_includes grams, "saga hwaet ic hatte"
      refute_includes grams, "elsewhere formula not mine", "the slug slice excludes other sources"
    end

    def test_scope_by_urn_prefix_spans_documents_under_it
      # Two documents under one super-prefix, each carrying the refrain.
      seed_riddles(make_document(urn: "urn:nabu:aspr:riddle"))
      seed_riddles(make_document(urn: "urn:nabu:aspr:exeter"))
      # A document OUTSIDE the prefix must not contribute.
      out = make_document(urn: "urn:nabu:aspr:beowulf")
      3.times { |i| make_passage(out, urn: "urn:nabu:aspr:beowulf:#{i}", sequence: i, text: "hwaet we gardena in") }

      result = formulas("urn:nabu:aspr:riddle")
      top = result.formulas.first
      assert_equal "saga hwaet ic hatte", top.gram
      refute result.formulas.any? { |f| f.gram == "hwaet we gardena in" }, "the prefix excludes urn:nabu:aspr:beowulf"
    end

    def test_unknown_scope_yields_an_empty_slice
      seed_riddles
      result = formulas("urn:nabu:nope:nothing")
      assert_equal 0, result.passage_count
      assert_empty result.formulas
    end

    # == language filter (design §5: mandatory for translation-bearing sources) =

    def test_lang_filters_the_slice
      # One source, two languages riding the same slug (perseus-greek: grc + eng).
      grc = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001", source: @greek, language: "grc")
      3.times do |i|
        make_passage(grc, urn: "urn:cts:greekLit:tlg0012.tlg001:#{i}", sequence: i, language: "grc",
                          text: "τὸν δ' αὖτε προσέειπε πόδας#{i}")
      end
      eng = make_document(urn: "urn:cts:greekLit:tlg0012.tlg001.eng", source: @greek, language: "eng")
      3.times do |i|
        make_passage(eng, urn: "urn:cts:greekLit:tlg0012.tlg001.eng:#{i}", sequence: i, language: "eng",
                          text: "then to him spoke swift#{i}")
      end

      grc_only = formulas("perseus-greek", lang: "grc").formulas.map(&:gram)
      assert_includes grc_only, "τον δ αυτε προσεειπε", "the folded Greek formula (elision stripped)"
      refute_includes grc_only, "then to him spoke", "the English formula is filtered out by --lang grc"

      eng_only = formulas("perseus-greek", lang: "eng").formulas.map(&:gram)
      assert_includes eng_only, "then to him spoke"
    end

    # == loci: compact examples vs --long full list ===========================

    def test_compact_caps_example_loci_long_lists_all
      seed_riddles # 4 loci for the refrain
      compact = formulas("aspr").formulas.first
      assert_equal Nabu::Query::Formulas::EXAMPLE_LOCI, compact.loci.size, "compact keeps a few examples"

      long = formulas("aspr", long: true).formulas.first
      assert_equal 4, long.loci.size, "--long gathers every locus"
      assert_equal %w[urn:nabu:aspr:riddle:0 urn:nabu:aspr:riddle:1
                      urn:nabu:aspr:riddle:2 urn:nabu:aspr:riddle:3], long.loci
    end

    def test_a_locus_is_a_passage_not_an_occurrence
      # The refrain twice in ONE line: counted twice, but the line is one locus.
      doc = make_document(urn: "urn:nabu:aspr:double")
      make_passage(doc, urn: "urn:nabu:aspr:double:0", sequence: 0,
                        text: "saga hwaet ic hatte saga hwaet ic hatte")
      make_passage(doc, urn: "urn:nabu:aspr:double:1", sequence: 1, text: "saga hwaet ic hatte end")
      formula = formulas("aspr", min_count: 2, long: true).formulas.first
      assert_equal 3, formula.count, "three overlapping occurrences (two in the doubled line)"
      assert_equal %w[urn:nabu:aspr:double:0 urn:nabu:aspr:double:1], formula.loci,
                   "loci are distinct passages, the doubled line counted once"
    end

    # == honest boundaries ====================================================

    def test_withdrawn_passages_do_not_contribute
      seed_riddles
      gone = make_document(urn: "urn:nabu:aspr:gone")
      3.times do |i|
        make_passage(gone, urn: "urn:nabu:aspr:gone:#{i}", sequence: i, text: "withdrawn phantom formula here",
                           withdrawn: true)
      end
      grams = formulas("aspr").formulas.map(&:gram)
      refute_includes grams, "withdrawn phantom formula here", "two-level visibility applies"
    end

    def test_gram_size_out_of_range_raises
      seed_riddles
      assert_raises(ArgumentError) { formulas("aspr", gram_size: 1) }
      assert_raises(ArgumentError) { formulas("aspr", gram_size: 20) }
    end

    def test_reports_slice_totals
      seed_riddles
      result = formulas("aspr")
      assert_equal 4, result.passage_count
      assert_equal 24, result.token_count, "6 tokens × 4 lines"
      assert_operator result.recurring_count, :>=, 1
    end
  end
end
