# frozen_string_literal: true

require_relative "esukhia_text"

module Nabu
  module Adapters
    # The Digital Derge Tengyur (P48-1): Esukhia/Barom Theksum Choling's
    # annotated faithful copy of the Derge Tengyur edition — 213 volume
    # files, ~617 MB UTF-8 plain text, Toh 1109–4569 (disjoint from the
    # Kangyur's 1–1108 by Tohoku-catalog design; the crosswalk key stays
    # unambiguous). Second registrant of the `esukhia-text` family — the
    # Tengyur rides the Kangyur's parser unchanged.
    #
    # The repo is NOT archived but dormant (last push 2021-10-20); the sync
    # is PINNED to that HEAD and aborts loudly on drift (owner re-pin).
    # Known upstream quirks the family handles: UTF-8 BOM on every volume
    # file (the README claims none), `#` peydurma note anchors, `[X]` error
    # candidates, and volume 213 (dkar chag) carrying no markers at all —
    # its text rides the last open document, like any unmarked volume
    # continuation.
    #
    # LICENSE (recorded honestly): README §License VERBATIM — "This work is
    # a mechanical reproduction of a Public domain work, and as such is
    # also in the Public domain." README-only declaration, no LICENSE
    # file. → class `open`.
    class DergeTengyur < EsukhiaText
      REPO_URL = "https://github.com/Esukhia/derge-tengyur"

      # master HEAD, 2021-10-20 — the dormant upstream's last state.
      PINNED_SHA = "174653137d62af481f53c6ae3dc842bf8629323e"

      MANIFEST = Nabu::SourceManifest.new(
        id: "derge-tengyur",
        name: "Digital Derge Tengyur (Esukhia/Barom Theksum Choling faithful copy of the Derge edition)",
        license: "Public Domain — README §License verbatim: \"This work is a mechanical reproduction " \
                 "of a Public domain work, and as such is also in the Public domain.\" README-only " \
                 "declaration, no LICENSE file (recorded honestly). Cite: ཚུལ་ཁྲིམས་རིན་ཆེན། [1697–1774], " \
                 "བསྟན་འགྱུར་སྡེ་དགེ་པར་མ།, etexts combined and proofread by Esukhia on behalf of Barom " \
                 "Theksum Choling, 2014–2019, github.com/Esukhia/derge-tengyur.",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "esukhia-text"
      )

      def self.manifest
        MANIFEST
      end
    end
  end
end
