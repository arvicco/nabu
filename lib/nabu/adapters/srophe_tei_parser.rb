# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser family "srophe-tei" (P31-4): the Srophe / Digital Syriac
    # Corpus TEI application (syriaccorpus.org, srophe/syriac-corpus) —
    # their OWN schema, deliberately not EpiDoc, probed against real files
    # and censused over all 632 before this family was shaped.
    #
    # == The layout (censused 2026-07-19, commit 833adc14)
    #
    # One TEI file per document. The header carries identity and rights:
    # publicationStmt idno[@type=URI] (the syriaccorpus.org id),
    # availability/licence (@target + text — CC BY 4.0 on all 632),
    # titleStmt title[@level='a'] (with the syriaca.org work URI in @ref),
    # author (+@ref person URI), revisionDesc/@status (the transcription-
    # quality lane: uncorrectedTranscription … ProofedDigitalEdition), and
    # profileDesc/creation/origDate. The body is divs of 16 censused types
    # (section/chapter/part/text/rubric/title/…) at depth ≤ 3, 1,958 of
    # 6,801 unnumbered, carrying five block shapes: p, ab, lg (stanza of
    # l), standalone l (113k — the poetry corpora), and head. <note>
    # elements (5,417 — apparatus: "sic", manuscript-siglum variants) ride
    # INSIDE p/l. <pb>/<lb>/<milestone> are print-edition breaks. 63 files
    # carry a <front> (editorial summaries).
    #
    # == Flattening rules
    #
    # - A block's text is its flattened content minus <note> subtrees
    #   (apparatus never pollutes text; the notes ride Block#notes
    #   verbatim), whitespace collapsed to single spaces (the files are
    #   pretty-printed; indentation is not text).
    # - lg emits ONE block, its l children joined with "\n" (the line
    #   break is real verse structure); a head inside lg hoists out as its
    #   own head block first. l inside p flattens into the p.
    # - Blocks flattening to nothing (1,389 corpus-wide) are skipped.
    # - <front> is skipped entirely: editorial front matter, not the
    #   transcription.
    # - xml:lang resolves by nearest ancestor (divs carry syr/en; blocks
    #   occasionally syr/en/eng/ar); nil when nothing declares — the
    #   ADAPTER maps raw codes to nabu languages, this family only reports.
    #
    # Format concerns only: urn minting, license classing and language
    # mapping are corpus policy and live in the registering adapter.
    class SropheTeiParser
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze

      # One text-bearing block in document order. +divs+ is the enclosing
      # div path as [type, n] pairs (nil entries preserved — 1,958 divs
      # are unnumbered upstream); +lang+ is the RAW resolved xml:lang.
      Block = Data.define(:tag, :n, :lang, :divs, :text, :notes)

      # One parsed file: header identity + rights + ordered blocks.
      Edition = Data.define(:path, :idno, :license_target, :license_text, :title,
                            :author, :author_ref, :work_ref, :status, :orig_date, :blocks)

      BLOCK_TAGS = %w[p ab l head].freeze
      private_constant :BLOCK_TAGS

      def self.parse(path)
        new(path).parse
      end

      def initialize(path)
        @path = path
      end

      def parse
        doc = read_xml
        body = doc.at_xpath("/tei:TEI/tei:text/tei:body", TEI_NS)
        raise ParseError, "#{@path}: no TEI text body" if body.nil?

        Edition.new(path: @path, blocks: blocks_of(body), **header(doc))
      end

      private

      def read_xml
        document = Nokogiri::XML(File.read(@path), &:strict)
        raise ParseError, "#{@path}: malformed srophe TEI: #{document.errors.first}" unless document.errors.empty?

        document
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{@path}: malformed srophe TEI: #{e.message}"
      end

      # -- header ---------------------------------------------------------

      def header(doc)
        title = doc.at_xpath("//tei:titleStmt/tei:title[@level='a']", TEI_NS) ||
                doc.at_xpath("//tei:titleStmt/tei:title", TEI_NS)
        author = doc.at_xpath("//tei:titleStmt/tei:author", TEI_NS)
        licence = doc.at_xpath("//tei:availability/tei:licence", TEI_NS)
        idno = doc.at_xpath("//tei:publicationStmt/tei:idno[@type='URI']", TEI_NS)
        {
          idno: idno && collapse(idno.text),
          license_target: licence && licence["target"],
          license_text: licence && collapse(licence.text),
          title: title && flatten(title),
          author: author && flatten(author),
          author_ref: author && author["ref"],
          work_ref: title && title["ref"],
          status: doc.at_xpath("//tei:revisionDesc", TEI_NS)&.[]("status"),
          orig_date: orig_date(doc)
        }
      end

      def orig_date(doc)
        node = doc.at_xpath("//tei:profileDesc//tei:origDate", TEI_NS)
        return nil if node.nil?

        date = {}
        %w[type when notBefore notAfter].each do |key|
          date[key] = node[key] if node[key]
        end
        text = flatten(node)
        date["text"] = text unless text.empty?
        date
      end

      # -- blocks ---------------------------------------------------------

      def blocks_of(body)
        blocks = []
        walk(body, [], lang_of(body, nil), blocks)
        blocks
      end

      def walk(element, divs, lang, blocks)
        element.element_children.each do |child|
          case child.name
          when "div"
            walk(child, divs + [[child["type"], child["n"]]], lang_of(child, lang), blocks)
          when "lg"
            stanza(child, divs, lang_of(child, lang), blocks)
          when *BLOCK_TAGS
            emit(child, tag: child.name, divs: divs, lang: lang, blocks: blocks)
          end
        end
      end

      # A stanza: heads hoist out as their own blocks, then the lg emits
      # once with its lines joined by newlines (real verse structure).
      def stanza(elem, divs, lang, blocks)
        elem.element_children.select { |c| c.name == "head" }.each do |head|
          emit(head, tag: "head", divs: divs, lang: lang_of(head, lang), blocks: blocks)
        end
        lines = elem.element_children.select { |c| c.name == "l" }
                                     .map { |line| flatten(line) }.reject(&:empty?)
        return if lines.empty?

        blocks << Block.new(tag: "lg", n: elem["n"], lang: lang_of(elem, lang), divs: divs,
                            text: lines.join("\n"), notes: notes_of(elem))
      end

      def emit(elem, tag:, divs:, lang:, blocks:)
        text = flatten(elem)
        return if text.empty? # 1,389 blocks corpus-wide flatten to nothing

        blocks << Block.new(tag: tag, n: elem["n"], lang: lang_of(elem, lang), divs: divs,
                            text: text, notes: notes_of(elem))
      end

      def lang_of(elem, inherited)
        elem["xml:lang"] || inherited
      end

      def notes_of(elem)
        elem.xpath(".//tei:note", TEI_NS).filter_map do |note|
          text = collapse(note.text)
          text unless text.empty?
        end
      end

      # Flattened text minus note subtrees, whitespace collapsed.
      def flatten(elem)
        parts = []
        gather(elem, parts)
        collapse(parts.join)
      end

      def gather(node, parts)
        node.children.each do |child|
          if child.text?
            parts << child.text
          elsif child.element? && child.name != "note"
            gather(child, parts)
          end
        end
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
