# frozen_string_literal: true

module Nabu
  module Adapters
    # The mandoku parser family (P33-0): Kanripo's org-mode text format, as
    # emitted by Christian Wittern's mandoku Emacs tooling. One TEXT is one
    # directory of per-juan files `<KR-id>_<NNN>.txt` (plus a Readme.org TOC,
    # never content); the family parses the whole directory into one
    # Nabu::Document.
    #
    # == Format census (seven real repos probed 2026-07-20; never invented)
    #
    # - Header block: `# -*- mode: mandoku-view -*-` (`;` variant exists),
    #   `#+TITLE:`, `#+DATE:`, `#+PROPERTY: <KEY> <value>` with keys ID,
    #   BASEEDITION, JUAN, CAT, WITNESS, FILE observed. ID and BASEEDITION
    #   REPEAT with diverging values in real files (KR1h0004 carries three
    #   BASEEDITION lines and a second ID `H15-21-0081`) — FIRST WINS; values
    #   ship trailing whitespace (`BASEEDITION WYG    `) — stripped.
    # - Page anchors `<pb:<KR-id>_<edition>_<NNN>-<leaf><side>>` (e.g.
    #   `<pb:KR1h0004_CHANT_001-1a>`): NNN = juan number (matches the file
    #   suffix in every probed file), leaf = 1+ digits, side = a/b. NO line
    #   component exists in any probed anchor, so the citation grain STOPS at
    #   leaf-side: passage = page, urn = <text-urn>:<NNN>:<leaf><side> with
    #   the anchor's own digits verbatim (no reinterpretation). Anchors occur
    #   MID-LINE ("不亦君子乎？」<pb:…_001-2a>¶"): the text before the anchor
    #   closes the old page, the rest opens the new one.
    # - `¶` terminates each print line of the source edition; page text is
    #   those print lines joined with "\n" (¶ marks stripped — they are
    #   mandoku's line-terminator markup, the newline preserves the break).
    #   Blank source lines are org-file layout, not edition text — dropped.
    # - `**` org headings are mandoku navigation (they carry no ¶): recorded
    #   as annotations {"level", "text"}, never page text.
    # - `# src: …` comments (CHANT alignment refs, e.g. "LY 01.02:01; tr.
    #   CH") ride annotations "src_refs" verbatim; other `#` comments (the
    #   mode line) are ignored. A comment/heading before the first anchor of
    #   a file attaches to the file's first page.
    # - Gaiji refs `&KR0809;` (KR-Gaiji ids) stay VERBATIM in the text and
    #   are listed in annotations "gaiji" — never resolved (KR-Gaiji is
    #   journaled, not ingested).
    # - Header-only files are real (KR1a0170_000.txt is five header lines):
    #   they contribute no passages, silently. But TEXT lines outside any
    #   page (before the first anchor, or in a file with no anchors) would
    #   be silently lost or mis-cited — both raise Nabu::ParseError (loud
    #   quarantine; every probed file is anchor-first).
    class MandokuParser
      TEXT_FILE = /\A(?<id>KR\d[a-z]\d{4})_(?<nnn>\d+)\.txt\z/
      HEADER_LINE = /\A#(?:\+|\s|-|\z)/
      PROPERTY = /\A#\+PROPERTY:\s+(?<key>\S+)\s+(?<value>.*)\z/
      TITLE = /\A#\+TITLE:\s+(?<value>.*)\z/
      ANCHOR = /<pb:(?<anchor>(?<text>KR\d[a-z]\d{4})_(?<edition>[^_>]+)_(?<juan>\d+)-(?<page>\d+[ab]))>/
      SRC_COMMENT = /\A#\s+src:\s+(?<ref>.*)\z/
      HEADING = /\A(?<stars>\*+)\s+(?<text>.*)\z/
      GAIJI = /&[A-Za-z][A-Za-z0-9-]*;/
      PILCROW = "¶"

      LANGUAGE = "lzh"

      # Parse the text directory at +dir+ into one Document. +urn+ is the
      # document urn the adapter minted; +text_id+ the KR id (names the
      # per-juan files).
      def parse(dir, urn:, text_id:)
        files = juan_files(dir, text_id)
        raise ParseError, "#{dir}: no #{text_id}_*.txt juan files" if files.empty?

        headers = read_headers(files)
        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, canonical_path: File.expand_path(dir),
          title: headers["title"], metadata: document_metadata(text_id, headers)
        )
        append_pages!(document, files, urn: urn)
        document
      end

      private

      def juan_files(dir, text_id)
        Dir.children(dir)
           .select { |name| (match = TEXT_FILE.match(name)) && match[:id] == text_id }
           .sort
           .map { |name| File.join(dir, name) }
      rescue Errno::ENOENT
        []
      end

      # First-wins TITLE and PROPERTY values across the files in order — the
      # census rule for upstream's repeated header lines.
      def read_headers(files)
        headers = {}
        files.each do |file|
          each_line(file) do |line|
            break unless HEADER_LINE.match?(line)

            if (match = TITLE.match(line))
              headers["title"] ||= match[:value].strip
            elsif (match = PROPERTY.match(line))
              headers[match[:key].downcase] ||= match[:value].strip
            end
          end
        end
        headers
      end

      def document_metadata(text_id, headers)
        metadata = { "class" => text_id[0, 3] }
        metadata["edition"] = headers["baseedition"] if headers["baseedition"]
        metadata["cat"] = headers["cat"] if headers["cat"]
        metadata
      end

      # -- page assembly ---------------------------------------------------

      def append_pages!(document, files, urn:)
        state = { document: document, urn: urn, sequence: 0, seen: {}, page: nil }
        files.each do |file|
          state[:pending] = { "src_refs" => [], "headings" => [] }
          each_line(file) { |line| consume_line(state, file, line) }
          flush_page!(state) # pages never span files (juan = file grain)
        end
      end

      def consume_line(state, file, line)
        return if line.empty?
        return consume_comment(state, line) if line.start_with?("#")
        return consume_heading(state, line) if HEADING.match?(line)

        consume_text_line(state, file, line)
      end

      def consume_comment(state, line)
        match = SRC_COMMENT.match(line)
        return unless match

        bucket = state[:page] ? state[:page][:annotations] : state[:pending]
        bucket["src_refs"] << match[:ref].strip
      end

      def consume_heading(state, line)
        match = HEADING.match(line)
        bucket = state[:page] ? state[:page][:annotations] : state[:pending]
        bucket["headings"] << { "level" => match[:stars].length, "text" => match[:text].strip }
      end

      # Split the physical line on page anchors: each fragment belongs to the
      # page open at that point; an anchor closes the current page and opens
      # the next.
      def consume_text_line(state, file, line)
        rest = line
        while (match = ANCHOR.match(rest))
          append_text(state, file, match.pre_match)
          open_page!(state, file, match)
          rest = match.post_match
        end
        append_text(state, file, rest)
      end

      def append_text(state, file, fragment)
        text = fragment.delete(PILCROW).strip
        return if text.empty?

        raise ParseError, "#{file}: text before the first page anchor (#{text[0, 20].inspect})" unless state[:page]

        state[:page][:lines] << fragment.delete(PILCROW).rstrip
      end

      def open_page!(state, file, match)
        flush_page!(state)
        key = "#{match[:juan]}:#{match[:page]}"
        raise ParseError, "#{file}: duplicate page anchor <pb:#{match[:anchor]}>" if state[:seen].key?(key)

        state[:seen][key] = true
        annotations = state[:pending]
        state[:pending] = { "src_refs" => [], "headings" => [] }
        state[:page] = { key: key, anchor: match[:anchor], lines: [], annotations: annotations }
      end

      # Emit the open page as a passage; empty pages (no print lines) are
      # dropped without minting a citation.
      def flush_page!(state)
        page = state[:page]
        state[:page] = nil
        return if page.nil? || page[:lines].empty?

        text = Nabu::Normalize.nfc(page[:lines].join("\n"))
        state[:document] << Nabu::Passage.new(
          urn: "#{state[:urn]}:#{page[:key]}", language: LANGUAGE, text: text,
          sequence: (state[:sequence] += 1),
          annotations: passage_annotations(page, text)
        )
      end

      def passage_annotations(page, text)
        annotations = { "anchor" => page[:anchor] }
        gaiji = text.scan(GAIJI)
        annotations["gaiji"] = gaiji unless gaiji.empty?
        %w[headings src_refs].each do |key|
          values = page[:annotations][key]
          annotations[key] = values unless values.empty?
        end
        annotations
      end

      def each_line(file, &)
        File.foreach(file, encoding: Encoding::UTF_8) { |line| yield line.chomp }
      rescue Errno::ENOENT, Errno::EISDIR => e
        raise ParseError, "#{file}: #{e.message}"
      end
    end
  end
end
