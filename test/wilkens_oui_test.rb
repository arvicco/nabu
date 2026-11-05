# frozen_string_literal: true

require "test_helper"
require "zlib"
require "nabu/stext_layout"
require "nabu/wilkens_oui"

# Nabu::WilkensOui — entry segmentation of Wilkens's Handwörterbuch des
# Altuigurischen (2021) from the positioned, styled text layer, pinned
# against the RECORDED stext of five real pages (README beside the fixture).
class WilkensOuiTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("wilkens-oui")
  PDF = File.join(FIXTURES, "wilkens-sample.pdf")

  def recorded_xml
    Zlib.gunzip(File.binread(File.join(FIXTURES, "wilkens-sample.stext.xml.gz")))
  end

  # The fixture trims non-consecutive pages: folios 1 | 44–45 | 182 | 441.
  # A page whose predecessor is absent starts a fresh flow, so its leading
  # continuation lines cannot attach to the wrong entry.
  def segment(xml)
    segmenter = Nabu::WilkensOui::Segmenter.new
    previous = nil
    Nabu::StextLayout.pages(xml).each do |page|
      segmenter.feed(page, continued: previous && page.folio == previous + 1)
      previous = page.folio
    end
    segmenter
  end

  def segmenter = @segmenter ||= segment(recorded_xml)
  def entries = segmenter.entries

  def entry(headword, kind: nil, homonym: nil)
    entries.find do |e|
      e.headword == headword && (kind.nil? || e.kind == kind) && (homonym.nil? || e.homonym == homonym)
    end || flunk("no entry #{headword.inspect}")
  end

  def test_main_headwords_come_from_the_bold_run_with_their_homonym_numbers
    firsts = entries.first(3).map { |e| [e.kind, e.headword, e.homonym] }
    assert_equal [[:main, "a", 1], [:main, "a", 2], [:main, "a", 3]], firsts
    one = entry("a", homonym: 1)
    assert_equal "Vokativpartikel (enkl.), Anruf; Wehruf", one.german
    assert one.turkish.start_with?("(önceki kelimeyle birleşen) seslenme edatı")
  end

  def test_the_letter_heading_is_not_an_entry
    refute(entries.any? { |e| e.raw.strip == "a" })
    assert_equal 1, segmenter.anomalies[:letter_heading]
  end

  def test_sub_entries_are_filed_under_their_main_entry
    sub = entry("a bašlap v tägi")
    assert_equal :sub, sub.kind
    assert_equal ["a", 3], [sub.parent, sub.parent_homonym]
    assert_equal ["von a bis v", "a’dan v’ye kadar"], [sub.german, sub.turkish]
  end

  def test_cross_references_carry_their_target_and_no_gloss
    xref = entry("a ušik")
    assert_equal ["a", 4], [xref.parent, xref.parent_homonym]
    assert_equal "a užik", xref.xref
    assert_nil xref.german
    rejected = entry("(a)b")
    assert rejected.labels.include?("r")
    assert_equal "^1av", rejected.xref
  end

  def test_justified_fragments_and_hyphen_wraps_are_reassembled
    amramak = entry("amramak", kind: :main)
    assert_includes amramak.german, "Liebe, Freundschaft, Zuneigung"
    assert_includes amramak.german, "freundschaftlich", "roman hyphen-wrap freundschaft-/lich rejoined"
    assert_includes amramak.turkish, "sevgi, dostluk, sempati", "dost-/luk rejoined"
    assert_includes amramak.turkish, "maithuna’nın", "italic Sanskrit mai-/thuna rejoined"
    assert_equal "ohne Zuneigung", entry("amramaksız").german
  end

  def test_a_sub_entry_phrase_wrapping_onto_a_second_line_stays_one_headword
    sub = entry("amramak äsirkämäk ömäk erinčkämäk tsuyurkamak")
    assert_equal "amramak", sub.parent
    assert_equal "Lieben, Sichsorgen, Achtsamkeit und Bedauern^2", sub.german
  end

  def test_variant_forms_ride_the_headword_and_verbs_keep_their_hyphen
    assert entry("amranmaklıg ~ amranmak(lıg)")
    verb = entry("amran-")
    assert_includes verb.labels, "verb"
    assert_equal "lieben, begehren, liebevoll sein", verb.german
  end

  def test_a_page_top_continuation_attaches_to_the_previous_pages_entry
    sub = entry("amranmaklıg äsürtgü suvsuš")
    assert_equal "amranmaklıg ~ amranmak(lıg)", sub.parent
    assert_equal 45, sub.folio
  end

  def test_a_sub_entry_at_a_non_standard_indent_is_still_a_sub_entry
    sub = entry("bitigü p(a)ryan")
    assert_equal ["bitigü", :sub], [sub.parent, sub.kind]
    assert_equal ["Schreibzelle", "yazı hücresi, yazı kulübesi"], [sub.german, sub.turkish]
  end

  def test_multi_line_bold_headwords_assemble_across_lines_and_the_column_break
    title = entry("Kün Ay T(ä)ŋridä Kut Bulmıš Ulug Kut Ornanmıš Alpın Ärdämin El Tutmıš Alp Arslan " \
                  "Kutlug Köl Bilgä Täŋri Han")
    assert_equal :main, title.kind
    assert title.german.start_with?("Herrschertitel (Herrscher des Westuig. Königreichs)")
  end

  def test_orphan_lines_after_a_gap_are_counted_never_misfiled
    assert_operator segmenter.anomalies[:orphan_line], :>, 0
    refute(entries.any? { |e| e.headword.start_with?("kün t(ä)ŋri") })
  end

  def test_every_glossed_entry_splits_into_german_and_turkish_halves
    glossed = entries.reject { |e| e.xref || e.note }
    assert_operator glossed.size, :>, 150
    assert(glossed.all? { |e| e.german && e.turkish }, "every glossed record carries both halves")
  end

  # The etymology chain at the head of the German half ("< TochA ābhāswar
  # < Skt. ābhāsvara"): each "<"/"<<" link names its source language in
  # roman and the etymon in italic — the italic run is the boundary signal
  # the segmenter carries through its records, so the chain splits off the
  # German half while the printed record (body, raw) keeps it.
  def test_the_etymology_chain_splits_off_the_german_half
    abasvar = entry("abasvar")
    assert_equal "< TochA ābhāswar < Skt. ābhāsvara", abasvar.etymology
    assert_equal "ein Himmel und eine Götterklasse (in der buddh. Kosmologie)", abasvar.german
    assert abasvar.body.start_with?("< TochA ābhāswar < Skt. ābhāsvara ein Himmel"), "the printed record keeps it"
    abakirti = entry("abakirti")
    assert_equal ["<< Skt. abhayakῑrti", "n. pr. (ein Guru)"], [abakirti.etymology, abakirti.german]
  end

  def test_variant_etyma_and_a_chain_wrapping_onto_the_next_line_stay_one_chain
    abidarim = entry("abidarim")
    assert_equal "< TochA abhidharm / < TochB abhidhārm ~ abhidārm < Skt. abhidharma", abidarim.etymology
    assert_equal "der dritte Teil des Tripiṭaka = Scholastik", abidarim.german
    abicaruk = entry("abičaruk")
    assert_equal "<< Skt. abhicāruka ~ ābhicāraka", abicaruk.etymology
    assert_equal "Überwältigung (Titel eines tantrischen Rituals)", abicaruk.german
  end

  def test_labels_around_the_chain_stay_with_the_gloss
    amrta = entry("amṛta")
    assert_equal ["< Skt. amṛta", "(br) Nektar, Ambrosia (Name eines Pulvers)"], [amrta.etymology, amrta.german]
    bnaya = entry("bnaya d-bnay")
    assert_equal ["< Syr. bnayā d-bnay", "(c) Söhne der Söhne"], [bnaya.etymology, bnaya.german]
  end

  def test_an_etymon_reading_in_parentheses_rides_the_chain
    kun = entry("kün", homonym: 3)
    assert_equal "< Chin. � kun (Spätmittelchin. khunˊ)", kun.etymology
    assert_equal "hinterer Palast, Wohnbereich der Frauen", kun.german
  end

  # No italic etymon, no boundary: the record keeps its German half whole
  # (counted), never a regex guess at where the language label ends.
  def test_without_an_italic_etymon_the_german_half_stays_whole
    bizi = entry("Biži")
    assert_nil bizi.etymology
    assert_equal "< Chin. Bestandteil von Personennamen; n. pr. (männlich)", bizi.german
    assert_equal 1, segmenter.anomalies[:etymology_without_etymon]
    late = entry("kündülülüg")
    assert_nil late.etymology, "a chain inside a parenthetical is not the record's head"
    assert_nil entry("a", homonym: 1).etymology
    assert_equal 27, entries.count(&:etymology), "every chain-headed record of the sample but Biži"
  end

  def test_output_is_nfc
    entries.each do |e|
      [e.headword, e.german, e.turkish, e.etymology, e.raw].compact.each do |s|
        assert_equal s.unicode_normalize(:nfc), s
      end
    end
  end

  def test_segmentation_is_stable_across_two_runs
    assert_equal entries, segment(recorded_xml).entries
  end

  # -- live mutool (present on the owner's box, absent in CI) ------------

  def test_real_mutool_extraction_segments_identically_to_the_recorded_layer
    skip "mutool not on PATH — the recorded-extraction tests carry the suite" unless mutool_available?

    live = Nabu::StextLayout.extract(PDF)
    assert_equal entries, segment(live).entries
  end

  private

  def mutool_available?
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |d| File.executable?(File.join(d, "mutool")) }
  end
end
