# frozen_string_literal: true

require "csv"
require "digest"

module Nabu
  module Adapters
    # westoldturkic — the CLDF dataset of Róna-Tas & Berta, *West Old
    # Turkic: Turkic Loanwords in Hungarian* (2011), via the
    # LoanpyDataHub extraction (P108-7, the Q107 half; Zenodo
    # 10.5281/zenodo.7893910 v2.0, license cc-by-4.0 on the record).
    # The turkic desk's comparative instrument: WOT — the r-Turkic
    # (Bolgar-type) branch Hungarian borrowed from — attested through
    # its Hungarian loans.
    #
    # == Surface (the iecor Option-A mold)
    #
    # ONE dictionary (slug westoldturkic), entry per WOT etymon (480
    # in v2.0), the reconstruction's Hungarian descent chain — Early
    # Ancient (EAH) → Late Ancient (LAH) → Old (OH) → modern (H)
    # Hungarian forms sharing the etymon's concept — as reflex rows;
    # the dataset's curated borrowings.csv pairs mark exactly the
    # loan STEP (WOT → EAH) borrowed, inherited descent below it
    # stays unmarked. Dictionary language `trk` (the ISO 639-5 Turkic
    # collective; WOT itself carries no ISO code — Glottocode
    # bolg1249). The Hungarian first-attestation Year is mined into
    # the body (the №R-70 law); Segments ride the body as the
    # phonemic transcription.
    class Westoldturkic < Nabu::Adapter
      ZIP_URL = "https://zenodo.org/api/records/7893910/files/" \
                "LoanpyDataHub/ronataswestoldturkic-2.0.zip/content"
      RELEASE_SHA256 = "f1a2bc9fa7d646bb7f60d9e2a07ed731b39bc56ea235fbd09edd2a9e0bd1b710"
      DICTIONARY_SLUG = "westoldturkic"
      DICTIONARY_LANGUAGE = "trk"
      CLDF_DIR = "cldf"
      ANCHOR_FILE = "forms.csv"
      TITLE = "West Old Turkic — Turkic loanwords in Hungarian (Róna-Tas & Berta 2011, CLDF)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "westoldturkic",
        name: TITLE,
        license: "CC BY 4.0 (the Zenodo record's license field, 10.5281/zenodo.7893910 v2.0, " \
                 "read 2026-09-29). Cite Róna-Tas & Berta 2011 and the LoanpyDataHub CLDF " \
                 "derivation (List & Forkel's lexibank ecosystem)",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.7893910",
        parser_family: "cldf-wordlist"
      )

      def self.manifest = MANIFEST
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "cldf zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        anchor = Dir.glob(File.join(workdir, "**", CLDF_DIR, ANCHOR_FILE)).min
        return unless anchor

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{CLDF_DIR}",
          path: File.expand_path(File.dirname(anchor)), metadata: {}
        )
      end

      def parse(document_ref)
        tables = read_tables(document_ref.path)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: DICTIONARY_LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        tables[:forms].values.select { |f| f["Language_ID"] == "WOT" }
                             .sort_by { |f| f["ID"] }.each do |form|
          document << build_entry(form, tables)
        end
        raise Nabu::ParseError, "#{document_ref.path}: no WOT etyma parsed" if document.entries.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "westoldturkic: #{e.message}"
      end

      # The iecor rail: prepare → verify the sha pin → breaker → complete.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now,
                              notes: [fetch.not_modified? ? "not modified (304)" : "v2.0 sha pin verified"])
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "westoldturkic fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "westoldturkic: downloaded zip sha #{fetch.sha} does not match the pinned " \
              "#{@pin} — upstream minted a new artifact; re-verify the record and bump the pin"
      end

      def read_tables(dir)
        {
          forms: index_csv(File.join(dir, "forms.csv")),
          languages: index_csv(File.join(dir, "languages.csv")),
          parameters: index_csv(File.join(dir, "parameters.csv")),
          borrowed_targets: borrowed_targets(File.join(dir, "borrowings.csv"))
        }
      end

      def index_csv(path)
        return {} unless File.file?(path)

        CSV.foreach(path, headers: true).to_h { |row| [row["ID"], row.to_h] }
      end

      # Target_Form_ID values — the forms a curated borrowing row names
      # as the loan's landing point (EAH in every v2.0 row).
      def borrowed_targets(path)
        return {} unless File.file?(path)

        CSV.foreach(path, headers: true).to_h { |row| [row["Target_Form_ID"], true] }
      end

      def build_entry(form, tables)
        concept = tables[:parameters][form["Parameter_ID"]]
        headword = Nabu::Normalize.nfc(form["Form"].to_s.strip)
        Nabu::DictionaryEntry.new(
          entry_id: form.fetch("ID"), key_raw: form["Form"].to_s,
          language: DICTIONARY_LANGUAGE, headword: headword,
          headword_folded: fold(headword),
          gloss: concept && Nabu::Normalize.nfc(concept["Name"].to_s),
          body: body_text(form, concept, tables),
          citations: [], reflexes: reflexes_for(form, tables)
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "westoldturkic: form #{form['ID'].inspect}: #{e.message}"
      end

      def fold(text)
        folded = Nabu::Normalize.search_form(text, language: DICTIONARY_LANGUAGE)
        folded.strip.empty? ? text : folded
      end

      def body_text(form, concept, tables)
        lines = ["West Old Turkic etymon — concept: #{concept ? concept['Name'] : '(unknown)'}"]
        lines << "segments: #{form['Segments']}" unless form["Segments"].to_s.strip.empty?
        year = hungarian_year(form, tables)
        lines << "Hungarian first attestation: #{year}" if year
        lines << form["Comment"] unless form["Comment"].to_s.strip.empty?
        Nabu::Normalize.nfc(lines.join("\n"))
      end

      # The modern-Hungarian sibling's Year column — the loan's dated
      # surfacing in the written record (the №R-70 mining law).
      def hungarian_year(form, tables)
        sibling = tables[:forms].values.find do |f|
          f["Language_ID"] == "H" && f["Parameter_ID"] == form["Parameter_ID"]
        end
        year = sibling && sibling["Year"].to_s.strip
        year && year.empty? ? nil : year
      end

      def reflexes_for(form, tables)
        tables[:forms].values
                      .select { |f| f["Parameter_ID"] == form["Parameter_ID"] && f["ID"] != form["ID"] }
                      .sort_by { |f| f["ID"] }
                      .map { |f| build_reflex(f, tables) }
      end

      def build_reflex(form, tables)
        variety = tables[:languages][form["Language_ID"]] || {}
        iso = variety["ISO639P3code"].to_s.strip
        code = iso.empty? ? form["Language_ID"] : iso
        language = iso.empty? ? nil : iso
        word = Nabu::Normalize.nfc(form["Form"].to_s.strip)
        Nabu::DictionaryReflex.new(
          lang_code: code, language: language, word: word, roman: nil,
          word_folded: language ? Nabu::Normalize.search_form(word, language: language) : word,
          roman_folded: nil,
          borrowed: tables[:borrowed_targets].key?(form["ID"]),
          lang_name: Nabu::Normalize.nfc(variety["Name"].to_s.tr("_", " "))
        )
      end
    end
  end
end
