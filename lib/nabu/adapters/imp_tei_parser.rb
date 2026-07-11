# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for the IMP-schema TEI P5 of the historical-Slovene
    # corpora (P13-9) — the imp-tei family, shared by goo300k (gold) and IMP
    # (silver). The schema is the corpora's own tei_imp.rng profile, NOT
    # EpiDoc/CTS: word-level annotation with a modernization layer,
    #
    #   <s>
    #     <choice><orig><w>ſvoje</w></orig>
    #             <reg><w lemma="svoj" ana="#P">svoje</w></reg></choice>
    #     <c> </c>
    #     <w lemma="biti" ana="#Va">je</w>
    #     <pc>,</pc>
    #     ... <reg><w …/><desc><gloss>apostol, učenec</gloss>
    #                          <bibl>[sskj]</bibl></desc></reg>
    #
    # A standalone, individually tested component the Goo300k and Imp
    # adapters compose (the CcmhCesParser shape): #header peeks one file's
    # teiHeader for discover-time titles, #blocks streams one file's passage
    # blocks. goo300k stores each printed page as its own file (root
    # <div type="pb">, xi:included by the document root); IMP documents are
    # self-contained <SIGIL>-<year>-ana.xml — #blocks serves both, the
    # adapters own the file choreography.
    #
    # == Text policy (canonical means canonical)
    #
    # A passage's text is the HISTORICAL orig surface: character data of the
    # <orig> side of every <choice>, of bare <w> (spelling already modern),
    # of <pc> punctuation and <c> whitespace — strictly these leaves, never
    # inter-element indentation, so "poklizal" + <pc>,</pc> reads
    # "poklizal,". The <reg> modernization NEVER enters the text: it rides
    # as token annotation (:gold) or is dropped (:none — the IMP silver
    # decision, owner 2026-07-11). Sentences within a block join on a
    # single space; whitespace runs collapse.
    #
    # == Blocks and citations
    #
    # A passage block is any element with direct <s> children — goo300k's
    # <ab> (upstream document-global xml:ids), IMP's un-id'd <p>/<head>.
    # Citation: the xml:id's last two dot-segments where upstream minted one
    # ("goo168-ZRC_00001-1584.ab.1" → "ab.1"), else a per-tag document-order
    # counter ("p.1", "head.1") — stable because both deposits are frozen
    # (2015), and sync_policy manual means any upstream re-mint is
    # owner-witnessed. An <ab part="F"> continuing across a page break keeps
    # its own id: two blocks, never merged (upstream reality). The teiHeader
    # and <front> carry no <s>, so they yield no blocks by construction.
    # Page tracking: a <pb/> milestone or a <div type="pb"> page-file root
    # sets the page id every following block records ("pb.001" — the
    # facsimile link).
    #
    # == Token records (:gold)
    #
    # One token per <reg> <w> (or per bare <w>): "form" = the orig surface
    # (what the passage text attests — the lemma index shows it as
    # evidence), "reg" = the modernized form, "lemma", "msd" (the
    # MULTEXT-East-style tag from @ana, "#" ref prefix stripped: goo300k
    # writes "#Ncm", IMP writes bare "Ncfsn"), plus "gloss"/"gloss_bibl"
    # when the editors flagged archaic vocabulary. The indexer's
    # passage_lemmas contract reads exactly these "lemma"/"form" keys.
    class ImpTeiParser
      # One teiHeader peek: the sourceDesc bibl fields (NOT the titleStmt
      # wrapper title) + the TEI root's xml:lang. Missing fields are nil.
      Header = Data.define(:title_orig, :title_reg, :author, :date, :xml_lang)

      # One passage block. +tokens+ is an Array of string-keyed Hashes
      # (:gold) or nil (:none).
      Block = Data.define(:citation, :page, :text, :tokens)

      TOKEN_MODES = %i[gold none].freeze

      BIBL_FIELDS = %w[title author date].freeze

      TEXT_NODE_TYPES = [Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA,
                         Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE].freeze

      def initialize(tokens:)
        unless TOKEN_MODES.include?(tokens)
          raise ArgumentError, "tokens mode must be one of #{TOKEN_MODES.inspect}, got #{tokens.inspect}"
        end

        @tokens_mode = tokens
      end

      # Peek the teiHeader: bibl title/author/date + root xml:lang; stops
      # reading at </teiHeader>.
      def header(path)
        fields = { title_orig: nil, title_reg: nil, author: nil, date: nil, xml_lang: nil }
        walk = { in_bibl: false, field: nil }
        each_node(path) do |node|
          fields[:xml_lang] ||= node.attribute("xml:lang") if node.name == "TEI"
          break if node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT && node.name == "teiHeader"

          track_bibl(node, walk, fields)
        end
        Header.new(**fields)
      end

      # Stream one file's passage blocks in document order. Blocks whose text
      # comes out empty are not yielded.
      def blocks(path, &block)
        return enum_for(:blocks, path) unless block

        walk = { stack: [], page: nil, counters: Hash.new(0), block: nil, in_s: false,
                 side: nil, choice: nil, word: nil }
        each_node(path) do |node|
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT then open_element(node, walk)
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT then close_element(node, walk, &block)
          when *TEXT_NODE_TYPES then capture_text(node, walk)
          end
        end
      end

      private

      # -- header helpers --------------------------------------------------------

      def track_bibl(node, walk, fields)
        case [node.node_type, node.name]
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, "bibl"] then walk[:in_bibl] = true
        in [Nokogiri::XML::Reader::TYPE_END_ELEMENT, "bibl"] then walk[:in_bibl] = false
        in [Nokogiri::XML::Reader::TYPE_ELEMENT, String => name] if walk[:in_bibl] && BIBL_FIELDS.include?(name)
          walk[:field] = bibl_field(node)
        in [Nokogiri::XML::Reader::TYPE_END_ELEMENT, String => name] if BIBL_FIELDS.include?(name)
          walk[:field] = nil
        in [Integer => type, _] if TEXT_NODE_TYPES.include?(type) && walk[:field]
          append_field(fields, walk[:field], node.value)
        else nil
        end
      end

      def bibl_field(node)
        case node.name
        when "title" then node.attribute("type") == "orig" ? :title_orig : :title_reg
        when "author" then :author
        when "date" then :date
        end
      end

      def append_field(fields, field, value)
        value = value.strip
        return if value.empty?

        fields[field] = [fields[field], value].compact.join(" ")
      end

      # -- block streaming -------------------------------------------------------

      # Handlers run BEFORE the element joins the stack, so stack.last is
      # the parent while an <s> opens.
      def open_element(node, walk)
        track_page(node, walk)
        return if node.self_closing?

        case node.name
        when "s" then open_sentence(walk)
        when "choice" then walk[:choice] = { orig: +"", tokens: [] } if walk[:in_s]
        when "orig", "reg" then walk[:side] = node.name if walk[:choice]
        when "w" then open_word(node, walk)
        end
        walk[:stack] << { name: node.name, id: node.attribute("xml:id") }
      end

      def close_element(node, walk, &)
        walk[:stack].pop
        case node.name
        when "s" then close_sentence(walk)
        when "choice" then close_choice(walk)
        when "orig", "reg" then walk[:side] = nil
        when "w" then close_word(walk)
        end
        emit_block(node, walk, &)
      end

      def open_sentence(walk)
        walk[:in_s] = true
        return if walk[:block]

        parent = walk[:stack].last or return
        walk[:counters][parent[:name]] += 1
        walk[:block] = { tag: parent[:name], depth: walk[:stack].size - 1, page: walk[:page],
                         id: parent[:id], n: walk[:counters][parent[:name]], text: +"", tokens: [] }
      end

      def close_sentence(walk)
        walk[:in_s] = false
        walk[:block][:text] << " " if walk[:block]
      end

      def track_page(node, walk)
        return unless node.name == "pb" || (node.name == "div" && node.attribute("type") == "pb")

        id = node.attribute("xml:id")
        walk[:page] = id_tail(id) if id
      end

      # A <w> carrying annotation: bare, or the <reg> side of a choice. The
      # <orig> side's text accumulates into the choice's orig buffer instead
      # (see capture_text) — it is surface, not a token of its own.
      def open_word(node, walk)
        return unless walk[:block] && walk[:in_s]
        return if walk[:choice] && walk[:side] != "reg"

        walk[:word] = { "form" => +"", "reg" => +"", "lemma" => node.attribute("lemma"),
                        "msd" => node.attribute("ana")&.delete_prefix("#") }
      end

      # Text lands by the element it sits IN (the stack top): leaf text only,
      # never inter-element indentation.
      def capture_text(node, walk)
        block = walk[:block]
        return unless block && walk[:in_s]

        case walk[:stack].last&.[](:name)
        when "w", "pc", "c"
          if walk[:side] == "orig" then walk[:choice][:orig] << node.value
          elsif walk[:side] == "reg" then walk[:word]["reg"] << node.value if walk[:word]
          elsif walk[:word] then walk[:word]["reg"] << node.value
          else block[:text] << node.value
          end
        when "gloss" then attach_gloss(walk, "gloss", node.value)
        when "bibl" then attach_gloss(walk, "gloss_bibl", node.value)
        end
      end

      # The archaic-vocabulary <desc> inside <reg> explains the token it
      # follows: attach to the last queued reg token.
      def attach_gloss(walk, key, value)
        token = walk[:choice] && walk[:side] == "reg" ? walk[:choice][:tokens].last : nil
        return unless token

        value = value.strip
        token[key] = [token[key], value].compact.join(" ") unless value.empty?
      end

      # A finished <w>: inside <reg> it queues on the choice (form filled at
      # </choice> from the orig surface); a bare word IS its own orig, so
      # form = reg and it lands in text and tokens directly.
      def close_word(walk)
        word = walk.delete(:word) or return

        word["reg"] = collapse(word["reg"])
        if walk[:choice]
          walk[:choice][:tokens] << word
        else
          word["form"] = word["reg"]
          walk[:block][:text] << word["form"]
          walk[:block][:tokens] << compact_token(word)
        end
      end

      # A finished <choice>: the orig surface enters the passage text, and
      # every queued <reg> token attests it as "form".
      def close_choice(walk)
        choice = walk.delete(:choice) or return

        orig = collapse(choice[:orig])
        walk[:block][:text] << orig
        choice[:tokens].each do |token|
          token["form"] = orig
          walk[:block][:tokens] << compact_token(token)
        end
      end

      def emit_block(node, walk, &)
        block = walk[:block]
        return unless block && walk[:stack].size == block[:depth] && node.name == block[:tag]

        walk[:block] = nil
        text = collapse(block[:text])
        return if text.empty?

        yield Block.new(citation: citation(block), page: block[:page], text: text,
                        tokens: @tokens_mode == :gold ? block[:tokens] : nil)
      end

      def citation(block)
        block[:id] ? id_tail(block[:id]) : "#{block[:tag]}.#{block[:n]}"
      end

      # "goo168-ZRC_00001-1584.ab.1" → "ab.1"; "pb.001" stays "pb.001".
      def id_tail(id)
        id.split(".").last(2).join(".")
      end

      def compact_token(token)
        token.reject { |_key, value| value.nil? || value.empty? }
      end

      def collapse(text)
        text.gsub(/[[:space:]]+/, " ").strip
      end

      # The streaming spine (house rule: Reader is the only Nokogiri entry
      # point for corpus files); malformed XML surfaces as ParseError naming
      # the file.
      def each_node(path, &)
        reader = Nokogiri::XML::Reader(File.open(path))
        reader.each(&)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed IMP TEI XML: #{e.message}"
      end
    end
  end
end
