# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# LoCongres adapter tests (P80-6): the Occitan Corpus from Lo Congrès news
# — Zenodo record 8411197, six dialect CSVs (`§`-separated quadruples, no
# header), 5,152 occitan/french sentence pairs, CC BY 4.0 on-record. The
# fixtures pin the line-number identity, the four-field damage contract,
# the per-dialect facet, the -fr French siblings, both NFC boundaries
# (oc-side AND fr-side non-NFC lines are censused upstream), and the
# idempotent double-load. No network: fetch runs against WebMock stubs of
# the real Zenodo download URLs.
class LoCongresTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("lo-congres")

  AUVERN_URN = "urn:nabu:lo-congres:auvern"
  GASCON_URN = "urn:nabu:lo-congres:gascon"
  PROVENC_URN = "urn:nabu:lo-congres:provenc"
  FIXTURE_URNS = [AUVERN_URN, "#{AUVERN_URN}-fr", GASCON_URN, "#{GASCON_URN}-fr",
                  PROVENC_URN, "#{PROVENC_URN}-fr"].freeze

  def conformance_adapter
    Nabu::Adapters::LoCongres.new(translations: true)
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "lo-congres"
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest_identifies_the_lo_congres_source
    manifest = Nabu::Adapters::LoCongres.manifest
    assert_equal "lo-congres", manifest.id
    assert_match(/Creative Commons Attribution 4\.0/, manifest.license,
                 "the record README's grant, verbatim")
    assert_equal "attribution", manifest.license_class
    assert_equal "https://zenodo.org/records/8411197", manifest.upstream_url
    assert_equal "lo-congres-csv", manifest.parser_family
  end

  # --- discover ---------------------------------------------------------------

  def test_discover_mints_one_ref_per_dialect_plus_fr_siblings
    refs = Nabu::Adapters::LoCongres.new(translations: true).discover(FIXTURES).to_a
    assert_equal FIXTURE_URNS, refs.map(&:id),
                 "registry order; -fr siblings interleave after their originals"
    assert(refs.all? { |r| r.source_id == "lo-congres" })
  end

  def test_discover_without_translations_yields_originals_only
    refs = Nabu::Adapters::LoCongres.new.discover(FIXTURES).to_a
    assert_equal [AUVERN_URN, GASCON_URN, PROVENC_URN], refs.map(&:id)
  end

  def test_discover_of_an_unfetched_workdir_yields_nothing
    Dir.mktmpdir do |dir|
      assert_empty Nabu::Adapters::LoCongres.new(translations: true).discover(dir).to_a
    end
  end

  # --- parse: originals -------------------------------------------------------

  def test_parse_mints_one_occitan_passage_per_line_numbered_from_one
    document = parse_urn(AUVERN_URN)
    assert_equal "oci", document.language
    assert_equal 6, document.size
    assert_equal %w[1 2 3 4 5 6], document.map { |p| p.urn.split(":").last },
                 "identity is the 1-based line number — upstream ships no sentence ids"
    assert_equal (0..5).to_a, document.map(&:sequence)
  end

  def test_passage_text_is_the_occitan_field
    passage = parse_urn(AUVERN_URN).first
    assert_equal "La Region Auvèrnhe signa la Carta interregionala", passage.text
  end

  def test_dialect_rides_as_a_document_facet_with_upstreams_own_code
    document = parse_urn(GASCON_URN)
    assert_equal({ "value" => "gascon", "raw" => "oc-gascon-grclass" },
                 document.metadata.dig("facets", "dialect"),
                 "the dialect is a facet, never an invented language subtag (tla-hf stage precedent)")
  end

  def test_non_nfc_occitan_field_is_normalized_at_the_boundary
    passage = parse_urn(GASCON_URN).to_a[5]
    assert passage.text.unicode_normalized?(:nfc),
           "gascon line 2161 upstream carries a decomposed accent in the oc field"
  end

  # --- parse: -fr siblings ----------------------------------------------------

  def test_fr_sibling_mints_one_french_passage_per_line
    document = parse_urn("#{AUVERN_URN}-fr")
    assert_equal "fra", document.language
    assert_equal "La Région Auvergne signe la Charte interregionale", document.first.text
    assert_equal "#{AUVERN_URN}-fr:1", document.first.urn
  end

  def test_fr_citations_align_with_the_original_for_parallel
    original = parse_urn(GASCON_URN)
    translation = parse_urn("#{GASCON_URN}-fr")
    assert_equal original.map { |p| p.urn.split(":").last },
                 translation.map { |p| p.urn.split(":").last },
                 "suffix-for-suffix alignment — the Query::Parallel contract"
  end

  def test_non_nfc_french_field_is_normalized_at_the_boundary
    passage = parse_urn("#{GASCON_URN}-fr").to_a[4]
    assert passage.text.unicode_normalized?(:nfc),
           "gascon line 2132 upstream carries a decomposed accent in the fr field"
  end

  # --- parse: damage is loud --------------------------------------------------

  def test_wrong_field_count_raises_parse_error
    with_broken_dialect("only two§fields\n") do |adapter, ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/line 1/, error.message,
                   "censused: every upstream line has exactly 4 fields — a deviation is damage")
    end
  end

  def test_unexpected_variety_code_raises_parse_error
    with_broken_dialect("Una frasa§oc-gascon-grclass§Une phrase§fr\n") do |adapter, ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/variety/, error.message,
                   "the variety field is constant per file (censused) — a swap is damage")
    end
  end

  # --- fetch (WebMock only, no network) ---------------------------------------

  def test_fetch_downloads_every_dialect_via_file_fetch
    stub_dialects
    Dir.mktmpdir do |workdir|
      adapter = Nabu::Adapters::LoCongres.new(translations: true)
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/auvern/, report.notes)
      urns = adapter.discover(workdir).map(&:id)
      assert_equal 12, urns.size, "all six dialects land in place (+ -fr siblings)"
      assert_includes urns, "urn:nabu:lo-congres:lengadoc"
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    Nabu::Adapters::LoCongres::DIALECTS.each_value do |dialect|
      stub_request(:get, dialect.fetch(:url)).to_return(status: 500)
    end
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { Nabu::Adapters::LoCongres.new.fetch(workdir) }
    end
  end

  # --- remote-health probe shape ----------------------------------------------

  def test_probe_heads_every_zenodo_file_url
    assert_equal :http_zip, Nabu::Adapters::LoCongres.remote_probe_strategy
    targets = Nabu::Adapters::LoCongres.http_probe_targets
    assert_equal 6, targets.size
    assert_equal %w[auvern gascon lemosin lengadoc provenc vivaraup], targets.map(&:state_subdir)
    assert(targets.all? { |t| t.zip_url.start_with?("https://zenodo.org/records/8411197/files/") })
    assert_equal [Nabu::FileFetch::STATE_FILE], targets.map(&:state_file).uniq
    assert(targets.all? { |t| t.metadata_url.nil? },
           "the license lives in the record README, no probe-shaped endpoint")
  end

  # --- store: idempotent double-load ------------------------------------------

  def test_loads_idempotently_into_the_store
    catalog = store_test_db
    source = create_source
    adapter = Nabu::Adapters::LoCongres.new(translations: true)
    first = Nabu::Store::Loader.new(db: catalog, source: source)
                               .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 6, first.added
    assert_equal 0, first.errored
    assert_equal 34, catalog[:passages].count, "(6 + 6 + 5) originals + (6 + 6 + 5) -fr siblings"

    second = Nabu::Store::Loader.new(db: catalog, source: source)
                                .load_from(adapter, workdir: FIXTURES, full: true)
    assert_equal 0, second.errored
    assert_equal 6, second.skipped, "a byte-identical reload skips every document"
    assert_equal [1], catalog[:passages].distinct.select_map(:revision),
                 "a byte-identical reload bumps no revisions"
  end

  # --- registry round-trip ----------------------------------------------------

  def test_registry_resolves_lo_congres_and_manifest_agrees
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["lo-congres"]
    refute_nil entry, "lo-congres must be registered in config/sources.yml"
    assert_equal Nabu::Adapters::LoCongres, entry.adapter_class
    assert entry.wired, "flipped 2026-08-21 — first sync owner-round-verified (12 docs)"
    assert entry.translations, "french coverage is 100% (censused) — -fr siblings ride the same parse"
    assert_equal Nabu::Adapters::LoCongres.manifest, entry.manifest
  end

  private

  def parse_urn(urn)
    adapter = Nabu::Adapters::LoCongres.new(translations: true)
    ref = adapter.discover(FIXTURES).find { |r| r.id == urn }
    refute_nil ref, "expected discover to yield #{urn}"
    adapter.parse(ref)
  end

  def create_source
    Nabu::Store::Source.create(slug: "lo-congres", name: "Lo Congrès Occitan news corpus",
                               adapter_class: "Nabu::Adapters::LoCongres",
                               license_class: "attribution")
  end

  # A workdir whose auvern file is +content+; yields the adapter and the
  # auvern ref so damage tests exercise the real discover→parse path.
  def with_broken_dialect(content)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "auvern"))
      File.write(File.join(dir, "auvern", "oc-auvern-grclass_fr.csv"), content)
      adapter = Nabu::Adapters::LoCongres.new
      ref = adapter.discover(dir).first
      refute_nil ref
      yield adapter, ref
    end
  end

  def stub_dialects
    Nabu::Adapters::LoCongres::DIALECTS.each do |slug, dialect|
      fixture = File.join(FIXTURES, slug, dialect.fetch(:filename))
      body = File.exist?(fixture) ? File.binread(fixture) : "Frasa§#{dialect.fetch(:variety)}§Phrase§fr\n"
      stub_request(:get, dialect.fetch(:url)).to_return(
        status: 200, body: body,
        headers: { "Content-Type" => "text/csv",
                   "Last-Modified" => "Thu, 05 Oct 2023 12:00:00 GMT" }
      )
    end
  end
end
