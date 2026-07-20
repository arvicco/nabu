# frozen_string_literal: true

require_relative "vienna_wiki"

module Nabu
  module Adapters
    # The TIR adapter (P29-3): Thesaurus Inscriptionum Raeticarum
    # (tir.univie.ac.at, ed. Schumacher/Salomon/Kluge/Bajc/Braun) — "the
    # only complete edition of the documents of Raetic, a Tyrsenian
    # language attested in Iron Age northern Italy and western Austria"
    # (the wiki's own Main Page). The `xrr` corpus of record, actively
    # edited. Census via api.php categoryinfo 2026-07-18: Inscription 389
    # · Object 294 · Site 82 · Word 155 — NB the packet brief's advertised
    # counts were label-shuffled (155 is the WORD category; the TIR word
    # pages are journaled v2, a `tir-words` sibling of lexlep-words).
    #
    # == License (both layers verbatim; class nc, relabel-on-reply — the
    # ogham precedent, licensing email №17 queued)
    #
    # - Project:Terms of Use (api.php, 2026-07-18): "Thesaurus
    #   Inscriptionum Raeticarum (TIR) is an interactive online lexicon
    #   created and licensed for scientific use only. In line with
    #   Wikimedia's terms of use the content of this site is available
    #   under conditions specified by the following licences: (1) the
    #   Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA
    #   3.0) license (2) the GNU Free Documentation License."
    # - The wiki's rightsinfo (api.php meta=siteinfo) is EMPTY — no footer
    #   grant at all.
    # "Scientific use only" scopes the BY-SA grant → restrictive reading
    # held: class nc until upstream answers; relabel via license_class on
    # reply (P10-4 override mechanics).
    #
    # Language per inscription (censused over 100 pages): "Raetic" → xrr
    # where the editors commit, "unknown" → und for the many short or
    # damaged rock inscriptions. Trismegistos sigla (sigla_tm) ride as
    # tm: reference edges; the print sigla (PID/IR/MLR/Mancini) stay
    # journaled for v2. Coordinates honesty: some objects deliberately
    # carry none ("by request of the Department for Prehistory in
    # Innsbruck to prevent damage" — AK-1 rock); absence is preserved.
    class Tir < ViennaWiki
      API_URL = "https://tir.univie.ac.at/api.php"
      URN_PREFIX = "urn:nabu:tir:"

      LANGUAGE_MAP = {
        "Raetic" => "xrr",
        "Etruscan" => "ett",
        "Latin" => "lat",
        "Celtic" => "cel"
      }.freeze

      # Trismegistos ids → tm: reference edges (the clean external id
      # space; trismegistos.org/text/<id>).
      CONCORDANCES = { "sigla_tm" => "tm" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "tir",
        name: "Thesaurus Inscriptionum Raeticarum (TIR) — Raetic corpus of record (Univ. Vienna)",
        license: "MAINTAINER-RESOLVED CC BY-NC-SA 4.0 (№17 reply, C. Salomon, 2026-07-20, verbatim: " \
                 "\"the information provided is indeed contradictory and outdated … I will … go with " \
                 "CC BY-NC-SA 4.0. I would therefore ask you to also use NC for the LexLep and TIR data " \
                 "in your library.\") — the conservative nc hold CONFIRMED, no reclass. Historical " \
                 "conflict kept for the record: " \
                 "Project:Terms of Use verbatim \"Thesaurus Inscriptionum Raeticarum (TIR) is an " \
                 "interactive online lexicon created and licensed for scientific use only. In line with " \
                 "Wikimedia's terms of use the content of this site is available under conditions " \
                 "specified by the following licences: (1) the Creative Commons Attribution-ShareAlike " \
                 "3.0 Unported (CC BY-SA 3.0) license (2) the GNU Free Documentation License.\"; the " \
                 "wiki's rightsinfo footer grant is empty — class nc until upstream answers, " \
                 "relabel-on-reply",
        license_class: "nc",
        upstream_url: "https://tir.univie.ac.at",
        parser_family: "wiki-template"
      )

      def self.manifest
        MANIFEST
      end
    end
  end
end
