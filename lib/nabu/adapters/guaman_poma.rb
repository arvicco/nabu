# frozen_string_literal: true

require_relative "poma_xhtml_parser"

module Nabu
  module Adapters
    # guaman-poma — Felipe Guaman Poma de Ayala, El primer nueva corónica y
    # buen gobierno (1615; the autograph, Copenhagen, Royal Danish Library
    # GKS 2232 4º), in the Library's digital edition (poma.kb.dk; P117-5).
    #
    # == The edition (recorded as metadata, read 2026-10-11)
    #
    # The site's "Sobre la transcripción" (Rolena Adorno, September 2004):
    # the transcription rests on Adorno's 1977 examination of the autograph
    # and the work of John V. Murra, Jorge L. Urioste and Adorno for their
    # editions of 1980 (México: Siglo Veintiuno) and 1987 (Madrid:
    # Historia 16); after the 2001 digitization Ivan Boserup and Adorno
    # revised it against the digital facsimile — this is the corrected
    # 1987 transcription, presented in the names of Murra, Urioste and
    # Adorno. The critical notes reproduce 1980/1987; the only new notes
    # are Boserup's and Adorno's ("[2004:]").
    #
    # == Shape (censused over the whole crawl, 2026-10-11)
    #
    # 1,190 pages (titlepage + 1..1189 — the navigation's last-page arrow;
    # PomaFetch), one static XHTML file each. Document = page (urn
    # :<permalink id> — "titlepage", "1" … "1189"); passage = one
    # transcription paragraph (urn :<id>:<n>), the poma-xhtml family's
    # reading (editorial insertions and note markers out of the text, the
    # edition's display reading kept as edition_text). Census: see
    # docs/02-sources.md row 255.
    #
    # == Language — declared coarse
    #
    # Mostly Spanish, with real Quechua passages (the songs of pp. 316–
    # 319, prayers, sermons, titles) and some Aymara and Latin. The
    # edition tags NO language: Quechua, Aymara and Latin are italicized
    # alike (<em>), so every passage is minted spa, the italic runs ride
    # per passage as "italic", and each page's modern-orthography list of
    # its Andean terms (the edition's "/ taki / qhapaq apukuna /" line)
    # rides as andean_terms. A qwc (Classical Quechua) lane would need a
    # language decision per italic run — not machine-recoverable from the
    # markup; declared, not guessed.
    #
    # == Axes
    #
    # Date: the autograph's 1615 (the edition's own title, "Nueva corónica
    # y buen gobierno (1615)") on every page → MetadataDates :structured.
    # Places: unplaced — the chronicle names hundreds of Andean places in
    # prose; the edition carries no place field (its onomastic index is a
    # separate site section, not crawled).
    #
    # == License
    #
    # The Royal Danish Library's project page (poma.kb.dk/permalink/2006/
    # poma/info/es/project/project.htm, read 2026-10-11), verbatim: "Esta
    # obra ha sido identificada como libre de restricciones conocidas bajo
    # la ley derecho autoral, incluyendo todos los derechos conexos. Puede
    # copiar, modificar, distribuir e interpretar la obra, incluso para
    # fines comerciales, todo esto sin pedir permiso. Recuerde siempre dar
    # crédito al autor." — linking creativecommons.org/publicdomain/mark/
    # 1.0/deed.es → open. The statement is unqualified; the transcription
    # and apparatus derive from the Murra/Adorno/Urioste editions (above)
    # — recorded, the KB's declaration is the grant basis.
    class GuamanPoma < Nabu::Adapter
      BASE_URL = "https://poma.kb.dk/permalink/2006/poma"
      URN_PREFIX = "urn:nabu:guaman-poma:"
      LANGUAGE = "spa"
      WORK_TITLE = "Nueva corónica y buen gobierno"

      EDITION = "the Royal Danish Library's digital edition (poma.kb.dk, 2001; revised 2004): the " \
                "transcription of John V. Murra, Rolena Adorno and Jorge L. Urioste (México: Siglo " \
                "Veintiuno, 1980; Madrid: Historia 16, 1987), corrected against the autograph's " \
                "digital facsimile by Rolena Adorno and Ivan Boserup"

      DATE = { "not_before" => 1615, "not_after" => 1615,
               "raw" => "the autograph, GKS 2232 4º — the edition's title: " \
                        "Nueva corónica y buen gobierno (1615)" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "guaman-poma",
        name: "Guaman Poma, Nueva corónica y buen gobierno (Royal Danish Library digital edition)",
        license: "Public Domain Mark 1.0 — the Royal Danish Library's project page, verbatim: \"Esta obra " \
                 "ha sido identificada como libre de restricciones conocidas bajo la ley derecho autoral, " \
                 "incluyendo todos los derechos conexos. Puede copiar, modificar, distribuir e interpretar " \
                 "la obra, incluso para fines comerciales, todo esto sin pedir permiso. Recuerde siempre " \
                 "dar crédito al autor.\" (creativecommons.org/publicdomain/mark/1.0). Credit: Felipe " \
                 "Guaman Poma de Ayala; transcription Murra, Adorno, Urioste (1980/1987), corrected by " \
                 "Adorno and Boserup; Det Kgl. Bibliotek, GKS 2232 4º.",
        license_class: "open",
        upstream_url: "#{BASE_URL}/info/es/frontpage.htm",
        parser_family: "poma-xhtml"
      )

      def self.manifest = MANIFEST

      # No git repo — the probe GETs one stable page (reachability only;
      # the edition serves no Last-Modified to drift on).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "poma/1/es/text", zip_url: Nabu::PomaFetch.page_url(BASE_URL, "1"),
          metadata_url: nil, state_subdir: "", state_file: Nabu::PomaFetch::STATE_FILE
        )]
      end

      # +delay+ exists for the WebMock'd tests (0); real syncs keep the
      # polite default.
      def initialize(delay: Nabu::PomaFetch::DELAY)
        super()
        @delay = delay
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::PomaFetch.sync!(
          base_url: BASE_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          delay: @delay, progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: fetch_notes(result))
      rescue Nabu::PomaFetch::Error => e
        raise Nabu::FetchError, "guaman-poma fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "*.html"))
           .select { |path| Nabu::PomaFetch.record?(File.basename(path)) }
           .sort_by { |path| sort_key(File.basename(path, ".html")) }
           .each do |path|
             id = File.basename(path, ".html")
             yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{id}",
                                         path: File.expand_path(path), metadata: { "permalink_id" => id })
           end
      end

      def parse(document_ref)
        id = document_ref.metadata.fetch("permalink_id") { File.basename(document_ref.path, ".html") }
        page = PomaXhtmlParser.new.parse(document_ref.path)
        if page.paragraphs.empty?
          # p. 1002 (census): the Mapa Mundi's second half, "For the
          # transcription of page 1002, see page 1001."
          raise Nabu::DocumentSkipped, "#{document_ref.id}: no transcription paragraph" \
                                       "#{" (transcribed with page #{page.see_page})" if page.see_page}"
        end

        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: title_for(page), metadata: metadata_for(id, page))
        page.paragraphs.each_with_index do |paragraph, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE,
                                        text: Normalize.nfc(paragraph.text), sequence: index + 1,
                                        annotations: annotations_for(paragraph))
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def sort_key(id) = id == Nabu::PomaFetch::TITLEPAGE ? -1 : id.to_i

      def title_for(page)
        label = "#{WORK_TITLE}, p. #{page.page}"
        page.section ? Normalize.nfc("#{label} — #{page.section}") : label
      end

      def metadata_for(id, page)
        meta = { "permalink" => Nabu::PomaFetch.page_url(BASE_URL, id), "page" => page.page,
                 "gp_page" => page.gp_page, "textdesc" => page.textdesc, "section" => page.section,
                 "drawing" => page.drawing, "image" => page.image, "date" => DATE, "edition" => EDITION,
                 "manuscript" => "Copenhagen, Det Kgl. Bibliotek, GKS 2232 4º",
                 "author" => "Felipe Guaman Poma de Ayala" }
        meta["page_notes"] = page.page_notes unless page.page_notes.empty?
        meta["andean_terms"] = page.andean_terms unless page.andean_terms.empty?
        meta["glosses"] = page.glosses unless page.glosses.empty?
        meta["commentary"] = page.commentary unless page.commentary.empty?
        deep_nfc(meta.compact)
      end

      def annotations_for(paragraph)
        annotations = {}
        edition = Normalize.nfc(paragraph.edition_text)
        annotations["edition_text"] = edition unless edition == Normalize.nfc(paragraph.text)
        annotations["italic"] = paragraph.italic unless paragraph.italic.empty?
        annotations["editorial"] = paragraph.editorial unless paragraph.editorial.empty?
        annotations["notes"] = paragraph.notes unless paragraph.notes.empty?
        annotations["translation"] = paragraph.translation if paragraph.translation
        deep_nfc(annotations)
      end

      def fetch_notes(result)
        base = "Guaman Poma navigation verified (#{result.manifest_count} pages; #{result.fetched} fetched, " \
               "#{result.cached} already on disk)"
        missing = ("#{result.missing.size} page(s) 404 upstream (#{result.missing.first(3).join(', ')})" unless
          result.missing.empty?)
        [base, missing, attic_notes(result.atticked)].compact.join("; ")
      end

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Hash then value.transform_values { |v| deep_nfc(v) }
        when Array then value.map { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
