# frozen_string_literal: true

require "test_helper"

module Adapters
  # westoldturkic — the Róna-Tas & Berta 2011 West Old Turkic loanword
  # database as CLDF (P108-7, the Q107 half; Zenodo 10.5281/zenodo.
  # 7893910 v2.0, CC BY 4.0): one dictionary, entry per WOT etymon,
  # the Hungarian descent chain (EAH → LAH → OH → H) as reflex rows
  # with the curated borrowing pairs marking the loan step.
  # No passage conformance suite — a pure dictionary source (the
  # iecor/wiktionary-recon precedent).
  class WestoldturkicTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("westoldturkic")

    def adapter = Nabu::Adapters::Westoldturkic.new

    def entries
      @entries ||= begin
        ref = adapter.discover(FIXTURES).first
        adapter.parse(ref).entries
      end
    end

    def test_manifest_and_double_parse_stability
      assert_equal "westoldturkic", adapter.manifest.id
      assert_equal "attribution", adapter.manifest.license_class
      ref = adapter.discover(FIXTURES).first
      again = adapter.parse(ref).entries.map(&:entry_id)
      assert_equal entries.map(&:entry_id), again, "entry ids stable across two parses"
    end

    def entry(id)
      entries.find { |e| e.entry_id == id } || flunk("entry #{id} not parsed")
    end

    def test_one_entry_per_wot_etymon
      assert_equal %w[WOT-0_carpenter-1 WOT-1_cannoncatapult-1], entries.map(&:entry_id).sort
      carpenter = entry("WOT-0_carpenter-1")
      assert_equal "aγaččï", carpenter.headword
      assert_equal "trk", carpenter.language
      assert_equal "carpenter", carpenter.gloss
    end

    def test_the_hungarian_chain_rides_as_reflexes
      cannon = entry("WOT-1_cannoncatapult-1")
      codes = cannon.reflexes.map(&:lang_code)
      assert_includes codes, "hun", "modern Hungarian resolves its ISO code"
      assert_includes codes, "ohu", "Old Hungarian resolves its ISO code"
      assert_includes codes, "EAH", "code-less varieties keep the upstream ID verbatim"
      agyu = cannon.reflexes.find { |r| r.lang_code == "hun" }
      assert_equal "ágyú", agyu.word
    end

    def test_the_borrowing_step_marks_its_reflex
      cannon = entry("WOT-1_cannoncatapult-1")
      eah = cannon.reflexes.find { |r| r.lang_code == "EAH" }
      assert eah.borrowed, "the curated borrowings row marks the EAH loan step"
      hun = cannon.reflexes.find { |r| r.lang_code == "hun" }
      refute hun.borrowed, "inherited descent below the loan step stays unmarked"
    end

    def test_first_attestation_year_rides_the_body
      assert_includes entry("WOT-0_carpenter-1").body, "1222",
                      "the Hungarian first-attestation year is mined into the body"
    end
  end
end
