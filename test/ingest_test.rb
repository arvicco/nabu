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

  def with_rig(resolver: Nabu::Ingest::AcceptResolver.new, overrides: {}, assist_command: nil,
               assist_runner: nil, notify: nil)
    Dir.mktmpdir("nabu-ingest") do |root|
      shelf = Nabu::LibraryShelf.new(dir: File.join(root, "canonical", "local-library"))
      notes = []
      engine = Nabu::Ingest.new(
        shelf: shelf, resolver: resolver, overrides: overrides,
        assist_command: assist_command, assist_runner: assist_runner || Nabu::Ingest::Assist.method(:run),
        pdf_pages: FAKE_PDF_PAGES, pdf_info: FAKE_PDF_INFO,
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
      # An aborted earlier ingest left the copy but no manifest entry.
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

  def test_a_bad_file_is_named_and_the_rest_proceed
    with_rig do |engine, shelf, root|
      good = write_pdf(root, "vaillant-1950-manuel.pdf")
      outcomes = engine.add_files([File.join(root, "ghost.pdf"), good])
      assert_equal %i[failed added], outcomes.map(&:status)
      assert_match(/ghost\.pdf/, outcomes.first.message)
      refute_predicate outcomes.first, :ok?
      assert shelf.manifested?("inbox", "vaillant-1950-manuel.pdf")
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

  def test_an_invalid_license_class_fails_loudly_naming_the_vocabulary
    ask = ScriptedAsk.new("license_class" => "public-domainish")
    with_rig(resolver: Nabu::Ingest::PromptResolver.new(ask: ask.to_proc)) do |engine, _shelf, root|
      outcome = engine.add_files([write_pdf(root, "vaillant-1950-manuel.pdf")]).first
      assert_equal :failed, outcome.status
      assert_match(/license_class must be one of open, attribution, nc, research_private, restricted/,
                   outcome.message)
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
end
