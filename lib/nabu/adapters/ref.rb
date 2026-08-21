# frozen_string_literal: true

require_relative "cora_xml_parser"

module Nabu
  module Adapters
    # The ReF adapter (P80-5): the Reference Corpus of Early New High
    # German (1350–1650) — Referenzkorpus Frühneuhochdeutsch v1.0.2
    # (Wegera, Solms, Demske, Dipper 2021; ISLRN 918-968-828-554-7),
    # ~3.7M tokens of diplomatically transcribed and annotated ENHG from
    # the three project sites Bochum (ReF.RUB), Halle (ReF.MLU) and
    # Potsdam (ReF.UP) — the THIRD rung of the Bochum/Hamburg
    # reference-corpus ladder after ReM (MHG, P40-5) and ReN (MLG,
    # P46-5), and the first registrant of the cora-xml family (the RAW
    # CorA export; the deposit ships NO TEI, so the cora-tei family the
    # siblings ride does not apply).
    #
    # == Scope (the shape verdict, censused 2026-08-19)
    #
    # The adapter ingests the two CorA-XML subcorpora — ref-mlu/ (136
    # files) + ref-rub/ (54 files) = ALL 190 texts of the corpus. The
    # ref-up/ subcorpus (26 TigerXML files, Potsdam's syntactic
    # annotation) duplicates 26 of those texts as sentence-segmented
    # EXCERPTS with word+pos+constituency but NO diplomatic layer, no
    # lemma and no layout — a syntax overlay, not new text. Ingesting it
    # would double-count; the graphs are a documented follow-up (a
    # tiger-xml family over the same deposit). The ref-lesetexte tarball
    # (PDF reading texts, no annotation) is not ingestible material.
    #
    # == Identity (minting)
    #
    # One document per CorA-XML file; the F-sigle filename IS upstream's
    # stable text id (also the <text id> and <cora-header sigle> —
    # censused identical). urn = urn:nabu:ref:<sigle downcased>
    # (urn:nabu:ref:f011). Passage = one PHYSICAL LINE (manuscript or
    # print — the corpus's own layout grain), cited
    # <page><side><column>.<label>: …:f011:001r.01, …:f313:003va.01
    # (named columns join the folio, the ReM rule), …:f240:090.08
    # (sideless pages cite the bare number). Upstream carries duplicate
    # line citations (censused: 5,729 across 40 files, adjacent duplicate
    # labels included) — collisions take the house :b2 positional
    # disambiguator, never quarantine, never merge.
    #
    # == The two token layers (owner doctrine: canonical means canonical)
    #
    # Passage text = the DIPLOMATIC layer (tok_dipl @utf — long ſ,
    # combining marks), NFC at this boundary; the annotated layer
    # (tok_anno: lemma/pos/morph, the DWB lemma id, the modern-punctuation
    # and sentence-boundary suggestion lanes) rides annotations["tokens"]
    # per line. Annotation provenance is honest: anno_type "manual" marks
    # the hand-checked minority (censused 544,520 of 3,418,971 anno
    # units; absence reads auto — the corpus is largely auto-annotated,
    # so the source rides lemma_tier silver, the achemenet rule).
    #
    # == Language / dating / localization
    #
    # Every file's header says language: fnhd (censused 190/190; parse
    # re-verifies and quarantines drift). ENHG has NO ISO code — gmh
    # stops at ~1500, de is anachronistic — so documents ride the bare
    # anchor "de" and the lect posture is pending on a de:early stage
    # mint in nabu-lects (the sv:old/it:old precedent). The header's
    # date/time/place lanes are REAL (unlike ReM's placeholders:
    # "1487/88", "Regensburg", time "15,2") and ride metadata verbatim;
    # the dialect chain (language-type → -region → -area, coarse to
    # fine) rides metadata["dialects"] — extractors over real synced
    # data are the future packets (postures: pending, the isicily
    # discipline).
    #
    # == License (the record-field conflict, recorded honestly)
    #
    # CC BY-SA 4.0 per the corpus's own statements: the rub.de access
    # page ("licensed under a Creative Commons Attribution-ShareAlike
    # 4.0 International License", read 2026-08-19), the in-deposit
    # README ("This work is licensed under a Creative Commons
    # Attribution-ShareAlike 4.0 International License") and the
    # in-deposit LICENSE (the BY-SA 4.0 legal text). The Zenodo record's
    # license FIELD says cc-by-4.0 — a metadata-entry discrepancy, not a
    # grant: the deposit's own files and the project page agree on
    # BY-SA, so the stricter BY-SA is honored. license_class
    # "attribution".
    #
    # == fetch / sync policy
    #
    # ONE immutable Zenodo artifact (record 5793616, ReF-v1.0.2.tar.gz,
    # 143,463,482 B) via ZipFetch archive: :tar_gz (the P80-5 extension)
    # with the phases hand-driven so the hard sha256 pin is checked
    # BETWEEN download and any tree mutation (the rem/iecor mold). The
    # tarball's single top dir (ReF-v1.0.2/) strips, so canonical =
    # LICENSE + README.md + dokumentation.pdf + ref-{mlu,rub,up}/ under
    # the workdir. A future v1.1 is a new Zenodo version: the owner
    # re-pins URL + sha and fires the re-sync. sync_policy: manual,
    # wired: false until the owner-fired first sync.
    class Ref < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/5793616"
      TAR_URL = "https://zenodo.org/api/records/5793616/files/ReF-v1.0.2.tar.gz/content"

      # sha256 of the 143,463,482-byte ReF-v1.0.2.tar.gz, pinned from the
      # 2026-08-19 fixture snapshot download (test/fixtures/ref/README.md).
      # Zenodo files are immutable: a mismatch is corruption or an
      # unannounced re-release, never a routine update.
      RELEASE_SHA256 = "288a478d02de5796d14faa0b669879dc6bf67c47e2d7ee261815e15120b99f0e"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ref",
        name: "ReF — Referenzkorpus Frühneuhochdeutsch (1350–1650), v1.0.2",
        license: "CC BY-SA 4.0 (the corpus's own statements: rub.de access page, in-deposit " \
                 "README and LICENSE, all BY-SA; the Zenodo record 5793616 license FIELD says " \
                 "cc-by-4.0 — a metadata discrepancy, the stricter BY-SA is honored. Cite: " \
                 "Wegera, Solms, Demske, Dipper 2021, ISLRN 918-968-828-554-7)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "cora-xml"
      )

      # ENHG has no ISO code: documents ride the bare de anchor; the
      # de:early stage refinement is the pending nabu-lects mint
      # (config/postures.yml).
      LANGUAGE = "de"

      # The per-file language pin (censused 190/190; drift quarantines).
      LANGUAGE_PIN = "fnhd"

      # The two CorA-XML subcorpus directories (class note: ref-up is the
      # TigerXML syntax overlay, a documented follow-up).
      SUBCORPORA = %w[ref-mlu ref-rub].freeze

      # Header fields consumed structurally rather than ridden verbatim:
      # language is the verified pin; the language-* chain becomes
      # metadata["dialects"]; date becomes the structured envelope (raw
      # preserved inside it — the P81-1 harvest).
      CONSUMED_FIELDS = %w[language language-type language-region language-area date].freeze

      # The clean date-lane parses (P81-1). Anything else — "ca. 1350-75",
      # "3. Viertel 14. Jh.", multi-source prose — is never number-scraped:
      # it falls back to the century-half grid below.
      DATE_EXACT = /\A(\d{4})\z/
      # "1383-1407", "1538 - 1545", "1487/88", "1481/96" — a 2-digit tail
      # expands with the head's century ("1487/88" → 1488).
      DATE_SPAN = %r{\A(\d{4})\s*[-–/]\s*(\d{2}|\d{4})\z}
      # Upstream's own century-half grid, on ALL 190 texts (censused
      # 2026-08-20): time "15,2" = 15th c., 2nd half → [1450, 1500].
      TIME_GRID = /\A(\d{2}),([12])\z/

      def self.manifest
        MANIFEST
      end

      # HEAD the Zenodo artifact: reachability + Last-Modified drift
      # against the .zip-fetch.json pin. metadata_url nil — the license
      # travels in-deposit and on the record page.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "ReF-v1.0.2.tar.gz", zip_url: TAR_URL, metadata_url: nil, state_subdir: ""
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per subcorpus text file, sorted by urn; a workdir
      # without the files yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Header (language pin verified) → document; one passage per
      # physical line, diplomatic text, token records riding annotations.
      def parse(document_ref)
        header = verified_header(document_ref)
        body = parser.body(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: header.name,
          canonical_path: document_ref.path,
          metadata: document_metadata(header, body, document_ref)
        )
        append_lines(document, body, document_ref)
        raise ParseError, "#{document_ref.path}: no physical lines in layoutinfo" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify the hard sha pin + unpack, phases hand-driven so
      # the pin check runs BETWEEN download and any tree mutation (prepare
      # → pin → mass-deletion breaker → complete); a 304 replays the
      # stored pin and touches nothing. No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: TAR_URL, dir: workdir, archive: :tar_gz,
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
        raise Nabu::FetchError, "ref fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        CoraXmlParser.new
      end

      def document_refs(workdir)
        reader = parser
        Dir.glob(File.join(workdir, "**", "{#{SUBCORPORA.join(',')}}", "*.xml")).map do |path|
          header = reader.header(path)
          sigle = File.basename(path, ".xml")
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:ref:#{sigle.downcase}",
            path: File.expand_path(path),
            metadata: { "title" => header.name, "language" => LANGUAGE }.compact
          )
        end.sort_by(&:id)
      end

      # The header, with the per-file language line held against the
      # corpus pin — drift quarantines the document (the ReM discipline).
      def verified_header(document_ref)
        header = parser.header(document_ref.path)
        unless header.fields["language"] == LANGUAGE_PIN
          raise ParseError, "#{document_ref.path}: header language " \
                            "#{header.fields['language'].inspect} != \"#{LANGUAGE_PIN}\" — " \
                            "a non-ENHG text does not belong to this source"
        end

        header
      end

      # The header lanes verbatim (upstream keys, placeholders already
      # dropped by the parser) minus the structurally consumed fields,
      # plus sigle/subcorpus identity, the coarse-to-fine dialect chain,
      # and the loudness censuses.
      def document_metadata(header, body, document_ref)
        dialects = %w[language-type language-region language-area]
                   .filter_map { |k| header.fields[k] }
        header.fields.except(*CONSUMED_FIELDS).merge(
          {
            "date" => date_envelope(header.fields["date"], header.fields["time"]),
            "sigle" => header.sigle,
            "subcorpus" => File.basename(File.dirname(document_ref.path)),
            # The subcorpus as a FACET row (FacetBuilder projects the
            # "facets" key): the total facet the ref-enhg lect rule keys
            # on (every text sits in exactly one deposit dir).
            "facets" => { "subcorpus" => {
              "value" => File.basename(File.dirname(document_ref.path))
            } },
            "dialects" => (dialects unless dialects.empty?),
            "shifttags" => (body.shifttags unless body.shifttags.empty?),
            "comments" => (body.comments if body.comments.positive?),
            "unrecognized_elements" => (body.unrecognized unless body.unrecognized.empty?)
          }.compact
        )
      end

      # The MetadataDates :structured envelope (P81-1): a clean date-lane
      # parse rules; prose datings take upstream's own century-half grid
      # (raw then names both claims); neither lane clean → the raw string
      # rides alone, minting nothing (the bdcamoes "18??" discipline).
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

        start = ((Integer(match[1], 10) - 1) * 100) + ((Integer(match[2], 10) - 1) * 50)
        [start, start + 50]
      end

      # Ref = <page><side><column>.<label> (named columns join the folio —
      # the ReM rule; sideless pages cite the bare number). Upstream's
      # duplicate citations (censused: 5,729) take the house :b2
      # positional disambiguator — never quarantine, never merge.
      def append_lines(document, body, document_ref)
        seen = Hash.new(0)
        body.lines.each do |line|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{line_ref(line, seen)}",
            language: LANGUAGE, text: Normalize.nfc(line.text),
            annotations: { "tokens" => line.tokens.map { |t| nfc_record(t) } },
            sequence: document.size
          )
        end
      end

      # Token records cross the adapter boundary NFC like the passage text
      # (the corpus's diplomatic layer is decomposed upstream).
      def nfc_record(record)
        record.transform_values { |v| v.is_a?(String) ? Normalize.nfc(v) : v }
      end

      def line_ref(line, seen)
        folio = [line.page, line.side, line.column].compact.join
        ref = [(folio unless folio.empty?), line.n].compact.join(".")
        count = (seen[ref] += 1)
        count == 1 ? ref : "#{ref}:b#{count}"
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "ref: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{TAR_URL} and re-pin RELEASE_SHA256 only after " \
              "reading the record"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo v1.0.2 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
