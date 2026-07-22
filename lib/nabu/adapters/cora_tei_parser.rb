# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Streaming parser for the cora-tei family (P40-5): the TEI P5
    # serialisation of the CorA-derived DDD reference corpora of historical
    # German — ReM (Middle High German) now; ReA (Old High German + Old
    # Saxon) and ReN (Middle Low German) ride the same family when their
    # licenses confirm (backlog №40-1/№40-2). Censused from the two whole
    # ReM v2.1 texts in test/fixtures/rem/ (never invented):
    #
    #   <body><ab>
    #     <pb n="100v" ed="1"/>
    #     <lb n="5" ed="1"/>
    #     <w xml:id="t5_m1" norm="grinme" lemma="grimme">grínme</w>
    #     <w xml:id="t6_m1" norm="stet" lemma="stêt" join="right">ſtet</w>
    #     <pc xml:id="t7_m1" norm="." lemma="--" join="left">.</pc>
    #
    # == The two token layers (canonical means canonical)
    #
    # CorA corpora carry BOTH a diplomatic transcription and a normalized
    # layer per token. In this TEI export the ELEMENT TEXT of <w>/<pc> is
    # the diplomatic form (long ſ, combining marks like uͦ, <unclear>/
    # <supplied> editorial wrappers, <space quantity unit="chars"/> scribal
    # gaps) and @norm/@lemma carry the normalized/annotated layer. The
    # diplomatic layer is the witness — it becomes the line text (the
    # imp-tei orig-side precedent); norm/lemma ride each token record. The
    # export carries NO pos/msd attributes (censused: those live only in
    # the upstream CorA-XML sibling zips), so token records are honestly
    # norm + lemma. @join="right"/"left" marks tokens written together in
    # the manuscript; multi-part tokens share a base id (t9_m1/t9_m2) and
    # stay separate records with the shared base visible in "id".
    #
    # == Lines (the layout grain)
    #
    # The manuscript line — <lb ed="1"/> (or an lb without @ed) — is the
    # primary layout unit (each fixture's encodingDesc: "Primary line
    # breaks: Handschrift"); <pb n ed="1"/> tracks the folio. A line is
    # cited (page, n). <lb ed="2"/> is the EDITION lineation: it never
    # splits a manuscript line; its labels ride Line#edition_lines.
    #
    # == Loudness (the aozora precedent)
    #
    # Unrecognized elements inside <body> are counted (Body#unrecognized,
    # name → count) and parsing continues; untokenized non-whitespace text
    # counts under "#text". ParseError is reserved for structural breakage:
    # malformed XML, a token outside any manuscript line, a nested token, a
    # primary <lb> without @n.
    class CoraTeiParser
      # One teiHeader peek. Placeholder values ("-", "--") read as nil;
      # +dialects+ is the langUsage value chain (mhd → oberdeutsch → …),
      # the corpus's localization classification.
      Header = Data.define(:text_id, :title, :token_count, :licence, :language_idents, :dialects,
                           :genre, :topic, :text_type, :repository, :ms_idno,
                           :orig_date, :orig_place, :derived_from)

      # One manuscript line: +page+ the pb @n (may be nil), +n+ the lb @n,
      # +edition_lines+ the ed="2" labels that fell inside it, +text+ the
      # raw diplomatic surface (caller normalizes), +tokens+ the token
      # records (string-keyed Hashes).
      Line = Data.define(:page, :n, :edition_lines, :text, :tokens)

      # One file's body: the lines in document order plus the unrecognized-
      # element census (sorted name → count; empty = clean).
      Body = Data.define(:lines, :unrecognized)

      # Upstream's null placeholder ("-", "--") in header fields and @lemma.
      NULL_PLACEHOLDER = /\A-+\z/

      # Header elements whose text is captured, keyed by [name, parent].
      HEADER_CAPTURES = {
        %w[title titleStmt] => :title,
        %w[title derivation] => :derived_from,
        %w[licence availability] => :licence,
        %w[language langUsage] => :language,
        %w[repository msIdentifier] => :repository,
        %w[idno msIdentifier] => :ms_idno,
        %w[classCode textClass] => :genre
      }.freeze

      TEXT_NODE_TYPES = [Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA,
                         Nokogiri::XML::Reader::TYPE_SIGNIFICANT_WHITESPACE].freeze

      # -- header ------------------------------------------------------------

      # Peek one file's teiHeader; stops reading at </teiHeader>.
      def header(path)
        walk = { stack: [], capture: nil, buffer: +"", fields: { language_idents: [], dialects: [] } }
        each_node(path) do |node|
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT then open_header_element(node, walk)
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT
            break if node.name == "teiHeader"

            close_header_element(node, walk)
          when *TEXT_NODE_TYPES then walk[:buffer] << node.value if walk[:capture]
          end
        end
        finish_header(walk[:fields])
      end

      # -- body --------------------------------------------------------------

      # Read one file's <body> into lines + the loudness census.
      def body(path)
        walk = { path: path, in_body: false, lines: [], unrecognized: Hash.new(0),
                 page: nil, line: nil, pending_ed2: [], word: nil, prev_join: nil }
        each_node(path) do |node|
          case node.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT then open_body_element(node, walk)
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT then close_body_element(node, walk)
          when *TEXT_NODE_TYPES then capture_body_text(node, walk)
          end
        end
        flush_line(walk)
        Body.new(lines: walk[:lines], unrecognized: walk[:unrecognized].sort.to_h)
      end

      private

      # -- header helpers ----------------------------------------------------

      def open_header_element(node, walk)
        fields = walk[:fields]
        case node.name
        when "fileDesc" then fields[:text_id] ||= node.attribute("xml:id")
        when "measure"
          fields[:token_count] ||= node.attribute("quantity")&.to_i if node.attribute("unit") == "tokens"
        when "term" then open_term_capture(node, walk)
        when "origDate" then open_capture(node, walk, :orig_date)
        when "origPlace" then open_capture(node, walk, :orig_place)
        else
          key = HEADER_CAPTURES[[node.name, walk[:stack].last]]
          open_capture(node, walk, key) if key
          fields[:language_idents] << node.attribute("ident") if key == :language
        end
        walk[:stack] << node.name unless node.self_closing?
      end

      def open_term_capture(node, walk)
        case node.attribute("type")
        when "topic" then open_capture(node, walk, :topic)
        when "text-type" then open_capture(node, walk, :text_type)
        end
      end

      def open_capture(node, walk, key)
        return if node.self_closing? || walk[:capture]

        walk[:capture] = key
        walk[:capture_element] = node.name
        walk[:buffer] = +""
      end

      def close_header_element(node, walk)
        walk[:stack].pop
        return unless walk[:capture] && node.name == walk[:capture_element]

        key = walk.delete(:capture)
        walk.delete(:capture_element)
        value = walk[:buffer].strip
        store_header_value(walk[:fields], key, value)
      end

      # First non-placeholder value wins per field; language values chain
      # into the dialect list.
      def store_header_value(fields, key, value)
        return if value.empty? || value.match?(NULL_PLACEHOLDER)

        if key == :language
          fields[:dialects] << value
        else
          fields[key] ||= value
        end
      end

      def finish_header(fields)
        Header.new(
          text_id: fields[:text_id], title: fields[:title], token_count: fields[:token_count],
          licence: fields[:licence], language_idents: fields[:language_idents].compact.uniq,
          dialects: fields[:dialects], genre: fields[:genre], topic: fields[:topic],
          text_type: fields[:text_type], repository: fields[:repository], ms_idno: fields[:ms_idno],
          orig_date: fields[:orig_date], orig_place: fields[:orig_place],
          derived_from: fields[:derived_from]
        )
      end

      # -- body helpers ------------------------------------------------------

      def open_body_element(node, walk)
        return walk[:in_body] = true if node.name == "body"
        return unless walk[:in_body]

        case node.name
        when "ab" then nil # the token container; lines are the grain
        when "pb" then walk[:page] = node.attribute("n")
        when "lb" then open_line_break(node, walk)
        when "w", "pc" then open_token(node, walk)
        when "unclear", "supplied" then walk[:word][:flags][node.name] = true if walk[:word]
        when "space" then walk[:word][:form] << (" " * (node.attribute("quantity") || "1").to_i) if walk[:word]
        else walk[:unrecognized][node.name] += 1
        end
      end

      # ed="1" (or no @ed) opens a manuscript line; any other @ed is edition
      # lineation and rides the open line's labels.
      def open_line_break(node, walk)
        ed = node.attribute("ed")
        if ed.nil? || ed == "1"
          n = node.attribute("n") or
            raise ParseError, "#{walk[:path]}: primary <lb> without @n — lines would be uncitable"
          flush_line(walk)
          walk[:line] = { page: walk[:page], n: n, ed2: walk.delete(:pending_ed2) || [],
                          text: +"", tokens: [] }
          walk[:pending_ed2] = []
        elsif walk[:line]
          walk[:line][:ed2] << node.attribute("n")
        else
          walk[:pending_ed2] << node.attribute("n")
        end
      end

      def open_token(node, walk)
        raise ParseError, "#{walk[:path]}: nested <#{node.name}> token" if walk[:word]
        unless walk[:line]
          raise ParseError, "#{walk[:path]}: <#{node.name}> token outside any manuscript line " \
                            "(no primary <lb> seen)"
        end

        walk[:word] = { name: node.name, form: +"", flags: {},
                        "id" => node.attribute("xml:id"), "norm" => node.attribute("norm"),
                        "lemma" => node.attribute("lemma"), "join" => node.attribute("join") }
        close_token(walk) if node.self_closing?
      end

      def close_body_element(node, walk)
        return unless walk[:in_body]

        case node.name
        when "body"
          walk[:in_body] = false
          flush_line(walk)
        when "ab" then flush_line(walk)
        when "w", "pc" then close_token(walk)
        end
      end

      # A finished token joins the line: text glued per @join, record
      # compacted (nil/empty attributes and the "--" null lemma drop).
      def close_token(walk)
        word = walk.delete(:word) or return
        line = walk[:line]
        if word[:form].empty?
          walk[:unrecognized]["empty-#{word[:name]}"] += 1
          return
        end

        joined = line[:text].empty? || word["join"] == "left" || walk[:prev_join] == "right"
        line[:text] << " " unless joined
        line[:text] << word[:form]
        walk[:prev_join] = word["join"]
        line[:tokens] << token_record(word)
      end

      def token_record(word)
        record = { "id" => word["id"], "form" => word[:form], "norm" => word["norm"],
                   "lemma" => word["lemma"], "join" => word["join"] }
        record["pc"] = true if word[:name] == "pc"
        record.merge!(word[:flags])
        # Only @lemma uses the "--" null (censused); a form/norm that IS a
        # dash would be real punctuation and must never drop.
        record.reject { |key, v| v.nil? || v == "" || (key == "lemma" && v.match?(NULL_PLACEHOLDER)) }
      end

      # Text inside a token is diplomatic form — layout whitespace removed
      # (scribal gaps arrive via <space>, never literal whitespace); text
      # outside any token is unaccounted witness text, censused loudly.
      def capture_body_text(node, walk)
        return unless walk[:in_body]

        if walk[:word]
          walk[:word][:form] << node.value.gsub(/[[:space:]]+/, "")
        elsif !node.value.strip.empty?
          walk[:unrecognized]["#text"] += 1
        end
      end

      def flush_line(walk)
        line = walk.delete(:line)
        walk[:prev_join] = nil
        return unless line && !line[:text].empty?

        walk[:lines] << Line.new(page: line[:page], n: line[:n], edition_lines: line[:ed2],
                                 text: line[:text], tokens: line[:tokens])
      end

      # The streaming spine (house rule: Reader is the only Nokogiri entry
      # point for corpus files); malformed XML surfaces as ParseError.
      def each_node(path, &)
        reader = Nokogiri::XML::Reader(File.open(path))
        reader.each(&)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed cora-tei XML: #{e.message}"
      end
    end
  end
end
