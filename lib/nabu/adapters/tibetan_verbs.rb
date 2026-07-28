# frozen_string_literal: true

require_relative "flat_csv_parser"
require_relative "../normalize"

module Nabu
  module Adapters
    # The Tibetan Verbs Database adapter (P48-4): the tibetan-nlp TVD —
    # 2,491 CSV rows of verb tense stems (present, past, future,
    # imperative; Tibetan script), each attributed to its lexicographic
    # sources (TDC / PH / GT / KN columns). Upstream deliberately keeps the
    # grammarians' disagreements as separate rows ("no choice has been made
    # about the correctness of the different forms" — upstream README), so
    # one present stem may head several paradigm rows; every row mints its
    # own entry, the tense stems as entry apparatus.
    #
    # == Shape (censused whole-file 2026-07-28)
    #
    # Header IS Tibetan: ད་ལྟ,འདས་པ,མ་འོངས,སྐུལ་ཚིག + TDC,PH,GT,KN. 2,491
    # data rows; present never empty; past/future empty on 11 rows,
    # imperative on 599; source cells carry exactly their column names;
    # the second-suffix ད rides upstream's own ༼ད༽ notation verbatim.
    #
    # - entry_id: the four stems joined ":" with empty cells as "-"
    #   (intrinsically stable — no positional dependence), plus a
    #   positional ":<n>" for the 5 whole-file duplicate 4-tuples (same
    #   paradigm restated under different source attributions).
    # - headword: the present stem (ད་ལྟ), the citation form.
    # - gloss: nil — the database carries NO translations; honest absence.
    # - body: labeled lanes (Present/Past/Future/Imperative, empty lanes
    #   omitted) + "Sources: TDC · PH · …".
    #
    # == License
    #
    # CC0-1.0 — the in-repo LICENSE file carries the full CC0 legal code
    # (verified 2026-07-28; the GitHub license field agrees) → class open.
    class TibetanVerbs < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "tibetan-verbs",
        name: "Tibetan Verbs Database (tibetan-nlp TVD)",
        license: "CC0-1.0 (in-repo LICENSE, the full CC0 legal code; verified 2026-07-28)",
        license_class: "open",
        upstream_url: "https://github.com/tibetan-nlp/tibetan-verbs-database",
        parser_family: "flat-csv"
      )

      CSV_FILENAME = "db.csv"
      DICTIONARY_SLUG = "tibetan-verbs"
      LANGUAGE = "bod"
      TITLE = "Tibetan Verbs Database — verb tense stems (TVD)"

      # The upstream header, verbatim: present, past, future, imperative in
      # Tibetan, then the four source columns. A silent upstream rename
      # must fail loudly (FlatCsvParser's required-headers contract).
      STEM_COLUMNS = {
        "Present" => "ད་ལྟ",
        "Past" => "འདས་པ",
        "Future" => "མ་འོངས",
        "Imperative" => "སྐུལ་ཚིག"
      }.freeze
      SOURCE_COLUMNS = %w[TDC PH GT KN].freeze

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # Clone or non-destructively pull the repo via the shared git path
      # (GitFetch: attic + pre-merge mass-deletion breaker). The default
      # :git probe strategy ls-remotes the same URL.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: manifest.upstream_url, workdir: workdir, progress: progress, force: force)
      end

      # One DocumentRef for the one CSV. A workdir without it yields
      # nothing (the day-one pre-fetch state); the same walk works under
      # the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", CSV_FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{CSV_FILENAME}",
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
        occurrences = Hash.new(0)
        parser.each_row(document_ref.path) do |row|
          document << build_entry(row, occurrences)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "tibetan-verbs: #{document_ref.id}: #{e.message}"
      end

      private

      def parser
        FlatCsvParser.new(required_headers: STEM_COLUMNS.values + SOURCE_COLUMNS)
      end

      def build_entry(row, occurrences)
        stems = STEM_COLUMNS.transform_values { |column| row[column].to_s.strip }
        entry_id = positional_id(stems.values.map { |stem| stem.empty? ? "-" : stem }.join(":"), occurrences)
        present = stems.fetch("Present")

        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: present, language: LANGUAGE,
          headword: Nabu::Normalize.nfc(present),
          headword_folded: Nabu::Normalize.search_form(present, language: LANGUAGE),
          gloss: nil,
          body: body_text(stems, sources(row)),
          citations: []
        )
      end

      def positional_id(id, occurrences)
        occurrences[id] += 1
        occurrences[id] > 1 ? "#{id}:#{occurrences[id]}" : id
      end

      def sources(row)
        SOURCE_COLUMNS.filter_map { |column| row[column].to_s.strip }.reject(&:empty?)
      end

      # Labeled lanes, empty stems omitted (never faked), then the source
      # attributions.
      def body_text(stems, sources)
        lines = stems.filter_map { |label, stem| "#{label}: #{stem}" unless stem.empty? }
        lines << "Sources: #{sources.join(' · ')}" unless sources.empty?
        Nabu::Normalize.nfc(lines.join("\n"))
      end
    end
  end
end
