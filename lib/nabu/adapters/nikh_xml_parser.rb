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
    # level3 (month) → level4 (day) → level5 (기사, the individual
    # article with its own editorial title, docNo, archive sources and
    # subjectClass rows).
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
    # every downstream option open).
    #
    # DOM, not SAX: sillok members top out ~6 MB (the ~5 MB house line
    # bends, measured, not ignored); the sjw scale test (78-2) revisits
    # with Nokogiri::XML::Reader if its members demand it.
    class NikhXmlParser
      LEVELS = %w[level1 level2 level3 level4 level5].freeze

      # A volume file: +id+ from the FILENAME (2nd_<id>.xml) — the root
      # id of a level1-rooted member is the bare reign code ("wqa"),
      # which only the filename disambiguates. +year+ is the root
      # front's 서기 year (nil when undated).
      Volume = Data.define(:id, :title, :year, :date_raw, :leaves)

      # A leaf citation unit. +title+ is its own mainTitle (the level5
      # editorial headline) or the nearest ancestor's; +date_raw+ the
      # nearest 서기 date attr; +sources+ the archive citations
      # ("태백산사고본: 太祖實錄 3책 15권 · 14장 A면" shape).
      Leaf = Data.define(:id, :title, :date_raw, :subject_classes, :sources, :text)

      def parse_file(path)
        xml = Nokogiri::XML(File.read(path, encoding: Encoding::UTF_8)) do |config|
          config.strict.nonet
        end
        build_volume(path, xml.root)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "nikh-xml: #{File.basename(path)}: #{e.message}"
      end

      private

      def build_volume(path, root)
        raise Nabu::ParseError, "nikh-xml: #{File.basename(path)}: no level root" if root.nil? ||
                                                                                     !LEVELS.include?(root.name)

        id = File.basename(path, ".xml").sub(/\A2nd_/, "")
        date = front_date(root)
        Volume.new(
          id: id, title: front_title(root),
          year: date && year_of(date), date_raw: date,
          leaves: collect_leaves(root)
        )
      end

      # Depth-first over the level tree: a node leafs when no descendant
      # level node exists beneath it; its text block is the citation unit.
      def collect_leaves(node)
        children = level_children(node)
        return children.flat_map { |child| collect_leaves(child) } unless children.empty?

        text = leaf_text(node)
        return [] if text.empty?

        [build_leaf(node, text)]
      end

      def level_children(node)
        node.element_children.select { |child| LEVELS.include?(child.name) }
      end

      def build_leaf(node, text)
        Leaf.new(
          id: node["id"],
          title: nearest(node) { |candidate| front_title(candidate) },
          date_raw: nearest(node) { |candidate| front_date(candidate) },
          subject_classes: node.xpath("./front//subjectClass").map { |sc| sc.text.strip },
          sources: front_sources(node),
          text: text
        )
      end

      # The node's own front value, else the nearest level ancestor's.
      def nearest(node, &extract)
        current = node
        while current && LEVELS.include?(current.name)
          value = extract.call(current)
          return value if value

          current = current.parent
        end
        nil
      end

      def front_title(node)
        title = node.at_xpath("./front//mainTitle")&.text&.strip
        title unless title.nil? || title.empty?
      end

      # The 서기 (western calendar) dateOccured attr — "1863" or
      # "1863-12-08L0" — the one machine-shaped date among the seven.
      def front_date(node)
        node.at_xpath("./front//dateOccured[@type='서기'][@date]")&.attr("date")
      end

      def year_of(date_raw)
        year = date_raw[/\A(\d{4})/, 1]
        year&.to_i
      end

      def front_sources(node)
        node.xpath("./front//source").map do |source|
          title = source.at_xpath("./mainTitle")
          label = [title&.attr("type"), title&.text&.strip].compact.reject(&:empty?).join(": ")
          page = source.at_xpath("./page")&.attr("begin")
          [label, page].compact.reject(&:empty?).join(" · ")
        end.reject(&:empty?)
      end

      # The leaf's paragraphs, one line each: index refs flatten to their
      # text, 원주 annotations ride inline (noteContent's own 【】 marks
      # travel verbatim), whitespace runs collapse — canonical means
      # canonical, so nothing is corrected, only the markup shed.
      def leaf_text(node)
        paragraphs = node.xpath("./text/content/paragraph").map { |paragraph| squish(paragraph.text) }
        paragraphs.reject(&:empty?).join("\n")
      end

      def squish(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
