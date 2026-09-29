# frozen_string_literal: true

require "digest"
require "fileutils"
require "nokogiri"
require_relative "../url_download"

module Nabu
  module Adapters
    # IEDC — the Invisible East Digital Corpus (P107-2, Q96.1): 1,316
    # documentary items of the medieval Islamicate East (Bamiyan and
    # Firuzkuh papers, Khotan documents, Bactrian economic documents …)
    # from ONE versioned Zenodo XML (doi 10.5281/zenodo.20490276,
    # CC BY 4.0; invisible-east.org, University of Oxford).
    #
    # == The honest text census (2026-09-28, v1.1)
    #
    # 481 items carry folio TRANSCRIPTIONS (embedded-HTML ordered lists,
    # one <li> per manuscript line; transliterations accompany some of
    # them — transcription wins, transliteration is a defensive
    # fallback layer only); the
    # remainder — including nearly the whole 552-item Khotanese slice —
    # are METADATA-ONLY catalog records (metadata "text_state" =
    # "catalog-record"), ingested for their axis metadata: typed date
    # strings with parenthesized ISO substrings ("… (1183-10)" →
    # metadata date_iso, the timeline lane), toponym lists with
    # latitude/longitude fields, editorial grades (Gold/Silver/Bronze →
    # the grade facet), document types, shelfmarks and collections.
    # Folio TRANSLATIONS (283 items) are a DECLARED v1 residue — not
    # served, recorded here, a future packet.
    #
    # == Identity / passages
    #
    # urn:nabu:iedc:<uri.downcase> (IEDC0201 → iedc0201 — the corpus's
    # own stable ids); passages cite :f<folio>.l<line> in folio order;
    # transliteration-only folios mark their passages with the
    # annotations layer flag. primaryLanguage maps to ISO codes
    # (LANGUAGES — an unmapped value raises: mislabeling a shelf is
    # worse than a loud parse).
    #
    # == fetch
    #
    # One versioned file from Zenodo (ZipFetch.download! shape); the
    # filename carries the upstream version stamp and is discovered by
    # glob, so a new deposit lands beside the old and wins by name sort.
    class Iedc < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/api/records/20490276"
      FILE_GLOB = "iedc_*.xml"
      URN_PREFIX = "urn:nabu:iedc:"

      # primaryLanguage → ISO 639-3 (script parentheticals recorded in
      # metadata "script_note", never folded into the code).
      LANGUAGES = {
        "Khotanese" => "kho", "New Persian" => "fa", "Middle Persian" => "pal",
        "Sogdian" => "sog", "Arabic" => "ara", "Judeo-Persian" => "jpr",
        "Bactrian" => "xbc", "Hebrew" => "heb", "Sanskrit" => "san",
        "Old Uyghur" => "oui", "Chinese" => "zho"
      }.freeze

      # "… (1183-10)" / "… (1183)" — the machine substring inside the
      # prose date string; absent parenthetical = honest date_text only.
      DATE_ISO = /\((\d{3,4}(?:-\d{2})?(?:-\d{2})?)\)\s*\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "iedc",
        name: "Invisible East Digital Corpus (Oxford) — documentary Islamicate East",
        license: "CC BY 4.0 (the Zenodo record's license; \"The Creative Commons Attribution " \
                 "license allows re-distribution and re-use of a licensed work on the condition " \
                 "that the creator is appropriately credited\"). Credit the Invisible East " \
                 "programme, University of Oxford (invisible-east.org), doi " \
                 "10.5281/zenodo.20490276, and each item's principal editor as recorded",
        license_class: "open",
        upstream_url: "https://invisible-east.org/",
        parser_family: "iedc-xml"
      )

      def self.manifest = MANIFEST

      # UrlDownload keeps no state file — the probe HEADs the stable
      # upstream URL for liveness only; drift honestly reads unknown.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "dataset xml", zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = corpus_path(workdir) or return
        items(path).each_with_index do |item, index|
          uri = text_at(item, "uri").strip
          next if uri.empty?

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{uri.downcase}",
            path: path, metadata: { "index" => index, "uri" => uri }
          )
        end
      end

      def parse(document_ref)
        item = items(document_ref.path)[document_ref.metadata.fetch("index")] or
          raise Nabu::ParseError, "#{document_ref.id}: item index out of range (stale ref?)"
        uri = text_at(item, "uri").to_s.strip
        unless "#{URN_PREFIX}#{uri.downcase}" == document_ref.id
          raise Nabu::ParseError, "#{document_ref.id}: item order drifted (found #{uri})"
        end

        language = language_for(item, document_ref)
        passages = passages_for(document_ref.id, item, language)
        metadata = metadata_for(item)
        metadata["text_state"] = passages.empty? ? "catalog-record" : "text"
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          canonical_path: document_ref.path,
          title: title_for(item), metadata: metadata
        )
        passages.each { |passage| document << passage }
        document
      end

      # The versioned corpus file, straight from the Zenodo record's
      # files API (the burman-concordance UrlDownload shape). The
      # filename carries the upstream version stamp.
      FILE_URL = "https://zenodo.org/api/records/20490276/files/iedc_2026-06-01_14-07.xml/content"
      FILE_NAME = "iedc_2026-06-01_14-07.xml"

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        target = File.join(workdir, FILE_NAME)
        downloaded = Nabu::UrlDownload.new.fetch(FILE_URL, dir: workdir)
        FileUtils.mv(downloaded, target) unless downloaded == target
        Nabu::FetchReport.new(sha: Digest::SHA256.file(target).hexdigest, fetched_at: Time.now,
                              notes: ["#{FILE_NAME} (#{File.size(target)} bytes)"])
      end

      private

      # The newest corpus file by name (the upstream stamps versions in
      # the filename).
      def corpus_path(workdir)
        Dir.glob(File.join(workdir, FILE_GLOB)).max
      end

      # Item list, memoized per (path, mtime): discover + 1,316 parses
      # must not re-read a 6.5 MB DOM per document.
      def items(path)
        key = [path, File.mtime(path)]
        return @items_cache if defined?(@items_key) && @items_key == key

        @items_key = key
        document = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict)
        @items_cache = document.root.xpath("item")
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: #{e.message.lines.first&.strip}"
      end

      def language_for(item, document_ref)
        raw = text_at(item, "primaryLanguage").to_s.strip
        name = raw.sub(/\s*\(.*\z/, "")
        LANGUAGES.fetch(name) do
          raise Nabu::ParseError, "#{document_ref.id}: unmapped primaryLanguage #{raw.inspect} — " \
                                  "extend Iedc::LANGUAGES deliberately, never guess"
        end
      end

      def title_for(item)
        shelfmark = text_at(item, "shelfmark").to_s.strip
        group = text_at(item, "group").to_s.strip
        title = [group.empty? ? nil : group, shelfmark.empty? ? nil : shelfmark].compact.join(" — ")
        title.empty? ? nil : Normalize.nfc(title)
      end

      def metadata_for(item)
        meta = { "uri" => text_at(item, "uri").to_s.strip }
        { "shelfmark" => "shelfmark", "collection" => "collection", "group" => "group",
          "classification" => "classification", "document_type" => "documentType",
          "document_subtype" => "documentSubtype", "summary" => "contentSummary",
          "principal_editor" => "principalEditor", "permalink" => "permalink",
          "source_of_data" => "sourceOfData" }.each do |key, tag|
          value = text_at(item, tag).to_s.strip
          meta[key] = Normalize.nfc(value) unless value.empty?
        end
        script = text_at(item, "primaryLanguage").to_s[/\(([^)]*)\)/, 1]
        meta["script_note"] = script if script
        add_dates(meta, item)
        add_toponyms(meta, item)
        add_facets(meta)
        meta
      end

      def add_dates(meta, item)
        raw = text_at(item, "dates").to_s.strip
        return if raw.empty?

        meta["date_text"] = Normalize.nfc(raw)
        iso = raw[DATE_ISO, 1]
        meta["date_iso"] = iso if iso
      end

      def add_toponyms(meta, item)
        topos = item.xpath("toponyms/item").filter_map do |topo|
          name = text_at(topo, "name").to_s.strip
          next if name.empty?

          entry = { "name" => Normalize.nfc(name) }
          %w[latitude longitude alternativeReadings].each do |tag|
            value = text_at(topo, tag).to_s.strip
            entry[tag] = value unless value.empty?
          end
          entry
        end
        meta["toponyms"] = topos unless topos.empty?
      end

      # The FacetBuilder contract: metadata "facets" is facet =>
      # {"value" => ...} — insert_facets SILENTLY drops flat strings
      # (the P107 first refresh projected zero iedc rows before this
      # took the real shape). grade = the bare word (the full
      # classification string stays in metadata); doctype = the
      # upstream documentType verbatim.
      def add_facets(meta)
        facets = {}
        if (grade = meta["classification"]&.slice(/\A(Gold|Silver|Bronze)/, 1))
          facets["grade"] = { "value" => grade }
        end
        facets["doctype"] = { "value" => meta["document_type"] } if meta["document_type"]
        meta["facets"] = facets unless facets.empty?
      end

      def passages_for(urn, item, language)
        passages = []
        item.xpath("folios/item").each_with_index do |folio, folio_index|
          layer, body = folio_text(folio)
          next if body.nil?

          side = text_at(folio, "side").strip
          lines_for(body).each_with_index do |line, line_index|
            annotations = {}
            annotations["layer"] = layer if layer != "transcription"
            annotations["side"] = side unless side.empty?
            passages << Nabu::Passage.new(
              urn: "#{urn}:f#{folio_index + 1}.l#{line_index + 1}",
              language: language, text: line, sequence: passages.size + 1,
              annotations: annotations
            )
          end
        end
        passages
      end

      # transcription wins; transliteration is the fallback layer.
      def folio_text(folio)
        %w[transcription transliteration].each do |field|
          raw = text_at(folio, field).to_s
          return [field, raw] unless raw.strip.empty?
        end
        nil
      end

      # The embedded-HTML line list: one <li> per manuscript line; a
      # body without <li> grain yields its whole text as one line.
      def lines_for(body)
        fragment = Nokogiri::HTML::DocumentFragment.parse(body)
        lines = fragment.css("li").map { |li| clean(li.text) }.reject(&:empty?)
        return lines unless lines.empty?

        text = clean(fragment.text)
        text.empty? ? [] : [text]
      end

      # Direct-child element text (Nokogiri; nil-safe).
      def text_at(node, tag)
        node.at_xpath(tag)&.text.to_s
      end

      def clean(text)
        Normalize.nfc(text.gsub(/ /, " ").gsub(/\s+/, " ").strip)
      end
    end
  end
end
