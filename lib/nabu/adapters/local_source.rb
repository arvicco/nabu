# frozen_string_literal: true

require_relative "../source_dossier"
require_relative "../source_shelf"
require_relative "../local_fetch"

module Nabu
  module Adapters
    # The local-source dossier shelf (P24-0, architecture §16) — the THIRD
    # local shelf: canonical/local-source/<slug>.md, one owner-editable
    # Markdown dossier per REGISTERED SOURCE, parsed into the catalog's
    # derived source_records (content_kind :source →
    # Store::SourceDossierLoader). An ordinary source in every pipeline
    # sense — registry entry, discovery accounting, quarantine on malformed
    # dossiers, attic rediscovery, rebuild — with `sync_policy: local`: no
    # upstream, no network; #fetch is LocalFetch (re-scan + per-file sha
    # pins), and programmatic accretion goes through Nabu::SourceShelf, the
    # local shelf's fetch analogue.
    #
    # License doctrine: the dossiers are the owner's own curation (shelf
    # descriptions distilled from docs/library.md and sources.yml, plus the
    # owner's prose), so the shelf is class "open"; the drift probe never
    # fetches anything for it (verdict "local").
    class LocalSource < Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: SourceShelf::SLUG,
        name: "Source dossiers (local shelf)",
        license: "Owner-authored curation (local shelf; no upstream)",
        license_class: "open",
        upstream_url: "canonical/local-source (local — no upstream)",
        parser_family: "source-dossier"
      )

      # <slug>.md where the basename is a plausible source slug — the
      # registry's own shape ("edh", "first1k-greek", "local-language").
      DOSSIER_FILE = /\A(?<slug>[a-z0-9]+(?:-[a-z0-9]+)*)\.md\z/

      def self.manifest = MANIFEST

      # Dossiers parse into per-source records, not passages or entries —
      # the fourth content kind, routed to Store::SourceDossierLoader.
      def self.content_kind = :source

      # No upstream repo to probe: the policy-level "local" verdict
      # short-circuits the remote probe before any strategy dispatch
      # (Health::RemoteProbe#probe_local_source).
      def self.upstream_repo_urls = []

      # Re-scan the tree (LocalFetch): validates it exists, sha-pins every
      # dossier (FetchReport#repos → one ledger pin per file, keyed
      # "local:<relative path>"), reports un-atticked disappearances loudly,
      # and trips the house mass-deletion breaker (--force overrides).
      def fetch(workdir, progress: nil, force: false)
        progress&.call("Scanning #{workdir}…")
        result = LocalFetch.sync!(dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force,
                                  hint: "for local-source: nabu list --export-source-dossiers")
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: fetch_notes(result), repos: pin_map(result))
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      # One ref per well-formed dossier filename, sorted for stability. The
      # ref id embeds the slug (ref.id == "local-source:<slug>"), the
      # loader's upsert key.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        dossier_entries(workdir).each do |file, slug|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{manifest.id}:#{slug}",
            path: File.join(File.expand_path(workdir), file), metadata: { "slug" => slug }
          )
        end
        self
      end

      # .md files whose basename is NOT a plausible slug (a stray README)
      # are explicit, benign skips — counted so the accounting stays honest.
      def discovery_skips(workdir)
        skipped = markdown_files(workdir).count { |file| DOSSIER_FILE.match(file).nil? }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      # Parse one dossier into a Nabu::SourceDossier. Format defects (bad
      # front matter, slug/filename mismatch, malformed or duplicate
      # sections) quarantine the FILE — one broken dossier never blocks the
      # shelf.
      def parse(document_ref)
        text = File.read(document_ref.path, encoding: "UTF-8")
        SourceDossier.parse(text, slug: document_ref.metadata.fetch("slug"))
      rescue SourceDossier::FormatError, Errno::ENOENT, Errno::EACCES => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      end

      private

      def markdown_files(workdir)
        return [] unless Dir.exist?(workdir)

        Dir.glob("*.md", base: workdir).sort
      end

      def dossier_entries(workdir)
        markdown_files(workdir).filter_map do |file|
          match = DOSSIER_FILE.match(file)
          [file, match[:slug]] if match
        end
      end

      # Live files pin under their sha; vanished-un-atticked files keep
      # their last-known sha in the map so the ledger pin LINGERS
      # (SyncRunner deletes pins absent from this map) and health stays
      # loud until the owner restores or deliberately attics the file.
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
