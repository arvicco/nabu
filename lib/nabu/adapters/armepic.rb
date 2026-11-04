# frozen_string_literal: true

require_relative "armepic_epidoc_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # ArmEpiC — the Armenian Epigraphic Corpus, ArtsakhEpiC sub-corpus
    # (EPFL Digital Humanities Laboratory; eds. Hamest Tamrazyan, Gayane
    # Hovhannisyan, Arsen Harutyunyan, Narine Sarvazyan; data curators
    # Emanuela Boros, Narek Meloyan): fifty Armenian inscriptions of
    # Artsakh, 1183–1998 — donations, building records, khachkar
    # dedications, memorials, an epitaph — in diplomatic TEI/EpiDoc with
    # word-level lemma + UPOS. A thin composition of the
    # ArmepicEpidocParser family with per-file FileFetch GETs against the
    # immutable Zenodo record.
    #
    # == License (first-hand, 2026-11-04)
    #
    # The deposit's LICENSE.txt: "The texts and data of this work (all
    # TEI/EpiDoc XML files and authority files in this deposit) are licensed
    # under the Creative Commons Attribution-NonCommercial 4.0 International
    # License (CC BY-NC 4.0)"; the record's license field cc-by-nc-4.0;
    # every inscription's <licence target=".../by-nc/4.0/">. The images are
    # carved out ("not covered by this licence") and never fetched → nc.
    #
    # == Grains (enumerated 2026-11-04 against the record's 66 files)
    #
    #   ART<nnnn>.xml      50 inscription records — ACCEPTED, one document
    #                      each (urn:nabu:armepic:art<nnnn>).
    #   ArmEpiC_List*.xml  12 authority vocabularies — SKIPPED BY RULE at
    #                      discover (counted in discovery_skips); the
    #                      records carry each term's labels inline.
    #   README.md, CHANGES_v7.md, LICENSE.txt — deposit documentation,
    #                      fetched for provenance, never .xml.
    #   ArtsakhEpiC_v7_images.zip (256 MB) — outside the license, never
    #                      fetched.
    #
    # == Count reconciliation
    #
    # Upstream's own advertised count: the record description's "fifty
    # Armenian epigraphic inscriptions from Artsakh (ART0001–ART0050)".
    # The fixture-time census through this parser (the whole deposit,
    # 2026-11-04): 50 records → 50 documents / 374 passages (371 lb-keyed
    # lines + 3 lb-less monogram textparts) / 1,872 word tokens, 12
    # authority lists skipped by rule, 0 errored — accepted + skipped = the
    # 62 XML files the record serves. FIRST-SYNC RECONCILIATION: pending —
    # recorded here once the first real sync lands.
    #
    # == fetch / sync policy
    #
    # 65 GETs (every file but the images zip), one FileFetch subdirectory
    # per file (a FileFetch owns its directory: canonical/armepic/ART0001/
    # ART0001.xml), each body checked against the record's own md5 (FILES)
    # BETWEEN download and any tree mutation; the breaker sees the combined
    # doomed set. Nothing is materialized beside the fetched files. Zenodo
    # versions are immutable: a new ArtsakhEpiC release is a NEW record id
    # the owner re-pins. sync_policy manual.
    class Armepic < Nabu::Adapter
      RECORD_ID = "23501516"
      RECORD_URL = "https://zenodo.org/records/#{RECORD_ID}".freeze
      RECORD_FILES_URL = "https://zenodo.org/api/records/#{RECORD_ID}/files".freeze

      CITATION = "Tamrazyan, H., Hovhannisyan, G., Harutyunyan, A., Boros, E., Sarvazyan, N., Meloyan, N., " \
                 "ArmEpiC – Armenian Epigraphic Corpus (ArtsakhEpiC Sub-Corpus), v7, EPFL DHLAB, 2026, " \
                 "doi 10.5281/zenodo.#{RECORD_ID} — CC BY-NC 4.0".freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "armepic",
        name: "ArmEpiC — Armenian Epigraphic Corpus, ArtsakhEpiC (EPFL DHLAB)",
        license: "CC BY-NC 4.0 (the deposit's LICENSE.txt: \"The texts and data of this work (all " \
                 "TEI/EpiDoc XML files and authority files in this deposit) are licensed under the " \
                 "Creative Commons Attribution-NonCommercial 4.0 International License (CC BY-NC 4.0)\"; " \
                 "Zenodo record 10.5281/zenodo.#{RECORD_ID} license cc-by-nc-4.0; every record's " \
                 "<licence target=creativecommons.org/licenses/by-nc/4.0/>). \"Images: the photographs " \
                 "and drawings in this deposit are not covered by this licence\" — never fetched.",
        license_class: "nc",
        upstream_url: RECORD_URL,
        parser_family: "armepic-epidoc",
        credit: CITATION
      )

      # Every deposit file but the images zip, under the record API's own
      # md5 (read 2026-11-04; every download verified against it).
      FILES = {
        "ART0001.xml" => "d2147a0dde3763f4604813120c20f7ed",
        "ART0002.xml" => "17283ff34de31d2813fd01031a0a227d",
        "ART0003.xml" => "9fa4bc71811ab392814a17cb4e03d72c",
        "ART0004.xml" => "2cf2c40dc48a8c53ea2f903f3bc76b2c",
        "ART0005.xml" => "3f2183a1b49358d51be03f634a1f60dc",
        "ART0006.xml" => "e14c88b8301a6fcb8844f5c09f81c3f2",
        "ART0007.xml" => "659de2c9ec5af44a30072c8ffd91079e",
        "ART0008.xml" => "38ee3dfd58fb0e8db504c92867090efa",
        "ART0009.xml" => "e7d5d2ceede891e6a8750e962eed5022",
        "ART0010.xml" => "1ea1935c182f6d52f493ccd893c9d30a",
        "ART0011.xml" => "efee93445ab8912bacc370eeaef8b20b",
        "ART0012.xml" => "260e63b89c5538fbee0c083d4f70b8ac",
        "ART0013.xml" => "6e07a0181dec6d5c324a62ea6e376978",
        "ART0014.xml" => "9500cf56a434a614db2788cf22a7a5ff",
        "ART0015.xml" => "908627fd7a26e2bfc88d7398207536ff",
        "ART0016.xml" => "f1ac138b62acbd277284d8aa512c25b0",
        "ART0017.xml" => "644088190c7c60c1726d9d4dbefdfdb0",
        "ART0018.xml" => "c6ebca19667c185020004a11201544b4",
        "ART0019.xml" => "128e9605ca966b0910f1e1654f9a49a9",
        "ART0020.xml" => "c7aadad2318f75ed45753b303e4655cd",
        "ART0021.xml" => "b2cfb89caf2d56b105e68d270287f6f9",
        "ART0022.xml" => "b2233c9bb312fc2072130a31bcdfd5bf",
        "ART0023.xml" => "6057b1ec105c9b8576b118e6963f97b2",
        "ART0024.xml" => "5d7f78e73b819534f272823f538da493",
        "ART0025.xml" => "3d0470b394d060f36d68d4c734056854",
        "ART0026.xml" => "89e868953a32305f2f5cdc7e4dbd13f0",
        "ART0027.xml" => "4cc16b711af0ca9e385e4f5adb7b0825",
        "ART0028.xml" => "30e08d9f91e57e2965e621ad746ce1b6",
        "ART0029.xml" => "f1e266ab7f2be0a7beaa7d0980b9c28b",
        "ART0030.xml" => "11a242f1a49e3d151a1f86cd4c84c1b8",
        "ART0031.xml" => "897ee5acb926e4582d4fa5d1663eaf9c",
        "ART0032.xml" => "4a6850f967ddf92248449470cc95a23a",
        "ART0033.xml" => "6268ec4e9c00ec4e44dc03ebe6d8dc07",
        "ART0034.xml" => "9e82d270bd7925822ba23e81e2d24bd5",
        "ART0035.xml" => "5d98c49b962cb8c4d7674c9f1fa9ac11",
        "ART0036.xml" => "9752d133439cafd77c51bde20472aebb",
        "ART0037.xml" => "ffa9eae8aca8db85d75d289706b1eeea",
        "ART0038.xml" => "619ad755eb195d2ce2ca2f0f76b822cb",
        "ART0039.xml" => "c2f6d05591f8e1b9487db790a61fd71b",
        "ART0040.xml" => "28c9e86c6b1aa6e2eaf991080110f8e4",
        "ART0041.xml" => "644d8099521519037e4228c76e5bd476",
        "ART0042.xml" => "6919cb8d2e0fa22d6e7356756b2a0bbf",
        "ART0043.xml" => "2475a76e5cf5aa7f03e73ca9584527c0",
        "ART0044.xml" => "8d6d068a3da67c36e75d1dbb83ae57ad",
        "ART0045.xml" => "c9927869efe4e86d125e2fdd7de4742e",
        "ART0046.xml" => "1f00d67f8843064a69a17b5ca9887da9",
        "ART0047.xml" => "cb9c7dd60efa2556c5dc5d07dc61500d",
        "ART0048.xml" => "01737894305ca2bfebe3d9061a1715e6",
        "ART0049.xml" => "e30b39afc50412bfaee39b4d854a78d3",
        "ART0050.xml" => "c8026c1f02398140e2dce730747304d0",
        "ArmEpiC_ListAbbreviationType_crm.xml" => "819b905ad21069ab165272534e8b7b1a",
        "ArmEpiC_ListBibl_crm.xml" => "5263abf010b5a0ca6eeffeb1897013aa",
        "ArmEpiC_ListChronology_crm.xml" => "0386f30402bcb9a6bfae389852238a72",
        "ArmEpiC_ListEditors.xml" => "769644de523a8c54f42fe8a3e18642ad",
        "ArmEpiC_ListInscriptionType_crm.xml" => "e4a0b7bda86ffe853124e5400d4aeaa1",
        "ArmEpiC_ListMaterial_crm.xml" => "81d589ed77d6e8d5f4c9ee4105148cbc",
        "ArmEpiC_ListMonument_crm.xml" => "20525a4d4a4dc0292a0cb49979c829da",
        "ArmEpiC_ListObjectType_crm.xml" => "196a2195a70bbd50dbbed437f5ba93b7",
        "ArmEpiC_ListPlace_crm.xml" => "dbe8cc10a177c20a9a44aa41ec05d51a",
        "ArmEpiC_ListPreservation_crm.xml" => "86d6d8b33615fe2c464a1968fba1a914",
        "ArmEpiC_ListScript_crm.xml" => "22c44676158aef106b9b881184018d2b",
        "ArmEpiC_ListTechniques_crm.xml" => "01e7416d0e5d7b82883057bb5f3df30a",
        "CHANGES_v7.md" => "77403850b0315f6f9a8a6c237908ca24",
        "LICENSE.txt" => "5b6552967b96fbfea57d10eaff04e66a",
        "README.md" => "c44a45db2ed5c9b98b0feda3480fb936"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # One HEAD against ART0001's FileFetch state: the record is
      # versioned-immutable, so one file's reachability answers for the
      # deposit (65 probes would say nothing more).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.keys.grep(ArmepicEpidocParser::FILENAME).first(1).map do |filename|
          Nabu::Adapter::HttpProbeTarget.new(
            label: "zenodo #{RECORD_ID} #{filename}", zip_url: file_url(filename), metadata_url: nil,
            state_subdir: subdir_of(filename), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def self.file_url(filename)
        "#{RECORD_FILES_URL}/#{filename}/content"
      end

      def self.subdir_of(filename)
        File.basename(filename, File.extname(filename))
      end

      # +files+ overrides the pin table (tests; a future owner re-pin).
      def initialize(files: FILES)
        super()
        @files = files
      end

      # One ref per ART<nnnn>.xml anywhere under the workdir (the fetched
      # tree nests one per subdir), attic excluded, sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        xml_paths(workdir).select { |path| record?(path) }.map do |path|
          Nabu::DocumentRef.new(source_id: manifest.id, id: ArmepicEpidocParser.urn_for(path), path: path)
        end.sort_by(&:id).each(&block)
      end

      # The authority vocabularies (ArmEpiC_List*.xml) are the deposit's
      # second grain, skipped by rule; any other .xml is unrecognized.
      def discovery_skips(workdir)
        others = xml_paths(workdir).reject { |path| record?(path) }
        authority, unknown = others.partition { |path| File.basename(path).start_with?("ArmEpiC_List") }
        notes = []
        notes << "#{authority.size} authority vocabularies (ArmEpiC_List*.xml) skipped by rule" if authority.any?
        notes.concat(unknown.map { |path| "#{File.basename(path)}: not an inscription record" })
        DiscoverySkips.new(skipped_by_rule: authority.size, unrecognized: unknown.size, notes: notes)
      end

      def parse(document_ref)
        ArmepicEpidocParser.new.parse(document_ref.path, urn: document_ref.id)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download every pinned file + verify its md5 BETWEEN download and
      # any tree mutation; the breaker sees the combined doomed set; a 304
      # touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each { |filename, fetch| prepare_and_verify!(filename, fetch) }
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.values.last.sha, fetched_at: Time.now, notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "armepic fetch failed into #{workdir}: #{e.message}"
      end

      private

      def xml_paths(workdir)
        Dir.glob(File.join(workdir, "**", "*.xml"))
           .reject { |path| path.delete_prefix(File.join(workdir, "")).split(File::SEPARATOR).include?(ATTIC_DIRNAME) }
           .map { |path| File.expand_path(path) }
      end

      def record?(path)
        ArmepicEpidocParser::FILENAME.match?(File.basename(path))
      end

      def file_fetches(workdir, progress)
        @files.keys.to_h do |filename|
          subdir = self.class.subdir_of(filename)
          [filename, Nabu::FileFetch.new(
            url: self.class.file_url(filename), dir: File.join(workdir, subdir), filename: filename,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
          )]
        end
      end

      def prepare_and_verify!(filename, fetch)
        fetch.prepare!
        pin = @files.fetch(filename)
        return if fetch.not_modified? || fetch.md5 == pin

        raise Nabu::FetchError,
              "armepic: #{filename} misses its md5 pin (expected #{pin}, got #{fetch.md5}) — Zenodo " \
              "record #{RECORD_ID} is versioned-immutable, so this is corruption or an unannounced " \
              "re-release; read #{RECORD_URL} and re-pin FILES only after reading it"
      end

      def fetch_notes(fetches)
        modified = fetches.values.count { |fetch| !fetch.not_modified? }
        base = if modified.zero?
                 "not modified (304 ×#{fetches.size})"
               else
                 "zenodo #{RECORD_ID}: #{modified} of #{fetches.size} files fetched, md5 pins verified"
               end
        [base, attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
