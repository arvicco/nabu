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
    #
    # == KR2 census additions (P33-1, seven KR2 + three KR5 repos probed
    #    2026-07-20)
    #
    # - RE-ASSERTED anchors: big KR2 texts repeat the OPEN page's anchor
    #   mid-page (SBCK 大清一統志: 1,507 instances across 178 of 210 files,
    #   every one the currently open page — zero closed-page repeats; WYG
    #   明史 re-asserts after an interleaved volume anchor). A re-assertion
    #   is a no-op — same page continues; an anchor re-opening a CLOSED page
    #   is still the loud duplicate ParseError.
    # - EDITION-VOLUME anchors `<pb:KR2a0038_WYG_WYG0297-0606c>`: the text's
    #   own id + edition, but an ALPHA-prefixed volume ordinal of the PRINT
    #   edition and an a/b/c register (the three text-registers of a 四庫
    #   page; the leaf-side grain has no c). They interleave the leaf-side
    #   pagination mid-page: recorded verbatim on the open page as
    #   annotations "edition_pages", never page text, never a page boundary.
    #
    # == KR5 witness overlays (P37-1, ten witness + four plain KR5 repos
    #    probed 2026-07-20)
    #
    # The DZJY overlay repos (WITNESS CK-KZ 重刊道藏輯要) transcribe the
    # WITNESS edition: file lines are the witness's print columns, and the
    # citable page structure is the witness's own `<pb:>` anchors, whose page
    # component is `<juan>p<leaf><side>` (never the plain `-` form). THREE
    # anchor arrangements censused — `CK-KZ_JY001_01p001a` (witness siglum +
    # DZJY volume), `KR5a0004_CK-KZ_01p001a` (text id + witness), and
    # `CK-KZ_KR5i0030_01p001a` (witness siglum + text id) — so a witness
    # anchor is accepted iff its FIRST component is the text id or the
    # declared WITNESS; anything else is a loud ParseError. Passage urn =
    # <text-urn>:<witness-juan>:<leaf><side>, digits verbatim; the census
    # found (juan, leaf-side) unique per repo in every probe, and the
    # duplicate-anchor error keeps that honest at sync.
    #
    # - Witness pages SPAN file boundaries (pervasive: 10/17 files of
    #   KR5b0147 open mid-page) — in the witness scheme the open page CARRIES
    #   across files instead of flushing at the juan-file grain. Sorted file
    #   order need not follow witness page order (KR5c0067's _000 front
    #   matter sits at witness juan 03, _001–_010 walk juan 02) — keys are
    #   global, so the carry stays correct.
    # - `<md:<KR-id>_<edition>_<NNN>-<leaf><side>>` milestones mark where the
    #   BASE edition's pages fall inside the witness text: annotations
    #   "base_pages" on the open page (pending → first page before the first
    #   anchor), never page text, never a boundary. The md edition component
    #   is recorded VERBATIM and never validated against BASEEDITION —
    #   KR5c0091 declares HFL but milestones say WYG (headers lie).
    # - `@fw` lines (line-initial only) are the witness page's running
    #   headers (forme work): annotations "fw", with embedded ¶ and `<md:>`
    #   milestones extracted ("@fw重<md:…_001-001a>¶刋道藏輯要" reads
    #   重刋道藏輯要). Any other at-code is a loud ParseError.
    # - ¶ marks the BASE edition's line ends (they fall mid-line); overlay
    #   headings DO carry ¶ and embedded milestones — both extracted from
    #   the heading text (plain-scheme headings carry neither, unchanged).
    # - ONE page scheme per document: the first page anchor locks it, and a
    #   leaf-side anchor in a witness document (or vice versa, or an `<md:>`/
    #   `@fw` in a leaf-side document) raises — every censused repo is
    #   scheme-pure. Documents in the witness scheme carry metadata
    #   "page_scheme" => "witness" plus the declared "witness" siglum.
    # - Anything `<…>`-shaped that survives anchor/milestone extraction is a
    #   loud ParseError (unrecognized construct) — never silent text
    #   pollution (census: zero stray angle brackets in any probed repo).
    class MandokuParser
      TEXT_FILE = /\A(?<id>KR\d[a-z]\d{4})_(?<nnn>\d+)\.txt\z/
      HEADER_LINE = /\A#(?:\+|\s|-|\z)/
      PROPERTY = /\A#\+PROPERTY:\s+(?<key>\S+)\s+(?<value>.*)\z/
      # KR5i repos ship `#+TITLE:唱道真言 Changdao Zhenyan` — no space after
      # the colon (P37-1 census): the separator is optional, value verbatim.
      TITLE = /\A#\+TITLE:\s*(?<value>.*)\z/
      # Any page-break tag; the inner form decides plain page vs edition-
      # volume annotation vs witness page — or raises (never silent).
      PAGE_BREAK = /<pb:(?<anchor>[^>]*)>/
      ANCHOR = /\A(?<text>KR\d[a-z]\d{4})_(?<edition>[^_]+)_(?<juan>\d+)-(?<page>\d+[ab])\z/
      # The print edition's own volume pagination interleaved mid-page (the
      # KR2 census): same text id, alpha-prefixed volume ordinal, a–c
      # register. Never a page boundary — an annotation on the open page.
      EDITION_PAGE = /\A(?<text>KR\d[a-z]\d{4})_(?<edition>[^_]+)_(?<volume>[A-Z]+\d+)-(?<page>\d+[a-c])\z/
      # The witness page form (the KR5 overlay census): juan `p` leaf-side.
      WITNESS_PAGE = /\A(?<head>[^_]+)_(?<container>[^_]+)_(?<juan>\d+)p(?<page>\d+[ab])\z/
      # Base-edition page milestones overlaid on the witness text.
      MILESTONE = /<md:(?<anchor>[^>]*)>/
      SRC_COMMENT = /\A#\s+src:\s+(?<ref>.*)\z/
      HEADING = /\A(?<stars>\*+)\s+(?<text>.*)\z/
      GAIJI = /&[A-Za-z][A-Za-z0-9-]*;/
      PILCROW = "¶"
      FW = /\A@fw/

      LANGUAGE = "lzh"

      # Parse the text directory at +dir+ into one Document. +urn+ is the
      # document urn the adapter minted; +text_id+ the KR id (names the
      # per-juan files).
      def parse(dir, urn:, text_id:)
        files = juan_files(dir, text_id)
        raise ParseError, "#{dir}: no #{text_id}_*.txt juan files" if files.empty?

        headers = read_headers(files)
        state = collect_pages(files, urn: urn, text_id: text_id, witness: headers["witness"])
        document = Nabu::Document.new(
          urn: urn, language: LANGUAGE, canonical_path: File.expand_path(dir),
          title: headers["title"], metadata: document_metadata(text_id, headers, state[:scheme])
        )
        state[:passages].each { |passage| document << passage }
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

      def document_metadata(text_id, headers, scheme)
        metadata = { "class" => text_id[0, 3] }
        metadata["edition"] = headers["baseedition"] if headers["baseedition"]
        metadata["cat"] = headers["cat"] if headers["cat"]
        metadata["dzid"] = headers["dzid"] if headers["dzid"]
        metadata["witness"] = headers["witness"] if headers["witness"]
        metadata["page_scheme"] = "witness" if scheme == :witness
        metadata
      end

      # -- page assembly ---------------------------------------------------

      def collect_pages(files, urn:, text_id:, witness:)
        state = { passages: [], urn: urn, text_id: text_id, witness: witness,
                  scheme: nil, sequence: 0, seen: {}, page: nil, pending: empty_annotations }
        files.each do |file|
          # Plain scheme: pages never span files (juan = file grain) and
          # dangling pendings drop. The witness scheme CARRIES both (the
          # census: witness pages routinely cross the file seams).
          state[:pending] = empty_annotations unless state[:scheme] == :witness
          each_line(file) { |line| consume_line(state, file, line) }
          flush_page!(state) unless state[:scheme] == :witness
        end
        flush_page!(state)
        state
      end

      def consume_line(state, file, line)
        return if line.empty?
        return consume_comment(state, line) if line.start_with?("#")
        return consume_at_code(state, file, line) if line.start_with?("@")
        return consume_heading(state, file, line) if HEADING.match?(line)

        consume_text_line(state, file, line)
      end

      def consume_comment(state, line)
        match = SRC_COMMENT.match(line)
        return unless match

        annotation_bucket(state)["src_refs"] << match[:ref].strip
      end

      # `@fw` = the witness page's running header (forme work; the only
      # censused at-code): milestones and ¶ extracted, the head recorded as
      # it reads. Any other at-code is new — loud.
      def consume_at_code(state, file, line)
        raise ParseError, "#{file}: unrecognized at-code (#{line[0, 20].inspect})" unless FW.match?(line)

        text = clean_fragment(state, file, line.sub(FW, "")).delete(PILCROW).strip
        annotation_bucket(state)["fw"] << text unless text.empty?
      end

      def consume_heading(state, file, line)
        match = HEADING.match(line)
        # Overlay headings carry ¶ and embedded milestones (plain-scheme
        # headings carry neither — a no-op there).
        text = clean_fragment(state, file, match[:text]).delete(PILCROW).strip
        annotation_bucket(state)["headings"] << { "level" => match[:stars].length, "text" => text }
      end

      # Split the physical line on page-break tags: each fragment belongs to
      # the page open at that point; a page anchor closes the current page
      # and opens the next (an edition-volume anchor only annotates).
      def consume_text_line(state, file, line)
        rest = line
        while (match = PAGE_BREAK.match(rest))
          append_text(state, file, match.pre_match)
          consume_page_break(state, file, match[:anchor])
          rest = match.post_match
        end
        append_text(state, file, rest)
      end

      def consume_page_break(state, file, anchor)
        if (match = ANCHOR.match(anchor))
          open_page!(state, file, anchor, match, :leafside)
        elsif EDITION_PAGE.match?(anchor)
          annotation_bucket(state)["edition_pages"] << anchor
        elsif (match = WITNESS_PAGE.match(anchor))
          witness_page!(state, file, anchor, match)
        else
          raise ParseError, "#{file}: unrecognized page anchor <pb:#{anchor}>"
        end
      end

      # A witness anchor's first component is the text id or the declared
      # WITNESS in every censused arrangement — anything else is new.
      def witness_page!(state, file, anchor, match)
        lock_scheme!(state, file, :witness, anchor)
        unless match[:head] == state[:text_id] || match[:head] == state[:witness]
          raise ParseError, "#{file}: unrecognized witness page anchor <pb:#{anchor}>"
        end

        open_page!(state, file, anchor, match, :witness)
      end

      def lock_scheme!(state, file, scheme, anchor)
        state[:scheme] ||= scheme
        return if state[:scheme] == scheme

        raise ParseError, "#{file}: mixed page anchor schemes at <pb:#{anchor}>"
      end

      def open_page!(state, file, anchor, match, scheme)
        lock_scheme!(state, file, scheme, anchor)
        key = "#{match[:juan]}:#{match[:page]}"
        # Re-asserting the OPEN page's anchor is upstream's way of resuming
        # the pagination after an interleave (census: 1,507 instances in
        # 大清一統志 alone, every one the open page) — no-op.
        return if state[:page] && state[:page][:key] == key

        flush_page!(state)
        raise ParseError, "#{file}: duplicate page anchor <pb:#{anchor}>" if state[:seen].key?(key)

        state[:seen][key] = true
        annotations = state[:pending]
        state[:pending] = empty_annotations
        state[:page] = { key: key, anchor: anchor, lines: [], annotations: annotations }
      end

      def append_text(state, file, fragment)
        fragment = clean_fragment(state, file, fragment)
        text = fragment.delete(PILCROW).strip
        return if text.empty?

        raise ParseError, "#{file}: text before the first page anchor (#{text[0, 20].inspect})" unless state[:page]

        state[:page][:lines] << fragment.delete(PILCROW).rstrip
      end

      # Extract `<md:>` base-page milestones (verbatim, onto the open page —
      # pending before the first) and refuse anything `<…>`-shaped that
      # survives: an unrecognized construct silently riding as text would be
      # a mis-citation.
      def clean_fragment(state, file, fragment)
        cleaned = fragment.gsub(MILESTONE) do
          milestone = Regexp.last_match[:anchor]
          if state[:scheme] == :leafside
            raise ParseError, "#{file}: base-page milestone <md:#{milestone}> in a leaf-side document"
          end

          annotation_bucket(state)["base_pages"] << milestone
          ""
        end
        raise ParseError, "#{file}: unrecognized construct (#{cleaned.strip[0, 30].inspect})" if cleaned.match?(/[<>]/)

        cleaned
      end

      def annotation_bucket(state)
        state[:page] ? state[:page][:annotations] : state[:pending]
      end

      def empty_annotations
        { "src_refs" => [], "headings" => [], "edition_pages" => [], "base_pages" => [], "fw" => [] }
      end

      # Emit the open page as a passage; empty pages (no print lines) are
      # dropped without minting a citation.
      def flush_page!(state)
        page = state[:page]
        state[:page] = nil
        return if page.nil? || page[:lines].empty?

        text = Nabu::Normalize.nfc(page[:lines].join("\n"))
        state[:passages] << Nabu::Passage.new(
          urn: "#{state[:urn]}:#{page[:key]}", language: LANGUAGE, text: text,
          sequence: (state[:sequence] += 1),
          annotations: passage_annotations(page, text)
        )
      end

      def passage_annotations(page, text)
        annotations = { "anchor" => page[:anchor] }
        gaiji = text.scan(GAIJI)
        annotations["gaiji"] = gaiji unless gaiji.empty?
        %w[headings src_refs edition_pages base_pages fw].each do |key|
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
