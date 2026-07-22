# frozen_string_literal: true

module Nabu
  module Adapters
    # Line-oriented streaming parser for OpenITI mARkdown (P41-1) — the
    # structured plaintext of the Open Islamicate Texts Initiative corpus
    # (premodern Arabic/Persian; ~14k text versions, 2.3B words). First of
    # the "openiti-markdown" family; the OpenITI adapter (P41-2) composes it.
    # Censused P41-g from the six real fixtures in test/fixtures/openiti/ —
    # never invented:
    #
    #   ######OpenITI#                       ← magic value, line 1 (a
    #                                          Shamela-sourced file may carry
    #                                          a leading U+FEFF BOM before it)
    #   #META# <anything at all>             ← metadata block …
    #   #META#Header#End#                    ← … terminated exactly so
    #   ### | <header>  … ### ||||| <h5>     ← section header, level = pipes
    #   # <paragraph or verse>               ← unit start
    #   ~~<wrapped continuation>             ← same unit, upstream line wrap
    #
    # == The #META# block is OPAQUE (the four-vocabulary ruling)
    #
    # Four incompatible vocabularies appear across sources: KITAB numbered
    # keys (000.BookURI … 999.MiscINFO, TAB-separated "::"), Shamela legacy
    # (Arabic keys الكتاب/المتوفى/المصدر mixed with iso/bkid/cat and free
    # prose), PDL/Ganjoor minimal (title/ed_info/url), and eScriptorium OCR
    # (Creator/Created/avg transcription confidence). No key=value model
    # fits all four, so the block is captured as an ORDERED LIST OF RAW
    # LINES (provenance), nothing more. Machine-readable metadata lives in
    # the .yml sidecars and the central TSV — P41-2's business, not ours.
    #
    # == Units and continuations
    #
    # "# " starts a unit; "~~" continues it (single-space join). The Shamela
    # and OCR files also use a fused "# ~~" shape — censused as a
    # CONTINUATION, not a new unit (the sentence provably spans it, e.g. the
    # basmala+hamdala join in the Ibn Sīnā fixture). A wholly empty "~~"
    # line contributes nothing. Verse-vs-prose is decided from the finished
    # unit content:
    #
    #   - PDL notation (Persian, Hafiz):  # <n> hemi1 %~% hemi2
    #   - legacy notation (Arabic, JK):   # % hemi1 % hemi2 % <n>
    #
    # In the legacy form "%" delimits fields; "% %" is an EMPTY field
    # (dropped — it mints no hemistich); the trailing field is the verse
    # number when purely numeric. Fixture reality: a page-final verse can
    # carry the NEXT poem's meter note in its trailing field ("… %
    # PageV01P002 البحر : طويل 1") — canonical means canonical, the
    # non-numeric tail stays as a field and the verse number is honestly
    # nil. A verse unit's +hemistichs+ is the list; +text+ is the
    # single-space join (a display joiner is the caller's business).
    #
    # == Page markers and milestones (citation structure)
    #
    # PageVnnPnnn (volume+page, padding VARIES by source: PageV01P001
    # 3-digit Arabic, PageV01P01 2-digit PDL) and msNN milestones (ms1 vs
    # ms01) appear inline mid-line OR standalone. They are markup, never
    # words: both are stripped from unit text (single space restored) but
    # never lost. PageVnnPnnn marks the END of the page in question
    # (fixture-proven: the whole hadith precedes its single PageV01P001), so
    # a unit's (volume, page) is retro-assigned from the FIRST marker at or
    # after the unit's start — the page the unit starts on. A marker falling
    # inside a unit also rides that unit's +page_breaks+ (the unit spans
    # onto the next page; a break recorded at the unit's very end means the
    # page closed there). Units after the last marker stay honestly
    # unplaced (nil — trimmed fixtures end mid-page). Milestones attach to
    # the unit they close over: the open unit, else the last finished one.
    #
    # == What stays in the text verbatim (canonical means canonical)
    #
    # Meter notes (البحر : طويل), bracketed and inline folio notes ([67/ألف],
    # (73 ظ)), footnote digits fused to words (بجودیه1که), guillemet
    # marginalia « … », tatweel U+0640, hadith ordinals "1)". Never
    # "cleaned". Text is NFC at this boundary (Arabic/Persian are NOT on the
    # NFC exemption list).
    #
    # == Loudness (the aozora posture) vs ParseError
    #
    # Spec-defined tags with NO fixture in the mainstream corpus
    # (biographical "### $…", events "### @…", "### |EDITOR|", riwāyāt
    # "# $RWY$", NER @PERXX/@TOPXX, geo #$#PROV…) get a LOUD CENSUS —
    # counted per document under their shape, parsing continues, no
    # semantics invented. Census keys: "### <token>" (unrecognized header
    # shape, line dropped), "$TAG$" (unit-initial spec tag, kept in text),
    # "bare-line" (unmarked body line, kept as a prose unit), "image"
    # ("# ![…](…)" OCR page-image reference, kept out of text),
    # "orphan-continuation", "orphan-milestone", "empty-unit", and the first
    # token of any other unrecognized "#…" line. ParseError is reserved for
    # structural breakage: missing magic value, unterminated #META# header,
    # invalid UTF-8.
    class OpenitiMarkdownParser
      # One file's header peek: +bom+ (the file carried a leading U+FEFF)
      # and +meta_lines+ — the #META# block as opaque raw lines, verbatim
      # (chomped, NFC), in order, blanks and the End marker excluded.
      Header = Data.define(:bom, :meta_lines)

      # One body unit. +kind+ is :prose, :verse or :section_header. +text+
      # is the marker-stripped content (verse: hemistichs joined by one
      # space). +hemistichs+/+verse_number+ ride verse units (else nil);
      # +level+ rides section headers (else nil). +section_path+ is the
      # enclosing header-text chain (a header includes itself). +volume+/
      # +page+ is the retro-assigned start position (nil after the last
      # marker); +page_breaks+ the [volume, page] markers that fell inside
      # the unit; +milestones+ the raw msNN tokens (padding preserved);
      # +annotations+ extras like {"auto" => true} on AUTO headers.
      Unit = Data.define(:kind, :text, :hemistichs, :verse_number, :level, :section_path,
                         :volume, :page, :page_breaks, :milestones, :annotations)

      # One file's body: units in document order + the loud census
      # (sorted shape → count; empty = clean).
      Body = Data.define(:units, :census)

      MAGIC = /\A######OpenITI#[ \t]*\z/
      META_END = /\A#META#Header#End#[ \t]*\z/
      # PageVnnPnnn (captures 1,2: volume, page) OR msNN (capture 3), plus
      # the marker's trailing whitespace — variable padding, inline or
      # standalone; removal leaves surrounding text single-spaced.
      ANY_MARKER = /(?:(?<![A-Za-z])PageV(\d+)P(\d+)(?!\d)|(?<![A-Za-z0-9])(ms\d+)(?![A-Za-z0-9]))[ \t]*/
      SECTION = /\A(\|{1,5})(?:[ \t]+(.*))?\z/
      IMAGE = /\A!\[[^\]]*\]\([^)]*\)\z/
      AUTO = /\AAUTO(?:[ \t]+|\z)/
      PDL_VERSE_NUMBER = /\A(\d+)[ \t]+/
      PDL_SPLIT = /[ \t]*%~%[ \t]*/
      SPEC_TAG = /\A\$[A-Z][A-Z_]*\$/
      private_constant :MAGIC, :META_END, :ANY_MARKER, :SECTION,
                       :IMAGE, :AUTO, :PDL_VERSE_NUMBER, :PDL_SPLIT, :SPEC_TAG

      EMPTY_ANNOTATIONS = {}.freeze
      AUTO_ANNOTATIONS = { "auto" => true }.freeze
      private_constant :EMPTY_ANNOTATIONS, :AUTO_ANNOTATIONS

      # Peek one file's magic value + #META# block; stops reading at
      # #META#Header#End#. +source+ is a path String or an IO.
      def header(source)
        walk = start_walk(source)
        each_content_line(source, walk) do |line|
          consume_header_line(line, walk)
          break if walk[:state] == :body
        end
        require_header!(walk)
        Header.new(bom: walk[:bom], meta_lines: walk[:meta])
      end

      # Parse one file's body into units + the loud census.
      def body(source)
        walk = start_walk(source)
        each_content_line(source, walk) do |line|
          if walk[:state] == :body
            body_line(line, walk)
          else
            consume_header_line(line, walk)
          end
        end
        require_header!(walk)
        flush(walk)
        Body.new(units: finalize_units(walk), census: walk[:census].sort.to_h)
      end

      private

      def start_walk(source)
        { path: label(source), state: :magic, bom: false, meta: [],
          units: [], census: Hash.new(0), pending: [], open: nil, stack: [] }
      end

      def label(source)
        return source if source.is_a?(String)

        (source.respond_to?(:path) && source.path) || "<io>"
      end

      # The streaming spine: chomped, NFC-normalized lines (per-line NFC is
      # safe — every line ends at a hard boundary, no combining sequence
      # crosses it). Invalid UTF-8 is structural breakage.
      def each_content_line(source, walk)
        raw = source.is_a?(String) ? File.foreach(source, encoding: Encoding::UTF_8) : source.each_line
        raw.each do |line|
          yield nfc_line(line, walk)
        end
      end

      def nfc_line(line, walk)
        Normalize.nfc(line.chomp)
      rescue Normalize::EncodingError => e
        raise ParseError, "#{walk[:path]}: invalid UTF-8 in mARkdown: #{e.message}"
      end

      # -- header ------------------------------------------------------------

      def consume_header_line(line, walk)
        case walk[:state]
        when :magic then consume_magic(line, walk)
        when :meta
          if META_END.match?(line)
            walk[:state] = :body
          elsif !line.strip.empty?
            walk[:meta] << line
          end
        end
      end

      def consume_magic(line, walk)
        walk[:bom] = line.start_with?("\uFEFF")
        line = line.delete_prefix("\uFEFF")
        unless MAGIC.match?(line)
          raise ParseError, "#{walk[:path]}: missing OpenITI magic value ######OpenITI# on line 1"
        end

        walk[:state] = :meta
      end

      def require_header!(walk)
        case walk[:state]
        when :magic
          raise ParseError, "#{walk[:path]}: empty file — missing OpenITI magic value"
        when :meta
          raise ParseError, "#{walk[:path]}: unterminated #META# header (no #META#Header#End#)"
        end
      end

      # -- body: line dispatch -----------------------------------------------

      def body_line(line, walk)
        if line.start_with?("### ")
          flush(walk)
          section_line(line.delete_prefix("### "), walk)
        elsif line.start_with?("# ") || line == "#"
          paragraph_line(line[2..] || "", walk)
        elsif line.start_with?("~~")
          continuation(line[2..], walk)
        elsif line.start_with?("#")
          walk[:census][line.split(/[ \t]/, 2).first] += 1
        else
          bare_line(line, walk)
        end
      end

      def paragraph_line(content, walk)
        stripped = content.strip
        if IMAGE.match?(stripped)
          flush(walk)
          walk[:census]["image"] += 1
        elsif stripped.start_with?("~~")
          # The fused "# ~~" wrap (Shamela + OCR files): a continuation.
          continuation(stripped[2..], walk)
        else
          flush(walk)
          open_unit(walk)
          append(content, walk)
        end
      end

      def continuation(rest, walk)
        unless walk[:open]
          walk[:census]["orphan-continuation"] += 1
          open_unit(walk)
        end
        append(rest, walk)
      end

      # A line with no marker of its own: position markers are extracted
      # (standalone "PageV01P001 ms1" lines are pure position updates); any
      # textual residue is censused loudly but NOT dropped.
      def bare_line(line, walk)
        residue = extract_markers(line, walk)
        return if residue.empty?

        walk[:census]["bare-line"] += 1
        flush(walk)
        open_unit(walk)
        walk[:open][:parts] << residue
      end

      # -- section headers ----------------------------------------------------

      def section_line(content, walk)
        match = SECTION.match(content)
        return walk[:census]["### #{content.split(/[ \t]/, 2).first}"] += 1 unless match

        level = match[1].length
        text = extract_markers(match[2] || "", walk)
        auto = AUTO.match?(text)
        text = text.sub(AUTO, "") if auto
        walk[:stack] = (walk[:stack][0, level - 1] || []) << text
        # A title-less header (bare `### |`, or nothing left after the AUTO
        # strip — live corpus reality, P41-i1b) advances the section stack
        # but mints NO unit: an empty passage is invalid downstream, and the
        # census keeps the omission loud.
        return walk[:census]["empty-section-header"] += 1 if text.strip.empty?

        unit = open_unit(walk)
        unit.merge!(kind: :section_header, text: text, level: level,
                    annotations: auto ? AUTO_ANNOTATIONS : EMPTY_ANNOTATIONS,
                    section_path: walk[:stack].dup.freeze)
        finish(unit, walk)
      end

      # -- unit lifecycle -----------------------------------------------------

      def open_unit(walk)
        unit = { kind: :prose, text: nil, hemistichs: nil, verse_number: nil, level: nil,
                 section_path: walk[:stack].dup.freeze, volume: nil, page: nil,
                 page_breaks: [], milestones: [], annotations: EMPTY_ANNOTATIONS, parts: [] }
        walk[:pending] << unit
        walk[:open] = unit
      end

      def append(text, walk)
        part = extract_markers(text, walk)
        walk[:open][:parts] << part unless part.empty?
      end

      def flush(walk)
        unit = walk[:open]
        return unless unit

        content = unit[:parts].join(" ")
        if content.empty?
          walk[:census]["empty-unit"] += 1
          walk[:pending].delete(unit)
          walk[:open] = nil
        else
          census_spec_tag(content, walk)
          classify(unit, content)
          finish(unit, walk)
        end
      end

      # Move a completed builder into document order; it stays in
      # walk[:pending] until a page marker places it.
      def finish(unit, walk)
        walk[:units] << unit
        walk[:open] = nil
      end

      def census_spec_tag(content, walk)
        tag = content[SPEC_TAG]
        walk[:census][tag] += 1 if tag
      end

      # -- verse vs prose -----------------------------------------------------

      def classify(unit, content)
        hemistichs, number =
          if content.include?("%~%")
            pdl_verse(content)
          elsif content.start_with?("%")
            legacy_verse(content)
          end
        return unit[:text] = content if hemistichs.nil? || hemistichs.empty?

        unit.merge!(kind: :verse, hemistichs: hemistichs,
                    verse_number: number, text: hemistichs.join(" "))
      end

      # "# <n> hemi1 %~% hemi2" — the verse number leads (PDL/Ganjoor).
      def pdl_verse(content)
        number = content[PDL_VERSE_NUMBER, 1]
        rest = number ? content.sub(PDL_VERSE_NUMBER, "") : content
        [rest.split(PDL_SPLIT).map(&:strip).reject(&:empty?), number&.to_i]
      end

      # "# % hemi1 % hemi2 % <n>" — "%" delimits fields, "% %" is an empty
      # field, the trailing field is the verse number only when numeric.
      def legacy_verse(content)
        fields = content.split("%").map(&:strip)
        fields.shift # the empty slot before the leading "%"
        number = fields.pop if fields.last&.match?(/\A\d+\z/)
        [fields.reject(&:empty?), number&.to_i]
      end

      # -- position markers ---------------------------------------------------

      # Strip PageVnnPnnn + msNN from +text+, recording the events. Each
      # marker is consumed together with its trailing whitespace, so a
      # mid-line marker leaves a single space and a standalone marker
      # leaves nothing; edges are trimmed.
      def extract_markers(text, walk)
        text.gsub(ANY_MARKER) do
          match = Regexp.last_match
          match[3] ? record_milestone(match[3], walk) : record_page(match, walk)
          ""
        end.strip
      end

      # End-of-page semantics: this marker closes (volume, page), so every
      # unit begun since the previous marker STARTED on that page. A marker
      # with unit content before it also rides that unit's page_breaks.
      def record_page(match, walk)
        volume = match[1].to_i
        page = match[2].to_i
        walk[:pending].each { |unit| unit.merge!(volume: volume, page: page) }
        walk[:pending].clear
        open = walk[:open]
        return unless open

        content_before = !open[:parts].empty? ||
                         !match.pre_match.gsub(ANY_MARKER, "").strip.empty?
        open[:page_breaks] << [volume, page] if content_before
      end

      # Milestones also mark the end of their span: attach to the open
      # unit, else the last finished one.
      def record_milestone(token, walk)
        target = walk[:open] || walk[:units].last
        return walk[:census]["orphan-milestone"] += 1 unless target

        target[:milestones] << token
      end

      # -- finish -------------------------------------------------------------

      def finalize_units(walk)
        walk[:units].map do |unit|
          Unit.new(**unit.slice(:kind, :text, :hemistichs, :verse_number, :level, :section_path,
                                :volume, :page, :page_breaks, :milestones, :annotations))
        end
      end
    end
  end
end
