# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "stringio"
require "json"
require "nabu/store/text_normalized_diet"

module Store
  # The owner-fired reclaim pass: rows the P112 loader stored in
  # full whose search form is text or SQLite's lower(text) take the
  # sentinel in place — batched, rowid-cursor resumable, exclusive, with a
  # first-class dry run. The ORACLE throughout: text_search is bit-identical
  # before and after, and the dieted column equals what the current loader
  # writes for the same passages.
  class TextNormalizedDietTest < Minitest::Test
    include StoreTestDB

    Diet = Nabu::Store::TextNormalizedDiet

    FIXTURES = File.expand_path("../fixtures", __dir__)

    # Real fixture corpora across scripts: Latin/English (ASCII-lower
    # class), Greek (Unicode folds), Han (folds to itself).
    SOURCES = [
      ["perseus-greek", "Nabu::Adapters::Perseus", %w[perseus greekLit], { translations: true }],
      ["ud", "Nabu::Adapters::UniversalDependencies", %w[ud]],
      ["proiel", "Nabu::Adapters::Proiel", %w[proiel]],
      ["kanripo", "Nabu::Adapters::Kanripo", %w[kanripo]]
    ].freeze

    def setup
      @dir = Dir.mktmpdir("nabu-diet")
      @path = File.join(@dir, "catalog.sqlite3")
      @db = Nabu::Store.connect(@path)
      Nabu::Store.migrate!(@db)
      Nabu::Store.setup!(@db)
      @out = StringIO.new
    end

    def teardown
      @db.disconnect
      FileUtils.remove_entry(@dir)
    end

    # -- the oracle over real fixtures ------------------------------------

    def test_loader_storage_serves_every_parsed_search_form_bit_identically
      folds = load_fixtures!
      served = @db[:passages].select_hash(:urn, :text_search)

      mismatched = folds.reject { |urn, (text, fold)| served.fetch(urn) == (fold.empty? ? text : fold) }
      assert_empty mismatched.keys.first(5),
                   "text_search must serve the parsed search form (P112 edge: empty fold → text)"
      classes = stored_classes
      assert_operator classes.fetch(:lower, 0), :>, 0, "the fixtures exercise the lower sentinel"
      assert_operator classes.fetch(:empty, 0), :>, 0, "…and the empty sentinel"
      assert_operator classes.fetch(:stored, 0), :>, 0, "…and genuine folds, which stay stored"
    end

    def test_diet_of_p112_storage_matches_the_loader_and_serves_identically
      load_fixtures!
      loader_stored = @db[:passages].order(:id).select_map(:text_normalized)
      served_before = served
      p112_storage!

      result = run_diet

      assert_equal served_before, served, "text_search bit-identical across the diet"
      assert_equal loader_stored, @db[:passages].order(:id).select_map(:text_normalized),
                   "the dieted column equals what the current loader stores"
      assert_operator result.rows, :>, 0
    end

    def test_dry_run_projects_exactly_what_the_live_run_frees_and_writes_nothing
      load_fixtures!
      p112_storage!
      bytes_before = stored_bytes
      digest = Templates.digest(@db)

      projection = run_diet(dry_run: true)

      assert_equal digest, Templates.digest(@db), "a dry run writes nothing"
      refute File.exist?(File.join(@dir, Diet::CURSOR_FILE)), "nor a cursor"
      assert_match(/DRY RUN/, @out.string)

      result = run_diet

      assert_equal projection.rows, result.rows
      assert_equal projection.to_empty, result.to_empty
      assert_equal projection.to_lower, result.to_lower
      assert_equal projection.bytes, result.bytes
      assert_equal bytes_before - stored_bytes, result.bytes, "projected bytes = payload bytes actually freed"
    end

    def test_a_second_run_finds_nothing
      seed_rows!
      run_diet
      again = run_diet

      assert_equal 0, again.rows
    end

    def test_rows_outside_both_classes_stay_untouched
      seed_rows!
      run_diet

      assert_equal "école abc", stored_of("ÉCOLE Abc"), "a Unicode fold ASCII lower() cannot reach stays stored"
      assert_equal "μηνιν", stored_of("Μῆνιν")
      assert_equal "\u0001", stored_of("Arma Virumque")
      assert_equal "", stored_of("arma virumque")
      assert_equal "", stored_of("ABC"), "the P112 empty-fold edge keeps its stored empty string"
    end

    # -- batching, progress, resume ---------------------------------------

    def test_batches_report_progress_and_the_summary_is_honest_about_space
      seed_rows!(padding: 25)
      run_diet(batch_rows: 10)

      batch_lines = @out.string.lines.grep(/^diet:text_normalized batch /)
      assert_operator batch_lines.size, :>=, 3, "one progress line per id window"
      summary = @out.string.lines.grep(/^SUMMARY/).first
      assert_match(/VACUUM/, summary)
      assert_match(/rebuild/, summary)
      assert_match(/db:snapshot/, summary)
      refute File.exist?(File.join(@dir, Diet::CURSOR_FILE)), "a completed run clears its cursor"
    end

    def test_an_interrupted_run_resumes_from_its_rowid_cursor
      seed_rows!(padding: 25)
      expected = served
      calls = 0
      interrupt = lambda do |_cursor|
        calls += 1
        raise Interrupt if calls == 2
      end

      assert_raises(Interrupt) { run_diet(batch_rows: 10, after_batch: interrupt) }
      cursor = Diet.new(catalog: @db, catalog_path: @path).saved_cursor
      assert_equal 20, cursor - min_id + 1, "two committed windows recorded"

      @out = StringIO.new
      run_diet(batch_rows: 10)

      assert_match(/resuming after id #{cursor}/, @out.string)
      first_window = @out.string[/ids \((\d+), /, 1].to_i
      assert_equal cursor, first_window, "the resumed run starts at the cursor, not the table's start"
      assert_equal expected, served
      assert_equal 0, run_diet.rows, "nothing left behind below the cursor"
    end

    def test_a_cursor_from_another_catalog_generation_is_ignored
      seed_rows!
      File.write(File.join(@dir, Diet::CURSOR_FILE), JSON.generate("ino" => -1, "cursor" => 10**9))

      result = run_diet

      assert_operator result.rows, :>, 0, "a stale cursor (rebuilt catalog) restarts from the beginning"
    end

    # -- refusals ---------------------------------------------------------

    def test_refuses_a_catalog_whose_seam_predates_the_widening_migration
      @db[:schema_info].update(version: 54)

      error = assert_raises(Diet::Refused) { run_diet }
      assert_match(/055/, error.message)
    end

    def test_refuses_while_a_rebuild_runs
      seed_rows!
      error = assert_raises(Diet::Refused) { run_diet(rebuild_check: -> { "a rebuild process is running (pid 7)" }) }
      assert_match(/rebuild/, error.message)
    end

    def test_refuses_while_another_diet_holds_the_lock
      seed_rows!
      File.open(File.join(@dir, Diet::LOCK_FILE), File::RDWR | File::CREAT) do |held|
        held.flock(File::LOCK_EX)
        error = assert_raises(Diet::Refused) { run_diet }
        assert_match(/another diet/, error.message)
      end
    end

    private

    def run_diet(dry_run: false, batch_rows: 1000, rebuild_check: -> {}, after_batch: nil)
      Diet.new(catalog: @db, catalog_path: @path, batch_rows: batch_rows, out: @out,
               rebuild_check: rebuild_check, after_batch: after_batch).run!(dry_run: dry_run)
    end

    # Load the fixture corpora; urn => [text, parsed search form].
    def load_fixtures!
      SOURCES.each_with_object({}) do |(slug, class_name, path, options), folds|
        adapter = Object.const_get(class_name).new(**(options || {}))
        source = Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: class_name,
                                            license_class: adapter.manifest.license_class)
        workdir = File.join(FIXTURES, *path)
        Nabu::Store::Loader.new(db: @db, source: source).load_from(adapter, workdir: workdir, full: true)
        adapter.discover(workdir).each do |ref|
          adapter.parse(ref).passages.each { |passage| folds[passage.urn] = [passage.text, passage.text_normalized] }
        rescue Nabu::ParseError, Nabu::DocumentSkipped
          next
        end
      end
    end

    # Rewind the column to the P112 loader's shape: the full search form
    # wherever it is not equal to text (sentinels materialized).
    def p112_storage!
      @db[:passages].exclude(text_normalized: Nabu::Store::Loader::EMPTY_SENTINEL)
                    .update(text_normalized: :text_search)
    end

    def seed_rows!(padding: 0)
      source = Nabu::Store::Source.create(slug: "s", name: "S", adapter_class: "TestAdapter", license_class: "open")
      document = Nabu::Store::Document.create(source_id: source.id, urn: "urn:d", title: "d", language: "lat",
                                              content_sha256: "x", revision: 1, withdrawn: false)
      rows = [["Arma Virumque", "arma virumque"], ["arma virumque", "arma virumque"], ["ÉCOLE Abc", "école abc"],
              ["Μῆνιν", "μηνιν"], ["ABC", ""], %w[王道 ""]]
      rows += Array.new(padding) { |i| ["Linea #{i} Gallia", "linea #{i} gallia"] }
      rows.each_with_index do |(text, stored), index|
        stored = "" if stored == text
        @db[:passages].insert(document_id: document.id, urn: "urn:d:#{index}", sequence: index, language: "lat",
                              text: text, text_normalized: stored, content_sha_raw: "x", revision: 1,
                              withdrawn: false, annotations_json: "{}")
      end
    end

    def stored_of(text) = @db[:passages].where(text: text).get(:text_normalized)

    def served = @db[:passages].order(:id).select_map(%i[id text_search])

    def min_id = @db[:passages].min(:id)

    def stored_bytes = @db[:passages].sum(Sequel.function(:octet_length, :text_normalized)).to_i

    def stored_classes
      @db[:passages].select_map(%i[text text_normalized]).each_with_object(Hash.new(0)) do |(text, stored), tally|
        tally[if stored == Nabu::Store::Loader::LOWER_SENTINEL
                :lower
              else
                stored.empty? && !text.empty? ? :empty : :stored
              end] += 1
      end
    end
  end
end
