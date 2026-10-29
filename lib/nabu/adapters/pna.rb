# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"

module Nabu
  module Adapters
    # PNA — "A Social Network of the Prosopography of the Neo-Assyrian
    # Empire" (Heidi Jauhiainen & Tero Alstola, University of Helsinki;
    # Journal of Open Humanities Data 8:8, 2022), the persons of The
    # Prosopography of the Neo-Assyrian Empire (Radner & Baker eds.,
    # 1998–2011, the Neo-Assyrian Text Corpus Project) extracted with their
    # attestations. Registered as a person-authority MODULE (the cbdb/dprr
    # shape — zero document rows): it feeds the "pna" person-index slice
    # through Nabu::PnaPersons.
    #
    # == The channel (read 2026-10-28)
    #
    # Zenodo record 6220409 — version 3 of concept DOI
    # 10.5281/zenodo.5862904 (index 2, is_last at the read), published
    # 2022-01-17 — serves three files: Networks.zip, SupplementaryData.zip
    # and README.txt. Fetch GETs all three and lands them VERBATIM, each
    # behind a hard sha256 pin (FILES; their md5s match the record's own
    # checksums), writing nothing until all three verify; the state file
    # records the pins. Zenodo versions are immutable: a mismatch is
    # corruption or an unannounced re-release — the owner reads the record
    # and re-pins. Nothing is unpacked: PnaPersons reads the archive
    # members in-process, so the tree is exactly the record's files plus
    # the state file (no materialized_paths to declare).
    #
    # == Delivery grains (census over the v3 files, 2026-10-28)
    #
    # - Networks/NodeList.csv — 17,387 persons, one row each (TAKEN: one
    #   person-index row per person, every column mined — PnaPersons).
    # - Networks/biModal.csv — 25,164 person-text links over 4,188 texts
    #   named by publication (TAKEN: the person's texts, resolved onto held
    #   documents by the crosswalk).
    # - SupplementaryData/Lists/oraccConcordances — 36,006 Oracc catalogue
    #   rows, designation → project/id (TAKEN: the crosswalk's first step).
    # - Networks/EdgeList.csv + EdgeList_NrOfCooccurrences.csv — the
    #   one-mode co-occurrence network, 149,045 edges in two weightings
    #   (SKIPPED BY RULE: co-presence in a text is no relation the person
    #   index has a lane for — no kinship/association lane; counted in the
    #   module census as skipped). PNANetworks.gephi is the same network as
    #   a Gephi project (skipped with it).
    # - SupplementaryData's remaining Lists (the normalization tables that
    #   produced NodeList's categories), Output/ (the pipeline's
    #   intermediate stages), the Java sources and serialized .bin
    #   intermediates (SKIPPED: the method's working material, already
    #   applied in NodeList/biModal — kept verbatim in the archive).
    #
    # == The crosswalk census (box catalog of 2026-10-28)
    #
    # Of the 4,188 publications, 3,084 resolve to a held document: 2,254
    # through the dataset's own Oracc concordance (1,820 in the
    # concordance's own project, 432 to the held copy of the same id in
    # another project, 2 ambiguous-project picks by designation), 696 by
    # designation under the zero-pad fold (the ATAE archives — StAT,
    # BATSH, SAAB, CTN …), 134 in cdli (5 by concordance id, 129 by
    # designation — mostly ABL letters). SAA itself: 2,273 of 2,275
    # resolve; SAA 1 28 and SAA 4 340 name Oracc ids the held saao build
    # lacks. The 1,104 unresolved (7,375 of the 25,164 links) are texts
    # neither shelf holds by any designation PNA uses: excavation and
    # museum numbers (ND 174, As 117, VAT 52, A 18, BM, K …), older
    # editions (GPA 115, TH 74, CT 54, KAV, VS, TCL, ADD 7, ABL 16 …),
    # journal citations (BaM, RA, AfO, ZA, Iraq …) and unpublished
    # material — they ride as bare citations (publication kept, urn nil).
    # 17,789 of 25,164 links (71%) reach a held text.
    #
    # == License (verified in the downloaded files 2026-10-28)
    #
    # README.txt (the record's top-level file), last line: "These files are
    # licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported
    # License." — the same sentence closes Networks/readme.txt,
    # SupplementaryData/README.txt and SupplementaryData/Lists/readme.md;
    # the Zenodo record's license field reads cc-by-sa-3.0. The README
    # records the PNA editors' (Baker, Parpola, Radner) permission to
    # publish the dataset. Class attribution (share-alike rides the
    # attribution class — internal use unencumbered; a public export of
    # derived rows carries CC BY-SA 3.0 and the attribution).
    class Pna < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/6220409"
      FILE_URL = "https://zenodo.org/api/records/6220409/files/%<name>s/content"

      # sha256 of each v3 file, pinned from the 2026-10-28 download (md5s
      # match the record: fbcd2b6a…, 115bf1be…, 1aa82a89…).
      FILES = {
        "Networks.zip" => "4e290e3fcf33a619673865661b926b035a2275261e4d10be1a98874a8fd40f3e",
        "SupplementaryData.zip" => "f10ddb6dca062fb5272b201ab2d90b929f10b4e56d36bc32773c5b6b3a6a08f8",
        "README.txt" => "e2aa0953ab9ab06e068a6e9aad4966577f1e7ee91e462af9e1b8325acebf5385"
      }.freeze

      STATE_FILE = ".pna-fetch.json"

      MANIFEST = Nabu::SourceManifest.new(
        id: "pna",
        name: "PNA — A Social Network of the Prosopography of the Neo-Assyrian Empire (person authority)",
        license: "CC BY-SA 3.0 (Jauhiainen & Alstola, Zenodo 10.5281/zenodo.6220409 v3; README.txt " \
                 "verbatim \"These files are licensed under a Creative Commons Attribution-ShareAlike 3.0 " \
                 "Unported License.\", verified in the downloaded files 2026-10-28)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "pna-network"
      )

      def self.manifest
        MANIFEST
      end

      def self.file_url(name) = format(FILE_URL, name: name)

      # Liveness only: the record page answers; the files are pinned.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "zenodo record", zip_url: RECORD_URL, metadata_url: nil,
          state_subdir: "", state_file: STATE_FILE, liveness_only: true
        )]
      end

      def self.person_index_producer? = true

      def self.person_index_producer(catalog:)
        Nabu::PnaPersons::Producer.new(catalog: catalog)
      end

      def self.module_census(read) = Nabu::PnaPersons.census(read)

      # +pins+ overrides the per-file sha256 pins (tests; a re-pin drill).
      def initialize(pins: FILES)
        super()
        @pins = pins
      end

      # A feature module mints no documents (the cbdb shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        nil
      end

      def parse(document_ref)
        raise ParseError, "#{document_ref.id}: pna is a person authority, not a text source — " \
                          "parse is unreachable"
      end

      # All three files → each verified against its pin → written only
      # after every one checks out. Already-pinned files on disk = no-op.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        sha = Digest::SHA256.hexdigest(JSON.generate(@pins))
        if current?(workdir)
          return FetchReport.new(sha: sha, fetched_at: Time.now, notes: "already at Zenodo v3 (pins verified)")
        end

        progress&.call("Downloading Zenodo record 6220409 (#{@pins.keys.join(', ')})…\n")
        bodies = @pins.to_h { |name, pin| [name, download!(name, pin)] }
        bodies.each { |name, bytes| File.binwrite(File.join(workdir, name), bytes) }
        File.write(File.join(workdir, STATE_FILE),
                   JSON.pretty_generate("record" => RECORD_URL, "sha256" => sha, "files" => @pins,
                                        "fetched_at" => Time.now.utc.iso8601))
        FetchReport.new(sha: sha, fetched_at: Time.now, notes: fetch_notes(workdir))
      end

      private

      def download!(name, pin)
        response, = Nabu::RedirectFollow.get(self.class.file_url(name), http: Nabu::ZipFetch.default_http,
                                                                        error: Nabu::FetchError, accept: [200])
        bytes = response.body.to_s.b
        actual = Digest::SHA256.hexdigest(bytes)
        return bytes if actual == pin

        raise Nabu::FetchError,
              "pna: #{name} misses its sha256 pin (expected #{pin}, got #{actual}) — Zenodo versions are " \
              "immutable, so this is corruption or an unannounced re-release; read #{RECORD_URL} and re-pin " \
              "Adapters::Pna::FILES only after reading the record"
      end

      def current?(workdir)
        @pins.all? do |name, pin|
          path = File.join(workdir, name)
          File.file?(path) && Digest::SHA256.file(path).hexdigest == pin
        end
      end

      def fetch_notes(workdir)
        counts = Nabu::ModuleCensus.at_dir(self.class, workdir).to_a.to_h { |c| [c.label, c.count] }
        "Zenodo v3 pins verified: #{counts['persons']} persons, #{counts['person-text links']} links"
      end
    end
  end
end
