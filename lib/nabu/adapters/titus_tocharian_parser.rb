# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "titus_avestan_parser"
require_relative "titus_pahlavi_parser"

module Nabu
  module Adapters
    # TITUS Tocharian corpus parser family (P114-1a). The same frame-based
    # TITUS machinery as the Avestan and Osco-Umbrian corpora (sequential
    # tochaNNN.htm pages on a "Next part" chain, machine-generated <A NAME>
    # anchors, the 1990s `</sPAN>` markup), with its own content model —
    # the edition's "synoptic" arrangement: every manuscript LINE is given
    # twice, "in a plain transcriptive and a transliterative (syllabic)
    # notation" (the editorial header's words, tocha001.htm).
    #
    # == Anchors (censused over 13 live pages, 2026-10-07)
    #
    #   TochA                      language        (no section)
    #   TochA_THT                  collection      (no section)
    #   TochA_THT_<ms>             manuscript      — the THT number
    #   TochA_THT_<ms>_<part>      leaf side       — Sieg & Siegling's own
    #                                                number + a/b (recto/verso)
    #   TochA_THT_<ms>_<part>_<l>  LINE            — the passage grain; the
    #                                                bilingual pages split a
    #                                                line into 1a/1b/1c
    #                                                sub-lines by language
    #
    # Deeper anchors are a structural surprise — ParseError.
    #
    # == Lanes (`<span id=…16>`, all content lanes carry the 16 suffix)
    #
    # A FAMILY, not a list (LANE_FAMILY): io + language stem + optional x
    # (syllabic) + optional c + 16 —
    #
    #   iotoa16 / iotoac16       Tocharian A transcription → the passage TEXT
    #   iotoax16 / iotoaxc16     Tocharian A syllabic transliteration
    #                            → the "syllabic" annotation (optional — some
    #                            pages give only the transcription)
    #   iosbpl16 / iosbplc16     Sanskrit transcription (the bilingual
    #                            sub-lines, e.g. "kṣemeṇa", "na tr[ā]ṇaṃm asti
    #                            jarā") — claimed `san`
    #   iosbplx16 / iosbplxc16   Sanskrit syllabic
    #
    # The `c`-suffixed variants occur page-wise (and once mixed with the
    # plain id on one page); the edition does not say what the suffix
    # marks, so both spellings map to the same role and language — never
    # interpreted further. A span id SHAPED like a content lane that the
    # family does not know quarantines the page (a new lane must be
    # classified, never dropped). `iocd12` is the THT catalogue block
    # (12-size: the find signature, the THT number, the German catalogue
    # note, the per-side Vorderseite/Rückseite label) — collected as
    # metadata, never text; a lane span QUOTED inside that prose (a 12-size
    # `iotoa12`/`iotoax12` word, or a 16-size run, sandwiched between two
    # catalogue spans: 15 cases, census 2026-10-10) is part of the note and
    # folds into it. `iocd16` is the per-line preservation remark ("(nicht
    # erhalten)") — the line's +note+, never text. `h*`/`n16`/`title`/
    # `textdescr`/`bibliogr` are layout and the editorial header; so is the
    # recto/verso label after a facsimile-image link (normally `n16`; twice
    # mis-typed with a lane id, tocha119/tocha253).
    #
    # == Language claims
    #
    # A line's language is its TRANSCRIPTION lane's (only the syllabic lane's
    # when the line gives no transcription). The syllabic lane is a notation
    # of the same line and does not vote: census 2026-10-10 found two lines
    # (1087_453a_2b, 1095_461a_2b) whose Tocharian transcription is mirrored
    # by a Sanskrit-typed syllabic lane carrying the same Tocharian words. A
    # syllabic run typed for another language that the line ALSO mirrors in
    # its own language (a trailing "hā hā hā" on 981_347b_3, with no
    # transcription counterpart) rides as the "inline_syllabic" annotation
    # keyed by that language, never as the line's claim. One page (tocha414,
    # 5 lines) interleaves Sanskrit phrases and their Tocharian rendering in
    # ONE line's transcription: the line claims the corpus language (xto),
    # its Sanskrit runs ride as the "inline" annotation (the interleaving
    # order is not kept in the text — declared coarseness). Any other
    # transcription mix still quarantines. Whitespace never votes: the 1990s
    # markup leaves spans unclosed, so blank text leaks lane ancestry across
    # lines (997_363_2b).
    #
    # == Text discipline
    #
    # Verbatim: the edition's damage/restoration notation (//// lacuna
    # edges, [..] damaged, (..) restored, _ and . for lost/illegible akṣaras,
    # + for a partially preserved one, capitals for the virāma/Fremdzeichen
    # forms, \ the virāma) rides untouched. The ONE exclusion is a <sup>
    # holding only digits: the print edition's footnote reference (TITUS
    # carries the number but not the note) — apparatus, collected as the
    # "footnotes" annotation. Whitespace collapses; NFC at the boundary.
    module TitusTocharianParser
      # One keyed line: +components+ the anchor tail after the collection
      # prefix ([ms, part, line]); +text+ the NFC transcription ("" for a
      # note-only line); +syllabic+ the syllabic lane (nil when the page gives
      # none); +language+ the lane vote (nil for a note-only line);
      # +footnotes+ the footnote numbers; +side+ the part's own catalogue
      # label (Vorderseite/Rückseite, "?" verbatim) or nil; +note+ the
      # iocd16 preservation remark or nil; +inline+ / +inline_syllabic+ the
      # off-language transcription / syllabic runs keyed by language
      # ({ "san" => "hā hā hā - - -" }), empty when none.
      Line = Data.define(:components, :text, :syllabic, :language, :footnotes, :side, :note, :inline,
                         :inline_syllabic) do
        def note_only? = text.empty?
      end

      # One manuscript block's catalogue: +number+ the THT number (anchor),
      # +catalogue+ the manuscript-level iocd12 lines in order.
      Manuscript = Data.define(:number, :catalogue)

      # The parsed page: its manuscripts (in order), its text lines, and its
      # note-only lines (a line or line range carrying only a preservation
      # remark — no passage, the remark rides document metadata).
      Page = Data.define(:manuscripts, :lines, :notes)

      # The structural anchor prefix every section carries; the bare
      # language/collection anchors open nothing.
      ANCHOR_PREFIX = "TochA_THT"

      # ms / part / line — 3 is the deepest level the edition mints.
      MAX_LEVELS = 3

      # The content-lane FAMILY: io + a language stem + an optional x (the
      # syllabic transliteration) + an optional c (page-wise variant, never
      # interpreted) + the 16 size. Stem → language.
      LANE_FAMILY = /\Aio(?<stem>toa|sbpl)(?<syllabic>x?)c?16\z/
      LANE_LANGUAGES = { "toa" => :xto, "sbpl" => :san }.freeze

      # The corpus language: the claim of a line whose transcription
      # interleaves it with another language.
      PRIMARY_LANGUAGE = :xto

      # The per-line editorial remark lane (`iocd16`, the 16-size sibling of
      # the catalogue lane): census 2026-10-10 over all 467 pages — 152
      # spans, every one "(nicht erhalten)" / "nicht erhalten" under a line
      # (or line-range, "4-6") anchor that carries no other lane text. A
      # preservation note, not text: collected as the line's +note+.
      NOTE_LANE = "iocd16"

      # The catalogue lane (manuscript and part notes).
      CATALOGUE_LANE = "iocd12"

      # A span id shaped like a content lane (the TITUS `io…16` family) —
      # anything matching this that the family does not know is a NEW lane.
      LANE_SHAPE = /\Aio[a-z]+16\z/

      # A lane span that can be quoted inside catalogue prose: any io* lane
      # (12- or 16-size) but the catalogue/note lanes themselves.
      QUOTABLE_LANE = /\Aio(?!cd)[a-z]+(?:12|16)\z/

      # Read one page as valid UTF-8: TITUS occasionally severs a multibyte
      # character around a tag (tocha314 "k..\xC3</a>\x84\\" = Ä); the
      # titus-pahlavi repair rejoins it. Beyond the repair → ParseError.
      def self.read_page(path)
        bytes = File.binread(path)
        html = bytes.dup.force_encoding(Encoding::UTF_8)
        return html if html.valid_encoding?

        repaired = TitusPahlaviParser.repair_severed(bytes)
        return repaired if repaired.valid_encoding?

        raise Nabu::ParseError, "titus-tocharian: #{path} is not valid UTF-8 (beyond the severed-sequence repair)"
      end

      # Parse one page's HTML. Raises Nabu::ParseError on a structural
      # surprise: an over-deep anchor, lane text before any line anchor, an
      # unknown content-shaped lane id, or a line whose transcription lanes
      # vote two languages.
      def self.parse(html)
        raise Nabu::ParseError, "titus-tocharian: page is not valid UTF-8" unless html.valid_encoding?

        state = { manuscripts: [], lines: [], current: nil, part_side: nil, part_open: false }
        doc = Nokogiri::HTML(html)
        fold_quoted_lanes(doc)
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        finished = state[:lines].filter_map { |line| finish(line) }
        Page.new(
          manuscripts: state[:manuscripts].map { |m| Manuscript.new(number: m[:number], catalogue: m[:catalogue]) },
          lines: finished.reject(&:note_only?),
          notes: finished.select(&:note_only?)
        )
      end

      # A lane span sandwiched between two catalogue spans is a quotation
      # inside the catalogue prose (tocha373: "… die akṣara: <iotoaxc16>rmeṣṣe
      # kartse tāko</iotoaxc16> zu lesen sind."): its text and the following
      # catalogue span merge into the preceding one, so the note reads whole.
      def self.fold_quoted_lanes(doc)
        doc.xpath("//span[@id='#{CATALOGUE_LANE}']").each do |span|
          loop do
            quoted = span.next_sibling
            tail = quoted&.next_sibling
            break unless quoted_lane?(quoted) && catalogue_span?(tail)

            [quoted, tail].each do |node|
              node.children.each { |child| span.add_child(child) }
              node.remove
            end
          end
        end
      end

      def self.quoted_lane?(node)
        node&.element? && node.name == "span" && QUOTABLE_LANE.match?(node["id"].to_s)
      end

      def self.visit(node, state)
        if (comps = section_components(node))
          open_section(comps, state)
        elsif catalogue_span?(node)
          note = clean(node.text)
          record_catalogue(note, state) unless note.empty?
        elsif node.text? && !image_label?(node) && (lane = lane_of(node))
          return if blank?(node.text) && state[:current].nil?
          raise Nabu::ParseError, "titus-tocharian: lane text before any line anchor" if state[:current].nil?

          accumulate(state[:current], lane, node)
        end
      end

      def self.open_section(comps, state)
        case comps.size
        when 1
          state[:manuscripts] << { number: comps[0], catalogue: [] }
          state[:current] = nil
          state[:part_side] = nil
          state[:part_open] = false
        when 2
          state[:current] = nil
          state[:part_side] = nil
          state[:part_open] = true
        else
          state[:part_open] = false
          state[:current] = { comps: comps, text: [], syllabic: [], note: +"", footnotes: [],
                              side: state[:part_side] }
          state[:lines] << state[:current]
        end
      end

      # Catalogue notes before a part's first line label the part (its
      # side); before any part they describe the manuscript.
      def self.record_catalogue(note, state)
        if state[:part_open]
          state[:part_side] = [state[:part_side], note].compact.join(" ")
        elsif state[:current].nil? && (manuscript = state[:manuscripts].last)
          manuscript[:catalogue] << note
        end
      end

      # The anchor-tail components when +node+ is a structural anchor under
      # the collection prefix, else nil (bare language/collection included).
      def self.section_components(node)
        return nil unless node.element? && node.name == "a"

        name = node["name"]
        return nil unless name&.start_with?("#{ANCHOR_PREFIX}_")

        comps = TitusAvestanParser.split_components(name.delete_prefix("#{ANCHOR_PREFIX}_"))
        return comps if (1..MAX_LEVELS).cover?(comps.size) && comps.none?(&:empty?)

        raise Nabu::ParseError,
              "titus-tocharian: anchor #{name.inspect} has #{comps.size} components (expected 1..#{MAX_LEVELS})"
      end

      # The outermost catalogue span (its link children are walked past by
      # the lane rule: iocd12 is not a content lane).
      def self.catalogue_span?(node)
        node&.element? && node.name == "span" && node["id"] == CATALOGUE_LANE
      end

      # The recto/verso label of a facsimile-image link: text in an <a> that
      # directly follows an <a> wrapping an <img> — layout, whatever id the
      # generator gave it.
      def self.image_label?(node)
        link = node.parent
        return false unless link&.name == "a"

        image_link = link.previous_element
        image_link&.name == "a" && !image_link.at_xpath(".//img").nil?
      end

      # [role, language] for a lane text node, or nil for excluded markup.
      # The NEAREST id-bearing ancestor decides: the generator sometimes
      # eats a line's closing `</span><span id=n16>` (leaving the residue
      # "|Tn16" in the text — 315 times, kept verbatim), so a lane span stays
      # open and swallows the next `h5` "Line: N" heading; walking past the
      # heading's own id would read the heading as lane text. An unknown
      # content-shaped lane id raises.
      def self.lane_of(node)
        id = node.ancestors.lazy.map { |ancestor| ancestor["id"] }.find { |candidate| !candidate.nil? }
        return nil if id.nil?

        if (match = LANE_FAMILY.match(id))
          return [match[:syllabic].empty? ? :text : :syllabic, LANE_LANGUAGES.fetch(match[:stem])]
        end
        return [:note, nil] if id == NOTE_LANE
        return nil unless LANE_SHAPE.match?(id)

        raise Nabu::ParseError, "titus-tocharian: unknown content lane #{id.inspect} — classify it before ingesting"
      end

      def self.accumulate(line, (role, language), node)
        if footnote?(node)
          line[:footnotes] << node.text.strip if role == :text
          return
        end

        case role
        when :note then line[:note] << node.text
        else append_run(line[role], language, node.text)
        end
      end

      # Lane text kept as consecutive same-language runs, so an off-language
      # run can be told apart at finish. Blank text never opens a run of its
      # own language (leaked ancestry, see Language claims).
      def self.append_run(runs, language, text)
        if runs.last && (runs.last[0] == language || blank?(text))
          runs.last[1] << text
        else
          runs << [language, +text]
        end
      end

      # A digits-only <sup>: the print edition's footnote reference.
      def self.footnote?(node)
        node.parent&.name == "sup" && node.text.strip.match?(/\A\d+\z/)
      end

      def self.finish(line)
        text_runs = clean_runs(line[:text])
        syllabic_runs = clean_runs(line[:syllabic])
        note = clean(line[:note])
        return nil if text_runs.empty? && syllabic_runs.empty? && note.empty?
        return note_only(line, note) if text_runs.empty? && syllabic_runs.empty?

        language = line_language(line[:comps], text_runs.empty? ? syllabic_runs : text_runs)
        text, inline = split_runs(text_runs, language, mirror: false)
        syllabic, inline_syllabic = split_runs(syllabic_runs, language, mirror: true)
        # A syllabic-only line never occurred in the census; stay honest.
        text = syllabic if text.empty?
        Line.new(components: line[:comps], text: text, syllabic: syllabic.empty? ? nil : syllabic,
                 language: language.to_s, footnotes: line[:footnotes], side: line[:side],
                 note: note.empty? ? nil : note, inline: inline, inline_syllabic: inline_syllabic)
      end

      def self.clean_runs(runs)
        runs.map { |language, run| [language, clean(run)] }.reject { |_, run| run.empty? }
      end

      def self.note_only(line, note)
        Line.new(components: line[:comps], text: "", syllabic: nil, language: nil, footnotes: line[:footnotes],
                 side: line[:side], note: note, inline: {}, inline_syllabic: {})
      end

      # The deciding runs' language (the transcription's; the syllabic
      # lane's only when the line has no transcription): one language is the
      # claim; a mix that includes the corpus language (PRIMARY_LANGUAGE —
      # the tocha414 bilingual interleave) claims it, the rest riding
      # inline; any other mix quarantines.
      def self.line_language(comps, runs)
        languages = runs.map(&:first).uniq
        return languages.first if languages.size == 1
        return PRIMARY_LANGUAGE if languages.include?(PRIMARY_LANGUAGE)

        raise Nabu::ParseError,
              "titus-tocharian: line #{comps.join('_').inspect} mixes languages " \
              "#{languages.inspect} — one line, one language claim"
      end

      # [own, inline]: the runs in the line's language join into the lane's
      # text; runs typed for another language are inline material keyed by
      # that language. With +mirror+ (the syllabic lane) and NO own-language
      # run, the lane IS the line's notation whatever its id says (the
      # 453a_2b / 461a_2b mirrors).
      def self.split_runs(runs, language, mirror:)
        own, other = runs.partition { |run_language, _| run_language == language }
        return [runs.map(&:last).join(" "), {}] if mirror && own.empty?

        inline = other.group_by(&:first).to_h { |run_language, rs| [run_language.to_s, rs.map(&:last).join(" ")] }
        [own.map(&:last).join(" "), inline]
      end

      def self.blank?(text)
        text.match?(/\A\p{Space}*\z/)
      end

      def self.clean(text)
        Nabu::Normalize.nfc(text.gsub(/\p{Space}+/, " ").strip)
      end
    end
  end
end
