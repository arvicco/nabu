# frozen_string_literal: true

require "csv"

require_relative "ccl_tei_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The CCL adapter (P28-3, .docs/surveys/egyptian-survey.md §9): the
    # Comprehensive Coptic Lexicon v1.2 (BBAW Akademienvorhaben "Strukturen
    # und Transformationen des Wortschatzes der ägyptischen Sprache" + FU
    # Berlin DDGLC; Refubium fub188/27813, DOI 10.17169/refubium-27566) —
    # the Coptic dictionary shelf, 11,284 entries whose xml:ids ARE the
    # Coptic Dictionary Online C-ids. content_kind :dictionary, slug ccl,
    # language cop, urns urn:nabu:dict:ccl:<C-id>.
    #
    # == Three canonical artifacts, one source (the crosswalk packaging verdict)
    #
    # Beside the TEI, #fetch pulls ORAEC's coptic_etymologies crosswalk
    # (CC0; 2,177 rows C-id ↔ TLA hieroglyphic lemma id ↔ TLA demotic word
    # id — the CSV has no header; the survey's "2,176" was one short) into
    # crosswalk/. It rides as CONFIG of this adapter, not as its own
    # source: its only content is edges, every one of its C-ids exists in
    # CCL v1.2 (censused 2026-07-18 — an entry-riding design loses
    # nothing), and a source needs a catalog grain the crosswalk does not
    # have. At parse time each matched entry carries its ancestor ids as
    # DictionaryCitations (content-sha'd — a crosswalk change honestly
    # revises the entry), and Nabu::CclEtymologies re-derives them into
    # kind=etymology links-journal edges after every sync (the
    # reference_producer seam; a pure function of the catalog, the
    # CorphDilReferences pattern). A missing crosswalk file parses to
    # citation-less entries (the day-one state); the entries revise when
    # it lands.
    #
    # == The KELLIA etymologies tab (P89-2, №R-52 ruled (a)+(c) 2026-08-30)
    #
    # Third artifact: KELLIA/dictionary's data/egyptian_etymologies.tab,
    # PINNED at release tag v3.0.0 (the lexicon stays on the frozen
    # Refubium deposit — option (a); the tag is only a refresh candidate if
    # upstream ever cuts a corrected *deposit*). The 88-R2 census, re-run
    # verbatim 2026-08-30: 2,311 rows, a STRICT SUPERSET of the ORAEC
    # crosswalk — 2,050/2,177 shared rows identical after id normalization,
    # 127 fill blanks ORAEC left, ZERO conflicts, +134 C-ids ORAEC lacks —
    # and every row carries the Egyptian/Demotic lemma transcription plus
    # an English AND German gloss the ORAEC file never had. Id
    # normalization (the census IS the join spec): egy_num is verbatim the
    # ORAEC hieroglyphic id; demo_num "d<n>" ≡ ORAEC bare <n> and
    # "dm<n>" ≡ ORAEC negative -<n> (the 220 negative demotic word
    # numbers), so the catalog's urn space stays ORAEC-convention and no
    # existing citation urn moves. merge_etymologies composes the two
    # witnesses (ORAEC id kept on any disagreement — censused zero;
    # KELLIA fills blanks and contributes the transcriptions/glosses,
    # which land as a `tla:` body line). Both files stay on disk — two
    # honest witnesses, never a replacement.
    #
    # == License (both layers verbatim; in-file grant governs, the house
    # doctrine)
    #
    # - TEI teiHeader <availability>: "Licence for this TEI document:
    #   Creative Commons, Attribution-ShareAlike 4.0 International (CC
    #   BY-SA 4.0)"; the Refubium record shows "Creative Commons:
    #   Namensnennung, Weitergabe unter gleichen Bedingungen" with
    #   DC.rights = https://creativecommons.org/licenses/by-sa/4.0/.
    # - Crosswalk repo LICENSE: CC0 1.0 Universal; its README verbatim:
    #   "The mapping was created by the ORAEC project and is licensed
    #   under CC 0." CC0 imposes nothing → license_class stays
    #   "attribution" (BY-SA).
    #
    # == fetch / sync policy
    #
    # Two Nabu::FileFetch units (the wiktionary-recon two-phase
    # choreography: all prepare, one combined breaker, all complete) —
    # the Refubium bitstream is a frozen 2020 deposit, the crosswalk repo
    # last moved 2024-08 → sync_policy: manual, enabled: false until the
    # owner-fired first sync. The remote probe HEADs both artifacts
    # (:http_zip); neither host serves a probe-shaped license endpoint, so
    # those rows honestly read unchecked (drift is caught by re-reading
    # record/README at any refetch).
    class Ccl < Nabu::Adapter
      LEXICON_URL = "https://refubium.fu-berlin.de/bitstream/handle/fub188/27813/" \
                    "Comprehensive_Coptic_Lexicon-v1.2-2020.xml?sequence=1&isAllowed=y"
      CROSSWALK_URL = "https://raw.githubusercontent.com/oraec/coptic_etymologies/main/" \
                      "digitizing_coptic_etymologies_coptic_list_entries.csv"

      KELLIA_URL = "https://raw.githubusercontent.com/KELLIA/dictionary/v3.0.0/data/" \
                   "egyptian_etymologies.tab"

      LEXICON_DIRNAME = "lexicon"
      LEXICON_FILENAME = "Comprehensive_Coptic_Lexicon-v1.2-2020.xml"
      CROSSWALK_DIRNAME = "crosswalk"
      CROSSWALK_FILENAME = "digitizing_coptic_etymologies_coptic_list_entries.csv"
      KELLIA_DIRNAME = "kellia"
      KELLIA_FILENAME = "egyptian_etymologies.tab"

      ORAEC_WITNESS = "ORAEC crosswalk"
      KELLIA_WITNESS = "KELLIA etymologies"

      # One C-id's composed etymology (class note): ids in the catalog's
      # ORAEC-convention space with their attesting witnesses, plus the
      # KELLIA-only enrichment (transcriptions + glosses).
      Etymology = Data.define(:hieroglyphic, :demotic, :hieroglyphic_witnesses, :demotic_witnesses,
                              :egy_lemma, :demo_lemma, :gloss_en, :gloss_de) do
        def initialize(hieroglyphic: nil, demotic: nil, hieroglyphic_witnesses: [],
                       demotic_witnesses: [], egy_lemma: nil, demo_lemma: nil,
                       gloss_en: nil, gloss_de: nil)
          super
        end
      end

      DICTIONARY_SLUG = "ccl"
      LANGUAGE = "cop"
      TITLE = "Comprehensive Coptic Lexicon (CCL v1.2)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ccl",
        name: "Comprehensive Coptic Lexicon v1.2 (BBAW/DDGLC) + ORAEC & KELLIA egy↔cop etymologies",
        license: "CC BY-SA 4.0 (verbatim in-file <licence>: \"Licence for this TEI document: Creative " \
                 "Commons, Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)\"; Refubium record " \
                 "fub188/27813 concurs). Crosswalk: CC0 1.0 (ORAEC coptic_etymologies README verbatim: " \
                 "\"The mapping was created by the ORAEC project and is licensed under CC 0.\"). " \
                 "KELLIA etymologies tab: CC BY-SA 4.0 (KELLIA/dictionary README: \"Lexicon data " \
                 "licensed CC BY-SA 4.0\"; fetched pinned at release tag v3.0.0)",
        license_class: "attribution",
        upstream_url: LEXICON_URL,
        parser_family: "ccl-tei"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild load
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The crosswalk edges (class note): refreshed after every load via
      # the shared reference_producer seam (P25-0).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        CclEtymologies.new(catalog: catalog, journal: journal)
      end

      # Both artifacts HEADed for reachability + Last-Modified drift
      # against their subdirs' FileFetch pins; no license metadata_url
      # (class note).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: LEXICON_FILENAME, zip_url: LEXICON_URL, metadata_url: nil,
            state_subdir: LEXICON_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: CROSSWALK_FILENAME, zip_url: CROSSWALK_URL, metadata_url: nil,
            state_subdir: CROSSWALK_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: KELLIA_FILENAME, zip_url: KELLIA_URL, metadata_url: nil,
            state_subdir: KELLIA_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          )
        ]
      end

      # Compose the two etymology witnesses (class note): the frozen ORAEC
      # deposit anchors every id it attests; KELLIA fills blanks and — on a
      # disagreement (censused zero) — is NOT credited for an id it does
      # not actually attest. Enrichment (transcriptions, glosses) is
      # KELLIA-only by construction.
      def self.merge_etymologies(oraec, kellia)
        (oraec.keys | kellia.keys).to_h do |cid|
          o_hiero, o_demo = oraec[cid]
          k = kellia[cid] || {}
          [cid, Etymology.new(
            hieroglyphic: o_hiero || k[:hieroglyphic],
            demotic: o_demo || k[:demotic],
            hieroglyphic_witnesses: witnesses(o_hiero, k[:hieroglyphic]),
            demotic_witnesses: witnesses(o_demo, k[:demotic]),
            egy_lemma: k[:egy_lemma], demo_lemma: k[:demo_lemma],
            gloss_en: k[:gloss_en], gloss_de: k[:gloss_de]
          )]
        end
      end

      def self.witnesses(oraec_id, kellia_id)
        list = []
        list << ORAEC_WITNESS if oraec_id
        list << KELLIA_WITNESS if kellia_id && (oraec_id.nil? || kellia_id == oraec_id)
        list
      end
      private_class_method :witnesses

      # KELLIA demo_num → the catalog's ORAEC-convention id space (class
      # note): d<n> ≡ <n>, dm<n> ≡ -<n>; anything else rides verbatim.
      def self.normalize_demotic(id)
        case id
        when nil then nil
        when /\Adm(\d+)\z/ then "-#{Regexp.last_match(1)}"
        when /\Ad(\d+)\z/ then Regexp.last_match(1)
        else id
        end
      end

      # One DocumentRef for the one TEI (the crosswalk is adapter config,
      # not a document — it surfaces through the entries it annotates). A
      # workdir without the file yields nothing (the day-one pre-fetch
      # state); the same walk works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", LEXICON_FILENAME)).first(1).each do |path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{DICTIONARY_SLUG}:#{LEXICON_FILENAME}",
            path: File.expand_path(path),
            metadata: { "dictionary" => DICTIONARY_SLUG }
          )
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        etymologies = self.class.merge_etymologies(crosswalk_for(document_ref.path),
                                                   kellia_for(document_ref.path))
        CclTeiParser.new.entries(document_ref.path, etymologies: etymologies)
                    .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "ccl: #{document_ref.id}: #{e.message}"
      end

      # Both artifacts two-phase (the wiktionary-recon choreography): all
      # prepare with the live tree untouched, the breaker sees the combined
      # doomed set, then all complete. Report: the lexicon sha (the
      # single-pin convention), both shas in notes.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.fetch(:lexicon).sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ccl fetch failed into #{workdir}: #{e.message}"
      end

      private

      # The crosswalk beside the lexicon: <workdir>/crosswalk/… relative to
      # <workdir>/lexicon/<xml> — the same relative shape under the attic.
      # Absent file → empty map (class note). Rows are id,hieroglyphic,
      # demotic with NO header (censused); malformed lines would surface as
      # CSV errors and quarantine the one dictionary file, honestly.
      def crosswalk_for(lexicon_path)
        path = File.join(File.dirname(lexicon_path, 2), CROSSWALK_DIRNAME, CROSSWALK_FILENAME)
        return {} unless File.file?(path)

        CSV.read(path).to_h { |row| [row[0], [presence(row[1]), presence(row[2])]] }
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "ccl: malformed crosswalk #{path}: #{e.message}"
      end

      # The KELLIA tab beside the lexicon (same relative shape as the
      # crosswalk; absent file → empty map, the pre-first-refetch state).
      # Plain tab-split, not CSV: the tab is quote-free TSV and glosses may
      # carry characters a CSV quote pass would misread. "NA" is upstream's
      # explicit absent marker.
      def kellia_for(lexicon_path)
        path = File.join(File.dirname(lexicon_path, 2), KELLIA_DIRNAME, KELLIA_FILENAME)
        return {} unless File.file?(path)

        header = nil
        rows = {}
        File.foreach(path, chomp: true) do |line|
          cells = line.split("\t", -1)
          (header = cells) && next if header.nil?

          row = header.zip(cells).to_h
          rows[row["tla"]] = {
            hieroglyphic: na(row["egy_num"]),
            demotic: self.class.normalize_demotic(na(row["demo_num"])),
            egy_lemma: na(row["egy_lemma"]), demo_lemma: na(row["demo_lemma"]),
            gloss_en: na(row["english"]), gloss_de: na(row["german"])
          }
        end
        rows
      end

      def na(value) = value == "NA" ? nil : presence(value)

      def presence(value) = value.nil? || value.empty? ? nil : value

      def file_fetches(workdir, progress)
        {
          lexicon: file_fetch(workdir, LEXICON_URL, LEXICON_DIRNAME, LEXICON_FILENAME, progress),
          crosswalk: file_fetch(workdir, CROSSWALK_URL, CROSSWALK_DIRNAME, CROSSWALK_FILENAME, progress),
          kellia: file_fetch(workdir, KELLIA_URL, KELLIA_DIRNAME, KELLIA_FILENAME, progress)
        }
      end

      def file_fetch(workdir, url, subdir, filename, progress)
        Nabu::FileFetch.new(
          url: url, dir: File.join(workdir, subdir), filename: filename,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
        )
      end

      def fetch_notes(fetches)
        shas = fetches.map { |name, fetch| "#{name} #{fetch.sha[0, 8]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
