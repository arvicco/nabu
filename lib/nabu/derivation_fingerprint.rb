# frozen_string_literal: true

require "digest"
require "json"

require_relative "normalize"

module Nabu
  # Per-source derivation fingerprint (P36-1): the honest identity behind
  # `rebuild --incremental`. A source may be SKIPPED by an incremental rebuild
  # only when every input that could change its derived rows is provably
  # unchanged. The inputs (the four-input rule, plus the registry posture):
  #
  # 1. canonical bytes — for git-backed trees the HEAD sha per embedded repo
  #    (plus the content of the git-excluded `.attic/`, which is canonical
  #    data git cannot vouch for); for everything else (zip/file fetches,
  #    local shelves) a sha256 over every file's bytes. A git tree with
  #    non-attic local modifications has NO honest identity: HEAD no longer
  #    names the bytes on disk, so the identity is WEAK (nil) and the source
  #    is never skipped. Over-rebuilding is safe; under-rebuilding is the sin.
  # 2. parser/pipeline code — a digest of the adapter's file closure within
  #    lib/nabu/adapters/ (constant-reference BFS, see #parser_files) plus the
  #    shared derivation core (loaders, indexers, models, script helpers).
  # 3. fold rules — LANGUAGE-SCOPED since P39-1: a token list of
  #    lib/nabu/normalize.rb (the wiring — NFC, diacritic folds,
  #    LANGUAGE_FOLDS, search_form; global on purpose, rare changes) PLUS the
  #    generated fold-table modules (hani.rb/jpn.rb) the source's derived
  #    rows actually consult, per the declared FOLD_LANGUAGES map. A source
  #    whose language set is unknowable consults ALL modules (dirty-more).
  #    Before P39-1 a single normalize.rb digest dirtied every source; then
  #    P38's Japanese-only fold change flipped all 86 registry rows dirty and
  #    turned the owner's incremental into a full 3.5 h rebuild. File digests
  #    are chosen over hand-bumped version constants: they cannot be
  #    forgotten.
  # 4. schema — the latest migration number the running code carries.
  # 5. the entry's derivation-shaping registry flags (translations, classes,
  #    lemma_tier, fuzzy_index): they change derived rows with no byte or
  #    code change, so they are part of the stamp (stored as plain JSON,
  #    self-explanatory in the db).
  #
  # DOCUMENTED LIMITS (over-rebuild-safe by refusal elsewhere, but honest):
  # gem upgrades (nokogiri et al.) and Ruby upgrades are not fingerprinted —
  # full rebuild remains the reference after toolchain changes.
  class DerivationFingerprint
    SEPARATOR = "\x1f"

    LIB_DIR = File.expand_path(__dir__)
    ADAPTERS_DIR = File.join(LIB_DIR, "adapters")
    FOLD_RULES_PATH = File.join(LIB_DIR, "normalize.rb")

    # The generated fold-table modules (P39-1). Excluded from the shared core
    # BECAUSE they are covered here per-source — the asymmetry doctrine's one
    # sanctioned exit: a module may leave the global digest only when the
    # scoped mechanism provably covers it (test-pinned: every name below is
    # in EXCLUDED_FILES, has a path, and is consulted by >= 1 language).
    FOLD_MODULE_PATHS = {
      "hani.rb" => File.join(LIB_DIR, "hani.rb"),
      "jpn.rb" => File.join(LIB_DIR, "jpn.rb")
    }.freeze

    # Which fold modules a language's search_form consults (primary subtag,
    # exactly like Normalize::LANGUAGE_FOLDS). Explicit, not clever: this is
    # a declared census, extended by hand when a fold module or language
    # lands. jpn lists hani.rb too because the generated jpn table composes
    # THROUGH Hani.fold at `rake fold:jpn` time — a hani change stales jpn's
    # skeletons even though Jpn.fold never calls Hani at runtime. Languages
    # not listed (grc, lat, ...) consult only the normalize.rb wiring.
    FOLD_LANGUAGES = {
      "lzh" => %w[hani.rb],
      "och" => %w[hani.rb],
      "jpn" => %w[jpn.rb hani.rb]
    }.freeze

    # The shared derivation core is EVERYTHING under lib/nabu/ except
    # adapters/ (covered per-source by the closure), normalize.rb (input 3),
    # hani.rb/jpn.rb (the fold-table modules — covered per-source by the
    # language-scoped fold digest, FOLD_MODULE_PATHS above; P39-1), and this
    # exclusion list of provably read-only / non-derivation code. The failure
    # modes are asymmetric: forgetting to exclude a file only over-rebuilds
    # (safe); an include-list that missed one would silently under-rebuild
    # (the sin). When in doubt, a file stays IN.
    EXCLUDED_DIRS = %w[adapters mcp query health ops].freeze
    EXCLUDED_FILES = %w[
      cli.rb display.rb status_report.rb progress_reporter.rb version.rb
      backup.rb review_hook.rb verify.rb fixture_sentinel.rb
      batch_cognates.rb batch_formulas.rb batch_parallels.rb
      suttacentral_parallels.rb library_references.rb corph_dil_references.rb
      ccl_etymologies.rb
      git_fetch.rb zip_fetch.rb file_fetch.rb lfs_fetch.rb wiki_fetch.rb
      kanripo_fetch.rb sefaria_fetch.rb local_fetch.rb url_download.rb
      redirect_follow.rb
      sync_runner.rb source_registry.rb axis_registry.rb config.rb
      ingest.rb language_shelf.rb library_shelf.rb source_shelf.rb
      note_shelf.rb
      normalize.rb
      hani.rb jpn.rb
    ].freeze

    # Namespace wrappers every adapter file opens — as "definitions" they
    # would make every file define (and reference) the same names, collapsing
    # the parser closure to the whole directory.
    NAMESPACE_NAMES = %w[Nabu Adapters].freeze

    # One source's computed fingerprint. +combined+ is the stored identity;
    # nil when the canonical identity is weak (such a source never skips).
    Fingerprint = Data.define(:canonical_identity, :parser_digest, :fold_digest,
                              :migration_level, :config_json) do
      def weak? = canonical_identity.nil?

      def combined
        return nil if weak?

        Digest::SHA256.hexdigest(
          [canonical_identity, parser_digest, fold_digest,
           migration_level.to_s, config_json].join(SEPARATOR)
        )
      end

      def short = combined&.slice(0, 12)

      # Why this fingerprint is not clean against +stamp+ (a derivation_stamps
      # row hash, or nil when unstamped): the first differing component in
      # blame order, or nil when the stamp matches. Weak identity blames
      # itself — it can never be clean.
      def drift_against(stamp)
        return :weak_identity if weak?
        return :unstamped if stamp.nil?
        return nil if stamp[:fingerprint] == combined
        return :migration if stamp[:migration_level] != migration_level
        return :canonical if stamp[:canonical_identity] != canonical_identity
        return :parser if stamp[:parser_digest] != parser_digest
        return :fold if stamp[:fold_digest] != fold_digest

        :config
      end

      # The fold files whose identity drifted against +stamp+ — what the
      # owner's dirty line names (`fold(jpn.rb)` vs the old opaque `fold`).
      # A pre-P39-1 stamp carries one bare sha (no name:sha tokens): every
      # currently consulted file is blamed, and `rake stamps:rebless` — not
      # silent acceptance — migrates the stamp.
      def fold_blame(stamp)
        mine = DerivationFingerprint.fold_tokens(fold_digest)
        theirs = DerivationFingerprint.fold_tokens(stamp && stamp[:fold_digest])
        (mine.keys | theirs.keys).reject { |name| mine[name] == theirs[name] }.sort
      end
    end

    def initialize(config:)
      @config = config
      @file_tokens = {}
      @references = {}
    end

    # Compute the full fingerprint for one registry +entry+. +languages+ is
    # the source's derived-row language census (Store::DerivationStamp
    # .derived_languages) scoping the fold digest; nil — the default, and the
    # census's own "cannot answer" — means unknowable, which consults EVERY
    # fold module (dirty-more, never dirty-less).
    def for_source(entry, languages: nil)
      Fingerprint.new(
        canonical_identity: self.class.canonical_identity(File.join(@config.canonical_dir, entry.slug)),
        parser_digest: parser_digest(entry),
        fold_digest: self.class.fold_digest(languages),
        migration_level: self.class.migration_level,
        config_json: self.class.config_json(entry)
      )
    end

    # The adapter's code closure within lib/nabu/adapters/: starting from the
    # file(s) defining the adapter's terminal constant, follow every
    # referenced constant that is itself defined in adapters/ (BFS). This
    # catches composition WITHOUT require_relative (Perseus references
    # EpidocParser bare — the require graph would under-count) and follows
    # subclassing (First1kGreek < Perseus). Over-approximation (a constant
    # named in a comment) only over-rebuilds; sorted absolute paths.
    def parser_files(entry)
      closure = []
      queue = definitions.fetch(terminal_constant(entry.adapter_class_name), []).dup
      until queue.empty?
        file = queue.shift
        next if closure.include?(file)

        closure << file
        queue.concat(references(file))
      end
      closure.sort
    end

    class << self
      # The canonical-bytes identity of +dir+, or nil (WEAK — never skip)
      # when the tree cannot honestly be named: missing dir, a git repo with
      # non-attic local modifications, or a git failure.
      def canonical_identity(dir)
        return nil unless Dir.exist?(dir)

        tokens = identity_tokens(dir, dir)
        tokens && Digest::SHA256.hexdigest(tokens.sort.join("\n"))
      end

      # The language-scoped fold identity (P39-1): "name:sha" tokens, the
      # normalize.rb wiring first, then the fold modules +languages+ consult
      # (sorted; nil languages = unknowable = all of them). Stored verbatim in
      # derivation_stamps.fold_digest so drift can NAME the changed file.
      def fold_digest(languages = nil)
        tokens = ["normalize.rb:#{fold_file_digest(FOLD_RULES_PATH)}"]
        fold_modules_for(languages).each do |name|
          tokens << "#{name}:#{fold_file_digest(FOLD_MODULE_PATHS.fetch(name))}"
        end
        tokens.join(" ")
      end

      # The fold-module names consulted by +languages+ (primary subtags,
      # union across the set), sorted for a stable token order.
      def fold_modules_for(languages)
        return FOLD_MODULE_PATHS.keys.sort if languages.nil?

        languages.flat_map { |tag| FOLD_LANGUAGES.fetch(Normalize.primary_subtag(tag), []) }
                 .uniq.sort
      end

      # { name => sha } out of a fold_digest value. A pre-P39-1 stamp is one
      # bare sha — no token parses, so blame falls on every current file.
      def fold_tokens(digest)
        digest.to_s.split
              .filter_map { |token| token.split(":", 2) if token.include?(":") }.to_h
      end

      # Seam (tests divert one file to simulate a fold-table change).
      def fold_file_digest(path)
        Digest::SHA256.file(path).hexdigest
      end

      # The latest migration number the running code carries (the catalog's
      # applied schema_info version must equal it for --incremental to run).
      def migration_level
        Dir[File.join(Store::MIGRATIONS_DIR, "*.rb")]
          .map { |file| File.basename(file).to_i }.max
      end

      # The entry's derivation-shaping flags, canonically ordered.
      def config_json(entry)
        JSON.generate(
          "classes" => entry.classes, "fuzzy_index" => entry.fuzzy_index,
          "lemma_tier" => entry.lemma_tier, "translations" => entry.translations
        )
      end

      private

      # Walk +dir+: each embedded git repo contributes its HEAD (O(1) for
      # arbitrarily large corpora) plus its attic's file contents; every
      # file outside a repo contributes its content sha. nil poisons the
      # whole walk (weak identity).
      def identity_tokens(dir, root)
        return repo_tokens(dir, root) if File.directory?(File.join(dir, ".git"))

        tokens = []
        Dir.children(dir).sort.each do |name|
          full = File.join(dir, name)
          sub = if File.directory?(full)
                  identity_tokens(full, root)
                else
                  ["file:#{relative(full, root)}:#{Digest::SHA256.file(full).hexdigest}"]
                end
          return nil if sub.nil?

          tokens.concat(sub)
        end
        tokens
      end

      def repo_tokens(dir, root)
        return nil unless porcelain_clean?(dir)

        head = Shell.run("git", "-C", dir, "rev-parse", "HEAD").strip
        tokens = ["git:#{relative(dir, root)}:#{head}"]
        # The attic is canonical data git is told to ignore (GitFetch
        # excludes it via .git/info/exclude) — hash its bytes explicitly.
        attic = File.join(dir, ".attic")
        tokens.concat(identity_tokens(attic, root)) if File.directory?(attic)
        tokens
      rescue Shell::Error
        nil
      end

      # Clean = git can vouch that HEAD names the working tree. The attic is
      # excluded by GitFetch; anything else (edits, untracked files, LFS
      # materialization) means HEAD is not the bytes we would parse.
      def porcelain_clean?(dir)
        Shell.run("git", "-C", dir, "status", "--porcelain").strip.empty?
      end

      def relative(path, root)
        path == root ? "." : path.delete_prefix("#{root}#{File::SEPARATOR}")
      end
    end

    private

    def parser_digest(entry)
      tokens = parser_files(entry).map { |file| file_token(file) }
      Digest::SHA256.hexdigest((tokens + [shared_core_digest]).join("\n"))
    end

    # { terminal constant name => [defining files] } across adapters/.
    def definitions
      @definitions ||= adapter_files.each_with_object({}) do |file, map|
        names = File.read(file).scan(/^\s*(?:class|module)\s+([A-Z]\w*)/).flatten.uniq
        (names - NAMESPACE_NAMES).each { |name| (map[name] ||= []) << file }
      end
    end

    def adapter_files = Dir[File.join(ADAPTERS_DIR, "*.rb")]

    # Files defining any adapters/-constant referenced in +file+ (one union
    # regex pass, cached per file).
    def references(file)
      @references[file] ||= begin
        names = File.read(file).scan(reference_pattern).flatten.uniq
        names.flat_map { |name| definitions.fetch(name) } - [file]
      end
    end

    def reference_pattern
      @reference_pattern ||= /\b(#{Regexp.union(definitions.keys.sort)})\b/
    end

    def terminal_constant(class_name) = class_name.split("::").last

    def file_token(file)
      @file_tokens[file] ||=
        "#{file.delete_prefix("#{LIB_DIR}#{File::SEPARATOR}")}:#{Digest::SHA256.file(file).hexdigest}"
    end

    # Everything under lib/nabu/ that shapes derived rows (class doc), plus
    # the alignment registry file — config whose content the Indexer derives
    # alignment_refs from.
    def shared_core_digest
      @shared_core_digest ||= begin
        files = Dir[File.join(LIB_DIR, "**", "*.rb")].reject { |file| excluded?(file) }.sort
        tokens = files.map { |file| file_token(file) }
        if File.exist?(@config.alignments_path.to_s)
          tokens << "alignments:#{Digest::SHA256.file(@config.alignments_path).hexdigest}"
        end
        Digest::SHA256.hexdigest(tokens.join("\n"))
      end
    end

    def excluded?(file)
      rel = file.delete_prefix("#{LIB_DIR}#{File::SEPARATOR}")
      EXCLUDED_DIRS.any? { |dir| rel.start_with?("#{dir}#{File::SEPARATOR}") } ||
        EXCLUDED_FILES.include?(rel)
    end
  end
end
