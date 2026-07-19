# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

module Adapters
  # Nabu::Adapters::SyriacCorpus (P31-4) — the Digital Syriac Corpus over
  # the new srophe-tei family: document = TEI file (the syriaccorpus.org
  # number), passage = text-bearing block in document order (the
  # addressability verdict: no uniform upstream citation scheme exists,
  # so the ordinal is the ref and the div path rides annotations).
  # Fixtures are six WHOLE real files at upstream commit 833adc14 — see
  # test/fixtures/syriac-corpus/README.md for why each was chosen.
  class SyriacCorpusTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("syriac-corpus")

    def conformance_adapter
      Nabu::Adapters::SyriacCorpus.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "syriac-corpus"
    end

    # -- registry / manifest --------------------------------------------------

    def test_registry_resolves_syriac_corpus_disabled_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["syriac-corpus"]
      refute_nil entry, "syriac-corpus must be registered in config/sources.yml"
      refute entry.enabled, "enabled: false until the owner-fired first real sync (checklist §6)"
      assert_equal "manual", entry.sync_policy
      assert_equal "syriac-corpus", entry.adapter_class.manifest.id
    end

    def test_manifest_is_attribution_with_the_availability_grant_verbatim
      manifest = Nabu::Adapters::SyriacCorpus.manifest
      assert_equal "attribution", manifest.license_class,
                   "CC BY 4.0 in every file's <availability> (censused over all 632) → attribution"
      assert_includes manifest.license, "Creative Commons — Attribution 4.0 International — CC BY 4.0"
      assert_includes manifest.license, "The Syriac base text is in the public domain"
      assert_equal "srophe-tei", manifest.parser_family
    end

    # -- discover -------------------------------------------------------------

    def test_discover_yields_one_ref_per_file_in_numeric_order
      refs = conformance_adapter.discover(FIXTURES).to_a
      assert_equal %w[
        urn:nabu:syriac-corpus:1
        urn:nabu:syriac-corpus:116
        urn:nabu:syriac-corpus:142
        urn:nabu:syriac-corpus:170
        urn:nabu:syriac-corpus:250
        urn:nabu:syriac-corpus:687
      ], refs.map(&:id), "the file number IS the identity (the syriaccorpus.org id; two files carry " \
                         "mismatched <idno>s upstream, so idno can never mint)"
    end

    def test_discover_yields_nothing_from_a_workdir_without_the_tree
      Dir.mktmpdir { |dir| assert_empty conformance_adapter.discover(dir).to_a }
    end

    def test_discovery_skips_flag_non_numeric_xml_as_unrecognized
      Dir.mktmpdir do |dir|
        tei = File.join(dir, "data", "tei")
        FileUtils.mkdir_p(tei)
        FileUtils.cp(File.join(FIXTURES, "data", "tei", "170.xml"), tei)
        FileUtils.cp(File.join(FIXTURES, "data", "tei", "170.xml"), File.join(tei, "stray.xml"))
        skips = conformance_adapter.discovery_skips(dir)
        assert_equal 1, skips.unrecognized, "a non-numeric xml under data/tei is a defect, not a norm"
        assert(skips.notes.any? { |note| note.include?("stray.xml") })
      end
    end

    # -- documents ------------------------------------------------------------

    def test_documents_carry_header_identity_and_the_work_concordance_lane
      aphrahat = parse_urn("urn:nabu:syriac-corpus:1")
      assert_equal "syc", aphrahat.language
      assert_includes aphrahat.title, "Demonstration 1: On Faith"
      assert_equal "Aphrahat", aphrahat.metadata["author"]
      assert_equal "http://syriaca.org/person/10", aphrahat.metadata["author_ref"]
      assert_equal "http://syriaca.org/work/8503", aphrahat.metadata["work"],
                   "the syriaca.org work URI — the future concordance lane"
      assert_equal "https://syriaccorpus.org/1", aphrahat.metadata["idno"]
      assert_equal "uncorrectedTranscription", aphrahat.metadata["status"],
                   "upstream's own transcription-quality label rides verbatim — silver is labeled"
      assert_equal({ "type" => "composition", "when" => "0337", "text" => "337 CE" },
                   aphrahat.metadata["orig_date"],
                   "attrs + flattened text (the editorial <note> inside origDate strips, like all notes)")
    end

    # -- passages: block grain with the citation lane -------------------------

    def test_passages_are_blocks_in_document_order_with_ordinal_urns
      aphrahat = parse_urn("urn:nabu:syriac-corpus:1")
      assert_equal 41, aphrahat.size, "title ab + 20 sections of head + p"
      assert_equal "urn:nabu:syriac-corpus:1:1", aphrahat.passages.first.urn
      section = aphrahat.passages[2]
      assert_equal "urn:nabu:syriac-corpus:1:3", section.urn
      assert section.text.start_with?("ܐܓܪܬܟ ܚܒܝܒܝ܃ ܩܒܠܬ܂"), "Dem. 1 §1 opens here"
      assert_equal "p", section.annotations["tag"]
      assert_equal [%w[section 1]], section.annotations["divs"],
                   "the div path is the citation lane the upstream numbering supports"
      assert_equal 129, parse_urn("urn:nabu:syriac-corpus:116").size
      assert_equal 15, parse_urn("urn:nabu:syriac-corpus:142").size
      assert_equal 6, parse_urn("urn:nabu:syriac-corpus:170").size
      assert_equal 5, parse_urn("urn:nabu:syriac-corpus:250").size
      assert_equal 7, parse_urn("urn:nabu:syriac-corpus:687").size
    end

    def test_verse_corpora_keep_line_grain_and_stanza_structure
      memra = parse_urn("urn:nabu:syriac-corpus:116")
      line = memra.passages.find { |p| p.annotations["n"] == "1" }
      assert_equal "l", line.annotations["tag"]
      assert_equal "ܬܰܪܥܳܐ ܪܰܒܳܐ ܦܼܬܰܚ ܠܺܝ ܝܰܘܣܶܦ ܕܰܫܟܰܚ̈ܳܬ݂ܳܐ", line.text
      hymn = parse_urn("urn:nabu:syriac-corpus:170")
      stanza = hymn.passages.find { |p| p.annotations["tag"] == "lg" }
      assert_includes stanza.text, "\n", "stanza lines keep their line breaks"
    end

    def test_block_languages_map_to_nabu_codes
      aphrahat = parse_urn("urn:nabu:syriac-corpus:1")
      assert(aphrahat.all? { |p| p.language == "syc" }, "syr and untagged blocks are syc")
      johannine = parse_urn("urn:nabu:syriac-corpus:142")
      chapter_head = johannine.passages.find { |p| p.annotations["tag"] == "head" }
      assert_equal "eng", chapter_head.language, "en heads map to eng, honestly"
      letter = parse_urn("urn:nabu:syriac-corpus:687")
      assert_includes letter.passages.map(&:language), "eng", "the parallel English translation blocks"
    end

    def test_apparatus_notes_ride_annotations_never_text
      letter = parse_urn("urn:nabu:syriac-corpus:687")
      noted = letter.passages.select { |p| p.annotations.key?("notes") }
      assert_equal 2, noted.size
      noted.each do |passage|
        passage.annotations["notes"].each do |note|
          refute_includes passage.text, note
        end
      end
    end

    # -- the license gate (the sarit re-verify discipline) --------------------

    def test_a_file_whose_licence_is_not_cc_by_quarantines_loudly
      Dir.mktmpdir do |dir|
        tei = File.join(dir, "data", "tei")
        FileUtils.mkdir_p(tei)
        source = File.read(File.join(FIXTURES, "data", "tei", "170.xml"))
        File.write(File.join(tei, "170.xml"),
                   source.sub("http://creativecommons.org/licenses/by/4.0/",
                              "http://creativecommons.org/licenses/by-nc/4.0/"))
        adapter = conformance_adapter
        ref = adapter.discover(dir).first
        error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
        assert_includes error.message, "by-nc",
                        "license drift on a per-file-licensed corpus must quarantine, never ingest"
      end
    end

    # -- idempotency ----------------------------------------------------------

    def test_double_load_is_idempotent
      catalog = store_test_db
      source = syriac_source
      first = Nabu::Store::Loader.new(db: catalog, source: source)
                                 .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal 6, first.added
      assert_equal 0, first.errored

      counts = [catalog[:documents].count, catalog[:passages].count]
      revisions = catalog[:documents].select_hash(:urn, :revision)
      Nabu::Store::Loader.new(db: catalog, source: source)
                         .load_from(conformance_adapter, workdir: FIXTURES, full: true)
      assert_equal counts, [catalog[:documents].count, catalog[:passages].count]
      assert_equal revisions, catalog[:documents].select_hash(:urn, :revision),
                   "unchanged documents must not fake content revisions"
    end

    private

    def parse_urn(urn)
      adapter = conformance_adapter
      ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
      refute_nil ref, "expected #{urn} in the discover set"
      adapter.parse(ref)
    end

    def syriac_source
      Nabu::Store::Source.create(
        slug: "syriac-corpus", name: "Digital Syriac Corpus",
        adapter_class: "Nabu::Adapters::SyriacCorpus", license_class: "attribution"
      )
    end
  end
end
