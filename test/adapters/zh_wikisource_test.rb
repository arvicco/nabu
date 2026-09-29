# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

module Adapters
  # zh-wikisource (P109-1, Q90 under №R-74): the censused-works shelf.
  # Fixture envelopes are real api.php captures (2026-09-29): 元朝秘史/
  # 卷15 (direct, whole — the Ming 總譯 layer, language zho), 續資治通鑑/
  # 卷001 (direct, trimmed), 全唐文/卷0001 (the transclusion-shell
  # shape: trimmed to its front matter + three sections, the three
  # pieces stored in the envelope's "transclusions" map).
  class ZhWikisourceTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("zh-wikisource")

    def conformance_adapter = Nabu::Adapters::ZhWikisource.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "zh-wikisource"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES)
                                        .map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(pageid) = documents.find { |d| d.urn.end_with?(":#{pageid}") } || flunk("#{pageid} missing")

    def test_discovers_one_document_per_subpage_envelope
      assert_equal %w[urn:nabu:zh-wikisource:109484 urn:nabu:zh-wikisource:41615
                      urn:nabu:zh-wikisource:63644],
                   conformance_adapter.discover(FIXTURES).map(&:id).sort
    end

    def test_direct_juan_parses_as_literary_chinese_prose
      d = doc(41_615)
      assert_equal "lzh", d.language
      assert_equal "續資治通鑑", d.metadata["work"]
      assert_equal "卷001", d.metadata["part"]
      assert_operator d.passages.size, :>=, 2
      refute(d.passages.any? { |p| p.text.include?("{{") }, "no template syntax leaks")
    end

    def test_secret_history_claims_the_ming_chinese_it_is
      d = doc(109_484)
      assert_equal "zho", d.language,
                   "the hosted layer is the Ming 總譯 — never lzh, never a Mongolic claim"
      assert(d.passages.first.text.include?("大王忙該"), "the 總譯 prose is the text")
    end

    def test_transcluded_shell_composes_its_pieces_offline
      d = doc(63_644)
      assert_equal "全唐文", d.metadata["work"]
      joined = d.passages.map(&:text).join("\n")
      assert_includes joined, "帝姓李氏", "the shell's own front matter parses"
      assert_includes joined, "乞言將智", "the transcluded 授老人等官教 piece text composes in"
      piece = d.passages.find { |p| p.text.include?("乞言將智") }
      assert_includes piece.annotations["section"], "授老人等官教",
                      "the shell's heading names the piece"
    end

    def test_dynasty_claim_rides_the_tang_canon_only
      assert_equal "唐", doc(63_644).metadata["dynasty"], "全唐文 IS the Tang prose canon"
      assert_nil doc(41_615).metadata["dynasty"], "a Qing compilation about Song–Yuan claims nothing"
      assert_nil doc(109_484).metadata["dynasty"], "the Ming 總譯 layer claims nothing"
    end

    def test_title_batches_cap_by_encoded_bytes_and_count
      adapter = conformance_adapter
      # 60 short titles: the 50-title API cap splits them 50/10.
      short = (1..60).map { |n| "卷#{n}" }
      assert_equal [50, 10], adapter.title_batches(short).map(&:size)
      # Long memorial-style titles (~40 hanzi ≈ 360 encoded bytes each)
      # must split by BYTE budget long before the count cap — 50 of
      # them in one GET was the live HTTP 414.
      long = (1..50).map { |n| "中書舍人王秀漏泄機密斷絞秀不伏款於掌事張會處傳得語秀合是從#{n}" }
      batches = adapter.title_batches(long)
      assert_operator batches.size, :>, 1, "one 50-title batch of long titles = HTTP 414"
      assert(batches.all? { |b| b.sum { |t| URI.encode_www_form_component(t).bytesize + 3 } <= 5_000 })
      assert_equal long, batches.flatten, "every title survives, in order"
    end

    def test_edition_unstated_recorded_honestly
      assert(documents.all? { |d| d.metadata["base_edition"] == "unstated" },
             "№R-74: no censused zh page states a 底本")
    end
  end
end
