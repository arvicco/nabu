# frozen_string_literal: true

require "digest"

require_relative "lexibank_cldf_parser"

module Nabu
  module Adapters
    # The lexibank-cldf adapter family: the shared machinery every lexibank
    # CLDF Wordlist source runs on (the parser seam is documented in
    # LexibankCldfParser). A dataset joins the library as a tiny subclass
    # declaring ONE value — DATASET, a LexibankCldf::Dataset naming its
    # slug, title, dictionary language, license grant, pinned release and
    # word strategy — plus its config/sources.yml row. Everything else —
    # manifest, discovery, parse, fetch choreography, probe — lives here.
    #
    # Why a subclass per dataset rather than one class parameterized by the
    # registry row: the adapter contract is CLASS-level (Adapter.manifest,
    # .http_probe_targets and .content_kind are read off the class by the
    # registry, health and the rebuild planner, before any instance
    # exists), and manifest.id must equal the slug. A per-row parameter
    # would have to thread the registry entry through every one of those
    # call sites; a declaration-only subclass satisfies the contract with
    # no change outside this family.
    #
    # == Pinning: two arms, both immutable or declared
    #
    # - ZenodoRelease — the dataset's GitHub release archived by the
    #   Zenodo integration: a versioned record (its own DOI) holding one
    #   immutable zip. Fetched through ZipFetch with the phases driven by
    #   hand (the iecor rail): prepare → verify the hard sha256 pin →
    #   mass-deletion breaker → complete; a body missing the pin aborts
    #   before any tree mutation. A new upstream release is a new record:
    #   the owner re-pins URL + sha.
    # - GitRepository — for the lexibank repositories that have never cut
    #   a release (no tag, no Zenodo record): the house GitFetch of the
    #   repository (the meloniromance precedent), sparse to the CLDF
    #   bundle + LICENSE + README.md, with the commit observed at fixture
    #   time recorded in the declaration (+commit+) — the release that
    #   does not exist cannot be pinned, so the row says so.
    #
    # == Grains
    #
    # The accepted grain is the CLDF bundle (cldf/ — ONE document per
    # dataset). Release archives also carry raw/ (upstream's pre-CLDF
    # source material the lexibank script converts) and, for tlopo, out/
    # (the rendered book chapters): each dataset declares those as
    # +rejected_grains+, counted by discovery_skips, never ingested.
    # etc/, the build scripts and the python packaging are machinery.
    class LexibankCldf < Nabu::Adapter
      # A Zenodo versioned record of a GitHub release (the DOI'd archive).
      ZenodoRelease = Data.define(:tag, :record, :url, :sha256) do
        def doi = "10.5281/zenodo.#{record}"
        def label = tag
      end

      # A tagless repository fetched by GitFetch; +commit+ is the head
      # observed when the fixture was cut (documentation of the read, not
      # an enforced pin — GitFetch follows +ref+ or the default branch).
      GitRepository = Data.define(:repo_url, :ref, :commit) do
        def initialize(repo_url:, commit:, ref: nil)
          super
        end

        def label = ref || "default branch @ #{commit[0, 8]}"
      end

      # One dataset's declaration (see the class note).
      Dataset = Data.define(:slug, :name, :title, :label, :language, :license, :upstream_url,
                            :release, :word_from, :varieties, :proto_varieties, :rejected_grains) do
        def initialize(slug:, name:, title:, label:, language:, license:, upstream_url:, release:,
                       word_from: :form, varieties: {}, proto_varieties: [], rejected_grains: {})
          super(slug: slug, name: name, title: title, label: label, language: language, license: license,
                upstream_url: upstream_url, release: release, word_from: word_from,
                varieties: varieties.freeze, proto_varieties: proto_varieties.freeze,
                rejected_grains: rejected_grains.freeze)
        end

        def zenodo? = release.is_a?(ZenodoRelease)
      end

      PARSER_FAMILY = "lexibank-cldf"
      CLDF_DIR = "cldf"
      ANCHOR_FILE = "forms.csv"
      # The GitFetch cone for a tagless repository: the bundle and its grant.
      GIT_SPARSE = %w[cldf LICENSE README.md].freeze

      def self.dataset
        const_defined?(:DATASET, false) or
          raise NotImplementedError, "#{name}: a lexibank-cldf source declares its DATASET"
        self::DATASET
      end

      def self.manifest
        @manifest ||= Nabu::SourceManifest.new(
          id: dataset.slug, name: dataset.name, license: dataset.license,
          license_class: "attribution", upstream_url: dataset.upstream_url,
          parser_family: PARSER_FAMILY
        )
      end

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      # Members mint dictionary_reflexes rows (health holds the promise).
      def self.reflex_bearing? = true

      # Zenodo arms HEAD the immutable artifact; git arms ride the default
      # :git probe against the repository.
      def self.remote_probe_strategy = dataset.zenodo? ? :http_zip : :git

      def self.http_probe_targets
        return [] unless dataset.zenodo?

        [Nabu::Adapter::HttpProbeTarget.new(
          label: "#{dataset.slug}-#{dataset.release.tag}.zip", zip_url: dataset.release.url,
          metadata_url: nil, state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the Zenodo sha256 (tests; an owner re-pin drill).
      def initialize(pin: nil)
        super()
        @pin = pin || (dataset.zenodo? ? dataset.release.sha256 : nil)
      end

      def dataset = self.class.dataset

      # One DocumentRef for the one CLDF bundle — the shallowest cldf/
      # holding forms.csv (ZipFetch flattens the release's single top dir;
      # a hand unpack keeps it; both discover under ONE stable ref id). A
      # workdir without the bundle yields nothing (the pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        anchor = Dir.glob(File.join(workdir, "**", CLDF_DIR, ANCHOR_FILE))
                    .min_by { |path| [path.count(File::SEPARATOR), path] }
        return unless anchor

        yield Nabu::DocumentRef.new(
          source_id: dataset.slug, id: "#{dataset.slug}:#{CLDF_DIR}",
          path: File.expand_path(File.dirname(anchor)), metadata: {}
        )
      end

      # The declared rejected grains present in the tree, one skip each.
      def discovery_skips(workdir)
        present = dataset.rejected_grains.select { |grain, _| File.exist?(File.join(workdir, grain)) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: present.size,
          notes: present.map { |grain, note| "#{note}, not ingested: #{grain}/" }
        )
      end

      def parse(document_ref)
        result = parser.read(document_ref.path)
        document = Nabu::DictionaryDocument.new(
          slug: dataset.slug, language: dataset.language,
          title: dataset.title, canonical_path: document_ref.path
        )
        result.entries.each { |entry| document << entry }
        document
      rescue Nabu::ValidationError, KeyError => e # KeyError: a spine column missing upstream
        raise Nabu::ParseError, "#{dataset.slug}: #{document_ref.id}: #{e.message}"
      end

      # The read's census (sets minted / skipped by rule, unjudged forms)
      # for the adapter test and an operator's first-sync reconciliation.
      def census(document_ref) = parser.read(document_ref.path).census

      def fetch(workdir, progress: nil, force: false)
        return zenodo_fetch(workdir, progress: progress, force: force) if dataset.zenodo?

        release = dataset.release
        git_fetch!(repo_url: release.repo_url, workdir: workdir, progress: progress, force: force,
                   ref: release.ref, sparse: GIT_SPARSE)
      end

      private

      def parser
        LexibankCldfParser.new(slug: dataset.slug, language: dataset.language, label: dataset.label,
                               word_from: dataset.word_from, varieties: dataset.varieties,
                               proto_varieties: dataset.proto_varieties)
      end

      def zenodo_fetch(workdir, progress:, force:)
        release = dataset.release
        fetch = Nabu::ZipFetch.new(url: release.url, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        base = fetch.not_modified? ? "not modified (304)" : "zenodo #{release.tag} sha pin verified"
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now,
                              notes: [base, attic_notes(fetch.atticked)].compact.join("; "))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{dataset.slug} fetch failed into #{workdir}: #{e.message}"
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "#{dataset.slug}: downloaded artifact misses the release sha256 pin (expected #{@pin}, " \
              "got #{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{dataset.release.url} and re-pin only after reading the record"
      end
    end
  end
end
