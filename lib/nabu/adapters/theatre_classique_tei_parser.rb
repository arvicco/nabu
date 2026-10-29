# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The Théâtre Classique TEI family (first consumer theatre-classique):
    # one file = one play from Paul Fièvre's theatre-classique.fr, in the
    # site's own pre-P5 TEI dialect — the root is <TEI> (three files still
    # carry the P4-era <TEI.2>), no namespace, acts and scenes as numbered
    # <div1>/<div2>, verse as <l id= part=>, prose as <p> holding <s>
    # sentences, and a header whose source description is the site's own
    # vocabulary (<SourceDesc> with <genre>, <inspiration>, <structure>,
    # <type>, <periode>, <taille>, <permalien>, <keywords>).
    #
    # == The header (read cheaply for discovery, fully at parse)
    #
    # titleStmt: the title verbatim and every <author> with its @type role
    # (texte/text = the playwright, traduction = translator, musique,
    # decor, costume … = collaborators) and @ISNI; "NAME (birth-death)" is
    # split into name + years ("?" uncertainty marks tolerated, a missing
    # parenthesis gives nil years). publicationStmt: <idno> (verbatim —
    # it disagrees with the filename on hundreds of files, so identity is
    # the adapter's call, never this field), <rights>, and the editor/
    # publisher statements (Fièvre's "Texte établi par …" lines).
    #
    # == The front (metadata, then text)
    #
    # docDate@value (the printed edition's year), premiere@date/@location
    # (first performance), the <printer> imprint statement and the
    # <set> location/country (the play's fictional setting — never a
    # provenance claim) are read as metadata. The front is ALSO text: the
    # title page, privilege, dedication, preface, contemporary letters,
    # cast list and setting line are what the printed edition carries.
    #
    # == Blocks (the passage grain)
    #
    # <head>, <l>, <p>, <s>, <stage> and <cell> are blocks; a block nested
    # in another block stays part of its container's text (a prose <p>
    # reads whole with its <s> sentences; an inline <stage> stays in its
    # verse line). Inside the front the site's own leaf vocabulary
    # (titlePart, docDate, docAuthor, printer, premiere, castItem, set,
    # acheveImprime, approbation, signature …) is open-ended, so the rule
    # there is structural: any non-container element that carries text of
    # its own is a block, of its own kind. Containers (the divs, <sp>,
    # <lg>, <poem>, <castList>, <docTitle>, <docImprint>, <performance>,
    # tables) never become blocks; a letter-bearing text run sitting
    # loose in one of them (an untagged stage direction inside an <sp> —
    # 484 runs in 185 files, censused 2026-10-28) is its own block of
    # kind "loose". Loose runs with no letter at all (stray "0", ".",
    # "+" debris) mint nothing. <note> and <speaker> mint no text: notes
    # are the editor's apparatus, the speaker label rides each block of its
    # <sp> as an annotation instead ("who" = sp@who, "speaker" = the label).
    # Verse lines carry "n" (l@id, the play's running line number) and
    # "part" (i/m/f for a line shared across speakers). Underscores joining
    # words ("le_Seigneur") are upstream's own no-break marks, kept verbatim.
    #
    # == Citation (frozen once minted)
    #
    # <zone><div ordinals>.<block ordinal>, the eltec-tei grammar: div
    # ordinals are 1-based among sibling divs (div/div1/div2/div3 alike),
    # joined by "."; the block ordinal counts the non-empty blocks a div
    # owns directly. Ordinals, never div@n: upstream's numbering repeats
    # (SAND_MOLIERE numbers its second act n="1"). Zones: body bare
    # ("1.1.5"), front "f" ("f0.3" outside any div, "f2.1"), back "b".
    class TheatreClassiqueTeiParser
      ROOTS = %w[TEI TEI.2].freeze
      DIVS = %w[div div1 div2 div3].freeze
      BLOCKS = %w[head l p s stage cell].freeze
      SILENT = %w[note speaker pb gap].freeze
      CONTAINERS = %w[front body back sp lg poem castList castGroup docTitle docImprint
                      performance table row].freeze
      ZONES = [["front", "f"], ["body", ""], ["back", "b"]].freeze
      LETTER = /\p{L}/
      # const: the site's SourceDesc vocabulary → metadata keys (<type> is the verse/prose form)
      SOURCE_DESC_KEYS = { "genre" => "genre", "inspiration" => "inspiration", "structure" => "structure",
                           "type" => "form", "periode" => "periode", "taille" => "size" }.freeze

      Author = Data.define(:name, :role, :isni, :birth, :death)

      Header = Data.define(:root, :title, :authors, :idno, :rights, :lang_tag, :statements,
                           :source_desc, :permalink, :keywords)

      Front = Data.define(:doc_date_value, :doc_date_text, :premiere_date, :premiere_location,
                          :premiere_text, :printer, :setting)

      Block = Data.define(:citation, :kind, :text, :who, :speaker, :n, :part)

      Parsed = Data.define(:header, :front, :blocks)

      # The teiHeader alone — discovery's admission rule reads only this.
      def header(path)
        raw = read(path)
        cut = raw.index("</teiHeader>") or raise Nabu::ParseError, "#{path}: no </teiHeader>"
        root = raw[/<(TEI(?:\.2)?)[\s>]/, 1] or raise Nabu::ParseError, "#{path}: no <TEI> root"
        read_header(xml(raw[0, cut + "</teiHeader>".size] + "</#{root}>", path), path)
      end

      def parse(path)
        doc = xml(read(path), path)
        header = read_header(doc, path)
        text = doc.root.at_xpath("text") or raise Nabu::ParseError, "#{path}: no <text>"
        blocks = []
        ZONES.each do |name, zone|
          node = text.at_xpath(name) or next
          walk(node, zone: zone, ords: [], counter: [0, 0], blocks: blocks, speech: nil)
        end
        Parsed.new(header: header, front: read_front(text), blocks: blocks)
      end

      private

      # Through the encoding belt: UTF-8 or a ParseError (the document
      # quarantines). The one file declaring encoding="iso-8859-1"
      # (CORNEILLET_LAODICE, Latin-1 bytes) meets that net — the belt reads
      # UTF-8 only, and this family does not grow a private decoder.
      def read(path) = SourceRead.utf8_file(path, label: "theatre-classique")

      def xml(source, path)
        doc = Nokogiri::XML(source, nil, "UTF-8") { |config| config.strict.nonet }
        doc.remove_namespaces!
        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed TEI: #{e.message}"
      end

      # One container's children in document order: divs recurse with
      # their sibling ordinal and a fresh counter; an <sp> recurses
      # carrying its speaker; containers and text-less wrappers recurse in
      # place; everything else is a block. +counter+ is the owning div's
      # running [block ordinal, child-div ordinal], shared through wrappers
      # (a div nested in an <lg> or <sp> still numbers among its siblings).
      def walk(node, zone:, ords:, counter:, blocks:, speech:)
        node.children.each do |child|
          if child.text? || child.cdata?
            emit(blocks, zone, ords, counter, "loose", squeeze(child.text), speech) if child.text.match?(LETTER)
          elsif child.element?
            name = child.name
            next if SILENT.include?(name)

            if DIVS.include?(name)
              counter[1] += 1
              walk(child, zone: zone, ords: ords + [counter[1]], counter: [0, 0], blocks: blocks, speech: speech)
            elsif name == "sp"
              walk(child, zone: zone, ords: ords, counter: counter, blocks: blocks, speech: child)
            elsif block?(child)
              emit(blocks, zone, ords, counter, name, block_text(child), speech, child)
            else
              walk(child, zone: zone, ords: ords, counter: counter, blocks: blocks, speech: speech)
            end
          end
        end
      end

      def block?(node)
        return true if BLOCKS.include?(node.name)
        return false if CONTAINERS.include?(node.name)

        node.children.any? { |c| (c.text? || c.cdata?) && c.text.match?(LETTER) }
      end

      def emit(blocks, zone, ords, counter, kind, text, speech, node = nil)
        return if text.nil? || text.empty?

        counter[0] += 1
        blocks << Block.new(
          citation: "#{zone}#{ords.empty? ? '0' : ords.join('.')}.#{counter[0]}",
          kind: kind, text: text,
          who: presence(speech&.[]("who")&.strip),
          speaker: speech && squeeze(speech.xpath("speaker").map(&:text).join(" ")),
          n: kind == "l" ? presence(node["id"]) : nil,
          part: kind == "l" ? presence(node["part"]) : nil
        )
      end

      def block_text(node)
        parts = []
        collect_text(node, parts)
        squeeze(parts.join)
      end

      def collect_text(node, parts)
        node.children.each do |child|
          if child.text? || child.cdata?
            parts << child.text
          elsif child.element? && !SILENT.include?(child.name)
            collect_text(child, parts)
          elsif child.element?
            parts << " " # a silent element still separates words
          end
        end
      end

      def read_header(doc, path)
        root = doc.root
        raise Nabu::ParseError, "#{path}: root is <#{root&.name}>, not <TEI>" unless ROOTS.include?(root&.name)

        file_desc = child(child(root, "teiHeader"), "fileDesc") or raise Nabu::ParseError, "#{path}: no fileDesc"
        title_stmt = child(file_desc, "titleStmt")
        title = squeeze(title_stmt&.at_xpath("title")&.text)
        raise Nabu::ParseError, "#{path}: titleStmt carries no title" if title.nil? || title.empty?

        pub = child(file_desc, "publicationStmt")
        source_desc = child(file_desc, "sourceDesc")
        Header.new(
          root: root.name, title: title,
          authors: title_stmt.xpath("author").map { |a| author(a) }.compact,
          idno: presence(squeeze(pub&.at_xpath("idno")&.text)),
          rights: presence(squeeze(pub&.at_xpath("rights")&.text)),
          lang_tag: presence(root["lang"]),
          statements: pub ? pub.xpath("editor|publisher").map { |n| squeeze(n.text) }.reject(&:empty?) : [],
          source_desc: source_desc_fields(source_desc),
          permalink: permalink(source_desc),
          keywords: source_desc ? keywords(source_desc) : []
        )
      end

      # The header's structural children by case-insensitive name: the
      # site's files spell them titleStmt/titlestmt, sourceDesc/SourceDesc
      # (35 files spell titlestmt, 40 publicationstmt, censused 2026-10-28).
      def child(node, name)
        node&.element_children&.find { |c| c.name.casecmp?(name) }
      end

      # "MOLIERE, Jean-Baptiste Poquelin dit (1622-1673)" → name + years;
      # "ROSWITHA (0935?-1000?)" keeps its uncertain years as integers.
      def author(node)
        text = squeeze(node.text)
        return nil if text.empty?

        match = text.match(/\A(.*?)\s*\(\s*([^()]*?)\s*-\s*([^()]*?)\s*\)\s*\z/)
        name, birth, death = match ? [match[1], year(match[2]), year(match[3])] : [text, nil, nil]
        Author.new(name: name, role: presence(node["type"]&.strip), isni: presence(node["ISNI"]&.strip),
                   birth: birth, death: death)
      end

      def year(value)
        digits = value.to_s[/\A(\d{3,4})\??\z/, 1]
        digits && Integer(digits, 10)
      end

      def source_desc_fields(node)
        return {} unless node

        SOURCE_DESC_KEYS.each_with_object({}) do |(element, key), out|
          value = squeeze(node.at_xpath(element)&.text)
          out[key] = value unless value.nil? || value.empty?
        end
      end

      def permalink(node)
        link = node&.at_xpath("permalien") or return nil
        url = squeeze(link.text)
        return nil if url.empty?

        { "url" => url, "shelfmark" => presence(squeeze(link["cote"].to_s)) }.compact
      end

      def keywords(node)
        node.xpath(".//keyword").filter_map do |k|
          value = squeeze(k.text)
          next if value.empty?

          { "type" => presence(k["type"]), "value" => value }.compact
        end
      end

      def read_front(text)
        front = text.at_xpath("front")
        doc_date = front&.at_xpath(".//docDate")
        premiere = front&.at_xpath(".//premiere")
        set = front&.at_xpath(".//set")
        Front.new(
          doc_date_value: presence(doc_date&.[]("value")&.strip),
          doc_date_text: presence(squeeze(doc_date&.text)),
          premiere_date: presence(premiere&.[]("date")&.strip),
          premiere_location: presence(premiere&.[]("location")&.strip),
          premiere_text: presence(squeeze(premiere&.text)),
          printer: imprint(front),
          setting: set && { "location" => presence(set["location"]&.strip),
                            "country" => presence(set["country"]&.strip) }.compact
        )
      end

      # The title-page imprint: <printer>, else the <docImprint>'s <editor>
      # (where the site's later files put "À PARIS, Chez CHARLES DE SERCY …").
      def imprint(front)
        return nil unless front

        [".//printer", ".//docImprint/editor"].each do |xpath|
          text = presence(squeeze(front.at_xpath(xpath)&.text))
          return text if text
        end
        nil
      end

      def squeeze(text)
        return nil if text.nil?

        Normalize.nfc(text.gsub(/[[:space:]]+/, " ").strip)
      end

      def presence(value)
        value if value && !value.empty?
      end
    end
  end
end
