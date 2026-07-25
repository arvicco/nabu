# frozen_string_literal: true

module Nabu
  module Adapters
    # Streaming parser for one digilibLT LiLa-linked CoNLL-U file — the
    # `digiliblt-conllu` parser family (P45-3), a small bespoke sibling to
    # ConlluParser for the dialect CIRCSE ships in github.com/CIRCSE/digilibLT
    # (373 late-antique Latin prose texts, UDPipe-lemmatized and LiLa-linked).
    #
    # == COMPOSE VERDICT — ConlluParser refuted from the bytes (censused over
    # all 373 real files, 2026-07-25)
    #
    #   1. Token lines are 11–14 tab-separated columns: the 10 standard
    #      CoNLL-U columns PLUS 1..4 trailing LiLa lemma-bank IRI columns
    #      (http://lila-erc.eu/data/id/lemma/… — several when the "Bronze"
    #      automatic linking is ambiguous, 397,689 tokens; empty-after-tab
    #      when unlinked, 1,998,023 tokens). ConlluParser hard-fails on
    #      anything but exactly 10 columns.
    #   2. Every file opens with a doc-level `# key=value` header block
    #      (docId/docTitle/contributor/corpusRef/docAuthor/seeAlso/
    #      description) terminated by a blank line — to ConlluParser that is
    #      a sentence block missing its mandatory sent_id.
    #   3. Three files (dlt000340/dlt000547/dlt000649) wrap their docTitle
    #      onto a raw continuation line that is neither a comment nor a
    #      token line; it folds into the preceding header value here.
    #
    # == The dialect
    #
    #   # docId=dlt000008
    #   # docTitle=Rerum gestarum libri qui supersunt
    #   # docAuthor=Ammianus Marcellinus
    #   # description=Source description: …
    #   <blank>
    #   # sent_id = 1
    #   # text = Post emensos insuperabilis expeditionis eventus …
    #   1\tPost\tpost\tADV\t_\t_\t_\t_\t_\tCitationHierarchy=…\t<IRI>[\t<IRI>…]
    #
    # XPOS/FEATS/HEAD/DEPREL/DEPS are `_` corpus-wide (UDPipe lemma + PoS
    # only, no trees) and fall out via the generic `_`-drop. sent_id is a
    # per-document 1..n integer; `# text` is present on every one of the
    # corpus's 461,026 sentences and is the authoritative surface string.
    # Token IDs are plain integers corpus-wide — no MWT ranges, no empty
    # nodes.
    #
    # == Passage minting
    #
    # - urn = "<document-urn>:<sent_id>"; sequence = block order from 0.
    # - text = the `# text` comment, NFC. A block without sent_id or text is
    #   a ParseError (naming file and line), never a papered-over sentence.
    # - annotations = { "tokens" => […], "citation" => "Paragraphus_3,Sentence_1" }.
    #   The citation is the first token's CitationHierarchy (MISC), hoisted
    #   to the passage and stripped — it repeats on every token upstream
    #   (the glaux div_book/div_chapter precedent), so it never rides tokens.
    #
    # == Tokens (the silver lemma lane + the LiLa bridge)
    #
    # Each token keeps "id", "form", "upos", "lemma" and "lila" (the LiLa IRI
    # candidates as an array, absent when unlinked). PUNCT tokens drop the
    # "lemma" key — a full stop is not a dictionary form, so the silver lemma
    # index stays clean (the glaux precedent). Lemmas are LiLa u-spelling
    # (euentus, uarietas) — the conventions-§9 lat u/v fold unifies them at
    # search time.
    #
    # == Malformed upstream bytes (dlt000079)
    #
    # One file of 373 ships real damage: a stray "http" glued before its
    # first header comment, token lines with spaces for tabs, loose prose
    # words mid-file. Every such shape fails loudly here (ParseError → the
    # sync quarantines that one document); the 372 clean files carry ≥11
    # columns on every token line, so 11 is the floor, not 10.
    class DigilibltConlluParser
      COLUMN_FLOOR = 11
      STANDARD_COLUMNS = 10
      private_constant :COLUMN_FLOOR, :STANDARD_COLUMNS

      # Standard-column keys we keep, TSV order; deps is dropped (house rule,
      # as ConlluParser) and misc is consumed for the citation, never carried.
      TOKEN_KEYS = %w[id form lemma upos xpos feats head deprel].freeze
      private_constant :TOKEN_KEYS

      # Upstream spells anonymity as this literal (57 files) — never journaled.
      NO_AUTHOR = "No author"
      private_constant :NO_AUTHOR

      CITATION = /CitationHierarchy=([^|]*)/
      private_constant :CITATION

      # Same signature family as ConlluParser#parse. The doc header is
      # IN-FILE here, so title and document metadata are derived from it
      # (docAuthor — docTitle, the glaux convention); explicit +title+ /
      # +metadata+ from the caller override and merge over the derived ones.
      def parse(source, urn:, language:, title: nil, metadata: {}, license_override: nil,
                canonical_path: nil)
        path = canonical_path || (source.is_a?(String) ? source : source.path)
        header, blocks = split_stream(source, path: path)
        document = Nabu::Document.new(
          urn: urn, language: language,
          title: title || derived_title(header),
          metadata: derived_metadata(header).merge(metadata),
          canonical_path: path, license_override: license_override
        )
        blocks.each_with_index do |block, sequence|
          document << build_passage(block, document_urn: urn, language: language,
                                           sequence: sequence, path: path)
        end
        raise Nabu::ParseError, "#{path}: no sentence blocks found" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{path}: #{e.message}"
      end

      private

      # One sentence block: comment strings (sans "#"), token column arrays,
      # and the 1-based line number of the block's first line.
      Block = Struct.new(:comments, :tokens, :first_line)
      private_constant :Block

      # Single streaming pass: the header block (everything before the first
      # blank line) then the sentence blocks. Never slurps the file — the
      # largest upstream file is 16 MB (Ammianus).
      def split_stream(source, path:)
        header = {}
        blocks = []
        state = State.new(header: header, path: path)

        read_lines(source) do |raw|
          state.feed(raw.chomp) { |block| blocks << block }
        end
        state.finish { |block| blocks << block }
        [header, blocks]
      end

      # The line-by-line reader state machine (header phase, then blocks).
      class State
        def initialize(header:, path:)
          @header = header
          @path = path
          @in_header = true
          @last_header_key = nil
          @block = nil
          @line_no = 0
        end

        def feed(line, &)
          @line_no += 1
          if line.strip.empty?
            blank(&)
          elsif @in_header
            header_line(line)
          else
            block_line(line)
          end
        end

        def finish(&emit)
          emit.call(@block) if @block
          @block = nil
        end

        private

        def blank(&)
          @in_header = false
          finish(&)
        end

        def header_line(line)
          if line.start_with?("#")
            key, value = line.delete_prefix("#").split("=", 2)
            raise malformed("header comment without `=`") if value.nil?

            @last_header_key = key.strip
            @header[@last_header_key] = Nabu::Normalize.nfc(value.strip)
          elsif line.include?("\t")
            raise malformed("token line inside the document header")
          else
            # The wrapped-docTitle continuation (3 files upstream): folds
            # into the previous header value. Before any header comment
            # (dlt000079's mangled first line) it is damage, not format.
            raise malformed("continuation line before any header comment") unless @last_header_key

            @header[@last_header_key] = Nabu::Normalize.nfc(
              "#{@header[@last_header_key]} #{line.strip}"
            )
          end
        end

        def block_line(line)
          @block ||= Block.new([], [], @line_no)
          if line.start_with?("#")
            @block.comments << line.sub(/\A#\s?/, "")
          else
            @block.tokens << split_token_line(line)
          end
        end

        def split_token_line(line)
          columns = line.split("\t", -1)
          if columns.length < COLUMN_FLOOR
            raise malformed("expected >= #{COLUMN_FLOOR} tab-separated columns " \
                            "(10 CoNLL-U + the LiLa link column), got #{columns.length}: " \
                            "#{line.inspect}")
          end
          columns
        end

        def malformed(message)
          Nabu::ParseError.new("#{@path}:#{@line_no}: #{message}")
        end
      end
      private_constant :State

      def read_lines(source, &block)
        if source.is_a?(String)
          File.open(source, "r:UTF-8") { |io| io.each_line(&block) }
        else
          source.each_line(&block)
        end
      end

      # "docAuthor — docTitle"; docTitle alone for anonymous works; nil when
      # the header carries neither (Document then falls back per its rules).
      def derived_title(header)
        presence([author(header), presence(header["docTitle"])].compact.join(" — "))
      end

      def derived_metadata(header)
        {
          "doc_id" => presence(header["docId"]),
          "author" => author(header),
          "work" => presence(header["docTitle"]),
          "source_description" => presence(header["description"])
        }.compact
      end

      def author(header)
        value = presence(header["docAuthor"])
        value == NO_AUTHOR ? nil : value
      end

      def build_passage(block, document_urn:, language:, sequence:, path:)
        sent_id = comment_value(block, "sent_id")
        if sent_id.nil? || sent_id.empty?
          raise Nabu::ParseError,
                "#{path}:#{block.first_line}: sentence block missing mandatory `# sent_id`"
        end
        text = comment_value(block, "text")
        if text.nil? || text.empty?
          raise Nabu::ParseError,
                "#{path}:#{block.first_line}: sentence #{sent_id} missing its `# text` comment " \
                "(present on all 461,026 upstream sentences — absence is damage)"
        end

        Nabu::Passage.new(
          urn: "#{document_urn}:#{sent_id}",
          language: language,
          text: Nabu::Normalize.nfc(text),
          annotations: annotations(block),
          sequence: sequence
        )
      end

      def annotations(block)
        result = { "tokens" => block.tokens.map { |columns| token_hash(columns) } }
        citation = citation(block.tokens.first)
        result["citation"] = citation if citation
        result
      end

      # Standard columns via the generic `_`-drop (xpos/feats/head/deprel are
      # `_` corpus-wide), MISC consumed by #citation, columns 11+ = the LiLa
      # IRI candidates. PUNCT drops the lemma key (class note).
      def token_hash(columns)
        hash = {}
        TOKEN_KEYS.each_with_index do |key, index|
          value = columns[index]
          next if value.nil? || value == "_"
          next if key == "lemma" && columns[3] == "PUNCT"

          hash[key] = %w[form lemma].include?(key) ? Nabu::Normalize.nfc(value) : value
        end
        iris = columns[STANDARD_COLUMNS..].reject { |value| value.nil? || value.strip.empty? }
        hash["lila"] = iris unless iris.empty?
        hash
      end

      def citation(first_token)
        return nil unless first_token

        match = first_token[STANDARD_COLUMNS - 1].to_s.match(CITATION)
        match && presence(match[1].strip)
      end

      def comment_value(block, key)
        prefix = /\A#{Regexp.escape(key)}\s*=\s*/
        line = block.comments.find { |comment| comment.match?(prefix) }
        line&.sub(prefix, "")
      end

      def presence(value)
        value if value && !value.empty?
      end
    end
  end
end
