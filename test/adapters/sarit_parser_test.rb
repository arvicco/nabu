# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# SaritParser (P26-2): the streaming parser family for SARIT scholarly TEI
# editions — a SIBLING of GretilParser (rung strategy, frozen-urn minting from
# the text's own structure), NOT a reuse of its in-text-marker regexes: SARIT
# addresses its texts through TEI apparatus (@xml:id / @n on lg-l-p, nested
# div paths, base-text <quote> blocks), never "// Abbr_N //" markers.
#
# The four fixtures span the census's dominant shapes:
#   astavakragita           IAST, lg/@xml:id verses ("verse_1.1"), the l-carried
#                           id quirk, out-of-order ids, prose speaker lines
#   samanyadusana           Devanagari, NO addressing at all (pure ordinals),
#                           <lb break="no"/> word joins, apparatus <note> drops
#   vatsyayana-nyayabhasya  IAST commentary, div/@xml:id path ladder
#                           ("nyāyabhāṣya__1.1.1"), base-text <quote n="NyāSū__…">
#   mahabharata-devanagari  Devanagari, parva/adhyāya div path, hyphenated
#                           self-contained lg ids ("adi-1-1-1"), <seg> padas
class SaritParserTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("sarit")

  ASTAVAKRA = File.join(FIXTURES, "astavakragita.xml")
  SAMANYA = File.join(FIXTURES, "samanyadusana.xml")
  NYAYA = File.join(FIXTURES, "vatsyayana-nyayabhasya-s1-2.xml")
  MBH = File.join(FIXTURES, "mahabharata-devanagari-adi1-svarga1.xml")

  def parser
    Nabu::Adapters::SaritParser.new
  end

  def parse(path, language:, urn: "urn:nabu:sarit:#{File.basename(path, '.xml')}")
    parser.parse(path, urn: urn, language: language)
  end

  # --- rung: lg/@xml:id verses (aṣṭāvakragītā, IAST) ------------------------

  def test_astavakra_lg_xml_id_verses
    doc = parse(ASTAVAKRA, language: "san-Latn")
    assert_equal "san-Latn", doc.language
    assert_equal 319, doc.size # 297 verse groups + 22 prose speaker lines

    v12 = find(doc, "1.2")
    assert_equal "xml-id", v12.annotations["addressing"]
    assert_equal "muktimicchasi cettāta viṣayānviṣavattyaja| " \
                 "kṣamārjavadayātoṣasatyaṃ pīyūṣavadbhaja||1|2||", v12.text
  end

  # The first lg carries its id on the FIRST <l>, not the lg
  # (<lg><l xml:id="verse_1.1">…): the exactly-one-addressed-line rule makes
  # the whole group one unit under that citation.
  def test_astavakra_l_carried_id_addresses_the_whole_group
    v11 = find(parse(ASTAVAKRA, language: "san-Latn"), "1.1")
    assert_equal "xml-id", v11.annotations["addressing"]
    assert_equal "kathaṃ jñānamavāpnoti kathaṃ muktirbhaviṣyati| " \
                 "vairāgyaṃ ca kathaṃ prāptametadbrūhi mama prabho||1|1||", v11.text
  end

  # Upstream encodes 1.13 BEFORE 1.12 (a real quirk): the citation is the id,
  # the sequence is document order — never resorted.
  def test_astavakra_out_of_order_ids_keep_document_order
    doc = parse(ASTAVAKRA, language: "san-Latn")
    citations = doc.map { |p| p.urn.split(":").last }
    assert_operator citations.index("1.13"), :<, citations.index("1.12"),
                    "document order must be preserved, not resorted by citation"
  end

  def test_astavakra_prose_speaker_lines_get_div_scoped_ordinals
    doc = parse(ASTAVAKRA, language: "san-Latn")
    p1 = find(doc, "1.p1")
    assert_equal "ordinal", p1.annotations["addressing"]
    assert_equal "|| atha śrīmadaṣṭāvakragītā||", p1.text
    assert_equal "janaka uvāca||1||", find(doc, "1.p2").text
    # Chapter 2's speaker line restarts the prose counter under div n="2".
    refute_nil find(doc, "2.p1")
  end

  # --- rung: no addressing at all → ordinals (sāmānyadūṣaṇa, Devanagari) ----

  def test_samanya_unaddressed_units_get_flat_ordinals
    doc = parse(SAMANYA, language: "san-Deva")
    assert_equal "san-Deva", doc.language
    # 5 verse groups + 29 prose paragraphs — 21 of the raw 50 <p> are the
    # apparatus notes' own paragraphs, dropped with their <note> subtrees.
    assert_equal 34, doc.size

    v1 = find(doc, "v1")
    assert_equal "ordinal", v1.annotations["addressing"]
    assert_equal "व्यापकं नित्यमेकं च सामान्यं यैः प्रकल्पितम् । मोहग्रन्थिच्छिदे तेषां तदभावः प्रसाध्यते ॥", v1.text
  end

  def test_samanya_lb_break_no_joins_the_split_word
    p1 = find(parse(SAMANYA, language: "san-Deva"), "p1")
    assert_includes p1.text, "भिन्नधीध्वनिप्रसवनिबन्धनमनुयायिरूपं",
                    '<lb break="no"/> continues the word — no space injected'
    refute_includes p1.text, "भिन्न धी", "the break=\"no\" join site must not carry a space"
    assert_includes p1.text, "सामान्यं न मान्यं मनीषिणामिति ?", "a plain <lb/> separates words"
  end

  def test_samanya_apparatus_notes_are_dropped
    doc = parse(SAMANYA, language: "san-Deva")
    doc.each do |passage|
      refute_includes passage.text, "°", "variant-apparatus <note> subtrees must be dropped"
    end
  end

  # The Devanagari search layer: text_normalized is the generic san fold of
  # the Deva→IAST TRANSCODE (canonical surface untouched), so an IAST query
  # lands on the Devanagari shelf exactly as on GRETIL.
  def test_samanya_devanagari_search_form_is_folded_iast
    v1 = find(parse(SAMANYA, language: "san-Deva"), "v1")
    assert_equal "vyapakam nityamekam ca samanyam yaih prakalpitam | " \
                 "mohagranthicchide tesam tadabhavah prasadhyate ||", v1.text_normalized
    assert_equal Nabu::Normalize.search_form(Nabu::Deva.to_iast(v1.text), language: "san-Deva"),
                 v1.text_normalized
  end

  # --- rung: div/@xml:id path + base-text quotes (nyāyabhāṣya, IAST) --------

  def test_nyaya_div_id_path_scopes_prose_ordinals
    doc = parse(NYAYA, language: "san-Latn")
    assert_equal 46, doc.size

    p1 = find(doc, "1.1.1.p1")
    assert_equal "ordinal", p1.annotations["addressing"]
    assert_equal "pramaṇato 'rthapratipattau pravṛttisāmarthyād arthavat pramāṇam/", p1.text
  end

  def test_nyaya_base_text_quote_inherits_the_sutra_citation
    doc = parse(NYAYA, language: "san-Latn")
    sutra = find(doc, "1.1.2")
    assert_equal "quote", sutra.annotations["addressing"]
    assert_equal "duḥkhajanmapravṛttidoṣamithyājñānām uttarottarāpāye " \
                 "tadanantarāpāyād apavargaḥ // 1.1.2 //", sutra.text
    refute_nil find(doc, "1.1.1"), "the first sūtra quote must mint 1.1.1"
  end

  def test_nyaya_inline_quotes_stay_in_the_running_text
    doc = parse(NYAYA, language: "san-Latn")
    carrier = doc.find { |p| p.text.include?("annaṃ vai prāṇinaḥ prāṇā") }
    refute_nil carrier, "an inline <quote> inside <p> is reading text, never a separate unit"
    assert_equal "ordinal", carrier.annotations["addressing"]
  end

  # --- rung: parva div path + self-contained lg ids (MBh, Devanagari) -------

  def test_mbh_lg_ids_are_self_contained_citations
    doc = parse(MBH, language: "san-Deva")
    assert_equal "san-Deva", doc.language
    assert_equal 337, doc.size # 327 verse groups + 10 prose units

    assert_equal "॥ श्रीवेदव्यासाय नमः ॥", find(doc, "1-1-0").text
    v = find(doc, "1-1-1")
    assert_equal "xml-id", v.annotations["addressing"]
    assert_equal "नारायणं नमस्कृत्य नरं चैव नरोत्तमम् । देवीं सरस्वतीं चैव(व्यासं) ततो जयमुदीरयेत् ॥", v.text
    assert_equal "narayanam namaskrtya naram caiva narottamam | " \
                 "devim sarasvatim caiva(vyasam) tato jayamudirayet ||", v.text_normalized
  end

  def test_mbh_seg_padas_join_with_single_spaces
    v = find(parse(MBH, language: "san-Deva"), "1-1-2")
    assert_equal "`नारायणं सुरगुरुं जगदेकनाथं' भक्तप्रियं सकललोकनमस्कृतं च । " \
                 "त्रैगुण्यवर्जितमजं विभुमाद्यमीशं वन्दे भवघ्नममरासुरसिद्धवन्द्यम्' ॥", v.text
  end

  def test_mbh_div_path_uses_n_and_falls_back_to_stripped_ids
    doc = parse(MBH, language: "san-Deva")
    # parva div n="01" → its śrī invocation is 01.p1; adhyāya div n="1" nests.
    assert_equal "श्रीः", find(doc, "01.p1").text
    assert_equal "(अनुक्रमणिकापर्व ॥ 1 ॥)", find(doc, "01.1.p1").text
    # svargārohaṇa adhyāya divs carry NO @n — the xml:id
    # "svargārohaṇaparva__adhyāya_001" strips to "001" as the path component.
    refute_nil find(doc, "18.001.p1")
    assert_equal "xml-id", find(doc, "18-1-1").annotations["addressing"]
  end

  # --- license gate (per-file, the availability header) ---------------------

  def test_license_is_read_per_file_and_carried_in_document_metadata
    assert_equal "CC BY-SA 3.0", parse(ASTAVAKRA, language: "san-Latn").metadata["license"]
    assert_equal "CC BY-SA 4.0", parse(SAMANYA, language: "san-Deva").metadata["license"]
    assert_equal "CC BY-SA 3.0", parse(MBH, language: "san-Deva").metadata["license"]
  end

  def test_mit_grant_is_recognized
    doctored = File.read(ASTAVAKRA).sub(
      "http://creativecommons.org/licenses/by-sa/3.0/", "https://opensource.org/licenses/MIT"
    )
    with_tempfile(doctored) do |path|
      assert_equal "MIT", parse(path, language: "san-Latn").metadata["license"]
    end
  end

  # The GRETIL-upgrade guarantee is per-file, not assumed: a grant outside
  # BY-SA/MIT (or none at all) quarantines the document loudly.
  def test_nc_grant_is_refused
    doctored = File.read(ASTAVAKRA).gsub("licenses/by-sa/3.0", "licenses/by-nc-sa/3.0")
                   .gsub("Attribution-ShareAlike", "Attribution-NonCommercial-ShareAlike")
    with_tempfile(doctored) do |path|
      error = assert_raises(Nabu::ParseError) { parse(path, language: "san-Latn") }
      assert_match(/license/i, error.message)
    end
  end

  def test_missing_grant_is_refused
    doctored = File.read(SAMANYA).sub(%r{<availability.*</availability>}m, "")
    with_tempfile(doctored) do |path|
      error = assert_raises(Nabu::ParseError) { parse(path, language: "san-Deva") }
      assert_match(/license/i, error.message)
    end
  end

  # --- honesty guards --------------------------------------------------------

  def test_language_mismatch_is_a_parse_error
    error = assert_raises(Nabu::ParseError) { parse(ASTAVAKRA, language: "san-Deva") }
    assert_match(/language mismatch/, error.message)
  end

  def test_no_body_is_a_parse_error
    with_tempfile("<TEI xmlns=\"http://www.tei-c.org/ns/1.0\"><teiHeader/></TEI>") do |path|
      assert_raises(Nabu::ParseError) { parse(path, language: "san-Latn") }
    end
  end

  def test_duplicate_citations_disambiguate_with_positional_suffixes
    xml = <<~XML
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><publicationStmt><availability>
          <p>This work is licensed under a Creative Commons Attribution-ShareAlike 4.0 licence.</p>
        </availability></publicationStmt></fileDesc></teiHeader>
        <text xml:lang="sa-Latn"><body>
          <lg xml:id="verse_1.1"><l>eka</l></lg>
          <lg xml:id="verse_1.1"><l>dvi</l></lg>
        </body></text>
      </TEI>
    XML
    with_tempfile(xml) do |path|
      doc = parse(path, language: "san-Latn")
      assert_equal(%w[1.1 1.1:b2], doc.map { |p| p.urn.delete_prefix("#{doc.urn}:") })
    end
  end

  def test_prose_license_wording_without_a_target_is_recognized
    # ratnakirti-nibandhavali carries its grant as bare prose (no ref target);
    # the same wording in a minimal rig must resolve.
    xml = <<~XML
      <TEI xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader><fileDesc><publicationStmt><availability>
          <p>This work is licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License.</p>
        </availability></publicationStmt></fileDesc></teiHeader>
        <text xml:lang="sa-Latn"><body><p>namaḥ</p></body></text>
      </TEI>
    XML
    with_tempfile(xml) do |path|
      assert_equal "CC BY-SA 3.0", parse(path, language: "san-Latn").metadata["license"]
    end
  end

  # --- urn stability + streaming proof --------------------------------------

  def test_urns_are_stable_across_two_parses
    [ASTAVAKRA, SAMANYA, NYAYA, MBH].each do |path|
      language = path.include?("devanagari") || path.include?("samanya") ? "san-Deva" : "san-Latn"
      first = parse(path, language: language).map(&:urn)
      second = parse(path, language: language).map(&:urn)
      assert_equal first, second, "#{File.basename(path)}: urns must be stable"
    end
  end

  def test_implementation_streams_and_never_builds_a_full_document_dom
    # SARIT's Mahābhārata is 38.6 MB — the >5 MB TEI rule is the reason this
    # family exists as a Reader state machine. Static proof, the EpidocParser
    # precedent: no full-document parse entry point in the implementation.
    source = File.read(File.expand_path("../../lib/nabu/adapters/sarit_parser.rb", __dir__))
    refute_match(/Nokogiri::XML(\.parse)?\s*\(/, source, "must not DOM-parse the document")
    refute_match(/Nokogiri::XML::Document/, source, "must not build a full XML document")
    assert_match(/Nokogiri::XML::Reader/, source, "must stream via Nokogiri::XML::Reader")
  end

  # --- citation-id prefix stripping (unit) -----------------------------------

  def test_strip_citation_id
    strip = Nabu::Adapters::SaritParser.method(:strip_citation_id)
    assert_equal "1.1", strip.call("verse_1.1")
    assert_equal "1.1.1", strip.call("nyāyabhāṣya__1.1.1")
    assert_equal "1.1.2", strip.call("NyāSū__1.1.2")
    assert_equal "1-1-1", strip.call("adi-1-1-1")
    assert_equal "1.1.001a", strip.call("Ah.1.1.001a")
    assert_equal "001", strip.call("svargārohaṇaparva__adhyāya_001")
    assert_equal "ādiparva", strip.call("ādiparva"), "an id with no numeric tail stays verbatim"
  end

  def test_normalize_language_maps_indic_codes_preserving_script
    normalize = Nabu::Adapters::SaritParser.method(:normalize_language)
    assert_equal "san-Deva", normalize.call("sa-Deva")
    assert_equal "san-Latn", normalize.call("sa-Latn")
    assert_equal "san-Latn", normalize.call("san-Latn")
    assert_equal "bra-Deva", normalize.call("braj-Deva")
    assert_equal "awa-Deva", normalize.call("avadhi-Deva")
    assert_nil normalize.call(nil)
  end

  private

  def find(doc, citation)
    doc.find { |p| p.urn.delete_prefix("#{doc.urn}:") == citation } or
      flunk "no passage with citation #{citation.inspect}; got #{doc.map(&:urn).first(8).inspect}…"
  end

  def with_tempfile(content)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "sarit-test.xml")
      File.write(path, content)
      yield path
    end
  end
end
