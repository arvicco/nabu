# frozen_string_literal: true

require "json"
require "open3"
require "tmpdir"
require_relative "url_download"
require_relative "library_shelf"
require_relative "language_shelf"
require_relative "language_dossier"
require_relative "pdf_text"
require_relative "adapters/local_library"

module Nabu
  # The intake engine behind `nabu ingest` (P19-5; design: canonical-memory
  # §4b) — the front door for local acquisitions, and the one path that
  # drives the shelves' sanctioned write gateways (LibraryShelf for files,
  # LanguageShelf for dossier scaffolds).
  #
  # == Atomic two-phase intake (P20-1, the GitFetch/ZipFetch phase mirror)
  #
  # A batch either lands WHOLE or leaves canonical/ byte-identical — the
  # owner's doctrine after the 2026-07-14 "chu (body ger)" poisoning
  # incident (a bad languages answer landed in the manifest and every
  # later shelf sync failed until hand-repair). Everything fallible runs
  # in PREPARE, against staging only:
  #
  #   0. stage — urls are downloaded (Nabu::UrlDownload, redirects
  #      followed) into a throwaway staging dir; local paths are
  #      existence-checked and EXECUTABLES REFUSED (mode +x — shelf
  #      material never runs; the live incident catalogued bin/nabu).
  #      All of this BEFORE any categorization: prompts never wait on the
  #      network, and a doomed batch never asks a single question.
  #   1. account — sha256 the source; an identical file already MANIFESTED
  #      in the shelf is an honest no-op (never a second copy).
  #   2. derive — mechanical candidates: PDF Info metadata + first-page
  #      sample via the PdfText seam where mutool exists (degrading
  #      gracefully where not), filename heuristics, the sha.
  #   3. categorize — through the injected RESOLVER (the seam that keeps
  #      all three CLI modes testable): interactive prompts prefilled with
  #      the candidates (invalid answers re-prompt with a one-line reason
  #      — see PromptResolver), an --assist suggestion prefilled the same
  #      way, or --yes flag-driven acceptance (invalid flag values raise,
  #      Ingest.field_error). Nothing lands unresolved or invalid.
  #   4. rehearse — the collection's FUTURE manifest (existing bytes plus
  #      every new entry) is round-tripped through the REAL LibraryManifest
  #      parser against a staging file: an entry the loader would reject
  #      cannot exist, by construction, whatever rule the loader grows.
  #
  # Only when the ENTIRE batch validated does COMMIT touch canonical: per
  # file, LibraryShelf#copy_in! (never move) + append_entry!; a freak
  # append failure rolls that file's copy back (compensating delete) so
  # canonical never keeps a stray. Any prepare defect instead aborts the
  # WHOLE batch: one named :failed outcome per defect, every other file
  # :aborted, nothing written. The residual crash window is a hard kill
  # between copy and append — the next sync's discovery census names the
  # stray LOUDLY as unmanifested.
  #
  # The caller (the CLI) then runs the shelf's ordinary sync — which, by
  # construction, cannot reject what the same validator passed — and
  # prints the minted urns; the engine itself never touches a database.
  class Ingest
    DEFAULT_COLLECTION = "inbox"

    # The manifest lanes ingest categorizes, in manifest order.
    LIBRARY_FIELDS = %w[title creator year languages tags related provenance license_class].freeze
    # The dossier lanes the --shelf language scaffold asks for.
    LANGUAGE_FIELDS = %w[name family context].freeze
    # List-valued lanes (comma-joined on prompts and flags).
    LIST_FIELDS = %w[languages tags related].freeze

    # Cap on the first-page sample piped to an assist command.
    SAMPLE_CHARS = 2000
    # Extensions read as born-digital text for the sample.
    TEXT_EXTENSIONS = Adapters::LocalLibrary::TEXT_EXTENSIONS

    # One field the resolver decides: its manifest key, the prompt label,
    # and the prefilled candidate (derived < assist < flags).
    Field = Data.define(:key, :label, :default)

    # What one ingested file (or one scaffolded dossier) came to:
    # +status+ ∈ :added, :revised, :skipped, :failed, :aborted (valid but
    # not landed — another file's defect aborted the batch); +urn+/+entry+
    # nil except on :added (+search_term+ is an extracted-text word for the
    # epilogue's search hint, nil when the file yielded no real word).
    Outcome = Data.define(:file, :status, :message, :urn, :entry, :search_term) do
      def initialize(file:, status:, message:, urn: nil, entry: nil, search_term: nil) = super
      def ok? = status != :failed
    end

    # One staged intake item: the local path the pipeline reads and, for a
    # url argument, the ORIGINAL url the owner gave (nil for local files —
    # mirror-node final urls rotate; the given url is the stable identity).
    Staged = Data.define(:path, :source_url) do
      def file = File.basename(path)
    end

    # One validated intake plan awaiting commit (P20-1): everything the
    # commit phase needs, prepared with ZERO canonical writes. +action+ ∈
    # :catalogue (new file: copy + append) or :revise (manifested name,
    # new bytes: copy replacement only); +entry+/+sample+ nil on :revise.
    Plan = Data.define(:action, :path, :file, :entry, :sample) do
      def initialize(action:, path:, file:, entry: nil, sample: nil) = super
    end

    # -- the shared field-validity rule (P20-1) --------------------------------

    # One place answers "is this resolved value valid for KEY?" for both
    # halves of the categorization seam: PromptResolver re-prompts on the
    # returned reason; build_entry raises it, so --yes/--assist fail the
    # FILE pre-append. nil means valid. Language tags reuse THE MODEL'S
    # shape rule (Model::Validation::LANGUAGE_SHAPE) — the manifest can
    # never accept what the loader rejects (the "chu (body ger)" incident).
    def self.field_error(key, value)
      case key
      when "languages"
        bad = coerce_list(value).find { |tag| !tag.match?(Model::Validation::LANGUAGE_SHAPE) }
        "#{bad.inspect} is not a language tag — give comma-separated codes like: chu, deu" if bad
      when "license_class"
        klass = value.to_s.strip
        unless klass.empty? || Model::Validation::LICENSE_CLASSES.include?(klass)
          "license_class must be one of #{Model::Validation::LICENSE_CLASSES.join(', ')}, got #{klass.inspect}"
        end
      end
    end

    # List lanes arrive as Arrays (candidates/assist) or comma strings
    # (prompt answers, flags) — one splitter for validation and assembly.
    def self.coerce_list(value)
      case value
      when nil then []
      when Array then value.map(&:to_s).map(&:strip).reject(&:empty?)
      else value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end

    # -- the resolvers (the categorization seam) ------------------------------

    # --yes: accept every prefilled candidate unprompted (flags already rode
    # in as overrides).
    class AcceptResolver
      def resolve(fields)
        fields.to_h { |field| [field.key, field.default] }
      end
    end

    # Interactive: one prompt per field, candidate prefilled; Enter keeps
    # the default, "-" clears a field. An INVALID answer (Ingest.field_error)
    # re-prompts with a one-line reason via +warn+ until valid or cleared —
    # categorization can never hand the pipeline a value the manifest would
    # reject (P20-1). +ask+ is injectable ((label, default) → String) so the
    # flow tests without a TTY; the CLI wires Thor's ask and a say-based warn.
    class PromptResolver
      CLEAR = "-"

      def initialize(ask:, warn: ->(line) { Kernel.warn("  ! #{line}") })
        @ask = ask
        @warn = warn
      end

      def resolve(fields)
        fields.to_h { |field| [field.key, resolve_field(field)] }
      end

      private

      def resolve_field(field)
        loop do
          answer = @ask.call(field.label, prompt_default(field.default)).to_s.strip
          return nil if answer == CLEAR

          value = answer.empty? ? field.default : answer
          error = Ingest.field_error(field.key, value)
          return value if error.nil?

          @warn.call(error)
        end
      end

      def prompt_default(default)
        default.is_a?(Array) ? default.join(", ") : default
      end
    end

    # -- the assist subprocess (the P18-7 ReviewHook pattern) -----------------

    # `--assist CMD`: pipe a JSON brief (schema nabu.ingest-assist/1 —
    # derived candidates + first-page sample) to CMD's stdin and parse a
    # suggested entry from its stdout. Tool-agnostic subprocess boundary:
    # the bundled script/ingest-assist-claude wires `claude -p`, but nabu
    # neither knows nor cares. A suggestion only ever PREFILLS the resolver
    # — AI suggests, the owner confirms (unless --yes was an explicit
    # decision to accept unreviewed). Failure is advisory: no suggestion,
    # honest note, mechanical candidates stand.
    module Assist
      SCHEMA = "nabu.ingest-assist/1"

      Result = Data.define(:status, :suggestion, :output) do
        def ok? = !status.nil? && status.zero? && !suggestion.nil?
      end

      module_function

      # stdout carries the suggestion; stderr is relayed as diagnostics
      # (capture3, not 2e — a chatty tool must not corrupt its own JSON).
      def run(command:, brief:)
        stdout, stderr, status = Open3.capture3(command, stdin_data: JSON.generate(brief))
        Result.new(status: status.exitstatus, suggestion: parse(stdout), output: stderr)
      rescue SystemCallError => e
        Result.new(status: nil, suggestion: nil, output: e.message)
      end

      # Lenient parse: the whole stdout as JSON, else the outermost {...}
      # span (models wrap JSON in prose); anything but an object is nil.
      def parse(stdout)
        object = JSON.parse(stdout)
        object.is_a?(Hash) ? object : nil
      rescue JSON::ParserError
        span = stdout[/\{.*\}/m]
        span ? parse(span) : nil
      end
    end

    # +resolver+ decides the final fields (see above); +assist_command+ (with
    # its injectable +assist_runner+) is optional; +pdf_pages+/+pdf_info+ are
    # the PdfText seams (tests inject fakes — the suite never needs mutool);
    # +download+ is the url seam (defaults to the real cert-hardened
    # UrlDownload; tests inject fakes or stub with WebMock); +overrides+ are
    # the CLI flag values (they beat assist beats derived); +notify+
    # receives advisory one-liners (assist failures, degrades, downloads).
    def initialize(resolver:, shelf: nil, assist_command: nil, assist_runner: Assist.method(:run),
                   pdf_pages: PdfText.method(:pages), pdf_info: PdfText.method(:info),
                   download: nil, overrides: {}, notify: ->(_line) {}, now: Time.now)
      @shelf = shelf
      @resolver = resolver
      @assist_command = assist_command
      @assist_runner = assist_runner
      @pdf_pages = pdf_pages
      @pdf_info = pdf_info
      @download = download || UrlDownload.new
      @overrides = overrides
      @notify = notify
      @now = now
    end

    # Ingest +paths+ (local files or http(s) urls) into +collection+,
    # ATOMICALLY (class comment): prepare everything against staging, then
    # commit the whole batch or nothing. Returns one Outcome per argument,
    # in order; any prepare defect keeps its named :failed outcome and
    # turns every would-land file :aborted — canonical is byte-identical
    # to before the run. The staging dir dissolves afterwards — the shelf
    # copy (commit phase only) is the record.
    def add_files(paths, collection: DEFAULT_COLLECTION)
      Dir.mktmpdir("nabu-ingest") do |staging_dir|
        staged = stage(paths, staging_dir)
        # A staging defect is already fatal to the batch: abort before any
        # categorization — never prompt for a batch that cannot land.
        return abort_batch(staged) if staged.any? { |item| failed?(item) }

        plans = staged.map { |item| prepare(item, collection) }
        rehearse!(plans, collection, staging_dir)
        return abort_batch(plans) if plans.any? { |item| failed?(item) }

        plans.map { |plan| plan.is_a?(Outcome) ? plan : commit(plan, collection) }
      end
    end

    # --shelf language CODE: scaffold a dossier skeleton (front matter +
    # context prose) through LanguageShelf, the shelf's own gateway. THIN by
    # design — a scaffold, not an editor: an existing dossier is an honest
    # no-op pointing at the file.
    def scaffold_language(code, language_shelf:)
      raise ValidationError, "#{code.inspect} is not a language code (chu, zle-ort, ine-pro…)" \
        unless "#{code}.md".match?(Adapters::LocalLanguage::DOSSIER_FILE)

      path = language_shelf.path_for(code)
      if language_shelf.load(code)
        return Outcome.new(file: code, status: :skipped,
                           message: "dossier exists — edit #{path}, then bin/nabu sync local-language")
      end

      fields = apply_suggestions(language_fields(code), language_brief(code))
      values = @resolver.resolve(fields)
      language_shelf.write!(LanguageDossier.new(code: code, name: presence(values["name"]),
                                                family: presence(values["family"]),
                                                context: presence(values["context"])))
      Outcome.new(file: code, status: :added, message: "dossier scaffolded at #{path}")
    end

    private

    # -- prepare (steps 0–4): everything fallible, zero canonical writes --------

    def stage(paths, staging_dir)
      paths.map do |path|
        if UrlDownload.url?(path)
          @notify.call("downloading #{path}")
          Staged.new(path: @download.fetch(path, dir: staging_dir), source_url: path)
        else
          raise Errno::ENOENT, path unless File.file?(path)
          if executable?(path)
            raise ValidationError,
                  "#{File.basename(path)} is executable (mode +x) — refusing; shelf material never runs"
          end

          Staged.new(path: path, source_url: nil)
        end
      rescue Nabu::Error, Errno::ENOENT, Errno::EACCES => e
        Outcome.new(file: File.basename(path), status: :failed, message: e.message)
      end
    end

    # Any x-bit refuses (the live incident catalogued bin/nabu itself):
    # there is no legitimate executable shelf material.
    def executable?(path)
      File.stat(path).mode.anybits?(0o111)
    end

    # Account + derive + categorize + build ONE file's entry — reads only;
    # a defect (a bad --yes flag value, an unreadable source) is a named
    # :failed outcome that will abort the batch. Interactive resolvers
    # cannot fail here: PromptResolver re-prompts until valid.
    def prepare(staged, collection)
      file = staged.file
      duplicate = manifested_duplicate(LibraryShelf.sha256(staged.path))
      if duplicate
        return Outcome.new(file: file, status: :skipped,
                           message: "identical bytes already catalogued at #{duplicate} — no-op")
      end
      return Plan.new(action: :revise, path: staged.path, file: file) if @shelf.manifested?(collection, file)

      candidates, sample = derive(staged.path, file, source_url: staged.source_url)
      fields = apply_suggestions(library_fields(candidates),
                                 library_brief(collection, file, candidates, sample))
      entry = build_entry(file, @resolver.resolve(fields), source_url: staged.source_url)
      Plan.new(action: :catalogue, path: staged.path, file: file, entry: entry, sample: sample)
    rescue Nabu::Error, Errno::ENOENT, Errno::EACCES => e
      Outcome.new(file: file, status: :failed, message: e.message)
    end

    # The rehearsal (step 4): round-trip the collection's FUTURE manifest —
    # existing bytes plus every new entry, cumulatively so a defect names
    # its plan — through the REAL parser, against a staging file. What the
    # loader would reject cannot reach commit, whatever rules the loader
    # grows; intra-batch duplicates surface here too.
    def rehearse!(plans, collection, staging_dir)
      entries = []
      rehearsal = File.join(staging_dir, "manifest-rehearsal.yml")
      plans.map! do |plan|
        next plan unless plan.is_a?(Plan) && plan.action == :catalogue

        entries << plan.entry
        File.write(rehearsal, @shelf.future_manifest(collection, entries))
        begin
          LibraryManifest.load(rehearsal)
          plan
        rescue LibraryManifest::FormatError => e
          entries.pop
          Outcome.new(file: plan.file, status: :failed,
                      message: e.message.sub("#{rehearsal}: ", "manifest rehearsal: "))
        end
      end
    end

    # The owner's all-or-nothing doctrine: defects stay named :failed,
    # honest no-ops stay :skipped (they never write anyway), and every
    # file that WOULD have landed becomes :aborted — canonical untouched.
    def abort_batch(items)
      items.map do |item|
        next item if item.is_a?(Outcome) && %i[failed skipped].include?(item.status)

        Outcome.new(file: item.file, status: :aborted,
                    message: "not ingested — batch aborted, canonical untouched")
      end
    end

    def failed?(item)
      item.is_a?(Outcome) && item.status == :failed
    end

    # -- commit: the only canonical writes, all pre-validated --------------------

    # :revise — same name, already manifested, new bytes: replace the copy
    # and let the loader's normal revision machinery record it at sync (the
    # manifest entry stands; metadata edits are manifest edits, not
    # re-ingests). :catalogue — copy + append; a freak append failure
    # (validated content, so IO-shaped only) rolls the copy back: canonical
    # never keeps a stray.
    def commit(plan, collection)
      file = plan.file
      @shelf.copy_in!(plan.path, collection: collection)
      if plan.action == :revise
        return Outcome.new(file: file, status: :revised,
                           message: "same name, new content — copy replaced; sync records a revision " \
                                    "(metadata edits go in #{@shelf.manifest_path(collection)})")
      end

      begin
        @shelf.append_entry!(collection: collection, entry: plan.entry)
      rescue Nabu::Error => e
        @shelf.remove_copy!(collection: collection, file: file)
        return Outcome.new(file: file, status: :failed, message: "#{e.message} — copy rolled back")
      end
      Outcome.new(file: file, status: :added, message: "→ #{collection}/#{file}",
                  urn: Adapters::LocalLibrary.urn_for(collection, file),
                  entry: plan.entry, search_term: search_term(plan.sample))
    end

    # The sha's existing home, when that home is MANIFESTED (an unmanifested
    # identical copy — an aborted earlier ingest — must not block the
    # resume; the census already flags it).
    def manifested_duplicate(sha)
      rel = @shelf.sha_index[sha]
      return nil if rel.nil?

      collection, file = rel.split(File::SEPARATOR, 2)
      file && @shelf.manifested?(collection, file) ? rel : nil
    end

    # -- derivation (mechanical candidates) ------------------------------------

    # The provenance candidate names where the copy REALLY came from: the
    # original url for a download (the staging path is ephemeral), the
    # expanded local path otherwise — and it also surfaces the url in the
    # categorize display without a prompt of its own (the source_url lane
    # is recorded mechanically).
    def derive(path, file, source_url: nil)
      candidates = filename_candidates(file)
      sample = nil
      case File.extname(file).downcase
      when ".pdf"
        merge_pdf_candidates!(candidates, path)
        sample = pdf_sample(path)
      when *TEXT_EXTENSIONS
        sample = File.read(path, encoding: "UTF-8").scrub("\u{FFFD}")[0, SAMPLE_CHARS]
      end
      candidates["provenance"] = "ingested #{@now.strftime('%Y-%m-%d')} from #{source_url || File.expand_path(path)}"
      [candidates, sample]
    end

    # PDF Info Title/Author beat the filename guesses (authored metadata),
    # but the Info YEAR only fills absence: CreationDate on a scan is the
    # scan date, while a year in a scholarly `author-year-title` filename is
    # the publication year, named deliberately.
    def merge_pdf_candidates!(candidates, path)
      info = pdf_candidates(path)
      filename_year = candidates["year"]
      candidates.merge!(info)
      candidates["year"] = filename_year if filename_year
    end

    # vaillant-1950-manuel.pdf → year 1950, title "vaillant 1950 manuel",
    # creator "Vaillant" (the leading token, only when a year anchors the
    # scholarly-filename shape). Candidates, not claims — the resolver shows
    # them for confirmation.
    def filename_candidates(file)
      stem = File.basename(file, ".*")
      year = stem[/(?<!\d)(1[4-9]\d\d|20\d\d)(?!\d)/]&.to_i
      candidates = { "title" => stem.tr("-_", "  ").squeeze(" ").strip }
      candidates["year"] = year if year
      lead = stem[/\A[[:alpha:]]{3,}/]
      candidates["creator"] = lead.capitalize if year && lead
      candidates
    end

    def pdf_candidates(path)
      @pdf_info.call(path)
    end

    def pdf_sample(path)
      first = @pdf_pages.call(path).find { |page| !page.strip.empty? }
      first&.slice(0, SAMPLE_CHARS)
    rescue PdfText::Error => e
      @notify.call("note: no text sample (#{e.message}) — filename candidates stand")
      nil
    end

    # A word of extracted text for the epilogue's search hint (title words
    # live in metadata, not passages — only real text is searchable). The
    # first ALPHABETIC word of length ≥ 4 — Unicode letters, so Greek and
    # Cyrillic count, while digit/symbol-riddled OCR junk ("01assJ£", the
    # live Leskien smoke) never becomes the hint; no real word, no hint
    # (the epilogue omits it on nil).
    def search_term(sample)
      sample.to_s.split(/\s+/)
            .map { |token| token.gsub(/\A[[:punct:]]+|[[:punct:]]+\z/, "") }
            .find { |word| word.length >= 4 && word.match?(/\A[[:alpha:]]+\z/) }
    end

    # -- fields, assist, entry assembly ----------------------------------------

    def library_fields(candidates)
      merged = candidates.merge(compact_overrides)
      LIBRARY_FIELDS.map do |key|
        default = merged.fetch(key, LIST_FIELDS.include?(key) ? [] : nil)
        default = LibraryManifest::DEFAULT_LICENSE_CLASS if key == "license_class" && default.nil?
        Field.new(key: key, label: field_label(key), default: default)
      end
    end

    def language_fields(code)
      family = code[/\A([a-z]{2,3})-/, 1]
      defaults = { "family" => family }.merge(compact_overrides)
      LANGUAGE_FIELDS.map do |key|
        Field.new(key: key, label: "#{key} (dossier front matter#{' — free prose' if key == 'context'})",
                  default: defaults[key])
      end
    end

    # The license default is STATED at the prompt — the shelf's whole
    # licensing doctrine in one label.
    def field_label(key)
      case key
      when "license_class"
        "license_class (#{Model::Validation::LICENSE_CLASSES.join(', ')}; default research_private " \
        "= never served or redistributed)"
      when *LIST_FIELDS then "#{key} (comma-separated)"
      else key
      end
    end

    def compact_overrides
      @overrides.compact
    end

    # Run the assist hook (when configured) and prefill its suggestion into
    # the fields — flags still win (they were merged first and a flag lane
    # is an explicit owner decision).
    def apply_suggestions(fields, brief)
      return fields if @assist_command.nil?

      result = @assist_runner.call(command: @assist_command, brief: brief)
      result.output.to_s.each_line { |line| @notify.call("assist| #{line.chomp}") }
      unless result.ok?
        status = result.status ? "exit #{result.status}" : "could not start"
        @notify.call("assist: #{status}, no usable suggestion — mechanical candidates stand")
        return fields
      end
      fields.map do |field|
        value = @overrides.key?(field.key) ? nil : result.suggestion[field.key]
        value.nil? ? field : Field.new(key: field.key, label: field.label, default: value)
      end
    end

    def library_brief(collection, file, candidates, sample)
      {
        schema: Assist::SCHEMA, shelf: "library", collection: collection, file: file,
        derived: candidates, sample: sample,
        fields: LIBRARY_FIELDS, list_fields: LIST_FIELDS,
        license_classes: Model::Validation::LICENSE_CLASSES,
        license_default: LibraryManifest::DEFAULT_LICENSE_CLASS
      }
    end

    def language_brief(code)
      { schema: Assist::SCHEMA, shelf: "language", code: code, fields: LANGUAGE_FIELDS }
    end

    # Resolved values → the manifest entry: keys in manifest order, lists
    # split, year coerced, languages + license validated (Ingest.field_error
    # — the interactive resolver already re-prompted these, so a raise here
    # means a --yes/--assist value, failing the FILE before any append),
    # empty lanes omitted — and the research_private DEFAULT omitted too
    # (manifest silence means the conservative class; an explicit class
    # marks an owner override). +source_url+ (a url ingest's original url)
    # is recorded mechanically, never prompted; local ingests get no such
    # lane.
    def build_entry(file, values, source_url: nil)
      entry = { "file" => file }
      title = presence(values["title"])
      entry["title"] = title if title
      creator = presence(values["creator"])
      entry["creator"] = creator if creator
      year = coerce_year(values["year"])
      entry["year"] = year if year
      LIST_FIELDS.each do |key|
        list = self.class.coerce_list(values[key])
        error = self.class.field_error(key, list)
        raise ValidationError, error if error

        entry[key] = list unless list.empty?
      end
      provenance = presence(values["provenance"])
      entry["provenance"] = provenance if provenance
      entry["source_url"] = source_url if source_url
      entry["license_class"] = validate_license!(values["license_class"])
      entry.compact
    end

    def coerce_year(value)
      return value if value.nil? || value.is_a?(Integer)

      text = value.to_s.strip
      return nil if text.empty?
      raise ValidationError, "year must be a number, got #{text.inspect}" unless text.match?(/\A\d{1,4}\z/)

      text.to_i
    end

    def validate_license!(value)
      klass = presence(value) || LibraryManifest::DEFAULT_LICENSE_CLASS
      error = self.class.field_error("license_class", klass)
      raise ValidationError, error if error

      klass == LibraryManifest::DEFAULT_LICENSE_CLASS ? nil : klass
    end

    def presence(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
