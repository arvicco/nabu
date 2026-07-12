# frozen_string_literal: true

require "json"

module Nabu
  module Adapters
    # Parser for one ORACC JSON corpus file (`corpusjson/<P/Q-number>.json`)
    # — the sixth parser family (P10-1), sibling to EpidocParser,
    # ConlluParser, ProielParser, DdbdpParser and GretilParser, and the
    # project's first JSON (non-XML) family. A standalone, individually
    # tested component that adapters (Oracc) compose.
    #
    # == The cdl tree (P9-5a findings, verified against both fixture projects)
    #
    # The document is a nested `cdl` tree of exactly three node kinds:
    #
    #   c  chunk: text > discourse > sentence; the sentence carries a human
    #      label ("o 1 - r 5"), often implicit
    #   d  discontinuity: type "object" (tablet), "surface" (obverse/reverse/
    #      seal), "line-start" (n + label, e.g. "o 1"), "nonw"/"nonx" (inline
    #      fragments and illegible stretches — never reading text)
    #   l  lemma: ONE word, its `f` object carrying the transliteration
    #      (form) and the gold lemmatization (norm/cf/gw/sense/pos/epos,
    #      lang, and a gdl grapheme array with per-sign logolang)
    #
    # Some rimanum texts additionally carry a node-less `linkbase` hash in
    # the top-level cdl array; anything without a "node" key is skipped.
    #
    # == Passage = the LINE
    #
    # The citable unit of Assyriology is the line ("obv. 5"): one passage per
    # `line-start` d-node. Passage#text is the TRANSLITERATION (the scholarly
    # text, conventions.md §4) reconstructed by joining each l-node's f.form
    # with single spaces, in document order, between line-starts.
    # Determinatives ({d}, {ki}), subscript numerals (ZI₃) and š/ṣ/ṭ survive
    # verbatim — folding is text_normalized's job (conventions.md §9, the
    # akk/sux rule). `nonw`/`nonx` d-node fragments are NOT reading text.
    #
    # CONTINUATION-OF-FORM pairs (rimanum reality): one written form can
    # carry two lemma words — NIG₂.ŠU = ša + qātu arrives as two l-nodes
    # sharing one ref, the head carrying "cof-tails", each continuation
    # carrying "cof-head". The form is written ONCE on the tablet, so a
    # cof continuation (an l-node with "cof-head") contributes NO text; both
    # words keep their token annotations. Without this rule the sign would
    # double in the passage text.
    #
    # Lines whose extraction is empty (an illegible stretch with no l-nodes)
    # are skipped; a document with zero citable lines is a ParseError
    # (quarantine — honest damage; the EMPTY catalog-only corpusjson files
    # never reach the parser: the adapter's discover skips them).
    #
    # == Identity (FROZEN minting)
    #
    #   urn         = urn:nabu:oracc:<project>:<textid>
    #   passage urn = <urn>:<line-label with spaces → dots>
    #
    # <project> is the file's own "project" field with any subproject slash
    # flattened to a hyphen (saao/saa01 → saao-saa01); <textid> is the stable
    # CDLI/ORACC P-number (artifact) or Q-number (composite). The line label
    # keeps everything else verbatim, primes included ("seal 1 1’" →
    # seal.1.1’). Most texts carry unique labels; where the P11-7 sentence-label
    # fallback makes two physical lines share a suffix (bilingual interlinear
    # blms, range-labeled saa08 omens), the second takes a ":b2" positional
    # suffix in document order (P14-9 disambiguate_suffixes — never quarantine,
    # never merge). The caller-supplied urn must equal the minting (mismatch →
    # ParseError, the DdbdpParser cross-check spirit).
    #
    # == Language: per-text primary, per-word honest
    #
    # ORACC tags every l-node (akk-x-oldbab, sux — Sumerian year-names occur
    # INSIDE Akkadian documents). Document and Passage#language carry the
    # per-text PRIMARY language: the majority base subtag over all l-nodes
    # (akk-x-oldbab → akk; ties broken by first attestation in document
    # order). The full per-word tag rides in every token annotation, and
    # per-grapheme logolang (Sumerian logograms inside Akkadian words) in
    # the token's "logolang" list. There is deliberately NO language:
    # parameter — unlike the XML families the language lives in the data,
    # not the repo layout.
    #
    # == Annotations (lean; only non-nil keys)
    #
    #   {"tokens" => [{"form","lemma","norm","gw","sense","pos","epos",
    #                  "lang","logolang"}…],   # lemma = cf, the citation form
    #    "sentences" => ["o 1 - r 5", …]}      # sentence c-node labels whose
    #                                          # words fall in this line
    #
    # The "tokens"/"lemma"/"form" shape is the SAME contract the treebank
    # families emit, so the P7-5 lemma index (Store::Indexer → passage_lemmas
    # → Query::LemmaSearch) picks up Akkadian/Sumerian citation forms with no
    # new plumbing. Upstream also carries morph/morph2/base (ETCSRI gold
    # morphology) — deliberately not ingested in v1, an enrichment-shaped
    # follow-up.
    class OraccJsonParser
      # f-object fields copied verbatim onto the token annotation when
      # present (f.cf lands as "lemma" — the shared treebank contract).
      LEMMA_FIELDS = %w[norm gw sense pos epos lang].freeze

      # Same signature family as the sibling parsers, minus language: (see
      # class note — the language is derived from the data).
      def parse(source, urn:, title: nil, canonical_path: nil)
        path = resolve_canonical_path(source, canonical_path)
        data = read_json(source, path: path)
        check_identity!(data, path: path, urn: urn)

        lines = Extraction.new.call(data["cdl"])
        build_document(lines, urn: urn, title: title, path: path)
      end

      private

      def resolve_canonical_path(source, canonical_path)
        return canonical_path if canonical_path
        return source if source.is_a?(String)
        return source.path if source.respond_to?(:path) && source.path

        raise ArgumentError, "canonical_path: is required when parsing from an IO without a #path"
      end

      def read_json(source, path:)
        raw = source.is_a?(String) ? File.read(source) : source.read
        JSON.parse(raw)
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed ORACC JSON: #{e.message}"
      end

      # urn:nabu:oracc:<project ("/"→"-")>:<textid> must equal the caller's
      # urn — a divergence means the file is not the document asked for.
      def check_identity!(data, path:, urn:)
        project = data["project"].to_s
        textid = data["textid"].to_s
        if project.empty? || textid.empty?
          raise ParseError, "#{path}: missing project/textid — not an ORACC corpus file"
        end

        minted = "urn:nabu:oracc:#{project.tr('/', '-')}:#{textid}"
        return if minted == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "project/textid mint #{minted.inspect}"
      end

      def build_document(lines, urn:, title:, path:)
        lines = lines.reject { |line| line.forms.empty? }
        # No transcribed lines: an object/surface skeleton catalogued but never
        # lemmatized (dcclt ships ~112 such files) — the catalog-only cousin of
        # the 0-byte case, an upstream norm, not damage. Skip it honestly (the
        # discovery accounting counts it "skipped by rule"), never quarantine.
        if lines.empty?
          raise DocumentSkipped.new("#{path}: no transcribed lines (catalog-only skeleton)",
                                    reason: "catalog-only (no content)")
        end

        language = primary_language(lines)
        document = Document.new(urn: urn, language: language, title: title, canonical_path: path)
        suffixes = disambiguate_suffixes(lines)
        lines.each_with_index do |line, sequence|
          document << Passage.new(
            urn: "#{urn}:#{suffixes[sequence]}",
            language: language,
            text: Normalize.nfc(line.forms.join(" ")),
            annotations: annotations(line),
            sequence: sequence
          )
        end
        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      # P14-9 collision tolerance (the GRETIL/ccmh :b<k> precedent, P9-4c/P13-2).
      # Bilingual literary (blms) and range-labeled omen (saa08) texts carry
      # MULTIPLE label-less line-starts under ONE sentence; the P11-7 fallback
      # resolves them all to that sentence's label, so distinct physical lines
      # (a Sumerian line and its Akkadian interlinear translation; an apodosis
      # gloss and its base line) would mint one suffix. Rather than quarantine
      # the whole tablet, the second line at a repeated suffix takes a ":b2"
      # positional suffix, the third ":b3", …, in document order — never merged
      # (different words/languages), never dropped. A document with no repeated
      # suffix is returned untouched: clean tablets keep byte-identical passage
      # urns (the frozen-URN guarantee).
      def disambiguate_suffixes(lines)
        seen = Hash.new(0)
        lines.map do |line|
          suffix = line_suffix(line.label)
          seen[suffix] += 1
          seen[suffix] == 1 ? suffix : "#{suffix}:b#{seen[suffix]}"
        end
      end

      # "o 1" → "o.1"; "seal 1 1’" → "seal.1.1’". FROZEN once minted.
      def line_suffix(label)
        Normalize.nfc(label).tr(" ", ".")
      end

      # Majority base subtag over the tokens' langs ("akk-x-oldbab" → "akk"),
      # ties broken by first attestation in document order (tally + max_by
      # both preserve insertion order, so the comparison is deterministic).
      def primary_language(lines)
        bases = lines.flat_map { |line| line.tokens.filter_map { |t| t["lang"]&.split("-")&.first } }
        raise ParseError, "no l-node carries a language tag" if bases.empty?

        bases.tally.max_by { |_base, count| count }.first
      end

      def annotations(line)
        result = { "tokens" => line.tokens }
        result["sentences"] = line.sentences unless line.sentences.empty?
        result
      end

      # One extracted line: label from its line-start d-node, forms in
      # document order (cof continuations excluded), token annotations for
      # every word, sentence labels touching the line.
      Line = Data.define(:label, :forms, :tokens, :sentences)
      private_constant :Line

      # The recursive cdl walk. State: the open line (l-nodes attach to it)
      # and the enclosing sentence label (scoped by recursion).
      class Extraction
        def call(cdl)
          @lines = []
          @current = nil
          walk(cdl, sentence: nil)
          @lines.map do |line|
            Line.new(label: line[:label], forms: line[:forms].freeze,
                     tokens: line[:tokens].freeze, sentences: line[:sentences].freeze)
          end
        end

        private

        def walk(nodes, sentence:)
          Array(nodes).each do |node|
            next unless node.is_a?(Hash) && node.key?("node") # linkbase etc.

            case node["node"]
            when "c" then chunk(node, sentence: sentence)
            when "d" then discontinuity(node, sentence: sentence)
            when "l" then lemma(node, sentence: sentence)
            end
          end
        end

        def chunk(node, sentence:)
          sentence = node["label"] if node["type"] == "sentence" && node["label"]
          walk(node["cdl"], sentence: sentence)
        end

        # Only line-start opens a line; object/surface context already lives
        # in the label ("o 1"), and nonw/nonx fragments are not reading text.
        #
        # LABEL-LESS line-start (dcclt ships ~58, e.g. P010104's one bare
        # line-start amid ~300 labeled ones — an upstream data gap): fall back
        # to the enclosing sentence c-node's label ("r xi' 10'"). If THAT too is
        # absent, skip only this line (set no open line so its words are not
        # citable) — never quarantine the whole document over one gap.
        def discontinuity(node, sentence:)
          return unless node["type"] == "line-start"

          label = node["label"].to_s
          label = sentence.to_s if label.empty?
          if label.empty?
            @current = nil
            return
          end

          @current = { label: label, forms: [], tokens: [], sentences: [] }
          @lines << @current
        end

        def lemma(node, sentence:)
          return if @current.nil? # words before any line-start are not citable

          features = node["f"] || {}
          form = features["form"]
          # a cof continuation shares the head's written form: token yes, text no
          @current[:forms] << form if form && !node.key?("cof-head")
          @current[:tokens] << token(features, form)
          record_sentence(sentence)
        end

        def token(features, form)
          token = {}
          token["form"] = form if form
          token["lemma"] = features["cf"] if features["cf"]
          OraccJsonParser::LEMMA_FIELDS.each do |field|
            token[field] = features[field] if features[field]
          end
          logolang = logolangs(features["gdl"])
          token["logolang"] = logolang unless logolang.empty?
          token
        end

        # Distinct per-grapheme logolang values, in order, from the (possibly
        # nested — sign groups) gdl array.
        def logolangs(gdl, found = [])
          Array(gdl).each do |entry|
            next unless entry.is_a?(Hash)

            value = entry["logolang"]
            found << value if value && !found.include?(value)
            logolangs(entry["group"], found)
            logolangs(entry["seq"], found)
          end
          found
        end

        def record_sentence(sentence)
          return unless sentence
          return if @current[:sentences].include?(sentence)

          @current[:sentences] << sentence
        end
      end
      private_constant :Extraction
    end
  end
end
