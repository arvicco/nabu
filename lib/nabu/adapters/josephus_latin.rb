# frozen_string_literal: true

require "csv"

require_relative "josephus_latin_tei_parser"

module Nabu
  module Adapters
    # The Latin Josephus (latinjosephus.org, Richard Matthew Pollard,
    # Université du Québec à Montréal): the complete late-antique Latin
    # Josephus — the Antiquitates Judaicae (20 books + proem) and Contra
    # Apionem (2) translated under Cassiodorus in the mid-sixth century,
    # the anonymous literal Bellum Judaicum (7, c. 400), and the free
    # reworking De excidio Hierosolymitano of "Pseudo-Hegesippus" (5,
    # c. 370) — from the project's v3.0 Zenodo deposit "The Latin Josephus
    # Scholarly Corpus" (record 24120761, DOI 10.5281/zenodo.24120761,
    # published 2026-11-10). A thin composition of the bespoke
    # `josephus-latin-tei` family (JosephusLatinTeiParser).
    #
    # == The witnesses
    #
    # Antiquities: a transcription of the Carolingian Bamberg,
    # Staatsbibliothek, Msc.Class.78 (s. IX med.), with the early-medieval
    # manuscript annotations of the other witnesses (Bern 50/118, Leiden
    # VLF 17, Monza, Vatican Pal. lat. 814 …). Bellum: Cardwell's edition
    # (Oxford, 1837), Pollard's electronic text. Contra Apionem: Boysen,
    # CSEL 37 (1898), via Open Greek and Latin csel-dev. De excidio:
    # Ussani, CSEL 66.1 (1932), via digilibLT DLT000241, corrected.
    #
    # == Delivery grains and the document grain (enumerated 2026-11-17)
    #
    # The record serves three files: SHA256SUMS.txt, the core zip
    # (Latin_Josephus_v3.0_Corrected_XML_ZENODO_RC.zip, 8,359,339 B — 166
    # canonical XML + 14 Niese citation registries + release docs) and a
    # supplementary zip (11,169,170 B — the Froben 1524 Latin, Millet 1556
    # French and Lauro 1544 Italian transcriptions as offset-coordinate JSON,
    # the 527-record manuscript catalogue, annotation and concordance
    # tables, the EEBO-TCP A04680 source). Only the CORE zip is fetched:
    # the supplementary data is coordinate-and-table JSON whose texts
    # rebuild from row/offset spans — a separate parser, deliberately not
    # this packet. Inside the core, document = one per-book TEI file under
    # assets/xml/<work>/Latin/. Every other file under assets/xml/ is a
    # rejected grain, counted by rule in discovery_skips:
    #
    #   Greek/          Niese's Greek via Perseus — held (perseus-greek tlg0526)
    #   English/        Whiston via Perseus — held (perseus-greek eng2)
    #   English/Lodge1602/  Lodge 1602 = EEBO-TCP A04680 — held (eebo-tcp)
    #   deh/English/    the De excidio English v1.2: per the project's own
    #                   statement it "was drafted by AI from the Latin"
    #                   (latinjosephus.org/texts) — never ingested
    #   paratext/       capitula files: Greek (Niese) and English (Whiston)
    #                   editorial paratext, and the Bamberg Latin capitula
    #                   whose lost margins are supplied from Blatt (1958) —
    #                   quotations outside the deposit's open grant
    #   niese/*.json    the Niese citation registries (data, not text)
    #   structure.xml, source-contents.xml   structural registers
    #
    # Reconciliation against upstream's own README count: 166 XML + 14
    # registries = 180 files under assets/xml/ = 35 accepted (21 + 7 + 2 +
    # 5 Latin books) + 145 skipped by rule (30 Greek, 30 Whiston, 30
    # Lodge, 5 AI English, 34 paratext, 14 registries, 2 registers).
    #
    # == Identity
    #
    #   document urn  urn:nabu:josephus-latin:<work>.<stem>
    #                 (urn:nabu:josephus-latin:antiquities.book-01,
    #                  …:antiquities.preface, …:deh.book-02)
    #   passage urn   <document-urn>:<unit ref> (…:antiquities.book-01:num27,
    #                 …:antiquities.book-13:p3 for an id-less capitulum)
    #
    # == License (mixed rights, per file, from the deposit's own manifest)
    #
    # The Zenodo record declares cc-by-4.0; the deposit's
    # FILE_LICENCE_MANIFEST.csv states each file's terms. Antiquities:
    # Public Domain Mark 1.0 (the historical witness) + CC BY 4.0 (Pollard's
    # editorial work); Bellum: CC BY 4.0; Contra Apionem: CC BY-SA 4.0 (the
    # Perseus/OGL layer); De excidio: CC BY-NC-SA 3.0 Italy (the digilibLT
    # layer). Source class `attribution`; a file whose manifest row names a
    # NonCommercial license carries a per-document `nc` override. A file
    # the manifest does not list, or a license URI outside the known set,
    # quarantines — terms are never guessed.
    #
    # == Dating (two claims, recorded apart)
    #
    # The held texts are the LATIN versions; the timeline dates the Latin
    # translation (class composition, the upstream Background page's own
    # datings, circa = ±10 years): De excidio c. 370 → 360–380; Bellum
    # c. 400 → 390–410; Antiquities and Contra Apionem "mid-sixth
    # century" under Cassiodorus → 530–570. Josephus' Greek originals
    # (c. 75–79, 93–94, 94–100 CE) ride metadata "original" only — a
    # translation is never dated by its source.
    #
    # Not carried (declared): the annotations' witness dates (the
    # manuscript catalogue lives in the supplementary zip) and any place
    # claim — upstream names the Cassiodoran translation's place only as
    # "Italy or perhaps Constantinople".
    #
    # == fetch / sync policy
    #
    # ONE immutable Zenodo artifact, sha256-pinned and checked BETWEEN
    # download and any tree mutation (the ReF mold); the zip has no single
    # top dir, so its tree lands at the workdir root. A later version is a
    # new Zenodo record: the owner re-pins URL + sha before a re-sync.
    class JosephusLatin < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/24120761"
      ZIP_NAME = "Latin_Josephus_v3.0_Corrected_XML_ZENODO_RC.zip"
      ZIP_URL = "https://zenodo.org/api/records/24120761/files/#{ZIP_NAME}/content".freeze

      # sha256 of the 8,359,339-byte core zip — the record's own
      # SHA256SUMS.txt value, verified against the 2026-11-17 download
      # (md5 ce4f8d782e727b1a1a259b5eac661980 matches the record API).
      RELEASE_SHA256 = "cfaf269a6fcbd7eb61754573449304dc1ed9d59bd5c6c0a7f5e9c8ec44d67106"

      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:josephus-latin:"
      XML_ROOT = File.join("assets", "xml")
      LICENCE_MANIFEST = "FILE_LICENCE_MANIFEST.csv"

      Work = Data.define(:title, :author, :date, :original)

      # The four works, keyed on the deposit's directory names. +date+ is
      # the Latin version's envelope (see class note), +original+ the Greek
      # source's date, both from latinjosephus.org/background.
      WORKS = {
        "antiquities" => Work.new(
          title: "Antiquitates Judaicae", author: "Flavius Josephus",
          date: { "not_before" => 530, "not_after" => 570, "class" => "composition",
                  "raw" => "mid-6th century: the Latin translation made under Cassiodorus" },
          original: "Greek, published 93–94 CE"
        ),
        "bellum" => Work.new(
          title: "Bellum Judaicum", author: "Flavius Josephus",
          date: { "not_before" => 390, "not_after" => 410, "class" => "composition",
                  "raw" => "c. 400: the anonymous literal Latin translation (once ascribed to Rufinus)" },
          original: "Greek, c. 75–79 (or 75–84) CE"
        ),
        "contra-apionem" => Work.new(
          title: "Contra Apionem", author: "Flavius Josephus",
          date: { "not_before" => 530, "not_after" => 570, "class" => "composition",
                  "raw" => "mid-6th century: translated with the Antiquities under Cassiodorus" },
          original: "Greek, c. 94–100 CE"
        ),
        "deh" => Work.new(
          title: "De excidio Hierosolymitano", author: "Pseudo-Hegesippus",
          date: { "not_before" => 360, "not_after" => 380, "class" => "composition",
                  "raw" => "c. 370: the free Latin reworking of the Jewish War" },
          original: "reworks Josephus' Bellum Judaicum (Greek, c. 75–79 CE)"
        )
      }.freeze

      # Licence URIs the manifest may name, → per-document override (nil =
      # inherit the source's attribution class).
      LICENSE_OVERRIDES = {
        "https://creativecommons.org/licenses/by/4.0/" => nil,
        "https://creativecommons.org/licenses/by-sa/4.0/" => nil,
        "https://creativecommons.org/publicdomain/mark/1.0/" => nil,
        "https://creativecommons.org/publicdomain/zero/1.0/" => nil,
        "https://creativecommons.org/licenses/by-nc-sa/3.0/it/" => "nc",
        "https://creativecommons.org/licenses/by-nc-sa/4.0/" => "nc"
      }.freeze

      # The rejected grains (class note), matched on the path under
      # assets/xml/ — first match wins, each with its discovery note.
      REJECTED = [
        [%r{\Adeh/English/[^/]+\.xml\z}, "De excidio English (AI-drafted translation per upstream)"],
        [%r{\A[^/]+/English/Lodge1602/[^/]+\.xml\z}, "Lodge 1602 English (EEBO-TCP A04680, held by eebo-tcp)"],
        [%r{\A[^/]+/English/[^/]+\.xml\z}, "Whiston English (Perseus, held by perseus-greek)"],
        [%r{\A[^/]+/Greek/[^/]+\.xml\z}, "Niese Greek (Perseus, held by perseus-greek)"],
        [%r{\A[^/]+/paratext/.+\.xml\z}, "capitula paratext"],
        [%r{\A[^/]+/niese/[^/]+\.json\z}, "Niese citation registry"],
        [%r{\A(?:[^/]+/)?(?:structure|source-contents)\.xml\z}, "structural register"]
      ].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "josephus-latin",
        name: "The Latin Josephus — Antiquitates, Bellum, Contra Apionem, De excidio " \
              "(latinjosephus.org v3.0)",
        license: "Mixed, per file (the deposit's FILE_LICENCE_MANIFEST.csv): Antiquities " \
                 "Public Domain Mark 1.0 + CC BY 4.0, Bellum CC BY 4.0, Contra Apionem " \
                 "CC BY-SA 4.0, De excidio CC BY-NC-SA 3.0 Italy (per-document nc); the " \
                 "Zenodo record declares cc-by-4.0. Cite: Richard Matthew Pollard, The Latin " \
                 "Josephus Scholarly Corpus, v3.0, doi:10.5281/zenodo.24120761",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "josephus-latin-tei"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD the Zenodo artifact: reachability + Last-Modified drift
      # against the .zip-fetch.json pin. The license travels in-deposit.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: ZIP_NAME, zip_url: ZIP_URL, metadata_url: nil, state_subdir: ""
        )]
      end

      # +pin+ overrides the release sha (tests; a future re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per Latin book file, sorted by urn; a pre-fetch
      # workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir)[:accepted].map { |rel| document_ref(workdir, rel) }.sort_by(&:id).each(&block)
      end

      # Every rejected grain counted with its note; anything under
      # assets/xml/ neither accepted nor matched by a rule is unrecognized.
      def discovery_skips(workdir)
        counts = census(workdir)
        notes = counts[:skipped].map { |label, n| "#{n} #{label} file(s) skipped by rule" }
        notes.concat(counts[:unrecognized].map { |rel| "unrecognized file under assets/xml: #{rel}" })
        DiscoverySkips.new(skipped_by_rule: counts[:skipped].values.sum,
                           unrecognized: counts[:unrecognized].size, notes: notes)
      end

      def parse(document_ref)
        result = JosephusLatinTeiParser.new.parse(document_ref.path)
        row = licence_row(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: document_ref.metadata.fetch("title"),
          canonical_path: document_ref.path,
          metadata: document_metadata(document_ref, result, row),
          license_override: license_override(document_ref, row)
        )
        result.units.each do |unit|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{unit.ref}", language: LANGUAGE, text: unit.text,
            annotations: unit.annotations.merge("unit" => unit.name), sequence: document.size
          )
        end
        raise ParseError, "#{document_ref.path}: no reading units" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Download + verify the hard sha pin + unpack; the pin check runs
      # BETWEEN download and any tree mutation (prepare → pin → breaker →
      # complete); a 304 replays the stored pin and touches nothing.
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
        raise Nabu::FetchError, "josephus-latin fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Path census under assets/xml/: accepted relpaths, per-rule skip
      # counts, unrecognized relpaths.
      def census(workdir)
        root = File.join(workdir, XML_ROOT)
        result = { accepted: [], skipped: Hash.new(0), unrecognized: [] }
        Dir.glob(File.join(root, "**", "*")).each do |path|
          next unless File.file?(path)

          rel = path.delete_prefix("#{root}/")
          if accepted?(rel)
            result[:accepted] << rel
          elsif (rule = REJECTED.find { |pattern, _| pattern.match?(rel) })
            result[:skipped][rule[1]] += 1
          else
            result[:unrecognized] << rel
          end
        end
        result
      end

      def accepted?(rel)
        work, lang, file, *rest = rel.split("/")
        rest.empty? && lang == "Latin" && WORKS.key?(work) && file.to_s.end_with?(".xml")
      end

      def document_ref(workdir, rel)
        work, _lang, file = rel.split("/")
        stem = File.basename(file, ".xml")
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{URN_PREFIX}#{work}.#{stem}",
          path: File.expand_path(File.join(workdir, XML_ROOT, rel)),
          metadata: { "work" => work, "stem" => stem, "title" => title(work, stem),
                      "upstream_path" => "#{XML_ROOT}/#{rel}", "language" => LANGUAGE }
        )
      end

      def title(work, stem)
        part = stem == "preface" ? "Proem" : "Book #{book_number(stem)}"
        "#{WORKS.fetch(work).title} (Latin), #{part}"
      end

      def book_number(stem)
        match = stem.match(/\Abook-0*(\d+)\z/)
        match ? match[1] : stem
      end

      def document_metadata(document_ref, result, row)
        work = WORKS.fetch(document_ref.metadata.fetch("work"))
        stem = document_ref.metadata.fetch("stem")
        {
          "work" => work.title,
          "book" => stem == "preface" ? "preface" : book_number(stem),
          "author" => work.author,
          "original" => work.original,
          "date" => work.date,
          "edition" => row["edition_or_role"],
          "witness" => (result.witness unless result.witness.empty?),
          "upstream_title" => (result.title unless result.title.empty?),
          "upstream_path" => document_ref.metadata.fetch("upstream_path"),
          "annotation_witnesses" => (result.witnesses unless result.witnesses.empty?),
          "licence_uris" => licence_uris(row),
          "rights" => row["rights_and_attribution"],
          "sha256" => row["sha256"],
          "facets" => { "genre" => { "value" => work.title } }
        }.compact
      end

      def license_override(document_ref, row)
        uris = licence_uris(row)
        unknown = uris.reject { |uri| LICENSE_OVERRIDES.key?(uri) }
        unless unknown.empty?
          raise ParseError, "#{document_ref.path}: licence URI(s) outside the known set " \
                            "#{unknown.join(', ')} — review the deposit's terms"
        end

        uris.filter_map { |uri| LICENSE_OVERRIDES[uri] }.first
      end

      def licence_uris(row)
        row["licence_uris"].to_s.split("|").map(&:strip).reject(&:empty?)
      end

      # The document's row in the deposit's licence manifest (the workdir
      # root's, or — for an attic ref — the live workdir's beside it).
      def licence_row(document_ref)
        upstream_path = document_ref.metadata.fetch("upstream_path")
        rows = licence_rows(manifest_path(document_ref))
        rows.fetch(upstream_path) do
          raise ParseError, "#{document_ref.path}: no #{LICENCE_MANIFEST} row for #{upstream_path} — " \
                            "terms are never guessed"
        end
      end

      def manifest_path(document_ref)
        root = document_ref.path.delete_suffix(document_ref.metadata.fetch("upstream_path")).chomp("/")
        [root, File.dirname(root)].map { |dir| File.join(dir, LICENCE_MANIFEST) }.find { |p| File.exist?(p) } or
          raise ParseError, "#{document_ref.path}: #{LICENCE_MANIFEST} absent — terms are never guessed"
      end

      def licence_rows(path)
        (@licence_rows ||= {})[path] ||=
          CSV.parse(SourceRead.utf8_file(path, label: "josephus-latin licence manifest"), headers: true)
             .to_h { |r| [r["path"], r.to_h] }
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "josephus-latin: downloaded artifact misses the release sha256 pin (expected #{@pin}, " \
              "got #{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{ZIP_URL} and re-pin RELEASE_SHA256 only after " \
              "reading the record"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo v3.0 core zip sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
