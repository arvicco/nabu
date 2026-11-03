# frozen_string_literal: true

require_relative "tcp_collection"

module Nabu
  module Adapters
    # Evans-TCP — the Text Creation Partnership's keyed edition of Early
    # American Imprints, Series I (Evans, 1639–1800): what was printed in
    # the American colonies and the early republic — sermons, broadside
    # verse and proclamations, almanac-era pamphlets, captivity narratives,
    # Revolutionary political argument. The TcpCollection shape (class
    # note there) over the TCP's own Evans Box folder.
    #
    # == Census (2026-11-03, the live Box listing + zip central directories)
    #
    #   P4_XML_TCP/ N0.zip 2,239 · N1.zip 1,126 · N2.zip 1,299 · N3.zip 200
    #               = 4,864 released texts
    #               unedited.zip 148 texts (0 overlap with the released)
    #   evans_pub_dates.txt  4,977 ids = the 4,864 released + 113 of the
    #               unedited; the other 35 unedited are exactly the ids of
    #               evnsdat_unfinished.sgm (the TCP's "partly done" list)
    #
    # Every member parsed: 5,012 docs / 1,724,124 passages (released
    # 4,864 / 1,694,119; unedited 148 / 30,005), 0 errors, IDG = filename
    # stem on all 5,012.
    #
    # Accepted 5,012 documents (both classes) + 0 skipped by rule on the
    # fetched tree reconcile to upstream's zips exactly; the 4,977-id list
    # is upstream's count of what it keyed AND encoded, the residue (35)
    # its own unfinished list.
    #
    # == Header facts mined
    #
    # The "stc" IDNOs are the bibliography references ("Evans 680",
    # "Shipton 41129" — the Evans / Shipton-Mooney numbers, every value in
    # order) → metadata "bibliography_refs". The evans_pub_dates.txt
    # PUBDATE is the TCP's own release year (2004–2009), machinery — never
    # a date of the text, so it is landed beside texts/ as the id roster
    # only.
    #
    # == License
    #
    # Every file's AVAILABILITY reads the CC0 1.0 waiver (censused ×5,012);
    # the license_mapper maps it open per document and a stranger statement
    # restricted, never silently open.
    class EvansTcp < TcpCollection
      # The Evans Box share (the TCP-readme's own Box mirror link).
      class Fetch < TcpBoxFetch
        COLLECTION = TcpBoxFetch::Collection.new(
          slug: "evans-tcp", label: "Evans-TCP", shared_name: "zj7pzfokxde4glrhebxsavbbxzyr3ogz",
          zips_folder: "P4_XML_TCP", root_sidecars: %w[eebo2prf.xml.dtd evans_pub_dates.txt].freeze
        )

        def self.collection = COLLECTION
      end

      IDNO_LISTS = { "stc" => "bibliography_refs" }.freeze

      # The one non-eng LANGUSAGE of 5,012 files (census 2026-11-03): N14218,
      # Henry Mackenzie's novel The man of the world, declares "pau"
      # (Palauan) — a cataloguing slip; every TEXT and its title page are
      # English. The LANGUSAGE stays verbatim in metadata.
      LANGUAGE_ERRATA = { "N14218" => "en" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "evans-tcp",
        name: "Evans-TCP — Early American Imprints, Text Creation Partnership",
        license: "OPEN — uniform CC0 1.0 Public Domain Dedication, per-file AVAILABILITY verbatim " \
                 "(censused 2026-11-03 on all 5,012 files): \"To the extent possible " \
                 "under law, the Text Creation Partnership has waived all copyright and related or " \
                 "neighboring rights to this keyboarded and encoded edition of the work described " \
                 "above, according to the terms of the CC0 1.0 Public Domain Dedication\". The waiver " \
                 "covers the transcriptions only, not the page images (not fetched). The 2026-08-20 " \
                 "grant (P.F. Schaffner, TCP text manager) additionally covers the TCP files.",
        license_class: "open",
        upstream_url: Fetch.shared_url,
        parser_family: "tcp-xml",
        credit: "Text Creation Partnership — Evans-TCP: Early American Imprints, Series I (Evans), " \
                "textcreationpartnership.org"
      )

      def self.manifest
        MANIFEST
      end
    end
  end
end
