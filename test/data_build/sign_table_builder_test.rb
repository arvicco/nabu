# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The sux/sign-table builder (P73-9): the compiled per-sign card table —
# OSL identity + codepoints + list numbers + CDLI reading concordances +
# per-source attestation doc-counts from the catalog (value/logogram
# tokens; compounds and numbers censused as out of counting scope).
class SignTableBuilderTest < Minitest::Test
  include StoreTestDB

  FIXTURE_ASL = File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl")

  def setup
    @catalog = store_test_db
    @cdli = Nabu::Store::Source.create(slug: "cdli", name: "CDLI", adapter_class: "TestAdapter",
                                       license_class: "open")
    [["urn:nabu:cdli:p1", "1. ak du₃\n2. ak zzz-unresolved\n"],
     ["urn:nabu:cdli:p2", "1. ak\n"]].each_with_index do |(urn, text), i|
      doc = Nabu::Store::Document.create(source_id: @cdli.id, urn: urn, title: urn,
                                         language: "sux", content_sha256: "x", revision: 1)
      Nabu::Store::Passage.create(document_id: doc.id, urn: "#{urn}:1", sequence: i,
                                  language: "sux", text: text, text_normalized: text,
                                  content_sha256: "x", revision: 1)
    end
  end

  def builder(root)
    canonical = File.join(root, "canonical")
    FileUtils.mkdir_p(File.join(canonical, "osl", "00lib"))
    FileUtils.cp(FIXTURE_ASL, File.join(canonical, "osl", "00lib", "osl.asl"))
    Nabu::DataBuild::SignTableBuilder.new(canonical_dir: canonical, cdli_readings: {})
  end

  def test_compiles_one_card_per_top_level_sign_with_attestation_counts
    Dir.mktmpdir do |root|
      out = File.join(root, "out")
      FileUtils.mkdir_p(out)
      result = builder(root).build(catalog: @catalog, out_dir: out)
      table = CSV.read(File.join(out, "sign-table.csv"), headers: true)
      assert_equal %w[ID Sign_Name OID Codepoints Values Lists CDLI_Readings
                      Count_cdli Count_oracc Count_tlhdig Source].join(","),
                   table.headers.join(",")
      assert_equal 13, table.size, "one card per top-level fixture sign"

      ak = table.find { |row| row["Sign_Name"] == "AK" }
      refute_nil ak
      assert_includes ak["Values"], "ak", "the OSL readings ride the card"
      assert_equal "2", ak["Count_cdli"], "both docs attest ak — DOC count, not token count"
      assert_nil ak["Count_oracc"], "an absent source column stays empty, never zero-invented"

      evaluation = result.evaluation
      assert_equal 2, evaluation.dig("counting", "docs_counted")
      assert_operator evaluation.dig("counting", "tokens_unresolved"), :>=, 1,
                      "the zzz stray is censused, never guessed"
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |root|
      error = assert_raises(Nabu::DataBuild::Error) do
        builder(root).build(catalog: nil, out_dir: root)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
