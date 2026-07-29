# frozen_string_literal: true

module Nabu
  module Adapters
    # OSL — the Oracc Sign List (github.com/oracc/osl, ex-OGSL; Veldhuis &
    # Tinney; rolling master, stable @oid identifiers), registered as a
    # FEATURE MODULE (kind: module), not a text source. It mints NO catalog
    # rows: its data is the Nabu::SignList read seam over the one machine
    # artifact `00lib/osl.asl` (~979 KB, the line-oriented ASL grammar,
    # parsed by Nabu::Adapters::AslParser) — ATF value → sign records with
    # Unicode codepoints, the P53-2 `nabu signs` surface's substrate (the
    # Edubba downstream). So, like the hypotactic/cldf-spine modules,
    # discover yields NOTHING and parse is unreachable.
    #
    # DO NOT build on the repo's `sl.json`: it serves a zero-byte 200 on
    # every host — the same Oracc failure class docs/02-sources.md records
    # for their metadata.json. `00lib/osl.asl` is the artifact.
    #
    # == License (recorded verbatim)
    #
    # The osl.asl header states: "CC0: osl.asl and its associated files are
    # placed in the public domain under a CC0 licence." → class `open`.
    #
    # == fetch: the sanctioned GitFetch of the whole repo
    #
    # A plain GitFetch clone of github.com/oracc/osl (attic + breaker +
    # ff-merge); the seam reads canonical/osl/00lib/osl.asl. Rolling master,
    # no tags: a re-sync is an owner call. sync_policy manual, wired: false
    # permanently (the module invariant).
    class Osl < Nabu::Adapter
      REPO_URL = "https://github.com/oracc/osl"

      MANIFEST = Nabu::SourceManifest.new(
        id: "osl",
        name: "OSL — the Oracc Sign List (cuneiform sign/value/codepoint instrument)",
        license: "CC0, stated verbatim in the osl.asl header: \"CC0: osl.asl and its associated " \
                 "files are placed in the public domain under a CC0 licence.\" (Veldhuis & " \
                 "Tinney, the Oracc Sign List, ex-OGSL)",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "asl"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents — its data is a read seam
      # (Nabu::SignList), not passages. Empty by design, not by accident
      # (the hypotactic/cldf-spine shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: osl is a sign-list instrument, not a text source — " \
                          "its data rides the Nabu::SignList read seam over 00lib/osl.asl " \
                          "(P53-1); parse is unreachable"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end
    end
  end
end
