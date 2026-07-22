# frozen_string_literal: true

require_relative "cora_tei_parser"

module Nabu
  module Adapters
    # The ReM adapter (P40-5): the Reference Corpus of Middle High German
    # (1050–1350) — Referenzkorpus Mittelhochdeutsch v2.1 (Roussel, Klein,
    # Dipper, Wegera, Wich-Reif 2024; ISLRN 937-948-254-174-0), ~400 texts /
    # ~2M word forms of manually annotated MHG, the gold flagship of the
    # High-German-before-print stretch of the germanic axis. First registrant
    # of the cora-tei family (the CorA-derived DDD TEI dialect); ReA (OHG +
    # Old Saxon) and ReN (Middle Low German) ride the same family when their
    # license replies land (backlog №40-1/№40-2).
    #
    # == Identity (FROZEN minting)
    #
    # One document per upstream text file tei/M<id>.xml: urn =
    # urn:nabu:rem:<textid downcased> (urn:nabu:rem:m058, urn:nabu:rem:m218b
    # — upstream's own M-ids, also the fileDesc xml:id). Passage = one
    # MANUSCRIPT LINE — the corpus's primary layout unit (encodingDesc:
    # "Primary line breaks: Handschrift"; <lb ed="1"/> under <pb ed="1"/>) —
    # cited urn:nabu:rem:<textid>:<page>.<line> (…:m058:100v.5, the folio +
    # line a manuscript is actually cited by). Minting is frozen once used.
    #
    # == The two token layers (owner doctrine: canonical means canonical)
    #
    # Passage text = the DIPLOMATIC layer (the witness — long ſ, combining
    # marks, scribal gaps), byte-honest NFC; the normalized layer (@norm) and
    # the gold lemma ride annotations["tokens"] per token, so the indexer's
    # passage_lemmas lights `lemma` search up for gmh while the stored text
    # stays the manuscript's. The imp-tei orig/reg precedent, not the ogham
    # sibling-document one: ReM's normalized layer is token-aligned attribute
    # data with no layout of its own, so it is annotation, not a parallel
    # rendering. The TEI export carries NO pos/msd (censused — those live in
    # the CorA-XML sibling zips only): token records are honestly norm+lemma.
    #
    # == Dating/localization (the timeline verdict)
    #
    # ReM headers carry origDate/origPlace slots and a langUsage dialect
    # chain (mhd → oberdeutsch → ostoberdeutsch → bairisch). Census verdict:
    # BOTH fixture texts carry only the "--"/"-" placeholders in origDate/
    # origPlace — no extractor is built on an uninspected format (the
    # isicily discipline; don't invent upstream formats). The dialect chain
    # and any non-placeholder origDate/origPlace ride document metadata
    # verbatim, so the timeline extractor can be built from real synced data
    # the day the filled format is censused.
    #
    # == License
    #
    # CC BY-SA 4.0, stated identically in the zip README, each file's
    # <licence>, and the Zenodo record (cc-by-sa-4.0). license_class
    # "attribution", MCP-safe. Parse RE-VERIFIES the in-file licence per
    # document and quarantines drift (the sarit/syriac-corpus discipline).
    #
    # == fetch / sync policy
    #
    # ONE immutable Zenodo artifact (record 13982324, ReM-v2.1_tei.zip,
    # 27,899,230 B) via ZipFetch with the phases hand-driven so the hard
    # sha256 pin is checked BETWEEN download and any tree mutation (the
    # iecor mold). Canonical = the extracted tree (README + tei/M*.xml) —
    # how every ZipFetch source stores canonical. A future v2.2 is a new
    # Zenodo version: the owner re-pins URL + sha and fires the re-sync.
    # sync_policy: manual, enabled: false until the owner-fired first sync.
    class Rem < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/13982324"
      ZIP_URL = "https://zenodo.org/api/records/13982324/files/ReM-v2.1_tei.zip/content"

      # sha256 of the 27,899,230-byte ReM-v2.1_tei.zip, pinned from the
      # 2026-07-22 fixture snapshot download (test/fixtures/rem/README.md).
      # Zenodo files are immutable: a mismatch is corruption or an
      # unannounced re-release, never a routine update.
      RELEASE_SHA256 = "a04e8ac60c87b24eadd7ff3155040c09fccbd359a229fec3fdebae53295351d1"

      MANIFEST = Nabu::SourceManifest.new(
        id: "rem",
        name: "ReM — Referenzkorpus Mittelhochdeutsch (1050–1350), v2.1",
        license: "CC BY-SA 4.0 (per-file <licence> verbatim: \"Creative Commons Attribution-ShareAlike " \
                 "4.0 International (CC-BY-SA)\"; zip README and Zenodo record 13982324 agree; cite " \
                 "Roussel, Klein, Dipper, Wegera, Wich-Reif 2024, ISLRN 937-948-254-174-0)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "cora-tei"
      )

      LANGUAGE = "gmh"

      # The licence line every ReM file must carry (drift quarantines).
      LICENCE_PIN = "Creative Commons Attribution-ShareAlike 4.0 International"

      # Upstream text files: tei/M058.xml, tei/M218B.xml, … (the zip README
      # is the only non-M member).
      FILE_PATTERN = /\AM\w+\.xml\z/

      def self.manifest
        MANIFEST
      end

      # HEAD the Zenodo artifact: reachability + Last-Modified drift against
      # the .zip-fetch.json pin. metadata_url nil — the license travels
      # in-file and on the record page.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "ReM-v2.1_tei.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per M*.xml text file, sorted by urn; a workdir
      # without the files yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Header (licence + language verified) → document; one passage per
      # manuscript line, diplomatic text, tokens + edition lineation riding
      # annotations, classification lanes riding document metadata.
      def parse(document_ref)
        header = verified_header(document_ref)
        body = parser.body(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: header.title,
          canonical_path: document_ref.path, metadata: document_metadata(header, body, document_ref)
        )
        append_lines(document, body, document_ref)
        raise ParseError, "#{document_ref.path}: no manuscript lines in <body>" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify the hard sha pin + unpack, phases hand-driven so
      # the pin check runs BETWEEN download and any tree mutation (prepare →
      # pin → mass-deletion breaker → complete); a 304 replays the stored
      # pin and touches nothing. No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "rem fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        CoraTeiParser.new
      end

      def document_refs(workdir)
        reader = parser
        Dir.glob(File.join(workdir, "**", "M*.xml")).filter_map do |path|
          basename = File.basename(path)
          next unless FILE_PATTERN.match?(basename)

          header = reader.header(path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:rem:#{basename.delete_suffix('.xml').downcase}",
            path: File.expand_path(path),
            metadata: { "title" => header.title, "language" => LANGUAGE }.compact
          )
        end.sort_by(&:id)
      end

      # The header, with the per-file licence and language idents held
      # against the corpus pins — drift quarantines the document.
      def verified_header(document_ref)
        header = parser.header(document_ref.path)
        unless header.licence&.include?(LICENCE_PIN)
          raise ParseError, "#{document_ref.path}: <licence> drifted from the CC BY-SA 4.0 pin " \
                            "(got #{header.licence.inspect}); re-verify upstream before ingesting"
        end
        unless header.language_idents == [LANGUAGE]
          raise ParseError, "#{document_ref.path}: langUsage idents #{header.language_idents.inspect} " \
                            "!= [\"#{LANGUAGE}\"] — a non-MHG text does not belong to this source"
        end

        header
      end

      # The classification lanes, placeholders already dropped by the
      # parser, plus the loudness census when it is non-empty.
      def document_metadata(header, body, document_ref)
        {
          "text_id" => header.text_id || File.basename(document_ref.path, ".xml"),
          "dialects" => (header.dialects unless header.dialects.empty?),
          "genre" => header.genre, "topic" => header.topic, "text_type" => header.text_type,
          "repository" => header.repository, "ms_idno" => header.ms_idno,
          "orig_date" => header.orig_date, "orig_place" => header.orig_place,
          "derived_from" => header.derived_from, "token_count" => header.token_count,
          "unrecognized_elements" => (body.unrecognized unless body.unrecognized.empty?)
        }.compact
      end

      def append_lines(document, body, document_ref)
        body.lines.each do |line|
          annotations = { "tokens" => line.tokens }
          annotations["edition_lines"] = line.edition_lines unless line.edition_lines.empty?
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{[line.page, line.n].compact.join('.')}",
            language: LANGUAGE, text: Normalize.nfc(line.text),
            annotations: annotations, sequence: document.size
          )
        end
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "rem: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{ZIP_URL} and re-pin RELEASE_SHA256 only after " \
              "reading the record"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo v2.1 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
