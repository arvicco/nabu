# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The Perseus adapter (architecture §3, packet P2-3): a thin composition of
    # the EpidocParser parser family with PerseusDL canonical-repo layout
    # knowledge. It owns three things the parser deliberately does not:
    #
    #   1. Repo walking — data/<textgroup>/<work>/<tg>.<work>.<edition>.xml,
    #      selecting the ORIGINAL-language edition (grc for greekLit, lat for
    #      latinLit) and skipping translations (perseus-eng*). The acceptance
    #      rule is data-driven — `#edition_slug_pattern` names which edition
    #      slugs count — so sibling corpora with other slug families (First1K's
    #      1st1K-grcN / opp-grcN) subclass and override just that one method.
    #      With `translations: true` (P7-4, per-source registry opt-in routed
    #      through SourceRegistry::Entry#build_adapter) the walk ALSO accepts
    #      English translations (`#translation_slug_pattern`, perseus-eng<n>),
    #      selected highest-version-per-work independently of the original, as
    #      ordinary documents: language "eng", their own edition urns — the
    #      shared CTS citation scheme is what makes passage-level alignment
    #      (…perseus-grc2:1.1 ↔ …perseus-eng4:1.1) free downstream.
    #   2. Metadata resolution — titles/urns from the work-level __cts__.xml
    #      (CTS namespace), which the streaming parser never reads.
    #   3. fetch — a git clone/pull of the vendored upstream snapshot.
    #
    # == Namespace / class design (the one non-obvious decision here)
    #
    # PerseusDL ships two sibling repos — canonical-greekLit and
    # canonical-latinLit — identical in structure, differing only in the CTS
    # namespace embedded in every urn (greekLit vs latinLit) and the
    # original-language slug (grc vs lat). Rather than duplicate the adapter, it
    # is parameterized by that namespace.
    #
    # This concrete class IS the greekLit adapter: `Perseus.manifest` and
    # `Perseus.new.manifest` both return the "perseus-greek" manifest, and
    # `Perseus.new` takes no required arguments — which is exactly what
    # SourceRegistry needs (`entry.adapter_class.new`, `entry.adapter_class.manifest`).
    #
    # latinLit will arrive later as a one-line sibling SUBCLASS:
    #
    #   class PerseusLatin < Perseus
    #     NAMESPACE = "latinLit"
    #   end
    #
    # The class methods key off `self::NAMESPACE` and the initializer defaults to
    # `self.class::NAMESPACE`, so the subclass inherits all behaviour and only
    # its manifest/urn namespace shift. Direct instantiation with an explicit
    # `Perseus.new(namespace: "latinLit")` also works for ad-hoc use, but the
    # registry path (no-arg .new + class-level .manifest) is the supported one.
    class Perseus < Nabu::Adapter
      # The CTS namespace this concrete class serves. Subclasses override.
      NAMESPACE = "greekLit"

      # Original-language edition slug per CTS namespace. Translations
      # (perseus-eng*) are skipped unless the adapter was built with
      # `translations: true`.
      LANGUAGES = { "greekLit" => "grc", "latinLit" => "lat" }.freeze

      # The language tag translation passages carry (BCP-47). English only:
      # that is what PerseusDL ships at scale (786 perseus-eng files in
      # canonical-greekLit; the scattered fre/ger files belong to other slug
      # families and stay out). Folding for eng is the generic rule (P6-4).
      TRANSLATION_LANGUAGE = "eng"

      # Translation bodies live in div[@type="translation"] (785 of 786
      # upstream eng files); the lone edition-typed outlier is accepted by the
      # fallback. Ordered: the shape actually shipped first.
      TRANSLATION_DIVISION_TYPES = %w[translation edition].freeze

      # Static manifests per namespace (architecture §5). CC BY-SA 4.0 →
      # license_class "attribution".
      MANIFESTS = {
        "greekLit" => Nabu::SourceManifest.new(
          id: "perseus-greek",
          name: "Perseus Digital Library — canonical Greek literature",
          license: "CC BY-SA 4.0",
          license_class: "attribution",
          upstream_url: "https://github.com/PerseusDL/canonical-greekLit",
          parser_family: "epidoc"
        ),
        "latinLit" => Nabu::SourceManifest.new(
          id: "perseus-latin",
          name: "Perseus Digital Library — canonical Latin literature",
          license: "CC BY-SA 4.0",
          license_class: "attribution",
          upstream_url: "https://github.com/PerseusDL/canonical-latinLit",
          parser_family: "epidoc"
        )
      }.freeze

      # The CTS metadata namespace used by every __cts__.xml.
      CTS_NS = { "ti" => "http://chs.harvard.edu/xmlns/cts" }.freeze
      private_constant :CTS_NS

      def self.manifest
        MANIFESTS.fetch(self::NAMESPACE)
      end

      # +translations+ (P7-4): when true, discover also yields the highest
      # perseus-eng<n> edition per work and parse reads translation divs. The
      # default (false) is provably inert — see #classify_edition. No-arg
      # construction stays the registry contract; the flag arrives via
      # SourceRegistry::Entry#build_adapter for opted-in sources only.
      def initialize(namespace: self.class::NAMESPACE, translations: false)
        super()
        @namespace = namespace
        @translations = translations
      end

      # Instance manifest tracks the instance's namespace (which defaults to,
      # and for the registry path always equals, the class namespace).
      def manifest
        MANIFESTS.fetch(@namespace)
      end

      # Walk <workdir>/data/<tg>/<work>/ for original-language editions,
      # yielding one Nabu::DocumentRef per work (highest edition version when
      # several exist). Deterministically sorted by urn. Returns an Enumerator
      # when called without a block (the adapter contract's lazy shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        edition_refs(workdir).each(&block)
      end

      # Delegate to the EpidocParser, feeding it the urn/language/title that
      # discover resolved from the repo layout and __cts__.xml. Translation
      # refs (language "eng") anchor on div[@type="translation"] with an
      # edition-typed fallback; originals keep the parser's default — so a
      # flag-off adapter never constructs a non-default parser call.
      def parse(document_ref)
        language = document_ref.metadata["language"]
        options = language == TRANSLATION_LANGUAGE ? { division_types: TRANSLATION_DIVISION_TYPES } : {}
        EpidocParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: language,
          title: document_ref.metadata["title"],
          **options
        )
      end

      # Bring the vendored upstream snapshot up to date via the shared
      # non-destructive git path (Nabu::GitFetch through Adapter#git_fetch!,
      # P5-2): fetch objects, run the mass-deletion breaker on the pending
      # deletions, attic upstream-deleted files, ff-merge — returning a
      # Nabu::FetchReport pinning the resulting HEAD sha (architecture §3).
      # No network in tests: exercised against local fixture git repos. A
      # Shell failure (bad remote, non-ff history, ...) aborts the sync as a
      # Nabu::FetchError; a tripped breaker as Nabu::SyncAborted with the
      # canonical tree byte-unchanged (+force+ overrides).
      #
      # When +progress+ is given, git is asked for `--progress` and its output
      # is streamed line by line to the callback (a clone of the multi-GB
      # PerseusDL repo is minutes of otherwise-silent work); when nil, the quiet
      # Shell.run path — the one conformance exercises — is used unchanged.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: manifest.upstream_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # One discoverable edition before ref construction. +language+ is the
      # passage language the edition will carry: the namespace original, or
      # TRANSLATION_LANGUAGE for an accepted translation.
      Candidate = Data.define(:textgroup, :work, :edition, :version, :language, :path)
      private_constant :Candidate

      def edition_refs(workdir)
        best_editions(workdir).map do |candidate|
          urn = "urn:cts:#{@namespace}:#{candidate.textgroup}.#{candidate.work}.#{candidate.edition}"
          work_dir = File.dirname(candidate.path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: urn,
            path: candidate.path,
            metadata: {
              "title" => resolve_title(work_dir, fallback: urn.split(":").last),
              "language" => candidate.language
            }
          )
        end.sort_by(&:id)
      end

      # All accepted editions, reduced to the highest version per work AND
      # language — the eng pick never competes with the original's (a work
      # keeps its grc2 even when eng4 > 2, and vice versa).
      def best_editions(workdir)
        candidates(workdir)
          .group_by { |candidate| [candidate.textgroup, candidate.work, candidate.language] }
          .map { |_work, group| group.max_by { |candidate| version_key(candidate.version) } }
      end

      # Filename shape: <tg>.<work>.<edition-slug>.xml — slugs never contain
      # dots, so the three components split cleanly. Whether a slug is an
      # original-language edition we ingest (and its version token) is decided
      # by `#edition_slug_pattern`; anything else (translations, other langs) is
      # filtered out here.
      FILENAME = /\A(?<textgroup>[^.]+)\.(?<work>[^.]+)\.(?<edition>[^.]+)\.xml\z/
      private_constant :FILENAME

      def candidates(workdir)
        Dir.glob(File.join(workdir, "data", "*", "*", "*.xml")).filter_map do |path|
          name = File.basename(path).match(FILENAME)
          next unless name

          version, language = classify_edition(name[:edition])
          next unless version

          Candidate.new(
            textgroup: name[:textgroup],
            work: name[:work],
            edition: name[:edition],
            version: version,
            language: language,
            path: File.expand_path(path)
          )
        end
      end

      # [version token, passage language] if +slug+ is an edition this adapter
      # ingests, else nil. The original-language gate (perseus-<lang>) runs
      # first and is the ONLY probe when translations are off — the flag-off
      # filter is character-for-character the pre-P7-4 one, which is the
      # structural half of the frozen-urn argument. The translation probe only
      # exists behind the flag.
      def classify_edition(slug)
        match = slug.match(edition_slug_pattern)
        return [match[:version], LANGUAGES.fetch(@namespace)] if match
        return nil unless @translations

        match = slug.match(translation_slug_pattern)
        match && [match[:version], TRANSLATION_LANGUAGE]
      end

      # Which edition slugs count as original-language, with a named :version
      # capture. Perseus ingests exactly perseus-<lang><n> (grc/lat). Subclasses
      # over other slug families (First1K) override this alone.
      def edition_slug_pattern
        lang = LANGUAGES.fetch(@namespace)
        /\Aperseus-#{lang}(?<version>\d+)\z/
      end

      # Which slugs count as ingestible translations when the flag is on:
      # exactly perseus-eng<n> (all 786 upstream eng version tokens are pure
      # digits; other languages and slug families stay excluded). Subclasses
      # inherit this unchanged — the flag defaults off everywhere, so First1K
      # and PerseusLatin behavior only shifts if a source opts in.
      def translation_slug_pattern
        /\Aperseus-#{TRANSLATION_LANGUAGE}(?<version>\d+)\z/
      end

      # Comparable key for highest-version selection: numeric part first, then
      # any letter suffix, so grc2 < grc2a (grc2a wins). Handles Perseus's
      # pure-numeric tokens ("2" => [2, ""]) and First1K's letter-suffixed ones
      # ("2a" => [2, "a"]) uniformly.
      def version_key(token)
        digits, letter = token.match(/\A(?<digits>\d+)(?<letter>[a-z]?)\z/).captures
        [digits.to_i, letter]
      end

      # Title from the work-level __cts__.xml, preferring the English <ti:title>
      # and falling back to the first. Missing/empty metadata → the caller's
      # fallback (upstream has works with no __cts__.xml at all; that must not
      # fail discover — fixture README §"Upstream structure notes").
      #
      # A tiny targeted DOM parse is acceptable HERE: __cts__.xml files are
      # <2 KB metadata, not editions — the opposite of the parser's streaming
      # rule, which exists for the multi-MB TEI editions.
      def resolve_title(work_dir, fallback:)
        cts_path = File.join(work_dir, "__cts__.xml")
        return fallback unless File.file?(cts_path)

        titles = Nokogiri::XML(File.read(cts_path)).xpath("//ti:work/ti:title", CTS_NS)
        english = titles.find { |title| title.attribute("lang")&.value == "eng" }
        text = (english || titles.first)&.text&.strip
        text.nil? || text.empty? ? fallback : text
      end
    end
  end
end
