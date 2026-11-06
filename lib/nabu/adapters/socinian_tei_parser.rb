# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # The parser family for the Socinian correspondence's teiCorpus letter
    # files (Die sozinianischen Briefwechsel, AdW Mainz — ediarum/TELOTA
    # TEI P5). One file is ONE letter as the edition publishes it:
    #
    #   teiCorpus                        the edition's corpus header
    #     TEI n="cover_letter"           the letter: titleStmt + correspDesc
    #       TEI n="reference_witness"    the edition's base witness (print or
    #       TEI (corresp=…)              manuscript), each with its OWN header:
    #                                    licence, langUsage, classCode,
    #                                    revisionDesc — and its <text>
    #     TEI n="attachment"             an enclosure (Beilage), same shape
    #       TEI n="reference_witness" …
    #
    # The parser is structural and source-agnostic about policy: it returns
    # every component with every witness header read and the text blocks of
    # every witness; which witness is THE text, which attachments a file
    # holds, and which licences are acceptable are the adapter's rules.
    #
    # == Text rendering (the reading text of the edition)
    #
    # A passage is one text BLOCK — p, head, opener, closer, dateline,
    # postscript, address, lg, list, table (a block inside a block — salute
    # inside opener — renders inline); loose text between blocks becomes a
    # "text" block of its own. <choice> takes the editors' reading (expan >
    # corr > reg); <del>, <fw> (foliation, catchwords) and <metamark> are not
    # reading text; <gap> renders the house mark […]; <add>, <supplied>,
    # <unclear>, <hi> render their text. <note> WITHOUT @hand is the editors'
    # commentary (German, keyed by xml:id) — it leaves the text and rides the
    # block's "notes"; a note WITH @hand is the writer's own marginalia and
    # renders inline. <pb> sets the page the next block starts on (and is
    # listed when it falls inside one); <lb> is a space; verse lines, list
    # items and table rows break the line. <rs type=person|place> surface
    # forms ride the block; <foreign xml:lang> languages too, and a block
    # whose every character sits inside one foreign language reports it.
    class SocinianTeiParser
      BLOCK_TAGS = %w[p head opener closer dateline postscript address lg list table].freeze
      CONTAINER_TAGS = %w[text body front back div].freeze
      SKIPPED_TAGS = %w[del fw metamark anchor cb figure].freeze
      CHOICE_PREFERENCE = %w[expan corr reg].freeze
      LINE_END_TAGS = %w[l item row].freeze
      GAP_MARK = "[…]"

      Block = Data.define(:tag, :text, :page, :page_breaks, :persons, :places, :notes, :foreign, :language)
      Witness = Data.define(:id, :designation, :licence_target, :licence_text, :languages, :class_code,
                            :dwds_class, :revisions, :medium, :source, :blocks) do
        def transcribed? = !blocks.empty?
      end
      Action = Data.define(:type, :persons, :places, :date)
      Component = Data.define(:id, :role, :type, :title, :actions, :witnesses)
      Result = Data.define(:title, :components)

      def parse(path)
        doc = Nokogiri::XML(SourceRead.utf8_file(path, label: "socinian-letters"), &:strict)
        doc.remove_namespaces!
        root = doc.root
        raise Nabu::ParseError, "#{path}: root is <#{root&.name}>, not <teiCorpus>" unless root&.name == "teiCorpus"

        components = root.xpath("./TEI").map { |tei| component(tei) }
        raise Nabu::ParseError, "#{path}: teiCorpus carries no TEI component" if components.empty?

        Result.new(title: squash(root.at_xpath("./teiHeader/fileDesc/titleStmt/title[@type='main']")&.text),
                   components: components)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # Whitespace runs → one space, stripped; nil for blank.
      def self.squash(value)
        text = value.to_s.gsub(/\s+/, " ").strip
        text.empty? ? nil : text
      end

      private

      def squash(value) = self.class.squash(value)

      def component(tei)
        header = tei.at_xpath("./teiHeader")
        Component.new(
          id: tei["id"], role: tei["n"], type: tei["type"],
          title: squash(header&.at_xpath("./fileDesc/titleStmt/title[@type='main']")&.text),
          actions: (header&.xpath("./profileDesc/correspDesc/correspAction") || []).map { |node| action(node) },
          witnesses: tei.xpath("./TEI").map { |wit| witness(wit) }
        )
      end

      def action(node)
        Action.new(
          type: node["type"],
          persons: node.xpath("./persName").filter_map do |pers|
            name = squash(pers.text)
            name && { "name" => name, "key" => pers["key"], "cert" => pers["cert"] }.compact
          end,
          places: node.xpath("./placeName").filter_map do |place|
            name = squash(place.text)
            name && { "name" => name, "key" => place["key"] }.compact
          end,
          date: node.at_xpath("./date")&.then do |date|
            %w[when from to notBefore notAfter cert].to_h { |key| [key, date[key]] }
                                                    .reject { |_k, v| v.to_s.strip.empty? }
          end
        )
      end

      def witness(wit)
        header = wit.at_xpath("./teiHeader")
        licence = header&.at_xpath("./fileDesc/publicationStmt/availability/licence")
        Witness.new(
          id: wit["id"], designation: wit["n"],
          licence_target: licence && licence["target"].to_s.strip,
          licence_text: squash(licence&.text),
          languages: (header&.xpath("./profileDesc/langUsage/language") || []).map { |lang| lang["ident"].to_s.strip },
          class_code: squash(header&.at_xpath("./profileDesc/textClass/classCode[@scheme='#sbw']")&.text),
          dwds_class: squash(header&.at_xpath("./profileDesc/textClass/classCode[contains(@scheme,'dwds')]")&.text),
          revisions: (header&.xpath("./revisionDesc/change") || []).filter_map { |change| squash(change.text) },
          medium: squash(header&.at_xpath("./fileDesc/titleStmt/title[@type='sub']")&.text),
          source: squash(header&.at_xpath("./fileDesc/sourceDesc/bibl")&.text),
          blocks: (text = wit.at_xpath("./text")) ? BlockWalker.new.blocks(text) : []
        )
      end

      # One witness <text> → its ordered, non-empty Blocks. A fresh walker per
      # witness: the page state is per witness.
      class BlockWalker
        def initialize
          @blocks = []
          @current = nil
          @page = nil
          @pending_notes = []
          @foreign = []
        end

        def blocks(text_node)
          walk_children(text_node)
          close_block
          @blocks.last&.notes&.concat(@pending_notes) unless @pending_notes.empty?
          @blocks
        end

        private

        def walk_children(node)
          node.children.each { |child| walk(child) }
        end

        def walk(node)
          if node.text?
            append(node.text.gsub(/\s+/, " "))
          elsif node.element?
            element(node)
          end
        end

        def element(node)
          name = node.name
          if BLOCK_TAGS.include?(name) && !real_block_open?
            close_block
            open_block(name)
            walk_children(node)
            close_block
          elsif CONTAINER_TAGS.include?(name)
            close_block if @current
            walk_children(node)
          else
            inline(node, name)
          end
        end

        def inline(node, name)
          case name
          when *SKIPPED_TAGS then nil
          when "note" then node["hand"] ? walk_children(node) : editorial_note(node)
          when "choice" then choice_reading(node)&.then { |reading| walk(reading) }
          when "gap" then append(" #{GAP_MARK} ")
          when "pb" then page_break(node)
          when "lb" then append(" ")
          when *LINE_END_TAGS then walk_then(node, "\n")
          when "cell" then walk_then(node, " ")
          when "rs" then mention(node)
          when "foreign" then foreign(node)
          else walk_children(node)
          end
        end

        def walk_then(node, separator)
          walk_children(node)
          append(separator)
        end

        def choice_reading(node)
          children = node.element_children
          CHOICE_PREFERENCE.each do |tag|
            hit = children.find { |child| child.name == tag }
            return hit if hit
          end
          children.first # nil for an empty <choice/> — nothing to read
        end

        def page_break(node)
          n = node["n"].to_s.strip
          n = nil if n.empty?
          @page = n
          @current[:page_breaks] << n if @current && n
        end

        def editorial_note(node)
          text = SocinianTeiParser.squash(node.text) or return
          if @current
            @current[:notes] << text
          else
            @pending_notes << text
          end
        end

        def mention(node)
          start = @current && @current[:buffer].length
          walk_children(node)
          return unless @current && start

          surface = SocinianTeiParser.squash(@current[:buffer][start..])
          key = { "person" => :persons, "place" => :places }[node["type"]]
          @current[key] << surface if key && surface
        end

        def foreign(node)
          lang = node["lang"].to_s.strip
          return walk_children(node) if lang.empty?

          @current[:foreign] << lang if @current
          @foreign.push(lang)
          walk_children(node)
          @foreign.pop
        end

        def append(text)
          return if text.empty?

          if @current.nil?
            return if text.strip.empty?

            open_block("text", implicit: true)
          end
          @current[:buffer] << text
          @current[:langs] << @foreign.last unless text.strip.empty?
        end

        def real_block_open? = @current && !@current[:implicit]

        def open_block(tag, implicit: false)
          @current = { tag: tag, implicit: implicit, buffer: +"", page: @page, page_breaks: [], persons: [],
                       places: [], notes: @pending_notes, foreign: [], langs: [] }
          @pending_notes = []
        end

        def close_block
          block = @current or return
          @current = nil
          text = block[:buffer].split("\n").filter_map { |line| SocinianTeiParser.squash(line) }.join("\n")
          if text.empty?
            @pending_notes.concat(block[:notes])
            return
          end

          langs = block[:langs].uniq
          @blocks << Block.new(tag: block[:tag], text: text, page: block[:page], page_breaks: block[:page_breaks],
                               persons: block[:persons].uniq, places: block[:places].uniq, notes: block[:notes],
                               foreign: block[:foreign].uniq, language: langs.size == 1 ? langs.first : nil)
        end
      end
    end
  end
end
