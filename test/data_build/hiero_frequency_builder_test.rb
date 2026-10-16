# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "csv"

# The egy/hiero-frequency builder (P77-r17, sign-learning P-1 Egyptian
# half): Gardiner-code token + doc frequencies from AES hiero_inventar
# annotations, per subcorpus with an `all` roll-up, withdrawn rows
# excluded, BY-SA license gate on the source class — WIDENED to the
# word grain: every Gardiner row carries Words (AES word tokens whose
# spelling carries the sign at least once), and the hiero-glyphs.csv
# sidecar publishes the catalog's precompiled AED per-glyph census
# (hiero_postings: texts, signs, words, unclear — migration 042).
class HieroFrequencyBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  AED_FILES = File.join(Nabu::TestSupport::FIXTURES_ROOT, "aed", "files")

  def registry_rig
    {
      "aes" => EntryRig.new(manifest: ManifestRig.new(
        name: "Ancient Egyptian Sentences", upstream_url: "https://aes.example", license: "CC BY-SA 4.0"
      )),
      "aed" => EntryRig.new(manifest: ManifestRig.new(
        name: "Ancient Egyptian Dictionary", upstream_url: "https://aed.example", license: "CC BY-SA 4.0"
      ))
    }
  end

  def setup
    @catalog = store_test_db
    @aes = Nabu::Store::Source.create(slug: "aes", name: "AES",
                                      adapter_class: "TestAdapter", license_class: "attribution")
    @aed = Nabu::Store::Source.create(slug: "aed", name: "AED",
                                      adapter_class: "TestAdapter", license_class: "attribution")
    @pyramid = document("urn:a:1", subcorpus: "pyramidtexts")
    @amarna = document("urn:a:2", subcorpus: "bbawamarna")
    # N5 in both docs (2+1 tokens); T21 only in the pyramid doc. The
    # "!" token is a non-Gardiner marker upstream spellings carry (the
    # 2026-09-19 live catch) — illegal verbatim in a CLDF ID, so the
    # row's ID minted-folds while the Gardiner column stays verbatim.
    # Z2 (plural strokes) repeats INSIDE one word: 3 tokens, 1 word —
    # the word grain is distinct from the token grain.
    passage(@pyramid, "urn:a:1:1", tokens: ["N5;T21", "N5", "!", "Z2;Z2;Z2"])
    passage(@amarna, "urn:a:2:1", tokens: ["N5"])
    # Withdrawn rows never count (the P77-r13 living-corpus rule).
    withdrawn_doc = document("urn:a:9", subcorpus: "pyramidtexts", withdrawn: true)
    passage(withdrawn_doc, "urn:a:9:1", tokens: ["Z9"])
    # The precompiled AED census, projected by the real store builder over
    # the real aed stand-off fixtures (𓂋: 42 signs / 39 words / 2 unclear).
    project_hiero_postings
  end

  def build!(out_dir)
    Nabu::DataBuild::HieroFrequencyBuilder.new(registry: registry_rig)
                                          .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_censuses_tokens_words_and_docs_per_subcorpus_with_all_rollup
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "hiero-frequency.csv"), headers: true)
      assert_equal %w[ID Gardiner Subcorpus Tokens Words Docs Source], table.headers

      rows = table.map(&:to_h)
      n5_all = rows.find { |r| r["ID"] == "N5-all" }
      assert_equal %w[3 3 2], n5_all.values_at("Tokens", "Words", "Docs"),
                   "N5: 3 tokens in 3 words across 2 docs"
      assert_equal %w[2 2 1], rows.find { |r| r["ID"] == "N5-pyramidtexts" }.values_at("Tokens", "Words", "Docs")
      assert_equal %w[1 1 1], rows.find { |r| r["ID"] == "N5-bbawamarna" }.values_at("Tokens", "Words", "Docs")
      assert_equal %w[1 1 1], rows.find { |r| r["ID"] == "T21-all" }.values_at("Tokens", "Words", "Docs")
      assert_equal %w[3 1 1], rows.find { |r| r["ID"] == "Z2-all" }.values_at("Tokens", "Words", "Docs"),
                   "a sign repeated inside one word: 3 tokens, 1 word"
      refute(rows.any? { |r| r["Gardiner"] == "Z9" }, "withdrawn documents never census")
      assert(rows.all? { |r| Integer(r["Words"]) <= Integer(r["Tokens"]) }, "Words never exceeds Tokens")

      assert_equal 2, result.evaluation["documents_with_signs"]
      assert_equal 8, result.evaluation["tokens_counted"]
      assert_equal 5, result.evaluation["words_counted"], "the five sign-bearing word tokens"
      assert_includes result.recipe, "sha256="
      assert_includes result.recipe, "words"
      assert_equal %w[aes aed], result.citations.map(&:key)
    end
  end

  def test_the_hiero_glyphs_sidecar_publishes_the_aed_word_grain_census
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "hiero-glyphs.csv"), headers: true, encoding: "UTF-8")
      assert_equal %w[ID Codepoint Glyph Texts Signs Words Unclear Source], table.headers
      assert_equal @catalog[:hiero_postings].count, table.size, "one row per hiero_postings glyph"

      r = table.find { |row| row["Glyph"] == "𓂋" }
      refute_nil r
      assert_equal %w[U1308B U+1308B 1 42 39 2 aed],
                   r.values_at("ID", "Codepoint", "Texts", "Signs", "Words", "Unclear", "Source"),
                   "𓂋: 42 occurrences in 39 words, 2 occurrences damage-flagged (<unclear>)"
      assert(table.all? { |row| Integer(row["Words"]) <= Integer(row["Signs"]) })
      assert(table.all? { |row| Integer(row["Unclear"]) <= Integer(row["Signs"]) })
      assert_equal table.map { |row| row["Codepoint"] }.sort, table.map { |row| row["Codepoint"] },
                   "deterministic codepoint order"
      assert(table.any? { |row| Integer(row["Unclear"]).positive? }, "the damage flag is live in the fixtures")

      sidecar = result.resources.find { |res| res.path == "hiero-glyphs.csv" }
      assert_equal ["ID"], sidecar.primary_key
      assert_equal(%w[Texts Signs Words Unclear],
                   sidecar.fields.select { |f| f[:type] == "integer" }.map { |f| f[:name] })
      assert_equal @catalog[:hiero_postings].sum(:unclear), result.evaluation["glyph_unclear_occurrences"]
      assert_includes result.recipe, "hiero_postings"
    end
  end

  def test_all_rows_lead_each_code_and_order_is_deterministic
    Dir.mktmpdir do |dir|
      build!(dir)
      ids = CSV.read(File.join(dir, "hiero-frequency.csv"), headers: true)["ID"]
      assert_equal %w[all pyramidtexts N5-all N5-bbawamarna N5-pyramidtexts
                      T21-all T21-pyramidtexts Z2-all Z2-pyramidtexts], ids,
                   "the '!' marker's IDs mint-fold ('!' sorts first); Gardiner stays verbatim"
    end
  end

  def test_a_non_publishable_source_class_refuses
    @aes.update(license_class: "nc")
    error = assert_raises(Nabu::DataBuild::Error) { Dir.mktmpdir { |dir| build!(dir) } }
    assert_match(/not publishable/, error.message)
  end

  def test_a_non_publishable_aed_class_refuses
    @aed.update(license_class: "nc")
    error = assert_raises(Nabu::DataBuild::Error) { Dir.mktmpdir { |dir| build!(dir) } }
    assert_match(/aed.*not publishable/, error.message)
  end

  def test_an_empty_hiero_postings_table_refuses_with_the_sync_hint
    @catalog[:hiero_postings].delete
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) { build!(dir) }
      assert_match(/hiero_postings/, error.message)
      assert_match(/sync aed/, error.message)
      assert_empty Dir.children(dir), "a refusal writes nothing"
    end
  end

  def test_the_registry_entry_states_the_word_grain_widening
    feature = Nabu::DataBuild.feature("egy/hiero-frequency")
    assert_equal %w[aes aed], feature.inputs
    assert_equal "CC-BY-SA-4.0", feature.license
    assert_match(/word/i, feature.title)
    assert_includes feature.rationale, "first public hieroglyph frequency list"
    %w[Words Unclear hiero_postings].each { |claim| assert_includes feature.rationale, claim }
  end

  private

  def project_hiero_postings
    Dir.mktmpdir do |dir|
      files = File.join(dir, "aed", "files")
      FileUtils.mkdir_p(files)
      Dir.glob(File.join(AED_FILES, "*_hiero.xml")).each { |f| FileUtils.cp(f, files) }
      Nabu::Store::HieroPostingsBuilder.rebuild!(catalog: @catalog, canonical_dir: dir)
    end
  end

  def document(urn, subcorpus:, withdrawn: false)
    Nabu::Store::Document.create(
      source_id: @aes.id, urn: urn, title: urn, language: "egy",
      content_sha256: "x", revision: 1, withdrawn: withdrawn,
      metadata_json: %({"subcorpus":"#{subcorpus}","text_id":"T"})
    )
  end

  def passage(doc, urn, tokens:, withdrawn: false)
    annotations = { "tokens" => tokens.map { |inv| { "form" => "w", "hiero_inventar" => inv } } }
    Nabu::Store::Passage.create(
      document_id: doc.id, urn: urn, sequence: 0, language: "egy",
      text: "t", text_normalized: "t", content_sha256: "x", revision: 1,
      withdrawn: withdrawn, annotations_json: JSON.generate(annotations)
    )
  end
end
