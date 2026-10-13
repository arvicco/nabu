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
    # == Levels come from the headings (census 2026-10-12, Tocharian B)
    #
    # The B corpus's later collections mint labels that themselves carry
    # underscores (London "TochB_BLK-IOL_Toch._2_r_1", Paris
    # "TochB_PK_NS_38_+_37._a__1", Berlin SHT "TochB_SHT_VI_1457a_…"), so an
    # anchor's level cannot be read by splitting it. The generator states
    # it instead: the anchor sits in an `h3` (manuscript), `h4` (page) or
    # `h5` (line) heading span, and each level's name extends its parent's
    # by "_<label>". A line straight under its manuscript (no page heading)
    # extends the manuscript by "__<label>" — an EMPTY page component, kept
    # empty. A second anchor in the same heading is an ALTERNATE numbering
    # (London's Hoernle "H.149…" numbers, Paris's "PK_…" sigla): on a line
    # it rides as the "alternate" annotation; the `h6` "Alternate page"
    # headings and the manuscript/page aliases restate that same numbering
    # and open nothing. An anchor outside a heading, or one whose name does
    # not extend its parent's, falls back to the underscore split (every
    # Tocharian A anchor and all but two Berlin B ones extend their parent
    # cleanly, so the split never decides a level there).
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
    #
    # == Profiles (the family's per-corpus constants)
    #
    # The anchor prefix(es — one per collection), the content-lane family,
    # its stem → language map and the corpus language are a PROFILE
    # (TOCHARIAN_A is the censused default; the Tocharian B adapter
    # declares its own). Everything else — the catalogue/note lanes, the
    # line discipline, the language claims — is the family's.
    #
    # A lane family may also admit a `v` notation (Tocharian B, Paris
    # collection: `iotobv16`, a second rendering of the line that repeats
    # the transcription in every censused case). The edition does not say
    # what it marks; it rides verbatim as the "variant" annotation, never
    # as text.
    module TitusTocharianParser
      # One keyed line: +components+ the anchor tail after the collection
      # prefix ([ms, part, line]); +text+ the NFC transcription ("" for a
      # note-only line); +syllabic+ the syllabic lane (nil when the page gives
      # none); +language+ the lane vote (nil for a note-only line);
      # +footnotes+ the footnote numbers; +side+ the part's own catalogue
      # label (Vorderseite/Rückseite, "?" verbatim) or nil; +note+ the
      # iocd16 preservation remark or nil; +inline+ / +inline_syllabic+ the
      # off-language transcription / syllabic runs keyed by language
      # ({ "san" => "hā hā hā - - -" }), empty when none; +variant+ the `v`
      # notation lane or nil; +alternate+ the line's alternate-numbering
      # anchor tail (see Levels) or nil.
      Line = Data.define(:components, :text, :syllabic, :language, :footnotes, :side, :note, :inline,
                         :inline_syllabic, :variant, :alternate) do
        def note_only? = text.empty?
      end

      # One manuscript block's catalogue: +number+ the manuscript label
      # (anchor; the THT number in Berlin), +collection+ the anchor's
      # collection ("THT", "BLK-IOL", "PK", "SHT"), +catalogue+ the
      # manuscript-level iocd12 lines in order.
      Manuscript = Data.define(:number, :collection, :catalogue)

      # The parsed page: its manuscripts (in order), its text lines, and its
      # note-only lines (a line or line range carrying only a preservation
      # remark — no passage, the remark rides document metadata).
      Page = Data.define(:manuscripts, :lines, :notes)

      # A corpus's anchor/lane constants (see Profiles above). +anchor_prefix+
      # is one collection prefix or a list of them.
      Profile = Data.define(:anchor_prefix, :lane_family, :lane_languages, :primary_language) do
        def anchor_prefixes = Array(anchor_prefix)
      end

      # The heading span ids that carry a structural anchor, by level.
      HEADING_LEVELS = { "h3" => 1, "h4" => 2, "h5" => 3 }.freeze

      # The lane-family notation letter → the line role it fills.
      NOTATION_ROLES = { "" => :text, "x" => :syllabic, "v" => :variant }.freeze

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

      # The censused Tocharian A profile — the family default.
      TOCHARIAN_A = Profile.new(anchor_prefix: ANCHOR_PREFIX, lane_family: LANE_FAMILY,
                                lane_languages: LANE_LANGUAGES, primary_language: PRIMARY_LANGUAGE)

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

      # Parse one page's HTML under +profile+ (default: Tocharian A). Raises
      # Nabu::ParseError on a structural surprise: an over-deep anchor, lane
      # text before any line anchor (a pre-anchor NOTE is catalogue — see
      # hold_pending_note), an unknown content-shaped lane id, or a line
      # whose transcription lanes vote two languages.
      def self.parse(html, profile: TOCHARIAN_A)
        raise Nabu::ParseError, "titus-tocharian: page is not valid UTF-8" unless html.valid_encoding?

        state = { manuscripts: [], lines: [], current: nil, part_side: nil, part_open: false, profile: profile,
                  manuscript_anchor: nil, part_anchor: nil, part_label: nil }
        doc = Nokogiri::HTML(html)
        fold_quoted_lanes(doc)
        TitusAvestanParser.walk(doc) { |node| visit(node, state) }
        flush_pending_note(state)
        finished = state[:lines].filter_map { |line| finish(line, profile) }
        Page.new(
          manuscripts: state[:manuscripts].map do |m|
            Manuscript.new(number: m[:number], collection: m[:collection], catalogue: m[:catalogue])
          end,
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
        profile = state[:profile]
        flush_pending_note(state) if note_boundary?(node)
        if (anchor = structural_anchor(node, profile))
          open_anchor(node, *anchor, state)
        elsif catalogue_span?(node)
          note = clean(node.text)
          record_catalogue(note, state) unless note.empty?
        elsif node.text? && !image_label?(node) && (lane = lane_of(node, profile))
          return hold_pending_note(node, state) if pending_note_text?(node, lane, state)
          return if blank?(node.text) && state[:current].nil?

          raise Nabu::ParseError, "titus-tocharian: lane text before any line anchor" if state[:current].nil?

          accumulate(state[:current], lane, node)
        end
      end

      # A pre-anchor note (ruled 2026-10-12): an iocd16 remark that arrives
      # BEFORE the first line of its manuscript or part — the manuscript-
      # level "fehlt 3/95" (the glass-plate inventory), a page heading's
      # "(0301v)" photo plate — is a catalogue-grade note, not a line's. Its
      # text nodes gather until the span ends (the next span or anchor), then
      # land where a catalogue note in that position lands: the part's label
      # inside an open part, else the manuscript catalogue. With no
      # manuscript open it has nowhere to land — still a structural surprise.
      def self.hold_pending_note(node, state)
        unless state[:part_open] || state[:manuscripts].any?
          raise Nabu::ParseError, "titus-tocharian: lane text before any line anchor"
        end

        (state[:pending_note] ||= +"") << node.text
      end

      # Note-lane text before any line: a note opens on its first non-blank
      # text; the blanks between its linked words then belong to it.
      def self.pending_note_text?(node, lane, state)
        state[:current].nil? && lane.first == :note && (state.key?(:pending_note) || !blank?(node.text))
      end

      def self.note_boundary?(node)
        node.element? && (node.name == "span" || (node.name == "a" && !node["name"].nil?))
      end

      def self.flush_pending_note(state)
        pending = state.delete(:pending_note)
        note = pending && clean(pending)
        record_catalogue(note, state) unless note.nil? || note.empty?
      end

      # Open the section a structural anchor names (see Levels): its level
      # from the heading, its components from the parent chain — or, off
      # the chain, from the underscore split. Alternate-numbering anchors
      # open nothing; a line's alias rides as its +alternate+.
      def self.open_anchor(node, name, prefix, state)
        heading = node.parent&.[]("id")
        return if heading == ALTERNATE_HEADING

        level = HEADING_LEVELS[heading]
        if level && alias_anchor?(node)
          record_alternate(name, state) if level == MAX_LEVELS
          return
        end

        comps = (level && chained_components(name, prefix, level, state)) || split_components(name, prefix)
        open_section(comps, name, collection_of(prefix), state)
      end

      # The `h6` "Alternate page" heading (see Levels).
      ALTERNATE_HEADING = "h6"

      # A second anchor in the same heading: the alternate numbering.
      def self.alias_anchor?(node)
        previous = node.previous_element
        !previous.nil? && previous.name == "a" && !previous["name"].nil?
      end

      def self.record_alternate(name, state)
        line = state[:current]
        return unless line && name.start_with?("#{line[:anchor]}_")

        line[:alternate] = name.delete_prefix("#{line[:anchor]}_")
      end

      # The components when +name+ extends its parent's anchor at +level+,
      # else nil (the caller falls back to the split).
      def self.chained_components(name, prefix, level, state)
        return nonempty([name.delete_prefix(prefix)]) if level == 1

        manuscript = state[:manuscript_anchor]
        return nil if manuscript.nil?

        number = state[:manuscripts].last[:number]
        if level == 2
          rest = tail_after(name, "#{manuscript}_")
          return rest && nonempty([number, rest])
        end

        part = state[:part_anchor]
        if part && (rest = tail_after(name, "#{part}_"))
          nonempty([number, state[:part_label], rest])
        elsif (rest = tail_after(name, "#{manuscript}__"))
          # A line straight under its manuscript: the page stays EMPTY.
          nonempty([number, rest]) && [number, "", rest]
        end
      end

      def self.nonempty(comps)
        comps.none?(&:empty?) ? comps : nil
      end

      def self.tail_after(name, head)
        name.start_with?(head) ? name.delete_prefix(head) : nil
      end

      # The underscore split (off the chain): 1..MAX_LEVELS non-empty
      # components, else a structural surprise.
      def self.split_components(name, prefix)
        comps = TitusAvestanParser.split_components(name.delete_prefix(prefix))
        return comps if (1..MAX_LEVELS).cover?(comps.size) && comps.none?(&:empty?)

        raise Nabu::ParseError,
              "titus-tocharian: anchor #{name.inspect} has #{comps.size} components (expected 1..#{MAX_LEVELS})"
      end

      # "TochB_BLK-IOL_" → "BLK-IOL".
      def self.collection_of(prefix)
        prefix.delete_suffix("_").split("_", 2).last
      end

      def self.open_section(comps, name, collection, state)
        case comps.size
        when 1
          state[:manuscripts] << { number: comps[0], collection: collection, catalogue: [] }
          state[:manuscript_anchor] = name
          state[:part_anchor] = nil
          state[:current] = nil
          state[:part_side] = nil
          state[:part_open] = false
        when 2
          state[:part_anchor] = name
          state[:part_label] = comps[1]
          state[:current] = nil
          state[:part_side] = nil
          state[:part_open] = true
        else
          state[:part_open] = false
          state[:current] = { comps: comps, anchor: name, text: [], syllabic: [], variant: [], note: +"",
                              footnotes: [], side: state[:part_side], alternate: nil }
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

      # [name, prefix] when +node+ is an anchor under one of the profile's
      # collection prefixes, else nil (bare language/collection included —
      # and the `h2` collection anchors, which only ever name the bare
      # prefix or an alternate of it, carry no level).
      def self.structural_anchor(node, profile)
        return nil unless node.element? && node.name == "a"

        name = node["name"]
        return nil if name.nil? || node.parent&.[]("id") == "h2"

        prefix = profile.anchor_prefixes.map { |p| "#{p}_" }.find { |p| name.start_with?(p) }
        prefix && [name, prefix]
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
      def self.lane_of(node, profile = TOCHARIAN_A)
        id = node.ancestors.lazy.map { |ancestor| ancestor["id"] }.find { |candidate| !candidate.nil? }
        return nil if id.nil?

        if (match = profile.lane_family.match(id))
          return [NOTATION_ROLES.fetch(match[:syllabic]), profile.lane_languages.fetch(match[:stem])]
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

      def self.finish(line, profile = TOCHARIAN_A)
        text_runs = clean_runs(line[:text])
        syllabic_runs = clean_runs(line[:syllabic])
        variant = clean_runs(line[:variant]).map(&:last).join(" ")
        note = clean(line[:note])
        return nil if text_runs.empty? && syllabic_runs.empty? && note.empty?
        return note_only(line, note) if text_runs.empty? && syllabic_runs.empty?

        language = line_language(line[:comps], text_runs.empty? ? syllabic_runs : text_runs,
                                 primary: profile.primary_language)
        text, inline = split_runs(text_runs, language, mirror: false)
        syllabic, inline_syllabic = split_runs(syllabic_runs, language, mirror: true)
        # A syllabic-only line (the Tocharian B Tumshuqese leaves, whose
        # iots16 transcription lane is always empty) carries the syllabic
        # lane as its text; stay honest.
        text = syllabic if text.empty?
        Line.new(components: line[:comps], text: text, syllabic: syllabic.empty? ? nil : syllabic,
                 language: language.to_s, footnotes: line[:footnotes], side: line[:side],
                 note: note.empty? ? nil : note, inline: inline, inline_syllabic: inline_syllabic,
                 variant: variant.empty? ? nil : variant, alternate: line[:alternate])
      end

      def self.clean_runs(runs)
        runs.map { |language, run| [language, clean(run)] }.reject { |_, run| run.empty? }
      end

      def self.note_only(line, note)
        Line.new(components: line[:comps], text: "", syllabic: nil, language: nil, footnotes: line[:footnotes],
                 side: line[:side], note: note, inline: {}, inline_syllabic: {}, variant: nil,
                 alternate: line[:alternate])
      end

      # The deciding runs' language (the transcription's; the syllabic
      # lane's only when the line has no transcription): one language is the
      # claim; a mix that includes the corpus language (+primary+ — the
      # tocha414 bilingual interleave) claims it, the rest riding inline;
      # any other mix quarantines.
      def self.line_language(comps, runs, primary: PRIMARY_LANGUAGE)
        languages = runs.map(&:first).uniq
        return languages.first if languages.size == 1
        return primary if languages.include?(primary)

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
