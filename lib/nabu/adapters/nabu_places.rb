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
