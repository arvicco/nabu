# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Diccas (P95-4): the Disaster Corpus in Classical
# Arabic Sources — one TEI file, ten classical books, catastrophe
# accounts with embedded English translation glosses. CC BY-NC-SA 4.0
# → nc. The fixture carries the header + books 1 (Qurʾān) and 10
# (al-Jāḥiẓ) whole.
class DiccasTest < Minitest::Test
  include AdapterConformance

  QURAN = "urn:nabu:diccas:1"
  JAHIZ = "urn:nabu:diccas:10"

  def conformance_adapter
    Nabu::Adapters::Diccas.new
  end

  def conformance_workdir
    Nabu::TestSupport.fixtures("diccas")
  end

  def conformance_expected_source_id
    "diccas"
  end

  def documents
    @documents ||= begin
      adapter = conformance_adapter
      adapter.discover(conformance_workdir).to_h { |ref| [ref.id, adapter.parse(ref)] }
    end
  end

  def test_each_book_is_a_document_titled_from_the_header_msdesc
    assert_equal [QURAN, JAHIZ].sort, documents.keys.sort
    assert_equal "al-Qur'an al-Karīm", documents.fetch(QURAN).title
    assert_equal "Rasāʾil al-Jāḥiẓ", documents.fetch(JAHIZ).title
    assert_equal "religious", documents.fetch(QURAN).metadata["genre"]
  end

  def test_passages_are_arabic_with_the_english_gloss_as_annotation
    quran = documents.fetch(QURAN)
    tested = quran.find { |p| p.annotations["gloss_en"].to_s.include?("famine") }
    refute_nil tested, "the Baqara 155 test-and-famine verse carries its gloss"
    assert_includes tested.text, "وَلَنَبْلُوَنَّكُم", "the Arabic is the passage text"
    refute_includes tested.text, "We will certainly test you",
                    "the embedded English translation must never enter the text"
    assert_includes tested.annotations["gloss_en"], "We will certainly test you"
  end

  def test_citations_ride_the_division_ladder
    quran = documents.fetch(QURAN)
    assert(quran.all? { |p| p.urn.start_with?("#{QURAN}:") })
    assert(quran.any? { |p| p.urn.match?(/:\d+(\.\d+)*\.p\d+\z/) },
           "citation = div @n ladder + paragraph ordinal")
  end

  def test_language_is_classical_arabic
    documents.each_value { |doc| assert_equal "ara", doc.language }
  end
end
