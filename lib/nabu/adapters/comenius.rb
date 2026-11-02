# frozen_string_literal: true

require "nokogiri"
require "digest"

module Nabu
  module Adapters
    # Comenius — the TEI editions of Jan Amos Komenský's Czech (and one
    # Dutch) devotional writings of 1619–1660, encoded by Tomáš Havelka
    # (Filosofický ústav AV ČR) on the text of Dílo Jana Amose Komenského
    # vol. 3 (ed. A. Molnár, V. Petráčková et al., Praha 1978) and deposited
    # on LINDAT/CLARIAH-CZ as twelve items (accessioned 2026-10-22; hdl
    # 20.500.12800/1-6182, 1-6274…6276, 1-6278, 1-6283…6289): Truchlivý I–IV,
    # Listové do nebe (1619), Přemyšlování o dokonalosti křesťanské,
    # Nedobytedlný hrad, Pres boží, O sirobě, Centrum securitatis, the Dutch
    # Bazuine des genaden jaar (1632) and Kšaft umírající matky Jednoty
    # bratrské (1650).
    #
    # == The delivery grains
    #
    # Each LINDAT item serves ONE bitstream (local.files.count 1, "1;TEI
    # XML"): the work's TEI file. Document = the work. Inside a file:
    #
    #   front/titlePage  the historic print's title page — rides metadata
    #                    (title_page), not a passage
    #   body p / head    the edition text → one passage per block
    #   back             the 1978 editors' "Informace o díle" / Latin notes —
    #                    modern editorial prose, REJECTED from the text
    #
    # The edition's critical apparatus (<app><lem wit="#DJAK03">…</lem>
    # <rdg wit="#St">…</rdg></app>) reads through the lemma; the witness
    # readings ride the passage's `apparatus` annotation, never the text.
    # Footnote glosses (<note place="bottom">) and the print's marginal
    # notes (<add place="margin">) ride annotations too. The DJAK.xsl
    # stylesheet the files reference is not deposited. Reconciliation: 12
    # items = 12 files = 12 documents (the volume's 05_ slot is not
    # deposited).
    #
    # == Identity
    #
    #   document urn  urn:nabu:comenius:<work slug>   (the filename's work
    #                 part: 06_DJAK_03_Pres_Bozi → pres-bozi)
    #   passage urn   <document-urn>:<n>             (body block ordinal)
    #
    # The DJAK page (pb ed="DJAK03"/"DJAK3") a block starts on rides
    # annotations["page"], the historic print's page (pb ed="T1624",
    # "#St"…) annotations["print_page"] with its edition siglum.
    #
    # == Language
    #
    # The TEI root's xml:lang (cs ×11, nl ×1), overridden per block by the
    # nearest xml:lang (the Latin prefaces); two-letter la → the house lat.
    #
    # == License
    #
    # CC BY 4.0 on every item (dc.rights verbatim "Creative Commons -
    # Attribution 4.0 International (CC BY 4.0)", dc.rights.uri
    # creativecommons.org/licenses/by/4.0/, label PUB) — verified on all
    # twelve 2026-11-02. → attribution.
    class Comenius < Nabu::Adapter
      BITSTREAM_URL = "https://lindat.mff.cuni.cz/repository/server/api/core/bitstreams/%s/content"
      URN_PREFIX = "urn:nabu:comenius:"

      # LINDAT handle suffix → [bitstream uuid, filename] (census 2026-11-02).
      ITEMS = {
        "1-6182" => ["1dfed25c-315a-4c71-9b36-5cb70d6bfd70", "10_DJAK_03_Ksaft.xml"],
        "1-6274" => ["37ac4340-2372-47dd-9a07-ad9216d0f22e", "01_DJAK_03_Truchlivy_I.xml"],
        "1-6275" => ["efdda553-0f9e-4fd4-936f-3f0cdf566d42", "01_DJAK_03_Truchlivy_II.xml"],
        "1-6276" => ["9fa58d3e-c9f2-4753-a96b-911509f71518", "01_DJAK_03_Truchlivy_III.xml"],
        "1-6278" => ["2f9fc293-6005-4a2b-9542-0a5e4eaacd4f", "01_DJAK_03_Truchlivy_IV.xml"],
        "1-6283" => ["7c75478a-f1ae-42e7-9c67-319c3fc03c28", "02_DJAK_03_Listove.xml"],
        "1-6284" => ["e92a8816-e189-4f8c-819f-a83b2d65bbdf", "03_DJAK_03_Premyslovani.xml"],
        "1-6285" => ["74a305ab-c0df-4a64-a23c-6e95f2a133b3", "09_DJAK_03_Bazuine.xml"],
        "1-6286" => ["d808f065-ffd6-41fd-a89c-a47b42b574fd", "08_DJAK_03_Centrum.xml"],
        "1-6287" => ["7fe50c2e-e2d2-4ff9-9902-91255ad46c56", "07_DJAK_03_O_sirobe.xml"],
        "1-6288" => ["5695f6cd-95fd-443b-b9bb-2a2d5ebe934b", "06_DJAK_03_Pres_Bozi.xml"],
        "1-6289" => ["70497548-0a88-4f47-8124-8ed135ade2ac", "04_DJAK_03_Nedobytedlny_hrad.xml"]
      }.freeze

      FILE_PATTERN = /\A\d{2}_DJAK_\d{2}_(?<work>.+)\.xml\z/
      NS = { "t" => "http://www.tei-c.org/ns/1.0" }.freeze
      XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
      LANGUAGES = { "la" => "lat" }.freeze
      # Subtrees that never enter a block's reading text.
      SKIPPED = %w[rdg note anchor label].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "comenius",
        name: "Comenius — TEI editions of J. A. Komenský's Czech writings (DJAK 3, LINDAT)",
        license: "CC BY 4.0 — every LINDAT item's dc.rights verbatim \"Creative Commons - " \
                 "Attribution 4.0 International (CC BY 4.0)\" (verified on all twelve, 2026-11-02). " \
                 "Cite: Komenský, J. A.; Havelka, T. (TEI), Filosofický ústav AV ČR, LINDAT/CLARIAH-CZ " \
                 "hdl 20.500.12800/1-6182…6289, on the text of Dílo Jana Amose Komenského 3 (Praha 1978)",
        license_class: "attribution",
        upstream_url: "https://hdl.handle.net/20.500.12800/1-6283",
        parser_family: "comenius-tei"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        ITEMS.map do |handle, (uuid, filename)|
          Nabu::Adapter::HttpProbeTarget.new(
            label: filename, zip_url: format(BITSTREAM_URL, uuid), metadata_url: nil,
            state_subdir: handle, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      def self.slug_for(filename)
        match = FILE_PATTERN.match(filename) or return nil
        match[:work].downcase.tr("_", "-")
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        refs = Dir.glob(File.join(workdir, "*", "*_DJAK_*.xml")).filter_map do |path|
          slug = self.class.slug_for(File.basename(path)) or next
          Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{slug}", path: File.expand_path(path),
                                metadata: { "handle" => "20.500.12800/#{File.basename(File.dirname(path))}" })
        end
        refs.sort_by(&:id).each(&block)
      end

      def parse(document_ref)
        xml = Nokogiri::XML(SourceRead.utf8_file(document_ref.path, label: "comenius"), &:strict)
        root = xml.at_xpath("/t:TEI", NS) or raise ParseError, "#{document_ref.path}: not a TEI file"
        build_document(xml, root, document_ref)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{document_ref.path}: malformed TEI: #{e.message}"
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # One FileFetch per LINDAT item into its own handle subdirectory (so
      # each item's single-file retention contract stays independent).
      def fetch(workdir, progress: nil, force: false)
        shas = ITEMS.map do |handle, (uuid, filename)|
          dir = File.join(workdir, handle)
          Nabu::FileFetch.sync!(
            url: format(BITSTREAM_URL, uuid), dir: dir, filename: filename,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, handle), progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          ).sha
        end
        FetchReport.new(sha: Digest::SHA256.hexdigest(shas.join), fetched_at: Time.now,
                        notes: "#{ITEMS.size} LINDAT items")
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "comenius fetch failed into #{workdir}: #{e.message}"
      end

      private

      def build_document(xml, root, document_ref)
        language = language_code(root.attribute_with_ns("lang", XML_NAMESPACE)&.value) || "cs"
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: document_title(xml),
          canonical_path: document_ref.path, metadata: document_metadata(xml, document_ref)
        )
        blocks(xml).each do |block|
          text, annotations = read_block(block)
          next if text.empty?

          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{document.size + 1}", language: block_language(block, language),
            text: Normalize.nfc(text), annotations: annotations, sequence: document.size
          )
        end
        raise ParseError, "#{document_ref.path}: no text blocks in <body>" if document.empty?

        document
      end

      def blocks(xml)
        xml.xpath("//t:text/t:body//*[self::t:p or self::t:head]" \
                  "[not(ancestor::t:note or ancestor::t:rdg or ancestor::t:add or ancestor::t:p or ancestor::t:head)]",
                  NS)
      end

      def document_title(xml)
        title = flat_text(xml.at_xpath("//t:titleStmt/t:title", NS))
        title && Normalize.nfc(title)
      end

      def document_metadata(xml, document_ref)
        when_year = xml.at_xpath("//t:front//t:docDate/t:date/@when", NS)&.value
        date_raw = squeeze(xml.at_xpath("//t:front//t:docDate/t:date", NS)&.text)
        editors = xml.xpath("//t:editionStmt/t:respStmt[1]/t:name", NS).map { |name| squeeze(name.text) }
        {
          "handle" => document_ref.metadata["handle"],
          "author" => "Jan Amos Komenský",
          "edition" => squeeze(xml.at_xpath("//t:editionStmt/t:edition", NS)&.text),
          "edition_pages" => squeeze(xml.at_xpath("//t:publicationStmt//t:bibl", NS)&.text),
          "editors" => (editors unless editors.empty?),
          "tei_encoding" => squeeze(xml.at_xpath("//t:editionStmt/t:respStmt[2]/t:name", NS)&.text),
          "title_page" => title_page(xml),
          "witnesses" => witnesses(xml),
          "date" => date_envelope(when_year, date_raw)
        }.compact.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end

      # The title page's own docDate: @when is the year (the P81-1
      # structured envelope, one-year), the printed wording rides raw
      # verbatim ("LÉTA PÁNĚ MDCXIX", "kolem 1623"). Never guessed: no
      # @when, no envelope.
      def date_envelope(when_year, raw)
        year = Integer(when_year.to_s[/\A\d{3,4}/] || "", 10, exception: false)
        return nil if year.nil?

        { "not_before" => year, "not_after" => year, "raw" => raw }.compact
      end

      def title_page(xml)
        parts = xml.xpath("//t:front/t:titlePage//t:titlePart", NS).map { |part| flat_text(part) }.compact
        parts.empty? ? nil : parts.join(" — ")
      end

      def witnesses(xml)
        list = xml.xpath("//t:sourceDesc/t:listWit/t:witness", NS).to_h do |witness|
          [witness.attribute_with_ns("id", XML_NAMESPACE)&.value, squeeze(witness.text)]
        end.compact
        list.empty? ? nil : list
      end

      # [reading text, annotations] for one block.
      def read_block(block)
        state = { text: +"", apparatus: [], notes: [], margin: [] }
        walk(block, state)
        annotations = {}
        page = preceding_page(block, djak: true)
        annotations["page"] = page["n"] if page
        print = preceding_page(block, djak: false)
        annotations["print_page"] = { "n" => print["n"], "ed" => print["ed"].to_s.strip }.compact if print
        annotations["block"] = block.name
        { apparatus: "apparatus", notes: "notes", margin: "marginalia" }.each do |key, name|
          annotations[name] = state[key] unless state[key].empty?
        end
        [squeeze(state[:text]).to_s, annotations]
      end

      def walk(node, state)
        node.children.each do |child|
          if child.text?
            state[:text] << child.text
          elsif child.element?
            visit(child, state)
          end
        end
      end

      def visit(element, state)
        case element.name
        when "rdg" then record_reading(element, state)
        when "note" then (text = squeeze(element.text)) && (state[:notes] << Normalize.nfc(text))
        when "add"
          return walk(element, state) unless element["place"] == "margin"

          (text = squeeze(element.text)) && (state[:margin] << Normalize.nfc(text))
        when "lb" then state[:text] << " " unless element["break"] == "no"
        when *SKIPPED, "pb" then nil
        else walk(element, state)
        end
      end

      def record_reading(rdg, state)
        lem = rdg.parent&.at_xpath("./t:lem", NS)
        state[:apparatus] << {
          "lem" => squeeze(lem&.text), "wit" => rdg["wit"], "rdg" => squeeze(rdg.text)
        }.compact.transform_values { |value| Normalize.nfc(value) }
      end

      # The page a block STARTS on: the nearest preceding pb of the kind
      # (DJAK edition vs historic print), else — a block opening its
      # file's first page — the first such pb inside it.
      def preceding_page(block, djak:)
        test = "contains(@ed,'DJAK') or contains(@edRef,'DJAK')"
        test = "not(#{test})" unless djak
        block.at_xpath("preceding::t:pb[#{test}][1]", NS) || block.at_xpath(".//t:pb[#{test}][1]", NS)
      end

      def block_language(block, default)
        code = block.at_xpath("ancestor-or-self::*[@xml:lang][1]/@xml:lang", NS)&.value
        language_code(code) || default
      end

      def language_code(code)
        return nil if code.to_s.strip.empty?

        LANGUAGES.fetch(code.strip, code.strip)
      end

      # Header text with <lb/> read as a space (the titles break lines).
      def flat_text(node)
        return nil if node.nil?

        copy = node.dup
        copy.xpath(".//t:lb", NS).each { |lb| lb.replace(" ") }
        squeeze(copy.text)
      end

      def squeeze(text)
        value = text.to_s.gsub(/\s+/, " ").strip
        value.empty? ? nil : value
      end
    end
  end
end
