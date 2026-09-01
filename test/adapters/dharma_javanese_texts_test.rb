# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::DharmaJavaneseTexts (P92-4): the philology repo — the
# family's critical-edition shapes. Fixtures (see the README): the
# Deśavarṇana trimmed to chapter 1 (nested chapter > canto(met) > lg > l
# verse), Bhīma Svarga trimmed to its first ten paragraphs (lb-less prose
# apparatus → paragraph mode), and one whole diplomatic transcription
# (folio-line lb grain).
class DharmaJavaneseTextsTest < Minitest::Test
  include AdapterConformance

  DESA = "urn:nabu:dharma-javanese-texts:CritEdKakavinDesavarnana"
  BHIMA = "urn:nabu:dharma-javanese-texts:CritEdBhimaSvarga"
  DIPL = "urn:nabu:dharma-javanese-texts:DiplEdDurgastakaPerpusnasL128"

  def conformance_adapter = Nabu::Adapters::DharmaJavaneseTexts.new

  def conformance_workdir = Nabu::TestSupport.fixtures("dharma-javanese-texts")

  def conformance_expected_source_id = "dharma-javanese-texts"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn }
  end

  def test_manifest
    manifest = Nabu::Adapters::DharmaJavaneseTexts.manifest
    assert_equal "dharma-javanese-texts", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "dharma-epidoc", manifest.parser_family
  end

  # -- the kakawin shape: chapter.canto.stanza.pāda + met annotations --------

  def test_desavarnana_cites_chapter_canto_stanza_pada_with_meter
    document = adapter.parse(ref_for(DESA))
    assert_equal "kaw-Latn", document.language
    assert_equal "https://creativecommons.org/licenses/by/4.0/", document.metadata["license"],
                 "the philology repo's in-file grant is CC BY (the epigraphy repos say BY-SA) — " \
                 "recorded per document, exactly why"
    opening = document.passages.find { |p| p.urn == "#{DESA}:1.1.1.a" }
    refute_nil opening, "chapter 1 > canto 1 > stanza 1 > pāda a"
    assert_match(/oṃ nāthāya namo stu te/, opening.text)
    assert_equal "jagaddhita", opening.annotations["met"],
                 "the canto's met= rides every pāda — the meter axis's SEA feed"
  end

  # -- the prose-apparatus shape: paragraph mode, lem preferred --------------

  def test_bhima_svarga_prose_is_paragraph_grain_reading_the_lemma
    document = adapter.parse(ref_for(BHIMA))
    first = document.passages.first
    assert_equal "#{BHIMA}:p1", first.urn, "no <lb> anywhere → paragraph keys"
    assert_equal "oṁ avighnam astu.", first.text,
                 "app reads the editor's lem; the witness rdg lanes are apparatus"
    second = document.passages.find { |p| p.urn == "#{BHIMA}:p2" }
    assert_match(/\Ahana sira brahmana ṛṣi/, second.text)
  end

  # -- the diplomatic shape: folio-line lb grain ------------------------------

  def test_diplomatic_transcription_keeps_folio_line_grain
    document = adapter.parse(ref_for(DIPL))
    urns = document.passages.map { |p| p.urn.split(":").last }
    assert_includes urns, "1r1", "the manuscript's own folio-line numbers are the citation"
    assert_includes urns, "1r2"
  end
end
