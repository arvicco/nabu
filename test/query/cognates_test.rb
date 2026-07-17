# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"

module Query
  # Nabu::Query::Cognates (P15-3, design §6): the alignment-hub × reflex-
  # crosswalk join — verses of a registered work where witnesses in ≥2
  # languages use reflexes of the same reconstruction root. The shelf side
  # loads from the REAL wiktionary-recon fixtures; the hub side is the
  # AlignmentIndexer rig (sentences whose tokens carry citation_part AND
  # gold lemmas, so one rebuild feeds passage_lemmas, alignment_refs, and
  # reflex_roots together — exactly as production does).
  class CognatesTest < Minitest::Test
    include StoreTestDB

    NT_REGISTRY = <<~YAML
      nt:
        title: "New Testament (test witnesses)"
        witnesses:
          - document: urn:nabu:test:grc-nt
          - document: urn:nabu:test:marianus
          - document: urn:nabu:test:gothic
          - document: urn:nabu:test:oe-mark
    YAML

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      recon = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryRecon",
        license: "CC-BY-SA + GFDL", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: @catalog, source: recon)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      @texts = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc"
      )
      @docs = {}
    end

    def teardown
      @fulltext.disconnect
    end

    # -- rig ------------------------------------------------------------------

    def registry(yaml = NT_REGISTRY)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "alignments.yml")
        File.write(path, yaml)
        return Nabu::AlignmentRegistry.load(path)
      end
    end

    def witness_doc(tail, language:, title: tail)
      @docs[tail] ||= Nabu::Store::Document.create(
        source_id: @texts.id, urn: "urn:nabu:test:#{tail}", title: title,
        language: language, content_sha256: "x", revision: 1, withdrawn: false
      )
    end

    # One witness sentence: verse identity in the token citation_parts (the
    # PROIEL shape), gold lemmas in the same tokens.
    def make_sentence(doc, ref:, lemmas:, forms: nil)
      seq = @catalog[:passages].where(document_id: doc.id).count
      tokens = lemmas.each_with_index.map do |lemma, i|
        { "citation_part" => ref, "lemma" => lemma, "form" => (forms || lemmas)[i] }
      end
      Nabu::Store::Passage.create(
        document_id: doc.id, urn: "#{doc.urn}:#{seq + 1}", sequence: seq,
        language: doc.language, text: "t", text_normalized: "t",
        annotations_json: JSON.generate({ "citation" => ref, "tokens" => tokens }),
        content_sha256: "x", revision: 1
      )
    end

    # Unaligned gold passages — inflate a lemma's corpus df without touching
    # the hub (suppression is a corpus-wide judgement).
    def inflate_df(language:, lemma:, count:)
      doc = witness_doc("filler-#{language}", language: language)
      count.times { make_sentence(doc, ref: "X 1.1", lemmas: [lemma]) }
    end

    def seed_gospel_verses
      grc = witness_doc("grc-nt", language: "grc", title: "Greek NT")
      chu = witness_doc("marianus", language: "chu", title: "Codex Marianus")
      got = witness_doc("gothic", language: "got", title: "Gothic NT")
      ang = witness_doc("oe-mark", language: "ang", title: "OE Mark")
      make_sentence(grc, ref: "MARK 1.1", lemmas: ["ἔφᾰγον"], forms: ["ἔφαγεν"])
      make_sentence(chu, ref: "MARK 1.1", lemmas: ["богъ"], forms: ["ба"])
      make_sentence(got, ref: "MARK 1.1", lemmas: ["guþ"])
      make_sentence(chu, ref: "MARK 1.2", lemmas: ["богъ"]) # only one language reaches the root
      make_sentence(ang, ref: "MARK 2.1", lemmas: ["cāsere"])
      make_sentence(chu, ref: "MARK 2.1", lemmas: ["цѣсар҄ь"])
    end

    def rebuild!(reg = registry)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: reg)
    end

    def cognates(reg = registry)
      Nabu::Query::Cognates.new(catalog: @catalog, fulltext: @fulltext, registry: reg)
    end

    def run_cognates(target, **)
      cognates.run(target, **)
    end

    # -- the join --------------------------------------------------------------

    def test_a_verse_where_two_languages_share_a_root_groups_them_under_it
      seed_gospel_verses
      rebuild!
      result = run_cognates("MARK 1.1")
      assert_equal "nt", result.work
      assert_equal "MARK 1.1", result.query
      assert_equal 1, result.groups.size
      group = result.groups.first
      assert_equal "MARK 1.1", group.ref
      assert_equal "*bʰeh₂g-", group.root.headword
      assert_equal "ine-pro", group.root.shelf
      assert_equal "attribution", group.root.license_class
      assert_equal %w[chu grc], group.witnesses.map(&:language).sort
      grc = group.witnesses.find { |w| w.language == "grc" }
      assert_equal "ἔφᾰγον", grc.lemma
      assert_includes grc.surfaces, "ἔφαγεν"
      assert_equal ["urn:nabu:test:grc-nt"], grc.document_urns
      assert_equal ["urn:nabu:test:grc-nt:1"], grc.passage_urns,
                   "the attesting passage urns ride the witness word (BatchCognates' edge anchor)"
    end

    # P18-3: the join is hash-keyed at every level — (ref, root) → language
    # → lemma_folded — so even raw duplicate closure rows (impossible from
    # the indexer's build, forced here directly) render ONE group with ONE
    # witness word per language, never a doubled row.
    def test_duplicate_closure_rows_render_one_group_with_one_witness_word_each
      seed_gospel_verses
      rebuild!
      table = @fulltext[Nabu::Store::ReflexRootsIndexer::TABLE]
      row = table.where(language: "chu", lemma_folded: "богъ",
                        root_urn: "urn:nabu:dict:wiktionary-ine-pro:bʰeh₂g-:root").first
      refute_nil row, "the closure must hold the chu богъ → *bʰeh₂g- row"
      table.insert(row)

      result = run_cognates("MARK 1.1")
      assert_equal 1, result.groups.size, "one (verse, root) group, not one per closure row"
      group = result.groups.first
      assert_equal %w[chu grc], group.witnesses.map(&:language).sort
      assert_equal 1, group.witnesses.count { |w| w.language == "chu" },
                   "the doubled closure row renders one witness word"
    end

    def test_a_root_reached_by_one_language_only_is_no_cognate_hit
      seed_gospel_verses
      rebuild!
      assert_empty run_cognates("MARK 1.2").groups,
                   "chu богъ alone is attestation, not a cross-language meet"
    end

    def test_a_loan_meet_is_labeled_with_the_lending_shelf
      seed_gospel_verses
      rebuild!
      group = run_cognates("MARK 2.1").groups.first
      assert_equal "*kaisaraz", group.root.headword
      assert_equal "gem-pro", group.root.shelf,
                   "цѣсар҄ь ~ cāsere meet at the GERMANIC shelf — a borrowing, and the shelf " \
                   "label is what lets the renderer say so"
    end

    def test_a_chapter_query_covers_its_verses
      seed_gospel_verses
      rebuild!
      result = run_cognates("MARK 1")
      assert_equal ["MARK 1.1"], result.groups.map(&:ref).uniq
      assert_equal "MARK 1", result.query
    end

    def test_a_work_id_batches_the_whole_work_in_citation_order
      seed_gospel_verses
      rebuild!
      result = run_cognates("nt")
      assert_equal ["MARK 1.1", "MARK 2.1"], result.groups.map(&:ref)
      assert_equal "nt", result.query
      assert_equal 2, result.total
      refute result.truncated
    end

    def test_langs_restricts_the_comparison_set
      seed_gospel_verses
      rebuild!
      assert_empty run_cognates("MARK 1.1", langs: %w[got chu]).groups,
                   "got guþ and chu богъ share no root — restricting to that pair must not " \
                   "let the grc×chu meet through"
      refute_empty run_cognates("MARK 1.1", langs: %w[grc chu]).groups
    end

    def test_langs_needs_at_least_two_languages
      seed_gospel_verses
      rebuild!
      error = assert_raises(Nabu::Query::Cognates::Error) { run_cognates("MARK 1.1", langs: %w[chu]) }
      assert_match(/at least two/, error.message)
    end

    def test_witness_documents_carry_their_effective_license
      seed_gospel_verses
      rebuild!
      result = run_cognates("MARK 1.1")
      assert_equal "nc", result.documents.fetch("urn:nabu:test:marianus").fetch(:license_class)
    end

    # -- common-word suppression ------------------------------------------------

    def test_common_lemmas_are_suppressed_by_default_and_shown_with_all
      seed_gospel_verses
      # Make both sides of the MARK 1.1 meet corpus-common: df ≥ max(50, 10%).
      inflate_df(language: "grc", lemma: "ἔφᾰγον", count: 60)
      inflate_df(language: "chu", lemma: "богъ", count: 60)
      rebuild!
      result = run_cognates("MARK 1.1")
      assert_empty result.groups
      assert_equal 1, result.suppressed
      all = run_cognates("MARK 1.1", all: true)
      assert_equal 1, all.groups.size
      assert_equal 0, all.suppressed
    end

    def test_suppression_never_fires_in_a_corpus_too_small_to_judge
      seed_gospel_verses
      rebuild!
      # Every fixture lemma is 100% of its tiny corpus — the absolute df
      # floor is what keeps "common" a real judgement, not a small-N artifact.
      result = run_cognates("MARK 1.1")
      assert_equal 1, result.groups.size
      assert_equal 0, result.suppressed
    end

    # -- P26-4: gold-tier scope (silver is not reconstruction evidence) -----------

    def silver_source
      @silver_source ||= Nabu::Store::Source.create(
        slug: "diorisis", name: "Diorisis", adapter_class: "TestAdapter",
        license_class: "attribution"
      )
    end

    def silver_rebuild!(reg = registry)
      Nabu::Store::Indexer.rebuild!(catalog: @catalog, fulltext: @fulltext, alignments: reg,
                                    lemma_tiers: { "diorisis" => "silver" })
    end

    # THE REFUTATION: with the grc witness edition declared silver, MARK 1.1
    # loses its grc evidence and the chu-only remainder is no meet — an
    # automatic lemmatization must never claim "this verse attests a reflex".
    def test_a_silver_witness_contributes_no_cognate_evidence
      @docs["grc-nt"] = Nabu::Store::Document.create(
        source_id: silver_source.id, urn: "urn:nabu:test:grc-nt", title: "Greek NT (silver)",
        language: "grc", content_sha256: "x", revision: 1, withdrawn: false
      )
      seed_gospel_verses
      silver_rebuild!
      assert_empty run_cognates("MARK 1.1").groups,
                   "the silver grc witness dropped out; chu alone is no cross-language meet"
    end

    # A silver flood must not re-judge a gold lemma common: the suppression
    # df and its stats denominator are both gold-scoped, so 60 silver filler
    # passages change nothing.
    def test_silver_rows_never_inflate_the_suppression_df
      seed_gospel_verses
      doc = Nabu::Store::Document.create(
        source_id: silver_source.id, urn: "urn:nabu:test:silver-filler", title: "F",
        language: "chu", content_sha256: "x", revision: 1, withdrawn: false
      )
      60.times { make_sentence(doc, ref: "X 1.1", lemmas: ["богъ"]) }
      silver_rebuild!
      result = run_cognates("MARK 1.1")
      assert_equal 1, result.groups.size, "the gold meet survives the silver flood"
      assert_equal 0, result.suppressed
    end

    # -- honest failure states ----------------------------------------------------

    def test_without_the_roots_table_the_error_names_the_fix
      seed_gospel_verses
      rebuild!
      @fulltext.drop_table(Nabu::Store::ReflexRootsIndexer::TABLE)
      error = assert_raises(Nabu::Query::Cognates::Error) { run_cognates("MARK 1.1") }
      assert_match(/nabu sync or nabu rebuild/, error.message)
    end

    def test_an_unknown_work_or_unattested_ref_reads_honestly
      seed_gospel_verses
      rebuild!
      error = assert_raises(Nabu::Query::Cognates::Error) { run_cognates("JOHN 99.1") }
      assert_match(/not attested/, error.message)
    end

    def test_an_empty_registry_raises_the_registry_hint
      rebuild!(registry(""))
      error = assert_raises(Nabu::Query::Cognates::Error) { cognates(registry("")).run("nt") }
      assert_match(/alignments.yml/, error.message)
    end

    # -- P17-3: the per-edge borrowed flag (the JOHN 13.18 acceptance case) ----

    # hlaifs ~ хлѣбъ at *hlaibaz: before P17-3 the reader had to apply the
    # taught meet-shelf reading ("gem-pro + Slavic witness = probably a
    # loan"); now the OCS witness's edge is FLAGGED (the loan marker rides
    # the gem→sla proto edge and ORs along the closure path) while the
    # Gothic side stays an unflagged inheritance claim.
    def test_witness_borrowed_flag_states_the_loan_per_edge
      chu = witness_doc("marianus", language: "chu", title: "Codex Marianus")
      got = witness_doc("gothic", language: "got", title: "Gothic NT")
      make_sentence(chu, ref: "JOHN 13.18", lemmas: ["хлѣбъ"])
      make_sentence(got, ref: "JOHN 13.18", lemmas: ["hlaifs"])
      rebuild!
      result = run_cognates("JOHN 13.18")
      group = result.groups.find { |g| g.root.headword == "*hlaibaz" } ||
              flunk("hlaifs and хлѣбъ must meet at gem-pro *hlaibaz")
      assert_equal "gem-pro", group.root.shelf
      chu_word = group.witnesses.find { |w| w.language == "chu" }
      assert_equal true, chu_word.borrowed, "the OCS descent from *hlaibaz is a flagged loan"
      got_word = group.witnesses.find { |w| w.language == "got" }
      assert_equal false, got_word.borrowed, "the Gothic side stays an inheritance claim"
    end

    def test_excluded_licenses_drop_their_witnesses
      seed_gospel_verses
      # The chu witness becomes research_private: its words must vanish and
      # the grc×chu meet with them (the MCP include_restricted contract).
      @catalog[:documents].where(urn: "urn:nabu:test:marianus").update(license_override: "research_private")
      rebuild!
      result = cognates.run("MARK 1.1", exclude_license: %w[research_private restricted])
      assert_empty result.groups
      shown = cognates.run("MARK 1.1", exclude_license: [])
      assert_equal 1, shown.groups.size
    end
  end
end
