# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Manichaica parser family — the Manichaean Middle Iranian corpora on
    # TITUS (the Manichaean Reader, the Corpus of Manichaean Texts arranged by
    # editions, the Sermon of the Soul). The same frame-based machinery and the
    # same two interleaved header hierarchies as the Pahlavi books
    # (TitusPahlaviParser — read_page, the `<!Level N>` / `<!XLevel N>` marker
    # rewrite, header labels and text cleaning are composed from there), with
    # three differences the census (2026-10-10, 11 real pages over the three
    # corpora) forced:
    #
    # == Sections are keyed by the headers' own VALUES, never by the anchors
    #
    # The anchors join every component with "_", and here the components
    # themselves carry underscores — manuscript sigla (`M_7984`, `So_18248`),
    # item ids (`Huy._I`, `b_I_A`, `ii_App.`, `AR_Frgm.D_+_O`), lines
    # (`4_[1]_(2208)`) — so a positional split of `MHC_Huy._I` would read the
    # DIFFERENT item `Huy.`. Each Level-N header's value (the text after its
    # colon: "Item of Ed.: Huy._I") sets level N of a running stack and drops
    # the deeper levels; the section key is the stack. A page that opens below
    # level 1 (every page after a corpus's first: "Item of Ed.: 8" anchored
    # `MKG_8`, the edition header never repeated) seeds its missing ancestors
    # from that first anchor minus the header's own "_value" suffix — the
    # leading levels (corpus/edition sigla) never carry underscores, the last
    # missing one takes the remainder.
    #
    # == Physical locations are the XLevel values IN FORCE
    #
    # XLevel headers (Manuscript / Part of Ms. / Page of Ms. / Line of Ms.,
    # the Reader's Page of edition and Editor / Edition, the Corpus's
    # "… in Reader" cross-references) each set their value — an EMPTY value
    # (TITUS's own reset idiom) removes it. A section's location is the
    # snapshot at its first lane text, so a "Line of Manuscript" header that
    # follows the Paragraph header on the same line is included.
    #
    # == Lanes: one family, several languages
    #
    # `<mi|is><lang>t<s|l><flavor><size>`: `s` the TRANSCRIPTION, `l` the
    # TRANSLITERATION; the two-letter <lang> code names the language — census:
    # mp Manichaean Middle Persian (pal), pt Parthian (xpr), sg Sogdian (sog),
    # tk the Sermon's Turkic appendix (oui); ph is the Pahlavi books' own code
    # (titus-pahlavi census, 1,573 pages) — pal. A `v` flavor is a manuscript
    # WITNESS reading or a note-quoted form (the Sermon's per-manuscript lines,
    # every form inside its `nc12` notes): apparatus, always. Every other run
    # is text at ANY size (`*22` headings, the Turkic `*l12` transliteration);
    # the census found no non-variant form quoted inside a note (the only
    # note-flanked runs are text around a "?" query mark). A section's
    # language is the lane carrying most of its text; all lanes it carries
    # are listed. A lane id under a content prefix (mi/is/ii) outside this
    # shape — or with an unknown <lang> — quarantines the page.
    module TitusManichaicaParser
      # One text-bearing citation section: +components+ the header values
      # from level 1 down (empties kept); +level+ N and +label+ ("Paragraph");
      # +text+ NFC; +language+ the predominant lane language, +languages+ all
      # of them (sorted); +location+ the XLevel values in force at its first
      # text; +transliteration+ when the section also carries a
      # transcription; +representation+ "transcription" / "transliteration" /
      # both joined with "+".
      Section = Data.define(:components, :level, :label, :text, :language, :languages, :location,
                            :transliteration, :representation)

      LANE = /\A(?:mi|is)(?<lang>[a-z]{2})t(?<rep>[sl])(?<flavor>[cvx]*)(?<size>\d+)\z/
      LANGUAGES = { "mp" => "pal", "ph" => "pal", "pt" => "xpr", "sg" => "sog", "tk" => "oui" }.freeze
      REPRESENTATIONS = { "s" => "transcription", "l" => "transliteration" }.freeze
      CONTENT_PREFIX = /\A(?:mi|is|ii)[a-z]/

      MARKER = TitusPahlaviParser::MARKER

      # Parse one page's HTML into ordered text-bearing sections. Raises
      # Nabu::ParseError on a structural surprise (invalid UTF-8, lane text
      # before any citation header, an unknown content lane, a page-start
      # header with no anchor to seed its ancestors from).
      def self.parse(html)
        raise Nabu::ParseError, "titus-manichaica: page is not valid UTF-8" unless html.valid_encoding?

        doc = Nokogiri::HTML(TitusPahlaviParser.mark_levels(html))
        state = { sections: [], current: nil, stack: [], xlevels: {}, break: false, ended: false,
                  lane_cache: {} }
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        state[:sections].filter_map { |section| finish(section) }
      end

      def self.visit(node, state)
        if node.element?
          case node.name
          when "br" then state[:break] = true
          when "hr" then state[:ended] = true # the page footer (the only <HR>s)
          when MARKER then marker(node, state)
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

      def self.marker(node, state)
        if node["data-kind"] == "level"
          open_section(node, state)
        else
          key = location_key(TitusPahlaviParser.header_label(node))
          value = header_value(node)
          value.empty? ? state[:xlevels].delete(key) : state[:xlevels][key] = value
        end
      end

      # The header's value: the text after its label's colon, whitespace
      # (the &nbsp; padding) trimmed, inner runs joined with "_".
      def self.header_value(marker)
        text = marker.parent.xpath("./text()").map(&:text).join
        text.split(":", 2)[1].to_s.gsub(/\A\p{Space}+|\p{Space}+\z/, "").gsub(/\p{Space}+/, "_")
      end

      # "Line of Manuscript" / "Line of Ms." → "line_of_ms" (the Reader and
      # the other corpora spell the same physical levels two ways).
      def self.location_key(label)
        label.downcase.gsub(/\bmanuscript\b/, "ms").gsub(/[^\p{Alnum}]+/, "_").gsub(/\A_|_\z/, "")
      end

      def self.open_section(marker, state)
        level = marker["data-n"].to_i
        value = header_value(marker)
        stack = seed_ancestors(state[:stack], level, value, marker)
        state[:stack] = stack.first(level - 1) + [value]
        return if state[:current] && state[:current][:key] == state[:stack]

        state[:current] = { key: state[:stack].dup, level: level, label: TitusPahlaviParser.header_label(marker),
                            location: nil, buffers: { "transcription" => +"", "transliteration" => +"" },
                            chars: Hash.new(0), representations: [] }
        state[:sections] << state[:current]
        state[:break] = false
      end

      # Fill levels 1..N-1 the page never declared from the header's first
      # anchor (see the module doc). Levels already on the stack win.
      def self.seed_ancestors(stack, level, value, marker)
        missing = level - 1 - stack.size
        return stack unless missing.positive?

        anchor = marker.parent.at_css("a[name]")&.[]("name")
        if anchor.nil?
          raise Nabu::ParseError, "titus-manichaica: level-#{level} header #{value.inspect} opens the page " \
                                  "with no anchor to place it"
        end

        prefix = anchor.end_with?("_#{value}") ? anchor.delete_suffix("_#{value}") : anchor
        known = stack.join("_")
        rest = if known.empty? then prefix
               elsif prefix == known then "" # the skipped levels are genuinely absent
               else prefix.delete_prefix("#{known}_")
               end
        parts = rest.empty? ? [] : rest.split("_", missing)
        stack + parts + Array.new(missing - parts.size, "")
      end

      # [language, representation] for a lane text node, nil for excluded
      # markup or apparatus. Cached per lane holder.
      def self.lane_of(node, cache = {})
        holder = node.ancestors.find { |a| a.element? && a["id"] }
        return nil if holder.nil?

        cache.fetch(holder.pointer_id) { cache[holder.pointer_id] = classify(holder["id"]) }
      end

      def self.classify(id)
        if (m = LANE.match(id)) && LANGUAGES.key?(m[:lang])
          return nil if m[:flavor].include?("v")

          [LANGUAGES.fetch(m[:lang]), REPRESENTATIONS.fetch(m[:rep])]
        elsif CONTENT_PREFIX.match?(id)
          raise Nabu::ParseError, "titus-manichaica: unknown content lane #{id.inspect} — classify it before ingesting"
        end
      end

      # A witness / note-quoted lane (`v` flavor) — the cheap byte needle the
      # adapter's discovery can use.
      def self.variant_lane?(id)
        m = LANE.match(id)
        !m.nil? && m[:flavor].include?("v")
      end

      def self.accumulate(state, (language, representation), text)
        current = state[:current]
        if current.nil?
          return if text.strip.empty?

          raise Nabu::ParseError,
                "titus-manichaica: content text #{text.strip.inspect} before any citation header"
        end

        current[:location] ||= state[:xlevels].dup unless text.strip.empty?
        broke = state[:break]
        state[:break] = false
        buffer = current[:buffers][representation]
        buffer << " " if !buffer.empty? && (broke || current[:last_buffer] != representation)
        buffer << text
        current[:last_buffer] = representation
        current[:chars][language] += text.strip.length
        current[:representations] << representation
      end

      def self.finish(section)
        transcription = TitusPahlaviParser.clean(section[:buffers]["transcription"])
        transliteration = TitusPahlaviParser.clean(section[:buffers]["transliteration"])
        text = transcription.empty? ? transliteration : transcription
        return nil if text.empty?

        languages = section[:chars].select { |_language, count| count.positive? }
        Section.new(
          components: section[:key], level: section[:level], label: section[:label], text: text,
          language: languages.max_by { |language, count| [count, language] }.first,
          languages: languages.keys.sort, location: section[:location] || {},
          transliteration: transcription.empty? || transliteration.empty? ? nil : transliteration,
          representation: section[:representations].uniq.sort.join("+")
        )
      end
    end
  end
end
