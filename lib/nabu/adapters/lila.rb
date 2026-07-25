# frozen_string_literal: true

module Nabu
  module Adapters
    # LiLa Lemma Bank — CIRCSE's knowledge base of Latin canonical forms
    # (215,102 lemmas), registered as a FEATURE MODULE (kind: module), not a
    # text source. It mints NO catalog rows and needs NO migration: it is a
    # pure READ seam (Nabu::Lila) — the Latin lemma spine, joining lemma lanes
    # the way the CJK character-desk crosswalks join Han glyphs. `nabu sync
    # lila` (owner-run) lands the Turtle dump under canonical/lila/, and
    # Nabu::Lila resolves a Latin lemma → its LiLa record {IRI, canonical
    # form, POS, variant forms}. So, like bridging/pleiades, discover yields
    # NOTHING and parse is unreachable. First consumer: the `nabu define`
    # variant-form fallback (Nabu::Query::Define).
    #
    # == fetch: the git-pinned sparse clone (the bridging posture)
    #
    # The distribution supports BOTH a Zenodo archival record (citable DOI
    # 10.5281/zenodo.4017229) AND the maintained GitHub repo — and the data
    # lives in the repo as a single 84 MB rdf/lemmaBank.ttl (the CIRCSE LASLA
    # linking triples point at it). We fetch via the sanctioned GitFetch
    # gateway (attic + breaker + ff-merge), version-pinned by commit sha, with
    # a SPARSE cone of exactly the Turtle dump + the grants — the ETCBC
    # bridging shape (a big data file + LICENSE + README, nothing else). The
    # 11 MB lila_db.sql.gz (the relational mirror) and the D2RQ mapping ttls
    # never materialize: the resolver reads the RDF, not the SQL.
    #
    # For a fully reproducible snapshot the owner may pin `ref:` to a specific
    # commit at first sync (a one-line call-site addition); the Zenodo DOI is
    # the citable anchor recorded in docs/02-sources.md.
    #
    # == License (verbatim, in-repo LICENSE, read 2026-07-24)
    #
    # "Attribution-ShareAlike 4.0 International" (the CC BY-SA 4.0 legalcode;
    # README "## Copyright" links creativecommons.org/licenses/by-sa/4.0/) →
    # class attribution (the house BY-SA posture: every CC BY-SA source classes
    # attribution; share-alike is a downstream-relicensing duty, not a serving
    # gate). Matches the LICENSE-authoritative doctrine and the CC BY-SA the
    # LiLa papers claim.
    class Lila < Nabu::Adapter
      REPO_URL = "https://github.com/CIRCSE/LiLa_Lemma-Bank"

      # The sparse cone IS the point: the RDF dump + the grants. The SQL
      # mirror and the D2RQ mapping files never land (the resolver is RDF-only).
      SPARSE_PATHS = ["rdf/lemmaBank.ttl", "README.md", "LICENSE"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "lila",
        name: "LiLa Lemma Bank — Latin canonical forms (lemma-spine instrument)",
        license: "CC BY-SA 4.0 (in-repo LICENSE verbatim: \"Attribution-ShareAlike 4.0 " \
                 "International\"; README links creativecommons.org/licenses/by-sa/4.0/) — " \
                 "the house BY-SA class",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "lila-turtle"
      )

      def self.manifest
        MANIFEST
      end

      # A feature module mints no documents — its data is a read seam
      # (Nabu::Lila), not passages. Empty by design (the bridging shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: lila is a lemma-spine instrument, not a text source — " \
                          "its Lemma Bank rides Nabu::Lila (P44-8); parse is unreachable"
      end

      # Sparse-clone the Turtle dump + grants via the sanctioned GitFetch
      # gateway (attic + breaker + ff-merge), commit-pinned. No network in
      # tests.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        REPO_URL
      end
    end
  end
end
