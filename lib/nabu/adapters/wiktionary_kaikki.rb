# frozen_string_literal: true

require_relative "wiktionary_jsonl_parser"

module Nabu
  module Adapters
    # The shared per-language kaikki.org shelf base (P99-7): the
    # wiktionary-cu/bo/sux mold — one kaikki per-language JSONL extraction
    # of English Wiktionary as one dictionary shelf (parser family
    # wiktionary-jsonl, FileFetch, descendants minted as reflexes) —
    # extracted into ONE class now that the mold has its fourth and fifth
    # occupants. A subclass declares only the facts that differ:
    #
    #   MANIFEST         - the Nabu::SourceManifest (id, kaikki URL, the
    #                      verbatim dual-license statement)
    #   FILENAME         - the kaikki artifact name discover globs for
    #   DICTIONARY_SLUG  - the shelf slug (= manifest id, by convention)
    #   LANGUAGE         - the stored language tag (639-3 where one exists)
    #   TITLE            - the DictionaryDocument display title
    #
    # The registry constructs one adapter CLASS per source
    # (SourceRegistry#build_adapter → arg-less .new), so per-source config
    # lives in these class constants rather than initializer arguments.
    # The three elder occupants (wiktionary-cu, wiktionary-bo,
    # wiktionary-sux) predate the base and keep their own copies of the
    # mold — folding them in is a separate refactor, not a rider.
    #
    # DEPRECATION CAVEAT (the wiktionary-cu class note, family-wide): the
    # per-language JSONL artifacts are labelled "DEPRECATED, will be
    # removed in the near future" upstream (wiktextract issue #1178). They
    # serve today; if one 404s (clean FetchError, sync aborts), the
    # durable fallback is filtering the full enwiktionary extract by the
    # language's lang_code — recorded per source in docs/02-sources.md.
    #
    # LICENSE, verbatim kaikki.org/dictionary/ "Copyright and license":
    # "This data is made available under the same licenses as Wiktionary -
    # both CC-BY-SA and GFDL." → license_class "attribution"; wiktextract
    # asks for an academic citation (Ylönen, LREC 2022) — in 02-sources.
    class WiktionaryKaikki < Nabu::Adapter
      # The verbatim kaikki dual-license statement every subclass manifest
      # carries.
      LICENSE = "CC-BY-SA + GFDL (verbatim kaikki.org/dictionary/: \"This data is made available " \
                "under the same licenses as Wiktionary - both CC-BY-SA and GFDL.\")"

      class << self
        def manifest
          self::MANIFEST
        end

        # Entries, not passages — SyncRunner/Rebuild load through
        # Store::DictionaryLoader (architecture §11).
        def content_kind = :dictionary

        # The parser runs with `reflexes: true`: worded descendants become
        # dictionary_reflexes rows (the P14-1 crosswalk). Health checks
        # this promise (P18-7).
        def reflex_bearing? = true

        # The probe HEADs the JSONL itself: reachability + Last-Modified
        # drift vs the .file-fetch.json pin — and, given the deprecation
        # flag, the early warning that upstream pulled the file.
        def remote_probe_strategy = :http_zip

        def http_probe_targets
          [Nabu::Adapter::HttpProbeTarget.new(
            label: self::FILENAME, zip_url: manifest.upstream_url, metadata_url: nil,
            state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
          )]
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", self.class::FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{self.class::DICTIONARY_SLUG}:#{self.class::FILENAME}",
            path: File.expand_path(path),
            metadata: { "dictionary" => self.class::DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: self.class::DICTIONARY_SLUG, language: self.class::LANGUAGE,
          title: self.class::TITLE, canonical_path: document_ref.path
        )
        WiktionaryJsonlParser.new(language: self.class::LANGUAGE, reflexes: true)
                             .entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{manifest.id}: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: self.class::FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "#{manifest.id} fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
