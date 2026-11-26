# frozen_string_literal: true

require "test_helper"

# The lane-tei parser family: the Perseus/Alpheios digitization of Lane's
# Arabic-English Lexicon (one letter-bucket file per call). Fixtures are
# real line-range trims of the upstream bucket files (README there).
class LaneTeiParserTest < Minitest::Test
  LAN = File.join(Nabu::TestSupport.fixtures("lane-lexicon"), "db", "lexica", "ara", "lan")
  DHAL = File.join(LAN, "u_0.xml")
  VARIANT = File.join(LAN, "uq2.xml")

  def parser = Nabu::Adapters::LaneTeiParser.new

  def dhal = @dhal ||= parser.entries(DHAL).to_h { |entry| [entry.entry_id, entry] }

  # -- identity -----------------------------------------------------------------

  def test_entries_keep_file_order_and_upstream_ids_with_anchored_bare_paragraphs
    ids = parser.entries(DHAL).map(&:entry_id)
    assert_equal 29, ids.size, "the letter article + roots ذمر (15 + 1 bare), ذمل (5), ذمى (7)"
    assert_equal %w[n13600 n14041 n14041.1 n14042 n14043], ids.first(5)
    assert_equal "n14067", ids.last
    assert_equal ids.uniq, ids
  end

  def test_an_id_prefix_qualifies_every_id_and_anchors_a_leading_bare_entry_on_the_prefix
    ids = parser.entries(VARIANT, id_prefix: "uq2").map(&:entry_id)
    assert_equal %w[uq2.1 uq2.n42477 uq2.n42478 uq2.n42479 uq2.n42507 uq2.n42508 uq2.n42508.1], ids
  end

  # The one text-less entryFree upstream (uq2.xml, root قو): the whole
  # article is its heading, "قو: see قوى" — the heading is the body.
  def test_an_empty_entry_reads_its_pointer_heading_as_the_body
    entry = parser.entries(VARIANT, id_prefix: "uq2").last
    assert_equal ["uq2.n42508.1", "قو", "قو: see قوى"], [entry.entry_id, entry.headword, entry.body]
    assert_equal([%w[see قوى]], entry.crossrefs.map { |c| [c.kind, c.target] })
  end

  def test_a_leading_bare_entry_without_a_prefix_anchors_on_the_file_stem
    assert_equal "uq2.1", parser.entries(VARIANT).first.entry_id
  end

  def test_identity_is_stable_across_two_parses
    first = parser.entries(DHAL).map { |e| [e.entry_id, Nabu::Store::ContentHash.dictionary_entry(e)] }
    second = parser.entries(DHAL).map { |e| [e.entry_id, Nabu::Store::ContentHash.dictionary_entry(e)] }
    assert_equal first, second
  end

  # -- headword, key, fold ------------------------------------------------------

  def test_an_id_entry_takes_its_headword_from_the_first_form_orth_and_folds_its_key
    entry = dhal.fetch("n14041")
    assert_equal "ذَمَرَ", entry.headword
    assert_equal "ذَمَرَ", entry.key_raw
    assert_equal "ara", entry.language
    assert_equal Nabu::Normalize.search_form("ذَمَرَ", language: "ara"), entry.headword_folded
  end

  def test_a_bare_paragraph_takes_its_orth_as_headword_and_key
    entry = dhal.fetch("n14041.1")
    assert_equal "ذَمَّرَ", entry.headword
    assert_equal "ذَمَّرَ", entry.key_raw
    assert_equal Nabu::Normalize.search_form("ذَمَّرَ", language: "ara"), entry.headword_folded
  end

  def test_a_leading_bare_entry_carries_its_orth_and_root_heading
    entry = parser.entries(VARIANT).first
    assert_equal "ق", entry.headword, "uq2's leading bare entry carries an orth of the letter itself"
    assert_equal({ "root" => "ق" }, entry.annotations.slice("root"))
  end

  # u_Y0.xml's "See Supplement" stubs (roots of ي that Lane's notes never
  # reached): no <form>, no orth — the root heading's Arabic is the only
  # lookup key the paragraph has; the heading's "&c." stays out of it.
  def test_a_bare_entry_without_any_orth_falls_back_to_its_root_heading
    entries = parser.entries(File.join(LAN, "u_Y0.xml"))
    assert_equal %w[n42419 n42419.1], entries.map(&:entry_id)
    stub = entries.last
    assert_equal %w[يتم يتم], [stub.headword, stub.key_raw]
    assert_equal "يتم", stub.annotations["root"]
    assert_equal "See Supplement", stub.body
  end

  # -- mined axes: root, paragraph, print page ------------------------------------

  def test_root_and_paragraph_ride_the_annotations
    assert_equal({ "root" => "ذمر", "paragraph" => "1" }, dhal.fetch("n14041").annotations.slice("root", "paragraph"))
    assert_equal({ "root" => "ذمر", "paragraph" => "2" }, dhal.fetch("n14041.1").annotations.slice("root", "paragraph"))
    assert_equal "ذمى", dhal.fetch("n14067").annotations["root"]
    refute dhal.fetch("n13600").annotations.key?("root"), "the letter article sits outside any root"
    refute dhal.fetch("n13600").annotations.key?("paragraph"), "'alphabetical letter' is no paragraph number"
  end

  def test_print_pages_follow_the_pb_milestones
    refute dhal.fetch("n14041").annotations.key?("page"), "before the file's first <pb> the page is unknown"
    assert_equal({ "page_end" => "978" }, dhal.fetch("n14042").annotations.slice("page", "page_end"),
                 "the entry runs onto p. 978 (its own closing <pb>)")
    assert_equal({ "page" => "978" }, dhal.fetch("n14043").annotations.slice("page", "page_end"))
    assert_equal({ "page" => "978", "page_end" => "979" }, dhal.fetch("n14062").annotations.slice("page", "page_end"))
    assert_equal({ "page" => "979" }, dhal.fetch("n14063").annotations.slice("page", "page_end"))
  end

  def test_extra_annotations_merge_into_every_entry
    entries = parser.entries(VARIANT, id_prefix: "uq2", annotations: { "section" => "supplement" })
    assert(entries.all? { |entry| entry.annotations["section"] == "supplement" })
  end

  # -- gloss and body ---------------------------------------------------------------

  def test_gloss_is_the_first_sense_italic_run_joined_across_short_parentheticals
    assert_equal "It moved.", dhal.fetch("n14061").gloss
    assert_equal "He (a lion) roared.", dhal.fetch("n14041").gloss
    assert_equal "He left him ill, or sick", dhal.fetch("n14062").gloss
  end

  def test_a_pure_pointer_paragraph_has_no_gloss
    assert_nil dhal.fetch("n14041.1").gloss
  end

  def test_body_is_the_whole_entry_with_sense_milestones_on_new_lines
    body = dhal.fetch("n14041").body
    assert body.start_with?("1 ذَمَرَ, (S,) inf. n. ذَمْرٌ"), body[0, 60]
    assert_includes body, "\n-A2- ذَمَرَهُ, aor."
    assert_includes body, "He excited, incited, urged,"
  end

  def test_every_text_field_is_nfc
    parser.entries(DHAL).each do |entry|
      [entry.headword, entry.headword_folded, entry.body, entry.gloss].compact.each do |text|
        assert text.unicode_normalized?(:nfc), "#{entry.entry_id}: #{text[0, 40]}"
      end
    end
  end

  # -- cross-references -----------------------------------------------------------------

  def test_a_numbered_paragraph_pointer_resolves_within_its_root
    crossref = dhal.fetch("n14041.1").crossrefs.find { |c| c.label == "see 1" }
    refute_nil crossref, dhal.fetch("n14041.1").crossrefs.inspect
    assert_equal ["see", "1", "n14041", nil],
                 [crossref.kind, crossref.target, crossref.target_id, crossref.target_folded]
    assert_equal "n14061", dhal.fetch("n14065").crossrefs.find { |c| c.label == "see 1" }&.target_id
  end

  def test_a_see_arabic_pointer_resolves_to_the_exact_vocalized_headword_in_the_file
    crossref = dhal.fetch("n14050").crossrefs.find { |c| c.target == "ذِمْرٌ" }
    refute_nil crossref, dhal.fetch("n14050").crossrefs.inspect
    assert_equal ["see", "n14044", nil], [crossref.kind, crossref.target_id, crossref.target_folded]
    assert_equal "n14055", dhal.fetch("n14041").crossrefs.find { |c| c.target == "مُذَمِّرٌ" }&.target_id,
                 "a capitalized '[See' points too"
  end

  def test_an_unheld_see_target_falls_back_to_the_folded_headword
    crossref = parser.entries(VARIANT, id_prefix: "uq2").find { |e| e.entry_id == "uq2.n42477" }.crossrefs.first
    assert_equal ["see", "مَعَازِفُ", nil], [crossref.kind, crossref.target, crossref.target_id]
    assert_equal Nabu::Normalize.search_form("مَعَازِفُ", language: "ara"), crossref.target_folded
  end

  def test_prose_pointers_mint_nothing
    assert_empty dhal.fetch("n14045").crossrefs, "'see the next preceding paragraph' has no machine target"
  end

  # -- damage -----------------------------------------------------------------------------

  def test_malformed_xml_raises_a_parse_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "ux0.xml")
      File.write(path, "<TEI.2><text><body><div1><entryFree id=\"n1\" key=\"x\">")
      assert_raises(Nabu::ParseError) { parser.entries(path) }
    end
  end
end
