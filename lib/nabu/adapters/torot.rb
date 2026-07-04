# frozen_string_literal: true

require_relative "proiel"

module Nabu
  module Adapters
    # The TOROT adapter (architecture §3, packet P3-5): the Tromsø Old Russian and
    # OCS Treebank ships the *identical* PROIEL 2.1 XML — one flat directory of
    # per-source *.xml files at the repo root, each a <proiel> → <annotation> +
    # <source> → <div> → <sentence> → <token> tree — so this is the thinnest
    # subclass of the phase (the First1KGreek<Perseus pattern, but for PROIEL). It
    # inherits discover, the <source>-header peek, parse (delegating to
    # ProielParser), and the single-repo git fetch WHOLESALE, overriding exactly
    # one thing: the manifest.
    #
    # == Shared urn:nabu:proiel: namespace (a deliberate decision)
    #
    # TOROT documents mint under the inherited urn:nabu:proiel:<source-id>
    # namespace rather than a urn:nabu:torot: of their own. TOROT is a sibling
    # corpus in the same treebank family: its source ids (peter, zogr, …) come
    # from the shared PROIEL id-space and the on-disk format is byte-identical, so
    # a per-source urn keyed on that id is the natural identity. urn:nabu:torot:
    # was considered and rejected — it would split one id-space across two
    # namespaces for no gain. Cross-adapter urn collision with the PROIEL adapter
    # is acceptable-impossible: upstream id-spaces are disjoint by project
    # convention, and cross-source uniqueness is preserved by distinct source ids.
    # If that convention ever broke, the loader's source-scoped upsert (P1-4)
    # contains the blast radius (documents are keyed by (source_id, urn), and
    # peter's source_id is "torot", not "proiel").
    #
    # == License
    #
    # CC BY-NC-SA 3.0 (US) — both per-source <source>/<license> headers (peter,
    # zogr) agree, matching the repo's NonCommercial-ShareAlike README; there is
    # no LICENSE file in the repo. license_class "nc" so query/export filters
    # never over-share.
    #
    # == fetch / sync policy
    #
    # Single upstream repo, so the inherited clone/ff-only-pull fetch applies
    # verbatim. Registered sync_policy: manual (config/sources.yml) — unlike the
    # frozen proiel-treebank, TOROT still gets occasional releases, so it is
    # re-syncable but not on a live schedule.
    class Torot < Proiel
      # CC BY-NC-SA 3.0 (US) → license_class "nc".
      MANIFEST = Nabu::SourceManifest.new(
        id: "torot",
        name: "TOROT — Tromsø Old Russian and OCS Treebank",
        license: "CC BY-NC-SA 3.0 (per-source headers; repo README, no LICENSE file)",
        license_class: "nc",
        upstream_url: "https://github.com/torottreebank/treebank-releases",
        parser_family: "proiel"
      )

      def self.manifest
        MANIFEST
      end
    end
  end
end
