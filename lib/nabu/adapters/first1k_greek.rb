# frozen_string_literal: true

require_relative "perseus"

module Nabu
  module Adapters
    # The First1KGreek adapter (architecture §3, packet P3-2): OpenGreekAndLatin's
    # First1KGreek corpus ships the *identical* CapiTainS/EpiDoc repo layout as
    # PerseusDL — data/<tg>/<work>/<tg>.<work>.<edition>.xml, dual __cts__.xml,
    # CTS refsDecl editions — so this is a thin SUBCLASS of Perseus rather than a
    # copy. It inherits discover/parse/fetch and the __cts__.xml title/urn
    # resolution wholesale, overriding exactly two things:
    #
    #   1. The manifest — a different source (id, name, upstream_url, license).
    #   2. The original-language edition-slug rule (#edition_slug_pattern).
    #
    # == Why subclass, not share a module
    #
    # Perseus already generalized the original-language selection into a single
    # data-driven method (#edition_slug_pattern) and made its class/instance
    # manifest methods overridable — it was written to be extended (its own
    # latinLit sibling is a one-line subclass). First1KGreek is greekLit only
    # (NAMESPACE stays "greekLit", so urns and the "grc" language tag come for
    # free), differing solely in slug family and identity. Subclassing captures
    # exactly that delta; a shared module would have to re-thread the namespace
    # plumbing Perseus already owns.
    #
    # == The edition-slug difference (the whole reason this class exists)
    #
    # Perseus editions are uniformly perseus-grcN. First1KGreek's are NOT: the
    # same corpus mixes 1st1K-grcN (dominant), opp-grcN, even perseus-grcN, and
    # letter-suffixed versions (1st1K-grc1a). So the acceptance rule ignores the
    # slug family entirely and matches ANY `…-grc<version>` tail; translations
    # (…-eng*, …-ger*, …-lat*, …-mul*, …-cop*) lack "-grc" and are skipped.
    # Highest-version-per-work selection is inherited unchanged — Perseus's
    # #version_key already orders numeric-then-letter (grc2 < grc2a).
    class First1kGreek < Perseus
      # First1KGreek is Greek only; the CTS namespace never shifts.
      NAMESPACE = "greekLit"

      # CC BY-SA 4.0 (repo-level) → license_class "attribution".
      MANIFEST = Nabu::SourceManifest.new(
        id: "first1k-greek",
        name: "Open Greek and Latin — First1KGreek",
        license: "CC BY-SA 4.0",
        license_class: "attribution",
        upstream_url: "https://github.com/OpenGreekAndLatin/First1KGreek",
        parser_family: "epidoc"
      )

      def self.manifest
        MANIFEST
      end

      def manifest
        MANIFEST
      end

      private

      # Accept any original-language Greek edition regardless of slug family:
      # 1st1K-grc1, opp-grc2, perseus-grc19, plus letter-suffixed versions
      # (1st1K-grc1a). Only the `-grc<version>` tail matters; the leading family
      # segment is free. The :version capture feeds the inherited
      # highest-version selection (Perseus#version_key).
      def edition_slug_pattern
        /-grc(?<version>\d+[a-z]?)\z/
      end
    end
  end
end
