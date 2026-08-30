# frozen_string_literal: true

require_relative "monlam_wordlist_parser"

module Nabu
  module Adapters
    # The Monlam headword-list shelf (P88-A3): MonlamIT/Tibetan-Lexicon —
    # the ONLY licensed machine-readable slice of the Monlam dictionary
    # world (Apache-2.0, in-repo LICENSE.txt verified 2026-08-29; the
    # README repeats the grant). Two lanes under one `monlam-lexicon`
    # dictionary slug, language bod (the wiktionary-bo modern-lexicon
    # convention; the desk's xct/otb corpora stay separate):
    #
    #   monlam   the Monlam Dictionary list      107,113 entries (UTF-16LE
    #            + BOM + CRLF + "word" header — the older edition)
    #   grand    the Monlam GRAND Dictionary     342,716 entries (UTF-8,
    #            list                            headerless)
    #
    # == What this shelf is NOT (recorded so nobody re-scouts)
    #
    # HEADWORDS ONLY — gloss nil is honest (the tibetan-verbs precedent).
    # Every definitions-bearing Monlam artifact found 2026-08-29 is
    # UNLICENSED and parked: iamironrabbit/monlam-dictionary's 36 MB app
    # SQLite (LICENSE covers only bundled fonts), 10zintopjor's ~250 MB
    # scraped Grand-Dictionary CSVs (no license, scraped provenance),
    # MonlamIT/TibetWord, MonlamAI's bo_en json. Definitions need an
    # upstream ask (the correspondence lane), never the scrape.
    #
    # == The lexicon-2 hole (censused 2026-08-29; .docs/upstream-reports.md)
    #
    # The Grand list's file has ONE contiguous 24,295-line blank run
    # (raw lines 224,165–248,459): the late-འ…ཡ alphabetical band is
    # absent upstream, so the README's "367,011" counts raw lines, not
    # entries — 342,716 is the real count. Empty lines skip honestly.
    #
    # == fetch / sync policy
    #
    # Plain GitFetch of the whole repo (4 files, ~29 MB working tree)
    # through the attic + breaker contract. Upstream is dormant (last
    # push 2024-02-19, "Cleanup and updated licence") → sync_policy
    # manual; a revived upstream is an owner re-sync.
    class MonlamLexicon < Nabu::Adapter
      REPO_URL = "https://github.com/MonlamIT/Tibetan-Lexicon"

      DICTIONARY_SLUG = "monlam-lexicon"
      LANGUAGE = "bod"
      TITLE = "Monlam Tibetan headword lists (MonlamIT/Tibetan-Lexicon)"

      # The two lane files, deposit-censused: physical shape + display name.
      LANES = {
        "monlam-lexicon-1.txt" => { lane: "monlam", encoding: "UTF-16LE", header: true,
                                    lane_title: "Monlam Dictionary" },
        "monlam-lexicon-2.txt" => { lane: "grand", encoding: "UTF-8", header: false,
                                    lane_title: "Monlam Grand Dictionary" }
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "monlam-lexicon",
        name: "Monlam Tibetan headword lists (MonlamIT/Tibetan-Lexicon)",
        license: "Apache-2.0 (in-repo LICENSE.txt, © 2024 Monlam IT, verified 2026-08-29; " \
                 "the repo holds only the word lists, so the grant covers the data). This is " \
                 "the HEADWORD-LIST slice — no Monlam definitions are licensed anywhere " \
                 "machine-readable; credit Monlam IT",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "monlam-wordlist"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One DocumentRef per present lane file, sorted by id. The same walk
      # works under the attic; a pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        LANES.keys.sort.each do |filename|
          path = File.join(workdir, filename)
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{filename}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        lane = LANES.fetch(File.basename(document_ref.path))
        MonlamWordlistParser.new.parse(
          document_ref.path,
          lane: lane.fetch(:lane), lane_title: lane.fetch(:lane_title),
          header: lane.fetch(:header), encoding: lane.fetch(:encoding),
          slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "monlam-lexicon: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the repo via the shared git path
      # (GitFetch: attic + pre-merge mass-deletion breaker).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        manifest.upstream_url
      end
    end
  end
end
