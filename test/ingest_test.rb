# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The `nabu ingest` engine (P19-5; design: canonical-memory §4b): derive →
# (assist) → categorize → copy → append, with the prompt layer and the
# assist subprocess both injectable so every mode tests without a TTY,
# without mutool, and without spawning anything.
class IngestTest < Minitest::Test
  FAKE_PDF_PAGES = lambda do |path|
    case File.basename(path)
    when "vaillant-1950-manuel.pdf" then ["Manuel du vieux slave\nGrammaire et textes.\n", "Deuxieme page.\n"]
    when "scan-plate.pdf", "leskien-1871-scan.pdf" then [""]
    when "ocr-smoke.pdf" then ["01assJ£ Die altbulgarische Sprache.\n"] # the live Leskien OCR garbage
    when "ocr-garbage.pdf" then ["01assJ£ 3,14 §§ 42\n"]
    when "greek-smoke.pdf" then ["※ 123 λόγος ἦν\n"]
    else raise Nabu::PdfText::Error, "mutool text extraction failed for #{path} (rigged)"
    end
  end

  FAKE_PDF_INFO = lambda do |path|
    case File.basename(path)
    when "vaillant-1950-manuel.pdf"
      { "title" => "Manuel du vieux slave", "creator" => "A. Vaillant", "year" => 1950 }
    when "leskien-1871-scan.pdf"
      { "year" => 2026 } # a scan's CreationDate is the SCAN date
    else
      {}
    end
  end

  # A scripted prompt layer: records every (label, default) it was asked and
  # replays canned answers per field key prefix ("" = accept the default).
  class ScriptedAsk
    attr_reader :asked

    def initialize(answers = {})
      @answers = answers
      @asked = []
    end

    def to_proc
      lambda do |label, default|
        @asked << [label, default]
        key = @answers.keys.find { |k| label.start_with?(k) }
        key ? @answers[key] : ""
      end
    end
  end

  # An ask double that replays a QUEUE of answers per field-label prefix —
  # the bad-then-good re-prompt rig (P20-1); exhausted queues answer ""
  # (accept the default), like ScriptedAsk.
  class QueuedAsk
    attr_reader :asked

    def initialize(queues)
      @queues = queues.transform_values(&:dup)
      @asked = []
    end

    def to_proc
      lambda do |label, default|
        @asked << [label, default]
        key = @queues.keys.find { |k| label.start_with?(k) }
        key && !@queues[key].empty? ? @queues[key].shift : ""
      end
    end
  end

  def with_rig(resolver: Nabu::Ingest::AcceptResolver.new, overrides: {}, assist_command: nil,
               assist_runner: nil, notify: nil, download: nil)
    Dir.mktmpdir("nabu-ingest") do |root|
      shelf = Nabu::LibraryShelf.new(dir: File.join(root, "canonical", "local-library"))
      notes = []
      engine = Nabu::Ingest.new(
        shelf: shelf, resolver: resolver, overrides: overrides,
        assist_command: assist_command, assist_runner: assist_runner || Nabu::Ingest::Assist.method(:run),
        pdf_pages: FAKE_PDF_PAGES, pdf_info: FAKE_PDF_INFO, download: download,
        notify: notify || ->(line) { notes << line }, now: Time.utc(2026, 7, 14)
      )
      yield engine, shelf, root, notes
    end
  end

  def write_pdf(root, name, content = "%PDF fake #{name}")
    path = File.join(root, name)
    File.write(path, content)
    path
  end

  # -- derivation: mechanical candidates ---------------------------------------

  def test_pdf_metadata_filename_heuristics_and_provenance_prefill_the_entry
    with_rig do |engine, shelf, root|
      source = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcome = engine.add_files([source]).first
      assert_equal :added, outcome.status
      assert_equal "urn:nabu:local-library:inbox:vaillant-1950-manuel", outcome.urn
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal "Manuel du vieux slave", entry.title, "PDF Info metadata beats the filename guess"
      assert_equal "A. Vaillant", entry.creator
      assert_equal 1950, entry.year
      assert_match(/\Aingested 2026-07-14 from /, entry.provenance)
      assert_equal "research_private", entry.license_class
      assert_equal "Manuel", outcome.search_term, "a word of extracted text feeds the search hint"
    end
  end

  def test_filename_heuristics_carry_when_pdf_metadata_is_absent
    with_rig do |engine, shelf, root|
      # No Info dict, no text layer: the scan — filename candidates stand.
      source = write_pdf(root, "scan-plate.pdf")
      outcome = engine.add_files([source]).first
      assert_equal :added, outcome.status
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal "scan plate", entry.title
      assert_nil outcome.search_term, "no text, no search hint — metadata-only files are not searchable"
    end
  end

  def test_a_filename_year_beats_the_pdf_creation_date
    with_rig do |engine, shelf, root|
      # CreationDate on a scan is the scan date; the year in a scholarly
      # `author-year-title` filename is the publication year, named
      # deliberately — it must win.
      engine.add_files([write_pdf(root, "leskien-1871-scan.pdf")])
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal 1871, entry.year
    end
  end

  def test_filename_year_and_creator_heuristics_on_text_files
    with_rig do |engine, shelf, root|
      path = File.join(root, "leskien-1871-notes.txt")
      File.write(path, "Die altbulgarische Sprache ist die aelteste Form.\n")
      engine.add_files([path], collection: "slavistics")
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("slavistics")).entries.first
      assert_equal 1871, entry.year
      assert_equal "Leskien", entry.creator
      assert_equal "leskien 1871 notes", entry.title
    end
  end

  def test_unreadable_pdf_degrades_to_filename_candidates_with_a_note
    with_rig do |engine, shelf, root, notes|
      source = write_pdf(root, "broken.pdf")
      outcome = engine.add_files([source]).first
      assert_equal :added, outcome.status, "an unreadable text layer degrades derivation; sync will judge the file"
      assert(notes.any? { |line| line.match?(/no text sample/) })
      assert_equal "broken", Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first.title
    end
  end

  # -- idempotency and the revision story ---------------------------------------

  def test_reingesting_identical_manifested_bytes_is_an_honest_no_op
    with_rig do |engine, shelf, root|
      source = write_pdf(root, "vaillant-1950-manuel.pdf")
      engine.add_files([source])
      outcome = engine.add_files([source]).first
      assert_equal :skipped, outcome.status
      assert_match(%r{identical bytes already catalogued at inbox/vaillant-1950-manuel\.pdf}, outcome.message)
      assert_equal 1, Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.size
    end
  end

  def test_an_unmanifested_identical_copy_does_not_block_the_resume
    with_rig do |engine, shelf, root|
      # A stray unmanifested copy (hand-copied, or the kill-between-copy-
      # and-append crash window) must not block re-running the ingest.
      source = write_pdf(root, "vaillant-1950-manuel.pdf")
      FileUtils.mkdir_p(File.join(shelf.dir, "inbox"))
      FileUtils.cp(source, File.join(shelf.dir, "inbox", "vaillant-1950-manuel.pdf"))
      outcome = engine.add_files([source]).first
      assert_equal :added, outcome.status, "re-running ingest must finish the cataloguing"
      assert shelf.manifested?("inbox", "vaillant-1950-manuel.pdf")
    end
  end

  def test_same_name_new_content_is_a_revision_not_a_second_entry
    with_rig do |engine, shelf, root|
      first = write_pdf(root, "vaillant-1950-manuel.pdf", "first bytes")
      engine.add_files([first])
      FileUtils.rm(first)
      second = write_pdf(root, "vaillant-1950-manuel.pdf", "second bytes")
      outcome = engine.add_files([second]).first
      assert_equal :revised, outcome.status
      assert_match(/sync records a revision/, outcome.message)
      assert_equal "second bytes", File.read(File.join(shelf.dir, "inbox", "vaillant-1950-manuel.pdf"))
      assert_equal 1, Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.size
    end
  end

  # -- atomicity (P20-1, owner doctrine): the batch lands whole or not at all ----

  def test_a_bad_file_aborts_the_whole_batch_and_canonical_is_untouched
    with_rig do |engine, shelf, root|
      good = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcomes = engine.add_files([File.join(root, "ghost.pdf"), good])
      assert_equal %i[failed aborted], outcomes.map(&:status),
                   "the defect is named; the valid file does NOT half-land"
      assert_match(/ghost\.pdf/, outcomes.first.message)
      refute_predicate outcomes.first, :ok?
      assert_match(/batch aborted, canonical untouched/, outcomes.last.message)
      refute Dir.exist?(shelf.dir), "no copy, no manifest — canonical is byte-identical"
    end
  end

  def test_a_failed_download_in_a_mixed_batch_aborts_the_local_file_too
    stub_request(:get, ARCHIVE_URL).to_return(status: 404)
    with_rig do |engine, shelf, root|
      good = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcomes = engine.add_files([ARCHIVE_URL, good])
      assert_equal %i[failed aborted], outcomes.map(&:status)
      assert_match(/HTTP 404/, outcomes.first.message)
      refute Dir.exist?(shelf.dir), "canonical untouched — nothing to clean up, nothing half-landed"
    end
  end

  def test_an_executable_file_is_refused_and_aborts_the_batch
    with_rig do |engine, shelf, root|
      rogue = write_pdf(root, "bin-nabu", "#!/usr/bin/env ruby\n")
      File.chmod(0o755, rogue)
      good = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcomes = engine.add_files([rogue, good])
      assert_equal %i[failed aborted], outcomes.map(&:status)
      assert_match(/bin-nabu is executable \(mode \+x\) — refusing; shelf material never runs/,
                   outcomes.first.message)
      refute Dir.exist?(shelf.dir), "the live incident catalogued bin/nabu itself — never again"
    end
  end

  def test_a_freak_append_failure_rolls_the_copy_back
    with_rig do |engine, shelf, root|
      def shelf.append_entry!(**)
        raise Nabu::LibraryShelf::Error, "disk full (rigged)"
      end
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :failed, outcome.status
      assert_match(/disk full \(rigged\) — copy rolled back/, outcome.message)
      refute_path_exists File.join(shelf.dir, "inbox", "vaillant-1950-manuel.pdf"),
                         "the compensating delete — canonical never keeps a stray"
      refute_path_exists shelf.manifest_path("inbox")
    end
  end

  def test_a_successful_batch_lands_every_file_and_entry
    with_rig do |engine, shelf, root|
      outcomes = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf"),
                                   write_pdf(root, "scan-plate.pdf")])
      assert_equal %i[added added], outcomes.map(&:status)
      entries = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries
      assert_equal %w[vaillant-1950-manuel.pdf scan-plate.pdf], entries.map(&:file)
      outcomes.each { |outcome| assert_path_exists File.join(shelf.dir, "inbox", outcome.file) }
    end
  end

  def test_intra_batch_duplicate_names_are_caught_at_the_rehearsal
    with_rig do |engine, shelf, root|
      nested = File.join(root, "again")
      FileUtils.mkdir_p(nested)
      first = write_pdf(root, "vaillant-1950-manuel.pdf", "first bytes")
      second_path = File.join(nested, "vaillant-1950-manuel.pdf")
      File.write(second_path, "different bytes, same basename")
      outcomes = engine.add_files([first, second_path])
      assert_equal %i[aborted failed], outcomes.map(&:status),
                   "two new files with one target name can never both be entries"
      assert_match(/manifest rehearsal: duplicate entry/, outcomes.last.message)
      refute Dir.exist?(shelf.dir)
    end
  end

  # -- url intake (P20-0): download first, then the exact same pipeline ----------

  ARCHIVE_URL = "https://archive.org/download/handbuch/leskien-1871-notes.txt"

  def test_a_url_downloads_then_flows_through_the_same_intake_with_the_source_url_lane
    stub_request(:get, ARCHIVE_URL).to_return(status: 200, body: "Die altbulgarische Sprache.\n")
    with_rig do |engine, shelf, _root|
      outcome = engine.add_files([ARCHIVE_URL]).first
      assert_equal :added, outcome.status
      assert_equal "urn:nabu:local-library:inbox:leskien-1871-notes", outcome.urn
      copied = File.join(shelf.dir, "inbox", "leskien-1871-notes.txt")
      assert_equal "Die altbulgarische Sprache.\n", File.read(copied)
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal ARCHIVE_URL, entry.source_url, "the manifest records the url the owner gave"
      assert_equal "ingested 2026-07-14 from #{ARCHIVE_URL}", entry.provenance,
                   "provenance names the url, never the ephemeral staging path"
      assert_equal 1871, entry.year, "filename heuristics run on the derived name"
    end
  end

  def test_a_redirected_url_ingests_the_final_body_but_records_the_original_url
    mirror = "https://ia601500.us.archive.org/5/items/handbuch/leskien-1871-notes.txt"
    stub_request(:get, ARCHIVE_URL).to_return(status: 302, headers: { "Location" => mirror })
    stub_request(:get, mirror).to_return(status: 200, body: "mirror body\n")
    with_rig do |engine, shelf, _root|
      outcome = engine.add_files([ARCHIVE_URL]).first
      assert_equal :added, outcome.status
      assert_equal "mirror body\n", File.read(File.join(shelf.dir, "inbox", "leskien-1871-notes.txt"))
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal ARCHIVE_URL, entry.source_url,
                   "mirror-node urls rotate — the original url is the stable identity"
    end
  end

  def test_a_failed_download_is_a_named_failure_with_no_shelf_mutation
    stub_request(:get, ARCHIVE_URL).to_return(status: 404)
    with_rig do |engine, shelf, _root|
      outcome = engine.add_files([ARCHIVE_URL]).first
      assert_equal :failed, outcome.status
      assert_match(/HTTP 404/, outcome.message)
      refute Dir.exist?(shelf.dir), "no copy, no manifest — the shelf is untouched"
    end
  end

  def test_mixed_batch_url_and_local_file_both_land
    stub_request(:get, ARCHIVE_URL).to_return(status: 200, body: "url body\n")
    with_rig do |engine, shelf, root|
      local = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcomes = engine.add_files([ARCHIVE_URL, local])
      assert_equal %i[added added], outcomes.map(&:status)
      entries = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries
      assert_equal [ARCHIVE_URL, nil], entries.map(&:source_url),
                   "the source_url lane exists only for url ingests"
    end
  end

  def test_local_ingests_write_no_source_url_lane
    with_rig do |engine, shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      refute_match(/source_url/, File.read(shelf.manifest_path("inbox")),
                   "omit-when-empty — the manifest style")
    end
  end

  def recording_download(events)
    download = Object.new
    download.define_singleton_method(:fetch) do |url, dir:|
      events << [:download, url]
      path = File.join(dir, File.basename(url))
      File.write(path, "downloaded body\n")
      path
    end
    download
  end

  def recording_resolver(events)
    Nabu::Ingest::PromptResolver.new(ask: lambda do |label, _default|
      events << [:ask, label]
      ""
    end)
  end

  def test_staging_completes_downloads_and_existence_checks_before_any_prompt
    events = []
    with_rig(resolver: recording_resolver(events), download: recording_download(events)) do |engine, _shelf, root|
      local = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcomes = engine.add_files(["https://example.org/a.txt", local])
      assert_equal %i[added added], outcomes.map(&:status)
      asks = events.each_index.select { |i| events[i].first == :ask }
      downloads = events.each_index.select { |i| events[i].first == :download }
      refute_empty asks
      refute_empty downloads
      assert_operator downloads.max, :<, asks.min,
                      "ALL staging (downloads, existence checks) precedes ANY categorization prompt"
    end
  end

  def test_a_staging_defect_asks_no_questions_at_all
    events = []
    with_rig(resolver: recording_resolver(events), download: recording_download(events)) do |engine, shelf, root|
      outcomes = engine.add_files([File.join(root, "ghost.pdf"), "https://example.org/a.txt"])
      assert_equal %i[failed aborted], outcomes.map(&:status)
      assert(events.none? { |kind, _| kind == :ask },
             "a batch that cannot land never wastes a prompt (atomic prepare, P20-1)")
      refute Dir.exist?(shelf.dir)
    end
  end

  def test_the_staging_dir_dissolves_after_the_batch
    dirs = []
    download = Object.new
    download.define_singleton_method(:fetch) do |_url, dir:|
      dirs << dir
      path = File.join(dir, "a.txt")
      File.write(path, "body\n")
      path
    end
    with_rig(download: download) do |engine, shelf, _root|
      engine.add_files(["https://example.org/a.txt"])
      refute Dir.exist?(dirs.first), "the temp download is cleaned up — the shelf copy is the record"
      assert shelf.manifested?("inbox", "a.txt")
    end
  end

  # -- the interactive mode (prompt layer injected) ------------------------------

  def test_interactive_prompts_every_field_with_candidates_prefilled_and_license_default_stated
    ask = ScriptedAsk.new("tags" => "grammar, ocs")
    with_rig(resolver: Nabu::Ingest::PromptResolver.new(ask: ask.to_proc)) do |engine, shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      assert_equal Nabu::Ingest::LIBRARY_FIELDS.size, ask.asked.size
      labels = ask.asked.map(&:first)
      assert_equal "title", labels.first
      license_label = labels.find { |l| l.start_with?("license_class") }
      assert_match(/default research_private = never served or redistributed/, license_label,
                   "the shelf's license doctrine is STATED at the prompt")
      assert_match(/open, attribution, nc, research_private, restricted/, license_label)
      assert_equal "Manuel du vieux slave", ask.asked.first.last, "candidates arrive as prompt defaults"
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal %w[grammar ocs], entry.tags, "typed comma lists split"
      assert_equal "A. Vaillant", entry.creator, "Enter keeps the prefilled candidate"
    end
  end

  def test_interactive_dash_clears_a_prefilled_field
    ask = ScriptedAsk.new("creator" => "-")
    with_rig(resolver: Nabu::Ingest::PromptResolver.new(ask: ask.to_proc)) do |engine, shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_nil entry.creator
    end
  end

  # -- validation at the resolver seam (P20-1, the "chu (body ger)" incident) ----

  INCIDENT = "chu (body ger)"

  def test_interactive_reprompts_an_invalid_languages_answer_with_a_one_line_reason
    ask = QueuedAsk.new("languages" => [INCIDENT, "chu, deu"])
    warnings = []
    resolver = Nabu::Ingest::PromptResolver.new(ask: ask.to_proc, warn: ->(line) { warnings << line })
    with_rig(resolver: resolver) do |engine, shelf, root|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :added, outcome.status
      assert_equal 2, ask.asked.count { |label, _| label.start_with?("languages") }, "the prompt repeated"
      assert_equal ['"chu (body ger)" is not a language tag — give comma-separated codes like: chu, deu'],
                   warnings
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal %w[chu deu], entry.languages
    end
  end

  def test_interactive_reprompts_an_invalid_license_class_naming_the_vocabulary
    ask = QueuedAsk.new("license_class" => %w[public-domainish open])
    warnings = []
    resolver = Nabu::Ingest::PromptResolver.new(ask: ask.to_proc, warn: ->(line) { warnings << line })
    with_rig(resolver: resolver) do |engine, shelf, root|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :added, outcome.status
      assert_match(/license_class must be one of open, attribution, nc, research_private, restricted/,
                   warnings.first)
      assert_equal "open", Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first.license_class
    end
  end

  def test_interactive_dash_escapes_the_reprompt_loop_by_clearing_the_field
    ask = QueuedAsk.new("languages" => [INCIDENT, "-"])
    resolver = Nabu::Ingest::PromptResolver.new(ask: ask.to_proc, warn: ->(_line) {})
    with_rig(resolver: resolver) do |engine, shelf, root|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :added, outcome.status
      assert_empty Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first.languages
    end
  end

  def test_yes_mode_fails_a_bad_languages_flag_in_prepare_and_nothing_is_written
    with_rig(overrides: { "languages" => INCIDENT }) do |engine, shelf, root|
      outcomes = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf"),
                                   write_pdf(root, "scan-plate.pdf")])
      assert_equal %i[failed failed], outcomes.map(&:status), "every defect is named (the flag hits both)"
      assert_match(/"chu \(body ger\)" is not a language tag — give comma-separated codes like: chu, deu/,
                   outcomes.first.message)
      refute Dir.exist?(shelf.dir), "validation fires in PREPARE — no copy, no manifest, canonical untouched"
    end
  end

  def test_an_invalid_license_class_flag_fails_the_file_naming_the_vocabulary
    with_rig(overrides: { "license_class" => "public-domainish" }) do |engine, shelf, root|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :failed, outcome.status
      assert_match(/license_class must be one of open, attribution, nc, research_private, restricted/,
                   outcome.message)
      refute Dir.exist?(shelf.dir)
    end
  end

  # The incident, pinned end to end: no resolver mode can land the exact
  # poison string in a manifest (interactive loops, --yes fails in prepare,
  # and an assist suggestion only prefills the same guarded seam) — and a
  # batch containing it lands NOTHING.
  def test_the_incident_string_can_never_reach_a_manifest_via_any_resolver_mode
    with_rig(overrides: { "languages" => INCIDENT }) do |engine, shelf, root|
      outcomes = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      assert_equal [:failed], outcomes.map(&:status), "--yes: refused in prepare"
      refute Dir.exist?(shelf.dir)
    end
    suggestion = Nabu::Ingest::Assist::Result.new(status: 0, suggestion: { "languages" => [INCIDENT] },
                                                  output: "")
    ask = QueuedAsk.new("languages" => ["", "-"]) # Enter keeps the poisoned prefill → re-prompt → clear
    resolver = Nabu::Ingest::PromptResolver.new(ask: ask.to_proc, warn: ->(_line) {})
    with_rig(resolver: resolver, assist_command: "my-assist",
             assist_runner: canned_assist(suggestion)) do |engine, shelf, root|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :added, outcome.status
      refute_match(/body ger/, File.read(shelf.manifest_path("inbox")),
                   "an assist suggestion prefills the guarded prompt — it can never land unvalidated")
    end
  end

  # -- the search-hint rider (P20-1): a real word or no hint at all --------------

  def test_search_hint_skips_ocr_garbage_for_the_first_alphabetic_word
    with_rig do |engine, _shelf, root|
      outcome = engine.add_files([write_pdf(root, "ocr-smoke.pdf")]).first
      assert_equal "altbulgarische", outcome.search_term,
                   "digit/symbol-riddled OCR tokens are not words; length < 4 skipped too"
    end
  end

  def test_search_hint_counts_unicode_letters_as_alphabetic
    with_rig do |engine, _shelf, root|
      outcome = engine.add_files([write_pdf(root, "greek-smoke.pdf")]).first
      assert_equal "λόγος", outcome.search_term
    end
  end

  def test_search_hint_is_omitted_when_the_sample_is_all_garbage
    with_rig do |engine, _shelf, root|
      outcome = engine.add_files([write_pdf(root, "ocr-garbage.pdf")]).first
      assert_equal :added, outcome.status
      assert_nil outcome.search_term, "junk is worse than no hint (the live `search 01assJ£` epilogue)"
    end
  end

  # -- the scripted mode (--yes + flags) -----------------------------------------

  def test_flag_overrides_beat_derived_candidates_and_land_unprompted
    overrides = { "title" => "Manuel du vieux slave (owner copy)", "languages" => "chu,fra",
                  "license_class" => "open", "related" => "urn:nabu:ccmh:mar:mt, chu" }
    with_rig(overrides: overrides) do |engine, shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal "Manuel du vieux slave (owner copy)", entry.title
      assert_equal %w[chu fra], entry.languages
      assert_equal "open", entry.license_class, "an explicit upgrade is written to the manifest"
      assert_equal ["urn:nabu:ccmh:mar:mt", "chu"], entry.related
    end
  end

  def test_the_research_private_default_is_omitted_from_the_manifest
    with_rig do |engine, shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      content = File.read(shelf.manifest_path("inbox"))
      refute_match(/license_class/, content,
                   "manifest silence means the conservative class — an explicit class marks an override")
    end
  end

  # -- the assist mode (subprocess suggestion) -------------------------------------

  def canned_assist(result)
    lambda do |command:, brief:|
      @assist_calls ||= []
      @assist_calls << [command, brief]
      result
    end
  end

  def test_assist_brief_carries_schema_derived_candidates_and_the_text_sample
    result = Nabu::Ingest::Assist::Result.new(status: 0, suggestion: {}, output: "")
    with_rig(assist_command: "my-assist", assist_runner: canned_assist(result)) do |engine, _shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      command, brief = @assist_calls.first
      assert_equal "my-assist", command
      assert_equal "nabu.ingest-assist/1", brief[:schema]
      assert_equal "library", brief[:shelf]
      assert_equal "vaillant-1950-manuel.pdf", brief[:file]
      assert_equal "A. Vaillant", brief[:derived]["creator"]
      assert_match(/Manuel du vieux slave/, brief[:sample])
      assert_equal "research_private", brief[:license_default]
      assert_includes brief[:license_classes], "nc"
    end
  end

  def test_assist_suggestion_prefills_but_flags_still_win
    suggestion = { "title" => "Manuel du vieux slave (2e éd.)", "tags" => %w[grammar ocs],
                   "creator" => "André Vaillant" }
    result = Nabu::Ingest::Assist::Result.new(status: 0, suggestion: suggestion, output: "")
    ask = ScriptedAsk.new
    with_rig(resolver: Nabu::Ingest::PromptResolver.new(ask: ask.to_proc),
             overrides: { "creator" => "Vaillant, A." },
             assist_command: "my-assist", assist_runner: canned_assist(result)) do |engine, shelf, root|
      engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")])
      entry = Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first
      assert_equal "Manuel du vieux slave (2e éd.)", entry.title, "the suggestion prefilled the prompt"
      assert_equal %w[grammar ocs], entry.tags
      assert_equal "Vaillant, A.", entry.creator, "an explicit flag beats the assist suggestion"
      title_default = ask.asked.find { |label, _| label == "title" }.last
      assert_equal "Manuel du vieux slave (2e éd.)", title_default,
                   "assist suggests, the owner confirms — the prompt still ran"
    end
  end

  def test_assist_failure_is_advisory_mechanical_candidates_stand
    result = Nabu::Ingest::Assist::Result.new(status: 3, suggestion: nil, output: "model unavailable\n")
    with_rig(assist_command: "my-assist", assist_runner: canned_assist(result)) do |engine, shelf, root, notes|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :added, outcome.status
      assert(notes.any? { |line| line.match?(/assist\| model unavailable/) })
      assert(notes.any? { |line| line.match?(/assist: exit 3, no usable suggestion/) })
      assert_equal "Manuel du vieux slave",
                   Nabu::LibraryManifest.load(shelf.manifest_path("inbox")).entries.first.title
    end
  end

  # Assist.run is a real subprocess boundary: JSON on stdout (prose-wrapped
  # tolerated), stderr as diagnostics, spawn failure honest.
  def test_assist_run_parses_json_from_a_real_subprocess
    result = Nabu::Ingest::Assist.run(command: %(echo '{"title":"From the hook"}'), brief: { a: 1 })
    assert_predicate result, :ok?
    assert_equal({ "title" => "From the hook" }, result.suggestion)
  end

  def test_assist_run_tolerates_prose_wrapped_json_and_reports_garbage_as_nil
    wrapped = Nabu::Ingest::Assist.run(command: %(echo 'Here you go: {"year": 1950} — hope that helps'),
                                       brief: {})
    assert_equal({ "year" => 1950 }, wrapped.suggestion)
    garbage = Nabu::Ingest::Assist.run(command: "echo no json here", brief: {})
    assert_nil garbage.suggestion
    refute_predicate garbage, :ok?
  end

  def test_assist_run_reports_an_unstartable_command
    result = Nabu::Ingest::Assist.run(command: "/no/such/hook-#{Process.pid}", brief: {})
    assert_nil result.status
    refute_predicate result, :ok?
  end

  # -- --shelf language: the dossier scaffold --------------------------------------

  def with_language_shelf
    Dir.mktmpdir("nabu-ingest-lang") do |root|
      yield Nabu::LanguageShelf.new(dir: File.join(root, "canonical", "local-language"))
    end
  end

  def test_scaffold_language_writes_a_parseable_dossier_skeleton
    with_language_shelf do |shelf|
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new,
                                overrides: { "name" => "Old Ruthenian", "context" => "Chancery language." })
      outcome = engine.scaffold_language("zle-ort", language_shelf: shelf)
      assert_equal :added, outcome.status
      dossier = shelf.load("zle-ort")
      assert_equal "Old Ruthenian", dossier.name
      assert_equal "zle", dossier.family, "the family candidate derives from the code prefix"
      assert_equal "Chancery language.", dossier.context
    end
  end

  def test_scaffold_language_prompts_name_family_context
    ask = ScriptedAsk.new("name" => "Church Slavic")
    with_language_shelf do |shelf|
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::PromptResolver.new(ask: ask.to_proc))
      engine.scaffold_language("chu", language_shelf: shelf)
      assert_equal(%w[name family context], ask.asked.map { |label, _| label.split.first })
      assert_equal "Church Slavic", shelf.load("chu").name
    end
  end

  def test_scaffold_language_is_a_no_op_on_an_existing_dossier
    with_language_shelf do |shelf|
      shelf.write!(Nabu::LanguageDossier.new(code: "chu", name: "Old Church Slavonic"))
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new)
      outcome = engine.scaffold_language("chu", language_shelf: shelf)
      assert_equal :skipped, outcome.status
      assert_match(/dossier exists — edit .*chu\.md/, outcome.message)
      assert_equal "Old Church Slavonic", shelf.load("chu").name, "the existing dossier is untouched"
    end
  end

  def test_scaffold_language_refuses_a_non_code
    with_language_shelf do |shelf|
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new)
      error = assert_raises(Nabu::ValidationError) do
        engine.scaffold_language("Not A Code!", language_shelf: shelf)
      end
      assert_match(/not a language code/, error.message)
    end
  end

  # -- --shelf source: the source-dossier scaffold (P24-0) --------------------

  def with_source_shelf
    Dir.mktmpdir("nabu-ingest-source") do |root|
      yield Nabu::SourceShelf.new(dir: File.join(root, "canonical", "local-source"))
    end
  end

  def test_scaffold_source_writes_a_parseable_dossier_skeleton
    with_source_shelf do |shelf|
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new,
                                overrides: { "description" => "Latin inscriptions, empire-wide.",
                                             "themes" => "epigraphy, onomastics",
                                             "key_works" => "urn:nabu:edh:hd029093" })
      outcome = engine.scaffold_source("edh", source_shelf: shelf, source_name: "Epigraphic Database Heidelberg")
      assert_equal :added, outcome.status
      dossier = shelf.load("edh")
      assert_equal "Latin inscriptions, empire-wide.", dossier.description
      assert_equal %w[epigraphy onomastics], dossier.themes
      assert_equal %w[urn:nabu:edh:hd029093], dossier.key_works
    end
  end

  def test_scaffold_source_prompts_with_the_source_name_prefilled
    ask = ScriptedAsk.new
    with_source_shelf do |shelf|
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::PromptResolver.new(ask: ask.to_proc))
      engine.scaffold_source("edh", source_shelf: shelf, source_name: "Epigraphic Database Heidelberg")
      assert_equal(%w[description themes key_works], ask.asked.map { |label, _| label.split.first })
      assert_equal "Epigraphic Database Heidelberg", ask.asked.first.last,
                   "the description prompt prefills from the registered source name"
      assert_equal "Epigraphic Database Heidelberg", shelf.load("edh").description
    end
  end

  def test_scaffold_source_is_a_no_op_on_an_existing_dossier
    with_source_shelf do |shelf|
      shelf.write!(Nabu::SourceDossier.new(slug: "edh", description: "Owner-edited."))
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new)
      outcome = engine.scaffold_source("edh", source_shelf: shelf, source_name: "EDH")
      assert_equal :skipped, outcome.status
      assert_match(/dossier exists — edit .*edh\.md/, outcome.message)
      assert_equal "Owner-edited.", shelf.load("edh").description, "the existing dossier is untouched"
    end
  end

  def test_scaffold_source_refuses_a_non_slug_and_a_non_urn_key_work
    with_source_shelf do |shelf|
      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new)
      error = assert_raises(Nabu::ValidationError) do
        engine.scaffold_source("Not A Slug!", source_shelf: shelf)
      end
      assert_match(/not a source slug/, error.message)

      engine = Nabu::Ingest.new(resolver: Nabu::Ingest::AcceptResolver.new,
                                overrides: { "key_works" => "hd029093" })
      error = assert_raises(Nabu::ValidationError) do
        engine.scaffold_source("edh", source_shelf: shelf)
      end
      assert_match(/not a urn/, error.message)
      assert_nil shelf.load("edh"), "an invalid --yes value fails the scaffold before any write"
    end
  end
end
