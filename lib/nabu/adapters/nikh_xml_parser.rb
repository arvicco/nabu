# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser family "nikh-xml" (P78-1): the Korean History Database
    # unified DTD (history.dtd ver 1.3, 2015-11-30 — shipped verbatim in
    # every NIKH dump zip, and its own changelog names the sillok, the
    # 승정원일기 and the 광해군일기 variants: one family across the whole
    # state record). A volume file roots at level1 (the _000 whole-reign
    # preface members) or level2 (the per-reign-year members) and nests
    # level3 (month) → level4 (day) → level5 (the individual 기사
    # article / 좌목 roster with its own editorial title, docNo, archive
    # sources and subjectClass rows).
    #
    # The LEAVES of the level tree are the citation units: level5
    # articles where present, else the deepest level node carrying text
    # (the appendix/preface members leaf at level3 or level2). The
    # header <text> blocks of NON-leaf nodes are navigation — repeats of
    # the mainTitle chain — and mint nothing.
    #
    # Dates: every dated front carries up to seven parallel calendar
    # systems (서기 with an ISO-ish date attr — "1863-12-08L0", L=lunar
    # flag — plus 간지/재위연도/개국연호/중국연호/단기/일본연호). The
    # parser surfaces the 서기 attr raw plus its parsed year; calendar
    # conversion is deliberately NOT attempted here (the raw attr keeps
    # every downstream option open). The sjw day fronts additionally
    # carry the weather record (front/description/weather — the DTD's
    # own 2015-08 addition); it rides each leaf via the ancestor chain.
    #
    # STREAMING (P78-2): sjw members run to 19 MB, far past the ~5 MB
    # DOM line — the walk is a Nokogiri::XML::Reader pass holding one
    # open-ancestor stack, with only the small front/text SUBTREES
    # parsed as mini-DOMs. One implementation for the whole family;
    # sillok's ≤6 MB members ride the same lane.
    class NikhXmlParser
      LEVELS = %w[level1 level2 level3 level4 level5].freeze

      # The ancestor-fallback default for a frame that carried no front.
      EMPTY_FRONT = { title: nil, date_raw: nil, subject_classes: [], sources: [], weather: nil }.freeze

      # A volume file: +id+ from the FILENAME (2nd_<id>.xml) — the root
      # id of a level1-rooted member is the bare reign code ("wqa"),
      # which only the filename disambiguates. +root_id+ is the root
      # element's own id attr (sjw keys its documents on it). +year+ is
      # the root front's 서기 year (nil when undated).
      Volume = Data.define(:id, :root_id, :title, :year, :date_raw, :leaves)

      # A leaf citation unit. +title+ is its own mainTitle (the level5
      # editorial headline) or the nearest ancestor's; +date_raw+ the
      # nearest 서기 date attr; +sources+ the archive citations
      # ("태백산사고본: 太祖實錄 3책 15권 · 14장 A면" shape); +weather+
      # the nearest ancestor's weather record (sjw day fronts), nil
      # elsewhere.
      Leaf = Data.define(:id, :title, :date_raw, :subject_classes, :sources, :weather, :text)

      def parse_file(path)
        walk(path)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "nikh-xml: #{File.basename(path)}: #{e.message}"
      end

      private

      # One streaming pass. Each open level element is a stack frame;
      # its front and text subtrees are captured as they stream past.
      # A frame that closes without ever seeing a level child is a LEAF.
      def walk(path)
        reader = Nokogiri::XML::Reader(File.open(path, encoding: Encoding::UTF_8))
        stack = []
        leaves = []
        root_frame = nil
        while reader.read
          case reader.node_type
          when Nokogiri::XML::Reader::TYPE_ELEMENT
            root_frame = open_element(reader, stack, leaves) || root_frame
          when Nokogiri::XML::Reader::TYPE_END_ELEMENT
            close_element(reader, stack, leaves)
          end
        end
        build_volume(path, root_frame, leaves)
      end

      # Returns the frame iff this element is the ROOT level node.
      def open_element(reader, stack, leaves)
        name = reader.name
        if LEVELS.include?(name)
          open_level(reader, stack, leaves, name)
        elsif !stack.empty?
          capture_subtree(reader, stack.last, name)
          nil
        end
      end

      def open_level(reader, stack, leaves, name)
        stack.last[:had_level_child] = true unless stack.empty?
        frame = { name: name, id: reader.attribute("id"), front: nil, text_xml: nil,
                  had_level_child: false, parent: stack.last }
        if reader.empty_element?
          emit_leaf(frame, leaves) # degenerate <levelN/> — empty text, emits nothing
        else
          stack << frame
        end
        stack.size == 1 ? frame : nil
      end

      # front/text captured ONCE per frame via outer_xml (the reader
      # walks on inside the subtree afterwards; the once-guards make the
      # revisit harmless).
      def capture_subtree(reader, frame, name)
        if name == "front" && frame[:front].nil?
          frame[:front] = parse_front(reader.outer_xml)
        elsif name == "text" && frame[:text_xml].nil?
          frame[:text_xml] = reader.outer_xml
        end
      end

      def close_element(reader, stack, leaves)
        return unless LEVELS.include?(reader.name)
        return if stack.empty? || stack.last[:name] != reader.name

        frame = stack.pop
        emit_leaf(frame, leaves) unless frame[:had_level_child]
      end

      def emit_leaf(frame, leaves)
        text = frame[:text_xml] ? leaf_text(frame[:text_xml]) : ""
        return if text.empty?

        leaves << Leaf.new(
          id: frame[:id],
          title: nearest(frame, :title), date_raw: nearest(frame, :date_raw),
          subject_classes: front_of(frame)[:subject_classes],
          sources: front_of(frame)[:sources],
          weather: nearest(frame, :weather),
          text: text
        )
      end

      # The frame's own front value, else the nearest level ancestor's.
      def nearest(frame, key)
        current = frame
        while current
          value = front_of(current)[key]
          return value if value

          current = current[:parent]
        end
        nil
      end

      def front_of(frame)
        frame[:front] || EMPTY_FRONT
      end

      # The small front subtree as a mini-DOM: title, the 서기 machine
      # date, subjectClass rows, archive-source citations, weather.
      def parse_front(xml)
        front = subtree_root(xml)
        title = front.at_xpath(".//mainTitle")&.text&.strip
        {
          title: (title unless title.nil? || title.empty?),
          date_raw: front.at_xpath(".//dateOccured[@type='서기'][@date]")&.attr("date"),
          subject_classes: front.xpath(".//subjectClass").map { |sc| sc.text.strip },
          sources: front_sources(front),
          weather: front.at_xpath(".//description/weather")&.text&.strip
        }
      end

      def front_sources(front)
        front.xpath(".//source").map do |source|
          title = source.at_xpath("./mainTitle")
          label = [title&.attr("type"), title&.text&.strip].compact.reject(&:empty?).join(": ")
          page = source.at_xpath("./page")&.attr("begin")
          [label, page].compact.reject(&:empty?).join(" · ")
        end.reject(&:empty?)
      end

      # The leaf's paragraphs, one line each: index refs and explanation
      # glosses flatten to their text, 원주 annotations ride inline
      # (noteContent's own 【】 marks travel verbatim), whitespace runs
      # collapse — canonical means canonical, so nothing is corrected,
      # only the markup shed.
      def leaf_text(text_xml)
        block = subtree_root(text_xml)
        paragraphs = block.xpath("./content/paragraph").map { |paragraph| squish(paragraph.text) }
        paragraphs.reject(&:empty?).join("\n")
      end

      def squish(text)
        text.gsub(/\s+/, " ").strip
      end

      # A captured subtree that won't mini-DOM (a truncated file hands
      # the reader an unterminated fragment) is damage, not data.
      def subtree_root(xml)
        Nokogiri::XML(xml).root or raise Nokogiri::XML::SyntaxError, "unparseable subtree"
      end

      def build_volume(path, root_frame, leaves)
        raise Nabu::ParseError, "nikh-xml: #{File.basename(path)}: no level root" if root_frame.nil?

        id = File.basename(path, ".xml").sub(/\A2nd_/, "")
        front = front_of(root_frame)
        Volume.new(
          id: id, root_id: root_frame[:id], title: front[:title],
          year: front[:date_raw] && year_of(front[:date_raw]), date_raw: front[:date_raw],
          leaves: leaves
        )
      end

      def year_of(date_raw)
        year = date_raw[/\A(\d{4})/, 1]
        year&.to_i
      end
    end
  end
end
