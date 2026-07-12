# frozen_string_literal: true

require "test_helper"

module Adapters
  # Nabu::Adapters::OraccTranslationParser (P13-4): one ORACC per-text
  # rendered-HTML fragment (`/<project>/<textid>/html`) + its sibling
  # corpusjson → an English aligned-translation Document in the P7-4 sibling
  # shape. Fixtures are REAL fragments (saao/saa01 P224395 — the
  # paragraph-grained SAA letter with two prose-free state-notice cells;
  # rimanum P405432/P405134 — the short admin texts whose cells anchor with
  # full labels and primes).
  class OraccTranslationParserTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("oracc")

    SAA_HTML = File.join(FIXTURES, "html-en", "saao-saa01", "P224395.html")
    SAA_CORPUS = File.join(FIXTURES, "saao-saa01", "saa01", "corpusjson", "P224395.json")
    SAA_URN = "urn:nabu:oracc:saao-saa01:P224395-en"

    RIM_HTML = File.join(FIXTURES, "html-en", "rimanum", "P405432.html")
    RIM_CORPUS = File.join(FIXTURES, "rimanum", "corpusjson", "P405432.json")
    RIM_URN = "urn:nabu:oracc:rimanum:P405432-en"

    def parse_saa(title: "SAA 01 175 (English translation)")
      Nabu::Adapters::OraccTranslationParser.new.parse(
        SAA_HTML, urn: SAA_URN, corpusjson_path: SAA_CORPUS, title: title
      )
    end

    # -- unit → passage shape --------------------------------------------------

    def test_parses_translation_units_into_anchor_labeled_passages
      document = parse_saa
      assert_equal SAA_URN, document.urn
      # 6 xtr cells: 4 prose units + 2 prose-free state notices ("(Break)",
      # "(Rest destroyed)") skipped by rule. Suffix = the ANCHOR line's frozen
      # label (spaces → dots), the same minting as the tablet's passages.
      assert_equal [
        "#{SAA_URN}:o.1", "#{SAA_URN}:o.4", "#{SAA_URN}:o.11", "#{SAA_URN}:r.30"
      ], document.map(&:urn)
      assert_equal (0..3).to_a, document.map(&:sequence)
    end

    def test_unit_prose_is_extracted_verbatim_with_restorations_kept
      document = parse_saa
      assert_equal "To the king, my lord: Your servant Adda-hati. " \
                   "Good health to the king, my lord!", document.first.text
      # Editorial marks survive verbatim — restorations are part of the
      # translation as published.
      assert_includes document.to_a[1].text, "[tran]sferred"
      assert_includes document.to_a[1].text, "(Ammili'ti)"
    end

    def test_the_xtr_label_print_marker_is_stripped_by_markup_not_regex
      # Every unit renders a leading print marker ("(1)", "(o 1)") in its own
      # <span class="xtr-label"> element — alignment metadata the citation now
      # carries, never part of the prose.
      parse_saa.each do |passage|
        refute_match(/\A\(\d/, passage.text,
                     "passage #{passage.urn} must not start with a print marker")
      end
    end

    def test_document_and_passages_are_english_with_attribution_override
      document = parse_saa
      assert_equal "eng", document.language
      assert_equal "attribution", document.license_override
      assert_equal "SAA 01 175 (English translation)", document.title
      document.each do |passage|
        assert_equal "eng", passage.language
        assert passage.text.unicode_normalized?(:nfc)
      end
    end

    def test_rimanum_full_label_anchors_resolve_including_primes
      document = Nabu::Adapters::OraccTranslationParser.new.parse(
        File.join(FIXTURES, "html-en", "rimanum", "P405134.html"),
        urn: "urn:nabu:oracc:rimanum:P405134-en",
        corpusjson_path: File.join(FIXTURES, "rimanum", "corpusjson", "P405134.json")
      )
      assert_equal(%w[o.1 r.1’ seal.1.1’],
                   document.map { |passage| passage.urn.split(":").last })
      assert_equal "[...]", document.first.text
    end

    def test_rimanum_p405432_units_and_nfc_text
      document = Nabu::Adapters::OraccTranslationParser.new.parse(
        RIM_HTML, urn: RIM_URN, corpusjson_path: RIM_CORPUS
      )
      assert_equal ["#{RIM_URN}:o.1", "#{RIM_URN}:o.3", "#{RIM_URN}:r.2", "#{RIM_URN}:r.3"],
                   document.map(&:urn)
      assert_includes document.first.text, "ŋešbun-allocation"
    end

    # -- identity --------------------------------------------------------------

    def test_urn_diverging_from_the_corpusjson_minting_raises
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::OraccTranslationParser.new.parse(
          SAA_HTML, urn: SAA_URN, corpusjson_path: RIM_CORPUS
        )
      end
      assert_match(/urn mismatch/, error.message)
    end

    # -- degradation (doctored real fixtures, the with_doctored_license idiom) --

    def test_html_without_translation_cells_is_skipped_not_quarantined
      doctored = doctor(SAA_HTML) { |html| html.gsub(%r{<td class="t1 xtr".*?</td>}m, "") }
      assert_raises(Nabu::DocumentSkipped) do
        Nabu::Adapters::OraccTranslationParser.new.parse(
          doctored, urn: SAA_URN, corpusjson_path: SAA_CORPUS
        )
      end
    end

    def test_prose_cell_anchored_at_a_non_line_row_reattaches_to_the_next_line
      # Move the first prose cell's anchor from the o 1 line-start row
      # (P405432.3) to the obverse SURFACE row (P405432.o.2, not a
      # line-start): the unit must reattach to the next labeled row — same
      # passages as the pristine parse, no prose dropped.
      doctored = doctor(RIM_HTML) { |html| html.sub('data-tlit-id="P405432.3"', 'data-tlit-id="P405432.o.2"') }
      document = Nabu::Adapters::OraccTranslationParser.new.parse(
        doctored, urn: RIM_URN, corpusjson_path: RIM_CORPUS
      )
      assert_equal "#{RIM_URN}:o.1", document.first.urn
      assert_includes document.first.text, "120 liters"
    end

    def test_two_units_resolving_to_one_label_join_rather_than_duplicate
      # Anchor the o 3 unit at o 1's row too: both units resolve to o.1 and
      # must JOIN into one passage (passage urns stay unique), in cell order.
      doctored = doctor(RIM_HTML) { |html| html.sub('data-tlit-id="P405432.5"', 'data-tlit-id="P405432.3"') }
      document = Nabu::Adapters::OraccTranslationParser.new.parse(
        doctored, urn: RIM_URN, corpusjson_path: RIM_CORPUS
      )
      first = document.first
      assert_equal "#{RIM_URN}:o.1", first.urn
      assert_includes first.text, "120 liters"
      assert_includes first.text, "Issued at the house"
      assert_equal ["#{RIM_URN}:o.1", "#{RIM_URN}:r.2", "#{RIM_URN}:r.3"], document.map(&:urn)
    end

    # -- P14-9 fix 2: trailing prose past all line-starts reattaches backward --

    P14 = Nabu::TestSupport.fixtures("oracc_p14_9")

    def test_trailing_prose_past_all_line_starts_reattaches_backward
      # saao-saa08 P336145: the final prose unit anchors at row P336145.13, an
      # unlemmatized "traces of a name" line (print label "(r 3)") the corpusjson
      # never mints — no readable signs. Reattach-FORWARD finds no line-start
      # after it; the honest fallback reattaches BACKWARD to the last line-start
      # (r 2), so the prose is kept and the suffix still exists in the tablet
      # (Query::Parallel's contract).
      document = Nabu::Adapters::OraccTranslationParser.new.parse(
        File.join(P14, "html-en", "saao-saa08", "P336145.html"),
        urn: "urn:nabu:oracc:saao-saa08:P336145-en",
        corpusjson_path: File.join(P14, "saao-saa08", "saa08", "corpusjson", "P336145.json")
      )
      suffixes = document.map { |p| p.urn.split(":").last }
      assert_includes suffixes, "r.2", "the trailing prose reattaches to r 2"
      trailing = document.find { |p| p.urn.end_with?(":r.2") }
      assert_includes trailing.text, "From", "the '[From NN]' prose is not dropped"
    end

    # -- P14-13: catalog-only skeleton blms tablet — fall back to print marker --

    P14_13 = Nabu::TestSupport.fixtures("oracc_p14_13")
    SKEL_HTML = File.join(P14_13, "html-en", "blms", "X000003.html")
    SKEL_CORPUS = File.join(P14_13, "blms", "corpusjson", "X000003.json")
    SKEL_URN = "urn:nabu:oracc:blms:X000003-en"

    def parse_skeleton(html: SKEL_HTML)
      Nabu::Adapters::OraccTranslationParser.new.parse(
        html, urn: SKEL_URN, corpusjson_path: SKEL_CORPUS,
              title: "GAAL 2, pl. 14 (English translation)"
      )
    end

    def test_skeleton_tablet_prose_anchors_on_its_printed_label
      # blms X000003 is a catalog-only skeleton: its corpusjson line-starts carry
      # empty ref AND label, so the labels map is empty and neither the forward
      # nor the backward reattach can resolve the HTML render-id anchors
      # ("X000003.2l"). But each prose cell PRINTS its label in span.xtr-label
      # ("(o 1)"), so the unit anchors on that rather than being dropped.
      document = parse_skeleton
      assert_equal ["#{SKEL_URN}:o.1", "#{SKEL_URN}:o.2"], document.map(&:urn)
      assert_equal (0..1).to_a, document.map(&:sequence)
    end

    def test_skeleton_prose_kept_verbatim_with_restorations_and_english_override
      document = parse_skeleton
      first = document.first
      assert_includes first.text, "[detain him]"   # restoration kept
      assert_includes first.text, "(in a house)"   # gloss kept
      refute_match(/\A\(o/, first.text, "the print marker is not part of the prose")
      assert_equal "eng", document.language
      assert_equal "attribution", document.license_override
      document.each { |p| assert p.text.unicode_normalized?(:nfc) }
    end

    def test_skeleton_unit_with_no_corpusjson_label_and_no_print_marker_raises
      # The loud-refusal guard survives the fallback: strip the span.xtr-label
      # markers and the same skeleton now resolves to NOTHING in either the
      # corpusjson or the fragment — prose would be dropped, so it must raise.
      doctored = doctor(SKEL_HTML) { |html| html.gsub(%r{<span class="xtr-label">.*?</span>}, "") }
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::OraccTranslationParser.new.parse(
          doctored, urn: SKEL_URN, corpusjson_path: SKEL_CORPUS
        )
      end
      assert_match(/resolves to no line-start row and prints no label/, error.message)
    end

    private

    def doctor(path)
      dir = Dir.mktmpdir
      doctored = File.join(dir, File.basename(path))
      File.write(doctored, yield(File.read(path)))
      doctored
    end
  end
end
