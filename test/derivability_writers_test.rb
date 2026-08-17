# frozen_string_literal: true

require "test_helper"

# THE DERIVABILITY LAW's writer guards (P71-5; the lects_test callsite
# pattern): persistent state may enter the tree only through the
# sanctioned gateways, and SQLite handles open only through Store's
# gate. A new writer cannot appear without deliberately touching an
# allowlist here — which is the moment its law classification gets
# asked.
class DerivabilityWritersTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  # (a) Sequel connections: store.rb is the ONE opener (WAL, timeouts,
  # readonly discipline live there). Everything else asks Store.
  def test_sequel_opens_only_through_store
    offenders = grep_files(/Sequel\.(connect|sqlite)\b/).reject { |f| f == "nabu/store.rb" }
    assert_empty offenders,
                 "Sequel opened outside Store's gate: #{offenders.join(', ')} — use " \
                 "Store.connect(..., readonly: true/false)"
  end

  # (b) Journal rows carry config write-throughs: only these callsites
  # may mint lect assignments (cli writes through LectRulings first;
  # the appliers replay config; the test-support rig is suite-only).
  ASSIGN_ALLOWLIST = %w[nabu/cli.rb nabu/lect_rules.rb nabu/lect_dates.rb nabu/lect_rulings.rb].freeze

  def test_lect_journal_assign_callsites_are_allowlisted
    offenders = grep_files(/LectJournal\.assign!/) - ASSIGN_ALLOWLIST - ["nabu/store/lect_journal.rb"]
    assert_empty offenders,
                 "LectJournal.assign! called from #{offenders.join(', ')} — new journal writers " \
                 "must keep the local/config write-through in view (P70-2)"
  end

  # (c) Persistent-file writers: the sanctioned gateway census. Fetch
  # arms and adapters write canonical/ inside #fetch; the four shelves +
  # ingest write local/shelves/; the write-through modules write
  # local/config/; ops/ and data_build/ write generated repo/site or
  # caller-named output (places_lpf_builder writes its GeoJSON/TSV into
  # the runner's caller-named dataset dir — P73-5); fixture_sentinel
  # writes test fixtures; local_migration executes the P71 layout move;
  # ops/drill writes its evidence files (report.txt, verify-issues.tsv)
  # into its OWN tmp workspace, and its workspace sweep (P77-r14)
  # salvages those same small files into the caller-named drill-log
  # home (~/Library/Logs/nabu via the rake harness) before removing a
  # superseded workspace — disposable ops evidence, never a permanent
  # folder (P77-r10/r14). ANY new file here is a deliberate allowlist
  # decision, not a drive-by.
  WRITER_ALLOWLIST = %w[
    nabu/adapters/bfm.rb nabu/adapters/kitab.rb nabu/adapters/oracc.rb
    nabu/adapters/riig.rb nabu/adapters/rundata.rb
    nabu/adapters/sabellic_loans.rb nabu/adapters/trismegistos.rb
    nabu/cantigas_fetch.rb nabu/derom_fetch.rb nabu/elephantine_fetch.rb
    nabu/file_fetch.rb nabu/git_fetch.rb nabu/iness_fetch.rb
    nabu/kanripo_fetch.rb nabu/lfs_fetch.rb nabu/local_fetch.rb
    nabu/manual_drop.rb nabu/ochre_fetch.rb nabu/otdo_fetch.rb
    nabu/sefaria_fetch.rb nabu/titus_fetch.rb nabu/url_download.rb
    nabu/wiki_fetch.rb nabu/zip_fetch.rb
    nabu/language_shelf.rb nabu/library_shelf.rb nabu/note_shelf.rb
    nabu/source_shelf.rb nabu/ingest.rb
    nabu/lect_rulings.rb nabu/link_scopes.rb nabu/grant_gate.rb
    nabu/health/quarantine_baseline.rb nabu/profile.rb
    nabu/ops/axis_pages.rb nabu/ops/site_data.rb
    nabu/ops/drill.rb
    nabu/data_build/runner.rb nabu/data_build/sources_bib.rb
    nabu/data_build/places_lpf_builder.rb
    nabu/fixture_sentinel.rb nabu/local_migration.rb
  ].freeze

  def test_file_writers_are_allowlisted
    offenders = grep_files(/File\.(write|binwrite)|IO\.write|FileUtils\.(mv|cp)\b/) - WRITER_ALLOWLIST
    assert_empty offenders,
                 "persistent-file writer outside the gateway census: #{offenders.join(', ')} — " \
                 "declare it here deliberately and name what it writes and its law kind"
  end

  private

  def grep_files(pattern)
    Dir.glob(File.join(LIB, "**", "*.rb")).select { |path| File.read(path).match?(pattern) }
                                          .map { |path| path.delete_prefix("#{LIB}/") }.sort
  end
end
