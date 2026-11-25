# frozen_string_literal: true

require_relative "../pdf_text"
require_relative "hrcak_marulana_fetch"
require_relative "hrcak_record"

module Nabu
  module Adapters
    # hrcak-marulana — Colloquia Maruliana, the annual journal of Marulić
    # studies (Split Literary Circle — Marulianum, centre for studies on
    # Marko Marulić and his humanist circle; vol. 1, 1992 → vol. 35, 2026),
    # in full text from Hrčak, the Croatian journal portal
    # (hrcak.srce.hr/colloquia-maruliana, OAI set journal:43). Beside the
    # scholarship on Marulić and the Dalmatian/Dubrovnik humanists the
    # journal prints text editions: Latin works of Marulić and his circle
    # (Regum Delmatiae atque Croatiae gesta, Tropologica Davidiadis
    # expositio, …), Venantius Fortunatus' Ad Felicem episcopum De pascha,
    # Croatian critical editions — mostly in the resource type "other".
    #
    # == Grains upstream serves (census 2026-11-25) and the one taken
    #
    # - the journal (the OAI set; the portal's journal page);
    # - the volume/issue (portal pages /broj/<id>; OAI carries only the
    #   volume/issue numbers) — not fetched: no content beyond the records;
    # - the ARTICLE RECORD (OAI-PMH oai_openaire / oai_dc / mods, and the
    #   landing page /<id>) — THE DOCUMENT: urn:nabu:hrcak-marulana:<id>,
    #   Hrčak's own permanent article id. 681 records advertised
    #   (resumptionToken completeListSize 681), all with full text;
    # - the full-text PDF (/file/<id>, 772 files: 591 records carry one,
    #   89 two, 1 three) — the passage source: one passage per non-blank PDF
    #   page, urn:…:<id>:f<file-id>:p<n> (the house PDF grain,
    #   Nabu::PdfText — the page is the only unit a PDF keeps stable; the
    #   file id keeps a record's several PDFs apart). A second/third PDF is
    #   the article's version or summary in another language (90 of 90
    #   multi-file records checked against the landing pages);
    # - the abstract (dc:description, 427 records, per language) — rides
    #   document metadata "abstracts", never a passage.
    #
    # Skipped BY RULE (discovery_skips): records whose own licence
    # condition grants nothing — 37 carry rightsstatements.org InC
    # (in copyright; their PDFs are never downloaded). Unrecognized: a
    # record whose PDFs are not all held (a fetch hole), a record missing
    # its oai_dc twin, or a licence URI outside HrcakRecord::LICENSES.
    # Reconciliation at the 2026-11-25 census: 681 advertised = 644
    # documents + 37 skipped by rule.
    #
    # == Languages (per PDF)
    #
    # Each PDF claims the language its record pairs with it (the
    # parallel-sequence rule, HrcakRecord); a record listing more
    # languages than PDFs prints the extra ones (summaries) inside the
    # last PDF — they ride metadata "inner_languages", the passages keep
    # the PDF's own language. Upstream's 639-2 codes are kept verbatim
    # (hrv, lat, ita, eng, fre, ger, spa, srp — the codemap folds the /B
    # spellings); the document language is the first PDF's. Coarseness,
    # declared: a page mixing an edition's Latin with a Croatian
    # apparatus or translation carries the PDF's one code.
    #
    # == The text layers, as upstream made them
    #
    # Three regimes (one PDF per volume sampled 2026-11-25): the early
    # volumes are scans with an Acrobat Paper Capture OCR layer (OCR
    # errors kept verbatim — "MaruliC", "naiSao" — canonical means
    # canonical); vols. ~3–15 are PageMaker documents set in a Croatian
    # slot font, whose text layer maps the Croatian letters to the Mac
    # Roman glyphs of the slots they replaced (MaruliÊ, πto, Ëitanje); the
    # later volumes are clean Unicode — though running heads and footnotes
    # of vols. ~12–22 may still sit in the slot font beside a Unicode body
    # (JovanoviÊ: in every running head). The slot-font layer is an
    # ENCODING defect, repaired at this boundary (LegacyFont), per PDF: the
    # WHOLE table when the PDF shows the signature and no real Croatian
    # letter; else only the unambiguous slots INSIDE Latin words (a mixed
    # PDF). Metadata "legacy_font_repairs" names each repaired PDF and its
    # mode. Slots whose reading is ambiguous stay verbatim (declared in
    # LegacyFont).
    #
    # == Mined metadata
    #
    # Titles (all languages), creators (name, affiliations, ORCID — the
    # author facet), issue date (the date axis, EDITION class: the
    # article's publication date, never a claim about the composition of
    # an edited text), volume/issue/pages, resource type (the genre facet
    # the kind fold reads), keywords (the subject facet), abstracts, the
    # landing and PDF URLs. Places: the records carry no place field
    # (affiliations are the authors', not the texts') — unplaced.
    #
    # == Licence (per record)
    #
    # The journal statement, verbatim on every record's oai_dc dc:rights:
    # CC BY 4.0. 91 records carry their OWN oaire:licenseCondition, which
    # governs them (the landing page shows that badge): CC BY / CC BY-SA →
    # the source class (attribution); CC BY-NC / CC BY-NC-ND → the
    # document's license_override "nc" (37 records); InC → skipped by rule.
    class HrcakMarulana < Nabu::Adapter
      SLUG = "hrcak-marulana"

      # The Croatian slot-font repair (see the class comment). A PDF's
      # text is LEGACY when it shows at least SIGNATURE_MIN of the four
      # unambiguous signature glyphs and not one real Croatian letter.
      # Within a legacy PDF the slot glyphs map back to the letters they
      # stand for (verified 2026-11-25 on vols. 3, 10, 11, 13: the repaired
      # words are real Croatian — Marulić, književnosti, riječi, između).
      # Verbatim on purpose (their reading is not settled from the text
      # alone): ¬ and µ (an edition's ļ/ń-like letters), ⌠ (long s), the
      # "fl" opening quote, and a word-initial » (a quote mark or Č).
      #
      # A MIXED PDF (real Croatian letters beside slot glyphs — a Unicode
      # body with slot-font running heads/footnotes; census 2026-11-25:
      # vols. 12, 14, 18, 19) gets only the in-word repair: Ê/Ë after a
      # Latin letter (MaruliÊ, toËno), ∆/π touching one, and the
      # private-use U+F8FF. æ/Æ/©/»/– stay verbatim there — the Latin
      # editions use æ legitimately (Delmatiæ), and » – are real
      # punctuation in a Unicode body.
      module LegacyFont
        SIGNATURE = /[ÊË∆\u{F8FF}]/
        SIGNATURE_MIN = 3
        CROATIAN = /[čćšžđČĆŠŽĐ]/
        SLOTS = { "Ê" => "ć", "Ë" => "č", "æ" => "ž", "Æ" => "Ž", "∆" => "Ć", "©" => "Š",
                  "\u{F8FF}" => "đ" }.freeze
        GREEK = /\p{Greek}/

        module_function

        def legacy?(text) = text.scan(SIGNATURE).size >= SIGNATURE_MIN && !CROATIAN.match?(text)

        # The mixed-PDF repair: only the slots no other reading fits,
        # inside a Latin word.
        def repair_in_words(text)
          out = text.gsub(/(?<=\p{Latin})[ÊË]/, "Ê" => "ć", "Ë" => "č")
          out = out.gsub(/(?<=\p{Latin})∆|∆(?=\p{Latin})/, "Ć")
          out = out.gsub(/(?<=\p{Latin})π|π(?=\p{Latin})/, "š")
          out.gsub("\u{F8FF}", "đ")
        end

        # [repaired pages, mode or nil]: "whole" for a legacy PDF, "in-word"
        # when the mixed repair changed anything, nil when nothing did.
        def repair_pdf(pages)
          return [pages.map { |page| repair(page) }, "whole"] if legacy?(pages.join("\f"))

          fixed = pages.map { |page| repair_in_words(page) }
          fixed == pages ? [pages, nil] : [fixed, "in-word"]
        end

        def repair(text)
          out = text.gsub(Regexp.union(SLOTS.keys), SLOTS)
          # π is š unless it sits in a Greek word (a Greek font's own pi).
          out = out.gsub(/(?<!\p{Greek})π(?!\p{Greek})/, "š")
          # Word-internal only: » is Č (U»ENJA, METAFORI»KOGA), – is Đ
          # (ODRE–ENJA), ‡ between digits is the range dash (63‡66).
          out = out.gsub(/(?<=\p{L})»(?=\p{L})/, "Č").gsub(/(?<=\p{L})–(?=\p{L})/, "Đ")
          out.gsub(/(?<=\d)‡(?=\d)/, "–")
        end
      end

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Colloquia Maruliana — the journal of Marulić studies (Marulianum, Split), full text from " \
              "Hrčak: scholarship on Marko Marulić and the Croatian humanists, Latin and Croatian text editions",
        license: "Per record. The journal statement, verbatim on every record (Hrčak OAI-PMH oai_dc " \
                 "dc:rights): \"The annual journal Colloquia Maruliana is published in open access. Its " \
                 "entire content is freely available to users. Users may copy and distribute the material, " \
                 "as well as modify, adapt, and build upon it, in accordance with the terms of the Creative " \
                 "Commons Attribution 4.0 International License (CC BY 4.0). Authors retain unrestricted " \
                 "copyright to their published works.\" A record's own licence condition " \
                 "(oaire:licenseCondition) governs it: CC BY 4.0 / CC BY-SA 4.0 as the source class; CC " \
                 "BY-NC 4.0 / CC BY-NC-ND 4.0 per document as nc; in-copyright records are not ingested. " \
                 "Credit: the article's authors, Colloquia Maruliana (Književni krug Split — Marulianum), " \
                 "via Hrčak (Srce); each document carries its landing URL and rights statement",
        license_class: "attribution",
        upstream_url: "https://hrcak.srce.hr/colloquia-maruliana",
        parser_family: "hrcak-oai-pdf"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # Liveness only: the harvest's state is the record files themselves.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "Hrčak OAI-PMH ListRecords (journal:43)",
          zip_url: HrcakMarulanaFetch.list_url("oai_dc"), metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # +pdf_text+ is the text-layer seam (path → Array of page strings,
      # Nabu::PdfText.pages' contract), injectable so the suite never
      # depends on mutool being installed.
      def initialize(pdf_text: PdfText.method(:pages), delay: HrcakMarulanaFetch::DELAY,
                     rate_limit_pause: HrcakMarulanaFetch::RATE_LIMIT_PAUSE)
        super()
        @pdf_text = pdf_text
        @delay = delay
        @rate_limit_pause = rate_limit_pause
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = HrcakMarulanaFetch.sync!(dir: workdir, delay: @delay, rate_limit_pause: @rate_limit_pause,
                                          progress: progress)
        notes = "#{result.records} record(s) harvested (#{result.records_written} written this sync); " \
                "#{result.pdfs_held} PDF(s) held (+#{result.pdfs_fetched} this sync); " \
                "#{result.gated} record(s) gated by their licence (PDFs not fetched)"
        notes += "; unreachable, retried next sync: #{result.failed.join(', ')}" unless result.failed.empty?
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue HrcakMarulanaFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      # One ref per record that is licensed, has its oai_dc twin, and whose
      # every PDF is held — in id order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        census(workdir).fetch(:accepted).each do |id, record|
          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}",
            path: File.expand_path(HrcakMarulanaFetch.record_path(workdir, id, "oai_openaire")),
            metadata: { "record_id" => id,
                        "pdfs" => record.files.map { |url| File.expand_path(pdf_path(workdir, url)) } }
          )
        end
      end

      def discovery_skips(workdir)
        result = census(workdir)
        notes = result[:holes].map { |id, why| "record #{id}: #{why}" }
        gated = result[:gated]
        notes << "#{gated.size} in-copyright record(s) skipped by rule (#{gated.first(5).join(', ')}…)" if gated.any?
        DiscoverySkips.new(skipped_by_rule: gated.size, unrecognized: result[:holes].size, notes: notes)
      end

      def parse(document_ref)
        path = document_ref.path
        record = HrcakRecord.from_files(path, path.sub(/\.oai_openaire\.xml\z/, ".oai_dc.xml"))
        versions = record.file_versions
        raise Nabu::ParseError, "#{path}: record lists no PDF" if versions.empty?

        legacy = {}
        passages = []
        versions.each do |version|
          pages, mode = LegacyFont.repair_pdf(read_pages(pdf_path(File.dirname(path, 2), version.url)))
          legacy[version.file_id] = mode if mode
          pages.each_with_index do |raw, index|
            text = clean(raw)
            next if text.empty?

            passages << [version, index + 1, text]
          end
        end
        raise Nabu::ParseError, "#{path}: no text on any PDF page" if passages.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: versions.first.language, canonical_path: path,
          title: record.titles.first&.fetch("text"), metadata: metadata_for(record, versions, legacy),
          license_override: license_override(record)
        )
        passages.each_with_index do |(version, page, text), index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:f#{version.file_id}:p#{page}", language: version.language, text: text,
            sequence: index + 1, annotations: { "pdf_file" => version.file_id, "pdf_page" => page }
          )
        end
        document
      end

      private

      def pdf_path(workdir, url) = HrcakMarulanaFetch.pdf_path(workdir, HrcakMarulanaFetch.file_id(url))

      # { accepted: [[id, record]], gated: [id], holes: [[id, why]] } over
      # the held oai_openaire records, in numeric id order.
      def census(workdir)
        result = { accepted: [], gated: [], holes: [] }
        paths = Dir.glob(File.join(workdir, HrcakMarulanaFetch::RECORDS_DIR, "*.oai_openaire.xml"))
        paths.sort_by { |p| File.basename(p).to_i }.each do |path|
          classify(workdir, path, result)
        end
        result
      end

      def classify(workdir, path, result)
        record = HrcakRecord.from_files(path)
        id = record.id
        return result[:holes] << [id, "licence #{record.license_condition['uri']} is not a known grant"] \
          unless record.known_license?
        return result[:gated] << id if record.license_class.nil?
        return result[:holes] << [id, "its oai_dc twin is not held"] \
          unless File.file?(path.sub(/\.oai_openaire\.xml\z/, ".oai_dc.xml"))

        missing = record.files.reject { |url| File.file?(pdf_path(workdir, url)) }
        return result[:holes] << [id, "PDF not held: #{missing.join(', ')} — a fetch hole"] unless missing.empty?

        result[:accepted] << [id, record]
      rescue Nabu::ParseError, HrcakMarulanaFetch::Error => e
        result[:holes] << [File.basename(path), e.message]
      end

      def read_pages(path)
        @pdf_text.call(path)
      rescue PdfText::Error, Errno::ENOENT => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      def clean(text)
        lines = text.to_s.split("\n").map { |line| line.gsub(/[[:blank:]]+/, " ").strip }
        Normalize.nfc(lines.reject(&:empty?).join("\n"))
      end

      def license_override(record)
        klass = record.license_class
        klass == MANIFEST.license_class ? nil : klass
      end

      def metadata_for(record, versions, legacy)
        condition = record.license_condition
        {
          "hrcak_id" => record.id, "landing_url" => record.landing_url, "journal" => record.journal,
          "publisher" => record.publisher, "volume" => record.volume, "issue" => record.issue,
          "issued" => record.issued, "resource_type" => record.resource_type,
          "titles" => record.titles, "authors" => record.creators.map(&:name),
          "creators" => record.creators.map { |c| creator_hash(c) },
          "languages" => record.languages, "inner_languages" => record.inner_languages,
          "pdfs" => versions.map { |v| pdf_hash(v) },
          "abstracts" => record.abstracts, "keywords" => record.subjects,
          "date" => date_for(record), "facets" => facets_for(record),
          "rights" => condition ? condition["label"] : record.journal_rights_statement,
          "license_uri" => condition&.fetch("uri"),
          "legacy_font_repairs" => legacy, "oai_datestamp" => record.datestamp
        }.reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      def creator_hash(creator)
        { "name" => creator.name, "affiliations" => creator.affiliations, "orcid" => creator.orcid }
          .reject { |_k, v| v.nil? || (v.respond_to?(:empty?) && v.empty?) }
      end

      def pdf_hash(version)
        pages = [version.first_page, version.last_page].compact.uniq.join("–")
        { "file_id" => version.file_id, "url" => version.url, "language" => version.language,
          "journal_pages" => pages.empty? ? nil : pages }.compact
      end

      # The issue date's year, EDITION class (see the class comment).
      def date_for(record)
        year = record.issued.to_s[/\A(\d{4})/, 1] or return nil
        { "not_before" => year.to_i, "not_after" => year.to_i, "raw" => record.issued, "class" => "edition",
          "basis" => "the article's issue date (datacite:date Issued), Colloquia Maruliana vol. #{record.volume}" }
      end

      def facets_for(record)
        facets = {}
        facets["genre"] = { "value" => record.resource_type } if record.resource_type
        facets["subject"] = { "values" => record.subjects } unless record.subjects.empty?
        facets
      end
    end
  end
end
