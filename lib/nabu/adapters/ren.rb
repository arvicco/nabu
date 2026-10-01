# frozen_string_literal: true

require_relative "cora_xml_parser"
require_relative "ren_tei_parser"

module Nabu
  module Adapters
    # The ReN adapter (P46-5): the Reference Corpus of Middle Low German /
    # Low Rhenish (1200–1650) — Referenzkorpus Mittelniederdeutsch/
    # Niederrheinisch 1.1 (Peters, Nagel et al.; Hamburg/Münster), the
    # Hanseatic rung between the held ReM (Middle High German) and the
    # Norse/Old English shelves, and the SECOND cora-tei registrant. 161
    # annotated texts (1,485,963 tokens with gold pos+msd+lemma — the
    # measured <w pos> census equals the deposit's claimed 1.49M) plus 74
    # transcribed-only texts (838,400 tokens, id+form only): charters,
    # town statutes, chronicles, devotional prose, from manuscripts,
    # prints and inscriptions.
    #
    # == Identity (minting)
    #
    # One document per upstream text file <anno|trans>/<Sigle>.tei; the
    # filename IS the deposit's stable text sigle ("Hamb._Uk._1301-1350",
    # "Brs._Ält._DegB_Altst._I"). urn = urn:nabu:ren:<slug> where slug is
    # the rundata-style ASCII slugify of the sigle (NFKD → ASCII strip →
    # downcase → non-alnum runs to "-"): hamb-uk-1301-1350,
    # brs-alt-degb-altst-i. Censused: all 235 sigla slugify uniquely, and
    # anno/ and trans/ share no basename. Filenames carry umlauts, so the
    # sigle is NFC-normalized before slugging (macOS globs return NFD).
    # Passage = one MANUSCRIPT LINE cited <page><column>.<line> exactly
    # like ReM (…:1ra.01 — two-column pages restart line numbers per
    # column); the charter collections restart pb/lb per entry with no
    # container element (censused: 5,664 collisions in 65 files — the ReM
    # M345 shape), so residual collisions take the house :b2 positional
    # disambiguator. lb numbers are upstream's zero-padded labels ("01"),
    # kept verbatim.
    #
    # == Language (the gml decision, censused 2026-07-26)
    #
    # The whole source rides gml (Middle Low German). The TEI export
    # carries NO per-file language marker; the CorA-XML sibling's headers
    # census language: mittelniederdeutsch ×206, niederrheinisch ×28,
    # empty ×1. Low Rhenish (Niederrheinisch) is the corpus's own coupled
    # lane — upstream classes it as its own thing, NOT Middle Dutch, so no
    # dum split is invented; the 28 censused texts carry metadata
    # "upstream_language" => "niederrheinisch" (LOW_RHENISH_SLUGS below)
    # so nothing is silently mislabeled and a future re-classification has
    # the data.
    #
    # == Dating / localization (the CorA-XML sibling zip)
    #
    # The TEI carries no header, so dating (date_ReN, the century-half
    # time grid), place and the language-area classification live ONLY in
    # the deposit's CorAXML_1.1.zip — fetched as a second sha-pinned arm
    # into the declared coraxml/ materialization (ReN_anno_2021-01-06/ +
    # ReN_trans_2021-01-06/, one <Sigle>.xml per text — censused 1:1 with
    # the 235 TEI sigla). Per document whose sibling exists:
    #   cora_header — the free-text header's 43 censused keys (one fixed
    #     order on all 235 files), verbatim, "-"/"---"/empty nulls dropped
    #     (the aggressive-mining policy: every field rides);
    #   date — the MetadataDates :structured envelope (the ReF mold): a
    #     clean date_ReN ("1329", "1452-1500", "1464/65") rules; prose
    #     datings ("[um 1300]", "Mitte 15. Jh.") are never number-scraped
    #     and take upstream's own century-half grid (time "14/1",
    #     "15/1-15/2" — on all 235), the raw naming both claims;
    #   place — the header place verbatim (85 of 235 carry one); the
    #     explicit "unbekannt" (5) is the absence of a claim and mints none
    #     (it stays verbatim in cora_header);
    #   dialects — the coarse-to-fine language-type → language-area chain;
    #   facets — the genre code (P/V/U, ReM's vocabulary) as a labeled
    #     facet row (the ReM P109-4 genre facet).
    # The CorA token layer is NOT read: the TEI already carries the gold
    # pos/msd/lemma (the inverse of ReM's gap). A tree without the sibling
    # (every canonical tree fetched before the arm existed) parses exactly
    # as before — test-pinned. The CorA header's own language line is the
    # source of LOW_RHENISH_SLUGS below; the hardcoded list stays so the
    # marker never depends on the sibling being present.
    #
    # == License
    #
    # CC BY 4.0, stated on the deposit record itself (fdr.uni-hamburg.de
    # record 9195, DOI 10.25592/uhhfdm.9195, version 1.1, 2021-01-06) —
    # verified on the record 2026-07-25. There is NO in-file licence (no
    # teiHeader), so no per-file re-verification is possible; the record +
    # DOI are the license basis, cited in the manifest. license_class
    # "attribution".
    #
    # == fetch / sync policy
    #
    # TWO versioned-immutable deposit artifacts — tei_1.1.zip (21,829,154
    # B, the text) and CorAXML_1.1.zip (67,786,811 B, the dating headers)
    # — via ZipFetch with the phases hand-driven so BOTH hard sha256 pins
    # are checked BETWEEN download and any tree mutation (the openiti
    # two-arm choreography over the rem/iecor mold). The record URLs 302
    # to short-lived signed S3 URLs — ZipFetch's RedirectFollow handles
    # it — and each zip's single top dir strips: canonical = anno/ +
    # trans/ under the workdir (coraxml/ in the text arm's keep-list) and
    # the CorA tree under coraxml/ (its own .zip-fetch.json state). A
    # future 1.2 is a new record version: the owner re-pins URLs + shas
    # and fires the re-sync. sync_policy: manual, wired: false until the owner-fired
    # first sync.
    class Ren < Nabu::Adapter
      RECORD_URL = "https://www.fdr.uni-hamburg.de/record/9195"
      ZIP_URL = "https://www.fdr.uni-hamburg.de/record/9195/files/tei_1.1.zip?download=1"

      # sha256 of the 21,829,154-byte tei_1.1.zip, pinned from the
      # 2026-07-26 fixture snapshot download (test/fixtures/ren/README.md).
      # The 1.1 deposit is versioned-immutable: a mismatch is corruption or
      # an unannounced re-release, never a routine update.
      RELEASE_SHA256 = "b4cc9664268f760517b822c5d3965050ad15d31d712ba7907742c87808b7841e"

      # The CorA-XML sibling (dating/localization headers): 67,786,811 B,
      # sha256 pinned from the 2026-10-01 fixture snapshot download (md5
      # 2bd9fc1ba540b9048b9c9586ed5a6736 cross-checked against the deposit
      # bucket listing). Unpacks into the declared coraxml/ subtree.
      CORAXML_URL = "https://www.fdr.uni-hamburg.de/record/9195/files/CorAXML_1.1.zip?download=1"
      CORAXML_SHA256 = "118087efcf27a09d6268d95749f7dc87adbe18bcaa1d9186d5bcf3afe0c46049"
      CORA_DIRNAME = "coraxml"

      # The ReN CorA header's closed key set (censused 2026-10-01: all 235
      # files carry exactly these 43, in this one order). A header line
      # starting with anything else continues the previous value.
      CORA_HEADER_KEYS = %w[
        text_ReN abbr_ddd text-type reference reference_secondary edition
        literature library library-shelfmark online scribe_or_printer place
        extent extract columns style hands author drawer illustration date_ReN
        online_file external_source notes_manuscript notes_language corpus
        notes_transcription notes_annotation digitization_by collation_by
        pre_editing_by annotation_by proofreading_by topic topic_ReN genre time
        medium language-area base_for_transcription token language language-type
      ].freeze

      # The clean date_ReN parses (the ReF P81-1 grammar). Anything else —
      # "[um 1300]", "Mitte 15. Jh.", multi-claim prose — is never
      # number-scraped: it falls back to the century-half grid below.
      DATE_EXACT = /\A(\d{4})\z/
      # "1452-1500", "1464/65" — a 2-digit tail expands with the head's century.
      DATE_SPAN = %r{\A(\d{4})\s*[-–/]\s*(\d{2}|\d{4})\z}
      # Upstream's own century-half grid, on ALL 235 texts: "14/1" = 14th
      # c., 1st half → [1300, 1350]; "15/1-15/2" spans → [1400, 1500].
      TIME_GRID = %r{\A(\d{2})/([12])(?:-(\d{2})/([12]))?\z}

      # The explicit no-place value (5 headers) — the absence of a claim.
      UNKNOWN_PLACE = "unbekannt"

      # The header genre code's vocabulary — ReM's (Rem::GENRE_LABELS),
      # censused on ReN as P 111 / U 86 / V 38; an unlisted code rides
      # value-only, never guessed.
      GENRE_LABELS = { "P" => "Prosa", "V" => "Vers", "PV" => "Prosa und Vers",
                       "U" => "Urkunde" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ren",
        name: "ReN — Referenzkorpus Mittelniederdeutsch/Niederrheinisch (1200–1650), v1.1",
        license: "CC BY 4.0 (deposit record fdr.uni-hamburg.de/record/9195, DOI " \
                 "10.25592/uhhfdm.9195 — the record's own license field; no in-file licence " \
                 "exists. Cite: Referenzkorpus Mittelniederdeutsch/Niederrheinisch (1200–1650), " \
                 "Version 1.1, 2021)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "cora-tei"
      )

      LANGUAGE = "gml"

      # The 28 texts the CorA-XML sibling's headers class as
      # language:niederrheinisch (censused from CorAXML_1.1.zip,
      # 2026-07-26; the other 206 are mittelniederdeutsch, and one header —
      # Rostocker_Liederbuch — is empty, plainly Baltic MLG). They ride gml
      # with this honest marker — upstream couples the two lanes in one
      # corpus and does NOT class them as Middle Dutch, so no dum split is
      # invented. Slugs, not sigla: the marker is applied by document urn.
      LOW_RHENISH_SLUGS = %w[
        aiol buschm-mirakel-greifsw chr-wass-duisburg
        drie-sermones dub-uk-1301-1350 dub-uk-1351-1400
        dub-uk-1401-1450 dub-uk-1451-1500 emmerich-susternb
        g-v-d-schuren-chr kle-uk-1301-1350 kle-uk-1351-1400
        kle-uk-1401-1450 kle-uk-1451-1500 klev-1-rechtsb-1430
        kolner-bibel-ke-1478-79 manuale-actorum notg-prot-duisburg
        nr-moralb-bestiaire nr-moralb-dogma nr-moralb-spr
        str-duisburg str-kalkar theophilus-trier
        trier-floyris wes-uk-1351-1400 wes-uk-1401-1450
        wes-uk-1451-1500
      ].freeze

      def self.manifest
        MANIFEST
      end

      # HEAD the deposit artifact: reachability + Last-Modified drift
      # against the .zip-fetch.json pin. metadata_url nil — the license
      # lives on the record page (license_watch in the registry row).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: "tei_1.1.zip", zip_url: ZIP_URL, metadata_url: nil,
            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: "CorAXML_1.1.zip", zip_url: CORAXML_URL, metadata_url: nil,
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

      # One DocumentRef per anno/trans text file, sorted by urn; a workdir
      # without the files yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Body → document; one passage per manuscript line, diplomatic text,
      # tokens + entry notes riding annotations. No header exists to
      # verify (the dialect has none) — identity is the filename sigle.
      def parse(document_ref)
        body = parser.body(document_ref.path)
        sigle = sigle_for(document_ref.path)
        metadata = document_metadata(body, document_ref, sigle)
                   .merge(cora_metadata(document_ref.metadata["cora_path"]))
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title_for(sigle),
          canonical_path: document_ref.path, metadata: metadata
        )
        append_lines(document, body, document_ref)
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
        raise Nabu::FetchError, "ren fetch failed into #{workdir}: #{e.message}"
      end

      # The rundata-style ASCII slugify (Django slugify allow_unicode=false
      # semantics, underscores folding to hyphens): NFKD → ASCII strip →
      # downcase → non-alnum runs to "-". Censused: all 235 deposit sigla
      # slugify non-empty and unique.
      def self.slug_for(sigle)
        ascii = sigle.unicode_normalize(:nfkd)
                     .encode(Encoding::US_ASCII, invalid: :replace, undef: :replace, replace: "")
        slug = ascii.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
        raise ParseError, "sigle #{sigle.inspect} slugifies to nothing" if slug.empty?

        slug
      end

      private

      def parser
        RenTeiParser.new
      end

      def document_refs(workdir)
        siblings = cora_siblings(workdir)
        Dir.glob(File.join(workdir, "**", "{anno,trans}", "*.tei")).map do |path|
          sigle = sigle_for(path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:ren:#{self.class.slug_for(sigle)}",
            path: File.expand_path(path),
            metadata: { "title" => title_for(sigle), "language" => LANGUAGE,
                        "layer" => layer_for(path), "cora_path" => siblings[sigle] }.compact
          )
        end.sort_by(&:id)
      end

      # NFC sigle → absolute path of its CorA-XML sibling under coraxml/
      # (empty when the sibling zip was never fetched — today's state).
      def cora_siblings(workdir)
        Dir.glob(File.join(workdir, CORA_DIRNAME, "*", "*.xml")).to_h do |path|
          [sigle_for(path, ext: ".xml"), File.expand_path(path)]
        end
      end

      # The sibling header's lanes (class note); {} when no sibling exists,
      # so a sibling-less document's metadata is byte-identical to before.
      def cora_metadata(cora_path)
        return {} if cora_path.nil?

        fields = CoraXmlParser.new.header(cora_path, keys: CORA_HEADER_KEYS)
                              .fields.transform_values { |v| Normalize.nfc(v) }
        place = fields["place"]
        dialects = fields.values_at("language-type", "language-area").compact
        {
          "cora_header" => fields,
          "date" => date_envelope(fields["date_ReN"], fields["time"]),
          "place" => (place unless place.nil? || place == UNKNOWN_PLACE),
          "dialects" => (dialects unless dialects.empty?),
          "facets" => genre_facet(fields["genre"])
        }.compact
      end

      def genre_facet(genre)
        return nil if genre.nil?

        facet = { "value" => genre }
        facet["raw"] = GENRE_LABELS[genre] if GENRE_LABELS.key?(genre)
        { "genre" => facet }
      end

      # The MetadataDates :structured envelope (the Ref#date_envelope
      # mold): a clean date_ReN parse rules; prose datings take the
      # century-half grid (raw then names both claims); neither clean →
      # the raw string rides alone, minting nothing.
      def date_envelope(date, time)
        clean = parse_date_lane(date)
        bounds = clean || parse_time_grid(time)
        raw = [date, ("(time #{time})" if clean.nil? && time)].compact.join(" ")
        return nil if raw.empty?
        return { "raw" => raw } if bounds.nil?

        { "not_before" => bounds[0], "not_after" => bounds[1], "raw" => raw }
      end

      def parse_date_lane(date)
        text = date.to_s.strip
        if (match = DATE_EXACT.match(text))
          year = Integer(match[1], 10)
          [year, year]
        elsif (match = DATE_SPAN.match(text))
          from = Integer(match[1], 10)
          to = match[2].length == 2 ? Integer("#{match[1][0, 2]}#{match[2]}", 10) : Integer(match[2], 10)
          from <= to ? [from, to] : nil # a descending pair is not a clean claim
        end
      end

      def parse_time_grid(time)
        match = TIME_GRID.match(time.to_s.strip) or return nil

        first = half_bounds(match[1], match[2])
        last = match[3] ? half_bounds(match[3], match[4]) : first
        first[0] <= last[1] ? [first[0], last[1]] : nil
      end

      def half_bounds(century, half)
        start = ((Integer(century, 10) - 1) * 100) + ((Integer(half, 10) - 1) * 50)
        [start, start + 50]
      end

      # The filename minus .tei IS the deposit's text sigle; NFC because
      # macOS filesystems hand globs NFD names (the umlaut sigla).
      def sigle_for(path, ext: ".tei")
        Normalize.nfc(File.basename(path, ext))
      end

      # The human title: the sigle with its underscores read as spaces —
      # exactly the CorA-XML header's own name field ("Hamb. Uk.
      # 1301-1350"; censused).
      def title_for(sigle)
        sigle.tr("_", " ")
      end

      def layer_for(path)
        File.basename(File.dirname(path)) == "anno" ? "annotated" : "transcribed"
      end

      # Sigle + layer + the loudness censuses; marginal-note counts (a
      # RECOGNIZED apparatus lane the parser swallows by design) are
      # reported apart from truly unrecognized elements.
      def document_metadata(body, document_ref, sigle)
        slug = document_ref.id.split(":").last
        marginal, unrecognized = body.unrecognized.partition { |name, _| name.start_with?("note[") }
        {
          "sigle" => sigle,
          "layer" => layer_for(document_ref.path),
          "upstream_language" => (LOW_RHENISH_SLUGS.include?(slug) ? "niederrheinisch" : nil),
          "marginal_notes" => (marginal.to_h unless marginal.empty?),
          "unrecognized_elements" => (unrecognized.to_h unless unrecognized.empty?)
        }.compact
      end

      # Ref = <page><column>.<line> (the ReM rule verbatim): two-column
      # pages restart line numbers per column so the cb @n joins the page;
      # the charter collections restart pb/lb per entry with NO container
      # element, so remaining collisions take the house :b2 positional
      # disambiguator — never quarantine, never merge.
      def append_lines(document, body, document_ref)
        seen = Hash.new(0)
        body.lines.each do |line|
          annotations = { "tokens" => line.tokens }
          annotations["entry_notes"] = line.notes unless line.notes.empty?
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
              "ren: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — the 1.1 deposit is versioned-immutable, so this is corruption " \
              "or an unannounced re-release; verify #{ZIP_URL} and re-pin RELEASE_SHA256 only " \
              "after reading the record"
      end

      def verify_cora_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @cora_pin

        raise Nabu::FetchError,
              "ren: downloaded CorAXML_1.1.zip misses its sha256 pin (expected #{@cora_pin}, " \
              "got #{fetch.sha}) — the 1.1 deposit is versioned-immutable, so this is " \
              "corruption or an unannounced re-release; verify #{CORAXML_URL} and re-pin " \
              "CORAXML_SHA256 only after reading the record"
      end

      def fetch_notes(tei, cora)
        [
          tei.not_modified? ? "not modified (304)" : "fdr 1.1 sha pin verified",
          cora.not_modified? ? "CorAXML not modified (304)" : "CorAXML sha pin verified",
          attic_notes(tei.atticked + cora.atticked)
        ].compact.join("; ")
      end
    end
  end
end
