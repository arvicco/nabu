# frozen_string_literal: true

require_relative "wiktionary_jsonl_parser"

module Nabu
  module Adapters
    # Wiktionary-Sumerian (P68-1, the Q8 sign-card sense lane): English
    # Wiktionary's Sumerian entries via the kaikki.org wiktextract
    # extraction — the wiktionary-cu mold verbatim (parser family
    # wiktionary-jsonl, dictionary shelf, FileFetch, reflexes). What it
    # adds to the library: sense GLOSSES for cuneiform — 1,314 of the
    # 2,499 entries carry pure-cuneiform headwords (𒊬, 𒀭), so the P65
    # cuneiform sign card joins senses by glyph — plus the sux→akk
    # borrowing chains riding the descendants trees (𒊬 → Akkadian kirûm),
    # minted as dictionary_reflexes (`reflexes: true`). The MZL/HZL print
    # numbers live in kaikki's TRANSLINGUAL extraction (136 MB) and are
    # already held via the OSL @list lines — deliberately NOT adopted
    # (the Q7 scout's verdict).
    #
    # == Upstream (measured 2026-08-09 by the Q7 scout; re-verified at
    # fixture snapshot 2026-08-10: 2,295,953 bytes, 2,499 lines)
    #
    # https://kaikki.org/dictionary/Sumerian/ — built from the
    # enwiktionary dump (wiktextract, Tatu Ylönen). DEPRECATION CAVEAT
    # (the wiktionary-cu class note verbatim): the per-language JSONL is
    # labelled deprecated upstream; it is what the site serves today, and
    # the durable fallback is filtering the full extract by
    # lang_code == "sux" — recorded in docs/02-sources.md.
    #
    # == License
    #
    # Verbatim, kaikki.org/dictionary/ "Copyright and license": "This data
    # is made available under the same licenses as Wiktionary - both
    # CC-BY-SA and GFDL." → license_class "attribution"; wiktextract's
    # academic citation (Ylönen, LREC 2022) carried in 02-sources.
    class WiktionarySux < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "wiktionary-sux",
        name: "Wiktionary Sumerian — kaikki.org machine-readable extract",
        license: "CC-BY-SA + GFDL (verbatim kaikki.org/dictionary/: \"This data is made available " \
                 "under the same licenses as Wiktionary - both CC-BY-SA and GFDL.\")",
        license_class: "attribution",
        upstream_url: "https://kaikki.org/dictionary/Sumerian/kaikki.org-dictionary-Sumerian.jsonl",
        parser_family: "wiktionary-jsonl"
      )

      FILENAME = "kaikki.org-dictionary-Sumerian.jsonl"
      DICTIONARY_SLUG = "wiktionary-sux"
      LANGUAGE = "sux"
      TITLE = "Wiktionary — Sumerian (kaikki.org extract)"

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      # descendants → dictionary_reflexes (the P14-1 crosswalk): the
      # sux→akk borrowing chains are the etymological payload here.
      def self.reflex_bearing? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

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
        raise Nabu::ParseError, "wiktionary-sux: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "wiktionary-sux fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
