# frozen_string_literal: true

require_relative "../places"

module Nabu
  module Adapters
    # nabu-places — the place-matching decisions registry (P63-6, the
    # nabu-lects sibling: source → verbatim name string → gazetteer refs /
    # status, identity-default), registered as a FEATURE MODULE: discover
    # mints no documents; the data rides Nabu::Places (read-only) and is
    # projected into document_axes.place_ref by `nabu place apply` (P63-7).
    # Fetch clones the whole repo via the sanctioned GitFetch gateway (the
    # nabu-lects posture — the repo is a few KB of YAML).
    class NabuPlaces < Nabu::Adapter
      REPO_URL = "https://github.com/arvicco/nabu-places.git"

      MANIFEST = Nabu::SourceManifest.new(
        id: "nabu-places",
        name: "nabu-places — the place-matching decisions registry",
        license: "CC BY 4.0 (repo LICENSE verbatim: \"Creative Commons Attribution 4.0 " \
                 "International (CC BY 4.0)\")",
        license_class: "attribution",
        upstream_url: "https://github.com/arvicco/nabu-places",
        parser_family: "nabu-places"
      )

      def self.manifest
        MANIFEST
      end

      # P63 native lane (owner ruling 2026-08-09): the registry's OWN minted
      # records (places.yml) derive into the place index as the "np" slice —
      # minted places resolve on the desk like any gazetteer's. Empty lane =
      # zero rows, honestly.
      def self.place_index_producer? = true

      def self.place_index_producer(catalog:)
        MintedProducer.new(catalog: catalog)
      end

      class MintedProducer
        def initialize(catalog:)
          @catalog = catalog
        end

        def run(_slug, workdir:)
          rows = Nabu::Places.minted(workdir)
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          count = Nabu::Store::PlaceIndex.derive!(
            @catalog, gazetteer: "np", places: rows, names_for: :name_keys.to_proc
          )
          return nil if count.nil?

          derive_crosswalks!(workdir)
          Nabu::Store::PlaceIndex::Producer::Census.new(
            places: count,
            seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          )
        end

        private

        # P64-2: the registry's crosswalks.csv (asserted equivalences with
        # harvest provenance) derives per-source wholesale — each harvest
        # source owns its slice, the cigs contract.
        def derive_crosswalks!(workdir)
          return unless @catalog.table_exists?(:place_crosswalk)

          rows = Nabu::Places.crosswalks(workdir)
          by_source = rows.group_by(&:source)
          @catalog.transaction do
            by_source.each do |source, group|
              @catalog[:place_crosswalk].where(source: source).delete
              inserts = group.map do |x|
                { source: source, gazetteer_a: x.gazetteer_a, id_a: x.id_a,
                  gazetteer_b: x.gazetteer_b, id_b: x.id_b }
              end
              inserts.uniq.each_slice(1_000) { |s| @catalog[:place_crosswalk].multi_insert(s) }
            end
          end
        end
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: nabu-places is a decisions-registry module, not a " \
                          "text source — its data rides Nabu::Places (P63-7); parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      def repo_url
        REPO_URL
      end
    end
  end
end
