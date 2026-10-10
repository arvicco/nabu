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
    # Lanes are classified by FAMILY, never by a literal id list (the live
    # corpus carries sizes and flavors no sample shows): `mipht<s|l>…<size>`
    # — `s` the edition's TRANSCRIPTION, `l` its TRANSLITERATION
    # (Aramaeograms in capitals) — and `ii<code><size>`, Avestan-script runs
    # (quotations, Pazand) that stay in the running text, the Bundahišn
    # quoting the Ahuna Vairya inside its sentence, and are also collected
    # for an annotation. Apparatus is excluded by two rules: a `v` flavor
    # (manuscript variant) anywhere, and a run of any size whose
    # neighbouring span is a small-type editorial note (`nc12`) — the forms
    # a note quotes. A section carrying BOTH renderings keeps the transcription as
    # text and the transliteration as an annotation. Any other id under a
    # content prefix is a new lane — quarantine, never a silent skip. Other
    # language lanes (`vonps*`, New Persian versions in vdp) fall outside
    # the vocabulary and are excluded.
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
      # +transliteration+ the paired transliteration when the section also
      # carries a transcription (nil otherwise); +representation+ the
      # renderings present ("transcription", "transliteration", or both).
      Section = Data.define(:components, :level, :label, :text, :location, :avestan, :transliteration,
                            :representation)

      # The Pahlavi lane family: mipht + s (transcription) / l
      # (transliteration) + flavor letters + font size, ANY size. Flavors
      # (full-corpus census of 1,573 pages, 2026-10-10): none = running
      # text; c = invocation/colophon (text) or — small, inside a note — a
      # proposed reading; x = a specially marked word INSIDE the running
      # text (Dēnkard 6's "a'ōn", 424×; Andarz's "ty<U>c</U>yh") or — small,
      # inside a note — a quoted form; v = a manuscript variant reading,
      # always apparatus.
      PAHLAVI_LANE = /\Amipht(?<rep>[sl])(?<flavor>[cvx]*)(?<size>\d+)\z/
      REPRESENTATIONS = { "s" => "transcription", "l" => "transliteration" }.freeze

      # Avestan-script lanes (the Avestan corpus's own `ii` prefix), any
      # size: ja/aa Avestan quotations (Bundahišn's Ahuna Vairya, the Zand's
      # Avestan lemmata), pz Pazand; a trailing v is a variant (apparatus).
      AVESTAN_LANE = /\Aii(?<code>[a-z]+)(?<size>\d+)\z/

      # Any id under a content-lane prefix that neither family shape knows
      # quarantines the page — a new lane must be classified, never skipped.
      CONTENT_PREFIX = /\A(?:mipht|ii)/

      # The small-type editorial-note span (apparatus notes; the body-size
      # nc16/nc22 captions are not notes).
      NOTE_SPAN = /\Anc12\z/

      # A note that is only a cross-reference beside running text
      # ("{= Y. 72,11b}", "{= Gj. 163}" in jamasp) — not an apparatus note.
      CROSS_REFERENCE = /\A[{(]=/

      # Body type size; smaller lane runs are the note-quotation suspects.
      BODY_SIZE = 16

      MARKER = "nabu-level"
      LEVEL_COMMENT = /<!(X?)Level\s+(\d+)>/

      # A multibyte UTF-8 sequence SEVERED by a tag: its lead (and any
      # continuation) bytes end one element, its remaining continuation
      # bytes open the next text. Census 2026-10-10, exactly 2 of 1,573
      # pages: snstrl/snstr002 "LCḎr̄'\xCC</a>\xB1" (U+0331) and zwy/zwy005
      # "štr\xCA</a>\xBC" (U+02BC).
      SEVERED_SEQUENCE = %r{([\xC2-\xF4][\x80-\xBF]{0,2})(</?[A-Za-z][^<>]*>)([\x80-\xBF]{1,3})}n

      # Read one page as valid UTF-8. A page TITUS served with a severed
      # sequence is repaired by rejoining the bytes AFTER the tag: the
      # completed character becomes the first character of the following
      # text — in both census cases the same lane span's text, so it
      # attaches to the word it was cut from (no break between them). Any
      # invalidity the repair cannot fix is a quarantine (ParseError naming
      # the page), never an encoding exception escaping to abort the sync.
      def self.read_page(path)
        bytes = File.binread(path)
        html = bytes.dup.force_encoding(Encoding::UTF_8)
        return html if html.valid_encoding?

        repaired = repair_severed(bytes)
        return repaired if repaired.valid_encoding?

        raise Nabu::ParseError, "titus-pahlavi: #{path} is not valid UTF-8 (beyond the severed-sequence repair)"
      end

      def self.repair_severed(bytes)
        bytes.b.gsub(SEVERED_SEQUENCE, '\2\1\3').force_encoding(Encoding::UTF_8)
      end

      # Parse one page's HTML into ordered text-bearing sections. Raises
      # Nabu::ParseError on a structural surprise (invalid UTF-8, lane text
      # before any citation header, an unknown content lane).
      def self.parse(html)
        raise Nabu::ParseError, "titus-pahlavi: page is not valid UTF-8" unless html.valid_encoding?

        doc = Nokogiri::HTML(mark_levels(html))
        xlabels = xlevel_labels(doc)
        state = { sections: [], current: nil, break: false, ended: false, lane_cache: {} }
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

          lane = lane_of(node, state[:lane_cache])
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
                            buffers: { "transcription" => +"", "transliteration" => +"" },
                            avestan: [], representations: [] }
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
      # for excluded markup. Classification is by lane FAMILY (see the
      # module doc), cached per lane holder; an id under a content-lane
      # prefix with no known family shape raises.
      def self.lane_of(node, cache = {})
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        return nil if holder.nil?

        cache.fetch(holder.pointer_id) { cache[holder.pointer_id] = classify(holder) }
      end

      # A manuscript-variant lane (`v` flavor / `…v` Avestan code) — always
      # apparatus.
      def self.variant_lane?(id)
        if (m = PAHLAVI_LANE.match(id)) then m[:flavor].include?("v")
        elsif (m = AVESTAN_LANE.match(id)) then m[:code].end_with?("v")
        else false
        end
      end

      def self.classify(holder)
        id = holder["id"]
        if (m = PAHLAVI_LANE.match(id))
          return nil if variant_lane?(id) || in_note?(holder, m[:size])

          [:text, REPRESENTATIONS.fetch(m[:rep])]
        elsif (m = AVESTAN_LANE.match(id))
          return nil if variant_lane?(id) || in_note?(holder, m[:size])

          [:avestan, nil]
        elsif CONTENT_PREFIX.match?(id)
          raise Nabu::ParseError, "titus-pahlavi: unknown content lane #{id.inspect} — classify it before ingesting"
        end
      end

      # A lane run set inside a small-type editorial note is apparatus
      # quoting a form, never running text. Looking outward from the run
      # (past any adjacent small-type lane runs — vdp's "Jmp. <iija12>u
      # <miphtlc12>lw <iija12>e" chains):
      #   - a SMALL run (< 16) with an `nc12` note on EITHER side is in a
      #     note: "prp. <miphtlc12> für Ms. <miphtlv12>" (mhd), "[Anmerkung:
      #     <miphtlx12> ließe sich …]" (andos013);
      #   - a BODY-size run is in a note with `nc12` on BOTH sides, or when
      #     an `nc12` note INTRODUCES it ("L4a <miphtl16>՚cyc</…>; DR",
      #     "…); Jmp <miphtl16>ˣMN" — vdp's note paragraphs quote forms at
      #     body size) — unless that note is a mere cross-reference
      #     ("{= Y. 72,11b}" before a jamasp sentence). A note FOLLOWING
      #     running text never pulls the text in (jamasp's "{= Gj. 163}";
      #     vdp003 §42's unclosed lane span, which upstream's broken markup
      #     makes the sibling of the next note paragraph).
      # Runs NOT inside a note are text at any size: the invocation lanes
      # (`miphtsc12` "pad nām ī yazdān"), vdp's small-type bracketed gloss
      # verses (`miphts12`). Body-size notes (`nc16` "cf. Pat. 1.1", `nc22`
      # captions) sit beside real text and are not apparatus notes.
      def self.in_note?(holder, size)
        span = ([holder] + holder.ancestors.to_a).find { |e| e.element? && e.name == "span" } || holder
        sides = [beyond_small_runs(span, :previous_element), beyond_small_runs(span, :next_element)]
        notes = sides.map { |e| e && NOTE_SPAN.match?(e["id"].to_s) }
        return notes.any? if size.to_i < BODY_SIZE

        notes.all? || (notes.first && !CROSS_REFERENCE.match?(sides.first.text.strip))
      end

      def self.beyond_small_runs(span, direction)
        sibling = span.public_send(direction)
        sibling = sibling.public_send(direction) while sibling && small_run?(sibling["id"].to_s)
        sibling
      end

      def self.small_run?(id)
        m = PAHLAVI_LANE.match(id) || AVESTAN_LANE.match(id)
        !m.nil? && m[:size].to_i < BODY_SIZE
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
        # An Avestan-script run belongs to the rendering it is quoted in.
        key = kind == :avestan ? (current[:last_rep] || "transcription") : representation
        buffer = current[:buffers][key]
        buffer << " " if !buffer.empty? && (broke || current[:last_buffer] != key)
        buffer << text
        current[:last_buffer] = key
        if kind == :avestan
          # Contiguous Avestan chunks (a word and its <SUP> mark) form ONE
          # run; a break or an intervening Pahlavi chunk starts the next.
          current[:avestan] << +"" if broke || current[:last_kind] != :avestan
          current[:avestan].last << text
        else
          current[:last_rep] = representation
          current[:representations] << representation
        end
        current[:last_kind] = kind
      end

      # The transcription is the passage text; a section that ALSO carries
      # the transliteration (andoshn, vdp, vd-19p, … pair them per section)
      # keeps it as the "transliteration" annotation. A transliteration-only
      # section (mhd, snstrl, zwy) has it as its text.
      def self.finish(section)
        transcription = clean(section[:buffers]["transcription"])
        transliteration = clean(section[:buffers]["transliteration"])
        text = transcription.empty? ? transliteration : transcription
        return nil if text.empty?

        avestan = section[:avestan].map { |run| clean(run) }.reject(&:empty?).join(" ")
        Section.new(
          components: section[:comps], level: section[:level], label: section[:label], text: text,
          location: section[:location], avestan: avestan.empty? ? nil : avestan,
          transliteration: transcription.empty? || transliteration.empty? ? nil : transliteration,
          representation: section[:representations].uniq.sort.join("+").then { |r| r.empty? ? nil : r }
        )
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
