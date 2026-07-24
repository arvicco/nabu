# frozen_string_literal: true

require "fileutils"
require "json"

module Nabu
  module Adapters
    # KITAB Text Reuse Data — passim text-reuse alignments over OpenITI,
    # registered as a FEATURE MODULE (kind: module), not a text source. It mints
    # NO catalog rows: its data is a links-journal instrument that wires held
    # OpenITI passages to one another with kind="reuse" edges (upstream-computed
    # alignments, distinct from nabu's own kind=parallel intertext detection).
    # The parse/load work lives entirely in the links producer
    # Nabu::KitabTextReuse (producer #9), wired via reference_producer below and
    # run by SyncRunner after every kitab sync — so, like the trismegistos and
    # bridging modules, discover yields NOTHING and parse is unreachable.
    #
    # == License (recorded verbatim — TWO facts, the pilot posture)
    #
    # AUTHORITATIVE: the Zenodo record "KITAB Text Reuse Data", DOI
    # 10.5281/zenodo.11501559, "Creative Commons Attribution Non Commercial
    # Share Alike 4.0 International" (CC BY-NC-SA 4.0) → class "nc" — versioned
    # per OpenITI corpus release (the current version matches our held OpenITI
    # 2025.1.9). The GitHub mirror this fetch reads (kitab-project-org/
    # pairwise-light) carries NO in-repo license file; it is the SAME dataset's
    # per-file access path (the license is the Zenodo record's, not the
    # mirror's). Both facts are recorded here and in config/sources.yml so a
    # public clone can never mistake the mirror's silence for permission.
    #
    # == fetch: the pilot pairwise fan (owner-run, sequential, resumable)
    #
    # The full set is ~1.6M files, so the pilot fetch takes a version-id
    # ALLOWLIST from the registry entry (the `classes:` seam — the house
    # owner-posture passthrough for an adapter's acquisition scope, the kanripo
    # precedent). One folder = one held book's COMPLETE pairwise fan (seeded with
    # ALCorpus00001-ara2). `nabu sync kitab` (owner-run) lists each allowed
    # folder on the mirror and GETs its TSV leaves sequentially with a ≥1s pause,
    # RESUMABLE (a file already on disk is skipped), landing them under
    # canonical/kitab/pairwise/<folder>/. The producer reads that tree.
    #
    # The full-set path (the Zenodo archive, ~1.6M files) is a DOCUMENTED FUTURE
    # STEP, not built here. As with trismegistos, the mirror's exact raw
    # branch/path and any fair-use terms are UNREAD by this fetcher — the owner
    # eyeballs them before the first real sync; the 1s pause is a conservative
    # guess.
    #
    # Like the trismegistos module this deliberately does NOT use
    # Nabu::FileFetch (which dooms every sibling under its dir but the one
    # target): the pairwise tree ACCUMULATES (immutable per-book fans), so the
    # fetch writes each file directly and never touches siblings.
    class Kitab < Nabu::Adapter
      # The mirror's raw per-file base and its contents-listing API. The exact
      # shapes are confirmed at the owner's first sync (class note).
      RAW_BASE = "https://raw.githubusercontent.com/kitab-project-org/pairwise-light/master/data"
      CONTENTS_API = "https://api.github.com/repos/kitab-project-org/pairwise-light/contents/data"

      # Mirrors Nabu::KitabTextReuse::PAIRWISE_DIRNAME (kept literal so the
      # adapter carries no load-order dependency on the producer).
      PAIRWISE_DIRNAME = "pairwise"
      REQUEST_PAUSE_SECONDS = 1.0

      # The pilot allowlist — one held book's complete pairwise fan per folder.
      # Seeded with the P43-4 exemplar; the owner extends it in config/sources.yml
      # (classes: [...]) as more held books' fans are wanted.
      DEFAULT_PILOT_FOLDERS = %w[ALCorpus00001-ara2].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "kitab",
        name: "KITAB Text Reuse Data — passim pairwise alignments over OpenITI (links instrument, pilot)",
        license: "CC BY-NC-SA 4.0 — the Zenodo record \"KITAB Text Reuse Data\" (DOI " \
                 "10.5281/zenodo.11501559), license field verbatim: \"Creative Commons Attribution Non " \
                 "Commercial Share Alike 4.0 International\", versioned per OpenITI corpus release (the " \
                 "current version matches held OpenITI 2025.1.9). NB the GitHub mirror " \
                 "(kitab-project-org/pairwise-light) this fetch reads carries NO in-repo license file — " \
                 "it is the same dataset's per-file access path; the grant is the Zenodo record's.",
        license_class: "nc",
        upstream_url: "https://doi.org/10.5281/zenodo.11501559",
        parser_family: "kitab-text-reuse"
      )

      def self.manifest
        MANIFEST
      end

      # This module's data rides the links journal via KitabTextReuse
      # (producer #9), refreshed by SyncRunner after every sync.
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        Nabu::KitabTextReuse.new(catalog: catalog, journal: journal)
      end

      # +classes+ (the registry `classes:` seam) is the pilot folder allowlist;
      # nil leaves the seeded default (class note). The vocabulary is this
      # adapter's to own — a folder is one held book's version id.
      def initialize(classes: nil)
        super()
        @pilot_folders = classes || DEFAULT_PILOT_FOLDERS
      end

      # A feature module mints no documents — its data is links-graph edges,
      # not passages. Empty by design, not by accident (the bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: kitab is a links instrument, not a text source — " \
                          "its text-reuse alignments ride the links journal (P43-4, KitabTextReuse); " \
                          "parse is unreachable"
      end

      # Fetch each allowed folder's complete pairwise fan (class note). +force+
      # has no destructive surface here (the tree only accumulates), so it is
      # accepted for interface parity and ignored.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        fetched = 0
        skipped = 0
        @pilot_folders.each do |folder|
          dir = File.join(workdir, PAIRWISE_DIRNAME, folder)
          FileUtils.mkdir_p(dir)
          folder_files(folder).each do |name|
            path = File.join(dir, name)
            if File.file?(path)
              skipped += 1
              next
            end
            sleep(REQUEST_PAUSE_SECONDS) unless (fetched + skipped).zero?
            progress&.call("KITAB #{folder}/#{name}…\n")
            File.write(path, fetch_leaf(folder, name))
            fetched += 1
          end
        end
        Nabu::FetchReport.new(sha: nil, fetched_at: Time.now,
                              notes: "kitab pairwise: #{fetched} fetched, #{skipped} already present " \
                                     "(#{@pilot_folders.size} pilot folder(s))")
      end

      private

      # The TSV leaf names of one folder, from the mirror's contents API. Each
      # entry is a {"name" => …, "type" => "file"} object; only the .csv leaves
      # are pairwise files.
      def folder_files(folder)
        url = "#{CONTENTS_API}/#{folder}"
        response, = Nabu::RedirectFollow.get(url, http: Nabu::ZipFetch.default_http,
                                                  error: Nabu::FetchError, accept: [200])
        entries = JSON.parse(response.body.to_s)
        unless entries.is_a?(Array)
          raise Nabu::FetchError, "kitab: contents listing for #{folder} was not a JSON array — " \
                                  "confirm the mirror path (#{url}) before the first real sync"
        end
        entries.filter_map { |entry| entry["name"] if entry["name"].to_s.end_with?(".csv") }.sort
      end

      # GET one pairwise TSV leaf (redirect-following, cert-hardened connection);
      # RedirectFollow raises Nabu::FetchError on any non-200 or transport
      # failure, so the sweep aborts loudly rather than persisting an error body.
      def fetch_leaf(folder, name)
        url = "#{RAW_BASE}/#{folder}/#{name}"
        response, = Nabu::RedirectFollow.get(url, http: Nabu::ZipFetch.default_http,
                                                  error: Nabu::FetchError, accept: [200])
        response.body.to_s
      end
    end
  end
end
