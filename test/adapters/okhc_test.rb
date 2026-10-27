# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# OKHC adapter tests (P91-1): the Open Korean Historical Corpus's curated
# historical slice — jsonl files from the HF deposit, one RECORD = one
# document (records are titled, dated, URL-addressable entries), body
# lines as passages. Fixtures are real rows from the repo's own published
# sample plus one live-probed Hanmun/null-copyright row. No network in
# tests; the bulk fetch is owner-fired.
class OkhcTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("okhc")

  def conformance_adapter
    Nabu::Adapters::Okhc.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "okhc"
  end

  def setup
    @adapter = Nabu::Adapters::Okhc.new
  end

  def documents
    @documents ||= @adapter.discover(FIXTURES).map { |ref| @adapter.parse(ref) }
  end

  def document(urn)
    documents.find { |d| d.urn == urn }
  end

  # --- manifest -------------------------------------------------------------

  def test_manifest_is_nc_with_the_requested_citation_in_the_credit
    manifest = Nabu::Adapters::Okhc.manifest
    assert_equal "okhc", manifest.id
    assert_equal "nc", manifest.license_class
    assert_match(/Song/, manifest.credit, "the authors' requested citation rides every surface")
    assert_match(/Open Korean Historical Corpus/, manifest.credit)
  end

  # --- discovery ------------------------------------------------------------

  def test_discover_yields_one_document_per_record_across_all_files
    refs = @adapter.discover(FIXTURES).to_a
    assert_equal 42, refs.size, "42 records across the 7 fixture files"
    assert(refs.all? { |ref| ref.id.start_with?("urn:nabu:okhc:") })
    assert_includes refs.map(&:id), "urn:nabu:okhc:sagi:sg_003_0030_0070"
  end

  def test_an_id_less_line_is_censused_unrecognized_never_silent
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "sagi"))
      File.write(File.join(dir, "sagi", "sagi.jsonl"), "{\"no_id\": true}\n")
      assert_empty @adapter.discover(dir).to_a
      skips = @adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert_match(/sagi\.jsonl/, skips.notes.join(" "))
    end
  end

  # --- parse: grain, languages, license -------------------------------------

  def test_sagi_record_parses_with_lzh_and_the_pd_override
    doc = document("urn:nabu:okhc:sagi:sg_003_0030_0070")
    refute_nil doc
    assert_equal "lzh", doc.language, "Classical Chinese label -> lzh (the held-shelf codemap precedent)"
    assert_equal "누리가 곡식을 해치다 ( 406년 07월 )", doc.title
    assert_equal "open", doc.license_override, "a Public Domain record relabels open (the ud split precedent)"
    assert_equal 1, doc.passages.size
    assert_equal "五年, 秋七月, 國西蝗害榖.", doc.passages.first.text
    assert_equal "urn:nabu:okhc:sagi:sg_003_0030_0070:1", doc.passages.first.urn
    assert_equal 1145, doc.metadata["year"]
    assert_match(/db\.history\.go\.kr/, doc.metadata["permanent_url"])
  end

  def test_hanmun_label_maps_to_lzh
    doc = document("urn:nabu:okhc:ilseongnok:1760-01-0-01-영조-GK12811_00-2-000-000")
    refute_nil doc
    assert_equal "lzh", doc.language, "the edition labels Korean-context Literary Sinitic 'Hanmun'"
  end

  # A real ND record (73 exist corpus-wide): ND earns NO upgrade — no
  # override, the source's nc governs, the verbatim status rides metadata.
  def test_an_nd_record_keeps_the_source_class
    doc = document("urn:nabu:okhc:aks_collection:WU.1985.4886-20101008.B015a_025_00001_YYY")
    refute_nil doc
    assert_nil doc.license_override
    assert_equal "CC BY-NC-ND 2.0 KR", doc.metadata["copyright"]
  end

  def test_korean_labels_map_to_ko
    korean = documents.select { |d| d.language == "ko" }
    refute_empty korean, "Early Modern/Modern Korean rows mint ko (honest-coarse; stages are a posture story)"
  end

  def test_multiline_body_becomes_ordered_line_passages
    doc = documents.find { |d| d.passages.size > 1 }
    refute_nil doc, "the fixtures carry multiline bodies"
    assert_equal (0...doc.passages.size).to_a, doc.passages.map(&:sequence)
    assert_equal(doc.passages.map(&:urn),
                 doc.passages.each_with_index.map { |_, i| "#{doc.urn}:#{i + 1}" })
  end

  # P91-1 first-sync census: the DEPOSIT's schema names the field
  # copyright_status (the repo sample's older schema says copyright — the
  # drift that silently nulled every override on the first load). This
  # row is a real deposit line, appended 2026-09-01: real-schema bytes
  # pin the PD → open relabel and the Hanmun mapping together.
  def test_the_deposit_schema_copyright_status_field_drives_the_override
    doc = document("urn:nabu:okhc:sagi:sg_001_0060_0130")
    refute_nil doc
    assert_equal "lzh", doc.language
    assert_equal "open", doc.license_override, "copyright_status: Public Domain relabels open"
    assert_equal "Public Domain", doc.metadata["copyright"]
  end

  # P91-1 first-sync census: gongu/jpn_records carry Western-language
  # documents (2,735 English + 25 French quarantined by the unknown-label
  # net on the first run) — classified onto the held en/fra codes.
  def test_western_language_labels_map_to_the_held_codes
    assert_equal "en", Nabu::Adapters::OkhcJsonlParser::LANGUAGES.fetch("English")
    assert_equal "fra", Nabu::Adapters::OkhcJsonlParser::LANGUAGES.fetch("French")
    row = { "id" => "gongu:x1", "content" => { "body" => "An English work", "title" => "t" },
            "language" => "English", "copyright" => "Public Domain" }
    record = Nabu::Adapters::OkhcJsonlParser.parse_record(JSON.generate(row))
    assert_equal "en", record.language
  end

  # --- P92-6: the year field onto the timeline ------------------------

  def test_dating_registers_in_the_metadata_dates_lane
    assert_equal :year_key, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["okhc"],
                 "the per-record year projects through the catalog lane — no re-parse"
  end

  def test_the_year_key_shape_reads_only_integer_years
    shape = Nabu::Store::TimelineBuilder::MetadataDates.method(:year_key)
    assert_equal [1145, 1145, "1145"], shape.call({ "year" => 1145 }),
                 "a bare integer year is a one-year envelope"
    assert_equal [nil, nil, nil], shape.call({}), "year-less records mint nothing"
    assert_equal [nil, nil, nil], shape.call({ "year" => "1145?" }),
                 "no bounds invented from prose"
  end

  # --- the named-entity markup (content.body_xml / title_xml) ----------------

  # The deposit carries a parallel *_xml field whose <ner_TYPE> spans mark
  # names inside the plain body; line N of the xml is line N of the body.
  # Each passage carries its line's spans as the "entities" annotation
  # (type verbatim, the ner_ prefix being the tag namespace).
  def test_body_xml_spans_ride_their_line_as_entities
    doc = document("urn:nabu:okhc:ilseongnok:1760-01-0-01-영조-GK12811_00-2-000-000")
    assert_equal [{ "type" => "건물", "text" => "太廟" }, { "type" => "건물", "text" => "毓祥宮" },
                  { "type" => "지명", "text" => "校洞" }, { "type" => "지명", "text" => "生洞" }],
                 doc.passages.first.annotations["entities"]
  end

  # A body-less record's passages come from the title — so the title_xml
  # spans are the ones that ride.
  def test_a_title_only_record_carries_the_title_xml_spans
    doc = document("urn:nabu:okhc:ilseongnok:1767-04-0-23-영조-GK12811_00-11-000-001")
    assert_equal "藥房入診。余侍坐。", doc.passages.first.text
    assert_equal [{ "type" => "관서", "text" => "藥房" }], doc.passages.first.annotations["entities"]
  end

  # With a body present the title is the document title, not a passage —
  # its spans have no passage to ride (the body's own spans do).
  def test_title_spans_never_ride_body_passages
    doc = document("urn:nabu:okhc:ilseongnok:1781-04-0-20-정조-GK12811_00-98-000-003")
    texts = doc.passages.flat_map { |p| Array(p.annotations["entities"]) }.map { |e| e["text"] }
    assert_equal ["直提學"], texts, "鄭民始 is marked only in the title"
  end

  def test_the_aks_person_and_place_markup_rides_verbatim
    doc = document("urn:nabu:okhc:aks_royal:RD00158")
    assert_equal [{ "type" => "person", "text" => "人禮" }, { "type" => "place", "text" => "勒薩" },
                  { "type" => "person", "text" => "朴齊純" }],
                 doc.passages.first.annotations["entities"]
  end

  # Not names: ilseongnok's 세주 (interlinear small-note) / 주석 spans and
  # klc's ner_unknown (cyclical-year heads) / ner_948a54 (a colour class
  # over 吐 reading particles) are text structure — skipped by rule.
  def test_non_name_markup_is_skipped_by_rule
    note = document("urn:nabu:okhc:ilseongnok:1778-06-0-05-정조-GK12811_00-63-000-011")
    assert_nil note.passages.first.annotations["entities"]
    particles = document("urn:nabu:okhc:klc:ITKC_MO_0220A_0120_000_0060")
    assert(particles.passages.none? { |p| p.annotations["entities"] })
    assert_equal %w[건물 관서 관직 능원 물건 서명 인물 지명 person place].sort,
                 Nabu::Adapters::OkhcJsonlParser::ENTITY_TYPES.sort
  end

  def test_a_record_whose_xml_lines_disagree_with_the_body_carries_no_entities
    row = { "id" => "sagi:x2", "language" => "Hanmun",
            "content" => { "body" => "甲\n乙", "body_xml" => "<ner_인물>甲</ner_인물>", "title" => "t" } }
    record = Nabu::Adapters::OkhcJsonlParser.parse_record(JSON.generate(row))
    assert_equal [nil, nil], record.entities, "line pairing is the only honest join — never guessed"
  end

  def test_okhc_joins_the_entity_index_roster
    roster = YAML.safe_load_file(File.expand_path("../../config/entity_index.yml", __dir__)).fetch("sources")
    assert_includes roster, "okhc"
  end

  # --- defensive quarantines ------------------------------------------------

  def test_an_unknown_language_label_quarantines_the_record
    Dir.mktmpdir do |dir|
      row = { "id" => "sagi:x1", "text" => "words", "content" => { "body" => "words", "title" => "t" },
              "language" => "Martian", "copyright" => "Public Domain" }
      FileUtils.mkdir_p(File.join(dir, "sagi"))
      File.write(File.join(dir, "sagi", "sagi.jsonl"), "#{JSON.generate(row)}\n")
      ref = @adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { @adapter.parse(ref) }
      assert_match(/unknown language label "Martian"/, error.message)
    end
  end

  def test_a_malformed_line_quarantines_only_its_own_record
    Dir.mktmpdir do |dir|
      good = File.read(File.join(FIXTURES, "sagi", "sagi.jsonl")).lines.first
      FileUtils.mkdir_p(File.join(dir, "sagi"))
      File.write(File.join(dir, "sagi", "sagi.jsonl"), "#{good}{\"id\": \"sagi:broken\", not json\n")
      refs = @adapter.discover(dir).to_a
      assert_equal 2, refs.size, "both lines carry ids and discover"
      assert @adapter.parse(refs[0]), "the good record parses"
      assert_raises(Nabu::ParseError) { @adapter.parse(refs[1]) }
    end
  end
end
