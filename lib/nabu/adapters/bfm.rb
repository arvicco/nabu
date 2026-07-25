# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "pathname"

require_relative "bfm_tei_parser"
require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "../git_fetch"

module Nabu
  module Adapters
    # BFM — Base de français médiéval, corpus BFM2022 (P45-4): ENS de Lyon /
    # UMR 5317 IHRIM (resp. Céline Guillot-Barbance; digital resp. Alexei
    # Lavrentiev). 219 TEI P5 texts / ~6.45M words of medieval French, 842
    # (Serments de Strasbourg) through the end of the 15th century — the Old
    # French text mass, first registrant of the `romance` axis. Distributed
    # via NAKALA (Huma-Num) as one data(set) per text under collection
    # doi:10.34847/nkl.93ee3ts1 (published 2022-11-07). A thin composition of
    # the bespoke `bfm-tei` parser family; the adapter owns identity, the
    # license evidence, and the sha1-pinned fetch.
    #
    # == Identity
    #
    # Each NAKALA data ships ONE TEI file <stem>.xml, and the stem IS the
    # BFM's own text identifier (== the header's <title type="reference">,
    # == the catalog id at catalog.bfm-corpus.org/<stem> — verified on the
    # fixtures), so:
    #
    #   document urn  urn:nabu:bfm:<stem>            (urn:nabu:bfm:nabaret)
    #   passage urn   <document-urn>:<div-path>.<unit>  (…:nabaret:d1.l1)
    #
    # The <div-path>.<unit> citation is minted by the parser (positional and
    # coherent — see BfmTeiParser). ref.id == parse(ref).urn (the conformance
    # identity the sync breaker relies on).
    #
    # == License — the D45-c evidence (two layers, both read from bytes)
    #
    # The NAKALA collection description, verbatim: "Les corpus sont diffusés
    # sous Licence ouverte Etalab, à l'exclusion de l'apparat critique
    # disponible sous licence CC BY-NC-SA 3.0 pour les textes suivants :
    # AlexisRaM, ChaceOisiiT, eulaliBfm, ImMondePrK, PsArundP, qgraal_cm,
    # QJoyesKa, strasbBfm.xml." Every per-data record carries dcterms:rights
    # "Texte : Domaine public" + "Suppléments numériques (balisage XML-TEI,
    # métadonnées, annotations linguistiques) : Sous licence Etalab"; the 8
    # named files add "Apparat critique : sous licence CC BY-NC-SA 3.0" and
    # point their in-file <licence target> at creativecommons.org/licenses/
    # by-nc-sa/3.0/fr. The Licence Ouverte 2.0 grant (Etalab, verbatim): free
    # to "communiquer, reproduire, copier … adapter, modifier … diffuser,
    # redistribuer … exploiter à titre commercial", "Sous réserve de :
    # mentionner la paternité de l'«Information» : sa source … et la date de
    # la dernière mise à jour" → class `attribution`.
    #
    # THE VERDICT: one class suffices. The parser drops the apparat critique
    # from the reading stream BY CONSTRUCTION (<note> subtrees and the
    # editorial-French <head xml:lang="fr"> titles never enter passages), so
    # what the catalog stores is text (public domain) + TEI supplements
    # (Etalab) on all 219 files — no NC bytes are served. The NC layer exists
    # only inside the 8 canonical files on disk; each document's own
    # <licence target> URL rides Document#metadata["license_url"] so the
    # per-file evidence stays queryable.
    #
    # == fetch: the sha1-pinned NAKALA inventory (sync_policy: manual)
    #
    # NAKALA serves each file at the sha1-ADDRESSED url
    # api.nakala.fr/data/<doi>/<file-sha1> — the address is the pin. INVENTORY
    # below records all 219 (stem, data-DOI, sha1) rows as censused from the
    # collection API on 2026-07-25 (BFM2022 is a VERSIONED, frozen release;
    # a re-pin against a future BFM20xx is a conscious owner act: regenerate
    # the table from api.nakala.fr/collections/10.34847/nkl.93ee3ts1/datas).
    # The fetch walks the inventory politely and resumably (a file already on
    # disk at its pinned sha1 is never re-downloaded), verifies every body
    # against the pin (mismatch aborts — FetchError, nothing lands), attics
    # any live file the inventory no longer pins (never hard-deletes; the
    # house retention contract), and reports the corpus-level pin = sha256
    # over the sorted per-file sha1 table. ~164 MB total on first sync,
    # owner-fired.
    class Bfm < Nabu::Adapter
      COLLECTION_URL = "https://nakala.fr/collection/10.34847/nkl.93ee3ts1"
      DATA_BASE_URL = "https://api.nakala.fr/data"
      DOI_PREFIX = "10.34847"

      XML_DIRNAME = "xml"
      ATTIC_DIRNAME = ".attic"
      LANGUAGE = "fro"
      URN_PREFIX = "urn:nabu:bfm:"

      # Politeness pause between actual downloads (the riig crawl posture);
      # cached files pay nothing.
      CRAWL_DELAY = 0.15

      MANIFEST = Nabu::SourceManifest.new(
        id: "bfm",
        name: "Base de français médiéval — BFM2022 (ENS de Lyon / IHRIM)",
        license: "Texte: Domaine public; suppléments numériques (balisage XML-TEI, " \
                 "métadonnées, annotations linguistiques): Licence Ouverte / Open Licence 2.0 " \
                 "(Etalab — \"mentionner la paternité … sa source et la date de la dernière " \
                 "mise à jour\") → attribution. The apparat critique of 8 named files is " \
                 "CC BY-NC-SA 3.0 FR and is dropped from the reading stream by the parser " \
                 "(D45-c). Cite the BFM: bfm.ens-lyon.fr, collection doi:10.34847/nkl.93ee3ts1",
        license_class: "attribution",
        upstream_url: COLLECTION_URL,
        parser_family: "bfm-tei"
      )

      def self.manifest
        MANIFEST
      end

      # No git repository to ls-remote — the upstream is a versioned NAKALA
      # collection (the sabellic-loans/menotec no-git posture).
      def self.upstream_repo_urls = []

      # One DocumentRef per xml/<stem>.xml, sorted by urn. A pre-fetch
      # workdir yields nothing (xml/ absent).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Delegate to the BfmTeiParser with identity and language; the parser
      # mines title, author, the composition-date envelope and the license
      # target from the teiHeader.
      def parse(document_ref)
        BfmTeiParser.new.parse(
          document_ref.path,
          urn: document_ref.id, language: LANGUAGE
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # The pinned-inventory crawl (see the class comment). Resumable and
      # non-destructive: verify-or-download each pinned file, attic strays,
      # never leave unverified bytes in the live tree.
      def fetch(workdir, progress: nil, force: false)
        xml_dir = File.join(workdir, XML_DIRNAME)
        FileUtils.mkdir_p(xml_dir)
        downloaded, atticked = sync_pinned_files(xml_dir, workdir, progress)
        atticked += attic_strays(xml_dir, workdir, force: force)
        notes = fetch_notes(downloaded: downloaded, atticked: atticked)
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: inventory_sha, fetched_at: Time.now, notes: notes)
      end

      private

      # Seam for tests (the house local-fixture pattern): the pinned
      # stem => [doi-suffix, sha1] table.
      def inventory
        INVENTORY
      end

      def sync_pinned_files(xml_dir, workdir, progress)
        downloaded = 0
        atticked = []
        inventory.each do |stem, (doi, sha1)|
          target = File.join(xml_dir, "#{stem}.xml")
          next if File.file?(target) && Digest::SHA1.file(target).hexdigest == sha1

          body = download(stem, doi, sha1, progress)
          atticked.concat(attic_divergent(target, workdir))
          write_atomically(target, body)
          downloaded += 1
        end
        [downloaded, atticked]
      end

      def download(stem, doi, sha1, progress)
        url = "#{DATA_BASE_URL}/#{doi_of(doi)}/#{sha1}"
        progress&.call("Downloading #{stem}.xml…\n")
        sleep(CRAWL_DELAY) if CRAWL_DELAY.positive?
        response, = RedirectFollow.get(url, http: ZipFetch.default_http, error: Nabu::FetchError)
        body = response.body.to_s.b
        actual = Digest::SHA1.hexdigest(body)
        raise Nabu::FetchError, "#{stem}.xml: sha1 mismatch (pinned #{sha1}, got #{actual})" if actual != sha1

        body
      end

      def doi_of(doi)
        doi.include?("/") ? doi : "#{DOI_PREFIX}/#{doi}"
      end

      def write_atomically(target, body)
        tmp = "#{target}.tmp"
        File.binwrite(tmp, body)
        File.rename(tmp, target)
      end

      # A live file whose bytes diverge from the pin (a re-pinned text) is
      # retained in the attic before the fresh body lands — first copy wins,
      # GitFetch-format manifest (the FileFetch retention contract).
      def attic_divergent(target, workdir)
        return [] unless File.file?(target)

        attic_file(target, workdir)
      end

      # Live xml/ files the inventory no longer pins: run the caller-side
      # mass-deletion breaker BEFORE the tree mutates, then attic and remove.
      def attic_strays(xml_dir, workdir, force:)
        pinned = inventory.keys.to_set { |stem| File.join(xml_dir, "#{stem}.xml") }
        strays = Dir.glob(File.join(xml_dir, "*.xml")).reject { |path| pinned.include?(path) }
        return [] if strays.empty?

        guard_mass_deletion!(workdir, strays, force: force)
        strays.flat_map do |path|
          copies = attic_file(path, workdir)
          FileUtils.rm_f(path)
          copies
        end
      end

      def attic_file(path, workdir)
        rel = Pathname.new(path).relative_path_from(Pathname.new(workdir)).to_s
        destination = File.join(workdir, ATTIC_DIRNAME, rel)
        return [] if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(path, destination)
        record_attic_manifest(workdir, rel)
        [rel]
      end

      def record_attic_manifest(workdir, rel)
        manifest_path = File.join(workdir, ATTIC_DIRNAME, GitFetch::ATTIC_MANIFEST)
        manifest = File.exist?(manifest_path) ? JSON.parse(File.read(manifest_path)) : {}
        manifest[rel] ||= inventory_sha # first record wins
        FileUtils.mkdir_p(File.dirname(manifest_path))
        File.write(manifest_path, JSON.pretty_generate(manifest))
      end

      # The corpus-level pin: sha256 over the sorted per-file sha1 table —
      # stable across resumed fetches, changed only by an owner re-pin.
      def inventory_sha
        Digest::SHA256.hexdigest(inventory.sort.map { |stem, (_, sha1)| "#{stem}=#{sha1}" }.join("\n"))
      end

      def fetch_notes(downloaded:, atticked:)
        cached = inventory.size - downloaded
        notes = "#{inventory.size} file(s) pinned · #{downloaded} downloaded, #{cached} already at pin"
        atticked.empty? ? notes : "#{notes} · atticked #{atticked.size} file(s)"
      end

      def document_refs(workdir)
        Dir.glob(File.join(workdir, XML_DIRNAME, "*.xml")).map do |path|
          stem = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "#{URN_PREFIX}#{stem}",
            path: File.expand_path(path),
            metadata: { "stem" => stem }
          )
        end.sort_by(&:id)
      end

      # The BFM2022 release census (NAKALA collection 10.34847/nkl.93ee3ts1,
      # read 2026-07-25): stem => [data DOI suffix (10.34847/<suffix>), file
      # sha1]. 219 rows; regenerate wholesale on a deliberate re-pin.
      INVENTORY = {
        "AlexisProlRaM" => ["nkl.2b0837xc", "daca26a85c3edebbd2d9ef9b48d25d250bb90fd1"],
        "AlexisRaM" => ["nkl.7bbe37x6", "e06c6409b82b905ba38a353942d690afa12cb431"],
        "BenDuc1b" => ["nkl.4dee4d8b", "413e5375f0aef819c9f2bd05e44b95f758fc53ee"],
        "Berin1" => ["nkl.df8c1c0k", "2bbc7d6c42da7736baaddb3684a6b8de2d849361"],
        "Berin2" => ["nkl.d378a4l2", "8db070cd321fc5786ad3e6f5c1ee08e416620cd5"],
        "BlondNesle" => ["nkl.e1733451", "554735bd385a5cddb7d1c9089e818a138ab9bbe9"],
        "BrutCist" => ["nkl.fadcnf3b", "b24a011e8cf9e45bc9ad130e21b9887c61159ba4"],
        "ChaceOisiiT" => ["nkl.779ekp22", "4e4717302deefc01a5bf9d1041032c67db4aa3d3"],
        "CharretteKu" => ["nkl.8fbc8004", "4cf11e77d0d4ffa5f088aa314824113ee1c56333"],
        "ChirAlbT" => ["nkl.a55aoth6", "64e97d7c6218f65fce0e077b7242018ef7b66d8e"],
        "ChronSMichelBo" => ["nkl.ec7185r8", "99816163e9d25f57d018ac16608b4e6a3d8f59e0"],
        "CligesKu" => ["nkl.215df441", "ee5fda84962997e1e763f1237c845c3903237f43"],
        "CommPsia1a" => ["nkl.689ej8cd", "0d37cd831fed0a87715419f2c724bdcffb4d5de2"],
        "CoutHector1" => ["nkl.4ea96xnk", "d982401f604ba5ad76bd64f38e0475b57b9890f2"],
        "CoutRoum" => ["nkl.1dc28p00", "bcadb11c477e4797da5800818c3a68f5f77227e3"],
        "DescrEngl" => ["nkl.2b0fek68", "b6a0615fb3db4078827970d7bf3ee4d3380d8422"],
        "DialAme" => ["nkl.2eb455u4", "e9ce0c9957589c7d253ba534a72f51d3f0738435"],
        "DialGreg1" => ["nkl.ab5bx81c", "dcafc3b707d75503e66e0ec2bceb5f6f6ea5f8a7"],
        "DialGreg2" => ["nkl.dd17p18k", "76e34afffc6ac50ef0b091798fd92b5703dd1e1d"],
        "DocSMichel_a" => ["nkl.6f8aryxb", "cc28222b28ed48d0ab7be57f1375d2145a934e28"],
        "Elucidaireiii" => ["nkl.c3a89n13", "f2968c7a201e37fa7c7d5f7764bf0a51d7a22d8f"],
        "EpMontDeu" => ["nkl.ea8b1104", "220e1bfd2093ad33c90020953f9a915e899c1d6d"],
        "EpreuveJudic" => ["nkl.846ers85", "dc10696d4b9902f2d20bc63aef3a54df7418fb65"],
        "ErecKu" => ["nkl.07af5m77", "0600f974e0b72a0bbb2232aedd7f05db4dacc93e"],
        "Fantosme" => ["nkl.0faan7tq", "acc4577495732c4534a6671a0f65acb6bc8dfe0a"],
        "GuillMachFortuneH" => ["nkl.9cafuiw9", "c7ad713790d44dbba8af2e3c512d9bcd127cda35"],
        "GuillMachLyonH" => ["nkl.f4bf60v0", "6eaa6a1d2c4e568fe2fea4369b2caac2aba9074b"],
        "GuillMachPlourH" => ["nkl.2c8fz0ry", "7d4a62f9ca98578c07cf983927edc608e6525e47"],
        "ImMondePrK" => ["nkl.a95a31c0", "d2fa30ee4f550f59d71f43401314f8f471e66d81"],
        "JAntInv" => ["nkl.28eb61ym", "3e47a31a47aa02f13510261cb817475e2aaeb7ef"],
        "JAntRect" => ["nkl.abb18883", "5f4a1acd91b9812749b8d821f16db56033ecbc37"],
        "Juise" => ["nkl.37b089er", "3558d7599aefc50a7a23b4d2a3a086f4cd2806d0"],
        "Lapidal" => ["nkl.f4fby86r", "fde6daf7bb905d191b64c8fcfa44c113b289d939"],
        "Lapidfp" => ["nkl.17a57o47", "e920ed60000ba7090e191c0fc52463f26370611b"],
        "MirNDChartr" => ["nkl.aa50v9q6", "37a0a65743cd8d788797f0b214a576f452557a79"],
        "MirNDOrl" => ["nkl.32fd0ho5", "0b1045a046f3ac37e34ca95ed1484fb01596014c"],
        "OrnDamesR" => ["nkl.d266x082", "361acbe8172febf2e8d101a86aabd1298839250c"],
        "PercevalKu" => ["nkl.558cd5pt", "4e75cd7ee4361fd9ee4aed58abdba2aaf5cb25fe"],
        "ProvSerlo" => ["nkl.c9c81ul5", "9bc68535a6f8be130da82f9d84775676c2a4a748"],
        "PsArundP" => ["nkl.e6e46754", "fa3a960c7b5a2910dbc5baa4be835acc2912b5d6"],
        "PsOrne" => ["nkl.0abavpd9", "6c35f95eaf22a0b5fafb5b681872ac0a62fe2eb7"],
        "QJoyesKa" => ["nkl.1d7av3je", "dfe3c003daec51a9c4e040ab62db52225f429071"],
        "RecCoulTitH" => ["nkl.d17cr7tc", "cda48f67ebf62f4cde63f8729bbd3950aec7d0c5"],
        "RecMedJute" => ["nkl.b8f4my0k", "a64ac685c3495181a3cf23b3ac6bc5184cce1da5"],
        "RegleSBenCotton" => ["nkl.879d4s17", "15281692ce5d64b8acb258806d501df4aa020fdc"],
        "RutebZ" => ["nkl.5443624a", "6f5e9bf91b5f26997c2eef1c949e435128414aae"],
        "SAgnesDob" => ["nkl.837c3143", "3dbdbf3a94a75af704eb29253a37187229035adb"],
        "SBath1" => ["nkl.7589rtfi", "6f857a435d146258bbddd28c7a5c342e40fe4c5e"],
        "SBath2" => ["nkl.7af4r7nv", "6f2f54ff1117d121dfa88459e7478f39721e827f"],
        "SBath3" => ["nkl.eedfj70s", "72637b8b56e9fc82d1bd95ab48a6426abcab5343"],
        "SBath4" => ["nkl.b535yzo2", "a13b1049f75be59c3d68d560080894040c8f365d"],
        "SBernAn" => ["nkl.f0df59um", "619741fda32d5778f3b0d8f3e49d13c3cee5ea9a"],
        "SBernCant" => ["nkl.afa2z894", "a4fa1bab76dc3d310790ac8201ca2d4f01f2ba53"],
        "SEustPr1" => ["nkl.1e41e350", "a0a15411aea6e0b07179a91f6d485e97f23b011a"],
        "SGenPr1" => ["nkl.9eeaco4j", "dd4826609f647e253dc717e602c8078be3efd654"],
        "SGenPr2" => ["nkl.afe49t0o", "ed341383b72ab47931537c4aefed43ac2a458a5b"],
        "SGenPr3" => ["nkl.9bc22j5d", "7f745f1c8661f92bfbdce5744546ee1c6ffa9edf"],
        "SGenPr4" => ["nkl.f87ara6z", "1eadd76152a3ff65560784168841453465cee3b5"],
        "SGenPr5" => ["nkl.9aadsffn", "df5972643d67d13ba369c60546367fec557503de"],
        "SLambert" => ["nkl.8b237bwt", "08bb46467d3e510dcc3d47b30da9860c755151b8"],
        "SermMadn" => ["nkl.ba45x88s", "86ae2a1d24c66519539c57931b5251d8fa65cab5"],
        "VidPierrePetit" => ["nkl.751a1469", "bc660c939c8f190deb1948a2762bbb372a362f7a"],
        "YvainKu" => ["nkl.dff6u8rs", "a070cb2394e3f5fc4a7e69a285f6a3922e2d3516"],
        "adgar" => ["nkl.cd9ery9h", "728a63d2dc6c37ce34685574f0a354ee4ecf564b"],
        "aliscans1" => ["nkl.a4ddq367", "e357d4ab125390a5654b18e9df910709c5cf2683"],
        "aliscans2" => ["nkl.6fe7kl29", "ae13cb974f43910936b87d7e8e61ee7edaffb1c4"],
        "amiamil" => ["nkl.d568g1d9", "306e1d86d43b1e014749ad5cb5a3f0a98581c12a"],
        "anglure" => ["nkl.bbfc1k15", "b88c41f3b57ce09940449fe952b3ad353e6722d1"],
        "archier" => ["nkl.0c5e8op2", "4b449347cf6cc0ce26b0dc2a8d5e064e7ab65b87"],
        "artois" => ["nkl.9a0c078s", "ee81ec7fbd4d46054812f5df58d848ae6c0c99eb"],
        "atrper" => ["nkl.2135yn36", "00c5728e729eefe9570455f8d42935e51a4142eb"],
        "aucassin" => ["nkl.a2a5koj5", "7f16da3b0bf6dd67a5dca0f636ef566dbf9a1f7f"],
        "baye1" => ["nkl.d3bd48f0", "9af65d46436eef89274fce6d800605cae0f661eb"],
        "baye2" => ["nkl.c6ae1426", "45989b2cd86152a8b532a4b63f1a6188636774ac"],
        "beauma1" => ["nkl.0394g32i", "eddba64e1fec49bdc8663a59e7c63a49c97e6383"],
        "becket" => ["nkl.cd5dio5e", "cd0e774276f80bfbc4c856b8570fbc731d14fe3c"],
        "belinc" => ["nkl.ec8byys0", "8566c0a2e1165a4a3b47d010fe0d9bace660df9c"],
        "beroul" => ["nkl.16beabfc", "1dc29f99f4c906f4080f12a56509925937637271"],
        "bestam" => ["nkl.e5fc9s6e", "f0a004343d321e43ec60445ac051ade456c02439"],
        "bestiaire" => ["nkl.953cu90o", "a108a9f68db4567552a547a7d90f6350b9baffa1"],
        "bibleberze" => ["nkl.11a0k77s", "2c484adc419c493000284f1f150c287f69795b1b"],
        "bodelnic" => ["nkl.91eeza91", "cd7dddf016220b08334b2864257281f52c9a02bd"],
        "brut2" => ["nkl.2f8f9g8w", "99769328ab2b6dbc4073589cd3b1a4ec518eec75"],
        "cambps" => ["nkl.2bfd2370", "da62b4d782f0ea80d46d68f5fbe09263c6219021"],
        "cdo_ballades" => ["nkl.dcb60bl8", "cfc321be8535c61164713f2c3f89819e15172ea4"],
        "cdo_complaintes" => ["nkl.c2868c3y", "4bd10d6e898769d8d9155dc855325951cbd59920"],
        "cdo_peche" => ["nkl.0e110prw", "f364a13b14353998fa8b7770239c045b93c297fe"],
        "cdo_retenue" => ["nkl.84b16zc5", "a88c3a6c40a564a7ce7c29e1c42baa63250584c1"],
        "cdo_rondeaux" => ["nkl.7c3a52x8", "56f1486ce96a26d22e1742ff3ada5ca2b311494b"],
        "cdo_songe" => ["nkl.a8178r8j", "cd7a96d56487f81672162389491d14ec0049b799"],
        "chartes_aube13" => ["nkl.9382r8ds", "387803280d82009ce75a4e0783cd57c0ba26d60a"],
        "chartes_hain13" => ["nkl.f7f963fz", "f40ffc4f2abac6f918330d2ac63b66401e437118"],
        "clari" => ["nkl.c47fw9b0", "0ae0d7a9ceb57408e190a1a4fac1be4bb7462744"],
        "cnn" => ["nkl.dc5eig8m", "9245fe725929d90ad679486a41e5510807844041"],
        "cobe" => ["nkl.fca5848n", "4fb7b5ab1fcda4a085c302b98ecc8160c0654ba4"],
        "commyn1" => ["nkl.f31fb17k", "4f8fb818db34b88bd1da29679cb685057b61b3f4"],
        "commyn2" => ["nkl.e0cbk77i", "df6c962abd6db212ab3ef826a1b1478b4e074bb6"],
        "commyn3" => ["nkl.abfaa9c1", "f6f8f374c359bc96e906c1ac11713699d0a7e62e"],
        "commyn4" => ["nkl.e1a31q5g", "d29f6f291b47cac7c5ef82d3f15474170f167123"],
        "commyn5" => ["nkl.56dfrgf2", "6b3b84e7060acfe166361c9eb915c06bea7ad2f6"],
        "commyn6" => ["nkl.2bffh5kx", "bd01171884b65636dcb51b467e0fe0a78143e7a5"],
        "commyn7" => ["nkl.b31bd3oj", "1600acda93c4113e7fa7548b368a701f333706a9"],
        "commyn8" => ["nkl.a10ct92c", "91d25a0a9dc7b40e58ec05588ef7f5a71758dcf9"],
        "comput" => ["nkl.fcdfas7p", "8763bc92aaab6e8e45a63fbbf4e147fec0bdcc10"],
        "conttyr_a" => ["nkl.1fa520sn", "f922f4233a74a400c085cbdc5e2256fa5f3d6493"],
        "coutpoit_a" => ["nkl.1d7di913", "664eacd8677e435e2583beba9b096a2a1a140ef5"],
        "daudin" => ["nkl.7e6327z2", "2e4c366352913c4b8466d3922fd9fb5c7c99cb73"],
        "desire" => ["nkl.f997i2cw", "d62e18ed9e46a699b63e38e16f3230a20ef7a990"],
        "dictier" => ["nkl.00008n3p", "36072d62a87c57ce6e6b605a95dfe9553e177b84"],
        "dizsages" => ["nkl.e2d7rwl6", "604f29d70e5c17069852213ee7ee9c1568ab9c96"],
        "dole" => ["nkl.d44d4o6f", "d1b4bf7a6d417fbacd68b5acfea5ed93684fa1fb"],
        "donait" => ["nkl.059a3pnh", "df97bbce7779156a612391f977823115ee7bb54f"],
        "doon" => ["nkl.ec2553q4", "ed35079fef2dbdfc693c360ff3548bd26c4440e2"],
        "edconfcambr" => ["nkl.0c18j959", "f359154bf4b9186faed0d634c732a3e4133d1c65"],
        "eneas1" => ["nkl.15041hh1", "1b64b3efb0973b431b501698bae1e33484d030fa"],
        "eneas2" => ["nkl.dbcc1dmo", "f80e849230536d7b9b949fdc088a5930943b2b57"],
        "eracle" => ["nkl.0269735z", "d5f03b5cd49168d2d77a00cf87d45eed9025b9ee"],
        "escoufle" => ["nkl.f638e070", "3f69bfff11fac14d70185ac8c6cba3589de1d4c6"],
        "espine" => ["nkl.80faksz3", "3fe5e5e044266431aa0195d0aed07aed1ca43e30"],
        "eulaliBfm" => ["nkl.d834xuuo", "b43da9dd2528946f3c6f773cd60ca77c06f7d722"],
        "fauvel" => ["nkl.af360929", "28c1828ab72796a818a0bec22ee254f746b6577d"],
        "floire_jl" => ["nkl.ffcf0e15", "4bfa7150bd44c3197d928712b6426d14899f5255"],
        "fouke" => ["nkl.19bbm590", "b5139e4597deccb3060e71574c6d65728b59cca7"],
        "fournival" => ["nkl.19d8kke3", "dea834abaf42c9c25be9025a6d12029ce1d9c663"],
        "froissart1" => ["nkl.35ech83h", "f362ff97b68c29a40f47c72402b3846153c999eb"],
        "galeran" => ["nkl.fc7c329a", "a3236e47501cbe542f26e0507e2279fb28c1ac2f"],
        "gcoin1" => ["nkl.540b76y4", "00e8daca5787d080cc1827fa8c2e4a4e67e1d6ad"],
        "gcoin2" => ["nkl.436fe0jq", "dd2e0432ed95e4d873bcaa75e5d0bd761d188fc2"],
        "gcoin3" => ["nkl.ddeax556", "b7756c66ba1c46dc61d39a940a7d1b54a72174fc"],
        "gcoin4" => ["nkl.cad77nu8", "686adc2dab8c2d5bc623565d6732e7ff2fdd5ebb"],
        "gerson_trinite" => ["nkl.ab1ew0z7", "083c9a17f2904cec34e6ee2bb68d47b9160ead96"],
        "gormont" => ["nkl.6a8d0n5f", "72062b36d6258a8b9b535a564a0be93f5f12e6ab"],
        "graelent" => ["nkl.1503sv9a", "fa4585b2461f79e63fa4f79c66eb8521c7a6b147"],
        "grchron1" => ["nkl.4865r68a", "553c4d0a985ecd31745b0c8166d4e211ba27f543"],
        "grchron9" => ["nkl.39bec375", "e350c7dc2607dffe24f125741f9b421a7982e423"],
        "grchron_j2c5" => ["nkl.3cc47izc", "0ec9a1f4ce257f22f1d78e5dc8964f335d06ea3c"],
        "griseld" => ["nkl.110ctj52", "6412732703c54bc62c176c03126677b6350e3466"],
        "guill1" => ["nkl.eda527iv", "97d0f169e279363ae1a57d29679d099492b0210c"],
        "guingamor" => ["nkl.e15d3n43", "d31e4e05086efd91cd5f9f8b197f24ec55c5ed4f"],
        "hlanc" => ["nkl.3764kli3", "e435381ea513136e01474fb96398ee78d3bf0bbb"],
        "jehan" => ["nkl.ec7bvmfy", "db8935c1aa05f891b01a97ab641c0ca6284e2138"],
        "jehpar" => ["nkl.4ec9qmgu", "3bf72853fa2b9dfaeaa88a42eb72a9de84bdf36f"],
        "joinville" => ["nkl.dc4c1s9m", "ba0c3ff433f0d3c560ac09ec8d70c9ceadca2416"],
        "jonas" => ["nkl.faeebcnf", "6eb81c68afa92fda247200502b1bf97b486b9dd1"],
        "jouvencel1" => ["nkl.b47cny05", "eefb613a4d983d2bef877a824895978fc7071509"],
        "jouvencel2" => ["nkl.29bdm1f6", "34d53780c795cf7f09b185a1f3eff85e0e65a086"],
        "lecheor" => ["nkl.add73700", "fed27c19d433e0748457013505f00b3402460ff9"],
        "leiswillelm" => ["nkl.76a1nvhk", "c283f3fe45c73291a7511ba7e65f6860ffeb7577"],
        "louis11_215" => ["nkl.7c680kt9", "afe17242b702a7699e83139fe6850f676770583f"],
        "louis11_223" => ["nkl.7428bkfv", "173578cc660c79aef4e1b28bba47ccab56e5cbe9"],
        "louis11_234" => ["nkl.b5db83g8", "7025752e8432da7473941c1b3665d81c833fb51a"],
        "louis11_248" => ["nkl.d5e4a0m1", "eac9d640ecba7990eae31ca678e9f4d398830457"],
        "magloire3" => ["nkl.11cfomx6", "7f0a03e3eaa7e1ffb6bc53fcc48c771eba521a86"],
        "maniere1396" => ["nkl.83044d4b", "8135b2f82da2c1d2d682c2249ac1ba7523a1def8"],
        "maniere1399" => ["nkl.bcb2o7tt", "6701d9bc388b7ff17d66fb7739652e957594ecc8"],
        "maniere1415" => ["nkl.7f23c940", "eab5430484f4df38551259be1bde42ea004b2fa7"],
        "melion" => ["nkl.2f683c5s", "ed192e853e4bfa73ce6ee83198fbb05159845723"],
        "melusine" => ["nkl.34af7q17", "e8938ee89225b6e20e4bac11f582d637480c5fce"],
        "menagier" => ["nkl.7015yg08", "8b453511d549c13b3647dc7f864dec012c05447c"],
        "menreims" => ["nkl.e4375465", "75c24af298dc6ee528ac72bc84ae716e7fbd0e9e"],
        "merlin_suite_litt" => ["nkl.ed99732g", "284ebf77abf18685e9d4f6475b00f1b91c95db1b"],
        "mestiersparis" => ["nkl.9fd48i6x", "2d4fd14d46957265faa56a3a77f0a97138705e19"],
        "mf" => ["nkl.24d97ixm", "bf271d1f1636b55892a04827eee60d56685603cd"],
        "mirsnicjuif" => ["nkl.422d4qq6", "5280c1a1931dffeb3b56ae3e0b8f45b436f9a957"],
        "molinet1_ch01-10" => ["nkl.9a81x8fq", "05b32373b434b15d35eb08e4a530697e62f1fdf7"],
        "monstre" => ["nkl.53880se8", "e9226126dfa86c1f5c88efe8c78e8078512a444c"],
        "moree" => ["nkl.7b11q6yo", "99ebda89335c86ea334cf2faf512e238b9305fd6"],
        "nabaret" => ["nkl.03afsboc", "a3d8560ca71e887d81beac20b6478400063bbb9b"],
        "narcisse_lai" => ["nkl.62ef72d7", "c774074f8068e72fd5d4dd06f7c835fdd78acd39"],
        "ombre" => ["nkl.8077jvn0", "ddabb4edf8086faf0aa8adf8c6b29f7bb86f02f9"],
        "orange" => ["nkl.cafd4j60", "485831d95f8fed12f154ed6c25b9ca8d2af6e410"],
        "oresme" => ["nkl.2f7f5g77", "9fb97a52a265960f9115fe3bc467db8dc20b6067"],
        "oxfps" => ["nkl.cec351oi", "95588b4a1c9ee44b2fb216905bde5ee6fa23570a"],
        "passauv" => ["nkl.c1602em8", "b4b3854adc6926b7f62f33a3d32b99b9c1f26504"],
        "passbonnes" => ["nkl.2c72p8d6", "adcca5bf8348b88d50cf347045bb210ac9b33c21"],
        "passion" => ["nkl.37a2q4iu", "9f0814880bfecc3f25fda6e50451c6533bc95a61"],
        "passpal" => ["nkl.3f0e8ioj", "0975470749eb3e91b210a15412e9e9e8e8de57aa"],
        "pathelin" => ["nkl.193a3o2j", "1107e2e1a402f1667ad62b03789e2d1fc441f304"],
        "phares" => ["nkl.91adot44", "b79ff0ee6555181f41bc6d5ffc668dc914511902"],
        "philomena" => ["nkl.63aad7m9", "46c605f8c7b336269a9d8799025aa8d21317861e"],
        "plaidsmortemer" => ["nkl.e4d2369t", "9a438b7987591728f02baf40324ea087f426429c"],
        "ponthus" => ["nkl.d9df2sq4", "d9be9635ce734facd8294fe6b0a3321cdccf72e5"],
        "prov" => ["nkl.afa206ms", "9b2071b97b3f310be3894c406cd6fd7e5d38f5e0"],
        "prunier" => ["nkl.af439t75", "8a6b820280128e37b7caf287994a8b81f5831bdd"],
        "pyrame" => ["nkl.1f02318k", "db3dbb71807417a3887c124f204caae320e151c2"],
        "qgraal_cm" => ["nkl.dfb27v81", "51b0ea60de6610ad02eb15c5a6ae9c9edbad6dd2"],
        "qlr" => ["nkl.3cf826l8", "955a7c8b5f1833dd538d6951fcd90c2a823b6eda"],
        "quadrilogue" => ["nkl.cedcus2w", "6ead79f95b3adc33ebd9147c79d49b339e69a58a"],
        "quenouilles1" => ["nkl.aa6b61y9", "953c1b129fba1852a0684e9bfecdf2c7e4046d3b"],
        "quenouilles2" => ["nkl.b71e8eus", "e3e0c89a273e49758aadcb3778ab508000fc157f"],
        "regcrim1" => ["nkl.6b388id9", "2723d3dc2f8a114809c2c9bc162ed0dee96999b5"],
        "regcrim2" => ["nkl.92630s0p", "cb4fee6b6995c920d66e5ab2a4dcb5b024247680"],
        "renart10" => ["nkl.ed664i29", "72420dcf372bcd5533064dedbfcaf00743191bb5"],
        "renart11" => ["nkl.0af1k30s", "ba39b968e4bcf7e58a6f596f153a13d3f2986276"],
        "ressource" => ["nkl.4c0539z6", "0c144096244b79a1219d3237df5cac105aa8dabb"],
        "roland" => ["nkl.289fbm08", "3883e7874e028abeab7ccf21b82700d5153c6b70"],
        "rosel" => ["nkl.42e06nx5", "f12da50d3b7d9989c34ab1635f0ea52467783816"],
        "rosem1" => ["nkl.ac79n6xq", "e611a08b629a1a74e575f3d10e605d34c8823608"],
        "rosem2" => ["nkl.4fbf96c2", "3b59c531f4c05b90f44f485dfa77583e137d795b"],
        "rosem3" => ["nkl.49fefla8", "8acaebc78deeb8ef61f4522c9f5cccf462cabe51"],
        "saintre" => ["nkl.bdc8t16b", "50320ba22a7cf76c3dad9596ddad44a12e5636c7"],
        "sarrasin" => ["nkl.9c5d327b", "517fa4fb381d501f017d9a539991403efa199333"],
        "slethgier" => ["nkl.dbdb12yj", "f605b4a9f462515ac6672adb0373b2c344bd1816"],
        "strasbBfm" => ["nkl.f57b23q4", "e0536f7f8410fde651354d1a840ff141bc067be2"],
        "tdechamp" => ["nkl.dc8984n7", "ed01d4eb4012e20b95fe27ef23c4cef366a76259"],
        "thebes1" => ["nkl.f30ao7o6", "089a010b19d09e5d536d1bd29fd74a5d633b482e"],
        "thebes2" => ["nkl.7dfa18ky", "4b6edd502671e8dbe40aa960a20ed076b906f063"],
        "theologie" => ["nkl.74d66vu0", "19ded314e9747231258686fee319dfea4fc2471d"],
        "thomas" => ["nkl.9c0aglfv", "dec00a4c39aed5bdf608a75f8458400e6d659756"],
        "tringant" => ["nkl.ceacjov7", "a27ebc43c5341ebf7a2e40331ad29fccf9f2aad7"],
        "trispr" => ["nkl.2913p8ez", "294a9eb7fa535734d1f83a64184159e65fbf1c14"],
        "trot" => ["nkl.9bcc76f7", "f768794cd1b489ae35072d555c73ba777a8aa739"],
        "tydorel" => ["nkl.6ae5qr5c", "3002138dbe03810288eee037c003237999a1f521"],
        "tyolet" => ["nkl.648457te", "1174640e848bb39a8b57e57a96ff0e920f6d1938"],
        "ursins" => ["nkl.d4029n9w", "9f78c9f07b785258b84929da1893d6ae22abc518"],
        "vergy" => ["nkl.0dbd4j6v", "47d615d6d42173113de2337f2761ff4cfc97ecf6"],
        "villehardouin1" => ["nkl.bfb79265", "6fe67c4d27cca666e01aaa7a24a68f72ab020980"],
        "villehardouin2" => ["nkl.2f99gszy", "c62f96a05ccaf7ad10670207d65b7fe7519d7684"],
        "villon" => ["nkl.0032v4s0", "5ab141157130f6089c02d98aee30535b861b6931"]
      }.freeze
      private_constant :INVENTORY
    end
  end
end
