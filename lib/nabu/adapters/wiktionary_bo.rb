# frozen_string_literal: true

require_relative "wiktionary_jsonl_parser"

module Nabu
  module Adapters
    # The Wiktionary-Tibetan adapter (P48-4): English Wiktionary's Tibetan
    # entries via the kaikki.org wiktextract extraction — the third shelf of
    # the tibetan-lexica packet, riding the wiktionary-cu shape EXACTLY
    # (same parser family, same FileFetch path, same DictionaryDocument/
    # Entry model). Dictionary slug wiktionary-bo, stored language "bod"
    # (639-3, the san/chu convention; kaikki's own lang_code is the 639-1
    # "bo" and stays in the raw record — `--lang bo/tib` reach the shelf
    # via Languages.code_variants). Etymology text is KEPT in entry bodies
    # (the compound chains — byang chub + sems + dpa' bo); descendants
    # crosswalk as reflexes (reflexes: true — 134 bearing records / 307
    # worded edges censused 2026-07-28; བོད "Tibet" descends into grc/lat
    # and, through Prakrit, into san भोट — edges into held shelves).
    #
    # == Upstream (verified 2026-07-28)
    #
    # https://kaikki.org/dictionary/Tibetan/ — "3394 distinct words", 3,651
    # records (4,547,518 B at fixture time, one JSON object per line,
    # Last-Modified 2026-07-25). The Classical Tibetan (xct) and Old
    # Tibetan (otb) per-language extracts do NOT exist upstream (404s
    # verified) — this is the one kaikki Tibetan artifact.
    #
    # DEPRECATION CAVEAT (the wiktionary-cu caveat verbatim): the
    # per-language JSONL is labelled "DEPRECATED, will be removed in the
    # near future" (wiktextract issue #1178). It serves today; if it 404s
    # (clean FetchError, sync aborts), the durable fallback is filtering
    # the full enwiktionary extract by lang_code == "bo" — recorded in
    # docs/02-sources.md.
    #
    # == License
    #
    # Verbatim, https://kaikki.org/dictionary/ "Copyright and license":
    # "This data is made available under the same licenses as Wiktionary -
    # both CC-BY-SA and GFDL." Dual license, the SA arm governs →
    # license_class "attribution", MCP-surface-safe. Wiktextract asks for
    # an academic citation (Ylönen, LREC 2022) — carried in 02-sources.
    class WiktionaryBo < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-bo",
        name: "Wiktionary Tibetan — kaikki.org machine-readable extract",
        license: "CC-BY-SA + GFDL (verbatim kaikki.org/dictionary/: \"This data is made available " \
                 "under the same licenses as Wiktionary - both CC-BY-SA and GFDL.\")",
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Tibetan/kaikki.org-dictionary-Tibetan.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Tibetan.jsonl"
      DICTIONARY_SLUG = "wiktionary-bo"
      LANGUAGE = "bod"
      TITLE = "Wiktionary — Tibetan (kaikki.org extract)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The parser runs with `reflexes: true`: descendants become
      # dictionary_reflexes rows. Health checks this promise (P18-7).
      def self.reflex_bearing? = true

      # The probe HEADs the JSONL itself: reachability + Last-Modified
      # drift vs the .file-fetch.json pin — and, given the deprecation
      # flag, the early warning that upstream pulled the file. metadata_url
      # nil — see the class note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the one JSONL. A workdir without the file
      # yields nothing (the day-one pre-fetch state); the same walk works
      # under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{FILENAME}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        WiktionaryJsonlParser.new(language: LANGUAGE, reflexes: true)
                             .entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "wiktionary-bo: #{document_ref.id}: #{e.message}"
      end

      # Download the single upstream JSONL via FileFetch (conditional GET,
      # sha pin, attic + guard contract). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "wiktionary-bo fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
