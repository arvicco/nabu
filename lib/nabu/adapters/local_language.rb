# frozen_string_literal: true

require_relative "../language_dossier"
require_relative "../language_shelf"
require_relative "../local_fetch"

module Nabu
  module Adapters
    # The local-language dossier shelf (P19-1, architecture §16) — the FIRST
    # local shelf: canonical/local-language/<code>.md, one owner-editable
    # Markdown dossier per language code, parsed into the catalog's derived
    # language_records (content_kind :language → Store::LanguageDossierLoader).
    # An ordinary source in every pipeline sense — registry entry, discovery
    # accounting, quarantine on malformed dossiers, attic rediscovery,
    # rebuild — with `kind: shelf`: no upstream, no network; #fetch is
    # LocalFetch (re-scan + per-file sha pins), and programmatic accretion
    # goes through Nabu::LanguageShelf, the local shelf's fetch analogue.
    #
    # License doctrine: the dossiers are the owner's own curation (the prose
    # that lived in config/languages.yml — reviewed in this repo's git — plus
    # accreted summaries of held sources' metadata), so the shelf is class
    # "open"; the drift probe never fetches anything for it (verdict "local").
    class LocalLanguage < Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: LanguageShelf::SLUG,
        name: "Language dossiers (local shelf)",
        license: "Owner-authored curation (local shelf; no upstream)",
        license_class: "open",
        upstream_url: "canonical/local-language (local — no upstream)",
        parser_family: "language-dossier"
      )

      # <code>.md where the basename is a plausible language code — the same
      # shape the model validates ("chu", "zle-ort", "ine-bsl-pro").
      DOSSIER_FILE = /\A(?<code>[a-z]{2,3}(?:-[A-Za-z0-9]{1,8})*)\.md\z/

      def self.manifest = MANIFEST

      # Dossiers parse into per-language records, not passages or entries —
      # the third content kind, routed to Store::LanguageDossierLoader.
      def self.content_kind = :language

      # No upstream repo to probe: the policy-level "local" verdict
      # short-circuits the remote probe before any strategy dispatch
      # (Health::RemoteProbe#probe_local_source).
      def self.upstream_repo_urls = []

      # Re-scan the tree (LocalFetch): validates it exists, sha-pins every
      # dossier (FetchReport#repos → one ledger pin per file, keyed
      # "local:<relative path>"), reports un-atticked disappearances loudly,
      # and trips the house mass-deletion breaker (--force overrides).
      def fetch(workdir, progress: nil, force: false)
        progress&.call("Scanning #{workdir}…\n")
        result = LocalFetch.sync!(dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force,
                                  hint: "for local-language: nabu language --export-dossiers")
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: fetch_notes(result), repos: pin_map(result))
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      # One ref per well-formed dossier filename, sorted for stability. The
      # ref id embeds the code (ref.id == "local-language:<code>"), the
      # loader's upsert key.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        dossier_entries(workdir).each do |file, code|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{manifest.id}:#{code}",
            path: File.join(File.expand_path(workdir), file), metadata: { "code" => code }
          )
        end
        self
      end

      # .md files whose basename is NOT a language code (a stray README) are
      # explicit, benign skips — counted so the accounting stays honest.
      def discovery_skips(workdir)
        skipped = markdown_files(workdir).count { |file| DOSSIER_FILE.match(file).nil? }
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      # Parse one dossier into a Nabu::LanguageDossier. Format defects (bad
      # front matter, code/filename mismatch, malformed or duplicate
      # sections) quarantine the FILE — one broken dossier never blocks the
      # shelf.
      def parse(document_ref)
        text = File.read(document_ref.path, encoding: "UTF-8")
        LanguageDossier.parse(text, code: document_ref.metadata.fetch("code"))
      rescue LanguageDossier::FormatError, Errno::ENOENT, Errno::EACCES => e
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
          [file, match[:code]] if match
        end
      end

      # Live files pin under their sha; vanished-un-atticked files keep their
      # last-known sha in the map so the ledger pin LINGERS (SyncRunner
      # deletes pins absent from this map) and health stays loud until the
      # owner restores or deliberately attics the file.
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
