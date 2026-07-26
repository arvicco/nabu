# frozen_string_literal: true

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
    # the data. Dating/localization (date_ReN, place, language-area) live
    # ONLY in the CorA-XML sibling zip's headers — a documented follow-up,
    # the inverse of ReM's pos/msd gap.
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
    # ONE versioned-immutable deposit artifact (tei_1.1.zip, 21,829,154 B)
    # via ZipFetch with the phases hand-driven so the hard sha256 pin is
    # checked BETWEEN download and any tree mutation (the rem/iecor mold).
    # The record URL 302s to a short-lived signed S3 URL — ZipFetch's
    # RedirectFollow handles it — and the zip's single top dir (tei_1.1/)
    # strips, so canonical = anno/ + trans/ under the workdir. A future
    # 1.2 is a new record version: the owner re-pins URL + sha and fires
    # the re-sync. sync_policy: manual, wired: false until the owner-fired
    # first sync.
    class Ren < Nabu::Adapter
      RECORD_URL = "https://www.fdr.uni-hamburg.de/record/9195"
      ZIP_URL = "https://www.fdr.uni-hamburg.de/record/9195/files/tei_1.1.zip?download=1"

      # sha256 of the 21,829,154-byte tei_1.1.zip, pinned from the
      # 2026-07-26 fixture snapshot download (test/fixtures/ren/README.md).
      # The 1.1 deposit is versioned-immutable: a mismatch is corruption or
      # an unannounced re-release, never a routine update.
      RELEASE_SHA256 = "b4cc9664268f760517b822c5d3965050ad15d31d712ba7907742c87808b7841e"

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
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "tei_1.1.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
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
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title_for(sigle),
          canonical_path: document_ref.path,
          metadata: document_metadata(body, document_ref, sigle)
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
        Dir.glob(File.join(workdir, "**", "{anno,trans}", "*.tei")).map do |path|
          sigle = sigle_for(path)
          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:ren:#{self.class.slug_for(sigle)}",
            path: File.expand_path(path),
            metadata: { "title" => title_for(sigle), "language" => LANGUAGE,
                        "layer" => layer_for(path) }
          )
        end.sort_by(&:id)
      end

      # The filename minus .tei IS the deposit's text sigle; NFC because
      # macOS filesystems hand globs NFD names (the umlaut sigla).
      def sigle_for(path)
        Normalize.nfc(File.basename(path, ".tei"))
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

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "fdr 1.1 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
