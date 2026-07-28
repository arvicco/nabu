# frozen_string_literal: true

require "digest"

require_relative "mvp_tei_parser"

module Nabu
  module Adapters
    # The Mahāvyutpatti adapter (P48-4): the early-9th-century imperial
    # Sanskrit–Tibetan glossary (bye brag rtog byed, ~9,400 numbered
    # entries; Chinese equivalents added later) in the DILA / Dharma Drum
    # Buddhist College TEI P5 digital edition — the Tibetan shelf's
    # crosswalk prize. Same content_kind :dictionary routing, same
    # DictionaryDocument/Entry model; dictionary slug mvp, language "san":
    # the glossary's own organization is Sanskrit-headed (every entry's
    # <form> is an IAST + Devanāgarī orth pair), so the shelf sits beside
    # MW and `define bodhisattvaḥ` aggregates both — MW's English beside
    # MVP's Tibetan and Chinese equivalents. Mvy. numbers are the standard
    # scholarly citation (Mvy. 625 = bodhisattvaḥ), so entry ids ARE the
    # upstream keys and urn:nabu:dict:mvp:625 is a citable address.
    #
    # SEAM (P48-6, deliberately not here): the Tibetan and Chinese
    # equivalents land in gloss/body lanes only — Tibetan-side lookup and
    # structured crosswalk edges into CBETA/GRETIL/SARIT/DCS are the
    # alignment packet's decision, not this registration's.
    #
    # == Upstream (verified 2026-07-28)
    #
    # https://glossaries.dila.edu.tw/glossaries/MVP — "This version
    # contains Sanskrit, Tibetan and Chinese." Bulk download
    # mahavyutpatti.dila.tei.p5.xml.zip [602.50 KiB, 2017-03-20], one XML
    # member (6,788,944 B, 9,379 entries / 308 divs censused) plus
    # __MACOSX junk. Upstream file is frozen (2017) → the fetch carries a
    # hard sha256 pin, the baxter-sagart posture; a drift is an owner
    # re-pin decision.
    #
    # == License (the honest-license doctrine)
    #
    # The glossary page states, verbatim: "We believe this text is in the
    # public domain." A PD-BELIEF assertion by the digitizer on a
    # 9th-century text → license_class "open", the phrasing carried
    # verbatim in the manifest; credit the DILA Glossaries Team (the page
    # asks for contact, not attribution — credited as good practice).
    class Mvp < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "mvp",
        name: "Mahāvyutpatti — Sanskrit–Tibetan–Chinese glossary (DILA TEI edition)",
        license: "Public domain — upstream belief statement, verbatim (glossaries.dila.edu.tw/glossaries/MVP): " \
                 "\"We believe this text is in the public domain.\"",
        license_class: "open",
        upstream_url: "https://glossaries.dila.edu.tw/data/mahavyutpatti.dila.tei.p5.xml.zip",
        parser_family: "mvp-tei",
        credit: "Glossaries Team, Dharma Drum Buddhist College (DILA), glossaries.dila.edu.tw"
      )

      ZIP_FILENAME = "mahavyutpatti.dila.tei.p5.xml.zip"
      XML_FILENAME = "mahavyutpatti.dila.tei.p5.xml"
      DICTIONARY_SLUG = "mvp"
      LANGUAGE = "san"
      TITLE = "Mahāvyutpatti (DILA TEI P5 edition)"

      # sha256 of the upstream zip, pinned from the 2026-07-28 download
      # (upstream dated 2017-03-20 — effectively frozen).
      ZIP_SHA256 = "571e35e4d8d109a582512b81d9a529e0366690e4446dc61079f129163130b773"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs the zip itself: reachability + Last-Modified drift
      # vs the .file-fetch.json pin. metadata_url nil — the PD-belief
      # statement lives on the glossary HTML page, not a probe-shaped
      # endpoint; it is re-read at any real refetch.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: ZIP_FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +zip_sha256+ exists for the WebMock'd fetch tests — real syncs keep
      # the frozen pin.
      def initialize(zip_sha256: ZIP_SHA256)
        super()
        @zip_sha256 = zip_sha256
      end

      # One DocumentRef for the one dictionary file, under ONE stable id
      # regardless of shape: a plain XML (fixtures; hand-unzipped trees)
      # wins over the zip (the real post-fetch canonical), whose ref
      # carries the member to stream. A workdir with neither yields nothing
      # (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ref = plain_ref(workdir) || zip_ref(workdir)
        yield ref if ref
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        MvpTeiParser.new.entries(xml_source(document_ref), path: document_ref.path)
                    .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "mvp: #{document_ref.id}: #{e.message}"
      end

      # Download the zip via FileFetch with the phases run separately so the
      # sha pin verifies BEFORE the tree mutates (the baxter-sagart
      # choreography). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(
          url: manifest.upstream_url, dir: workdir, filename: ZIP_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "mvp fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.sha == @zip_sha256

        raise Nabu::FetchError,
              "mvp: #{ZIP_FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned #{@zip_sha256} " \
              "(upstream dated 2017-03-20); review upstream and re-pin (owner decision)"
      end

      def plain_ref(workdir)
        path = Dir.glob(File.join(workdir, "**", XML_FILENAME)).min or return nil

        document_ref(path, member: nil)
      end

      def zip_ref(workdir)
        path = Dir.glob(File.join(workdir, "**", ZIP_FILENAME)).min or return nil

        document_ref(path, member: XML_FILENAME)
      end

      def document_ref(path, member:)
        metadata = { "dictionary" => DICTIONARY_SLUG }
        metadata["member"] = member if member
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{XML_FILENAME}",
          path: File.expand_path(path), metadata: metadata
        )
      end

      # The TEI source: straight off the plain file, or streamed out of the
      # zip member (unzip -p via Nabu::Shell — no gem, the house rule; the
      # __MACOSX junk member is never named).
      def xml_source(document_ref)
        member = document_ref.metadata["member"]
        return File.read(document_ref.path, encoding: Encoding::UTF_8) if member.nil?

        Nabu::Shell.run("unzip", "-p", document_ref.path, member)
                   .force_encoding(Encoding::UTF_8)
      rescue Nabu::Shell::Error => e
        raise Nabu::ParseError, "mvp: cannot read #{member} from #{document_ref.path}: #{e.message}"
      end
    end
  end
end
