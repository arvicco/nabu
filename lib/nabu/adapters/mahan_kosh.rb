# frozen_string_literal: true

require_relative "mahan_kosh_json_parser"

module Nabu
  module Adapters
    # Mahan Kosh: Bhai Kahan Singh Nabha, Gurushabad Ratnakar Mahan Kosh
    # (1930) — the great Sikh encyclopedic dictionary of the Gurbani
    # vocabulary (Punjabi, Braj, Sanskrit and Persian words of the Guru
    # Granth Sahib and the Dasam Granth, with quotations and the book's
    # own etymological notes), in Punjabi. For the held Gurbani text
    # (shabados).
    #
    # Stored language pan (shabados's own tag). The Gurmukhi lane only —
    # MahanKoshJsonParser's class note says what is held off and why.
    #
    # == Upstream / grains (verified 2026-11-02)
    #
    # github.com/redroyals/mahan-kosh-multilingual (pushed 2026-09-08,
    # main b298c32e), packaged by Sikhi.io. data/entries/ serves one JSON
    # file per column on one id grid: core.json (the grid — ACCEPTED as
    # the document), gurmukhi.json (the original 1930 text — ACCEPTED,
    # joined by id), en.json + hi.json (the Patiala English and its
    # Hindi — REJECTED, rights not shown), and 25 machine-translated
    # columns (REJECTED, machine text); plus corruption_flags.json (about
    # the English), data/pages/, data/reading-aids/ (a separate Faridkot
    # Teeka dataset) and the site/ viewer. Only core.json and
    # gurmukhi.json are fetched (FileFetch, two GETs, ~40 MB, into
    # core/ and gurmukhi/) — the rejected columns never land, as the
    # kaikki shelves fetch one artifact of many.
    #
    # Reconciliation against upstream's own manifest.json ("total_entries":
    # 68150, "live_entries": 64218, "excluded_entries": 3932): 64,218
    # entries parsed + 3,932 excluded rows skipped = 68,150; 60,196 carry
    # the Gurmukhi body (README: "60,196 / 64,218 (93.7%)"), 4,022 are
    # locator-only. Census through the house parser: 64,218 unique ids,
    # 56,623 distinct headwords (60,510 distinct grid headwords before the
    # book-lemma substitution), 4,054 glossless.
    #
    # == License
    #
    # LICENSE, verbatim: "The 1930 Gurmukhi text of Gurushabad Ratnakar
    # Mahan Kosh (Bhai Kahan Singh Nabha) is in the public domain. This
    # compiled dataset (English text from the Punjabi University Patiala
    # edition, Hindi, machine translations, JSON packaging, and the viewer
    # in site/) is released under Creative Commons Attribution 4.0
    # International (CC BY 4.0)." → license_class "attribution" (the
    # packaging's credit: "Packaged by Sikhi.io").
    class MahanKosh < Nabu::Adapter
      RAW_BASE = "https://raw.githubusercontent.com/redroyals/mahan-kosh-multilingual/main/data/entries"
      # Each file in its own subdir (core/core.json, gurmukhi/gurmukhi.json):
      # one FileFetch state pin per directory.
      FILES = %w[core.json gurmukhi.json].freeze
      DICTIONARY_SLUG = "mahan-kosh"
      TITLE = "Bhai Kahan Singh Nabha, Gurushabad Ratnakar Mahan Kosh (1930)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "mahan-kosh",
        name: "Mahan Kosh (Bhai Kahan Singh Nabha, 1930) — the Gurmukhi text, Sikhi.io JSON packaging",
        license: "CC BY 4.0 packaging, the 1930 text public domain (LICENSE verbatim: \"The 1930 Gurmukhi text " \
                 "of Gurushabad Ratnakar Mahan Kosh (Bhai Kahan Singh Nabha) is in the public domain. This " \
                 "compiled dataset … is released under Creative Commons Attribution 4.0 International (CC BY " \
                 "4.0).\"); packaged by Sikhi.io",
        license_class: "attribution",
        upstream_url: "https://github.com/redroyals/mahan-kosh-multilingual",
        parser_family: "mahan-kosh-json"
      )

      def self.manifest = MANIFEST

      # Entries, not passages — SyncRunner/Rebuild load through
      # Store::DictionaryLoader (architecture §11).
      def self.content_kind = :dictionary

      def self.url_for(name) = "#{RAW_BASE}/#{name}"

      def self.subdir(name) = File.basename(name, ".json")

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |name|
          Nabu::Adapter::HttpProbeTarget.new(
            label: name, zip_url: url_for(name), metadata_url: nil,
            state_subdir: subdir(name), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        core, gurmukhi = FILES.map { |name| File.join(workdir, self.class.subdir(name), name) }
        return unless File.file?(core) && File.file?(gurmukhi)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:core.json", path: File.expand_path(core),
          metadata: { "dictionary" => DICTIONARY_SLUG, "gurmukhi" => File.expand_path(gurmukhi) }
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: MahanKoshJsonParser::LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
        MahanKoshJsonParser.new.entries(core_path: document_ref.path,
                                        gurmukhi_path: document_ref.metadata.fetch("gurmukhi"))
                           .each do |entry|
          document << entry
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "mahan-kosh: #{document_ref.id}: #{e.message}"
      end

      # Both files two-phase (prepare all, breaker over the combined doomed
      # set, complete all) — the fsv-lexica choreography.
      def fetch(workdir, progress: nil, force: false)
        fetches = FILES.to_h do |name|
          sub = self.class.subdir(name)
          [name, Nabu::FileFetch.new(url: self.class.url_for(name), dir: File.join(workdir, sub), filename: name,
                                     attic_dir: File.join(workdir, ATTIC_DIRNAME, sub), progress: progress)]
        end
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        notes = fetches.map { |name, f| "#{name} #{f.sha[0, 8]}" }.join(" · ")
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now,
                              notes: [notes, attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; "))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "mahan-kosh fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
