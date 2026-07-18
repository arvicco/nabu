# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# Nabu::Adapters::Aes (P28-0): AES — Ancient Egyptian Sentences, the TLA/BBAW
# January-2018 snapshot (github.com/simondschweitzer/aes): 101,796 lemmatized
# sentences / 13,026 texts across 16 subcorpus JSON files under files/aes/
# (~342 MB; CC BY-SA 4.0 verbatim in the repo README: "All files: CC-BY-SA
# 4.0"). One document per TEXT (the AED text id — sentences are contiguous
# per text in file order, censused across all 16 files), one passage per
# sentence on upstream's globally-unique sentence ids.
#
# THE KNOWN TRAP, pinned here with the real bytes: the `hiero_unicode` field
# is HTML-entity-encoded ("&#x13099;", all 241,414 occurrences hex-numeric,
# zero literal hieroglyphs censused) — decoded at the adapter boundary.
# Second boundary regression: 13,682 written forms carry the deprecated
# U+2329/U+232A math angle brackets, which NFC canonically maps to
# U+3008/U+3009 — the boundary Normalize.nfc is the fix, pinned on fixture
# bytes.
#
# LANGUAGE VERDICT (censused): the JSON carries NO language or stage tags —
# the honest tag is uniform `egy` (ISO 639-2 Egyptian (Ancient)); stage
# subtags are never invented. The transliteration (written_form) is the
# passage surface, the ORACC-translit precedent; hieroglyphs/MdC/Gardiner
# ride the token annotations.
#
# THE LEMMA JOIN CONTRACT (P28-1 consumes this): token "lemma" = lemma_form
# (feeds passage_lemmas via the shared treebank contract, tier gold) and
# token "lemma_id" = the AED lemmaID VERBATIM ("123130") — P28-1's AED
# dictionary joins on exact string equality lemma_id == entry_id, no folding.
class AesTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  TUEB_URN = "urn:nabu:aes:tuebingerstelen:3F5KUVWQG5EPBM7GMQ6ZFVO5OQ"
  TUEB2_URN = "urn:nabu:aes:tuebingerstelen:5YVC3WZOGZHSBGXTIEM7ZUG2UA"
  ARCH_URN = "urn:nabu:aes:bbawarchive:26BP5JT5RZEDHDDU2R5TMUBD24"
  ARCH_K_URN = "urn:nabu:aes:bbawarchive:IMLY3YQIZFHHNJUGOZXVPOJTGU"
  ARCH_NS6_URN = "urn:nabu:aes:bbawarchive:NS6BAIQRENELJM2A2LDNHIYK6E"
  SAWLIT_URN = "urn:nabu:aes:sawlit:2PD2OKCZCRELBGQD6NCAMOFEWA"
  SAWLIT2_URN = "urn:nabu:aes:sawlit:YSJ3UHIOBJEILCD7KFQIGVOCLY"

  ORIGINAL_URNS = [
    ARCH_URN, ARCH_K_URN, ARCH_NS6_URN, SAWLIT_URN, SAWLIT2_URN, TUEB_URN, TUEB2_URN
  ].freeze

  def conformance_adapter
    Nabu::Adapters::Aes.new(translations: true)
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("aes")
  end

  def conformance_expected_source_id
    "aes"
  end

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_plus_de_siblings_sorted_by_urn
    expected = ORIGINAL_URNS.flat_map { |urn| [urn, "#{urn}-de"] }.sort
    assert_equal expected, adapter.discover(workdir).map(&:id),
                 "one document per AED text + one -de sibling per translated text, sorted"
  end

  def test_discover_without_translations_is_provably_inert
    refs = Nabu::Adapters::Aes.new.discover(workdir).to_a
    assert_equal ORIGINAL_URNS.sort, refs.map(&:id),
                 "the no-arg registry contract yields originals only"
  end

  def test_refs_carry_subcorpus_and_text_id_metadata
    ref = ref_for(TUEB_URN)
    assert_equal "tuebingerstelen", ref.metadata["subcorpus"]
    assert_equal "3F5KUVWQG5EPBM7GMQ6ZFVO5OQ", ref.metadata["text"]
  end

  # -- parse: the original (transliteration surface) --------------------------

  def test_parses_a_text_into_transliteration_passages_on_sentence_ids
    document = adapter.parse(ref_for(TUEB_URN))
    assert_equal "egy", document.language, "no stage tags upstream — uniform egy, never invented subtags"
    assert_equal 12, document.count
    first = document.first
    assert_equal "#{TUEB_URN}:IBcAYfWPD6TkHESXl08OjBEmuv4", first.urn,
                 "passage citation = upstream's globally-unique sentence id"
    assert_equal "ẖn(,w) n(,j) ḥm =f Ḥꜣy", first.text,
                 "the Unicode transliteration is the passage surface, forms space-joined"
  end

  def test_tokens_carry_the_gold_lemma_layer_and_the_aed_join_key
    first = adapter.parse(ref_for(TUEB_URN)).first
    token = first.annotations.fetch("tokens").first
    assert_equal "ẖn(,w)", token["form"]
    assert_equal "Xn(,w)", token["mdc"], "MdC transliteration rides verbatim"
    assert_equal "ẖn.w", token["lemma"], "lemma_form = the shared treebank lemma contract"
    assert_equal "123130", token["lemma_id"], "the AED lemmaID VERBATIM — P28-1's exact-equality join key"
    assert_equal "Ruderer", token["gloss"]
    assert_equal "epitheton_title", token["pos"]
    assert_equal "title", token["epitheton"], "fine pos subtypes ride under their upstream names"
    assert_equal "D33", token["hiero"], "Gardiner-number encoding verbatim"
    assert_equal "1", token["line"], "lineCount rides as the token's line anchor"
  end

  def test_hiero_unicode_entities_decode_at_the_boundary
    document = adapter.parse(ref_for(TUEB_URN))
    token = document.first.annotations.fetch("tokens").first
    assert_equal "\u{13099}", token["hiero_unicode"],
                 "&#x13099; decodes to the actual hieroglyph codepoint, never stored entity-encoded"
    document.each do |passage|
      passage.annotations.fetch("tokens").each do |t|
        refute_match(/&#/, t["hiero_unicode"].to_s,
                     "no HTML entity survives the boundary (#{passage.urn})")
      end
    end
  end

  def test_the_fixture_bytes_really_carry_the_entity_encoding
    raw = File.read(File.join(workdir, "files", "aes", "_aes_tuebingerstelen.json"))
    assert_includes raw, "&#x13099;", "the regression fixture must keep the offending upstream bytes"
  end

  def test_deprecated_angle_brackets_normalize_to_nfc_at_the_boundary
    raw = File.read(File.join(workdir, "files", "aes", "_aes_tuebingerstelen.json"))
    assert_includes raw, "〈", "the fixture must keep the deprecated U+2329 upstream bytes"
    document = adapter.parse(ref_for(TUEB_URN))
    editorial = document.to_a[1]
    assert_includes editorial.text, "Nb(w)-m-jnḥꜣ〈s〉",
                    "U+2329/232A canonically compose to U+3008/3009 under the boundary NFC"
    refute_includes editorial.text, "〈"
  end

  def test_a_token_without_lemmatization_stays_honest
    document = adapter.parse(ref_for(TUEB2_URN))
    token = document.first.annotations.fetch("tokens")[10]
    assert_includes token["form"], "nḏ,t(j)-jt(j)"
    refute token.key?("lemma"), "a lemma-less upstream token claims no lemma (95.6% coverage censused)"
    refute token.key?("lemma_id")
  end

  def test_a_token_less_sentence_yields_no_original_passage
    document = adapter.parse(ref_for(ARCH_NS6_URN))
    assert_equal 2, document.count,
                 "3 sentences upstream, 1 token-less (censused: 3 corpus-wide, never a whole text)"
    refute_includes document.map(&:urn), "#{ARCH_NS6_URN}:IBUBd4R4jQOm80W1gMPGfy493eQ"
  end

  def test_document_metadata_carries_editor_date_findspot_and_facets
    metadata = adapter.parse(ref_for(TUEB_URN)).metadata
    assert_equal "tuebingerstelen", metadata.fetch("subcorpus")
    assert_equal "3F5KUVWQG5EPBM7GMQ6ZFVO5OQ", metadata.fetch("text_id")
    assert_equal "Susanne Beck", metadata.fetch("owner")
    assert_equal "NK", metadata.fetch("date"), "the corpus's own period value, verbatim"
    assert_equal "Upper Egypt (South of Assiut)", metadata.fetch("findspot")
    assert_equal({ "value" => "tuebingerstelen", "raw" => "tuebingerstelen" },
                 metadata.dig("facets", "subcorpus"))
    assert_equal({ "value" => "nk", "raw" => "NK" }, metadata.dig("facets", "period"))
    assert_equal({ "value" => "upper-egypt", "raw" => "Upper Egypt (South of Assiut)" },
                 metadata.dig("facets", "findspot"))
  end

  def test_degenerate_date_and_unknown_findspot_mint_no_facets
    metadata = adapter.parse(ref_for(ARCH_K_URN)).metadata
    assert_equal "k", metadata.fetch("date"), "the real degenerate upstream value, verbatim"
    assert_equal "unknown", metadata.fetch("findspot")
    assert_nil metadata.dig("facets", "period"), "an unmapped date value never guesses a period"
    assert_nil metadata.dig("facets", "findspot"), "unknown is not a place"
  end

  # -- parse: the -de German siblings ------------------------------------------

  def test_de_sibling_carries_the_editor_translations_as_aligned_passages
    document = adapter.parse(ref_for("#{TUEB_URN}-de"))
    assert_equal "ger", document.language
    assert_equal "translation", document.metadata.fetch("kind")
    assert_equal 12, document.count
    first = document.first
    assert_equal "#{TUEB_URN}-de:IBcAYfWPD6TkHESXl08OjBEmuv4", first.urn,
                 "sibling passages cite the SAME sentence id — the verse-pair alignment key"
    assert_equal "Der Ruderer seiner Majestät, Hai.", first.text
  end

  def test_de_sibling_skips_untranslated_sentences_honestly
    document = adapter.parse(ref_for("#{SAWLIT_URN}-de"))
    assert_equal 7, document.count, "8 sentences upstream, 1 without a translation"
    refute_includes document.map(&:urn), "#{SAWLIT_URN}-de:IBUBd789wZJOXU94kVYcLelNZKQ"
  end

  def test_de_sibling_keeps_the_translation_of_a_token_less_sentence
    document = adapter.parse(ref_for("#{ARCH_NS6_URN}-de"))
    assert_equal 3, document.count,
                 "the German of a token-less sentence exists — a one-sided parallel row, never dropped"
    assert_includes document.map(&:urn), "#{ARCH_NS6_URN}-de:IBUBd4R4jQOm80W1gMPGfy493eQ"
  end

  # -- store: idempotent double-load -------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 14, first.added, "7 texts + 7 -de siblings"
    assert_equal 0, first.errored
    assert_equal 62, db[:passages].count, "31 transliteration + 31 translated sentences"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 14, second.skipped, "a byte-identical reload skips every document"
    assert_equal 62, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # -- the gold lemma mint: search --lemma finds an AES passage -----------------

  def test_lemma_search_finds_an_aes_passage_at_gold_tier
    db, fulltext = indexed_store
    results = Nabu::Query::LemmaSearch.new(catalog: db, fulltext: fulltext).run("ẖn.w")
    assert_equal ["#{TUEB_URN}:IBcAYYiU7YgQKk1vmcBvmZb1eZY",
                  "#{TUEB_URN}:IBcAYfWPD6TkHESXl08OjBEmuv4"], results.map(&:urn).sort,
                 "the TLA gold lemma ẖn.w (lemmaID 123130) lights both attesting fixture passages"
    hit = results.first
    assert_equal "gold", hit.tier, "TLA lemmatization is verified annotation — gold, never silver"
    assert_equal "egy", hit.language
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- show --parallel: the -de sibling resolves like the SAA letters ----------

  def test_parallel_resolves_the_de_sibling_as_verse_pairs
    db, fulltext = indexed_store
    result = Nabu::Query::Parallel.new(catalog: db).run(TUEB_URN, lang: "ger")
    refute_nil result.right, "the -de sibling is the ger edition of the same text"
    assert_equal "#{TUEB_URN}-de", result.right.urn
    pair = result.groups.find { |group| group.kind == :pair } ||
           flunk("no verse pair — sentence-id suffixes must align")
    assert_equal ":IBcAYfWPD6TkHESXl08OjBEmuv4", pair.anchor
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch (local git only, no network) ---------------------------------------

  def test_fetch_sparse_clones_only_the_aes_cone
    Dir.mktmpdir("nabu-aes-fetch") do |root|
      upstream = File.join(root, "upstream")
      build_upstream_repo(upstream)
      work = File.join(root, "canonical")

      aes = adapter
      aes.define_singleton_method(:repo_url) { upstream }
      report = aes.fetch(work)

      assert_kind_of Nabu::FetchReport, report
      assert_match(/\A[0-9a-f]{40}\z/, report.sha)
      assert File.file?(File.join(work, "files", "aes", "_aes_tuebingerstelen.json"))
      assert File.file?(File.join(work, "README.md")), "the root README carries the license grant"
      refute File.exist?(File.join(work, "files", "relANNIS")),
             "the ~114 MB relANNIS zips are outside the cone and must not materialize"
      refute_empty aes.discover(work).to_a, "the fetched tree is discoverable"
    end
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "aes", name: "AES", adapter_class: "Nabu::Adapters::Aes", license_class: "attribution"
    )
  end

  def indexed_store
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
    [db, fulltext]
  end

  # A local upstream repo with the real layout: the files/aes cone (fixture
  # bytes) + root README, plus relANNIS ballast the sparse fetch must skip.
  def build_upstream_repo(upstream)
    FileUtils.mkdir_p(File.join(upstream, "files", "relANNIS"))
    FileUtils.mkdir_p(File.join(upstream, "files", "aes"))
    Dir.glob(File.join(workdir, "files", "aes", "*")).each do |path|
      FileUtils.cp(path, File.join(upstream, "files", "aes"))
    end
    File.write(File.join(upstream, "README.md"),
               "# aes\n\n## licence\nAll files: [CC-BY-SA 4.0](http://creativecommons.org/licenses/by-sa/4.0/)\n")
    File.write(File.join(upstream, "files", "relANNIS", "sawlit.zip"), "outside the cone")
    git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
    Nabu::Shell.run("git", "init", "-q", upstream)
    git.call("add", ".")
    git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
  end
end
