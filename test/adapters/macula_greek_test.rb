# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# MaculaGreek adapter tests: Clear-Bible/macula-greek's word-level TSV of
# the SBLGNT (SBLGNT/tsv/macula-greek-SBLGNT.tsv, one row per word, 27
# columns), held as its own annotation edition beside the sblgnt text.
# The fixture is a real trim of the pinned file — Mark 1:1-3, John 1:1-2
# + 21:23, 3 John whole (315 word rows, real header) — plus the TEI
# 3 John as the pinned rejected-grain specimen. No network: fetch runs
# against a WebMock stub of the pinned raw URL.
class MaculaGreekTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("macula-greek")
  TSV = File.join(FIXTURES, "SBLGNT", "tsv", "macula-greek-SBLGNT.tsv")
  SBLGNT_3JOHN = File.join(Nabu::TestSupport.fixtures("sblgnt"), "data", "sblgnt", "text", "3John.txt")

  BOOK_URNS = %w[urn:nabu:macula-greek:3john urn:nabu:macula-greek:john urn:nabu:macula-greek:mark].freeze

  def conformance_adapter
    Nabu::Adapters::MaculaGreek.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "macula-greek"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_carries_the_grant_and_the_marble_caveat
    manifest = Nabu::Adapters::MaculaGreek.manifest
    assert_equal "macula-greek", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/Clear-Bible/macula-greek", manifest.upstream_url
    assert_equal "macula-tsv", manifest.parser_family
    assert_match(/\ACC BY 4\.0/, manifest.license)
    assert_includes manifest.license, "MACULA Greek Linguistic Datasets, available at " \
                                      "https://github.com/Clear-Bible/macula-greek/"
    assert_includes manifest.license, "(`@ln`, `@domain`) Used with permission.",
                    "the column-level MARBLE caveat rides the license string verbatim"
    assert_match(/not ingested/, manifest.license)
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_book_present_sorted_by_urn
    refs = Nabu::Adapters::MaculaGreek.new.discover(FIXTURES).to_a
    assert_equal BOOK_URNS, refs.map(&:id)
    assert_equal(%w[3JN JHN MRK], refs.map { |r| r.metadata["book"] })
    assert(refs.all? { |r| r.source_id == "macula-greek" && r.path == File.expand_path(TSV) })
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::MaculaGreek.new.discover(dir).to_a
      assert_equal Nabu::Adapter::DiscoverySkips.new, Nabu::Adapters::MaculaGreek.new.discovery_skips(dir)
    end
  end

  # Upstream's other delivery grains (lowfat / nodes / TEI XML, and the
  # Nestle1904 tree) are out of scope by rule: the pinned TEI specimen is
  # counted skipped-by-rule with its note, never dropped silently.
  def test_rejected_xml_grain_counts_as_skipped_by_rule
    skips = Nabu::Adapters::MaculaGreek.new.discovery_skips(FIXTURES)
    assert_equal 1, skips.skipped_by_rule
    assert_equal 0, skips.unrecognized
    assert_equal 1, skips.notes.size
    assert_match(/XML grain/, skips.notes.first)
    assert_match(%r{SBLGNT/tei/25-3john\.xml}, skips.notes.first)
  end

  def test_unknown_book_code_is_unrecognized_not_silent
    with_mutated_tsv(->(cols) { cols[1] = cols[1].sub("MRK", "XYZ") if cols[1].start_with?("MRK") }) do |dir|
      adapter = Nabu::Adapters::MaculaGreek.new
      refute_includes adapter.discover(dir).map(&:id), "urn:nabu:macula-greek:mark"
      skips = adapter.discovery_skips(dir)
      assert_equal 1, skips.unrecognized
      assert(skips.notes.any? { |n| n.include?("XYZ") })
    end
  end

  # --- parse: text reassembly ---------------------------------------------------

  def test_mark_reassembles_with_trailing_punctuation
    document = parse("urn:nabu:macula-greek:mark")
    assert_equal "grc", document.language
    assert_equal "Mark (MACULA Greek)", document.title
    assert_equal(%w[1.1 1.2 1.3], document.map { |p| p.urn.split(":").last })
    assert_equal "Ἀρχὴ τοῦ εὐαγγελίου Ἰησοῦ χριστοῦ.", document.first.text
    assert_equal "MRK 1:1", document.first.annotations["citation"]
  end

  # 3 John is whole in both fixtures: every verse reassembled from the word
  # rows equals the SBLGNT verse line modulo the two DECLARED divergences —
  # SBLGNT's text-critical sigla (absent from MACULA's word rows) and the
  # elision mark's codepoint (MACULA ’ U+2019 where SBLGNT has ʼ U+02BC).
  def test_3john_reassembles_to_the_sblgnt_verse_text
    document = parse("urn:nabu:macula-greek:3john")
    sblgnt = File.readlines(SBLGNT_3JOHN, chomp: true).drop(1).to_h do |line|
      ref, text = line.split("\t", 2)
      [ref.split.last.tr(":", "."), text.strip]
    end
    assert_equal 15, document.size
    document.each do |passage|
      key = passage.urn.split(":").last
      expected = Nabu::Normalize.nfc(sblgnt.fetch(key).gsub(/[⸀⸁⸂⸃⸄⸅]/, "").squeeze(" "))
      assert_equal expected, passage.text.tr("’", "ʼ"), "3 John #{key}"
    end
    assert_equal "Ὁ πρεσβύτερος Γαΐῳ τῷ ἀγαπητῷ, ὃν ἐγὼ ἀγαπῶ ἐν ἀληθείᾳ.",
                 document.find { |p| p.urn.end_with?(":1.1") }.text
  end

  # Upstream's own quirk, kept verbatim (canonical means canonical): the
  # word text "ἀλλ’·" carries its elision mark AND the raised dot inside
  # the text column.
  def test_upstream_text_column_quirk_rides_verbatim
    verse = parse("urn:nabu:macula-greek:john").find { |p| p.urn.end_with?(":21.23") }
    assert_includes verse.text, "ἀλλ’· Ἐὰν"
  end

  def test_every_word_row_becomes_one_token
    adapter = Nabu::Adapters::MaculaGreek.new
    tokens = adapter.discover(FIXTURES).sum do |ref|
      adapter.parse(ref).sum { |p| p.annotations.fetch("tokens").size }
    end
    assert_equal File.readlines(TSV).size - 1, tokens
  end

  # --- parse: the token layers ----------------------------------------------------

  def test_token_carries_morphology_glosses_and_ids
    token = parse("urn:nabu:macula-greek:john").first.annotations.fetch("tokens")[2]
    assert_equal({ "id" => "n43001001003", "form" => "ἦν", "lemma" => "εἰμί", "normalized" => "ἦν",
                   "strong" => "2258", "morph" => "V-IAI-3S", "class" => "verb", "role" => "vc",
                   "person" => "third", "number" => "singular", "tense" => "imperfect",
                   "voice" => "active", "mood" => "indicative",
                   "english" => "was", "mandarin" => "有", "gloss" => "was" }, token)
  end

  def test_trailing_punctuation_rides_the_token
    tokens = parse("urn:nabu:macula-greek:mark").first.annotations.fetch("tokens")
    assert_equal ".", tokens.last["trailer"]
    refute tokens.first.key?("trailer"), "a plain space separator is not stored"
  end

  def test_frames_and_referents_ride_verbatim
    tokens = parse("urn:nabu:macula-greek:3john").flat_map { |p| p.annotations.fetch("tokens") }
    assert(tokens.any? { |t| t["frame"].to_s.match?(/\AA0:n64\d+/) }, "semantic frames kept")
    assert(tokens.any? { |t| t["referent"].to_s.match?(/\An64\d+/) }, "participant referents kept")
  end

  def test_english_gloss_reaches_the_token_gloss_registry
    token = parse("urn:nabu:macula-greek:mark").first.annotations.fetch("tokens").first
    assert_equal "beginning", Nabu::Query::TokenGlosses.gloss(token, source: "macula-greek")
  end

  # --- the MARBLE exclusion rule ------------------------------------------------

  # UBS MARBLE's Louw-Nida columns (domain, ln) are "Used with permission"
  # — a grant to MACULA, not a CC BY grant to us — so they are excluded AT
  # PARSE. The public fixture carries the columns' header with blanked
  # cells; here they are repopulated so the exclusion is proven on
  # non-empty values.
  def test_marble_columns_never_reach_a_token
    fill = lambda do |cols|
      cols[22] = "033005"
      cols[23] = "33.38"
    end
    with_mutated_tsv(fill) do |dir|
      adapter = Nabu::Adapters::MaculaGreek.new
      tokens = adapter.discover(dir).flat_map { |ref| adapter.parse(ref).flat_map { |p| p.annotations["tokens"] } }
      refute_empty tokens
      assert(tokens.none? { |t| t.key?("domain") || t.key?("ln") })
      assert(tokens.none? { |t| t.value?("033005") || t.value?("33.38") })
    end
  end

  def test_header_drift_is_a_parse_error
    with_mutated_header(->(header) { header.sub("\tafter\t", "\tpunct\t") }) do |dir|
      adapter = Nabu::Adapters::MaculaGreek.new
      ref = adapter.discover(dir).first
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/after/, error.message)
    end
  end

  # --- store: idempotent double-load ----------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = Nabu::Store::Source.create(slug: "macula-greek", name: "MACULA Greek",
                                        adapter_class: "Nabu::Adapters::MaculaGreek",
                                        license_class: "attribution")
    adapter = Nabu::Adapters::MaculaGreek.new
    first = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 3, first.added
    assert_equal 0, first.errored
    assert_equal 21, catalog[:passages].count

    second = Nabu::Store::Loader.new(db: catalog, source: source).load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 3, second.skipped, "a byte-identical reload skips every document"
    assert_equal 21, catalog[:passages].count
    assert_equal [1], catalog[:passages].distinct.select_map(:revision)
  end

  # --- fetch (WebMock only) -----------------------------------------------------

  def test_fetch_lands_the_tsv_at_upstreams_path_and_verifies_the_pin
    body = File.binread(TSV)
    stub_request(:get, Nabu::Adapters::MaculaGreek::TSV_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |dir|
      report = Nabu::Adapters::MaculaGreek.new(tsv_sha256: Digest::SHA256.hexdigest(body)).fetch(dir)
      assert_equal body, File.binread(File.join(dir, "SBLGNT", "tsv", "macula-greek-SBLGNT.tsv"))
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal BOOK_URNS, Nabu::Adapters::MaculaGreek.new.discover(dir).map(&:id)
    end
  end

  def test_fetch_aborts_on_sha_drift_with_the_tree_untouched
    stub_request(:get, Nabu::Adapters::MaculaGreek::TSV_URL).to_return(status: 200, body: File.binread(TSV))
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::MaculaGreek.new(tsv_sha256: "0" * 64).fetch(dir) }
      assert_match(/re-pin/, error.message)
      refute File.exist?(File.join(dir, "SBLGNT", "tsv", "macula-greek-SBLGNT.tsv"))
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, Nabu::Adapters::MaculaGreek::TSV_URL).to_return(status: 404)
    Dir.mktmpdir do |dir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::MaculaGreek.new.fetch(dir) }
    end
  end

  def test_tsv_url_is_commit_pinned
    assert_match(%r{\Ahttps://raw\.githubusercontent\.com/Clear-Bible/macula-greek/\h{40}/SBLGNT/tsv/macula-greek-SBLGNT\.tsv\z},
                 Nabu::Adapters::MaculaGreek::TSV_URL)
    targets = Nabu::Adapters::MaculaGreek.http_probe_targets
    assert_equal [Nabu::Adapters::MaculaGreek::TSV_URL], targets.map(&:zip_url)
    assert_equal ["SBLGNT/tsv"], targets.map(&:state_subdir)
  end

  # --- registry -----------------------------------------------------------------

  def test_registry_row_exists_wired_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources", __dir__))
    entry = registry["macula-greek"]
    refute_nil entry, "config/sources.yml must register macula-greek"
    assert_equal Nabu::Adapters::MaculaGreek, entry.adapter_class
    assert entry.wired, "wired after the verified first sync"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::MaculaGreek.manifest, entry.manifest
  end

  private

  def parse(urn)
    adapter = Nabu::Adapters::MaculaGreek.new
    adapter.parse(adapter.discover(FIXTURES).find { |r| r.id == urn })
  end

  # A tmp workdir whose TSV is the fixture with +mutate+ applied to every
  # data row's column array (header untouched).
  def with_mutated_tsv(mutate, &)
    header, *rows = File.readlines(TSV, chomp: true)
    rows = rows.map do |row|
      cols = row.split("\t", -1)
      mutate.call(cols)
      cols.join("\t")
    end
    with_tsv_lines([header, *rows], &)
  end

  def with_mutated_header(mutate, &)
    header, *rows = File.readlines(TSV, chomp: true)
    with_tsv_lines([mutate.call(header), *rows], &)
  end

  def with_tsv_lines(lines)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "SBLGNT", "tsv", "macula-greek-SBLGNT.tsv")
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, "#{lines.join("\n")}\n")
      yield dir
    end
  end
end
