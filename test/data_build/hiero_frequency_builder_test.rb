# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The egy/hiero-frequency builder (P77-r17, sign-learning P-1 Egyptian
# half): Gardiner-code token + doc frequencies from AES hiero_inventar
# annotations, per subcorpus with an `all` roll-up, withdrawn rows
# excluded, BY-SA license gate on the source class.
class HieroFrequencyBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "aes" => EntryRig.new(manifest: ManifestRig.new(
      name: "Ancient Egyptian Sentences", upstream_url: "https://aes.example",
      license: "CC BY-SA 4.0"
    )) }
  end

  def setup
    @catalog = store_test_db
    @aes = Nabu::Store::Source.create(slug: "aes", name: "AES",
                                      adapter_class: "TestAdapter", license_class: "attribution")
    @pyramid = document("urn:a:1", subcorpus: "pyramidtexts")
    @amarna = document("urn:a:2", subcorpus: "bbawamarna")
    # N5 in both docs (2+1 tokens); T21 only in the pyramid doc.
    passage(@pyramid, "urn:a:1:1", tokens: ["N5;T21", "N5"])
    passage(@amarna, "urn:a:2:1", tokens: ["N5"])
    # Withdrawn rows never count (the P77-r13 living-corpus rule).
    withdrawn_doc = document("urn:a:9", subcorpus: "pyramidtexts", withdrawn: true)
    passage(withdrawn_doc, "urn:a:9:1", tokens: ["Z9"])
  end

  def build!(out_dir)
    Nabu::DataBuild::HieroFrequencyBuilder.new(registry: registry_rig)
                                          .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_censuses_tokens_and_docs_per_subcorpus_with_all_rollup
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "hiero-frequency.csv"), headers: true)
      assert_equal %w[ID Gardiner Subcorpus Tokens Docs Source], table.headers

      rows = table.map(&:to_h)
      n5_all = rows.find { |r| r["ID"] == "N5-all" }
      assert_equal %w[3 2], n5_all.values_at("Tokens", "Docs"), "N5: 3 tokens across 2 docs"
      assert_equal %w[2 1], rows.find { |r| r["ID"] == "N5-pyramidtexts" }.values_at("Tokens", "Docs")
      assert_equal %w[1 1], rows.find { |r| r["ID"] == "N5-bbawamarna" }.values_at("Tokens", "Docs")
      assert_equal %w[1 1], rows.find { |r| r["ID"] == "T21-all" }.values_at("Tokens", "Docs")
      refute(rows.any? { |r| r["Gardiner"] == "Z9" }, "withdrawn documents never census")

      assert_equal 2, result.evaluation["documents_with_signs"]
      assert_includes result.recipe, "sha256="
      assert_equal "aes", result.citations.first.key
    end
  end

  def test_all_rows_lead_each_code_and_order_is_deterministic
    Dir.mktmpdir do |dir|
      build!(dir)
      ids = CSV.read(File.join(dir, "hiero-frequency.csv"), headers: true)["ID"]
      assert_equal %w[N5-all N5-bbawamarna N5-pyramidtexts T21-all T21-pyramidtexts], ids
    end
  end

  def test_a_non_publishable_source_class_refuses
    @aes.update(license_class: "nc")
    error = assert_raises(Nabu::DataBuild::Error) { Dir.mktmpdir { |dir| build!(dir) } }
    assert_match(/not publishable/, error.message)
  end

  private

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
