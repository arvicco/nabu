# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Query
  # Nabu::Query::Collation (P15-4, docs/intertext-design.md §2): the witness
  # DIFF over the alignment hub. Raw-token LCS within a (language, script) cell;
  # cross-script witnesses rendered undiffed. The golden is the live MARK 2.3
  # apparatus — the Helsinki-ASCII CCMH codices collated against each other with
  # the Cyrillic PROIEL Marianus honestly set aside.
  class CollationTest < Minitest::Test
    include StoreTestDB

    # Real MARK 2.3 texts from the live catalog — the four Helsinki-ASCII CCMH
    # codices (chu, Latin script), the Cyrillic PROIEL Marianus (chu, Cyrillic),
    # and the two Greek + two Latin witnesses that form clean same-script cells.
    MARIANUS_CU = "Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми."
    CCMH_ASSEMANIANUS = "*/i pridO k$ nemu nosEqe /oslablena ZIlamI . nosIm& Cet&ir$mI ."
    CCMH_MARIANUS = "*J pridO k& nemu nosESte oslablen& Zilami . nosim& Cetyr$mi ."
    CCMH_SAVVINA = "(i pridoSE k& nemu nosEqe (oslabena Zilami . nosim& Cetyr&mi ."
    CCMH_ZOGRAPHENSIS = "*(J pridoSE k& n^emu nosESte oslabl^ena Zilami . nosim& Cetyr$mi ."
    GREEK_PROIEL = "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων."
    GREEK_SBLGNT = "καὶ ἔρχονται ⸂φέροντες πρὸς αὐτὸν παραλυτικὸν⸃ αἰρόμενον ὑπὸ τεσσάρων."
    LATIN_PROIEL = "et venerunt ferentes ad eum paralyticum qui a quattuor portabatur"
    LATIN_VULGATE = "Et venerunt ad eum ferentes paralyticum, qui a quatuor portabatur."

    def setup
      @catalog = store_test_db
      @fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
      @source = Nabu::Store::Source.create(
        slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc"
      )
    end

    def teardown
      @fulltext.disconnect
    end

    # -- rig ---------------------------------------------------------------------

    # A registry over the seeded witnesses: each entry is [urn, label] (label
    # nil ⇒ the urn tail). All use the default proiel-citation extractor, so a
    # seeded passage's citation_part is the ref.
    def registry_for(entries)
      rows = entries.map do |urn, label|
        line = "    - document: #{urn}"
        line += "\n      label: #{label}" if label
        line
      end
      load_registry("nt:\n  title: \"New Testament (parallel witnesses)\"\n  witnesses:\n#{rows.join("\n")}\n")
    end

    def load_registry(yaml)
      Dir.mktmpdir do |dir|
        path = File.join(dir, "alignments.yml")
        File.write(path, yaml)
        return Nabu::AlignmentRegistry.load(path)
      end
    end

    def seed(urn, language:, text:, ref: "MARK 2.3", license: nil)
      unless @catalog[:documents].where(urn: urn).get(:id)
        @catalog[:documents].insert(
          source_id: @source.id, urn: urn, title: urn.split(":").last.capitalize,
          language: language, license_override: license, content_sha256: "x", revision: 1, withdrawn: false
        )
      end
      doc_id = @catalog[:documents].where(urn: urn).get(:id)
      seq = @catalog[:passages].where(document_id: doc_id).count
      @catalog[:passages].insert(
        document_id: doc_id, urn: "#{urn}:s#{seq}", sequence: seq, language: language,
        text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
        annotations_json: JSON.generate(
          "citation" => ref, "tokens" => [{ "citation_part" => ref, "form" => "x" }]
        )
      )
    end

    def collate(ref, registry, base: nil, long: false, exclude_licenses: [])
      Nabu::Store::AlignmentIndexer.rebuild!(catalog: @catalog, fulltext: @fulltext, registry: registry)
      Nabu::Query::Collation.new(catalog: @catalog, fulltext: @fulltext, registry: registry)
                            .run(ref, base: base, long: long, exclude_licenses: exclude_licenses)
    end

    # The four Helsinki CCMH codices (chu, Latin) + the Cyrillic Marianus, in
    # registry order (Marianus first, then CCMH alphabetical) — the live layout.
    def seed_chu_witnesses
      seed("urn:nabu:proiel:marianus", language: "chu", text: MARIANUS_CU)
      seed("urn:nabu:ccmh:assemanianus", language: "chu", text: CCMH_ASSEMANIANUS)
      seed("urn:nabu:ccmh:marianus", language: "chu", text: CCMH_MARIANUS)
      seed("urn:nabu:ccmh:savvina", language: "chu", text: CCMH_SAVVINA)
      seed("urn:nabu:ccmh:zographensis", language: "chu", text: CCMH_ZOGRAPHENSIS)
      registry_for([
                     ["urn:nabu:proiel:marianus", "marianus"],
                     ["urn:nabu:ccmh:assemanianus", "ccmh-assemanianus"],
                     ["urn:nabu:ccmh:marianus", "ccmh-marianus"],
                     ["urn:nabu:ccmh:savvina", "ccmh-savvina"],
                     ["urn:nabu:ccmh:zographensis", "ccmh-zographensis"]
                   ])
    end

    def cell_for(result, language, script)
      result.refs.first.cells.find { |cell| cell.language == language && cell.script == script }
    end

    # -- the golden: PROIEL Cyrillic Marianus vs the Helsinki CCMH codices --------

    def test_chu_latin_codices_collate_and_cyrillic_marianus_is_set_aside
      registry = seed_chu_witnesses
      result = collate("MARK 2.3", registry)

      cell = cell_for(result, "chu", "Latin")
      refute_nil cell, "the four Helsinki-ASCII CCMH codices form one chu/Latin cell"
      assert_equal 4, cell.readings.size
      # Base = first CCMH in registry order (assemanianus), the rest diff against it.
      assert_equal "ccmh-assemanianus", cell.base_label
      assert_equal %w[ccmh-assemanianus ccmh-marianus ccmh-savvina ccmh-zographensis],
                   cell.readings.map(&:label)

      # The Cyrillic Marianus cannot be folded into the Latin cell — set aside,
      # honestly, as cross-script (its language has Latin witnesses too).
      aside = result.refs.first.asides.find { |candidate| candidate.label == "marianus" }
      refute_nil aside
      assert_equal "Cyrillic", aside.script
      assert_equal :cross_script, aside.reason
      assert_equal MARIANUS_CU, aside.text
    end

    def test_real_ccmh_divergences_are_substitutions_marked_against_base
      registry = seed_chu_witnesses
      cell = cell_for(collate("MARK 2.3", registry), "chu", "Latin")
      marianus = cell.readings.find { |reading| reading.label == "ccmh-marianus" }

      # assemanianus */i pridO k$ nemu nosEqe /oslablena ZIlamI nosIm& Cet&ir$mI
      # marianus     *J  pridO k& nemu nosESte oslablen& Zilami nosim& Cetyr$mi
      # pridO and nemu ANCHOR the diff (shared tokens): */i→*J and k$→k& are
      # isolated substitutions; the unbroken run nosEqe…Cet&ir$mI (no shared
      # token between) is ONE substitution block — correct LCS behaviour.
      subs = marianus.edits.select { |edit| edit.op == :sub }.map { |edit| [edit.base, edit.witness] }
      assert_includes subs, [["*/i"], ["*J"]]
      assert_includes subs, [["k$"], ["k&"]]
      run = subs.find { |base, _witness| base.include?("nosEqe") }
      refute_nil run, "the medial variant run is collated as one substitution"
      assert_includes run[1], "nosESte", "the ослабленъ/nosESte reading is inside the run — markers kept raw"
      assert(marianus.edits.none? { |edit| %i[ins del].include?(edit.op) },
             "equal-length CCMH witnesses diverge only by substitution here")
    end

    # -- LCS correctness: insert / substitute / omit ------------------------------

    def controlled_pair(base_text, other_text)
      seed("urn:nabu:x:base", language: "lat", text: base_text)
      seed("urn:nabu:x:other", language: "lat", text: other_text)
      registry = registry_for([["urn:nabu:x:base", "base"], ["urn:nabu:x:other", "other"]])
      cell = cell_for(collate("MARK 2.3", registry), "lat", "Latin")
      cell.readings.find { |reading| reading.label == "other" }.edits
    end

    def test_lcs_marks_a_substitution
      edits = controlled_pair("alpha beta gamma", "alpha delta gamma")
      assert_equal [Nabu::Query::Collation::Edit.new(op: :sub, base: ["beta"], witness: ["delta"])], edits
    end

    def test_lcs_marks_an_omission
      edits = controlled_pair("alpha beta gamma delta", "alpha gamma delta")
      assert_equal [Nabu::Query::Collation::Edit.new(op: :del, base: ["beta"], witness: [])], edits
    end

    def test_lcs_marks_an_insertion
      edits = controlled_pair("alpha gamma delta", "alpha beta gamma delta")
      assert_equal [Nabu::Query::Collation::Edit.new(op: :ins, base: [], witness: ["beta"])], edits
    end

    def test_agreement_is_elided_entirely
      edits = controlled_pair("alpha beta gamma", "alpha beta gamma")
      assert_empty edits, "identical witnesses produce no apparatus entries"
    end

    def test_a_transposition_renders_honestly_as_delete_plus_insert
      # PROIEL "ferentes ad eum" vs Vulgate "ad eum ferentes" — a word-order
      # variant, honestly a deletion here and an insertion there (no transpose op).
      seed("urn:nabu:proiel:latin-nt", language: "lat", text: LATIN_PROIEL)
      seed("urn:nabu:vulgate:mrk", language: "lat", text: LATIN_VULGATE)
      registry = registry_for([["urn:nabu:proiel:latin-nt", "latin-nt"], ["urn:nabu:vulgate:mrk", "vulgate"]])
      cell = cell_for(collate("MARK 2.3", registry), "lat", "Latin")
      vulgate = cell.readings.find { |reading| reading.label == "vulgate" }
      ops = vulgate.edits.map(&:op)
      refute_empty ops, "a word-order variant produces apparatus entries"
      assert(ops.all? { |op| %i[sub del ins].include?(op) },
             "a transposition surfaces as ordinary sub/del/ins edits — there is no transpose op")
      assert_includes ops, :del, "the moved word is dropped from its old slot"
    end

    # -- script grouping ----------------------------------------------------------

    def test_two_greek_witnesses_form_a_greek_cell
      seed("urn:nabu:proiel:greek-nt", language: "grc", text: GREEK_PROIEL)
      seed("urn:nabu:sblgnt:mark", language: "grc", text: GREEK_SBLGNT)
      registry = registry_for([["urn:nabu:proiel:greek-nt", "greek-nt"], ["urn:nabu:sblgnt:mark", "sblgnt"]])
      cell = cell_for(collate("MARK 2.3", registry), "grc", "Greek")

      refute_nil cell
      assert_equal 2, cell.readings.size
      # Raw tokens keep the SBLGNT editorial brackets ⸂ ⸃ verbatim — the diff
      # surfaces them rather than folding them away.
      sblgnt = cell.readings.find { |reading| reading.label == "sblgnt" }
      assert(sblgnt.edits.any? { |edit| edit.witness.any? { |token| token.include?("⸂") } })
    end

    def test_same_script_different_language_do_not_share_a_cell
      # Gothic (Latin script) and Latin (Latin script) are different LANGUAGES —
      # never collated together despite the shared script.
      seed("urn:nabu:proiel:gothic-nt", language: "got",
                                        text: "jah qemun at imma usliþan bairandans, hafanana fram fidworim.")
      seed("urn:nabu:proiel:latin-nt", language: "lat", text: LATIN_PROIEL)
      registry = registry_for([["urn:nabu:proiel:gothic-nt", "gothic-nt"], ["urn:nabu:proiel:latin-nt", "latin-nt"]])
      result = collate("MARK 2.3", registry)

      assert_empty result.refs.first.cells, "no two witnesses share BOTH language and script"
      assert_equal 2, result.refs.first.asides.size
      assert(result.refs.first.asides.all? { |aside| aside.reason == :sole },
             "each is the sole witness of its language — not a cross-script split")
    end

    # -- cross-script honesty ------------------------------------------------------

    def test_a_sole_language_witness_is_set_aside_as_sole_not_cross_script
      registry = seed_chu_witnesses
      # Gothic added: alone in got/Latin → :sole, distinct from the chu Cyrillic
      # Marianus whose language HAS Latin witnesses (→ :cross_script).
      seed("urn:nabu:proiel:gothic-nt", language: "got", text: "jah qemun at imma usliþan.")
      registry2 = registry_for([
                                 ["urn:nabu:proiel:marianus", "marianus"],
                                 ["urn:nabu:ccmh:assemanianus", "ccmh-assemanianus"],
                                 ["urn:nabu:ccmh:marianus", "ccmh-marianus"],
                                 ["urn:nabu:ccmh:savvina", "ccmh-savvina"],
                                 ["urn:nabu:ccmh:zographensis", "ccmh-zographensis"],
                                 ["urn:nabu:proiel:gothic-nt", "gothic-nt"]
                               ])
      result = collate("MARK 2.3", registry2)
      _ = registry # silence: the first registry was only for its seeds

      gothic = result.refs.first.asides.find { |aside| aside.label == "gothic-nt" }
      marianus = result.refs.first.asides.find { |aside| aside.label == "marianus" }
      assert_equal :sole, gothic.reason
      assert_equal :cross_script, marianus.reason
    end

    # -- --base override ----------------------------------------------------------

    def test_base_override_by_label
      registry = seed_chu_witnesses
      cell = cell_for(collate("MARK 2.3", registry, base: "ccmh-marianus"), "chu", "Latin")
      assert_equal "ccmh-marianus", cell.base_label
      assert_equal "ccmh-marianus", cell.readings.first.label, "the base heads its cell"
    end

    def test_base_override_that_matches_nothing_raises
      registry = seed_chu_witnesses
      error = assert_raises(Nabu::Query::Collation::Error) do
        collate("MARK 2.3", registry, base: "nonesuch")
      end
      assert_match(/no witness matches --base/, error.message)
    end

    # -- --long -------------------------------------------------------------------

    def test_long_carries_full_tokens_per_witness
      registry = seed_chu_witnesses
      cell = cell_for(collate("MARK 2.3", registry, long: true), "chu", "Latin")
      marianus = cell.readings.find { |reading| reading.label == "ccmh-marianus" }
      # The tokens are the RAW witness tokens, punctuation-only "." dropped.
      assert_equal %w[*J pridO k& nemu nosESte oslablen& Zilami nosim& Cetyr$mi], marianus.tokens
      refute_includes marianus.tokens, ".", "a bare punctuation token is dropped"
    end

    # -- range mode: per-ref apparatus --------------------------------------------

    def test_range_mode_yields_one_apparatus_per_ref
      seed("urn:nabu:ccmh:assemanianus", language: "chu", text: CCMH_ASSEMANIANUS, ref: "MARK 2.3")
      seed("urn:nabu:ccmh:marianus", language: "chu", text: CCMH_MARIANUS, ref: "MARK 2.3")
      seed("urn:nabu:ccmh:assemanianus", language: "chu", text: "drUgy pridO", ref: "MARK 2.4")
      seed("urn:nabu:ccmh:marianus", language: "chu", text: "drugy pridoSE", ref: "MARK 2.4")
      registry = registry_for([["urn:nabu:ccmh:assemanianus", "ccmh-assemanianus"],
                               ["urn:nabu:ccmh:marianus", "ccmh-marianus"]])
      result = collate("MARK 2.3-2.4", registry)

      assert_equal ["MARK 2.3", "MARK 2.4"], result.refs.map(&:ref)
      assert(result.refs.all? { |rc| rc.cells.size == 1 }, "each ref collates its own witnesses")
    end

    # -- license withholding (the MCP gate) ---------------------------------------

    def test_excluded_license_witnesses_are_withheld_from_the_diff
      seed("urn:nabu:proiel:greek-nt", language: "grc", text: GREEK_PROIEL)
      seed("urn:nabu:sblgnt:mark", language: "grc", text: GREEK_SBLGNT, license: "restricted")
      registry = registry_for([["urn:nabu:proiel:greek-nt", "greek-nt"], ["urn:nabu:sblgnt:mark", "sblgnt"]])
      result = collate("MARK 2.3", registry, exclude_licenses: ["restricted"])

      assert_empty result.refs.first.cells, "the restricted witness cannot form a cell alone"
      withheld = result.refs.first.missing.find { |missing| missing.label == "sblgnt" }
      assert_equal :withheld, withheld.status
    end
  end
end
