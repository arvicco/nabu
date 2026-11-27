# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "nabu/ops/rebuild_verify"

module Ops
  # Nabu::Ops::RebuildCensus + RebuildVerify (`rake rebuild:census` →
  # `nabu rebuild` → `rake rebuild:verify`): the before picture, and the one
  # read-only command that proves the rebuild landed — each check a labeled
  # PASS/WARN/FAIL/SKIP line with its numbers, exit non-zero on FAIL.
  class RebuildVerifyTest < Minitest::Test
    include StoreTestDB

    V = Nabu::Ops::RebuildVerify
    C = Nabu::Ops::RebuildCensus
    T0 = Time.utc(2026, 11, 20, 12)

    Plan = Data.define(:refusal, :verdicts, :builders_dirty, :index_dirty)
    Verdict = Nabu::IncrementalRebuild::Verdict

    def setup
      @db = store_test_db
      @tmp = Dir.mktmpdir("nabu-rebuild-verify")
      @db_dir = File.join(@tmp, "db")
      @local_dir = File.join(@tmp, "local")
      FileUtils.mkdir_p([@db_dir, @local_dir])
      @ledger = Nabu::Store::Ledger.open!(File.join(@local_dir, "history.sqlite3"))
      @fulltext = Sequel.sqlite
      scratch = Nabu::Store.connect(File.join(@db_dir, "catalog.sqlite3"))
      scratch.create_table(:t) { Integer :x }
      scratch[:t].insert(x: 1)
      scratch.disconnect
      @texts = make_source("texts")
      @other = make_source("other")
      load(@texts, [document("u:a", 2), document("u:b", 2)])
      load(@other, [document("u:o", 1)])
      Nabu::Store::SourceAggregates.index_rebuilt!(@db)
      @plan = Plan.new(refusal: nil, verdicts: [Verdict.new(slug: "texts", state: :clean, reason: nil)],
                       builders_dirty: false, index_dirty: false)
    end

    def teardown
      @ledger.disconnect
      @fulltext.disconnect
      FileUtils.rm_rf(@tmp)
    end

    # -- the rig ------------------------------------------------------------

    def make_source(slug)
      Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "nc")
    end

    def load(source, docs) = Nabu::Store::Loader.new(db: @db, source: source).load(docs)

    def document(urn, count, text: "w")
      doc = Nabu::Document.new(urn: urn, title: urn, language: "grc", canonical_path: "#{urn}.xml", metadata: {})
      count.times do |i|
        doc << Nabu::Passage.new(urn: "#{urn}:#{i + 1}", sequence: i, language: "grc", text: "#{text} #{i}",
                                 text_normalized: "#{text} #{i}".downcase)
      end
      doc
    end

    def census!(at: T0 - 3_600)
      C.capture!(catalog: @db, db_dir: @db_dir, local_dir: @local_dir, ledger: @ledger, now: at, git_sha: "abc")
    end

    def full_run!(completed: true, notes: nil)
      id = Nabu::Store::RebuildRuns.start!(@ledger, mode: "full", planned_stages: [], git_sha: "deadbeef00", pid: 1,
                                                    at: T0)
      Nabu::Store::RebuildRuns.complete!(@ledger, id, at: T0 + 3_600) if completed
      Nabu::Store::RebuildRuns.fail!(@ledger, id, Nabu::Error.new(notes)) if notes
      # Ledger DateTime columns are written as local wall time (every
      # writer passes Time.now) — the rig writes the same way.
      Nabu::Store::StageTimings.record!(@ledger, kind: "rebuild", scope: "corpus", stage: "fts_lemma",
                                                 seconds: 60, rows: held, at: (T0 + 1_800).getlocal)
    end

    def held = Nabu::Store::SourceAggregates.rollup(@db).fetch(:passages_count)

    def quarantined!(slug, errored)
      @ledger[:runs].insert(source_slug: slug, kind: "rebuild", started_at: (T0 + 3_540).getlocal,
                            errored: errored, status: "succeeded")
    end

    def verify(**)
      @out = StringIO.new
      V.new(catalog: @db, fulltext: @fulltext, ledger: @ledger, db_dir: @db_dir, local_dir: @local_dir,
            stamps_plan: -> { @plan }, deleted_holders: -> { [] }, out: @out, **).run!
    end

    def check(report, name) = report.checks.find { |c| c.name == name }

    # -- the whole pass -----------------------------------------------------

    def test_a_clean_rebuild_passes_every_check_and_says_its_numbers
      census!
      full_run!
      report = verify

      refute report.failed?
      assert_equal %w[run counts aggregates fulltext stamps fold sizes readers integrity inspect],
                   report.checks.map(&:name)
      assert_equal [:pass], report.checks.map(&:status).uniq, @out.string
      assert_match(/PASS  run        full rebuild completed 2026-11-20 in 1h wall \(code deadbeef00\)/, @out.string)
      assert_match(/PASS  counts     2 sources, 0 changed; documents 3 → 3, passages 5 → 5/, @out.string)
      assert_match(/PASS  fulltext   held 5, searchable 5 \(delta 0\); indexer 5/, @out.string)
      assert_match(/PASS  fold       5 sampled rows: "" 100\.0% .*no stored fold equals text or lower\(text\)/,
                   @out.string)
      assert_match(/\.\.\.\.  integrity  PRAGMA quick_check over 1 file\(s\), .* reads every page/, @out.string,
                   "a heavy check announces its cost BEFORE it runs")
      assert_match(/SUMMARY rebuild:verify — 10 pass, 0 warn, 0 fail, 0 skip in /, @out.string)
    end

    # -- run ----------------------------------------------------------------

    def test_a_rebuild_that_never_completed_fails_loudly_and_names_the_restart
      census!
      full_run!(completed: false, notes: "disk I/O error")
      report = verify

      assert report.failed?
      assert_match(%r{never completed \(failed: disk I/O error\) — re-run `bin/nabu rebuild`; there is no resume},
                   check(report, "run").detail)
      assert_equal :skip, check(report, "counts").status
    end

    def test_no_recorded_rebuild_fails_and_a_census_after_the_run_is_never_the_before_picture
      assert_equal :fail, check(verify, "run").status

      full_run!
      census!(at: T0 + 7_200) # taken after the rebuild: must not pass for the before picture
      report = verify
      assert_equal :skip, check(report, "counts").status
      assert_match(/census: none captured before this rebuild/, @out.string)
    end

    # -- counts -------------------------------------------------------------

    def test_a_document_loss_is_explained_only_by_the_rebuilds_own_quarantine
      census!
      load(@texts, [document("u:a", 2)]) # u:b leaves the live set
      full_run!
      quarantined!("texts", 1)

      report = verify
      assert_equal :pass, check(report, "counts").status
      assert_includes check(report, "counts").lines,
                      "NOTE texts: documents 2 → 1, passages 4 → 2 — explained: the rebuild quarantined 1"

      @ledger[:runs].update(errored: 0)
      report = verify
      assert_equal :fail, check(report, "counts").status
      assert_match(/1 document\(s\) lost, only 0 quarantined by the rebuild/, check(report, "counts").lines.join)
      assert report.failed?
    end

    def test_a_lost_source_fails_and_a_passage_loss_with_documents_intact_warns
      census!
      load(@other, [])
      load(@texts, [document("u:a", 1), document("u:b", 2)])
      full_run!

      lines = check(verify, "counts").lines
      assert_equal "FAIL other: documents 1 → 0, passages 1 → 0 — LOST the whole source", lines.first
      assert_includes lines, "WARN texts: documents 2 → 2, passages 4 → 3 — passages lost with documents intact " \
                             "(a parser change since the census?)"
    end

    # -- counts: dictionary-kind sources -------------------------------------

    # A dictionary-kind source holds entries, not passages (no
    # source_aggregates row): the census counts its live entries, the
    # verify compares them. No entry-grained quarantine accounting is
    # readable ops-side (a dictionary run row counts quarantined FILES), so
    # an entry loss is a FAIL that names those files; a gain is a NOTE.
    def dictionary!(slug, entries, withdrawn: 0)
      source = Nabu::Store::Source.first(slug: slug) || make_source(slug)
      id = @db[:dictionaries].where(slug: slug).get(:id) ||
           @db[:dictionaries].insert(source_id: source.id, slug: slug, title: slug, language: "grc")
      @db[:dictionary_entries].where(dictionary_id: id).delete
      (entries + withdrawn).times do |i|
        @db[:dictionary_entries].insert(dictionary_id: id, urn: "#{slug}:#{i}", entry_id: i.to_s, key_raw: "k#{i}",
                                        headword: "h#{i}", headword_folded: "h#{i}", body: "b", content_sha256: "s",
                                        withdrawn: i >= entries)
      end
    end

    def test_the_census_counts_dictionary_sources_live_entries
      dictionary!("lexicon", 3, withdrawn: 2)
      _, census = census!

      assert_equal({ "lexicon" => { "dictionaries" => 1, "entries" => 3 } }, census.fetch("dictionaries"))
      assert_equal 3, census.dig("totals", "dictionary_entries")
      refute census.fetch("sources").key?("lexicon"), "passage sources stay where they were"
    end

    # The behind count is the loaders' write-time flag, not an index
    # probe: the summary says so, and says for how many sources fulltext
    # membership is recorded at all (unknown membership is not "0 behind").
    def test_the_census_summary_counts_dictionaries_and_labels_the_behind_flag
      dictionary!("lexicon", 3)
      @db[Nabu::Store::SourceAggregates::TABLE].where(source_id: @other.id).update(fts_member_count: nil)
      path, census = census!

      summary = C.summary(census, path)
      assert summary.start_with?("SUMMARY rebuild:census — 2 passage sources · 3 documents · 5 passages · " \
                                 "3 dictionary entries over 1 dictionary source(s) · "), summary
      assert_includes summary, " · 0 flagged fulltext-behind (the loaders' write-time flag, not an index probe; " \
                               "membership recorded for 1 of 2 passage sources) · "
      assert_match(/ · 1 db file\(s\), [\d.]+ KB → #{Regexp.escape(path)}\z/, summary)
    end

    def test_a_dictionary_entry_loss_fails_and_a_gain_is_a_note
      dictionary!("lexicon", 3)
      dictionary!("glossary", 2)
      census!
      dictionary!("lexicon", 2)
      dictionary!("glossary", 4)
      full_run!
      quarantined!("lexicon", 1)

      counts = check(verify, "counts")
      assert_equal :fail, counts.status
      assert_includes counts.lines, "FAIL lexicon: dictionary entries 3 → 2 — 1 entry(ies) lost; the rebuild " \
                                    "quarantined 1 dictionary file(s), but entry-grained quarantine accounting is " \
                                    "not readable — check by hand"
      assert_includes counts.lines, "NOTE glossary: dictionary entries 2 → 4 — gained"
      assert_match(/; dictionary entries 5 → 6 over 2 source\(s\)/, counts.detail)
    end

    def test_a_lost_dictionary_source_fails
      dictionary!("lexicon", 3)
      census!
      dictionary!("lexicon", 0)
      full_run!

      counts = check(verify, "counts")
      assert_equal :fail, counts.status
      assert_includes counts.lines, "FAIL lexicon: dictionary entries 3 → 0 — LOST the whole source"
    end

    def test_a_census_without_dictionary_counts_still_verifies_and_says_it_skipped_them
      dictionary!("lexicon", 3)
      path, census = census!
      census.delete("dictionaries")
      File.write(path, JSON.generate(census))
      full_run!

      counts = check(verify, "counts")
      assert_equal :pass, counts.status
      assert_match(/; dictionary entries not compared \(the census predates dictionary counts\)/, counts.detail)
      assert_includes counts.lines, "SKIP dictionary entries: the census predates dictionary counts — not compared"
    end

    # -- aggregates / fulltext ----------------------------------------------

    def test_a_drifted_aggregate_row_fails_the_sampled_recount
      census!
      full_run!
      @db[Nabu::Store::SourceAggregates::TABLE].where(source_id: @texts.id).update(documents_count: 9)

      report = verify
      assert_equal :fail, check(report, "aggregates").status
      assert_includes check(report, "aggregates").lines, "texts: documents_count stored 9 ≠ live 2"
    end

    def test_fulltext_fails_on_a_behind_source_an_indexer_mismatch_and_a_missing_lane
      census!
      full_run!
      Nabu::Store::SourceAggregates.mark_behind!(@db, @other.id)
      @ledger[:stage_timings].where(stage: "fts_lemma").update(rows: 4)

      fulltext = check(verify(cjk_slugs: ["texts"]), "fulltext")
      assert_equal :fail, fulltext.status
      assert_includes fulltext.lines, "other: held 1, searchable 1 (flagged behind)"
      assert_includes fulltext.lines, "the indexer indexed 4 passages but the catalog holds 5"
      assert(fulltext.lines.any? { |line| line.start_with?("cjk lane: texts is flagged but the cjk lane is ABSENT") })
      assert_equal :fail, check(verify(fulltext: nil), "fulltext").status
    end

    # -- stamps / fold ------------------------------------------------------

    def test_dirty_stamps_and_a_refusing_planner_fail
      census!
      full_run!
      @plan = Plan.new(refusal: nil, verdicts: [Verdict.new(slug: "texts", state: :dirty, reason: "parser drift")],
                       builders_dirty: false, index_dirty: true)
      stamps = check(verify, "stamps")
      assert_equal :fail, stamps.status
      assert_equal ["the fulltext index reads dirty (index code changed since the stamp)", "texts: parser drift"],
                   stamps.lines
      @plan = Plan.new(refusal: nil, verdicts: [Verdict.new(slug: "texts", state: :dirty, reason: :weak_identity),
                                                Verdict.new(slug: "other", state: :clean, reason: nil)],
                       builders_dirty: false, index_dirty: false)
      weak = check(verify, "stamps")
      assert_equal :warn, weak.status, "a weak-identity source is never stampable — a warning, not a failed rebuild"
      assert_equal "1 clean, 0 dirty, 1 weak identity, 0 without canonical", weak.detail.sub(/ \(.*\)\z/, "")
      @plan = Plan.new(refusal: "schema drift", verdicts: [], builders_dirty: false, index_dirty: false)
      assert_match(/planner refused: schema drift/, check(verify, "stamps").detail)
      assert_equal :skip, check(verify(stamps_plan: nil), "stamps").status
    end

    # A trickle runner (Ops::Trickle) crawls into canonical/ after the
    # rebuild stamped its source: the canonical identity moves, the stamp
    # reads dirty — by design, not a failed rebuild. Only canonical drift,
    # and only with the runner alive.
    def trickle!(slug, pid)
      dir = File.join(@local_dir, "trickle")
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, "#{slug}.pid"), "#{pid}\n")
      dir
    end

    def trickle_plan(reason, reasons: nil)
      Plan.new(refusal: nil, verdicts: [Verdict.new(slug: "texts", state: :clean, reason: nil),
                                        Verdict.new(slug: "wellcome", state: :dirty, reason: reason,
                                                    reasons: reasons)],
               builders_dirty: false, index_dirty: false)
    end

    # The verdict names every drifted component, so code drift behind a
    # trickle's canonical move is no longer excused as the crawl's: a FAIL
    # naming both.
    def test_code_drift_behind_a_live_trickle_canonical_move_fails_naming_both
      census!
      full_run!
      dir = trickle!("wellcome", 4242)
      @plan = trickle_plan(:canonical, reasons: %i[canonical parser])
      stamps = check(verify(trickle_dir: dir, alive: ->(pid) { pid == 4242 }), "stamps")

      assert_equal :fail, stamps.status
      assert_equal ["wellcome: canonical + parser"], stamps.lines
    end

    def test_canonical_drift_under_a_live_trickle_crawl_is_a_note_not_a_failure
      census!
      full_run!
      dir = trickle!("wellcome", 4242)
      @plan = trickle_plan(:canonical)
      stamps = check(verify(trickle_dir: dir, alive: ->(pid) { pid == 4242 }), "stamps")

      assert_equal :pass, stamps.status
      assert_equal "1 clean, 0 dirty, 1 moved by a live trickle crawl, 0 weak identity, 0 without canonical",
                   stamps.detail.sub(/ \(\d.*\)\z/, "")
      assert_equal ["NOTE wellcome: canonical moved under its live trickle crawl (pid 4242) — later arrivals " \
                    "load at the source's next sync"], stamps.lines
    end

    def test_canonical_drift_with_a_dead_trickle_pidfile_still_fails
      census!
      full_run!
      dir = trickle!("wellcome", 4242)
      @plan = trickle_plan(:canonical)
      stamps = check(verify(trickle_dir: dir, alive: ->(_pid) { false }), "stamps")

      assert_equal :fail, stamps.status
      assert_equal ["wellcome: canonical"], stamps.lines
    end

    def test_a_non_canonical_drift_under_a_live_trickle_still_fails
      census!
      full_run!
      dir = trickle!("wellcome", 4242)
      @plan = trickle_plan(:parser)
      stamps = check(verify(trickle_dir: dir, alive: ->(_pid) { true }), "stamps")

      assert_equal :fail, stamps.status
      assert_equal ["wellcome: parser"], stamps.lines
      assert_match(/\A1 clean, 1 dirty, 0 weak identity/, stamps.detail)
    end

    def test_a_stored_fold_equal_to_lower_text_fails_the_fold_sample
      load(@texts, [document("u:a", 2, text: "Wrath"), document("u:b", 2)])
      census!
      full_run!
      assert_equal :pass, check(verify, "fold").status, "the loader stored the one-byte lower sentinel"
      assert_match(/lower sentinel 40\.0%/, check(verify, "fold").detail)

      @db[:passages].where(urn: "u:a:1").update(text_normalized: "wrath 0")
      fold = check(verify, "fold")
      assert_equal :fail, fold.status
      assert_match(/1 stored fold\(s\) equal text or lower\(text\)/, fold.detail)
    end

    # -- sizes / readers / integrity / inspect -------------------------------

    def test_sizes_compare_against_the_census_and_deleted_handles_warn
      census!
      full_run!
      File.binwrite(File.join(@db_dir, "fulltext.sqlite3"), "")
      report = verify(deleted_holders: lambda {
        [[42, "ruby", File.join(@db_dir, "catalog.sqlite3")], [43, "x", "/elsewhere/catalog.sqlite3"]]
      })

      sizes = check(report, "sizes")
      assert_match(/\Acatalog\.sqlite3: [\d.]+ KB → [\d.]+ KB \(\+0\.0%\)\z/, sizes.lines.first)
      assert_equal "fulltext.sqlite3: — → 0 B", sizes.lines.last
      readers = check(report, "readers")
      assert_equal :warn, readers.status
      assert_equal ["pid 42 (ruby) still holds deleted #{File.join(@db_dir, 'catalog.sqlite3')}"], readers.lines
      refute report.failed?, "a pinned reader warns, it does not fail the rebuild"
    end

    def test_an_unreadable_db_file_fails_integrity_and_quick_mode_skips_the_heavy_checks
      census!
      full_run!
      File.binwrite(File.join(@db_dir, "links.sqlite3"), "not a database at all, just bytes" * 200)

      integrity = check(verify, "integrity")
      assert_equal :fail, integrity.status
      assert_match(/\Alinks\.sqlite3: unreadable — /, integrity.lines.first)

      report = verify(quick: true)
      assert_equal %i[skip skip], [check(report, "integrity").status, check(report, "inspect").status]
      assert_match(/QUICK=1 — PRAGMA quick_check over 2 file\(s\) not run/, check(report, "integrity").detail)
    end

    # FTS5's own `INSERT INTO t(t) VALUES('integrity-check')` is a write a
    # read-only handle refuses; since SQLite 3.44 the quick_check pragma
    # runs each FTS5 table's integrity method itself, so a damaged inverted
    # index fails the read-only check with no extra command.
    def test_quick_check_covers_a_damaged_fts5_index_read_only
      census!
      full_run!
      path = File.join(@db_dir, "fulltext.sqlite3")
      db = Nabu::Store.connect(path)
      db.run("CREATE VIRTUAL TABLE t USING fts5(x)")
      20.times { |i| db[:t].insert(x: "hello world #{i}") }
      db[:t_docsize].where { id < 10 }.delete
      db.disconnect

      report = verify
      integrity = check(report, "integrity")
      assert_equal :fail, integrity.status
      assert_includes integrity.lines, "fulltext.sqlite3: malformed inverted index for FTS5 table main.t"
      assert_match(/\.\.\.\.  integrity  .*FTS5 tables' own integrity checks included \(SQLite 3\.\d+/, @out.string,
                   "the progress line says the FTS5 internals are covered, and by which SQLite")
    end

    def test_inspect_shaped_text_fails_with_the_urn_named
      doc = Nabu::Document.new(urn: "u:bad", title: "bad", language: "grc", canonical_path: "bad.xml", metadata: {})
      doc << Nabu::Passage.new(urn: "u:bad:1", sequence: 0, language: "grc", text: '{"text" => "μῆνιν"}',
                               text_normalized: '{"text" => "μηνιν"}')
      doc << Nabu::Passage.new(urn: "u:bad:2", sequence: 1, language: "grc", text: "{restored} word",
                               text_normalized: "{restored} word")
      load(@other, [document("u:o", 1), doc])
      census!
      full_run!

      inspect = check(verify, "inspect")
      assert_equal :fail, inspect.status
      assert_equal "1 live passage(s) hold inspect-shaped text", inspect.detail.sub(/ \(.*\)\z/, "")
      assert_equal ["u:bad:1: #{'{"text" => "μῆνιν"}'.inspect}"], inspect.lines, "editorial braces are real text"
    end

    def test_lsof_deleted_field_output_parses_one_row_per_name
      out = "p42\ncruby\nf9\nn/db/catalog.sqlite3\nf10\nn/db/fulltext.sqlite3\np43\ncmdworker\nn/tmp/x\n"
      assert_equal [[42, "ruby", "/db/catalog.sqlite3"], [42, "ruby", "/db/fulltext.sqlite3"],
                    [43, "mdworker", "/tmp/x"]], V.deleted_rows(out)
    end

    # -- the census gateway --------------------------------------------------

    def test_the_census_lands_under_local_rebuild_and_is_never_overwritten
      path, census = census!

      assert_equal File.join(@local_dir, "rebuild", "census-20261120T110000Z.json"), path
      assert_equal({ "documents" => 2, "passages" => 4, "fts_members" => 4, "fts_behind" => false },
                   census.fetch("sources").fetch("texts"))
      assert_equal 5, census.dig("totals", "passages_count")
      assert_operator census.dig("files", "catalog.sqlite3"), :>, 0
      assert_equal JSON.parse(File.read(path)), census
      assert_raises(C::Refused) { census! }
    end

    def test_latest_before_picks_the_newest_census_strictly_before_the_time
      census!(at: T0 - 7_200)
      newest, = census!(at: T0 - 60)
      census!(at: T0 + 60)

      assert_equal newest, C.latest_before(@local_dir, T0).first
      assert_nil C.latest_before(@local_dir, T0 - 86_400)
    end

    def test_a_catalog_without_aggregates_refuses_the_census
      bare = Sequel.sqlite
      bare.create_table(:sources) { primary_key :id }
      error = assert_raises(C::Refused) { C.build(catalog: bare, db_dir: @db_dir, git_sha: "x") }
      assert_match(/rake aggregates:backfill/, error.message)
    ensure
      bare&.disconnect
    end
  end
end
