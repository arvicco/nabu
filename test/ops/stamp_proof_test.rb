# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "stringio"

# The parse rig with ONE deliberately altered document — what a refactor
# that was NOT a semantic no-op looks like to the by-proof sample.
class DivergentTestAdapter < TestAdapter
  def parse(document_ref)
    document = super
    return document unless document.urn.end_with?(":doc06")

    altered = Nabu::Document.new(urn: document.urn, language: document.language, title: document.title,
                                 canonical_path: document.canonical_path)
    document.passages.each do |passage|
      altered << Nabu::Passage.new(urn: passage.urn, language: passage.language,
                                   text: passage.sequence.zero? ? "#{passage.text} (altered)" : passage.text,
                                   sequence: passage.sequence)
    end
    altered
  end
end

# `rake stamps:rebless_by_proof`: for a semantic no-op refactor that dirties
# every derivation stamp, prove each dirty source's identity on a re-parse
# sample through current code (nothing written) before reblessing it; any
# divergence leaves the stamp untouched and names the first diverging urn.
class StampProofTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("nabu-stamp-proof")
    @canonical = File.join(@root, "canonical")
    @db_dir = File.join(@root, "db")
    @sources_path = File.join(@root, "sources.yml")
    write_registry("alpha" => "TestAdapter", "gamma" => "JpnTestAdapter")
    write_canonical("alpha", (1..9).to_h { |n| [format("doc%02d.txt", n), "Title #{n}\nμῆνιν #{n}\nἄειδε #{n}\n"] })
    write_canonical("gamma", "g.txt" => "草枕\n學問はどこまでも\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_refuses_without_the_attestation_and_touches_nothing
    full_rebuild
    simulate_code_drift
    before = stamp_rows

    [nil, "", "yes", Nabu::Ops::StampRebless::ATTESTATION].each do |attestation|
      error = assert_raises(Nabu::Error) { proof.run(attestation: attestation, out: StringIO.new) }
      assert_match(/canonical/, error.message)
      assert_match(/under-deriv/, error.message, "the refusal must spell out the blast radius")
      assert_match(/not DATA/, error.message, "the refusal must say what the proof does not cover")
    end
    assert_equal before, stamp_rows, "a refused proof must rewrite nothing"
  end

  def test_identical_sample_reblesses_without_rederiving
    full_rebuild
    rows_before = passage_rows
    simulate_code_drift

    out = StringIO.new
    result = proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, out: out)

    assert_equal %w[alpha gamma], result.proven.map(&:slug).sort
    assert_empty result.diverged
    assert_match(%r{proven  alpha — 9/9 sampled identical \(parser drift\)}, out.string)
    assert_match(/rebless alpha/, out.string, "the proven source rides the rebless write path")
    assert_match(/2 dirty sources/, out.string, "the estimate line comes first")
    assert_equal rows_before, passage_rows, "a proof must not re-derive a single row"
    assert_empty incremental.run.outcomes, "proven stamps must read clean"
  end

  def test_divergent_parse_is_named_and_its_stamp_untouched
    full_rebuild
    rows_before = passage_rows
    simulate_code_drift
    write_registry("alpha" => "DivergentTestAdapter", "gamma" => "JpnTestAdapter")
    alpha_before = stamp_rows.find { |row| row[:slug] == "alpha" }

    out = StringIO.new
    result = proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, sample: 9, out: out)

    diverged = result.diverged.map(&:slug)
    assert_equal %w[alpha], diverged
    verdict = result.diverged.first
    assert_equal "urn:nabu:test_adapter:doc06:1", verdict.urn
    assert_match(/altered/, verdict.detail, "the hint shows the difference")
    assert_match(/DIVERGE alpha — urn:nabu:test_adapter:doc06:1: text: .*stays dirty/, out.string)
    assert_equal alpha_before, stamp_rows.find { |row| row[:slug] == "alpha" }, "a diverged stamp is untouched"
    assert_equal %w[gamma], result.proven.map(&:slug), "other sources still prove independently"
    assert_equal rows_before, passage_rows
  end

  def test_a_divergence_outside_the_sample_is_not_seen
    # The documented limit (attestation text): a sample is evidence, not
    # exhaustion. 9 docs, sample 3 = indices 0, 4, 8 — doc06 is index 5.
    full_rebuild
    simulate_code_drift
    write_registry("alpha" => "DivergentTestAdapter", "gamma" => "JpnTestAdapter")

    result = proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, sample: 3, out: StringIO.new)

    assert_includes result.proven.map(&:slug), "alpha"
    assert_equal [3, 9], [result.proven.find { |v| v.slug == "alpha" }.sampled, result.proven.first.total]
  end

  def test_canonical_drift_is_not_provable
    full_rebuild
    simulate_code_drift
    File.write(File.join(@canonical, "alpha", "doc01.txt"), "Title 1\nchanged\n")
    alpha_before = stamp_rows.find { |row| row[:slug] == "alpha" }

    out = StringIO.new
    result = proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, out: out)

    assert_equal %w[alpha], result.unprovable.map(&:slug)
    assert_match(/dirty   alpha — not provable: canonical drift/, out.string)
    assert_equal(alpha_before, stamp_rows.find { |row| row[:slug] == "alpha" })
  end

  def test_held_document_no_longer_discovered_diverges
    full_rebuild
    simulate_code_drift
    # Rename keeps the tree's bytes but not its urns — simulate instead a
    # held row discovery cannot account for, without touching canonical.
    with_db(write: true) do |db|
      source_id = db[:sources].where(slug: "alpha").get(:id)
      db[:documents].where(source_id: source_id, urn: "urn:nabu:test_adapter:doc01")
                    .update(urn: "urn:nabu:test_adapter:ghost")
    end

    result = proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, out: StringIO.new)

    verdict = result.diverged.find { |v| v.slug == "alpha" }
    assert_equal "urn:nabu:test_adapter:ghost", verdict.urn
    assert_match(/no longer discovered/, verdict.detail)
  end

  def test_clean_sources_are_left_alone
    full_rebuild
    before = stamp_rows

    out = StringIO.new
    result = proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, out: out)

    assert_equal %w[alpha gamma], result.cleans.sort
    assert_empty result.proven
    assert_equal before, stamp_rows
    assert_match(/2 already clean/, out.string)
  end

  def test_sampling_is_deterministic_and_stratified
    assert_equal [0, 4, 8], Nabu::Ops::StampProof.sample_indices(9, 3)
    assert_equal (0...5).to_a, Nabu::Ops::StampProof.sample_indices(5, 20), "small sources are sampled whole"
    indices = Nabu::Ops::StampProof.sample_indices(1000, 20)
    assert_equal 20, indices.size
    assert_equal [0, 999], [indices.first, indices.last], "first and last always ride"
    assert_equal indices, Nabu::Ops::StampProof.sample_indices(1000, 20), "same inputs, same sample"
    gaps = indices.each_cons(2).map { |a, b| b - a }
    assert_operator gaps.max - gaps.min, :<=, 1, "evenly spaced"
    assert_empty Nabu::Ops::StampProof.sample_indices(0, 20)
  end

  def test_rejects_a_bad_sample_size
    full_rebuild
    %w[0 1 abc].each do |sample|
      assert_raises(Nabu::Error) do
        proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, sample: sample, out: StringIO.new)
      end
    end
  end

  def test_refuses_without_a_catalog
    error = assert_raises(Nabu::Error) do
      proof.run(attestation: Nabu::Ops::StampProof::ATTESTATION, out: StringIO.new)
    end
    assert_match(/full rebuild/, error.message)
  end

  private

  # A no-op refactor's footprint: every stamp's parser digest moved (the
  # shared core re-hashed), canonical and everything else unchanged.
  def simulate_code_drift
    with_db(write: true) { |db| db[:derivation_stamps].update(parser_digest: "0" * 64, fingerprint: "0" * 64) }
  end

  def config
    Nabu::Config.new(
      canonical_dir: @canonical, db_dir: @db_dir,
      sources_path: @sources_path, config_path: File.join(@root, "config", "nabu.yml")
    )
  end

  def registry = Nabu::SourceRegistry.load(@sources_path)

  def proof = Nabu::Ops::StampProof.new(config: config, registry: registry)

  def incremental = Nabu::IncrementalRebuild.new(config: config, registry: registry)

  def full_rebuild = Nabu::Rebuild.new(config: config, registry: registry).run

  def write_registry(adapters)
    File.write(@sources_path, adapters.map { |slug, adapter| "#{slug}:\n  adapter: #{adapter}\n" }.join)
  end

  def write_canonical(slug, files)
    dir = File.join(@canonical, slug)
    FileUtils.mkdir_p(dir)
    files.each { |name, content| File.write(File.join(dir, name), content) }
  end

  def with_db(write: false)
    db = Nabu::Store.connect(config.catalog_path, readonly: !write)
    yield db
  ensure
    db&.disconnect
  end

  def stamp_rows = with_db { |db| db[:derivation_stamps].order(:slug).all }

  def passage_rows = with_db { |db| db[:passages].order(:id).all }
end
