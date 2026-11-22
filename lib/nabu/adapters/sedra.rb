# frozen_string_literal: true

require "digest"

require_relative "sedra_jsonl_parser"

module Nabu
  module Adapters
    # Sedra — the Syriac lexical database of Beth Mardutho: The Syriac
    # Institute (George A. Kiraz, Editor-in-Chief; edited by George A.
    # Kiraz and James Bennett), sedra.bethmardutho.org. Classical Syriac
    # roots, lexemes, word forms with their morphology and vocalization,
    # glosses (English, French, Arabic, Latin, Greek …) and etymologies,
    # drawn from the lexicons of its partners — Sedra III, Brock & Kiraz's
    # Gorgias Concise Dictionary, Margoliouth's Compendious Dictionary and
    # Supplement, Payne Smith's Thesaurus, Brockelmann's Lexicon Syriacum,
    # Audo, Costaz, Bar Bahlul, Ciancaglini's Iranian Loanwords … (the
    # sources table). The library's first Syriac lexicon proper, beside the
    # wiktionary-syc extract.
    #
    # == Version pin and fetch
    #
    # PINNED to the numbered release 5.0 (released 2026-10-24 — "a weekly
    # release kept for good, to cite: its files never change", per
    # pages/downloads.html; listed in /releases/index.json): ONE ZipFetch
    # of /releases/v5.0/sedra-2026-10-24.zip (13,604,317 B), the sha256 the
    # release index publishes checked BEFORE the tree mutates. The zip's
    # single top directory is stripped, so the tree is the release's own
    # files; nothing is materialized beside it. The site's robots.txt asks
    # for exactly this ("If you want the data, please fetch these instead
    # of crawling the site") — the API and pages are never touched.
    # Re-pin = a conscious move to a newer numbered release.
    #
    # == Delivery grains (the release README's own table, 2026-10-24)
    #
    # Two formats of the same data plus documentation. ACCEPTED — joined
    # into ONE dictionary document (ref sedra:lexemes.jsonl.gz): the Sedra
    # V tables lexemes (the entry grain, 35,892 rows), roots (3,465),
    # words (65,000), glosses (67,692), etymologies (3,078) and the
    # lookups they reference (sources, languages, category_types, kaylos,
    # tenses, numbers, persons, genders, states). SKIPPED BY RULE (each
    # counted in discovery_skips with its note): sedra4/ (words, lexemes,
    # roots, definitions.json, semiticLanguages.xsd — "exactly as the Sedra
    # IV API answered", the same rows in the older format), the paradigm
    # tables (conjugation_templates; conjugations, empty in this release),
    # and the lookups no entry row references (stems — words.stem_id is
    # null in all 65,000 rows; vowels; authors; transliteration_schemes;
    # transliteration_patterns). README.md is documentation. Any other
    # table-shaped file is UNRECOGNIZED.
    #
    # Reconciliation (parse of the full release, 2026-11-22): 35,892
    # lexeme rows = 35,891 entries + 1 headwordless row skipped by rule
    # (lexeme 28521: empty Syriac, one empty word form, no gloss — nothing
    # to mint); 67,692 glosses, 3,078 etymologies and 65,000 words all
    # attach to a lexeme (the README: "Sedra IV rows not in this release: 2
    # words and 229 glosses that belong to no lexeme"). Inside the entries:
    # 66,451 glosses (1,241 cells hold no text — empty, spaces or a lone
    # RLM — absence), 3,078 etymology rows → 2,995 reflexes (83 rows name
    # only a language), 64,999 word forms (the one empty form is row
    # 28521's). 6,955 entries carry no gloss in any language.
    #
    # == License (the release README, verbatim, read 2026-11-22)
    #
    # "Copyright © 2011–2026 Beth Mardutho: The Syriac Institute. The data
    # in this release is licensed under the Creative Commons
    # Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0):
    # you may share and adapt it for non-commercial purposes, giving credit
    # to Sedra and Beth Mardutho." The README adds: "the resource partners
    # require credit"; CITATION.cff: license "CC-BY-NC-4.0". → class nc.
    # Cite: Sedra, edited by George A. Kiraz and James Bennett. Beth
    # Mardutho: The Syriac Institute. Data release 5.0 (2026),
    # https://sedra.bethmardutho.org/releases/v5.0/.
    class Sedra < Nabu::Adapter
      SLUG = "sedra"
      LANGUAGE = "syc"

      RELEASE = "5.0"
      RELEASE_URL = "https://sedra.bethmardutho.org/releases/v5.0/"
      ZIP_URL = "#{RELEASE_URL}sedra-2026-10-24.zip".freeze

      # sha256 of sedra-2026-10-24.zip as /releases/index.json publishes it
      # (verified against the download, 2026-11-22).
      RELEASE_SHA256 = "b1a0bca072f5766fbd44ac5368c1225f9a370957e7cdf9b025ea7e060dd7e89b"

      ENTRY_TABLE = "lexemes.jsonl.gz"

      # The Sedra V tables the entry join reads.
      JOINED = %w[lexemes roots words glosses etymologies sources languages category_types kaylos
                  tenses numbers persons genders states].map { |t| "#{t}.jsonl.gz" }.freeze

      # The release's other files, each skipped by rule with its reason.
      SKIPPED = {
        "conjugation_templates.jsonl.gz" => "the conjugation paradigm templates — patterns, not entries",
        "conjugations.jsonl.gz" => "the generated conjugations table (empty in this release)",
        "stems.jsonl.gz" => "verb-class descriptions no word row references (stem_id is always null)",
        "vowels.jsonl.gz" => "the vowel lookup — vowel ids ride the lexeme rows only",
        "authors.jsonl.gz" => "the lexicographers table — no entry row references it",
        "transliteration_schemes.jsonl.gz" => "the romanization schemes — transliterations ride the rows",
        "transliteration_patterns.jsonl.gz" => "the romanization patterns — transliterations ride the rows"
      }.freeze

      SEDRA4_NOTE = "the Sedra IV format of the same rows (\"exactly as the Sedra IV API answered\")"

      # Table-shaped files the discovery census accounts for.
      DATA_GLOB = "**/*.{jsonl.gz,json,xsd}"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Sedra — the Syriac lexical database of Beth Mardutho (data release 5.0)",
        license: "CC BY-NC 4.0 (class nc). Release README verbatim: \"Copyright © 2011–2026 Beth " \
                 "Mardutho: The Syriac Institute. The data in this release is licensed under the " \
                 "Creative Commons Attribution-NonCommercial 4.0 International licence (CC BY-NC 4.0): " \
                 "you may share and adapt it for non-commercial purposes, giving credit to Sedra and " \
                 "Beth Mardutho.\" (read 2026-11-22; the resource partners require credit). Cite: Sedra, " \
                 "edited by George A. Kiraz and James Bennett. Beth Mardutho: The Syriac Institute. " \
                 "Data release 5.0 (2026), https://sedra.bethmardutho.org/releases/v5.0/",
        license_class: "nc",
        upstream_url: "https://sedra.bethmardutho.org",
        parser_family: "sedra-jsonl",
        credit: "Sedra, edited by George A. Kiraz and James Bennett — Beth Mardutho: The Syriac " \
                "Institute (data release 5.0, 2026), with its resource partners"
      )

      TITLE = "Sedra — Syriac lexical database (Beth Mardutho, data release 5.0)"

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: File.basename(ZIP_URL), zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the zip sha256 (tests; the re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, ENTRY_TABLE)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{SLUG}:#{ENTRY_TABLE}", path: File.expand_path(path),
                                    metadata: { "dictionary" => SLUG, "path" => ENTRY_TABLE })
      end

      def discovery_skips(workdir)
        return DiscoverySkips.new unless File.directory?(workdir)

        files = Dir.glob(DATA_GLOB, base: workdir).sort.reject { |rel| rel.start_with?("#{ATTIC_DIRNAME}/") }
        others = files - JOINED
        by_rule, strays = others.partition { |rel| SKIPPED.key?(rel) || rel.start_with?("sedra4/") }
        notes = by_rule.map { |rel| "#{rel}: #{SKIPPED.fetch(rel, SEDRA4_NOTE)}" } +
                strays.map { |rel| "#{rel}: not a recognized Sedra release file" }
        lexemes = File.join(workdir, ENTRY_TABLE)
        if File.file?(lexemes)
          SedraJsonlParser.new(workdir).headwordless.each do |row|
            notes << "#{ENTRY_TABLE} row #{row['id']}: no Syriac headword — mints no entry (skipped by rule)"
          end
        end
        DiscoverySkips.new(skipped_by_rule: by_rule.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        parser = SedraJsonlParser.new(File.dirname(document_ref.path))
        document = Nabu::DictionaryDocument.new(slug: SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        parser.entries(language: LANGUAGE).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "sedra: #{document_ref.id}: #{e.message}"
      end

      # The zip prepared and sha256-verified BEFORE the guard and BEFORE
      # the tree mutates (the opengnt choreography).
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
                                   progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        notes = [fetch.not_modified? ? "not modified (304)" : "release #{RELEASE} zip sha256 pin verified",
                 attic_notes(fetch.atticked)].compact.join("; ")
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: notes)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "sedra fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "sedra: downloaded zip misses the sha256 pin (expected #{@pin}, got #{fetch.sha}) — a " \
              "numbered release's files never change, so this is corruption; verify #{ZIP_URL} against " \
              "https://sedra.bethmardutho.org/releases/index.json and re-pin only after reading it"
      end
    end
  end
end
