# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "tmpdir"
require "zlib"

# Nabu::Adapters::WilkensOui — Wilkens's Handwörterbuch des Altuigurischen
# (Göttingen 2021, CC BY-SA 4.0) as a dictionary shelf, segmented from the
# PDF's positioned text layer. Dictionary-shaped, so it mirrors the
# conformance checks for the dictionary shape (the Shuowen mold): manifest,
# discover→parse round-trip, id uniqueness/stability, NFC, license class,
# the DictionaryLoader contract, plus the entry pins.
#
# The "book" the tests parse is assembled from the RECORDED stext of the
# two fixture trims (README beside them), in PDF page order: the rejected
# matter grain (PDF pp. 3 and 15 — the license page and the Symbole page),
# body folios 1, 44, 45, then folio 169 (the empty-headword residue
# specimen), folios 182 and 441. The mutool seams return those recorded
# pages for any requested range, so chunking is exercised for real.
class WilkensOuiAdapterTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wilkens-oui")
  Adapter = Nabu::Adapters::WilkensOui

  def self.recorded_pages(name)
    xml = Zlib.gunzip(File.binread(File.join(FIXTURES, name)))
    Nokogiri::XML(xml).xpath("//page").map(&:to_xml)
  end

  SAMPLE = recorded_pages("wilkens-sample.stext.xml.gz")
  GRAINS = recorded_pages("wilkens-grains.stext.xml.gz")
  BOOK = [GRAINS[0], GRAINS[1], SAMPLE[0], SAMPLE[1], SAMPLE[2], GRAINS[2], SAMPLE[3], SAMPLE[4]].freeze

  def fake_extract
    lambda do |_path, pages|
      first, last = pages.split("-").map { Integer(_1, 10) }
      "<document>#{BOOK[(first - 1)..(last - 1)].join}</document>"
    end
  end

  def adapter(chunk_pages: Adapter::CHUNK_PAGES)
    Adapter.new(extract: fake_extract, page_count: ->(_path) { BOOK.size }, chunk_pages: chunk_pages)
  end

  # A workdir holding the real sample bytes under the upstream filename.
  def with_workdir
    Dir.mktmpdir("nabu-wilkens") do |dir|
      FileUtils.cp(File.join(FIXTURES, "wilkens-sample.pdf"), File.join(dir, Adapter::PDF_NAME))
      yield dir
    end
  end

  def parsed(subject = adapter)
    with_workdir { |dir| subject.parse(subject.discover(dir).first) }
  end

  def document = @document ||= parsed

  def entry(id) = document.find { |e| e.entry_id == id } || flunk("no entry #{id.inspect}")

  # -- manifest / discovery -------------------------------------------------

  def test_manifest_and_content_kind
    manifest = Adapter.manifest
    assert_equal "wilkens-oui", manifest.id
    assert_equal "attribution", manifest.license_class, "CC BY-SA 4.0 → attribution with the share-alike rider"
    assert_match(/CC BY-SA 4\.0/, manifest.license)
    assert_match(/Share-alike rider/, manifest.license)
    assert_match(/Namensnennung - Weitergabe unter gleichen Bedingungen 4\.0/, manifest.license)
    assert_match(%r{10\.17875/gup2021-1590}, manifest.credit)
    assert_equal "wilkens-stext", manifest.parser_family
    assert_equal :dictionary, Adapter.content_kind
    assert_empty Adapter.materialized_paths, "the fetch lands upstream's PDF only"
  end

  def test_discover_yields_the_one_pdf
    with_workdir do |dir|
      refs = adapter.discover(dir).to_a
      assert_equal ["wilkens-oui:Wilkens_handwoerterbuch.pdf"], refs.map(&:id)
      assert_equal "wilkens-oui", refs.first.source_id
    end
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_an_oui_dictionary_document
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wilkens-oui", document.slug
    assert_equal "oui", document.language
  end

  # -- grains ---------------------------------------------------------------

  # The rejected grain: pages without an arabic folio (front matter, back
  # cover) never reach the segmenter — counted with their note.
  def test_matter_pages_are_skipped_by_rule_and_counted
    refute(document.any? { |e| e.body.include?("Namensnennung") || e.body.include?("fehlerhafte Lesung oder") })
    skips = adapter.tap { |a| parsed(a) }.discovery_skips("unused")
    notes = skips.notes.join("\n")
    assert_match(%r{2 PDF page\(s\) without an arabic folio skipped — the front/back matter grain \(pp\. 1–2\)}, notes)
  end

  # A record the segmenter closed with an empty headword cannot key an
  # entry: skipped by rule, named in the notes (folio 169 — the Hebrew
  # etymon of bidilhim wrapped onto an indent line).
  def test_an_empty_headword_record_is_skipped_by_rule_with_its_note
    subject = adapter
    parsed(subject)
    skips = subject.discovery_skips("unused")
    assert_equal 1, skips.skipped_by_rule
    assert skips.clean?
    assert_match(/record skipped by rule \(empty headword, p\. 169\): .*n\. loc\. \(= Bethlehem\)/,
                 skips.notes.join("\n"))
    assert(document.none? { |e| e.headword.strip.empty? })
  end

  def test_discovery_skips_without_a_parse_says_so
    skips = adapter.discovery_skips("unused")
    assert_equal 0, skips.skipped_by_rule
    assert_match(/rides the parse/, skips.notes.join)
  end

  def test_chunking_never_splits_a_record
    small = with_workdir { |dir| adapter(chunk_pages: 2).then { |a| a.parse(a.discover(dir).first) } }
    assert_equal document.map(&:entry_id), small.map(&:entry_id)
    assert_equal document.to_a, small.to_a
  end

  # -- entries --------------------------------------------------------------

  def test_homonyms_key_by_their_printed_number
    one = entry("^1a")
    two = entry("^2a")
    assert_equal %w[a a], [one.headword, two.headword]
    assert_equal [1, 2], [one.annotations["homonym"], two.annotations["homonym"]]
    assert_equal "a", one.headword_folded
    assert_equal "Vokativpartikel (enkl.), Anruf", one.gloss, "the first German sense"
    assert_equal "Vokativpartikel (enkl.), Anruf; Wehruf", one.annotations["german"]
    assert one.annotations["turkish"].start_with?("(önceki kelimeyle birleşen) seslenme edatı")
    assert_equal "glossed", one.annotations["shape"]
  end

  def test_a_sub_entry_is_its_own_record_pointing_at_its_main_entry
    sub = entry("^3a::a bašlap v tägi")
    assert_equal "a bašlap v tägi", sub.headword
    assert_equal "von a bis v", sub.gloss
    assert_equal({ "entry_kind" => "sub", "parent" => "^3a", "page" => 1, "column" => "left",
                   "german" => "von a bis v", "turkish" => "a’dan v’ye kadar", "shape" => "glossed" },
                 sub.annotations)
    parent = sub.crossrefs.find { |x| x.kind == "subentry-of" }
    assert_equal ["^3a", "a"], [parent.target_id, parent.target]
    assert_nil parent.target_folded
  end

  def test_a_cross_reference_points_by_folded_headword
    xref = entry("^4a::a ušik")
    assert_equal "cross-reference", xref.annotations["shape"]
    assert_equal "a užik", xref.annotations["cross_reference"]
    assert_nil xref.gloss
    see = xref.crossrefs.find { |x| x.kind == "see" }
    assert_equal ["a užik", "a uzik", "→ a užik"], [see.target, see.target_folded, see.label]
  end

  def test_a_rejected_reading_is_flagged_and_points_as_a_false_reading
    rejected = entry("^1abaga")
    assert rejected.annotations["rejected_reading"]
    pointer = rejected.crossrefs.find { |x| x.kind == "false-reading" }
    assert_equal ["^1apaga", "apaga", "† → ^1apaga"], [pointer.target, pointer.target_folded, pointer.label],
                 "an unheld numbered target falls back to the folded headword"
  end

  def test_a_cross_reference_chain_mints_one_pointer_per_link
    chain = entry("abıpıraay")
    assert_equal([%w[false-reading abipiraay], %w[see abipiray]],
                 chain.crossrefs.map { |x| [x.kind, x.target] })
  end

  def test_a_numbered_target_held_by_the_book_is_id_keyed
    pointers = document.flat_map(&:crossrefs).select { |x| x.target_id && x.kind != "subentry-of" }
    refute_empty pointers, "the fixture holds a ^n pointer to a main entry it also holds"
    ids = document.map(&:entry_id)
    assert(pointers.all? { |x| ids.include?(x.target_id) })
  end

  def test_the_printed_page_is_the_citation_grain
    amramak = entry("amramak")
    assert_equal 44, amramak.annotations["page"]
    assert_match(/\np\. 44, (left|right) column\z/, amramak.body)
    assert amramak.body.start_with?("amramak ")
    assert_includes amramak.body, "\nGerman: "
    assert_includes amramak.body, "\nTurkish: "
  end

  def test_verbs_keep_their_hyphen_in_the_headword_but_not_the_fold
    verb = entry("amran-")
    assert_equal "amran", verb.headword_folded
    assert_includes verb.annotations["labels"], "verb"
  end

  # The book's tradition and script marks, mapped per its own Abkürzungen
  # (PDF pp. 13–14) into the entry-facet seam: (m) manichäisch, (c)
  # christlich → tradition; (br) Brāhmī, (r) Runenschrift, (tib)
  # tibetische Schrift, (p) ʾPhags pa (Schrift) → script.
  def test_tradition_and_script_marks_ride_as_entry_facets
    assert_equal ["Manichaean"], entry("amraklug").annotations["tradition"]
    assert_equal ["Manichaean"], entry("amranmak::amranmak bilig").annotations["tradition"]
    assert_equal ["Christian"], entry("bnaya d-bnay").annotations["tradition"]
    assert_equal ["Brāhmī"], entry("amṛta").annotations["script"]
    assert_equal ["runic"], entry("(a)bınču").annotations["script"]
    plain = entry("amraksızın")
    assert_includes plain.annotations["labels"], "adv."
    refute plain.annotations.key?("tradition"), "a grammar label is no tradition mark"
    refute plain.annotations.key?("script")
  end

  def test_the_mark_table_is_the_books_own
    assert_equal({ "m" => %w[tradition Manichaean], "c" => %w[tradition Christian],
                   "br" => %w[script Brāhmī], "r" => %w[script runic],
                   "tib" => %w[script Tibetan], "p" => %w[script ʾPhags-pa] },
                 Adapter::MARK_FACETS.transform_values(&:to_a))
  end

  # The census counts every mapped mark and every label left unmapped.
  def test_the_census_counts_mapped_marks_and_unmapped_labels
    subject = adapter
    parsed(subject)
    notes = subject.discovery_skips("unused").notes.join("\n")
    assert_match(/entry facets: script Brāhmī 2, runic 5; tradition Christian 1, Manichaean 8/, notes)
    assert_match(%r{labels left unmapped \(grammar/name labels, no facet\): \d+ across \d+ kinds}, notes)
  end

  def test_variants_fold_on_their_first_form
    assert_equal "amranmaklıg", entry("amranmaklıg ~ amranmak(lıg)").headword_folded
  end

  def test_lost_chinese_characters_are_carried_and_counted
    lost = document.select { |e| e.annotations.key?("text_layer_loss") }
    refute_empty lost
    lost.each do |e|
      assert_includes e.body, "�", "U+FFFD served as upstream's text layer yields it"
      assert_equal e.body.lines.first.count("�"), e.annotations["text_layer_loss"]
    end
  end

  def test_entry_ids_are_unique_stable_and_nfc
    ids = document.map(&:entry_id)
    assert_equal ids.uniq, ids
    assert_equal ids, parsed(adapter).map(&:entry_id)
    document.each do |e|
      [e.headword, e.headword_folded, e.body, e.gloss].compact.each { |s| assert s.unicode_normalized?(:nfc) }
    end
  end

  def test_loads_idempotently_and_resolves_every_parent_pointer
    db = store_test_db
    source = Nabu::Store::Source.create(slug: "wilkens-oui", name: "Wilkens", license_class: "attribution",
                                        adapter_class: "Nabu::Adapters::WilkensOui")
    with_workdir do |dir|
      2.times do
        report = Nabu::Store::DictionaryLoader.new(db: db, source: source).load_from(adapter, workdir: dir)
        assert_equal 0, report.errored
        assert_equal document.size, db[:dictionary_entries].count
      end
    end
    parents = db[:dictionary_crossrefs].where(kind: "subentry-of")
    refute_empty parents.all
    assert_equal 0, parents.where(to_entry_id: nil).count, "every sub-entry resolves to its main entry"
    assert_includes db[:dictionary_entries].select_map(:urn), "urn:nabu:dict:wilkens-oui:^3a::a bašlap v tägi"
  ensure
    db&.disconnect
  end

  # -- fetch ----------------------------------------------------------------

  def test_fetch_lands_the_pdf_and_verifies_the_pin
    body = File.binread(File.join(FIXTURES, "wilkens-sample.pdf"))
    stub_request(:get, Adapter::PDF_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = Adapter.new(pdf_sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, Adapter::PDF_NAME))
      assert_equal Digest::SHA256.hexdigest(body), report.sha
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    body = File.binread(File.join(FIXTURES, "wilkens-sample.pdf"))
    stub_request(:get, Adapter::PDF_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Adapter.new.fetch(dir) }
      assert_match(/drifted.*re-pin/, error.message)
      refute File.exist?(File.join(dir, Adapter::PDF_NAME))
    end
  end

  def test_the_pin_is_the_fixture_readmes
    readme = File.read(File.join(FIXTURES, "README.md"))
    assert_includes readme, Adapter::PDF_SHA256
  end

  # -- registry -------------------------------------------------------------

  def test_registry_row_exists_wired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wilkens-oui"]
    refute_nil entry, "config/sources.yml must register wilkens-oui"
    assert_equal Adapter, entry.adapter_class
    assert entry.wired, "wired flipped after the first real sync verified 49,619 entries (2026-10-22)"
    assert_equal "manual", entry.sync_policy
  end

  # -- live mutool (present on the owner's box) ----------------------------

  def test_real_mutool_extraction_agrees_with_the_recorded_layer
    skip "mutool not on PATH — the recorded-extraction tests carry the suite" unless mutool_available?

    with_workdir do |dir|
      live = Adapter.new
      sample = live.parse(live.discover(dir).first)
      recorded_sample = Adapter.new(extract: ->(_path, _pages) { "<document>#{SAMPLE.join}</document>" },
                                    page_count: ->(_path) { SAMPLE.size })
      assert_equal recorded_sample.parse(recorded_sample.discover(dir).first).to_a, sample.to_a
    end
  end

  private

  def mutool_available?
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? { |d| File.executable?(File.join(d, "mutool")) }
  end
end
