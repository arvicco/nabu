# frozen_string_literal: true

require_relative "cora_tei_parser"

module Nabu
  module Adapters
    # The ReN dialect of the cora-tei family (P46-5) — the TEI export of the
    # Referenzkorpus Mittelniederdeutsch/Niederrheinisch 1.1 (tei_1.1.zip on
    # fdr.uni-hamburg.de record 9195). Censused from the WHOLE deposit (all
    # 161 anno/ + 74 trans/ files, 2026-07-26) — never invented. Where ReM's
    # dialect and this one differ, the differences are pinned in
    # test/adapters/ren_tei_parser_test.rb:
    #
    # - NO teiHeader: files open at <text><body><ab>. There is no in-file
    #   licence, language ident, or title — identity comes from the filename
    #   sigle, the license from the deposit record (the adapter's concern).
    # - Tokens are <w xml:id pos msd lemma [join]> in anno/ files and bare
    #   <w xml:id [join]> in trans/ files. NO @norm anywhere (ReM's is the
    #   inverse: norm+lemma, no pos/msd) and no <pc> — punctuation is a <w>
    #   with pos "$;<$;" whose msd/lemma carry the "--" null (dropped, the
    #   ReM lemma discipline extended to pos/msd).
    # - <s> sentence containers cross-cut the manuscript lines: recognized,
    #   never a passage boundary, never censused.
    # - No @ed on pb/cb/lb anywhere (297,594 lb censused): ALL lineation is
    #   the manuscript's own, so the parent's ed-nil-is-primary reading
    #   applies file-wide and edition_lines stays empty.
    # - <lb>/<pb> land INSIDE tokens (a<lb/>derleteren, stuyer<pb/><lb/>
    #   schen): the token completes on the line it ends on, parts glued.
    #   The scribal "=" hyphenation mark (vor=<lb/>genompd) is witness text.
    # - Editorial apparatus rides inside tokens — <expan> (222,807),
    #   <del>, <add>, <unclear>, <gap reason="illegible"> — text (where any)
    #   flows into the diplomatic form, presence is flagged on the token
    #   record. A token whose only content is an illegible gap has no
    #   witness text and drops with the parent's loud empty-w census.
    # - <note type="editorial"> between entries carries the ASnA charter
    #   sigle ("HBG1", "Lub 1352a"): captured and attached to the line that
    #   follows (Line#notes). <note place="…"> is ALWAYS inside a token in
    #   the 1.1 deposit (all 35,036 censused; and in-token notes are the
    #   token's whole surface, 639/639 note-only — another hand's text), so
    #   its text flows into the form with the place flagged. The
    #   free-standing case is DEFENSIVE: text swallowed, the occurrence
    #   censused loudly as "note[<place>]" so a future deposit that grows
    #   free marginalia is never silent.
    # - join="both" (708 censused) glues on both sides — the multi-part
    #   Latin dates (t2_m1..m4 join right/both/both/left).
    class RenTeiParser < CoraTeiParser
      # One manuscript line, the ReN shape: the parent's citation fields
      # (page, column, n), +notes+ the editorial (charter-sigle) notes that
      # introduced it, text + tokens as in the parent. edition_lines is
      # kept for shape parity but is always empty (no @ed upstream).
      Line = Data.define(:page, :column, :n, :edition_lines, :notes, :text, :tokens)

      # Token attributes whose "--" reads as null and drops (the parent
      # drops it for lemma only; ReN's pos/msd use the same placeholder).
      NULL_DROPPED_ATTRS = %w[lemma pos msd].freeze

      private

      def open_body_element(node, walk)
        return walk[:in_body] = true if node.name == "body"
        return unless walk[:in_body]
        return swallow_note_element(node, walk) if walk[:note_depth]

        case node.name
        when "ab", "s" then nil # containers; the manuscript line is the grain
        when "pb" then open_page_break(node, walk)
        when "cb" then open_column_break(node, walk)
        when "lb" then open_line_break(node, walk)
        when "w" then open_token(node, walk)
        when "note" then open_note(node, walk)
        when "expan", "del", "add", "unclear", "gap"
          walk[:word][:flags][node.name] = true if walk[:word]
        when "space"
          walk[:word][:form] << (" " * (node.attribute("quantity") || "1").to_i) if walk[:word]
        else walk[:unrecognized][node.name] += 1
        end
      end

      # ReN tokens: pos/msd/lemma (anno) or nothing (trans) — never @norm.
      def open_token(node, walk)
        raise ParseError, "#{walk[:path]}: nested <#{node.name}> token" if walk[:word]
        unless walk[:line]
          raise ParseError, "#{walk[:path]}: <#{node.name}> token outside any manuscript line " \
                            "(no <lb> seen)"
        end

        walk[:word] = { name: node.name, form: +"", flags: {},
                        "id" => node.attribute("xml:id"), "pos" => node.attribute("pos"),
                        "msd" => node.attribute("msd"), "lemma" => node.attribute("lemma"),
                        "join" => node.attribute("join") }
        close_token(walk) if node.self_closing?
      end

      def token_record(word)
        record = { "id" => word["id"], "form" => word[:form], "pos" => word["pos"],
                   "msd" => word["msd"], "lemma" => word["lemma"], "join" => word["join"] }
        record.merge!(word[:flags])
        record.reject do |key, value|
          value.nil? || value == "" ||
            (NULL_DROPPED_ATTRS.include?(key) && value.is_a?(String) && value.match?(NULL_PLACEHOLDER))
        end
      end

      # In-token notes are the token's surface (text flows via the open
      # word), place flagged. Editorial notes open a text capture for the
      # next line. Any other free-standing note is marginal apparatus:
      # censused by place, text swallowed until it closes.
      def open_note(node, walk)
        place = node.attribute("place")
        if walk[:word]
          walk[:word][:flags]["note"] = place || true
        elsif node.attribute("type") == "editorial"
          walk[:editorial] = +"" unless node.self_closing?
        else
          walk[:unrecognized][place ? "note[#{place}]" : "note"] += 1
          walk[:note_depth] = 0 unless node.self_closing?
        end
      end

      # Inside a marginal note, nested markup (<gap>, <unclear>) is part of
      # the apparatus, not the token stream: tracked only for depth.
      def swallow_note_element(node, walk)
        walk[:note_depth] += 1 unless node.self_closing?
      end

      def close_body_element(node, walk)
        return unless walk[:in_body]

        if walk[:note_depth]
          if walk[:note_depth].zero? && node.name == "note"
            walk.delete(:note_depth)
          else
            walk[:note_depth] -= 1
          end
        elsif walk[:editorial] && node.name == "note"
          finish_editorial_note(walk)
        else
          super
        end
      end

      # A closed editorial note ALWAYS waits for the next manuscript line:
      # the sigle notes announce the entry that FOLLOWS ("Lub 1353a" lands
      # between the last line of one charter — still open — and the next
      # charter's pb/lb, and belongs to the latter).
      def finish_editorial_note(walk)
        text = walk.delete(:editorial).strip
        (walk[:pending_notes] ||= []) << text unless text.empty?
      end

      def open_line_break(node, walk)
        super
        return unless walk[:line]

        pending = walk.delete(:pending_notes)
        walk[:line][:notes] = pending if pending && !pending.empty?
      end

      def capture_body_text(node, walk)
        return unless walk[:in_body]

        if walk[:editorial]
          walk[:editorial] << node.value
        elsif walk[:note_depth]
          nil # marginal-note text; the occurrence was censused at open
        else
          super
        end
      end

      def flush_line(walk)
        line = walk.delete(:line)
        walk[:prev_join] = nil
        return unless line && !line[:text].empty?

        walk[:lines] << Line.new(page: line[:page], column: line[:column], n: line[:n],
                                 edition_lines: line[:ed2], notes: line[:notes] || [],
                                 text: line[:text], tokens: line[:tokens])
      end
    end
  end
end
