# frozen_string_literal: true

module Nabu
  module Adapters
    # Parser for the HSMS transcription format (P77-1) — the hsms family:
    # the Hispanic Seminary of Medieval Studies semi-paleographic
    # transcriptions as shipped in OSTA's transcriptions/TEXT.xxx.txt lane.
    #
    # == The format (censused from the two complete fixture files)
    #
    # A leading block of {RMK: ...} groups is the HSMS header (fixed slot
    # order: HSMS-NNNN text id, author, "[SIG] Title.", a date/edition slot
    # — empty "." in both fixtures — "City | Library | Shelfmark.",
    # transcriber). Then structure: [fol. Nr] folio milestones, {HD. ...}
    # headings, {CB1.}/{CB2.} column blocks whose closing brace rides the
    # END of their last text line, and inside the blocks the numbered
    # section markers {RMK: HSMS-NNNN-NNNN: Title.} — the corpus's citable
    # unit — with the transcription lines between them. Text carries the
    # HSMS markup verbatim: <ue> abbreviation expansions (<<x>> variant),
    # [*x] damaged-letter reconstructions, [^x] interlinear additions,
    # [x] editorial supplials, [ ] editorial word division, [??] lacunae,
    # (^x)/(x) scribal and editorial deletions, ¶ paragraph marks.
    #
    # == Grain and honesty rules
    #
    # Passage = one numbered section, citation = the section ordinal with
    # zero-padding stripped (the full HSMS-NNNN-NNNN id rides the "hsms"
    # annotation verbatim); duplicate ordinals take the house :b2 suffix.
    # Pre-section text — the {HD.} heading in practice — is the honest
    # `head` passage (searchable scribal text, never dropped; the openiti
    # headers-are-passages precedent). Folio and column milestones ride
    # annotations ("folios"/"columns", tags verbatim, never interpreted);
    # heading lines are additionally listed in "headings". Unknown brace
    # tags are censused loud in document metadata ("unrecognized_tags")
    # while their inner text still flows, and stray/unclosed braces are
    # censused likewise ("brace_defects" — the first-sync finding:
    # transcribers mix sibling and batched column closes, so counts
    # genuinely unbalance in ~2% of files) — no silent drops, ParseError
    # only for zero passages — the aozora posture, for a 663-file
    # corpus censused from two.
    #
    # == The search-form derivation (conventions §9; the ccmh-txt mold)
    #
    # Pristine text keeps the markup VERBATIM (canonical means canonical).
    # text_normalized is minted through the ONE folding boundary over
    # .search_source — a pure function of the stored text, so the form is
    # recomputable from the row alone: parenthesized deletions drop,
    # angle expansions resolve (innermost-out), bracket groups resolve
    # (reconstruction/addition marks stripped, lacunae drop, [ ] becomes
    # a space), pilcrows and line-break slashes become spaces, whitespace
    # squeezes. A line that would derive to nothing keeps its raw text
    # (text_normalized must never be empty).
    class HsmsParser
      # Scanner tokens in priority order: an inline RMK group (content
      # never carries a brace), a folio milestone, a container opening
      # ({TAG. or {TAG:), a bare closing brace. Split with the capture
      # group keeps the tokens; everything between them is text. Tags
      # admit `=` — the first-sync census over the real 663 files found
      # the whole =-family ({MIN=.} ×1707, {=DIAG.} ×974, {=DIAG=.}
      # ×688, {DIAG=.}, {=MIN=:}…); a rejected tag is not neutral, its
      # closing brace steals the enclosing column container's pop.
      TOKEN = /(\{RMK:[^}\n]*\}|\[fol\.[^\]\n]*\]|\{[A-Za-z0-9=]+[.:]|\})/
      RMK = /\A\{RMK:([^}]*)\}\z/
      FOLIO = /\A\[fol\.\s*([^\]]*?)\s*\]\z/
      OPEN = /\A\{([A-Za-z0-9=]+)[.:]\z/
      SECTION = /\A(HSMS-\d+-\d+):?\s*(.*)\z/m
      HSMS_ID = /\AHSMS-\d+\.?\z/
      COLUMN_TAG = /\ACB\d+\z/

      # The documented derivation text_normalized is minted from — pure
      # and deterministic over the stored passage text (the conformance
      # pin). Order matters: deletions before expansions (a deleted group
      # may contain them), expansions before brackets ([^<r>] nests).
      def self.search_source(text)
        source = text.gsub(/\(\^?[^)\n]*\)/, "")
        loop do
          resolved = source.gsub(/<<([^<>\n]*)>>/, '\1').gsub(/<([^<>\n]*)>/, '\1')
          break if resolved == source

          source = resolved
        end
        source = source.gsub(/\[([^\]\n]*)\]/) { bracket_reading(Regexp.last_match(1)) }
        source = source.tr("¶/", "  ").gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").strip
        source.empty? ? text : source
      end

      # One bracket group's reading: marks stripped ([*x] reconstruction,
      # [^x] addition, plain [x] supplial all read as x), an all-? lacuna
      # drops, a bare [ ] word division reads as a space.
      def self.bracket_reading(content)
        cleaned = content.tr("*^?", "")
        return cleaned unless cleaned.strip.empty?

        content.include?("?") ? "" : " "
      end

      def parse(path, urn:, language:, fallback_title:, extra_metadata: {})
        reset(path, urn, language)
        File.foreach(path).with_index(1) { |raw, lineno| process_line(raw.chomp, lineno) }
        @brace_defects << "end of file: unclosed {#{@stack.join('. {')}. implicitly closed" unless @stack.empty?
        close_passage
        build_document(fallback_title, extra_metadata)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def reset(path, urn, language)
        @path = path
        @urn = urn
        @language = language
        @header = []
        @header_open = true
        @stack = []
        @unrecognized = Hash.new(0)
        @brace_defects = []
        @folio = nil
        @pending_columns = []
        @pending_notes = []
        @current = nil
        @passages = []
        @citations = Hash.new(0)
        @empty_sections = []
        @line_buffer = []
        @line_heading = false
      end

      def process_line(line, lineno)
        line.split(TOKEN).each do |part|
          next if part.empty?

          if (match = RMK.match(part))
            rmk(Normalize.nfc(match[1].strip))
          elsif (match = FOLIO.match(part))
            folio(match[1])
          elsif (match = OPEN.match(part))
            open_container(match[1])
          elsif part == "}"
            close_container(lineno)
          else
            text(part)
          end
        end
        flush_line
      end

      def rmk(content)
        if (match = SECTION.match(content))
          @header_open = false
          start_section(match[1], match[2])
        elsif @header_open
          @header << content
        elsif content != "." && !content.empty?
          note(content)
        end
      end

      def folio(value)
        @header_open = false
        @folio = value
      end

      def open_container(tag)
        @header_open = false
        @stack << tag
        if COLUMN_TAG.match?(tag)
          @pending_columns << tag
        elsif tag != "HD"
          @unrecognized[tag] += 1
        end
      end

      # The first-sync census over the real 663 files: transcribers mix
      # sibling-style column closes (`}` before each new {CBn.) and
      # batched folio-end closes (`}}`), sometimes within ONE file, so
      # brace counts genuinely do not balance in ~2% of the corpus. A
      # stray close is therefore a CENSUSED defect (loud in metadata),
      # never a quarantine — the text must never pay for a brace.
      def close_container(lineno)
        if @stack.empty?
          @brace_defects << "line #{lineno}: unmatched close brace ignored"
          return
        end

        @stack.pop
      end

      def text(part)
        @header_open = false
        @line_buffer << part
        @line_heading = true if @stack.last == "HD"
      end

      def note(content)
        (@current ? @current[:notes] : @pending_notes) << content
      end

      def flush_line
        line = @line_buffer.join.strip
        heading = @line_heading
        @line_buffer = []
        @line_heading = false
        add_line(line, heading: heading) unless line.empty?
      end

      def add_line(line, heading:)
        @current ||= open_passage("head", { "kind" => "head" })
        @current[:lines] << line
        @current[:folios] << @folio if @folio && @current[:folios].last != @folio
        @current[:columns].concat(@pending_columns)
        @pending_columns = []
        @current[:notes].concat(@pending_notes)
        @pending_notes = []
        @current[:headings] << line if heading
      end

      def start_section(hsms_id, raw_title)
        close_passage
        annotations = { "hsms" => hsms_id }
        title = raw_title.strip.sub(/\.\z/, "")
        annotations["title"] = title unless title.empty?
        @current = open_passage(Integer(hsms_id.split("-").last, 10).to_s, annotations)
      end

      def open_passage(citation, annotations)
        { citation: citation, annotations: annotations,
          lines: [], folios: [], columns: [], notes: [], headings: [] }
      end

      def close_passage
        passage = @current
        @current = nil
        return unless passage

        if passage[:lines].empty?
          @empty_sections << passage[:annotations]["hsms"] if passage[:annotations]["hsms"]
          return
        end
        @passages << build_passage(passage)
      end

      def build_passage(passage)
        text = Normalize.nfc(passage[:lines].join("\n"))
        annotations = passage[:annotations]
        %w[folios columns headings notes].each do |key|
          annotations[key] = passage[key.to_sym] unless passage[key.to_sym].empty?
        end
        Nabu::Passage.new(
          urn: "#{@urn}:#{disambiguated(passage[:citation])}", language: @language, text: text,
          text_normalized: Normalize.search_form(self.class.search_source(text), language: @language),
          annotations: annotations, sequence: @passages.size
        )
      end

      def disambiguated(citation)
        @citations[citation] += 1
        count = @citations[citation]
        count == 1 ? citation : "#{citation}:b#{count}"
      end

      def build_document(fallback_title, extra_metadata)
        metadata = header_metadata
        metadata["sections"] = @passages.count { |passage| passage.annotations.key?("hsms") }
        metadata["unrecognized_tags"] = @unrecognized.sort.to_h unless @unrecognized.empty?
        metadata["brace_defects"] = @brace_defects unless @brace_defects.empty?
        metadata["empty_sections"] = @empty_sections unless @empty_sections.empty?
        metadata.merge!(extra_metadata)
        document = Nabu::Document.new(
          urn: @urn, language: @language, title: metadata["title"] || fallback_title,
          canonical_path: File.expand_path(@path), metadata: metadata
        )
        @passages.each { |passage| document << passage }
        raise ParseError, "#{@path}: no passages parsed" if document.empty?

        document
      end

      # Header extraction is by SHAPE, never by position alone (663 files
      # censused from two): the HSMS-NNNN entry, the "[SIG] Title." entry
      # (the entry before it is the author slot), the pipe-separated
      # repository, the trailing transcriber. The full slot list rides
      # "header" verbatim — empty "." slots included, positions are
      # upstream facts — so nothing extraction misses is lost.
      def header_metadata
        meta = {}
        meta["header"] = @header.dup unless @header.empty?
        id_entry = @header.find { |entry| HSMS_ID.match?(entry) }
        meta["hsms_id"] = id_entry.sub(/\.\z/, "") if id_entry
        extract_siglum_title_author(meta)
        repository = @header.find { |entry| entry.include?(" | ") }
        meta["repository"] = repository.sub(/\.\z/, "") if repository
        extract_editor(meta, repository)
        meta
      end

      def extract_siglum_title_author(meta)
        index = @header.index { |entry| entry.start_with?("[") }
        return unless index

        match = /\A\[([^\]]+)\]\s*(.*)\z/m.match(@header[index])
        meta["siglum"] = match[1]
        title = match[2].strip.sub(/\.\z/, "")
        meta["title"] = title unless title.empty?
        return unless index >= 1 && !HSMS_ID.match?(@header[index - 1])

        author = @header[index - 1].sub(/\.\z/, "").strip
        meta["author"] = author unless author.empty?
      end

      def extract_editor(meta, repository)
        entry = @header.last
        return unless entry && entry != "." && entry != repository &&
                      !HSMS_ID.match?(entry) && !entry.start_with?("[")

        meta["editor"] = entry.sub(/\.\z/, "")
      end
    end
  end
end
