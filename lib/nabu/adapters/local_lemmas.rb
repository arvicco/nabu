# frozen_string_literal: true

require_relative "../lemma_shelf"
require_relative "../local_fetch"

module Nabu
  module Adapters
    # The local-lemmas shelf (P84-1, architecture §16) — the FIFTH local
    # shelf: local/shelves/local-lemmas/<language>/shard-NNNNNN.jsonl, the
    # silver-lemma enricher's non-derivable model output, written only by
    # the Nabu::LemmaShelf gateway (driven by `nabu lemma-enrich`). An
    # ordinary `kind: shelf` registry row for census purposes — discovery
    # accounting, per-file sha pins, vanished/attic integrity, status —
    # but UNLIKE the other shelves its derived product is FULLTEXT-side:
    # Store::SilverLemmaIndexer projects the shards into passage_lemmas
    # (tier silver) at every rebuild/sync and on `lemma-enrich --index`.
    # The loader lane (content_kind :lemmas → Store::LemmaShelfLoader)
    # therefore only VALIDATES: a malformed shard quarantines loudly, and
    # nothing is derived catalog-side.
    #
    # License doctrine: the shards are locally computed annotation over
    # texts the catalog already holds under their own licenses — the shelf
    # itself carries no upstream text, so class "open" (the local-notes
    # argument); every RENDER of a silver lemma happens beside its passage
    # and inherits that passage's own license handling.
    class LocalLemmas < Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: LemmaShelf::SLUG,
        name: "Silver lemmas (local shelf, model output)",
        license: "Locally computed lemmatization (local shelf; no upstream)",
        license_class: "open",
        upstream_url: "local/shelves/local-lemmas (local — no upstream)",
        parser_family: "lemma-shards"
      )

      SHARD_FILE = %r{\A(?<language>[a-z0-9-]+)/(?<shard>shard-\d{6})\.jsonl\z}

      # What parse yields: the validated shard's honest summary (the
      # loader derives nothing — validation IS the load).
      Shard = Data.define(:language, :shard, :records)

      def self.manifest = MANIFEST

      # Lemma shards parse into fulltext-side rows, not passages/entries/
      # records — the sixth content kind, routed to Store::LemmaShelfLoader
      # (the closed-set rule: a new kind is a deliberate routing decision).
      def self.content_kind = :lemmas

      # No upstream repo to probe: the policy-level "local" verdict
      # short-circuits the remote probe (the P19-1 machinery).
      def self.upstream_repo_urls = []

      # Re-scan the tree (LocalFetch): sha-pins every file, reports
      # un-atticked disappearances loudly, trips the house mass-deletion
      # breaker (--force overrides).
      def fetch(workdir, progress: nil, force: false)
        progress&.call("Scanning #{workdir}…\n")
        result = LocalFetch.sync!(dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force,
                                  hint: "for local-lemmas: bin/nabu lemma-enrich <language>")
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: fetch_notes(result), repos: pin_map(result))
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      # One ref per shard file, sorted for stability. The ref id embeds
      # language + shard stem (ref.id == "local-lemmas:lat/shard-000001").
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        shard_entries(workdir).each do |file, language, shard|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{manifest.id}:#{language}/#{shard}",
            path: File.join(File.expand_path(workdir), file),
            metadata: { "language" => language }
          )
        end
        self
      end

      # Validate one shard through the gateway's own reader (the shapes
      # can never drift apart). Format defects quarantine the SHARD — one
      # broken file never blocks the shelf.
      def parse(document_ref)
        language = document_ref.metadata.fetch("language")
        count = 0
        shelf = LemmaShelf.new(dir: File.dirname(document_ref.path, 2))
        File.foreach(document_ref.path).with_index(1) do |line, lineno|
          record = shelf.parse_line(line, document_ref.path, lineno)
          unless record.language == language
            raise LemmaShelf::FormatError,
                  "#{File.basename(document_ref.path)}:#{lineno} claims language " \
                  "#{record.language.inspect} in the #{language} lane"
          end
          count += 1
        end
        Shard.new(language: language, shard: File.basename(document_ref.path, ".jsonl"), records: count)
      rescue LemmaShelf::FormatError, Errno::ENOENT, Errno::EACCES => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      end

      private

      def shard_entries(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.glob("*/shard-*.jsonl", base: workdir).sort.filter_map do |file|
          match = SHARD_FILE.match(file)
          [file, match[:language], match[:shard]] if match
        end
      end

      # Live files pin under their sha; vanished-un-atticked files keep
      # their last-known sha so the ledger pin LINGERS and health stays
      # loud (the P19-1 story, verbatim).
      def pin_map(result)
        result.files.merge(result.vanished).transform_keys { |rel| "local:#{rel}" }
      end

      def fetch_notes(result)
        notes = []
        unless result.vanished.empty?
          notes << "#{result.vanished.size} file(s) VANISHED without an attic copy: " \
                   "#{result.vanished.keys.join(', ')} — restore from backup, or move to .attic/ to retire"
        end
        notes << "#{result.retired} file(s) retired into the attic" if result.retired.positive?
        notes.empty? ? nil : notes.join("; ")
      end
    end
  end
end
