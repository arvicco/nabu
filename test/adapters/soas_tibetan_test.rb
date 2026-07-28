# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "digest"

# Nabu::Adapters::SoasTibetan (P48-3): the SOAS "Tibetan in Digital
# Communication" gold POS corpus of Classical Tibetan (Hill, Garrett et al.;
# Zenodo record 574878, DOI 10.5281/zenodo.574878, CC BY 4.0) — four
# hand-corrected gold-segmentation + gold-POS texts (Mdzaṅs blun, Bu ston
# chos ḥbyuṅ, Mi la ras paḥi rnam thar, Mar paḥi rnam thar), 991 lines /
# 318,230 form|tag tokens. The Tibetan quality anchor.
#
# LANGUAGE RULING (P48-3, pinned below): the four classical texts are `xct`
# (ISO 639-3 Classical Tibetan — the gretil xct_ precedent), NEVER `bo`
# (modern Tibetan; kaikki's dictionary shelf) nor `otb` (Old Tibetan — the
# old-tibetan source's lane).
#
# NO LEMMA LANE: the format is form|tag only — tokens mint form/pos keys,
# the lemma index gains zero rows from this source (honest absence, not a
# tier). See the parser test.
class SoasTibetanTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("soas-tibetan")
  ZIP_URL = "https://zenodo.org/records/574878/files/Texts.zip?download=1"

  MDZANGSBLUN_URN = "urn:nabu:soas-tibetan:mdzangsblun"
  MARPA_URN = "urn:nabu:soas-tibetan:marpa"

  def conformance_adapter = Nabu::Adapters::SoasTibetan.new

  def conformance_workdir = FIXTURES

  def conformance_expected_source_id = "soas-tibetan"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_gold_text_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal [MARPA_URN, MDZANGSBLUN_URN], refs.map(&:id),
                 "one document per Texts/<stem>-horizontal.txt, urn " \
                 "urn:nabu:soas-tibetan:<stem>, sorted"
    assert(refs.all? { |ref| ref.source_id == "soas-tibetan" })
  end

  def test_the_undisambiguated_lex_rendering_is_a_censused_discovery_skip
    refute_includes adapter.discover(workdir).to_a.map(&:path),
                    File.join(workdir, "Texts", "mila-horizontal-lex.txt"),
                    "-lex files are lexicon furniture, never documents"
    assert_equal 1, adapter.discovery_skips(workdir).skipped_by_rule,
                 "the skip is counted, never silent"
  end

  # -- parse: the language ruling + gold POS ----------------------------------

  def test_documents_are_classical_tibetan_xct_with_deposit_titles
    document = adapter.parse(ref_for(MDZANGSBLUN_URN))
    assert_equal "xct", document.language,
                 "Classical Tibetan is xct (gretil precedent) — not bo, not otb"
    assert_equal "Mdzaṅs blun", document.title
    assert_equal "mdzangsblun", document.metadata["text_id"]
    assert_equal "9th century, canonical", document.metadata["period"]
    assert_equal 3, document.count, "one passage per line (trimmed fixture: 3 of 310)"
  end

  def test_the_mdzangsblun_opening_is_byte_pinned_with_gold_pos
    first = adapter.parse(ref_for(MDZANGSBLUN_URN)).first
    assert_equal "#{MDZANGSBLUN_URN}:1", first.urn
    assert first.text.start_with?("།མཛངས་བླུན་ཞེས་བྱ་བའི་མདོ།"),
           "the Mdzaṅs blun incipit, real bytes"
    tokens = first.annotations["tokens"]
    assert_equal 377, tokens.length
    assert_equal({ "form" => "མཛངས་བླུན་", "pos" => "n.count" }, tokens[1])
    assert(tokens.none? { |token| token.key?("lemma") }, "POS-only — no lemma lane")
  end

  def test_no_document_carries_a_license_override
    adapter.discover(workdir).each do |ref|
      assert_nil adapter.parse(ref).license_override,
                 "one CC BY 4.0 grant deposit-wide — no per-document override"
    end
  end

  # -- store: idempotent load, zero lemma rows --------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 2, first.added
    assert_equal 0, first.errored
    assert_equal 5, db[:passages].count, "3 mdzangsblun + 2 marpa (trimmed heads)"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 2, second.skipped, "a byte-identical reload skips every document"
    assert_equal 5, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  def test_the_lemma_index_gains_zero_rows_from_this_source
    db = store_test_db
    source = create_source(db)
    Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    fulltext = Nabu::Store.connect_fulltext("sqlite::memory:")
    Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext)
    assert_equal 0, fulltext[Nabu::Store::Indexer::LEMMA_TABLE].count,
                 "form|tag carries no lemma — an honest absence, never faked rows"
  ensure
    fulltext&.disconnect
    db&.disconnect
  end

  # -- fetch: ZipFetch + the hard sha pin (WebMock only, no network) ----------

  def test_fetch_downloads_verifies_the_pin_and_unpacks
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(
      status: 200, body: body,
      headers: { "Content-Type" => "application/zip", "Last-Modified" => "Thu, 11 May 2017 12:38:00 GMT" }
    )
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::SoasTibetan.new(pin: Digest::SHA256.hexdigest(body))
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal [MARPA_URN, MDZANGSBLUN_URN], adapter.discover(workdir).map(&:id),
                   "the unpacked Texts/ tree is discoverable in place (the zip has TWO " \
                   "top-level entries — Texts/ + __MACOSX/ — so nothing strips)"
    end
  end

  def test_fetch_aborts_on_a_sha_pin_mismatch_with_the_tree_untouched
    body = stub_zip_body
    stub_request(:get, ZIP_URL).to_return(status: 200, body: body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::SoasTibetan.new.fetch(workdir) }
      assert_match(/sha256 pin/, error.message)
      assert_empty Dir.children(workdir), "a pin miss aborts BEFORE any tree mutation"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    stub_request(:get, ZIP_URL).to_return(status: 500)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::SoasTibetan.new.fetch(workdir) }
    end
  end

  # -- remote-health probe + registry round-trip ------------------------------

  def test_probe_heads_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::SoasTibetan.remote_probe_strategy
    targets = Nabu::Adapters::SoasTibetan.http_probe_targets
    assert_equal 1, targets.size
    assert_equal ZIP_URL, targets[0].zip_url
    assert_equal Nabu::ZipFetch::STATE_FILE, targets[0].state_file
  end

  def test_registry_resolves_soas_tibetan_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["soas-tibetan"]
    refute_nil entry, "soas-tibetan must be registered in config/sources.yml"
    assert_equal "Nabu::Adapters::SoasTibetan", entry.adapter_class_name
    assert entry.wired, "flipped 2026-07-28 (owner ruling; first sync verified live)"
    assert_equal "manual", entry.sync_policy, "a versioned-immutable Zenodo record"
    assert_includes entry.axes, "tibetan"
    assert_equal "attribution", entry.manifest.license_class, "CC BY 4.0"
    assert_match(%r{10\.5281/zenodo\.574878}, entry.manifest.license,
                 "the DOI rides the license string for citation")
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "soas-tibetan", name: "SOAS Classical Tibetan gold POS corpus",
      adapter_class: "Nabu::Adapters::SoasTibetan", license_class: "attribution"
    )
  end

  # A zip shaped like the real Texts.zip: Texts/ beside an Apple __MACOSX/
  # sidecar (TWO top-level entries — the no-strip shape ZipFetch keeps).
  def stub_zip_body
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "Texts"), File.join(dir, "Texts"))
      FileUtils.mkdir_p(File.join(dir, "__MACOSX", "Texts"))
      File.binwrite(File.join(dir, "__MACOSX", "Texts", "._mdzangsblun-horizontal.txt"),
                    "\x00\x05\x16\x07AppleDouble junk")
      zip_path = File.join(dir, "soas.zip")
      Nabu::Shell.run("zip", "-q", "-r", zip_path, "Texts", "__MACOSX", chdir: dir)
      return File.binread(zip_path)
    end
  end
end
