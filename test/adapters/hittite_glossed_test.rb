# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # hittite-glossed — the Zenodo "Glossed Hittite Texts with German
  # Translation" corpus (P109-3, Q80's strongest line): ONE CSV
  # (7000_hitt_txts_wGloss.csv, DOI 10.5281/zenodo.14266302 v1.0,
  # CC BY 4.0), 7,099 texts / 170,496 word rows. Grain: document = one
  # text (txtid, the tablet publication id — the same id family
  # TLHdig's manuscripts carry), passage = one manuscript line (the
  # lnr runs, in file order), token layers riding as aligned
  # annotations. Fixture: three real texts trimmed verbatim from the
  # CSV — IBoT 1.30+ (the "+" join id), KBo 35.261 (empty-gloss
  # tokens), Bo 8897 (the multi-CTH duplicate-index shape).
  class HittiteGlossedTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("hittite-glossed")

    def conformance_adapter = Nabu::Adapters::HittiteGlossed.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "hittite-glossed"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(slug) = documents.find { |d| d.urn.end_with?(":#{slug}") } || flunk("#{slug} missing")

    def test_discovers_one_document_per_text_with_tlhdig_style_slugs
      assert_equal %w[urn:nabu:hittite-glossed:bo.8897
                      urn:nabu:hittite-glossed:ibot.1.30+
                      urn:nabu:hittite-glossed:kbo.35.261],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_lines_become_passages_with_aligned_token_layers
      d = doc("ibot.1.30+")
      assert_equal "hit", d.language
      first = d.passages.first
      assert_equal "#{d.urn}:l1", first.urn
      assert_equal "Vs. 1", first.annotations["line"]
      assert_equal "LUGALuš kuapi DINGIRaš aruaizi GUDU₁₂ kišan malti", first.text
      assert_equal "⸢LUGAL⸣-uš ku-wa-pí DINGIR{MEŠ}-aš a-ru-wa-a-ez-zi {LÚ}GUDU₁₂ kiš-an ma-al-di",
                   first.annotations["translit"]
      assert_equal "FNL(u).NOM.SG.C | CNJ | D/L.PL | 3SG.PRS | NOM.SG(UNM) | DEMadv | 3SG.PRS",
                   first.annotations["gloss"]
      assert_equal "König | sobald als | Gottheit | sich verneigen | Gesalbter | in dieser Weise | äußern",
                   first.annotations["trans_de"]
    end

    def test_cth_rides_as_the_tlhdig_shaped_facet
      d = doc("ibot.1.30+")
      assert_equal "IBoT 1.30+ (CTH 821)", d.title
      assert_equal({ "value" => "821", "raw" => "CTH 821" }, d.metadata.dig("facets", "cth"))
      assert_equal %w[821], d.metadata["cth_numbers"]
    end

    def test_multi_cth_text_keeps_every_number_and_marks_passages
      d = doc("bo.8897")
      assert_equal %w[615 670], d.metadata["cth_numbers"]
      assert_equal "615", d.metadata.dig("facets", "cth", "value")
      # The duplicate index repeats the same lines under each CTH entry:
      # ordinal urns stay unique, the line label and cth ride as
      # annotations.
      assert_equal 4, d.passages.size
      assert_equal(%w[615 615 670 670], d.passages.map { |p| p.annotations["cth"] })
      assert_equal(["Vs.? 3", "Vs.? 4", "Vs.? 3", "Vs.? 4"],
                   d.passages.map { |p| p.annotations["line"] })
    end

    def test_single_cth_text_passages_carry_no_cth_annotation
      assert(doc("ibot.1.30+").passages.none? { |p| p.annotations.key?("cth") })
    end

    def test_empty_gloss_tokens_keep_their_aligned_slot
      d = doc("kbo.35.261")
      glosses = d.passages.map { |p| p.annotations["gloss"] }
      assert(glosses.any? { |g| g.split(" | ", -1).any?(&:empty?) },
             "KBo 35.261 carries the corpus's empty-gloss token shape")
    end
  end
end
