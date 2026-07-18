# frozen_string_literal: true

require_relative "flat_csv_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The Larth ETP glossary adapter (P29-0): Data/ETP_POS.csv from the
    # Larth repo (github.com/GianlucaVico/Larth-Etruscan-NLP; Vico &
    # Spanakis 2023, ALP2023) — 1,122 Etruscan vocabulary rows with English
    # translations, grammatical categories and universal POS tags, the
    # machine-readable descendant of the Etruscan Texts Project vocabulary
    # (Wallace-project scholarly lineage). The SECOND Etruscan dictionary
    # row beside the kaikki ett extract (wiktionary-recon), and the second
    # flat-csv composition. The sibling raw lists ETPWords/ETPNames/ETPSuff
    # are the same material pre-merge — journaled, not ingested.
    #
    # == What one row yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the upstream row index verbatim (the unnamed first
    #   column) — homograph rows (acil 643 "is necessary" / 644 "work")
    #   stay separate entries; stable while upstream file order is stable
    #   (a reorder is a revision, the loader's content-sha handles it).
    # - headword: the `Etruscan` column, NFC (transliterated; ś is spelled
    #   σ' upstream); headword_folded via the generic ett search form.
    # - gloss: the first CERTAIN non-empty translation, else the first
    #   non-empty one. The Translations column is a Python tuple repr —
    #   ((True, 'work'), (False, 'product')) — whose boolean marks
    #   translation certainty (the ETPWords "?" convention); uncertain
    #   glosses render with an honest " (?)" in the body and never win the
    #   gloss over a certain sibling.
    # - body: the translations line, "grammatical: <categories>" (the POS
    #   column: "def art nom", "1st gen"…), "pos: <TAG>" (universal POS),
    #   plus the honest flags — "suffix entry" (Is suffix), "inferred"
    #   (Is inferred), "abbreviation of <full form>" (also the gloss
    #   fallback for bare abbreviation rows like a → aule).
    # - citations/reflexes: always empty — the ETP vocabulary cites no
    #   urns and names no descendants.
    #
    # == License / fetch
    #
    # Repo LICENSE: CC BY 4.0 (verified 2026-07-18; added by upstream
    # 2026-07-14 on owner request) → attribution; the required credit is
    # the paper citation, carried in the manifest. One FileFetch from the
    # PINNED commit's raw URL, sha256-verified BEFORE the tree mutates
    # (the corph re-pin doctrine); the repo still moves occasionally →
    # sync_policy: manual, owner re-pins.
    class LarthEtp < Nabu::Adapter
      REPO_URL = "https://github.com/GianlucaVico/Larth-Etruscan-NLP"
      COMMIT = "daf4972175f45b48188fe36671db3a0e081e5130" # main @ 2026-07-14, LICENSE CC BY 4.0
      CSV_URL = "https://raw.githubusercontent.com/GianlucaVico/Larth-Etruscan-NLP/" \
                "#{COMMIT}/Data/ETP_POS.csv".freeze
      CSV_SHA256 = "4f9d5875d7ed0899a4d98cc579a08fedb5611825841cfce45f7504dbd48918ce"

      FILENAME = "ETP_POS.csv"
      DICTIONARY_SLUG = "larth-etp"
      LANGUAGE = "ett"
      TITLE = "ETP vocabulary — Etruscan words, POS and translations (Larth)"

      REQUIRED_HEADERS = ["", "Etruscan", "Translations", "POS", "Is inferred", "Is suffix",
                          "Abbreviation of", "TAG"].freeze

      # One (certainty, gloss) member of the Python tuple repr; upstream
      # switches to double quotes when the gloss carries an apostrophe
      # ("left'"), so both quote styles match.
      TRANSLATION = /\((True|False),\s*(?:'([^']*)'|"([^"]*)")\)/

      MANIFEST = Nabu::SourceManifest.new(
        id: "larth-etp",
        name: "Larth ETP glossary — Etruscan vocabulary with POS and translations",
        license: "CC BY 4.0 (repo LICENSE, github.com/GianlucaVico/Larth-Etruscan-NLP; credit: " \
                 "Vico & Spanakis 2023, \"Larth: Dataset and Machine Translation for Etruscan\", " \
                 "ALP2023 — ETP/Wallace-project vocabulary lineage)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "flat-csv"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One HEAD against the pinned raw URL (reachability; the commit-pinned
      # body never drifts — drift means the PIN changed locally).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: CSV_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +csv_sha256+ exists for the WebMock'd fetch tests — real syncs keep
      # the frozen pin.
      def initialize(csv_sha256: CSV_SHA256)
        super()
        @csv_sha256 = csv_sha256
      end

      # One DocumentRef for the one CSV (the bosworth-toller shape). A
      # workdir without the file yields nothing; the same walk works under
      # the attic.
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
        parser.each_row(document_ref.path) { |row| document << build_entry(row, document_ref.path) }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "larth-etp: #{document_ref.id}: #{e.message}"
      end

      # FileFetch phases run separately so the sha pin verifies BEFORE the
      # tree mutates (the open-etruscan choreography at one-artifact size).
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(
          url: CSV_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "larth-etp fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS)
      end

      def verify_pin!(fetch)
        return if fetch.sha == @csv_sha256

        raise Nabu::FetchError,
              "larth-etp: ETP_POS.csv drifted — fetched sha256 #{fetch.sha} != pinned #{@csv_sha256} " \
              "(commit #{COMMIT[0, 12]}); review upstream and re-pin (owner decision)"
      end

      # -- entry building ------------------------------------------------------

      def build_entry(row, path)
        index = row.fetch("").to_s.strip
        headword = row.fetch("Etruscan").to_s.strip
        translations = parse_translations(row["Translations"])
        Nabu::DictionaryEntry.new(
          entry_id: index, key_raw: headword, language: LANGUAGE,
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(translations, row),
          body: body_text(translations, row),
          citations: []
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "larth-etp: row index=#{index.inspect} in #{path}: #{e.message}"
      end

      # [[certain(Boolean), gloss(String)], …] — empty glosses dropped
      # (upstream carries (True, '') members).
      def parse_translations(value)
        value.to_s.scan(TRANSLATION).filter_map do |certain, single, double|
          text = (single || double).to_s.strip
          [certain == "True", text] unless text.empty?
        end
      end

      # The first certain translation, else the first at all, else the
      # abbreviation target (a → aule), else nil — honestly gloss-less.
      def gloss(translations, row)
        text = translations.find { |certain, _| certain }&.last || translations.first&.last ||
               blank_to_nil(row["Abbreviation of"])
        text && Normalize.nfc(text)
      end

      def body_text(translations, row)
        lines = [translations_line(translations), labeled(row, "POS", "grammatical"),
                 labeled(row, "TAG", "pos"), *flag_lines(row)].compact
        lines = ["(vocabulary entry — no translation recorded)"] if lines.empty?
        Normalize.nfc(lines.join("\n"))
      end

      def translations_line(translations)
        return nil if translations.empty?

        rendered = translations.map { |certain, text| certain ? text : "#{text} (?)" }
        "translations: #{rendered.join('; ')}"
      end

      def labeled(row, column, label)
        value = blank_to_nil(row[column])
        value && "#{label}: #{value}"
      end

      def flag_lines(row)
        lines = []
        lines << "suffix entry" if truthy?(row["Is suffix"])
        lines << "inferred" if truthy?(row["Is inferred"])
        abbreviation = blank_to_nil(row["Abbreviation of"])
        lines << "abbreviation of #{abbreviation}" if abbreviation
        lines
      end

      def truthy?(value)
        value.to_s.strip.casecmp("true").zero?
      end

      def blank_to_nil(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
