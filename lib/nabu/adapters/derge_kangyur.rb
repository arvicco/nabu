# frozen_string_literal: true

require_relative "esukhia_text"

module Nabu
  module Adapters
    # The Digital Derge Kangyur (P48-1): Esukhia/Barom Theksum Choling's
    # 2014–2018 proofreading of the UVA-SOAS 2013 eKangyur — an exact
    # representation of the Derge woodblocks held by the Library of
    # Congress (mistakes preserved; that is the point). 103 volume files,
    # ~300 MB UTF-8 plain text, Toh 1–1108. First registrant of the
    # `esukhia-text` family and of the `tibetan` axis.
    #
    # The repo is ARCHIVED (June 2022, moved to OpenPecha/P000001 — which
    # this source deliberately does NOT follow: OpenPecha-Data is a
    # per-pecha licensing minefield, P47-s2, while this frozen repo carries
    # the clean PD declaration). The sync is PINNED to the archival HEAD;
    # drift is impossible upstream and aborts loudly here.
    #
    # LICENSE (recorded honestly): README §License VERBATIM — "This work is
    # a mechanical reproduction of a Public Domain work, and as such is
    # also in the Public Domain." A README-only declaration: there is NO
    # LICENSE file. → class `open`.
    #
    # All parsing/identity doctrine lives on EsukhiaText (the family base).
    class DergeKangyur < EsukhiaText
      REPO_URL = "https://github.com/Esukhia/derge-kangyur"

      # The archival master HEAD (2022-06-24) — the frozen state of record.
      PINNED_SHA = "a582cf471b7c85a101035071078032f106a8e536"

      MANIFEST = Nabu::SourceManifest.new(
        id: "derge-kangyur",
        name: "Digital Derge Kangyur (Esukhia/Barom proofreading of the UVA-SOAS 2013 eKangyur)",
        license: "Public Domain — README §License verbatim: \"This work is a mechanical reproduction " \
                 "of a Public Domain work, and as such is also in the Public Domain.\" README-only " \
                 "declaration, no LICENSE file (recorded honestly). Cite: ཆོས་ཀྱི་འབྱུང་གནས། [1721–31], " \
                 "བཀའ་འགྱུར་སྡེ་དགེ་པར་མ།, etexts combined and proofread by Esukhia on behalf of Barom " \
                 "Theksum Choling, 2012–2018, github.com/Esukhia/derge-kangyur.",
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
