# frozen_string_literal: true

require_relative "cora_date_lane"
require_relative "cora_tei_parser"
require_relative "cora_xml_parser"

module Nabu
  module Adapters
    # The ReM adapter (P40-5): the Reference Corpus of Middle High German
    # (1050–1350) — Referenzkorpus Mittelhochdeutsch v2.1 (Roussel, Klein,
    # Dipper, Wegera, Wich-Reif 2024; ISLRN 937-948-254-174-0), ~400 texts /
    # ~2M word forms of manually annotated MHG, the gold flagship of the
    # High-German-before-print stretch of the germanic axis. First registrant
    # of the cora-tei family (the CorA-derived DDD TEI dialect); ReN (Middle
    # Low German) is the second (P46-5, its own dialect subclass); ReA (OHG +
    # Old Saxon) joins when its license reply lands (asked by email 2026-07-22).
    #
    # == Identity (FROZEN minting)
    #
    # One document per upstream text file tei/M<id>.xml: urn =
    # urn:nabu:rem:<textid downcased> (urn:nabu:rem:m058, urn:nabu:rem:m218b
    # — upstream's own M-ids, also the fileDesc xml:id). Passage = one
    # MANUSCRIPT LINE — the corpus's primary layout unit (encodingDesc:
    # "Primary line breaks: Handschrift"; <lb ed="1"/> under <pb ed="1"/>) —
    # cited urn:nabu:rem:<textid>:<page>.<line> (…:m058:100v.5, the folio +
    # line a manuscript is actually cited by). Two-column codices (<cb
    # ed="1">) restart line numbers per column, so the column joins the
    # folio (…:m242:5ra.1 — P40-r1; the 46 first-sync quarantines were all
    # duplicate folio.line refs from this shape); residual collisions take
    # the house :b2 positional disambiguator. Minting is frozen once used —
    # column-less documents keep byte-identical refs, and no quarantined
    # document had ever loaded.
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
    # the CorA-XML sibling zip only): without it token records are honestly
    # norm+lemma.
    #
    # == pos/msd (the CorA-XML sibling zip)
    #
    # ReM-v2.1_coraxml.zip is fetched as a second sha-pinned arm into the
    # declared coraxml/ materialization (coraxml/cora-xml/M<id>.xml — the
    # zip's top dir strips). Its tok_anno ids ARE the TEI <w>/<pc> xml:ids
    # (censused 2026-10-01 over all 406 texts: identical id sequences,
    # 2,579,276 of 2,579,276 tokens), so the join is exact: each TEI token
    # record gains "pos" (CorA <pos @tag>, on every token) and "msd" (CorA
    # <infl @tag> — the morphological feature string, keyed "msd" like the
    # ReN sibling's TEI lane), verbatim; CorA's "--" null never rides. A
    # TEI token the sibling cannot answer is counted in metadata
    # "coraxml_unmatched_tokens" (loud census, never a quarantine). The
    # other CorA token lanes (pos_gen, lemma_gen, lemma_idmwb, inflClass…)
    # are not read; the element header feeds the dating lane (below). A
    # tree without the sibling
    # (every canonical tree fetched before the arm existed) parses exactly
    # as before — test-pinned.
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
    # The DATING lane comes from the CorA-XML sibling's ELEMENT header
    # instead (censused 2026-10-01 over all 406): <time> — upstream's
    # century-half grid, comma-spelled ("13,1", "12,2-13,1", bare-century
    # "12") — is filled on 396; <date> on 225, mostly prose ("um 1140/50
    # (?)", century claims "11"/"12,M"). Per document whose sibling
    # exists: cora_header = the element header verbatim (nulls dropped),
    # and date = the MetadataDates :structured envelope (CoraDateLane, the
    # ReF mold): a clean date ("1172", "1342-43") sets the bounds, anything
    # else falls back to the grid with the raw naming both claims, neither
    # clean → raw only. The TEI orig_place scriptorium lane is untouched
    # (PLACE_KEYS). No sibling → no date key (today's parse, test-pinned).
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
    # TWO immutable Zenodo artifacts (record 13982324): ReM-v2.1_tei.zip
    # (27,899,230 B, the text) and ReM-v2.1_coraxml.zip (110,668,767 B,
    # pos/msd) via ZipFetch with the phases hand-driven so BOTH hard
    # sha256 pins are checked BETWEEN download and any tree mutation (the
    # openiti two-arm choreography over the iecor mold). Canonical = the
    # extracted trees (README + tei/M*.xml, coraxml/ in the text arm's
    # keep-list; the CorA tree under coraxml/ with its own
    # .zip-fetch.json state). A future v2.2 is a new Zenodo version: the
    # owner re-pins URLs + shas and fires the re-sync.
    # sync_policy: manual, enabled: false until the owner-fired first sync.
    class Rem < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/13982324"
      ZIP_URL = "https://zenodo.org/api/records/13982324/files/ReM-v2.1_tei.zip/content"

      # sha256 of the 27,899,230-byte ReM-v2.1_tei.zip, pinned from the
      # 2026-07-22 fixture snapshot download (test/fixtures/rem/README.md).
      # Zenodo files are immutable: a mismatch is corruption or an
      # unannounced re-release, never a routine update.
      RELEASE_SHA256 = "a04e8ac60c87b24eadd7ff3155040c09fccbd359a229fec3fdebae53295351d1"

      # The CorA-XML sibling (pos/msd): 110,668,767 B, sha256 pinned from
      # the 2026-10-01 fixture snapshot download (Zenodo's published md5
      # 1bb74c17a10c665fde98504bb8c858aa cross-checked). Unpacks into the
      # declared coraxml/ subtree.
      CORAXML_URL = "https://zenodo.org/api/records/13982324/files/ReM-v2.1_coraxml.zip/content"
      CORAXML_SHA256 = "bfe5179db48c1d14d65c088939d7b09e266e1e60af0240090c5a1d779d01b291"
      CORA_DIRNAME = "coraxml"

      # CorA tok_anno children merged into the TEI token records (CorA
      # element → record key).
      CORA_TAGS = { "pos" => "pos", "infl" => "msd" }.freeze

      # CorA's null placeholder ("--"), never a value.
      CORA_NULL = /\A-+\z/

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
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: "ReM-v2.1_tei.zip", zip_url: ZIP_URL, metadata_url: nil,
            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: "ReM-v2.1_coraxml.zip", zip_url: CORAXML_URL, metadata_url: nil,
            state_subdir: CORA_DIRNAME, state_file: Nabu::ZipFetch::STATE_FILE
          )
        ]
      end

      # The CorA-XML sibling's unpack lands beside upstream's TEI tree
      # (Q59-a): declared so the canonical identity stays strong.
      def self.materialized_paths = [CORA_DIRNAME]

      # +pin+ / +cora_pin+ override the release shas (tests; a future owner
      # re-pin drill).
      def initialize(pin: RELEASE_SHA256, cora_pin: CORAXML_SHA256)
        super()
        @pin = pin
        @cora_pin = cora_pin
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
        tags = cora_tags(document_ref.metadata["cora_path"])
        metadata = document_metadata(header, body, document_ref)
                   .merge(cora_dating(document_ref.metadata["cora_path"]))
        unmatched = tags && body.lines.sum { |line| line.tokens.count { |t| !tags.key?(t["id"]) } }
        metadata["coraxml_unmatched_tokens"] = unmatched if unmatched&.positive?
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: header.title,
          canonical_path: document_ref.path, metadata: metadata
        )
        append_lines(document, body, document_ref, tags: tags)
        raise ParseError, "#{document_ref.path}: no manuscript lines in <body>" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify BOTH hard sha pins + unpack, phases hand-driven
      # so every pin check runs BETWEEN download and any tree mutation
      # (prepare both → pins → mass-deletion breaker over both → complete
      # both); a 304 replays the stored pin and touches nothing. No
      # network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        tei = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir, keep: [CORA_DIRNAME],
                                 attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        cora = Nabu::ZipFetch.new(url: CORAXML_URL, dir: File.join(workdir, CORA_DIRNAME),
                                  attic_dir: File.join(workdir, ATTIC_DIRNAME, CORA_DIRNAME),
                                  progress: progress)
        begin
          tei.prepare!
          verify_pin!(tei)
          cora.prepare!
          verify_cora_pin!(cora)
          guard_mass_deletion!(workdir, tei.doomed_paths + cora.doomed_paths, force: force)
          tei.complete!
          cora.complete!
        ensure
          tei.cleanup!
          cora.cleanup!
        end
        Nabu::FetchReport.new(sha: tei.sha, fetched_at: Time.now, notes: fetch_notes(tei, cora))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "rem fetch failed into #{workdir}: #{e.message}"
      end

      # P109-4 (№R-70): the ReM classification vocabulary the genre facet
      # labels (P Prosa / V Vers / PV both / U Urkunde); an unlisted
      # code rides value-only, never guessed.
      GENRE_LABELS = { "P" => "Prosa", "V" => "Vers", "PV" => "Prosa und Vers",
                       "U" => "Urkunde" }.freeze

      private

      def parser
        CoraTeiParser.new
      end

      # The coraxml/ sibling tree carries M*.xml names too — it is never
      # a text (the sibling joins by basename instead).
      def document_refs(workdir)
        reader = parser
        cora_root = File.join(File.expand_path(workdir), CORA_DIRNAME, "")
        Dir.glob(File.join(workdir, "**", "M*.xml")).filter_map do |path|
          basename = File.basename(path)
          next unless FILE_PATTERN.match?(basename)
          next if File.expand_path(path).start_with?(cora_root)

          header = reader.header(path)
          sibling = File.join(cora_root, "cora-xml", basename)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:rem:#{basename.delete_suffix('.xml').downcase}",
            path: File.expand_path(path),
            metadata: { "title" => header.title, "language" => LANGUAGE,
                        "cora_path" => (sibling if File.file?(sibling)) }.compact
          )
        end.sort_by(&:id)
      end

      # The sibling's element header + its date envelope (class note); {}
      # when no sibling exists, so the metadata is byte-identical to before.
      def cora_dating(cora_path)
        return {} if cora_path.nil?

        fields = CoraXmlParser.new.element_header(cora_path).transform_values { |v| Normalize.nfc(v) }
        { "cora_header" => fields,
          "date" => CoraDateLane.envelope(fields["date"], fields["time"], separator: ",") }.compact
      end

      # tok_anno id → { "pos" => …, "msd" => … } (nulls dropped, NFC), or
      # nil when the document has no sibling (today's state).
      def cora_tags(cora_path)
        return nil if cora_path.nil?

        CoraXmlParser.new.anno_tags(cora_path, names: CORA_TAGS.keys).transform_values do |found|
          found.each_with_object({}) do |(element, tag), record|
            record[CORA_TAGS.fetch(element)] = Normalize.nfc(tag) unless tag.nil? || tag.match?(CORA_NULL)
          end
        end
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
          "unrecognized_elements" => (body.unrecognized unless body.unrecognized.empty?),
          "facets" => genre_facet(header.genre)
        }.compact
      end

      def genre_facet(genre)
        return nil if genre.nil? || genre.empty?

        facet = { "value" => genre }
        facet["raw"] = GENRE_LABELS[genre] if GENRE_LABELS.key?(genre)
        { "genre" => facet }
      end

      # Ref = <folio><column>.<line> (m242:5ra.1 — two-column codices restart
      # line numbers per column, so the cb @n joins the folio; column-less
      # files keep their byte-identical <folio>.<line> refs). Any REMAINING
      # collision (censused: M345-type entry-wise restarts with no upstream
      # container element) takes the house :b2 positional disambiguator
      # (the DdbdpParser/ORACC precedent) — never quarantine, never merge.
      # P40-r1: the 46 first-sync quarantines were all one failure class,
      # duplicate folio.line refs; none of those documents ever loaded, so
      # no frozen minting is disturbed.
      def append_lines(document, body, document_ref, tags: nil)
        seen = Hash.new(0)
        body.lines.each do |line|
          tokens = tags ? line.tokens.map { |t| t.merge(tags.fetch(t["id"], {})) } : line.tokens
          annotations = { "tokens" => tokens }
          annotations["edition_lines"] = line.edition_lines unless line.edition_lines.empty?
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{line_ref(line, seen)}",
            language: LANGUAGE, text: Normalize.nfc(line.text),
            annotations: annotations, sequence: document.size
          )
        end
      end

      def line_ref(line, seen)
        folio = [line.page, line.column].compact.join
        ref = [(folio unless folio.empty?), line.n].compact.join(".")
        count = (seen[ref] += 1)
        count == 1 ? ref : "#{ref}:b#{count}"
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "rem: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{ZIP_URL} and re-pin RELEASE_SHA256 only after " \
              "reading the record"
      end

      def verify_cora_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @cora_pin

        raise Nabu::FetchError,
              "rem: downloaded ReM-v2.1_coraxml.zip misses its sha256 pin (expected #{@cora_pin}, " \
              "got #{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{CORAXML_URL} and re-pin CORAXML_SHA256 only " \
              "after reading the record"
      end

      def fetch_notes(tei, cora)
        [
          tei.not_modified? ? "not modified (304)" : "zenodo v2.1 sha pin verified",
          cora.not_modified? ? "coraxml not modified (304)" : "coraxml sha pin verified",
          attic_notes(tei.atticked + cora.atticked)
        ].compact.join("; ")
      end
    end
  end
end
