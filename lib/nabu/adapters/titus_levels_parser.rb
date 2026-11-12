# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"
require_relative "titus_old_prussian_parser"

module Nabu
  module Adapters
    # TITUS "levels" parser family — the frame-based editions whose header
    # spans carry the `<!Level N>` / `<!XLevel N>` comments (the machinery
    # titus_pahlavi reads), shared by the Old Lithuanian, Old Albanian and
    # Old Frisian editions. Each adapter supplies its own LANE vocabulary
    # (Lanes); the walk, the unit grain and the quarantine rules are one.
    #
    # == Units: the citation header, or the printed line
    #
    #   <span id=h4><!Level 4>Verse: 1<A NAME="Donelait._Met._1_1">…</span>
    #   <span id=h5><!XLevel 5>Line: 9<A NAME="Mazv._Cat._I._Decal._18/22_9">…</span>
    #
    # `<!Level N>` headers are the CITATION hierarchy (Verse, Sentence,
    # Paragraph, and in the Wolfenbüttel Postil and Matrënga the printed
    # Line); `<!XLevel N>` the physical one (page, manuscript page, Bible
    # reference). The diplomatic editions (Mažvydas, Buzuku) cite only down
    # to the part or chapter and carry the printed LINE as an XLevel — a
    # Part-grain unit would be the whole page, so an XLevel header labeled
    # "Line" opens a unit too. Every other XLevel (Page, "Page of ms. A",
    # Reference) never opens one: its value rides the open unit's location.
    # A unit's identity is its header's FIRST anchor, verbatim (it rides the
    # passage urn); a header re-opening the open unit's anchor continues it.
    #
    # == Lanes
    #
    # The nearest ancestor carrying an id decides a text node's lane:
    #   <prefix><flavors><size>  the edition's language → the unit TEXT,
    #                            flavor letters from Lanes#text_flavors
    #                            (typography and quotation classes: x a
    #                            hyphen-broken fragment, b/i/r bold/italic/
    #                            roman, …); a flavor carrying f (footnote) or
    #                            v (variant / footnote-link holder) is
    #                            apparatus; any OTHER flavor letter
    #                            quarantines — a new lane is classified,
    #                            never guessed
    #   Lanes#others             other languages inside the unit (the Latin
    #                            of the prints and dictionaries) → one
    #                            annotation per language, never the text
    #   tm<size>                 a typographic mark (the "&" of "Pſ: 109 &
    #                            131.") — stays in the running text
    #   nc*/n*/nd*/…f<size>, headers, title furniture — excluded
    # Any other lane-shaped id quarantines the page. A small-type (< 16)
    # text run set beside an `nc12` editorial note is a note quoting a form
    # (Blanchus's "ξ = Albanian /th/, /dh/" legend) — apparatus.
    #
    # A unit with no text-lane run is not a passage (a Latin-only caption,
    # an empty Page header). Footnote links (the `fn` marker + its number)
    # are stripped first, the titus_old_prussian rule.
    module TitusLevelsParser
      # One unit: +anchor+ the header's first anchor (verbatim); +label+ the
      # header's own word ("Line", "Verse"); +text+ the NFC text lanes;
      # +others+ {annotation key => NFC text} for other-language runs;
      # +location+ {"page" => …} the physical location at the unit's open;
      # +extras+ {annotation key => NFC text} for per-flavor annotations.
      Unit = Data.define(:anchor, :label, :text, :others, :location, :extras)

      # An adapter's lane vocabulary. +prefixes+ the language's lane stems
      # ("bpal", "baal"); +text_flavors+ the flavor letters that are text;
      # +others+ {Regexp => annotation key} for other-language lane stems;
      # +flavor_annotations+ {letter => annotation key} — a flavor that rides
      # its own annotation instead of the text.
      Lanes = Data.define(:prefixes, :text_flavors, :others, :flavor_annotations) do
        def initialize(prefixes:, text_flavors:, others: {}, flavor_annotations: {})
          super
        end

        def family
          /\A(?:#{stems})(?<flavor>[a-z]*)(?<size>\d+)\z/
        end

        # The byte needle discovery uses: a text-flavored run of the language.
        def needle
          /<span id=(?:#{stems})[#{text_flavors}]*\d+>/i
        end

        private

        def stems = prefixes.sort_by { -_1.size }.map { Regexp.escape(_1) }.join("|")
      end

      MARKER = "nabu-level"
      LEVEL_COMMENT = /<!(X?)Level\s+(\d+)>/
      APPARATUS_FLAVOR = /[fv]/
      MARK_LANE = /\Atm\d+\z/
      # Notes, layout, footnote apparatus (…f12 / …fi12, the OP rule).
      EXCLUDED_LANE = /\A(?:nc|nd|n)\d+\z|fi?\d+\z/
      LANE_SHAPE = /\A[a-z]+\d+\z/
      NOTE_SPAN = /\Anc12\z/
      BODY_SIZE = 16

      # Parse one page into its ordered text-bearing units. Raises
      # Nabu::ParseError on a structural surprise: an unknown lane, or text
      # of the language before any unit header.
      def self.parse(html, lanes:, label: "titus")
        doc = Nokogiri::HTML(mark_levels(html))
        TitusOldPrussianParser.strip_footnote_links(doc)
        state = { units: [], current: nil, break: false, location: {}, cache: {}, lanes: lanes, label: label }
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        state[:units].filter_map { |unit| finish(unit) }
      end

      # libxml drops `<!…>` comments: rewrite each into a marker element.
      def self.mark_levels(html)
        html.gsub(LEVEL_COMMENT) do
          kind = ::Regexp.last_match(1).empty? ? "level" : "xlevel"
          %(<#{MARKER} data-kind="#{kind}" data-n="#{::Regexp.last_match(2)}"></#{MARKER}>)
        end
      end

      def self.visit(node, state)
        if node.element?
          case node.name
          when "br" then state[:break] = true
          when MARKER then header(node, state)
          end
        elsif node.text?
          lane = lane_of(node, state)
          if lane
            accumulate(state, lane, node.text)
          elsif node.text.match?(/\p{Space}/)
            state[:break] = true
          end
        end
      end

      # A header: a Level header or an XLevel "Line" opens a unit; every
      # header's value updates the physical location when it names one.
      def self.header(marker, state)
        label = header_label(marker)
        value = header_value(marker)
        xlevel = marker["data-kind"] == "xlevel"
        opens = !xlevel || label.match?(/\ALine\b/i)
        locate(state, label, value)
        return unless opens

        anchor = marker.parent.css("a[name]").map { |a| a["name"] }.first
        return if anchor.nil? || anchor.empty?
        return if state[:current] && state[:current][:anchor] == anchor

        state[:current] = { anchor: anchor, label: label, location: state[:location].dup,
                            text: +"", others: Hash.new { |h, k| h[k] = +"" },
                            extras: Hash.new { |h, k| h[k] = +"" }, texted: false }
        state[:units] << state[:current]
        state[:break] = false
      end

      # The header's own words before the colon ("Page of ms. A: 9r").
      def self.header_label(marker)
        own_text(marker).split(":", 2).first.to_s.gsub(/\p{Space}+/, " ").strip
      end

      def self.header_value(marker)
        own_text(marker).split(":", 2)[1].to_s.gsub(/\p{Space}+/, " ").strip
      end

      def self.own_text(marker)
        marker.parent.xpath("./text()").map(&:text).join
      end

      # Physical locations: a page (of the print, of a manuscript) runs on
      # until the next one, so each unit records the page it opens on; a
      # Bible reference (the Postil's XLevel "Reference", set mid-line)
      # belongs to the unit it sits in only. Citation labels are in the
      # anchor and never repeated here.
      def self.locate(state, label, value)
        return if value.empty?

        key = label.downcase.gsub(/[^\p{Alnum}]+/, "_").gsub(/\A_|_\z/, "")
        current = state[:current]
        if label.match?(/\A(?:Page|Folio)\b/i)
          state[:location][key] = value
          # A page header set right after a unit's own header (the Brokmer
          # Recht's "Sentence: 1" then "Page: 020") is that unit's page.
          current[:location][key] = value if current && current[:text].empty?
        elsif label.match?(/\AReference\b/i) && current
          refs = current[:location]
          refs[key] = [refs[key], value].compact.join("; ")
        end
      end

      # [:text] / [:extra, key] / [:other, key] / [:mark] for a lane text
      # node, nil for excluded markup. Cached per lane holder.
      def self.lane_of(node, state)
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        return nil if holder.nil?

        state[:cache].fetch(holder.pointer_id) do
          state[:cache][holder.pointer_id] = classify(holder, state[:lanes], state[:label])
        end
      end

      def self.classify(holder, lanes, label)
        id = holder["id"].to_s
        if (m = lanes.family.match(id))
          flavor = m[:flavor]
          return nil if flavor.match?(APPARATUS_FLAVOR) || in_note?(holder, m[:size])

          unknown = flavor.delete(lanes.text_flavors + lanes.flavor_annotations.keys.join)
          unless unknown.empty?
            raise Nabu::ParseError, "#{label}: unknown lane flavor #{id.inspect} — classify it before ingesting"
          end

          extra = lanes.flavor_annotations.find { |letter, _| flavor.include?(letter) }
          return extra ? [:extra, extra.last] : [:text]
        end
        return [:mark] if MARK_LANE.match?(id)
        return nil if EXCLUDED_LANE.match?(id)

        other = lanes.others.find { |pattern, _| pattern.match?(id) }
        return [:other, other.last] if other
        return nil unless LANE_SHAPE.match?(id) && !id.match?(/\Ah\d\z/)

        raise Nabu::ParseError, "#{label}: unknown content lane #{id.inspect} — classify it before ingesting"
      end

      # A small run beside an nc12 note is the note quoting a form.
      def self.in_note?(holder, size)
        return false if size.to_i >= BODY_SIZE

        span = ([holder] + holder.ancestors.to_a).find { |e| e.element? && e.name == "span" } || holder
        [span.previous_element, span.next_element].any? { |e| e && NOTE_SPAN.match?(e["id"].to_s) }
      end

      def self.accumulate(state, (kind, key), text)
        current = state[:current]
        if current.nil?
          return if text.strip.empty? || kind != :text

          raise Nabu::ParseError,
                "#{state[:label]}: text #{text.strip[0, 40].inspect} before any unit header"
        end
        buffer = case kind
                 when :text, :mark then current[:text]
                 when :other then current[:others][key]
                 when :extra then current[:extras][key]
                 end
        buffer << " " if state[:break] && !buffer.empty?
        state[:break] = false
        buffer << text
        current[:texted] = true if kind == :text && !text.strip.empty?
      end

      def self.finish(unit)
        text = clean(unit[:text])
        return nil unless unit[:texted] && text.match?(/[\p{L}\p{N}]/)

        Unit.new(anchor: unit[:anchor], label: unit[:label], text: text,
                 others: compact(unit[:others]), location: unit[:location], extras: compact(unit[:extras]))
      end

      def self.compact(buffers)
        buffers.transform_values { |value| clean(value) }.reject { |_key, value| value.empty? }
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
