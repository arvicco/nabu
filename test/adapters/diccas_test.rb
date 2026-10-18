# frozen_string_literal: true

require "test_helper"

# Nabu::Adapters::Diccas (P95-4): the Disaster Corpus in Classical
# Arabic Sources — one TEI file, ten classical books, catastrophe
# accounts with embedded English translation glosses. CC BY-NC-SA 4.0
# → nc. The fixture carries the header + books 1 (Qurʾān) and 10
# (al-Jāḥiẓ) whole.
class DiccasTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

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
    assert_equal({ "value" => "religious" }, documents.fetch(QURAN).metadata.dig("facets", "genre"),
                 "P109-4: the genre word reaches the facet lane")
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

  # The body byline per book: the author (Arabic name + its
  # transliteration gloss) and the life dates — the dating lane's
  # author-life envelope, class composition (the work was written within
  # the author's life; the disco author-band precedent).
  def test_the_byline_author_and_life_dates_reach_metadata_and_the_date_lane
    jahiz = documents.fetch(JAHIZ)
    assert_equal "ʿAmr ibn Baḥr ibn Maḥbūb al-Kinānī bi-l-walāʾ, al-Laythī, Abū ʿUthmān, known as al-Ǧāḥiẓ",
                 jahiz.metadata["author"]
    assert_equal "عمرو بن بحر بن محبوب الكناني بالولاء، الليثي، أبو عثمان، الشهير بالجاحظ",
                 jahiz.metadata["author_ar"], "the transliteration gloss never pollutes the Arabic name"
    assert_equal({ "birth" => { "raw" => "767/150", "ce" => 767, "ah" => 150 },
                   "death" => { "raw" => "869/255", "ce" => 869, "ah" => 255 } },
                 jahiz.metadata["author_life"], "upstream writes this pair CE/AH — read by magnitude")
    assert_equal({ "not_before" => 767, "not_after" => 869, "raw" => "b. 767/150 – d. 869/255",
                   "class" => "composition" }, jahiz.metadata["date"])
    quran = documents.fetch(QURAN)
    %w[author author_life date].each { |key| refute quran.metadata.key?(key), "no byline → no #{key}" }
  end

  # The real byline strings of all nine authored books (the fixture holds
  # one; the rest are verbatim from the full deposit): AH/CE pairs in both
  # orders, and Muslim's bare CE year with its @when.
  def test_life_dates_parse_both_calendars_in_either_order
    parse = Nabu::Adapters::Diccas.method(:life_year)
    assert_equal({ "raw" => "194/810", "ce" => 810, "ah" => 194 }, parse.call("194/810"))
    assert_equal({ "raw" => "813/1410", "ce" => 1410, "ah" => 813 }, parse.call("813/1410"))
    assert_equal({ "raw" => "1126/510", "ce" => 1126, "ah" => 510 }, parse.call("1126/510"),
                 "Ibn al-Jawzī's pair is CE/AH; the CE half stays upstream's claim verbatim")
    assert_equal({ "raw" => "821", "ce" => 821 }, parse.call("821", when_attr: "0821"))
    assert_nil parse.call("no data")
  end

  # The header listBibl per msDesc: the source edition's imprint —
  # edition LINEAGE, carried, never the text's origin or date.
  def test_the_header_edition_imprint_rides_metadata
    edition = documents.fetch(JAHIZ).metadata["edition"]
    assert_equal "رسائل الجاحظ", edition["title"]
    assert_equal "عبد السلام محمد هارون", edition["editor"]
    assert_equal "مكتبة الخانجي", edition["publisher"]
    assert_equal "القاهرة", edition["pub_place"]
    assert_equal "1384/1964", edition["date"]
    assert_equal ["https://shamela.ws/book/10428/"], edition["refs"]
    assert_equal({ "refs" => ["https://quran.com/"] }, documents.fetch(QURAN).metadata["edition"])
  end

  # <placeName translation=…> and <term type="catastrophe"
  # translation=… subtype=…> were transparent reading text; they now
  # ride the passage annotations (text unchanged) and project per book.
  def test_places_and_catastrophe_terms_ride_passage_annotations
    jahiz = documents.fetch(JAHIZ)
    passage = jahiz.find { |p| Array(p.annotations["places"]).any? { |pl| pl["translation"] == "Egypt" } }
    refute_nil passage
    assert_includes passage.annotations["places"], { "name" => "مصر", "translation" => "Egypt" }
    assert_includes passage.annotations["catastrophes"], { "term" => "نكبة", "translation" => "catastrophe" }
    assert_includes passage.text, "مصر", "the tagged words stay reading text"
    quran = documents.fetch(QURAN)
    typed = quran.flat_map { |p| Array(p.annotations["catastrophes"]) }.find { |t| t["subtype"] }
    assert_equal "divine", typed["subtype"]
    earhquake = quran.flat_map { |p| Array(p.annotations["catastrophes"]) }
                     .find { |t| t["translation"] == "earhquake" }
    refute_nil earhquake, "the annotation keeps upstream's attribute verbatim"
  end

  def test_book_grain_disaster_and_place_lanes_for_the_facets
    quran = documents.fetch(QURAN).metadata
    assert_includes quran["disaster_types"], "earthquake"
    refute_includes quran["disaster_types"], "earhquake", "the one typo fold joins the label"
    assert_includes quran["disaster_types"], "earthquake, shaken"
    assert_equal %w[divine], quran["disaster_classes"]
    refute quran.key?("places_mentioned"), "book 1 names no place in its paragraphs"
    jahiz = documents.fetch(JAHIZ).metadata
    assert_equal %w[Aleppo Anatolia Antioch Egypt Iraq], jahiz["places_mentioned"].sort
    assert_equal ["catastrophe", "difficulty", "hail cold", "plague", "thirst", "wind"],
                 jahiz["disaster_types"].map { |t| t.delete(",") }.sort
  end

  def test_the_life_envelope_projects_through_the_metadata_date_lane_as_composition
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["diccas"]
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "diccas", name: "DiCCAS", adapter_class: "Nabu::Adapters::Diccas",
                                        license_class: "nc")
    Nabu::Store::Loader.new(db: db, source: source).load_from(conformance_adapter, workdir: conformance_workdir)
    rows = Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: db, slug: "diccas")
    assert_equal 1, rows, "only the authored book dates — the Qurʾān has no byline"
    axis = db[:document_axes].first
    assert_equal [767, 869, "composition"], axis.values_at(:not_before, :not_after, :date_class)
    assert_nil axis[:place_name], "mentioned places never become the book's place"
  end

  def test_language_is_classical_arabic
    documents.each_value { |doc| assert_equal "ara", doc.language }
  end
end
