# frozen_string_literal: true

require_relative "med_headwords_parser"

module Nabu
  module Adapters
    # The Middle English Dictionary headword shelf: the MED editors' own
    # list of every entry's headword spellings, variant spellings ("Also
    # …"), part of speech and MED entry id — the form section of all
    # 57,094 entries of the Middle English Dictionary (University of
    # Michigan; Kurath, Kuhn, Lewis et al., 1952–2001, maintained and
    # revised online by its editors since), excerpted from the dictionary's
    # working XML. It puts every
    # Middle English spelling the MED records behind one entry id, so a
    # form met in the held Middle English texts (cme, pcmep, the Penn
    # corpora) finds its MED entry and the entry's online address. Language
    # enm, bare.
    #
    # == Upstream / grains (verified 2026-11-26)
    #
    # medictionary.info ("A Middle English Dictionary Companion", maintained
    # by the MED editors) /pages/headwords.html lists the entry-list
    # vintages. ACCEPTED: the "Most recent version (October 2023)" —
    # headwords_202310.xml, "Headwords, variant spellings, and IDs" (one
    # XML file, 19,396,721 bytes, Last-Modified 2026-02-23, its own DTD and
    # CSS referenced by URL and never fetched). The page's older vintages
    # (headwords_202210.xml; headwords_forms_and_IDs.202112.xml;
    # MED_heads_and_ids_202108.html; heads_with_diacritics.ncr.html, 2020;
    # MED_lemmata_with_ids.update201712.xml; the 2007
    # MED_lemmata_with_ids.xml / MED_all-forms_with_ids.xml) are superseded
    # snapshots of the same list, never fetched; one that lands in the
    # workdir anyway is skipped by rule (#discovery_skips). The editors note
    # every list reflects their working copy, so it may run "ahead" of the
    # online MED (entries not yet online; @DEL entries still live there).
    #
    # Grain = the entry: one <ENTRY> → one DictionaryEntry
    # (urn:nabu:dict:med-headwords:<MED id>). Reconciliation (upstream
    # advertises no total; whole-file census 2026-11-26): 57,094 <ENTRY>,
    # 57,094 unique ids (2,587 decimal post-print ids), SEQ 1–57,094 in
    # order; 398 @DUB, 91 @DEL — every one kept, flagged; 0 skipped.
    #
    # == The list vintage
    #
    # The editors announce a refreshed list. The vintage this adapter
    # holds is pinned three ways: FILENAME (its YYYYMM stamp, carried as
    # "list_vintage" on the document ref and in the document title), the
    # body's LIST_SHA256 (fetch refuses any other bytes), and the served
    # Last-Modified FileFetch records in canonical/med-headwords/
    # .file-fetch.json. A new list is a conscious re-pin: new FILENAME +
    # LIST_SHA256 + fixture README, then a re-sync (the superseded file goes
    # to the attic).
    #
    # == License (granted by email, 2026-11-06)
    #
    # Paul F. Schaffner (Middle English Dictionary / Middle English
    # Compendium, University of Michigan): the list is "to be used in
    # whatever way you choose. No conditions whatever", with one courtesy
    # request — the list is never re-posted for download — and credit to the
    # MED. → class nc: full local use on every surface (search, define, MCP —
    # nc is not MCP-excluded), and the class every redistribution path
    # (`--license-class open,attribution` exports, the nabu-data builds)
    # already screens out row by row, which is what keeps the list from
    # being re-posted. research_private would wrongly withhold it from MCP;
    # attribution would let it flow into published datasets.
    #
    # == fetch / sync policy
    #
    # One FileFetch of the list, sha256-verified against LIST_SHA256 BEFORE
    # the tree mutates (the wilkens-oui choreography). Nothing is
    # materialized beside it. sync_policy manual.
    class MedHeadwords < Nabu::Adapter
      FILENAME = "headwords_202310.xml"
      LIST_URL = "https://medictionary.info/pages/#{FILENAME}".freeze
      LIST_SHA256 = "e530ecacd3b94d79327882cdc32f1e1a0fcbbf32183bdb18a0a46f3eff56b268"
      LIST_PATTERN = /\Aheadwords_(\d{4})(\d{2})\.xml\z/
      DICTIONARY_SLUG = "med-headwords"
      LANGUAGE = MedHeadwordsParser::LANGUAGE

      MANIFEST = Nabu::SourceManifest.new(
        id: "med-headwords",
        name: "Middle English Dictionary — headwords, variant spellings and entry ids (MED editors' list)",
        license: "Granted by email, 2026-11-06, by Paul F. Schaffner (Middle English Dictionary, " \
                 "University of Michigan): \"to be used in whatever way you choose. No conditions " \
                 "whatever\" — one courtesy request: the list is never re-posted for download; credit " \
                 "the Middle English Dictionary. Class nc keeps it out of every redistribution set.",
        license_class: "nc",
        upstream_url: LIST_URL,
        parser_family: "med-headwords-xml",
        credit: "Middle English Dictionary, ed. Robert E. Lewis et al. (Ann Arbor: University of " \
                "Michigan Press, 1952–2001; online edition in the Middle English Compendium, ed. " \
                "Frances McSparran et al., University of Michigan Library) — headword list by the " \
                "MED editors, medictionary.info"
      )

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      # The probe HEADs the list itself: reachability + Last-Modified drift
      # vs the .file-fetch.json pin (no probe-shaped license endpoint).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: LIST_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # "2023-10" for headwords_202310.xml.
      def self.vintage(filename = FILENAME)
        year, month = LIST_PATTERN.match(filename)&.captures
        year && "#{year}-#{month}"
      end

      # +sha256+ exists for the WebMock'd fetch tests — real syncs keep the
      # frozen pin.
      def initialize(sha256: LIST_SHA256)
        super()
        @sha256 = sha256
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{FILENAME}", path: File.expand_path(path),
          metadata: { "dictionary" => DICTIONARY_SLUG, "list_vintage" => self.class.vintage }
        )
      end

      # Another vintage of the list in the workdir is skipped by rule (one
      # pinned vintage is the shelf); any other XML file is a stray, named.
      def discovery_skips(workdir)
        return DiscoverySkips.new unless File.directory?(workdir)

        others = Dir.glob("*.xml", base: workdir).sort - [FILENAME]
        vintages, strays = others.partition { |name| LIST_PATTERN.match?(name) }
        notes = vintages.map do |name|
          "#{name}: another vintage of the MED headword list (#{self.class.vintage(name)}) — the shelf " \
            "holds the pinned #{FILENAME} only (skipped by rule)"
        end
        notes += strays.map { |name| "#{name}: not the MED headword list" }
        DiscoverySkips.new(skipped_by_rule: vintages.size, unrecognized: strays.size, notes: notes)
      end

      def parse(document_ref)
        vintage = document_ref.metadata.fetch("list_vintage", self.class.vintage)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE, canonical_path: document_ref.path,
          title: "Middle English Dictionary — headwords, variant spellings and entry ids (list of #{vintage})"
        )
        MedHeadwordsParser.new.entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "med-headwords: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(url: LIST_URL, dir: workdir, filename: FILENAME,
                              attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "med-headwords fetch failed into #{workdir}: #{e.message}"
      end

      private

      # A 304 repeats the stored pin (nothing touched); any fetched body
      # must be the pinned vintage.
      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @sha256

        raise Nabu::FetchError,
              "med-headwords: #{FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned #{@sha256}; " \
              "review upstream (a refreshed list?) and re-pin (owner decision)"
      end
    end
  end
end
