# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::Achemenet (P77-r18, №R-33 PKG-1) — the Helsinki
  # Achemenet Babylonian corpus over the NEW baby-conllu family:
  # 17-column BabyLemmatizer CoNLL-U-Plus, documents delimited only by
  # `# <id> = <designation>` lines, urn = the id lowercased (the cdli
  # convention — the shared P-number space is a future crosswalk join),
  # one whole-text passage with the token layer (form/lemma/pos/eng/
  # score) in annotations, SILVER lemma tier. Fixtures: real trimmed
  # slices (four Murašû texts incl. an X-id, one YOS7 text).
  class AchemenetTest < Minitest::Test
    include AdapterConformance
    include StoreTestDB

    FIXTURES = Nabu::TestSupport.fixtures("achemenet")

    def conformance_adapter
      Nabu::Adapters::Achemenet.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "achemenet"
    end

    # -- registry -------------------------------------------------------------

    def test_registry_resolves_achemenet_unwired_until_first_real_sync
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["achemenet"]
      refute_nil entry, "achemenet must be registered in config/sources.yml"
      refute entry.wired
      assert_equal "manual", entry.sync_policy
      assert_includes entry.axes, "cuneiform"
      assert_equal "silver", registry.lemma_tiers["achemenet"],
                   "BabyLemmatizer output is SILVER — the GLAUx rule"
    end

    # -- discovery ------------------------------------------------------------

    def test_discovers_five_documents_with_cdli_convention_urns
      refs = Nabu::Adapters::Achemenet.new.discover(FIXTURES).to_a
      assert_equal %w[urn:nabu:achemenet:p261571 urn:nabu:achemenet:p261572
                      urn:nabu:achemenet:p261494 urn:nabu:achemenet:x000428
                      urn:nabu:achemenet:p307862], refs.map(&:id),
                   "file order within Murashu (id order is NOT monotonic upstream — kept), then YOS7"
      assert_equal "Murašu BE 9, 2", refs.first.metadata["designation"]
      assert_equal "Murashu", refs.first.metadata["archive"]
    end

    def test_discovery_skips_census_recognizes_readmes_and_counts_strays
      skips = Nabu::Adapters::Achemenet.new.discovery_skips(FIXTURES)
      assert_equal 1, skips.unrecognized,
                   "READMEs are recognized non-corpus files; the fixture rig's own manifest.yml " \
                   "is a stray the census counts LOUDLY — exactly what it must do for any " \
                   "unexpected file in a real workdir"
      assert_equal ["non-corpus file: manifest.yml"], skips.notes
    end

    # -- parse ----------------------------------------------------------------

    def test_parses_one_whole_text_passage_with_the_token_layer
      adapter = Nabu::Adapters::Achemenet.new
      ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:achemenet:p261571" }
      document = adapter.parse(ref)

      assert_equal "akk", document.language
      assert_equal "Murašu BE 9, 2", document.title
      assert_equal({ "value" => "Murashu" }, document.metadata["facets"]["archive"])
      assert_equal "P261571", document.metadata["cdli_p"],
                   "a P-id names its CDLI artifact — the crosswalk hook"

      assert_equal 1, document.passages.size, "no line/sentence grain upstream — one honest passage"
      passage = document.passages.first
      assert_equal "urn:nabu:achemenet:p261571:1", passage.urn
      tokens = passage.annotations["tokens"]
      assert_operator tokens.size, :>, 20
      lemmatized = tokens.find { |t| t["lemma"] }
      refute_nil lemmatized
      assert lemmatized.key?("pos"), "the BabyLemmatizer POS rides"
      assert passage.text.include?(tokens.first["form"]), "the passage text is the joined forms"
    end

    def test_an_x_id_document_has_no_cdli_hook
      adapter = Nabu::Adapters::Achemenet.new
      ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:achemenet:x000428" }
      document = adapter.parse(ref)
      assert_nil document.metadata["cdli_p"], "X-ids are Helsinki-local placeholders, not CDLI artifacts"
    end

    def test_number_tokens_carry_no_invented_lemma
      adapter = Nabu::Adapters::Achemenet.new
      ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:achemenet:p261571" }
      tokens = adapter.parse(ref).passages.first.annotations["tokens"]
      ordinal = tokens.find { |t| t["form"] == "22-KAM" }
      refute_nil ordinal, "the fixture carries the 22-KAM ordinal token"
      refute ordinal.key?("lemma"), "upstream `_` cells stay absent — nothing invented"
    end
  end
end
