# frozen_string_literal: true

module Nabu
  module Adapters
    # Streaming parser for one LASLA CoNLL-U Plus file — the `lasla-conllup`
    # parser family, a bespoke sibling of ConlluParser for the dialect CIRCSE
    # ships in github.com/CIRCSE/LASLA/conllup (the LASLA hand-verified Latin
    # corpus, linked to the LiLa LemmaBank).
    #
    # == COMPOSE VERDICT — ConlluParser refuted from the bytes (censused over
    # all 242 upstream files, 2026-10-21)
    #
    # Token lines carry 13, 15, 17 or 19 tab-separated columns (ConlluParser
    # hard-fails on anything but 10): the 10 standard columns, then three
    # LiLa columns — FLCAT (LiLa inflectional category), SENTID (the sent_id
    # again), LINE (the token's row in LASLA's database) — then one
    # (lilaLemma, TokenURI) PAIR per LiLa lemma candidate: none (13 columns,
    # 128,416 lines) on a multiword-token range line (36,405) and on every
    # word of the six files upstream never linked (92,011: Livy 8, Ovid
    # Met. 6 / 7+11+14 / 9+10, Pliny NH 2 / 37 — which also carry no
    # CitationHierarchy, so their passages cite by sent_id alone), one on an
    # unambiguous token (15; 1,743,705), two or three when the linking is
    # ambiguous (17: 1,506; 19: 2,149). The `# global.columns` header names
    # only the first 13 — the README documents the pair ("the link to LiLa
    # knowledge base", "the token uri"). Floor 13, and the tail must pair.
    #
    # == The dialect
    #
    #   # global.columns = ID FORM LEMMA … LILA:FLCAT LILA:SENTID LILA:LINE
    #   # sent_id = CicQuaest-D-59-1
    #   # text = quod non detrectare militiam sed defendere prouinciam iudicata est
    #   1\tquod\tquod\tSCONJ\tT\t_\t_\t_\t_\tCitationHierarchy=…\ti\tCicQuaest-D-59-1\t1\tlilaLemma:74854\tTokenURI=…
    #
    # The global.columns line opens the FIRST block (no blank line after it)
    # and is an ordinary ignored comment. Every block carries sent_id and
    # text (95,974 of each); text is LASLA's normalized surface (u for v,
    # no punctuation — no PUNCT tokens exist corpus-wide). HEAD/DEPREL/DEPS
    # are `_` everywhere: lemma + morphology, no trees.
    #
    # == Passage minting
    #
    # urn = "<document-urn>:<sent_id>" (verbatim), sequence = block order.
    # A REPEATED sent_id is upstream's own shape for an interleaved sentence
    # resumed after a fragment (Tacitus Hist. 4: 1791, 1792, 1791, 1792 —
    # the only file of 242 that does it, twice): the second occurrence cites
    # "<sent_id>.2" and records "sent_id" + "sent_id_occurrence" — never a
    # urn collision, never a quarantined Tacitus book.
    #
    # Passage annotations: "tokens"; "citation" = the first token's MISC
    # CitationHierarchy ("Liber_1,Versus_1"; ambiguous tokens repeat it
    # pipe-joined — the first copy wins) and "citation_end" = the last
    # token's when the sentence crosses a unit (verse sentences span lines).
    #
    # == Tokens (the GOLD lemma lane)
    #
    # "id","form","lemma","upos","xpos","feats" (the `_`-drop; LASLA's own
    # code rides xpos — "B1", "A3"; feats is UD Key=Value, the morph façade's
    # native dialect), "flcat" (LiLa inflectional category), "lasla_line"
    # (the LINE column), "lila" (the lemma candidates, CURIEs verbatim —
    # "lilaLemma:74854"; several when ambiguous). MISC LASLAVariant →
    # "lasla_variant"; MISC Tac → "tac" (the word upstream marks as
    # understood: "testatum" Tac=est). The TokenURI repeats one per-file
    # base plus the 7-digit LINE ("…CicQuaest.BPN_t_0000001"), so it folds
    # into document metadata "lila_token_base" once; a token whose URI is
    # NOT base + line keeps it verbatim as "token_uri" (nothing is lost
    # silently). The SENTID column duplicates the block's sent_id and is
    # not carried.
    class LaslaConllupParser
      STANDARD_COLUMNS = 10
      LILA_FIXED = 3
      COLUMN_FLOOR = STANDARD_COLUMNS + LILA_FIXED
      private_constant :STANDARD_COLUMNS, :LILA_FIXED, :COLUMN_FLOOR

      TOKEN_KEYS = %w[id form lemma upos xpos feats].freeze
      private_constant :TOKEN_KEYS

      FLCAT = 10
      LINE = 12
      private_constant :FLCAT, :LINE

      CITATION = /CitationHierarchy=([^|]*)/
      TOKEN_URI = "TokenURI="
      URI_BASE = /\A(.*BPN_t_)(\d+)\z/
      private_constant :CITATION, :TOKEN_URI, :URI_BASE

      # Same signature family as ConlluParser#parse. +metadata+ from the
      # caller (author/work from the filename) merges under the derived
      # lila_token_base.
      def parse(source, urn:, language:, title: nil, metadata: {}, canonical_path: nil)
        path = canonical_path || source.to_s
        blocks = read_blocks(source, path: path)
        base = token_base(blocks)
        document = Nabu::Document.new(
          urn: urn, language: language, title: title, canonical_path: path,
          metadata: metadata.merge({ "lila_token_base" => base }.compact)
        )
        seen = Hash.new(0)
        blocks.each_with_index do |block, sequence|
          document << build_passage(block, document_urn: urn, language: language, sequence: sequence,
                                           seen: seen, base: base, path: path)
        end
        raise Nabu::ParseError, "#{path}: no sentence blocks found" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      private

      Block = Struct.new(:comments, :tokens, :first_line)
      private_constant :Block

      # Blank-line-delimited blocks; a path is read whole through the
      # encoding belt (the largest upstream file is ~10 MB — invalid bytes
      # quarantine the document as ParseError), token lines split and
      # validated as they arrive.
      def read_blocks(source, path:)
        blocks = []
        block = nil
        each_line(source).with_index(1) do |raw, line_no|
          line = raw.chomp
          if line.strip.empty?
            blocks << block if block
            block = nil
            next
          end
          block ||= Block.new([], [], line_no)
          if line.start_with?("#")
            block.comments << line.sub(/\A#\s?/, "")
          else
            block.tokens << split_token_line(line, path: path, line_no: line_no)
          end
        end
        blocks << block if block
        blocks
      end

      def each_line(source, &)
        return enum_for(:each_line, source) unless block_given?

        if source.is_a?(String)
          SourceRead.utf8_file(source, label: "lasla").each_line(&)
        else
          source.each_line(&)
        end
      end

      def split_token_line(line, path:, line_no:)
        columns = line.split("\t", -1)
        if columns.length < COLUMN_FLOOR || (columns.length - COLUMN_FLOOR).odd?
          raise Nabu::ParseError,
                "#{path}:#{line_no}: expected 13 + 2n tab-separated columns (10 CoNLL-U, 3 LiLa, " \
                "lemma/URI pairs), got #{columns.length}: #{line[0, 120].inspect}"
        end
        columns
      end

      # The per-file TokenURI base, read off the first token carrying a URI.
      def token_base(blocks)
        blocks.each do |block|
          block.tokens.each do |columns|
            uri = uris(columns).first
            match = uri && URI_BASE.match(uri)
            return match[1] if match
          end
        end
        nil
      end

      def build_passage(block, document_urn:, language:, sequence:, seen:, base:, path:)
        sent_id = comment_value(block, "sent_id")
        text = comment_value(block, "text")
        if sent_id.nil? || sent_id.empty? || text.nil? || text.empty?
          raise Nabu::ParseError, "#{path}:#{block.first_line}: sentence block missing `# sent_id` or `# text`"
        end

        occurrence = (seen[sent_id] += 1)
        cite = occurrence == 1 ? sent_id : "#{sent_id}.#{occurrence}"
        Nabu::Passage.new(
          urn: "#{document_urn}:#{cite}", language: language, text: Nabu::Normalize.nfc(text),
          annotations: annotations(block, sent_id: sent_id, occurrence: occurrence, base: base),
          sequence: sequence
        )
      end

      def annotations(block, sent_id:, occurrence:, base:)
        result = { "tokens" => block.tokens.map { |columns| token_hash(columns, base: base) } }
        words = block.tokens.reject { |columns| columns[0].include?("-") }
        first = citation(words.first)
        last = citation(words.last)
        result["citation"] = first if first
        result["citation_end"] = last if last && last != first
        if occurrence > 1
          result["sent_id"] = sent_id
          result["sent_id_occurrence"] = occurrence
        end
        result
      end

      def token_hash(columns, base:)
        hash = {}
        TOKEN_KEYS.each_with_index do |key, index|
          value = columns[index]
          next if value.nil? || value == "_"

          hash[key] = %w[form lemma].include?(key) ? Nabu::Normalize.nfc(value) : value
        end
        misc = columns[STANDARD_COLUMNS - 1].to_s.split("|")
        variant = misc_value(misc, "LASLAVariant")
        tac = misc_value(misc, "Tac")
        hash["flcat"] = columns[FLCAT] unless blank?(columns[FLCAT])
        hash["lasla_line"] = columns[LINE] unless blank?(columns[LINE])
        hash["lasla_variant"] = variant if variant
        hash["tac"] = Nabu::Normalize.nfc(tac) if tac
        lemmas = lila_lemmas(columns)
        hash["lila"] = lemmas unless lemmas.empty?
        uri = uris(columns).first
        hash["token_uri"] = uri if uri && !(base && uri == "#{base}#{format('%07d', columns[LINE].to_i)}")
        hash
      end

      def pairs(columns) = columns[COLUMN_FLOOR..].each_slice(2).to_a

      def lila_lemmas(columns) = pairs(columns).map(&:first).reject { |value| blank?(value) }.uniq

      def uris(columns)
        pairs(columns).filter_map do |_lemma, uri|
          uri.delete_prefix(TOKEN_URI) if uri&.start_with?(TOKEN_URI)
        end.uniq
      end

      def misc_value(misc, key)
        pair = misc.find { |item| item.start_with?("#{key}=") }
        value = pair&.split("=", 2)&.last
        value unless blank?(value)
      end

      def citation(columns)
        return nil unless columns

        match = columns[STANDARD_COLUMNS - 1].to_s.match(CITATION)
        match && !match[1].strip.empty? ? match[1].strip : nil
      end

      def comment_value(block, key)
        prefix = /\A#{Regexp.escape(key)}\s*=\s*/
        line = block.comments.find { |comment| comment.match?(prefix) }
        line&.sub(prefix, "")&.strip
      end

      def blank?(value) = value.nil? || value.strip.empty? || value == "_"
    end
  end
end
