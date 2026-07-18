# frozen_string_literal: true

require_relative "../note_file"
require_relative "../note_shelf"
require_relative "../local_fetch"

module Nabu
  module Adapters
    # The local-notes shelf (P24-1, architecture §16) — the THIRD local
    # shelf: canonical/local-notes/<topic>.yml, one owner-curated YAML notes
    # file per topic, parsed into the catalog's derived urn_notes rows
    # (content_kind :notes → Store::NoteLoader). An ordinary source in every
    # pipeline sense — registry entry, discovery accounting, quarantine on a
    # malformed topic file, attic rediscovery, rebuild — with `sync_policy:
    # local`: no upstream, no network; #fetch is LocalFetch (re-scan +
    # per-file sha pins), and programmatic accretion goes through
    # Nabu::NoteShelf, the shelf's one sanctioned write gateway (driven by
    # `nabu note`).
    #
    # License doctrine: the notes are the owner's own annotations, so the
    # SHELF is class "open" (the local-language argument) — but a note
    # renders only beside its TARGET urn, and the MCP surface withholds a
    # note wherever the target document itself is withheld
    # (research_private/restricted): owner metadata is useful context, a
    # withheld text's content frame is not.
    class LocalNotes < Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: NoteShelf::SLUG,
        name: "Owner notes on urns (local shelf)",
        license: "Owner-authored annotations (local shelf; no upstream)",
        license_class: "open",
        upstream_url: "canonical/local-notes (local — no upstream)",
        parser_family: "urn-notes"
      )

      # <topic>.yml where the basename is an honest topic name (the
      # NoteShelf::TOPIC_NAME shape, matched here so gateway and discovery
      # can never disagree on what is a topic file). "manifest" is RESERVED
      # shelf furniture, not a topic — the fixture-manifest convention and
      # the other shelves' record file both claim the name, and the gateway
      # refuses it symmetrically.
      NOTE_FILE = /\A(?<topic>[a-z0-9][a-z0-9_-]*)\.yml\z/
      RESERVED_TOPICS = NoteShelf::RESERVED_TOPICS

      def self.manifest = MANIFEST

      # Notes parse into per-urn annotation rows, not passages or entries —
      # the fourth content kind, routed to Store::NoteLoader (the closed-set
      # rule: a new kind means a new loader and a deliberate routing
      # decision).
      def self.content_kind = :notes

      # No upstream repo to probe: the policy-level "local" verdict
      # short-circuits the remote probe (the P19-1 machinery).
      def self.upstream_repo_urls = []

      # Re-scan the tree (LocalFetch): sha-pins every file, reports
      # un-atticked disappearances loudly, trips the house mass-deletion
      # breaker (--force overrides).
      def fetch(workdir, progress: nil, force: false)
        progress&.call("Scanning #{workdir}…\n")
        result = LocalFetch.sync!(dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force,
                                  hint: "for local-notes: bin/nabu note URN \"TEXT\"")
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: fetch_notes(result), repos: pin_map(result))
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      # One ref per well-formed topic filename, sorted for stability. The
      # ref id embeds the topic (ref.id == "local-notes:<topic>"), the
      # loader's replace key.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        topic_entries(workdir).each do |file, topic|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{manifest.id}:#{topic}",
            path: File.join(File.expand_path(workdir), file), metadata: { "topic" => topic }
          )
        end
        self
      end

      # .yml files whose basename is NOT a topic name (reserved furniture
      # included) are explicit, benign skips — counted so the accounting
      # stays honest (the dossier-shelf precedent; README.md is outside the
      # content pattern entirely).
      def discovery_skips(workdir)
        skipped = yaml_files(workdir).count { |file| topic_for(file).nil? }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      # Parse one topic file into a Nabu::NoteFile. Format defects (wrong
      # shape, bad record) quarantine the FILE — one broken topic never
      # blocks the shelf.
      def parse(document_ref)
        NoteFile.load(document_ref.path, topic: document_ref.metadata.fetch("topic"))
      rescue NoteFile::FormatError, Errno::ENOENT, Errno::EACCES => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      rescue Nabu::Normalize::EncodingError => e
        raise ParseError, "#{document_ref.id}: undecodable text (#{e.message})"
      end

      private

      def yaml_files(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.glob("*.yml", base: workdir).sort
      end

      def topic_entries(workdir)
        yaml_files(workdir).filter_map do |file|
          topic = topic_for(file)
          [file, topic] if topic
        end
      end

      def topic_for(file)
        match = NOTE_FILE.match(file)
        return nil if match.nil? || RESERVED_TOPICS.include?(match[:topic])

        match[:topic]
      end

      # Live files pin under their sha; vanished-un-atticked files keep
      # their last-known sha so the ledger pin LINGERS and health stays loud
      # (the P19-1 story, verbatim).
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
