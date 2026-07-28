# frozen_string_literal: true

require "json"

require_relative "../languages"

module Nabu
  module Query
    # The cross-source arm of `show --parallel` (P48-r2): pairing over a
    # links-journal `kind=translation` edge at Degé FOLIO/PAGE grain.
    #
    # == Why this exists (the superseded grain verdict)
    #
    # The P48-6 crosswalk pinned "the two citation systems share no
    # vocabulary" and stopped the Kangyur↔84000 connection at document-grain
    # edges. The owner's first live pairing attempt refuted the pinned
    # wording: 84000 TEI embeds INLINE Degé folio anchors
    # (`<ref cRef="F.3.b" type="folio"/>`, ~33k across the 396 published
    # Kangyur files, plus `V<n>` volume refs on multi-volume texts carrying
    # the actual eKangyur volume numbers) — exactly the page vocabulary the
    # Esukhia shelves cite (`…derge-kangyur:toh846a:3b.1`;
    # `…toh1-6:2.1b.3` volume-prefixed). The E84000TeiParser captures them
    # per chunk ("folios" / "folios_by_toh" annotations); this class joins
    # the two sides on those tokens. Edges stay document grain — the page
    # pairing is read-time derivation, nothing new is minted.
    #
    # == The pairing (page-run blocks, both directions)
    #
    # Passages pair per Degé PAGE through the existing Parallel span-group
    # shapes: the woodblock lines of a page (or page RUN, when an English
    # chunk straddles a folio/volume boundary) render first, then the
    # covering English chunks once, joined, with an honest coverage label
    # (:block). A page no chunk covers renders one-sided; a chunk whose
    # folios the queried document lacks renders one-sided after the runs;
    # chunks with no folio annotation at all (front matter — summary,
    # introduction) translate nothing of the woodblock and are omitted from
    # the Kangyur-side view, while from the English side they are the
    # queried text and stay honest one-sided rows. Direction works both
    # ways; the edge's from side (the 84000 publication) is always the
    # translation side.
    #
    # == Edge resolution
    #
    # The queried document's urn is probed in both edge directions; a Derge
    # SUBTEXT (toh1-6) additionally reaches the edge minted on its toh1
    # container parent (the toh_base join lands there), picking the
    # publication whose slug matches its own. In the other direction an
    # edge pointing at a passage-less container refines to the
    # passage-bearing subtext named by the publication's own "toh" keys.
    # A multi-Toh publication pairs its primary witness (own slug) and
    # selects that witness's keyed folio stream.
    #
    # == Language semantics
    #
    # The edge has exactly ONE counterpart per direction, so `--parallel
    # LANG` is honored iff LANG names that counterpart's language
    # (ISO 639 B/T/two-letter variants folded, and the historical Tibetan
    # stages xct/otb folded to bod so `--parallel bo` reaches the xct
    # shelf); otherwise Parallel::TranslationMismatch names the language
    # that would work — an honest error, never a silent miss.
    class FolioParallel
      KIND = "translation"

      # Historical-stage fold for --parallel matching ONLY (stored codes
      # never change): Classical/Old Tibetan answer to the modern bo/bod.
      STAGE_FOLD = { "xct" => "bod", "otb" => "bod" }.freeze

      # The resolved counterpart document row plus the built groups.
      Pairing = Data.define(:counterpart, :groups)

      def initialize(catalog:, journal:)
        @catalog = catalog
        @journal = journal
      end

      # Pair +document+ (a Parallel#locate row) against its translation-edge
      # counterpart. Returns a Pairing, or nil when no edge/counterpart
      # exists (the caller keeps the honest right-nil Result). Raises
      # Parallel::TranslationMismatch when the edge exists but +lang+ does
      # not name the counterpart's language.
      def pair(document, lang:)
        return nil if @journal.nil?

        edge, direction = edge_for(document)
        return nil if edge.nil?

        counterpart = resolve_counterpart(document, edge, direction)
        return nil if counterpart.nil?

        ensure_language!(counterpart, lang)
        groups = if direction == :translation_left
                   translation_left_groups(document, counterpart)
                 else
                   original_left_groups(document, counterpart)
                 end
        Pairing.new(counterpart: counterpart, groups: groups)
      end

      private

      # -- edge resolution ---------------------------------------------------

      # [edge row, :translation_left | :original_left], or nil. Determinism:
      # the edge whose far side matches the document's own slug wins, then
      # urn order.
      def edge_for(document)
        urn = document.fetch(:urn)
        rows = edges(from_urn: urn)
        return [pick_edge(rows, urn, :to_urn), :translation_left] unless rows.empty?

        rows = edges(to_urn: urn)
        rows = parent_edges(document) if rows.empty?
        return nil if rows.empty?

        [pick_edge(rows, urn, :from_urn), :original_left]
      end

      def edges(criteria)
        @journal[:links].where(kind: KIND).where(criteria).all
      end

      # The container hop: a derge subtext's edge lives on its parent (the
      # toh_base join) — reach it through the document's own "parent"
      # metadata, never by guessing slugs.
      def parent_edges(document)
        parent = parent_urn(document)
        parent ? edges(to_urn: parent) : []
      end

      def pick_edge(rows, urn, far_side)
        own = slug_of(urn)
        rows.min_by { |row| [slug_of(row.fetch(far_side)) == own ? 0 : 1, row.fetch(far_side)] }
      end

      def parent_urn(document)
        parent = document_metadata(document.fetch(:id))["parent"]
        return nil unless parent.is_a?(String) && !parent.empty?

        urn = document.fetch(:urn)
        "#{urn[0..urn.rindex(':')]}#{parent}"
      end

      # The counterpart document row. When the queried side is the
      # translation and the edge lands on a passage-less container, refine
      # to the subtext the publication's own "toh" keys name (class note).
      def resolve_counterpart(document, edge, direction)
        other = direction == :translation_left ? edge.fetch(:to_urn) : edge.fetch(:from_urn)
        row = document_row(other)
        return row unless direction == :translation_left
        return row if row && passages?(row)

        prefix = other[0..other.rindex(":")]
        document_metadata(document.fetch(:id)).fetch("toh", []).each do |key|
          candidate = document_row("#{prefix}#{key}")
          return candidate if candidate && passages?(candidate)
        end
        row
      end

      def passages?(row)
        !passages_of(row).empty?
      end

      def document_row(urn)
        @catalog[:documents].where(urn: urn).select(:id, :urn, :title, :language).first
      end

      def document_metadata(document_id)
        json = @catalog[:documents].where(id: document_id).get(:metadata_json)
        parsed = json && JSON.parse(json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      # -- language ----------------------------------------------------------

      def ensure_language!(counterpart, lang)
        stored = counterpart.fetch(:language).to_s
        return if expand(lang).intersect?(expand(stored))

        raise Parallel::TranslationMismatch,
              "the translation link pairs #{counterpart.fetch(:urn)} [#{stored}] — " \
              "--parallel #{lang} does not match; try --parallel #{stored}"
      end

      def expand(code)
        variants = Nabu::Languages.code_variants(code)
        variants | variants.filter_map { |c| STAGE_FOLD[c] }
      end

      # -- the page-run pairing ----------------------------------------------

      # Kangyur side queried: pages of the woodblock lines drive; each run
      # of pages an English chunk-set covers renders as one :block.
      def original_left_groups(left_doc, right_doc)
        pages, page_lines, page_index = page_map(passage_lines(left_doc))
        chunks = folio_chunks(right_doc, stream_slugs(left_doc.fetch(:urn))).reject { |c| c[:folios].nil? }
        assigned, orphans = assign_chunks(chunks, page_index)

        groups = []
        i = 0
        while i < pages.size
          page = pages[i]
          if assigned[page].nil?
            page_lines[page].each { |line| groups << one_sided_original(line) }
            i += 1
            next
          end
          members, last = collect_run(assigned, pages, page_index, i)
          originals = pages[i..last].flat_map { |p| page_lines[p] }
          groups << block(originals, joined_line(members.map { |m| m[:line] }), chunk_span_label(members))
          i = last + 1
        end
        orphans.each { |chunk| groups << one_sided_translation(chunk[:line]) }
        groups
      end

      # Each chunk starts on its first folio present in the left document;
      # chunks whose folios the queried document lacks entirely fall out as
      # one-sided rows after the runs.
      def assign_chunks(chunks, page_index)
        assigned = {}
        orphans = []
        chunks.each do |chunk|
          start = chunk[:folios].find { |token| page_index.key?(token) }
          start ? (assigned[start] ||= []) << chunk : orphans << chunk
        end
        [assigned, orphans]
      end

      # Grow the run from page i across every folio its chunks straddle
      # (the volume-boundary chunk pulls both volumes' pages into one
      # block). Returns [members in reading order, last page index].
      def collect_run(assigned, pages, page_index, first)
        last = first
        queue = assigned[pages[first]].dup
        members = []
        until queue.empty?
          chunk = queue.shift
          members << chunk
          top = chunk[:folios].filter_map { |token| page_index[token] }.max || last
          next unless top > last

          ((last + 1)..top).each { |j| queue.concat(assigned[pages[j]] || []) }
          last = top
        end
        [members.sort_by { |m| m[:seq] }, last]
      end

      # English side queried: the chunks drive; consecutive chunks sharing
      # a page run merge, their pages' woodblock lines render once, joined.
      # Folio-less chunks (front matter) stay honest one-sided left rows.
      def translation_left_groups(left_doc, right_doc)
        pages, page_lines, page_index = page_map(passage_lines(right_doc))
        chunks = folio_chunks(left_doc, stream_slugs(right_doc.fetch(:urn)))

        groups = []
        covered = {}
        index = 0
        while index < chunks.size
          chunk = chunks[index]
          tokens = chunk[:folios]&.select { |token| page_index.key?(token) } || []
          if tokens.empty?
            groups << one_sided_original(chunk[:line])
            index += 1
            next
          end
          members, run_tokens, index = collect_chunk_run(chunks, index, page_index)
          run_tokens.each { |token| covered[token] = true }
          lines = run_tokens.flat_map { |token| page_lines[token] }
          groups << block(members.map { |m| m[:line] }, joined_line(lines), page_span_label(run_tokens))
        end
        pages.reject { |token| covered[token] }.each do |token|
          page_lines[token].each { |line| groups << one_sided_translation(line) }
        end
        groups
      end

      # Absorb following chunks while they start on a page the run already
      # holds; each absorbed chunk may extend the run (the straddle).
      # Returns [members, run page tokens in page order, next index].
      def collect_chunk_run(chunks, index, page_index)
        run = {}
        members = []
        loop do
          chunk = chunks[index]
          members << chunk
          chunk[:folios].each { |token| run[token] = true if page_index.key?(token) }
          nxt = chunks[index + 1]
          start = nxt && nxt[:folios]&.find { |token| page_index.key?(token) }
          break unless start && run[start]

          index += 1
        end
        [members, run.keys.sort_by { |token| page_index[token] }, index + 1]
      end

      # -- row shaping ---------------------------------------------------------

      # [Line] in sequence order (the Parallel shape; anchor unused here).
      def passage_lines(document)
        urn = document.fetch(:urn)
        passages_of(document).map { |row| line(row, urn) }
      end

      # All passages with their folio span for the selected witness stream:
      # the keyed stream matching a slug when one exists, else the unkeyed
      # main stream. nil folios = a chunk before any anchor (front matter).
      def folio_chunks(document, slugs)
        urn = document.fetch(:urn)
        passages_of(document).each_with_index.map do |row, seq|
          annotations = parse_annotations(row[:annotations_json])
          keyed = annotations["folios_by_toh"]
          folios = slugs.filter_map { |slug| keyed && keyed[slug] }.first || annotations["folios"]
          { line: line(row, urn), folios: folios, seq: seq }
        end
      end

      def passages_of(document)
        @catalog[:passages]
          .where(document_id: document.fetch(:id))
          .order(:sequence)
          .select(:urn, :text, :withdrawn, :annotations_json)
      end

      def line(row, document_urn)
        Parallel::Line.new(
          suffix: row.fetch(:urn).delete_prefix(document_urn), urn: row.fetch(:urn),
          text: row.fetch(:text), withdrawn: [true, 1].include?(row.fetch(:withdrawn)), anchor: nil
        )
      end

      def parse_annotations(json)
        return {} if json.nil? || json.empty?

        parsed = JSON.parse(json)
        parsed.is_a?(Hash) ? parsed : {}
      rescue JSON::ParserError
        {}
      end

      # -- pages and labels ----------------------------------------------------

      # [ordered page tokens, token → lines, token → position].
      def page_map(lines)
        pages = []
        page_lines = {}
        lines.each do |line|
          token = page_of(line.suffix)
          (page_lines[token] ||= (pages << token; [])) << line # rubocop:disable Style/Semicolon
        end
        [pages, page_lines, pages.each_with_index.to_h]
      end

      # A derge suffix's page component in the folio-token vocabulary:
      # ":3b.4" → "3b"; ":1.277b.6" (multi-volume) → "1.277b"; a ":bN"
      # collision counter never reaches the page.
      def page_of(suffix)
        citation = suffix.delete_prefix(":").split(":").first.to_s
        segments = citation.split(".")
        if segments[0]&.match?(/\A\d+\z/) && segments[1]&.match?(/\A\d+x?[ab]\z/)
          "#{segments[0]}.#{segments[1]}"
        else
          segments[0].to_s
        end
      end

      # The folio streams a derge document answers to: its own slug and,
      # for a subtext, the base Toh number (the parser's toh_base rule —
      # part suffixes strip, letter suffixes stay).
      def stream_slugs(urn)
        slug = slug_of(urn)
        [slug, slug.sub(/-\d+\z/, "")].uniq
      end

      def slug_of(urn)
        urn.split(":").last.to_s
      end

      def chunk_span_label(members)
        first = members.first[:line].suffix
        last = members.last[:line].suffix
        first == last ? first : "#{first}–#{last}"
      end

      def page_span_label(tokens)
        tokens.size == 1 ? ":#{tokens.first}" : ":#{tokens.first}–:#{tokens.last}"
      end

      # -- group builders (the Parallel shapes) --------------------------------

      def block(originals, translation, anchor)
        Parallel::Group.new(
          kind: :block, anchor: anchor,
          covers_first: originals.first.suffix, covers_last: originals.last.suffix,
          originals: originals, translation: translation,
          clipped: false, shown_first: originals.first.suffix, shown_last: originals.last.suffix
        )
      end

      def joined_line(lines)
        Parallel::Line.new(
          suffix: lines.first.suffix, urn: lines.first.urn,
          text: lines.map(&:text).join(" "), withdrawn: lines.any?(&:withdrawn), anchor: nil
        )
      end

      def one_sided_original(line)
        Parallel::Group.new(
          kind: :original, anchor: nil, covers_first: line.suffix, covers_last: line.suffix,
          originals: [line], translation: nil,
          clipped: false, shown_first: line.suffix, shown_last: line.suffix
        )
      end

      def one_sided_translation(line)
        Parallel::Group.new(
          kind: :translation, anchor: line.suffix, covers_first: nil, covers_last: nil,
          originals: [], translation: line,
          clipped: false, shown_first: nil, shown_last: nil
        )
      end
    end
  end
end
