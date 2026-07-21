# frozen_string_literal: true

module Nabu
  module Adapters
    # KR-Gaiji (P37-3) — the Kanseki Repository's list of NOT-YET-ENCODED
    # characters, registered as a FEATURE MODULE row (the P34-1 bridging
    # precedent), not a text source. The repo is one org sibling of the ~9,355
    # kanripo text repos: `charlist.org.txt` (5,254 `&KR\d+;` gaiji references,
    # one per line — id, occurrence count, Unicode-or-IDS representation,
    # normalized substitute, image link) plus a 5,232-PNG `images/` tree.
    #
    # == Why a module row, not a text source
    #
    # It mints NO documents — it is a reference asset the DISPLAY layer reads,
    # not a corpus. Its faithful subset is curated into config/gaiji/kanripo.tsv
    # (the 972 refs whose representation is a single real codepoint — 36.4% of
    # all gaiji OCCURRENCES; census in that file's header + the P37-3 worklog),
    # and the `reading` mode resolves those refs to real glyphs while every
    # other ref renders the ⬚ placeholder box. So discover yields NOTHING,
    # parse is unreachable, and `enabled: false` stands PERMANENTLY. The row
    # exists only to give the owner the sanctioned GitFetch path — one run of
    # `nabu sync kr-gaiji` lands canonical/kr-gaiji so the curated map can be
    # regenerated when upstream advances (the map is refreshed by hand from the
    # fetched charlist, deliberately not auto-derived — it is a censused
    # resource like MARK_CLASSES / EAST_ASIAN_WIDE, not db/ output).
    #
    # == Fetch shape (the sparse cone IS the point)
    #
    # The mapping is one 241 KB file; the 5,232 PNG glyph images are ~5 MB of
    # raster the resolution never needs. The sparse cone takes only
    # charlist.org.txt + README.md, so a sync is a few hundred KB, not the
    # whole image tree.
    #
    # == License (verbatim, the org-level grant)
    #
    # KR-Gaiji carries no per-repo LICENSE file; it rides the kanripo org grant
    # verbatim: "Comprehensive collection of premodern Chinese texts. Licensed
    # as CC BY SA 4.0." (github.com/kanripo) — the same grant the kanripo text
    # adapter records, corroborated by ytenx's DATA_LICENSE.md → class
    # attribution. The resolved glyphs surface only on kanripo (lzh) passages,
    # whose own attribution class already governs serving.
    class KrGaiji < Nabu::Adapter
      REPO_URL = "https://github.com/kanripo/KR-Gaiji"

      # charlist.org.txt is the whole mapping; README.md carries the format
      # doc + the org grant. The 5,232-PNG images/ tree never materializes.
      SPARSE_PATHS = ["charlist.org.txt", "README.md"].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "kr-gaiji",
        name: "KR-Gaiji — Kanseki Repository not-yet-encoded characters (gaiji resolution map)",
        license: "Org-level grant verbatim: \"Comprehensive collection of premodern Chinese texts. " \
                 "Licensed as CC BY SA 4.0.\" (github.com/kanripo; no per-repo LICENSE file; the same " \
                 "grant the kanripo text shelf records, ytenx DATA_LICENSE.md corroborating). Resolved " \
                 "glyphs surface only on kanripo lzh passages, whose attribution class governs serving.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "gaiji-charlist"
      )

      def self.manifest
        MANIFEST
      end

      def self.upstream_repo_urls
        [REPO_URL]
      end

      # A feature module mints no documents — the charlist is a display-time
      # resolution asset, not a corpus. Empty by design, not by accident.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: kr-gaiji is a feature module, not a text source — " \
                          "its charlist feeds the reading-mode gaiji map (P37-3); parse is unreachable"
      end

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
