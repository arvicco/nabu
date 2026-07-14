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
  # LanguageShelf for dossier scaffolds). Per file, in the design's order:
  #
  #   0. stage — a distinct FIRST pass over the whole batch (P20-0): url
  #      arguments are downloaded (Nabu::UrlDownload, redirects followed)
  #      into a throwaway staging dir and local paths existence-checked,
  #      all BEFORE any categorization — an interactive header can never
  #      precede a failure, and prompts never wait on the network. For a
  #      url the staging copy is the original (the shelf copies it in;
  #      the manifest entry records the owner's url in a source_url lane).
  #   1. account — sha256 the source; an identical file already MANIFESTED
  #      in the shelf is an honest no-op (never a second copy).
  #   2. copy — LibraryShelf#copy_in! (never move; same name over new
  #      content is the loader's normal revision story).
  #   3. derive — mechanical candidates: PDF Info metadata + first-page
  #      sample via the PdfText seam where mutool exists (degrading
  #      gracefully where not), filename heuristics, the sha.
  #   4. categorize — through the injected RESOLVER (the seam that keeps
  #      all three CLI modes testable): interactive prompts prefilled with
  #      the candidates, an --assist suggestion prefilled the same way, or
  #      --yes flag-driven acceptance. Nothing lands unresolved.
  #   5. append — one manifest entry, mechanically, append-only.
  #
  # The caller (the CLI) then runs the shelf's ordinary sync and prints the
  # minted urns — the engine itself never touches a database.
  #
  # Partial-failure honesty: each file's defect (missing, unreadable, a bad
  # field) becomes a named :failed outcome; the remaining files proceed.
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
    # +status+ ∈ :added, :revised, :skipped, :failed; +urn+/+entry+ nil
    # except on :added (+search_term+ is an extracted-text word for the
    # epilogue's search hint, nil when the file yielded no text).
    Outcome = Data.define(:file, :status, :message, :urn, :entry, :search_term) do
      def initialize(file:, status:, message:, urn: nil, entry: nil, search_term: nil) = super
      def ok? = status != :failed
    end

    # One staged intake item: the local path the pipeline reads and, for a
    # url argument, the ORIGINAL url the owner gave (nil for local files —
    # mirror-node final urls rotate; the given url is the stable identity).
    Staged = Data.define(:path, :source_url)

    # -- the resolvers (the categorization seam) ------------------------------

    # --yes: accept every prefilled candidate unprompted (flags already rode
    # in as overrides).
    class AcceptResolver
      def resolve(fields)
        fields.to_h { |field| [field.key, field.default] }
      end
    end

    # Interactive: one prompt per field, candidate prefilled; Enter keeps
    # the default, "-" clears a field. +ask+ is injectable ((label, default)
    # → String) so the flow tests without a TTY; the CLI wires Thor's ask.
    class PromptResolver
      CLEAR = "-"

      def initialize(ask:)
        @ask = ask
      end

      def resolve(fields)
        fields.to_h do |field|
          answer = @ask.call(field.label, prompt_default(field.default)).to_s.strip
          value = answer.empty? ? field.default : answer
          [field.key, answer == CLEAR ? nil : value]
        end
      end

      private

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

    # Ingest +paths+ (local files or http(s) urls) into +collection+.
    # Returns one Outcome per argument, in order; a bad item is a named
    # :failed outcome and the rest proceed. The staging pass runs FIRST for
    # the whole batch (class comment, step 0); the staging dir dissolves
    # afterwards — the shelf copy is the record.
    def add_files(paths, collection: DEFAULT_COLLECTION)
      Dir.mktmpdir("nabu-ingest") do |staging_dir|
        stage(paths, staging_dir).map do |item|
          next item if item.is_a?(Outcome)

          begin
            add_file(item.path, collection, source_url: item.source_url)
          rescue Nabu::Error, Errno::ENOENT, Errno::EACCES => e
            Outcome.new(file: File.basename(item.path), status: :failed, message: e.message)
          end
        end
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

    # -- staging (step 0): every argument settled before any prompt -------------

    def stage(paths, staging_dir)
      paths.map do |path|
        if UrlDownload.url?(path)
          @notify.call("downloading #{path}")
          Staged.new(path: @download.fetch(path, dir: staging_dir), source_url: path)
        else
          raise Errno::ENOENT, path unless File.file?(path)

          Staged.new(path: path, source_url: nil)
        end
      rescue Nabu::Error, Errno::ENOENT, Errno::EACCES => e
        Outcome.new(file: File.basename(path), status: :failed, message: e.message)
      end
    end

    # -- the per-file pipeline -------------------------------------------------

    def add_file(path, collection, source_url: nil)
      raise Errno::ENOENT, path unless File.file?(path)

      file = File.basename(path)
      sha = LibraryShelf.sha256(path)
      duplicate = manifested_duplicate(sha)
      if duplicate
        return Outcome.new(file: file, status: :skipped,
                           message: "identical bytes already catalogued at #{duplicate} — no-op")
      end
      return revise(path, collection, file) if @shelf.manifested?(collection, file)

      catalogue(path, collection, file, source_url: source_url)
    end

    # Same name, already manifested, new bytes: overwrite the copy and let
    # the loader's normal revision machinery record it at sync. The manifest
    # entry stands (metadata edits are manifest edits, not re-ingests).
    def revise(path, collection, file)
      @shelf.copy_in!(path, collection: collection)
      Outcome.new(file: file, status: :revised,
                  message: "same name, new content — copy replaced; sync records a revision " \
                           "(metadata edits go in #{@shelf.manifest_path(collection)})")
    end

    def catalogue(path, collection, file, source_url: nil)
      @shelf.copy_in!(path, collection: collection)
      candidates, sample = derive(path, file, source_url: source_url)
      fields = apply_suggestions(library_fields(candidates),
                                 library_brief(collection, file, candidates, sample))
      entry = build_entry(file, @resolver.resolve(fields), source_url: source_url)
      @shelf.append_entry!(collection: collection, entry: entry)
      Outcome.new(file: file, status: :added, message: "→ #{collection}/#{file}",
                  urn: Adapters::LocalLibrary.urn_for(collection, file),
                  entry: entry, search_term: search_term(sample))
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
    # live in metadata, not passages — only real text is searchable).
    def search_term(sample)
      sample.to_s.split(/\s+/).map { |word| word.gsub(/[[:punct:]]/, "") }
                              .find { |word| word.length >= 4 }
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
    # split, year coerced, license validated, empty lanes omitted — and the
    # research_private DEFAULT omitted too (manifest silence means the
    # conservative class; an explicit class marks an owner override).
    # +source_url+ (a url ingest's original url) is recorded mechanically,
    # never prompted; local ingests get no such lane.
    def build_entry(file, values, source_url: nil)
      entry = { "file" => file }
      title = presence(values["title"])
      entry["title"] = title if title
      creator = presence(values["creator"])
      entry["creator"] = creator if creator
      year = coerce_year(values["year"])
      entry["year"] = year if year
      LIST_FIELDS.each do |key|
        list = coerce_list(values[key])
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

    def coerce_list(value)
      case value
      when nil then []
      when Array then value.map(&:to_s).map(&:strip).reject(&:empty?)
      else value.to_s.split(",").map(&:strip).reject(&:empty?)
      end
    end

    def validate_license!(value)
      klass = presence(value) || LibraryManifest::DEFAULT_LICENSE_CLASS
      unless Model::Validation::LICENSE_CLASSES.include?(klass)
        raise ValidationError, "license_class must be one of " \
                               "#{Model::Validation::LICENSE_CLASSES.join(', ')}, got #{klass.inspect}"
      end
      klass == LibraryManifest::DEFAULT_LICENSE_CLASS ? nil : klass
    end

    def presence(value)
      text = value.to_s.strip
      text.empty? ? nil : text
    end
  end
end
