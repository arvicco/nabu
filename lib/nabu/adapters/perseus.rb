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
    #      latinLit) and skipping translations (perseus-eng*).
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
      # (perseus-eng*) are skipped; only these are ingested.
      LANGUAGES = { "greekLit" => "grc", "latinLit" => "lat" }.freeze

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

      def initialize(namespace: self.class::NAMESPACE)
        super()
        @namespace = namespace
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
      # discover resolved from the repo layout and __cts__.xml.
      def parse(document_ref)
        EpidocParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"]
        )
      end

      # Bring the vendored upstream snapshot up to date with a git clone (first
      # time) or ff-only pull, and return the resulting HEAD sha (String). No
      # network in tests: exercised against local fixture git repos. A Shell
      # failure (bad remote, non-ff history, ...) aborts the sync as a
      # Nabu::FetchError.
      #
      # NOTE for SyncRunner (P2-4): the return value is the bare 40-char HEAD
      # sha String — the runner is responsible for wrapping it into a
      # FetchReport and writing sources.last_sync_sha.
      def fetch(workdir)
        if Dir.exist?(File.join(workdir, ".git"))
          Nabu::Shell.run("git", "-C", workdir, "pull", "--ff-only")
        else
          Nabu::Shell.run("git", "clone", "--depth", "1", manifest.upstream_url, workdir)
        end
        Nabu::Shell.run("git", "-C", workdir, "rev-parse", "HEAD").strip
      rescue Nabu::Shell::Error => e
        raise Nabu::FetchError, "perseus fetch failed for #{manifest.upstream_url} into #{workdir}: #{e.message}"
      end

      private

      # One discoverable edition before ref construction.
      Candidate = Data.define(:textgroup, :work, :edition, :version, :path)
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
              "language" => LANGUAGES.fetch(@namespace)
            }
          )
        end.sort_by(&:id)
      end

      # All original-language editions, reduced to the highest version per work.
      def best_editions(workdir)
        candidates(workdir)
          .group_by { |candidate| [candidate.textgroup, candidate.work] }
          .map { |_work, group| group.max_by(&:version) }
      end

      def candidates(workdir)
        pattern = edition_filename_pattern
        Dir.glob(File.join(workdir, "data", "*", "*", "*.xml")).filter_map do |path|
          match = File.basename(path).match(pattern)
          next unless match

          Candidate.new(
            textgroup: match[:textgroup],
            work: match[:work],
            edition: match[:edition],
            version: match[:version].to_i,
            path: File.expand_path(path)
          )
        end
      end

      # Filename shape: <tg>.<work>.perseus-<lang><version>.xml. The language
      # gate here is what excludes perseus-eng* translations.
      def edition_filename_pattern
        lang = LANGUAGES.fetch(@namespace)
        /\A(?<textgroup>[^.]+)\.(?<work>[^.]+)\.(?<edition>perseus-#{lang}(?<version>\d+))\.xml\z/
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
