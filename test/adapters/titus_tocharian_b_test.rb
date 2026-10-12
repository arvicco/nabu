# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TITUS Tocharian B adapter tests: the West Tocharian corpus TITUS serves
# to MEMBERS ONLY (HTTP Basic auth at titus.fkidg1.uni-frankfurt.de) — the
# titus-tocharian-a family with its own constants, fetched through the
# credentials seam.
#
# FIXTURE DECISION: no B page has ever been seen (no credentials existed
# when the adapter was built, and none may be invented), so there are NO
# B parse fixtures. Re-labelling Tocharian A pages as B stand-ins would be
# hand-made fake upstream — their anchors and lanes are A's, so they would
# either exercise nothing B-specific or need hand edits. Coverage here is
# therefore fetch + config + credentials only; parse coverage (and the
# conformance suite) arrives with the first authenticated sync, whose real
# pages are cut into local/fixtures/titus-tocharian-b/ (the A recipe).
class TitusTocharianBTest < Minitest::Test
  SLUG = "titus-tocharian-b"
  ADAPTER = Nabu::Adapters::TitusTocharianB
  ENTRY = "https://titus.fkidg1.uni-frankfurt.de/texte/etcc/toch/tochb/tochb.htm"
  BASE = File.dirname(ENTRY)
  A_FIXTURES = Nabu::TestSupport.local_fixtures("titus-tocharian-a")

  def setup
    @adapter = ADAPTER.new(delay: 0)
    @auth = Nabu::Credentials::Entry.new(name: "titus", user: "member", password: "pw", token: nil,
                                         updated_at: nil)
  end

  # --- manifest: the grant's display duty --------------------------------------

  def test_manifest_carries_the_grant_and_the_editors_credit
    manifest = ADAPTER.manifest
    assert_equal SLUG, manifest.id
    assert_equal "titus_tocharian", manifest.parser_family
    assert_equal "nc", manifest.license_class
    assert_match(/2026-10-06/, manifest.license)
    assert_match(/no redistribution/i, manifest.license)
    assert_match(/TITUS/, manifest.credit)
    assert_match(/Schaefer/, manifest.credit, "the Berlin B data-entry editors are part of the display duty")
    assert_match(/Peyrot/, manifest.credit, "the London/Paris data-entry editors are part of the display duty")
    assert_equal ENTRY, manifest.upstream_url
  end

  def test_the_corpus_constants_are_its_own
    assert_equal "txb", ADAPTER::LANGUAGE
    assert_match ADAPTER::PAGE_RE, "tochb001.htm"
    refute_match ADAPTER::PAGE_RE, "tocha001.htm"
    refute_match ADAPTER::PAGE_RE, "tochb.htm"
    assert_equal :txb, ADAPTER::PARSER_PROFILE.primary_language
    refute_same Nabu::Adapters::TitusTocharianParser::TOCHARIAN_A, ADAPTER::PARSER_PROFILE
  end

  def test_probe_declares_the_members_entry_page
    targets = ADAPTER.http_probe_targets
    assert_equal [ENTRY], targets.map(&:zip_url)
    assert_equal [Nabu::TitusFetch::STATE_FILE], targets.map(&:state_file)
  end

  # --- fetch through the credentials seam (WebMock) ---------------------------

  def test_fetch_sends_the_stored_credential_and_walks_the_chain
    stub_request(:get, ENTRY).with(basic_auth: %w[member pw])
                             .to_return(body: '<frameset><frame src="tochb001.htm" name="etatext"></frameset>')
    stub_request(:get, "#{BASE}/tochb001.htm").with(basic_auth: %w[member pw])
                                              .to_return(body: "<html><body></body></html>")
    @adapter.credentials = @auth
    Dir.mktmpdir do |dir|
      report = @adapter.fetch(dir)
      assert_equal ["tochb001.htm"], Dir.children(dir).grep(/\.htm\z/)
      assert_match(/\A\h{64}\z/, report.sha)
    end
  end

  def test_a_rejected_credential_names_the_gateway_command_unwrapped
    stub_request(:get, ENTRY).to_return(status: 401)
    @adapter.credentials = @auth
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::Credentials::Rejected) { @adapter.fetch(dir) }
      assert_equal "titus credentials rejected (rotated?) — run bin/nabu creds set titus", error.message
    end
  end

  def test_discovery_reads_only_this_corpus_pages
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "tochb.htm"), "<frameset></frameset>")
      assert_empty @adapter.discover(dir).to_a, "the frameset is never a document"
    end
  end

  # The provisional B profile never silently ingests a page outside its
  # census: a real Tocharian A page (A anchors, A lanes) quarantines.
  def test_an_a_shaped_page_quarantines_under_the_b_profile
    skip "local/fixtures/titus-tocharian-a absent (restricted)" unless Dir.exist?(A_FIXTURES)
    path = File.join(A_FIXTURES, "tocha001.htm")
    ref = Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:tocha001", path: path,
                                metadata: { "page" => "tocha001" })
    assert_raises(Nabu::ParseError) { @adapter.parse(ref) }
  end

  # --- registry round-trip -----------------------------------------------------

  def test_registry_row_is_grant_gated_credentialed_blocked_and_unwired
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry[SLUG]
    refute_nil entry, "#{SLUG} must be registered in config/sources.yml"
    assert_equal ADAPTER, entry.adapter_class
    refute entry.wired, "wired: false until the first authenticated sync is verified"
    assert_equal "manual", entry.sync_policy
    assert_equal "titus", entry.credentials
    assert_predicate entry, :grant_required?
    assert_predicate entry, :blocked?
    assert_equal "2026-10-06", entry.grant.date
    assert_match(/Gippert/, entry.grant.grantor)
    assert_match(/Tocharian A and B/, entry.grant.terms)
    assert_equal %w[etym buddhist], entry.axes
    assert_equal ADAPTER.manifest, entry.manifest
  end
  # Parse coverage on real member-area pages (cut 2026-10-12 after the
  # first authenticated sync; restricted — local/fixtures only).
  B_FIXTURES = Nabu::TestSupport.local_fixtures("titus-tocharian-b")

  def require_b_fixtures!
    return if Nabu::TestSupport.local_fixtures?("titus-tocharian-b")

    skip "titus-tocharian-b local fixtures absent (the TITUS grant forbids " \
         "redistribution — bytes live in local/fixtures/, never in git)"
  end

  def test_real_page_parses_to_txb_passages
    require_b_fixtures!
    adapter = Nabu::Adapters::TitusTocharianB.new
    ref = adapter.discover(B_FIXTURES).find { |r| r.id.end_with?("tochb001") }
    refute_nil ref, "THT 1 discovered from the fixture dir"
    doc = adapter.parse(ref)
    assert_equal "txb", doc.language
    assert_equal 16, doc.passages.size
    assert doc.passages.any? { |p| p.text.include?("pelaikne") },
           "a known THT 1 reading survives verbatim"
    assert doc.passages.all? { |p| p.text.unicode_normalized?(:nfc) }
  end

  def test_real_pages_parse_stably_twice
    require_b_fixtures!
    adapter = Nabu::Adapters::TitusTocharianB.new
    refs = adapter.discover(B_FIXTURES).to_a
    assert_equal 2, refs.size
    first = refs.map { |r| adapter.parse(r).passages.map(&:urn) }
    second = refs.map { |r| adapter.parse(r).passages.map(&:urn) }
    assert_equal first, second, "URNs stable across two parses"
  end

end
