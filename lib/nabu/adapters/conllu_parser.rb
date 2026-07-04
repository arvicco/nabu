# frozen_string_literal: true

module Nabu
  module Adapters
    # Streaming parser for one CoNLL-U treebank file — the second parser family
    # (architecture §3), sibling to EpidocParser: a standalone, individually
    # tested component that adapters (UniversalDependencies, and later PROIEL
    # exports) compose. Same call shape as EpidocParser#parse.
    #
    # == The format
    #
    # CoNLL-U is line-based TSV, 10 tab-separated columns per token:
    #
    #   ID FORM LEMMA UPOS XPOS FEATS HEAD DEPREL DEPS MISC
    #
    # A sentence is a block of `#`-comment lines followed by token lines,
    # terminated by a single blank line. One sentence = one Nabu::Passage.
    # Files are multi-MB in the wild (the trimmed fixtures stand in for
    # 1–3 MB test sets), so the read is strictly streaming (each_line — the
    # file is never slurped) and a block is materialized only long enough to
    # emit its Passage.
    #
    # == Passage minting
    #
    # - urn = "<document-urn>:<sent_id>", sent_id from the mandatory
    #   `# sent_id = …` comment. It is mandatory in UD; a block without one is
    #   a Nabu::ParseError (naming the file and the offending block) rather
    #   than a silently-skipped or auto-numbered sentence — a missing sent_id
    #   means the upstream file is malformed, not that we should paper over it.
    # - sequence = block order from 0.
    # - text = the `# text = …` comment (the authoritative surface string),
    #   NFC-normalized. Absent (not the case in any fixture, but legal), it is
    #   reconstructed from the FORM column honoring `SpaceAfter=No` in MISC.
    #   text_normalized = NFC(text.downcase) — the downcase can denormalize
    #   Greek, so it is re-normalized (same discipline as EpidocParser).
    #
    # == Annotations (the payload that makes treebanks worth ingesting)
    #
    # annotations = {
    #   "tokens" => [ {"id","form","lemma","upos","xpos","feats","head",
    #                  "deprel","misc"}, … ],   # `_` → dropped, keys stay lean
    #   "source" => <the `# source =` comment, when present>
    # }
    # DEPS (column 9) is intentionally not carried — enhanced dependencies are
    # not used downstream and would bloat every token; HEAD/DEPREL (the basic
    # tree) are kept. Column values are kept as strings, faithful to the TSV.
    #
    # == CoNLL-U quirks encountered in the UD ancient-language fixtures
    #
    # - Multiword tokens (MWT): a range line whose ID is "n-m" (e.g. the Latin
    #   enclitic `essetque` → "14-15") precedes its member tokens and, per
    #   spec, carries only FORM (+ optional MISC); its other 8 columns are `_`.
    #   It is emitted with just the columns it actually has ("id" as the range
    #   string, "form", and "misc" if any) — the generic `_`-drop handles this
    #   without a special case.
    # - Empty nodes: a decimal ID "n.m" (ellipsis in enhanced deps). None occur
    #   in these fixtures; tolerated and emitted verbatim if they do.
    # - PROIEL XPOS: the Gothic/Greek PROIEL treebanks use terse 2-char XPOS
    #   tags ("Pd", "V-", "Nb", "Df", …) — carried through untouched.
    # - MISC citations: PROIEL rows carry the source reference as `Ref=MATT_7.12`
    #   / `Ref=1.20.1` inside MISC (kept as-is inside the token's "misc"),
    #   alongside `LId=` lemma-disambiguators. Sanskrit-Vedic adds extra
    #   sentence-level comments (`# citation_text=…`, `# layer=…`); only
    #   sent_id/text/source are interpreted, the rest are ignored.
    # - License variance is per-treebank (see the UD adapter + fixture README);
    #   the parser is license-agnostic.
    class ConlluParser
      COLUMN_COUNT = 10

      # The nine token keys we keep, in TSV order, minus DEPS (index 8). Index
      # into the split line; nil marks a column deliberately skipped.
      TOKEN_KEYS = %w[id form lemma upos xpos feats head deprel deps misc].freeze
      private_constant :TOKEN_KEYS

      DROPPED_COLUMNS = %w[deps].freeze
      private_constant :DROPPED_COLUMNS

      MWT_ID = /\A\d+-\d+\z/
      private_constant :MWT_ID

      # Same signature family as EpidocParser#parse.
      def parse(source, urn:, language:, title: nil, canonical_path: nil)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title,
          canonical_path: canonical_path || source.to_s
        )

        each_block(source) do |block, sequence|
          document << build_passage(block, document_urn: urn, language: language, sequence: sequence)
        end

        raise Nabu::ParseError, "#{source}: no sentence blocks found" if document.empty?

        document
      end

      private

      # One accumulating sentence block: raw comment strings (sans leading `#`)
      # and the token lines already split into columns, plus the line number of
      # the block's first line for error messages.
      Block = Struct.new(:comments, :tokens, :first_line)
      private_constant :Block

      # Stream +source+ line by line, yielding a completed Block (and its 0-based
      # sequence) at each blank-line terminator. Never slurps the file.
      def each_block(source)
        sequence = 0
        block = nil
        line_no = 0

        read_lines(source) do |raw|
          line_no += 1
          line = raw.chomp

          if line.empty?
            next if block.nil?

            yield block, sequence
            sequence += 1
            block = nil
          elsif line.start_with?("#")
            block ||= Block.new([], [], line_no)
            block.comments << line.sub(/\A#\s?/, "")
          else
            block ||= Block.new([], [], line_no)
            block.tokens << split_token_line(line, source: source, line_no: line_no)
          end
        end

        # A file that does not end in a blank line still yields its last block.
        yield block, sequence if block
      end

      # +source+ is a filesystem path (String) opened streaming, or an already
      # open IO-like (StringIO in tests) iterated directly. A String is always a
      # path — String#each_line would otherwise iterate the path text itself.
      def read_lines(source, &block)
        if source.is_a?(String)
          File.open(source, "r:UTF-8") { |io| io.each_line(&block) }
        else
          source.each_line(&block)
        end
      end

      def split_token_line(line, source:, line_no:)
        columns = line.split("\t", -1)
        unless columns.length == COLUMN_COUNT
          raise Nabu::ParseError,
                "#{source}:#{line_no}: expected #{COLUMN_COUNT} tab-separated columns, " \
                "got #{columns.length}: #{line.inspect}"
        end
        columns
      end

      def build_passage(block, document_urn:, language:, sequence:)
        sent_id = comment_value(block, "sent_id")
        if sent_id.nil? || sent_id.empty?
          raise Nabu::ParseError,
                "block starting at line #{block.first_line}: missing mandatory `# sent_id`"
        end

        text = passage_text(block)
        Nabu::Passage.new(
          urn: "#{document_urn}:#{sent_id}",
          language: language,
          text: text,
          text_normalized: Nabu::Normalize.nfc(text.downcase),
          annotations: annotations(block),
          sequence: sequence
        )
      end

      # The `# text =` surface string (NFC), else a reconstruction from FORM.
      def passage_text(block)
        raw = comment_value(block, "text")
        raw = reconstruct_text(block) if raw.nil? || raw.empty?
        Nabu::Normalize.nfc(raw)
      end

      def annotations(block)
        result = { "tokens" => block.tokens.map { |columns| token_hash(columns) } }
        source = comment_value(block, "source")
        result["source"] = source if source && !source.empty?
        result
      end

      # A token as a lean hash: `_` placeholders and the dropped DEPS column
      # become absent keys. MWT range lines (only FORM/MISC populated) and empty
      # nodes fall out of this naturally.
      def token_hash(columns)
        hash = {}
        TOKEN_KEYS.each_with_index do |key, index|
          next if DROPPED_COLUMNS.include?(key)

          value = columns[index]
          next if value.nil? || value == "_"

          hash[key] = value
        end
        hash
      end

      # First `# key = value` comment for +key+, or nil. Tolerant of the exact
      # UD spacing (`# key = value`) and the loose `# key=value` some treebanks
      # emit for their non-standard comments.
      def comment_value(block, key)
        prefix = /\A#{Regexp.escape(key)}\s*=\s*/
        line = block.comments.find { |comment| comment.match?(prefix) }
        line&.sub(prefix, "")
      end

      # Reconstruct surface text from FORM, honoring SpaceAfter=No. A MWT range
      # supplies the surface for its member tokens (which are then skipped);
      # empty nodes contribute nothing. Fallback only — no fixture needs it.
      def reconstruct_text(block)
        out = +""
        skip_through = nil
        block.tokens.each do |columns|
          id = columns[0]
          next if id.include?(".") # empty node

          if (range = id.match(/\A(\d+)-(\d+)\z/))
            skip_through = range[2].to_i
            append_form(out, columns)
          elsif skip_through && id.to_i <= skip_through
            skip_through = nil if id.to_i == skip_through
          else
            append_form(out, columns)
          end
        end
        out.strip
      end

      def append_form(out, columns)
        out << columns[1]
        out << " " unless columns[9].to_s.split("|").include?("SpaceAfter=No")
      end
    end
  end
end
