# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# CcmhTxtParser (P14-5): the ccmh-txt family — CCMH's three txt-only texts
# (Suprasliensis + the two Vitae), 7-digit line codes, two citation schemes
# (folio-line diplomatic vs chapter-verse), and the diplomatic line-break
# rejoining mechanics (owner requirement 2026-07-12): pristine text stays
# the verbatim line; text_normalized is minted from a documented derivation
# (hyphen-split words completed, orphan fragments dropped) carried in the
# "hyphen_join" annotation. Fixtures are byte-identical trimmed slices of
# the real Kielipankki files.
class CcmhTxtParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("ccmh")

  def parse(file, scheme:, urn:, title:)
    Nabu::Adapters::CcmhTxtParser.new.parse(
      File.join(FIXTURES, file),
      scheme: scheme, urn: urn, language: "chu", title: title
    )
  end

  def suprasliensis
    parse("suprasliensis.txt", scheme: "folio-line",
                               urn: "urn:nabu:ccmh:suprasliensis", title: "Codex Suprasliensis")
  end

  def vita_constantini
    parse("vita_constantini.txt", scheme: "chapter-verse",
                                  urn: "urn:nabu:ccmh:vita-constantini", title: "Vita Constantini")
  end

  def vita_methodii
    parse("vita_methodii.txt", scheme: "chapter-verse",
                               urn: "urn:nabu:ccmh:vita-methodii", title: "Vita Methodii")
  end

  # --- folio-line scheme (Suprasliensis): one passage per physical line -------

  def test_folio_line_mints_part_folio_side_line_citations
    document = suprasliensis
    assert_equal "urn:nabu:ccmh:suprasliensis", document.urn
    assert_equal 72, document.size, "one passage per fixture line"
    first = document.first
    assert_equal "urn:nabu:ccmh:suprasliensis:1.1.1.1", first.urn,
                 "code 1001101 = part 1, folium 001, side 1 (recto), line 01 — zero-padding stripped"
    assert_equal "my(ix& bo (ot& boga (jesv@ . tvojei bo", first.text
  end

  def test_folio_line_keeps_the_diplomatic_hyphen_verbatim
    passage = find(suprasliensis, "1.1.1.3")
    assert_equal ")i do s&mr)$ti . ne dobr@ mOdrova-", passage.text,
                 "canonical means canonical — the line-break hyphen is upstream text"
  end

  def test_folio_line_crosses_the_recto_verso_boundary
    assert_equal "slavy !xsovy . i c@sar$stva nebes&naa-", find(suprasliensis, "1.1.2.1").text,
                 "code 1001201 = folium 1 verso line 1"
  end

  def test_folio_line_keeps_the_upstream_side_3_slip_verbatim
    # Code 3014301 carries side digit 3 (upstream's own numbering slip — the
    # catalogue's "not properly checked" made concrete). Kept raw, never
    # validated to recto/verso.
    passage = find(suprasliensis, "3.14.3.1")
    assert_equal "*pomySl^enije Ze v)$nE vid@ti kako (ot&-", passage.text
  end

  def test_folio_line_suffixes_duplicate_codes_in_document_order
    # Upstream reality: codes 1042114-1042119 appear twice (the second run a
    # mis-numbered continuation of side 2) with distinct text — :b2, never
    # merged (GRETIL/ccmh-ces precedent).
    document = suprasliensis
    assert_equal "bogu v@rovav&Se !xsa (ispov@dav)$Se .", find(document, "1.42.1.14").text
    assert_equal "m& mOCenic@ Cuditi sE ni (o d&vo^ju .", find(document, "1.42.1.14:b2").text
  end

  # --- the hyphen_join mechanics (owner requirement, 2026-07-12) --------------

  def test_hyphen_line_completes_the_split_word_in_the_search_form
    passage = find(suprasliensis, "1.1.1.3")
    assert_equal({ "hyphen_join" => { "tail" => "ti" } }, passage.annotations)
    assert_equal ")i do s&mr)$ti . ne dobr@ modrovati", passage.text_normalized,
                 "the split word is whole in the search form (searchable), hyphen dropped"
  end

  def test_continuation_line_drops_the_orphan_fragment_from_the_search_form
    passage = find(suprasliensis, "1.1.1.4")
    assert_equal "ti na c@lomOdrovanije k& bogu .", passage.text, "pristine text untouched"
    assert_equal({ "hyphen_join" => { "orphan" => "ti" } }, passage.annotations)
    assert_equal "na c@lomodrovanije k& bogu .", passage.text_normalized,
                 "the orphan fragment is index noise and is dropped"
  end

  def test_a_line_can_both_continue_and_start_a_split
    # Line 1001106 continues to-/m$jenije AND ends (ag'g^e- (tail "la").
    passage = find(suprasliensis, "1.1.1.6")
    assert_equal({ "hyphen_join" => { "orphan" => "m$jenije", "tail" => "la" } },
                 passage.annotations)
    assert_equal "v&vr&ze te v& xulo . (ag'g^ela", passage.text_normalized
  end

  def test_hyphen_join_crosses_the_code_collision_seam
    # Line 1042213 ends (jedino- and the completing "m&" opens the SECOND
    # 1042114 run — the join follows file order straight across the slip.
    # (It is also itself a continuation: its orphan "n&" completes the
    # previous line's s&podob)$(je- and is dropped.)
    document = suprasliensis
    assert_equal ". nam' ze pr@d&lezit& ne (o (jedinom&",
                 find(document, "1.42.2.13").text_normalized
    assert_equal({ "hyphen_join" => { "orphan" => "m&" } },
                 find(document, "1.42.1.14:b2").annotations)
  end

  def test_lines_without_a_split_carry_no_annotation
    passage = find(suprasliensis, "1.1.1.1")
    assert_empty passage.annotations
    assert_equal passage.text.downcase, passage.text_normalized
  end

  def test_final_hyphen_line_of_a_document_keeps_its_fragment
    # No next line, no tail: the fragment stays searchable as-is rather than
    # being silently dropped. Exercised via a two-line scratch file.
    Dir.mktmpdir do |dir|
      path = File.join(dir, "t.txt")
      File.write(path, "1001101 pr@Zde slovo my(ix&\n1001102 kon)$C$no slo-\n")
      document = Nabu::Adapters::CcmhTxtParser.new.parse(
        path, scheme: "folio-line", urn: "urn:t", language: "chu", title: "t"
      )
      last = document.to_a.last
      assert_empty last.annotations
      assert_equal "kon)$c$no slo-", last.text_normalized
    end
  end

  # --- search_source: the documented, recomputable derivation -----------------

  def test_search_source_is_recomputable_from_text_plus_annotations
    suprasliensis.each do |passage|
      assert_equal Nabu::Normalize.search_form(
        Nabu::Adapters::CcmhTxtParser.search_source(passage.text, passage.annotations),
        language: passage.language
      ), passage.text_normalized,
                   "#{passage.urn}: text_normalized must be the minted fold of the derivation"
    end
  end

  def test_search_source_falls_back_to_the_raw_line_when_the_derivation_empties
    assert_equal "ti-", Nabu::Adapters::CcmhTxtParser.search_source(
      "ti-", { "hyphen_join" => { "orphan" => "ti-" } }
    ), "an all-orphan line keeps its raw text (text_normalized must not be empty)"
  end

  # --- chapter-verse scheme (the Vitae): verse-grain aggregation --------------

  def test_chapter_verse_aggregates_a_verse_and_mints_chapter_dot_verse
    document = vita_constantini
    assert_equal 17, document.size
    incipit = find(document, "0.0")
    assert_equal "*pamet$ i ZitJe blaZenago uCitelja naSego *kostan'tina " \
                 "filosofa, pr&vago nastav'nika sloven'skU jezykU. blagoslovi:",
                 incipit.text, "chapter 00 is the incipit — cited 0.0, lines joined by a space"
  end

  def test_chapter_verse_absorbs_an_adjacent_code_slip_into_one_verse
    # VC 0600200 appears on two adjacent lines (the second should have been
    # 0600210): same verse run, ONE passage — it is one continuous sentence.
    passage = find(vita_constantini, "6.2")
    assert_equal "kako vyi xristJani jedin$ bog& m@neqe, razm@Sajete i paky " \
                 "na trJi, glagoljuqe, jako wt$c$ i syn$ i dux$ jest$?", passage.text
    assert_nil find(vita_constantini, "6.2:b2")
  end

  def test_chapter_verse_suffixes_a_nonadjacent_duplicate_verse
    # VC 1101010 recurs 17 lines later (a slip for 1101910) — a separate run,
    # distinct text: :b2, never merged into the earlier verse.
    document = vita_constantini
    assert_equal "reCe Ze filosof$: wgn$ iskuSajet$ zlat$ i srebro, a Clov@k$ " \
                 "umom$ wts@kajet$ l$ZU wt$ istiny.", find(document, "11.10").text
    assert_equal "s&tvorit$, to posl@di slad'k$ plod' priplodit$.",
                 find(document, "11.10:b2").text
  end

  def test_chapter_verse_absorbs_a_duplicate_code_inside_one_run
    # VM 1700100 recurs with 1700110 between — still one consecutive verse
    # run (17,001): one passage, no :b2.
    document = vita_methodii
    assert_equal 5, document.size
    assert_equal(%w[0.0 1.1 1.2 17.1 17.2], document.map { |p| p.urn.split(":").last })
    assert_equal "takoZe v$sE viny ot&s@k& po v$sE strany i usta mnogor@C$nyix& " \
                 "zagradi, teCenije Ze s&v$r$Si, v@ru s&bljude, Caja prav$d$nago v@n$ca.",
                 find(document, "17.1").text
  end

  def test_chapter_verse_handles_crlf_line_endings
    # Both Vitae are CRLF upstream (Suprasliensis is LF) — no \r may leak
    # into passage text.
    vita_methodii.each do |passage|
      refute_includes passage.text, "\r", "#{passage.urn} leaked a CR"
    end
  end

  # --- errors ------------------------------------------------------------------

  def test_malformed_line_raises_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad.txt")
      File.write(path, "not-a-code some text\n")
      error = assert_raises(Nabu::ParseError) do
        Nabu::Adapters::CcmhTxtParser.new.parse(
          path, scheme: "folio-line", urn: "urn:t", language: "chu", title: "t"
        )
      end
      assert_match(/bad\.txt/, error.message)
    end
  end

  def test_unknown_scheme_raises_argument_error
    assert_raises(ArgumentError) do
      Nabu::Adapters::CcmhTxtParser.new.parse(
        "x.txt", scheme: "nope", urn: "urn:t", language: "chu", title: "t"
      )
    end
  end

  def test_two_parses_mint_identical_urns_and_forms
    first = suprasliensis
    second = suprasliensis
    assert_equal first.map(&:urn), second.map(&:urn)
    assert_equal first.map(&:text_normalized), second.map(&:text_normalized)
    assert_equal first.map(&:annotations), second.map(&:annotations)
  end

  private

  def find(document, citation)
    document.find { |p| p.urn == "#{document.urn}:#{citation}" }
  end
end
