# frozen_string_literal: true

require_relative "vienna_wiki"

module Nabu
  module Adapters
    # The LexLep inscription adapter (P29-3): Lexicon Leponticum
    # (lexlep.univie.ac.at, ed. Stifter/Salomon/Braun et al.) — "a digital
    # edition and etymological dictionary of Cisalpine Celtic": the
    # inscriptions of Lepontic and Cisalpine Gaulish, northern Italy /
    # southern Switzerland, 1st millennium BC. Census via api.php
    # categoryinfo 2026-07-18: Inscription 494 (+ subcat Coin) · Object 419
    # · Site 134 — NB the packet brief's advertised counts were
    # label-shuffled (628 is the WORD category; the words ride the sibling
    # `lexlep-words` dictionary source).
    #
    # == License — the CONFLICT, all three layers verbatim (class nc,
    # relabel-on-reply; the ogham precedent, licensing email №17 queued)
    #
    # - Project:Terms of use (api.php, 2026-07-18): "Lexicon Leponticum
    #   (LexLep) is an interactive online dictionary and lexicon created
    #   and licenced for '''scientific use only'''. In line with
    #   Wikimedia's terms of use the content of this site is is available
    #   under conditions specified by the following licences: (1) the
    #   Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA
    #   3.0) license (2) the GNU Free Documentation License." [sic — the
    #   doubled "is is" and "licenced" are upstream's]
    # - The wiki's own rightsinfo (api.php meta=siteinfo, the footer
    #   grant): url https://creativecommons.org/licenses/by-nc-sa/4.0/,
    #   text "Creative Commons Attribution-NonCommercial-ShareAlike".
    # The BY-SA 3.0 grant and the BY-NC-SA 4.0 footer CONTRADICT, and the
    # preamble scopes to "scientific use only" → the restrictive reading
    # is held: class nc (MCP default-excluded, never redistributed) until
    # upstream answers; on reply, relabel via license_class (the P10-4
    # override mechanics — no urns change).
    #
    # Language per inscription (censused over 100 pages): the corpus lane
    # is "Cisalpine Celtic"; the per-page language param is mostly the
    # cover term "Celtic" (→ the ISO 639-5 collective `cel`, the iecor
    # `ine` precedent) or "unknown" (→ und, short/damaged texts), with
    # Lepontic/Cisalpine Gaulish appearing on Word pages and occasional
    # Latin/Etruscan carriers here.
    class Lexlep < ViennaWiki
      API_URL = "https://lexlep.univie.ac.at/api.php"
      URN_PREFIX = "urn:nabu:lexlep:"

      LANGUAGE_MAP = {
        "Lepontic" => "lep",
        "Cisalpine Gaulish" => "xcg",
        "Transalpine Gaulish" => "xtg",
        "Celtic" => "cel",
        "Latin" => "lat",
        "Etruscan" => "ett"
      }.freeze

      # The print-corpus concordances (Morandi 2004 "Celti d'Italia",
      # Solinas 1995) → related keys, the riig rig: pattern.
      CONCORDANCES = { "morandi" => "morandi", "solinas" => "solinas" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "lexlep",
        name: "Lexicon Leponticum (LexLep) — Cisalpine Celtic inscriptions (Univ. Vienna)",
        license: "UNRESOLVED CONFLICT, restrictive reading held (licensing email №17 queued): " \
                 "Project:Terms of use verbatim \"created and licenced for scientific use only. In line " \
                 "with Wikimedia's terms of use the content of this site is is available under conditions " \
                 "specified by the following licences: (1) the Creative Commons Attribution-ShareAlike 3.0 " \
                 "Unported (CC BY-SA 3.0) license (2) the GNU Free Documentation License.\" vs the wiki's " \
                 "own rightsinfo/footer \"Creative Commons Attribution-NonCommercial-ShareAlike\" " \
                 "(…/by-nc-sa/4.0/) — class nc until upstream answers, relabel-on-reply",
        license_class: "nc",
        upstream_url: "https://lexlep.univie.ac.at",
        parser_family: "wiki-template"
      )

      def self.manifest
        MANIFEST
      end
    end
  end
end
