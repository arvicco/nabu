# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"

module Nabu
  module Adapters
    # TITUS Pahlavi parser family — the Zoroastrian Middle Persian book
    # editions on TITUS (Ardā Wirāz, Bundahišn, Dēnkard, the Zand, …). The
    # same frame-based 1990s machinery as the Avestan and Osco-Umbrian
    # corpora (sequential <prefix>NNN.htm pages, a "Next part" chain,
    # machine-generated <A NAME> anchors), but with one structural twist the
    # Avestan family cannot absorb: TWO interleaved hierarchies.
    #
    # == Level vs XLevel — the edition's own header comments
    #
    # Every header span carries an SGML-ish comment naming its kind:
    #
    #   <span id=h3><!Level 3>Sentence: 2<A NAME="AV_1_2">…<A NAME="AV_1_2_1_3">…</span>
    #   <span id=h5><!XLevel 5>Line of edition: 3<A NAME="AV_1_1_1_3">…</span>
    #
    # `<!Level N>` is the CITATION hierarchy (Book / Chapter / Sentence,
    # Text / Chapter / Paragraph, … / Verse — labels vary by edition);
    # `<!XLevel N>` the PHYSICAL one (page and line of the printed edition,
    # manuscript folio,line locations like Bundahišn's IBd/TD1/TD2/DH). A
    # sentence routinely starts mid-line, so the line anchors fall INSIDE
    # sentences — an anchor-driven walk (the Avestan family) would chop every
    # sentence at each line. Here only a Level header opens a section, keyed
    # by the first N components of its first anchor; XLevel headers never
    # do. libxml drops `<!…>` comments, so #parse first rewrites each into a
    # marker element the walk can see.
    #
    # == The full anchor carries the physical location
    #
    # A Level-N header's LAST anchor is the machine-generated full position:
    # the logical components, then one component per XLevel in XLevel-number
    # order (component index k-1 is XLevel k). `Bd._I_1_1_2_1,1_3,7_2,7_1,14`
    # is Bundahišn I.1 at page 1, line 2, IBd 1,1, TD1 3,7, TD2 2,7, DH 1,14
    # — so each section's start location is read exactly from its own
    # anchor, labeled by the page's XLevel headers (a label the page never
    # declares falls back to "xlevel_<k>" — raw, never guessed).
    #
    # == Lanes: what is text
    #
    # The nearest ancestor carrying an id decides a text node's lane (word
    # links carry the lane id themselves; header spans `h<N>`, footnote
    # markers `fn`, notes `nc*`/`n*`, titles, and the data-entry block all
    # fall outside the vocabulary and are excluded by that one rule — the
    # nested Sentence header inside a text lane never leaks its label).
    # Text lanes: `mipht[s|l]…` — `s` the edition's TRANSCRIPTION, `l` its
    # TRANSLITERATION (Aramaeograms in capitals, MacKenzie-style) — at body
    # (16) and heading (22) size, plus the invocation lanes (`miphtsc12`,
    # `miphtsc16`: "pad nām ī yazdān"). Embedded AVESTAN quotations (`ii*`
    # lanes, the Avestan corpus's own lane prefix) stay in the running text
    # — the Bundahišn quotes the Ahuna Vairya inside its sentence — and are
    # also collected for an annotation. The small-size apparatus lanes
    # (`miphtlc12` proposed reading, `miphtlv12` manuscript reading,
    # `miphtlx12`/`miphtl12` legend glyphs) are excluded; any OTHER
    # `mipht…`/`ii…` id is a new lane — quarantine, never a silent skip.
    #
    # A line break (`<BR>`, or any whitespace-bearing non-lane text — the
    # layout newline, a line header) between lane runs becomes a single
    # space; adjacent lane spans with nothing between join verbatim
    # (Bundahišn's "vairiiō" + "-ē"; a footnote marker "*" is no break). Upstream
    # editorial sigla ({!}, [ ], < >, \) are canonical text and kept.
    module TitusPahlaviParser
      # One text-bearing citation section: +components+ the raw logical
      # anchor components (empties preserved); +level+ N and +label+ the
      # header's own words ("Sentence"); +text+ NFC; +location+ the physical
      # start position ({"page" => "1", "line" => "2", "ibd_location" => …});
      # +avestan+ the embedded Avestan quotation text (nil when none);
      # +representation+ "transcription"/"transliteration".
      Section = Data.define(:components, :level, :label, :text, :location, :avestan, :representation)

      # Text lanes → the representation they carry.
      TEXT_LANES = {
        "miphts16" => "transcription", "miphts22" => "transcription",
        "miphtsc12" => "transcription", "miphtsc16" => "transcription",
        "miphtl16" => "transliteration", "miphtl22" => "transliteration"
      }.freeze

      # Embedded Avestan quotation lanes (Bundahišn ch. I: `iija16` the
      # quotation, `iipz16` its bracketed editorial variant).
      AVESTAN_LANES = %w[iija16 iipz16].freeze

      # Censused apparatus lanes — excluded, never text (mhd001 notes,
      # the snstr transliteration legend).
      APPARATUS_LANES = %w[miphtlc12 miphtlv12 miphtlx12 miphtl12].freeze

      # An id shaped like a content lane; anything matching that no
      # vocabulary above knows quarantines the page.
      LANE_SHAPE = /\A(?:mipht|ii)[a-z]*\d*\z/

      MARKER = "nabu-level"
      LEVEL_COMMENT = /<!(X?)Level\s+(\d+)>/

      # Parse one page's HTML into ordered text-bearing sections. Raises
      # Nabu::ParseError on a structural surprise (lane text before any
      # citation header, an unknown content lane).
      def self.parse(html)
        doc = Nokogiri::HTML(mark_levels(html))
        xlabels = xlevel_labels(doc)
        state = { sections: [], current: nil, break: false, ended: false }
        TitusAvestanParser.walk(doc) { |node| visit(node, state, xlabels) }
        state[:sections].filter_map { |section| finish(section) }
      end

      # Rewrite each `<!Level N>` / `<!XLevel N>` comment into a marker
      # element (libxml silently drops the comment form).
      def self.mark_levels(html)
        html.gsub(LEVEL_COMMENT) do
          kind = ::Regexp.last_match(1).empty? ? "level" : "xlevel"
          %(<#{MARKER} data-kind="#{kind}" data-n="#{::Regexp.last_match(2)}"></#{MARKER}>)
        end
      end

      # XLevel number → its label on this page ("Page of edition", …).
      def self.xlevel_labels(doc)
        doc.css(%(#{MARKER}[data-kind="xlevel"])).to_h do |marker|
          [marker["data-n"].to_i, header_label(marker)]
        end
      end

      def self.visit(node, state, xlabels)
        if node.element?
          case node.name
          when "br" then state[:break] = true
          when "hr" then state[:ended] = true # the page footer (the only <HR>s)
          when MARKER then open_section(node, state, xlabels) if node["data-kind"] == "level"
          end
        elsif node.text?
          return if state[:ended]

          lane = lane_of(node)
          if lane
            accumulate(state, lane, node.text)
          elsif node.text.match?(/\p{Space}/)
            state[:break] = true # layout whitespace / a header between lane runs
          end
        end
      end

      # A Level-N header: key = the first N components of its first anchor.
      # The same key as the open section continues it (the jamasp
      # "Sentence: _" shape — a short anchor naming its parent).
      def self.open_section(marker, state, xlabels)
        anchors = marker.parent.css("a[name]").map { |a| a["name"] }
        return if anchors.empty?

        level = marker["data-n"].to_i
        comps = TitusAvestanParser.split_components(anchors.first).first(level)
        return if state[:current] && state[:current][:comps] == comps

        state[:current] = { comps: comps, level: level, label: header_label(marker),
                            location: location(anchors.last, level, xlabels),
                            text: +"", avestan: [], representations: [] }
        state[:sections] << state[:current]
        state[:break] = false
      end

      # The header's own label: the text before the first colon in the
      # header span ("Page of ed.: 90" → "Page of ed.").
      def self.header_label(marker)
        text = marker.parent.xpath("./text()").map(&:text).join
        text.split(":", 2).first.to_s.gsub(/\p{Space}+/, " ").strip
      end

      # The physical start location from the full anchor: component k-1 is
      # XLevel k (only components deeper than the header's own level; empty
      # ones are absent levels).
      def self.location(anchor, level, xlabels)
        comps = TitusAvestanParser.split_components(anchor)
        comps.each_with_index.with_object({}) do |(value, index), loc|
          k = index + 1
          next if k <= level || value.empty?

          loc[location_key(xlabels[k], k)] = value
        end
      end

      def self.location_key(label, xlevel)
        return "xlevel_#{xlevel}" if label.nil? || label.empty?
        return "page" if label.match?(/\APage\b/i)
        return "line" if label.match?(/\ALine\b/i)

        label.downcase.gsub(/[^\p{Alnum}]+/, "_").gsub(/\A_|_\z/, "")
      end

      # [:text, representation] / [:avestan, nil] for a lane text node, nil
      # for excluded markup. An unknown content-shaped lane raises.
      def self.lane_of(node)
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        id = holder && holder["id"]
        return nil if id.nil?
        return [:text, TEXT_LANES.fetch(id)] if TEXT_LANES.key?(id)
        return [:avestan, nil] if AVESTAN_LANES.include?(id)
        return nil if APPARATUS_LANES.include?(id) || !LANE_SHAPE.match?(id)

        raise Nabu::ParseError, "titus-pahlavi: unknown content lane #{id.inspect} — classify it before ingesting"
      end

      def self.accumulate(state, (kind, representation), text)
        current = state[:current]
        if current.nil?
          return if text.strip.empty?

          raise Nabu::ParseError,
                "titus-pahlavi: content text #{text.strip.inspect} before any citation header"
        end

        broke = state[:break]
        state[:break] = false
        current[:text] << " " if broke
        current[:text] << text
        if kind == :avestan
          # Contiguous Avestan chunks (a word and its <SUP> mark) form ONE
          # run; a break or an intervening Pahlavi chunk starts the next.
          current[:avestan] << +"" if broke || current[:last_kind] != :avestan
          current[:avestan].last << text
        else
          current[:representations] << representation
        end
        current[:last_kind] = kind
      end

      def self.finish(section)
        text = clean(section[:text])
        return nil if text.empty?

        avestan = section[:avestan].map { |run| clean(run) }.reject(&:empty?).join(" ")
        Section.new(
          components: section[:comps], level: section[:level], label: section[:label], text: text,
          location: section[:location], avestan: avestan.empty? ? nil : avestan,
          representation: section[:representations].uniq.join("+").then { |r| r.empty? ? nil : r }
        )
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
