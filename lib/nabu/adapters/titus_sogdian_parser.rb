# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Sogdian parser family — the Sogdian corpora on TITUS (N. Sims-
    # Williams's corpus "arranged by texts", E. Morano's Stellung-Jesu
    # hymns). The same frame-based TITUS machinery as the Pahlavi books
    # (sequential pages on a "Next part" chain, `<!Level N>` / `<!XLevel N>`
    # header comments, `<span id=…>` lanes, the 1990s `</sPAN>` markup) —
    # composed from it (TitusPahlaviParser.read_page / mark_levels / clean,
    # TitusAvestanParser.walk) — with a different citation model the Pahlavi
    # family cannot absorb.
    #
    # == The passage is the MANUSCRIPT LINE (census of 22 live pages, 2026-10-10)
    #
    # The `<!Level N>` citation hierarchy (Text / Chapter / Paragraph in the
    # corpus; Editor / Item / Page of edition in Morano) does not track the
    # text grain: a "Paragraph" is ONE line in the Christian C2 (sogdn040),
    # a whole letter in the Ancient Letters (sogdn377), and "_" (absent) in
    # most fragment texts (BBB, the Berlin M-fragments, the inscriptions —
    # 652 lines under one "Chapter: UI"). The one uniform grain is the
    # manuscript line — the `Line of Manuscript` XLevel header — which every
    # content page carries before every text row. So a LINE header opens a
    # passage; any other header that arrives after text has started closes
    # the open one (a paragraph starting mid-line, a new edition page), and
    # text that follows it continues as its own passage.
    #
    # == Keys come from header VALUES, never from split anchors
    #
    # The machine anchors cannot be split: values carry underscores of their
    # own ("Text: C_1", "Manuscript: T_II_B_30_.4", "Or._8212_(92)"), and
    # TITUS's position vector never resets, so anchors drag stale values for
    # hundreds of pages ("…_Ch/U6854V_…" from an earlier text). Each header's
    # own "Label: value" is read instead; per page, the last value seen per
    # label is the context ("_" or empty = absent). TITUS itself never
    # clears deeper levels when a shallower one changes, and neither does
    # this (staleness is bounded by the page). The section's opening anchor
    # rides verbatim as `titus_anchor` (the deep link: page.htm#anchor).
    #
    # == Lanes: classified by FAMILY at any size
    #
    #   issg<script>l<flavor><size>   Sogdian transliteration — the TEXT.
    #       script: c Christian (Syriac script), mm Manichaean script,
    #       t / sb / sm / i the Sogdian script (the corpus's own section
    #       titles: "Documents in Ancient Sogdian script", "Sogdian Texts in
    #       Manichaean Script"); flavors x (a word split over two lines,
    #       "δc՚=" / "=pt") and r (a rubric) are running text.
    #   mitk<script>l<flavor><size>   Turkic fragments the Berlin pages
    #       carry ("Turkic fragment according to Wilkens") — text, claimed
    #       Old Uyghur (oui: the Turfan manuscript horizon).
    #   iosk<flavor><size>            Sanskrit — a title run continuing a
    #       subtitle ("Fragment of the Bhaiṣajyaguru…sūtra") is a HEADING
    #       (document metadata, never text); elsewhere Sanskrit text.
    #
    # A run below body size (< 16) beside a `voc` editorial note is a form
    # the note quotes ("Or <issgtl12>δβz՚</…> (with all previous editors)")
    # — apparatus. Body-size runs are always text. Notes (`voc*`), headers
    # (`h*`), layout (`n*`, `nc*`) and the title block are not lanes. ANY
    # other `<letters><digits>` id is a NEW lane: the page quarantines
    # (ParseError) until it is classified — never a silent skip; likewise an
    # unknown script code or flavor inside a known family.
    module TitusSogdianParser
      # One passage: +key+ the dotted citation from the context values
      # (chapter / paragraph / manuscript / page / line); +context+ every
      # header value in force at its first text ({"line_of_manuscript" =>
      # "1", …}); +anchor+ the opening header's anchor verbatim; +text+ NFC;
      # +language+ the passage claim; +scripts+ the Sogdian runs' scripts;
      # +embedded+ {language => text} of foreign runs inside a Sogdian line.
      Section = Data.define(:key, :context, :anchor, :text, :language, :scripts, :embedded)

      # The parsed page: its sections and its header block ({"titles" =>
      # [...], "subtitles" => [...], "bibliography" => "…", "data_entry" =>
      # "…"}, each key only when the page carries it).
      Page = Data.define(:sections, :header)

      # Header-block spans mined into metadata (same-kind spans in order).
      HEADER_SPANS = { "title" => "titles", "subtitle" => "subtitles", "bibliogr" => "bibliography",
                       "textdescr" => "data_entry" }.freeze
      LIST_KEYS = %w[titles subtitles].freeze

      SOGDIAN_LANE = /\Aissg(?<script>[a-km-z]+)l(?<flavor>[a-z]*?)(?<size>\d+)\z/
      TURKIC_LANE = /\Amitk(?<script>[a-km-z]+)l(?<flavor>[a-z]*?)(?<size>\d+)\z/
      SANSKRIT_LANE = /\Aiosk(?<flavor>[a-z]*?)(?<size>\d+)\z/
      # Parthian (`iiptht16`, Morano's "pwr kr'm" formula inside a Sogdian
      # line): the script letter is not interpreted; no flavor censused.
      PARTHIAN_LANE = /\Aiipth(?<script>[a-z]*?)(?<flavor>)(?<size>\d+)\z/

      # Sogdian lane script code → ISO 15924 (the census vocabulary).
      SCRIPTS = { "c" => "Syrc", "mm" => "Mani", "t" => "Sogd", "sb" => "Sogd", "sm" => "Sogd",
                  "i" => "Sogd" }.freeze

      # Flavor letters censused as running text.
      TEXT_FLAVORS = "xr"

      # Ids that are layout/apparatus, never lanes: headers, the n16 layout
      # carrier, small-type and body notes.
      NON_LANE = /\A(?:h|n|nc|voc)\d+\z/

      # Anything shaped like a TITUS lane id.
      LANE_SHAPE = /\A[a-z]+\d+\z/

      NOTE_SPAN = /\Avoc\d+\z/
      HEADING_SPAN = /\A(?:sub)?title\z/
      BODY_SIZE = 16

      # Context labels whose values key a passage, in citation order.
      KEY_FIELDS = %w[chapter paragraph manuscript page_of_manuscript line_of_manuscript].freeze

      LINE_LABEL = /\ALine\b/i

      # Parse one page's HTML (already valid UTF-8 — read it through
      # TitusPahlaviParser.read_page). Raises Nabu::ParseError on a
      # structural surprise.
      def self.parse(html)
        raise Nabu::ParseError, "titus-sogdian: page is not valid UTF-8" unless html.valid_encoding?

        doc = Nokogiri::HTML(TitusPahlaviParser.mark_levels(html))
        state = { sections: [], current: nil, pending: nil, context: {}, break: false, ended: false,
                  lanes: {} }
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        Page.new(sections: finish_all(state[:sections]), header: header_block(doc))
      end

      # The page's header block. A heading lane run (the Sanskrit sūtra
      # name after "Fragment of the") completes the subtitle it continues;
      # split spans of one kind join with " … " (the titus-pahlavi shape).
      def self.header_block(doc)
        # The page footer ("This text is part of the TITUS edition …") can
        # nest inside an unclosed header span — nothing after the first
        # <HR> is header.
        doc.xpath("(//hr)[1]/following::text()").each(&:unlink)
        HEADER_SPANS.each_with_object({}) do |(span_id, key), block|
          parts = doc.css(%(span[id="#{span_id}"])).map { |span| clean(span.text + heading_tail(span)) }
          parts.reject!(&:empty?)
          next if parts.empty?

          block[key] = LIST_KEYS.include?(key) ? parts : parts.join(" … ")
        end
      end

      def self.heading_tail(span)
        tail = +""
        sibling = span.next_element
        while sibling && SANSKRIT_LANE.match?(sibling["id"].to_s)
          tail << " " << sibling.text
          sibling = sibling.next_element
        end
        tail
      end

      # The page's own Level-1 value ("Text: C_1" → "C_1"), or nil on a
      # continuation page.
      def self.level_one(html)
        match = html.match(/<!Level 1>([^<]*)/)
        return nil if match.nil?

        value = match[1].split(":", 2)[1].to_s.gsub(/\p{Space}+/, " ").strip
        value.empty? || value == "_" ? nil : value
      end

      def self.visit(node, state)
        if node.element?
          case node.name
          when "br" then state[:break] = true
          when "hr" then state[:ended] = true # the page footer
          when TitusPahlaviParser::MARKER then header(node, state)
          end
        elsif node.text? && !state[:ended]
          lane = lane_of(node, state[:lanes])
          if lane.nil?
            state[:break] = true if node.text.match?(/\p{Space}/)
          elsif lane.first == :text
            accumulate(state, lane, node.text)
          end
        end
      end

      # A Level/XLevel header: record its value; a LINE header opens the
      # next passage; any header after text closes the open passage.
      def self.header(marker, state)
        label, value = header_label_value(marker)
        key = label_key(label)
        if value.empty? || value == "_"
          state[:context].delete(key)
        else
          state[:context][key] = value
        end
        anchor = marker.parent.css("a[name]").first&.[]("name")
        if state[:current] && !state[:current][:text].strip.empty?
          state[:current] = nil
          state[:pending] = nil
        end
        if label.match?(LINE_LABEL)
          state[:current] = nil
          state[:pending] = anchor || ""
        elsif state[:pending].nil?
          state[:pending] = anchor || ""
        end
      end

      # "Line of Manuscript: 1" → ["Line of Manuscript", "1"] (the header
      # span's own text, before any nested element).
      def self.header_label_value(marker)
        text = marker.parent.xpath("./text()").map(&:text).join.gsub(/\p{Space}+/, " ").strip
        label, value = text.split(":", 2)
        [label.to_s.strip, value.to_s.strip]
      end

      def self.label_key(label)
        label.downcase.gsub(/[^\p{Alnum}]+/, "_").gsub(/\A_|_\z/, "")
      end

      # [:text, language, script] / [:heading] for a lane text node, nil for
      # excluded markup. Cached per lane holder.
      def self.lane_of(node, cache)
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        return nil if holder.nil?

        cache.fetch(holder.pointer_id) { cache[holder.pointer_id] = classify(holder) }
      end

      def self.classify(holder)
        id = holder["id"]
        return nil if NON_LANE.match?(id) || !LANE_SHAPE.match?(id)

        if (m = SOGDIAN_LANE.match(id))
          script = SCRIPTS.fetch(m[:script]) { unknown!("script code #{m[:script].inspect} in lane #{id.inspect}") }
          lane_role(holder, m, [:text, "sog", script])
        elsif (m = TURKIC_LANE.match(id))
          lane_role(holder, m, [:text, "oui", nil])
        elsif (m = PARTHIAN_LANE.match(id))
          lane_role(holder, m, [:text, "xpr", nil])
        elsif (m = SANSKRIT_LANE.match(id))
          return [:heading] if heading?(holder)

          lane_role(holder, m, [:text, "san", nil])
        else
          unknown!("content lane #{id.inspect}")
        end
      end

      def self.lane_role(holder, match, role)
        flavor = match[:flavor]
        unknown!("flavor #{flavor.inspect} in lane #{holder['id'].inspect}") unless flavor.delete(TEXT_FLAVORS).empty?
        return nil if in_note?(holder, match[:size])

        role
      end

      def self.unknown!(what)
        raise Nabu::ParseError, "titus-sogdian: unknown #{what} — classify it before ingesting"
      end

      # The outer lane span (word links carry the lane id themselves).
      def self.lane_span(holder)
        ([holder] + holder.ancestors.to_a).find { |e| e.element? && e.name == "span" } || holder
      end

      # A run continuing a title/subtitle span (directly beside it).
      def self.heading?(holder)
        span = lane_span(holder)
        [span.previous_element, span.next_element].any? { |e| e && HEADING_SPAN.match?(e["id"].to_s) }
      end

      # A small-type run beside a `voc` note (past adjacent small runs) is
      # a form the note quotes. Body-size runs are text.
      def self.in_note?(holder, size)
        return false if size.to_i >= BODY_SIZE

        span = lane_span(holder)
        %i[previous_element next_element].any? do |direction|
          sibling = span.public_send(direction)
          sibling = sibling.public_send(direction) while sibling && small_run?(sibling["id"].to_s)
          sibling && NOTE_SPAN.match?(sibling["id"].to_s)
        end
      end

      def self.small_run?(id)
        m = [SOGDIAN_LANE, TURKIC_LANE, PARTHIAN_LANE, SANSKRIT_LANE].lazy.filter_map { |re| re.match(id) }.first
        !m.nil? && m[:size].to_i < BODY_SIZE
      end

      def self.accumulate(state, (_kind, language, script), text)
        current = state[:current] || open_section(state, text)
        return if current.nil?

        broke = state[:break]
        state[:break] = false
        current[:text] << " " if broke && !current[:text].empty?
        current[:text] << text
        current[:runs] << [language, script, text]
      end

      # Open the pending passage at its first text, snapshotting the
      # context. Text before any header quarantines the page.
      def self.open_section(state, text)
        return nil if text.strip.empty?

        if state[:pending].nil?
          raise Nabu::ParseError, "titus-sogdian: content text #{text.strip.inspect} before any header"
        end

        state[:current] = { anchor: state[:pending], context: state[:context].dup, text: +"", runs: [] }
        state[:sections] << state[:current]
        state[:break] = false
        state[:current]
      end

      def self.finish_all(raw)
        raw.filter_map { |section| finish(section) }
      end

      # Language: Sogdian when any Sogdian run is present (foreign runs then
      # ride the `embedded` annotation), else the one foreign language.
      def self.finish(section)
        text = clean(section[:text])
        return nil if text.empty?

        languages = section[:runs].map(&:first).uniq
        language = languages.include?("sog") ? "sog" : languages.first
        if !languages.include?("sog") && languages.size > 1
          raise Nabu::ParseError, "titus-sogdian: line #{section[:anchor].inspect} mixes " \
                                  "#{languages.inspect} with no Sogdian run"
        end

        embedded = section[:runs].reject { |lang, _, _| lang == language }
                                 .group_by(&:first)
                                 .transform_values { |runs| clean(runs.map(&:last).join(" ")) }
        Section.new(key: key_for(section[:context]), context: section[:context], anchor: section[:anchor],
                    text: text, language: language, scripts: section[:runs].filter_map { |r| r[1] }.uniq,
                    embedded: embedded)
      end

      # The dotted citation (a component's own trailing period drops so the
      # dots stay separators: "A.L." → "A.L"); "_" when no field is known.
      def self.key_for(context)
        parts = KEY_FIELDS.filter_map { |field| context[field]&.delete_suffix(".") }.reject(&:empty?)
        parts.empty? ? "_" : parts.join(".")
      end

      def self.clean(text)
        TitusPahlaviParser.clean(text)
      end
    end
  end
end
