# frozen_string_literal: true

require_relative "tcp_collection"

module Nabu
  module Adapters
    # ECCO-TCP — the Text Creation Partnership's keyed selection from
    # Eighteenth Century Collections Online: English books of 1700–1800
    # (Gray, Pope, Defoe, Smollett, Burney, the ballad and song-sheet
    # trade, sermons, law, medicine). The TcpCollection shape (class note
    # there) over the TCP's own ECCO Box folder.
    #
    # == Census (2026-11-03, the live Box listing + every member parsed)
    #
    #   p4/ ecco_p4_released.zip  2,473 texts · 2,000,264 passages
    #       ecco_p4_unedited.zip    628 texts ·   697,450 passages
    #   0 id overlap; 0 parse errors; IDG = filename stem on all 3,101
    #
    # Accepted 3,101 documents (both classes) + 0 skipped by rule on the
    # fetched tree = upstream's two zips exactly (the TCP's "2,473
    # released" is the released zip's member count).
    #
    # == Header facts mined
    #
    # Each ECCO header carries the Gale subject module of the source book
    # (<IDNO TYPE="ContentSet">: ECLL Literature and Language, ECMS
    # Medicine, Science and Technology, ECSS Social Sciences, ECHG History
    # and Geography, ECRP Religion and Philosophy, ECFA Fine Arts, ECGR
    # General Reference, ECLW Law) → metadata "content_set", folded onto
    # the kind axis (config/kind_map.yml); and its ESTC number → "estc".
    # ECCO carries almost no LCSH headings (29 of 3,101 files).
    #
    # == License
    #
    # Every file's AVAILABILITY reads the CC0 1.0 waiver (censused ×3,101);
    # the license_mapper maps it open per document and a stranger statement
    # restricted, never silently open.
    class EccoTcp < TcpCollection
      # The ECCO Box share (the TCP-readme's own Box mirror link).
      class Fetch < TcpBoxFetch
        COLLECTION = TcpBoxFetch::Collection.new(
          slug: "ecco-tcp", label: "ECCO-TCP", shared_name: "6jbuf443i145f97c4t56z3garu3u2j09",
          zips_folder: "p4", root_sidecars: %w[eebo2prf.xml.dtd].freeze
        )

        def self.collection = COLLECTION
      end

      IDNO_SINGLES = { "ContentSet" => "content_set", "ESTC" => "estc" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ecco-tcp",
        name: "ECCO-TCP — Eighteenth Century Collections Online, Text Creation Partnership",
        license: "OPEN — uniform CC0 1.0 Public Domain Dedication, per-file AVAILABILITY verbatim " \
                 "(censused 2026-11-03 on all 3,101 files): \"To the extent possible under law, the " \
                 "Text Creation Partnership has waived all copyright and related or neighboring " \
                 "rights to this keyboarded and encoded edition of the work described above, " \
                 "according to the terms of the CC0 1.0 Public Domain Dedication\". The waiver does " \
                 "not extend to the page images (not fetched). The 2026-08-20 grant (P.F. Schaffner, " \
                 "TCP text manager) additionally covers the TCP files.",
        license_class: "open",
        upstream_url: Fetch.shared_url,
        parser_family: "tcp-xml",
        credit: "Text Creation Partnership — ECCO-TCP: Eighteenth Century Collections Online, " \
                "textcreationpartnership.org"
      )

      def self.manifest
        MANIFEST
      end
    end
  end
end
