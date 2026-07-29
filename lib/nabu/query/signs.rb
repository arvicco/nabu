# frozen_string_literal: true

require_relative "../errors"
require_relative "../atf_tokenizer"
require_relative "show"

module Nabu
  module Query
    # `nabu signs` (P53-2): ATF transliteration — a passage urn out of the
    # catalog's ATF corpora (cdli/oracc/ebl/etcsl-class shelves) or raw pasted
    # text — resolved token by token through the P53-1 SignList seam into
    # sign identities: value → sign name → codepoint(s). The first consumer
    # beside the CLI is the Edubba downstream, whose reading panels render
    # this output — the boundary holds: the sign list adds IDENTITY, not
    # curriculum.
    #
    # == The frozen status vocabulary (one per token, honest always)
    #
    #   deterministic  exactly one candidate sign, encoded
    #   qualified      a valueₓ(SIGN) form — the explicit sign resolved
    #   ambiguous      several candidate signs: ALL listed, never one silently
    #   no-codepoint   the sign resolved but carries no Unicode encoding —
    #                  absence is data (P53-1), never an error
    #   broken         an illegible token (x, X, [...], …)
    #   unknown        the value is not in the OSL — said plainly
    #
    # == Uppercase-logogram resolution order (the documented decision)
    #
    #   1. sign(NAME) verbatim (name / @aka / variant-form indexes)
    #   2. sign(NAME minus the ~a variant suffix), when one was present
    #   3. value fallback: lookup(name.downcase) — a logogram is routinely
    #      written by its dominant value (URI₅ → uri₅ → |ŠEŠ.AB|)
    #   4. a dotted group tries the |compound| wrapping first, then splits
    #      into its component sign names, each its own output token
    #   5. else unknown
    #
    # == Modes
    #
    # run_text needs NO catalog (raw ATF; language via the caller, dialect
    # :catf default). run_urn opens nothing itself — it reads the passage/
    # document through Query::Show on the caller's read-only catalog, takes
    # language from the row, and auto-selects the :etcsl dialect for the
    # etcsl shelf's urns (--dialect overrides). The JSON contract
    # (.json_payload) is the ONE serializer — CLI --json and MCP nabu_signs
    # emit the identical shape.
    class Signs
      # A urn that resolves to something other than transliterated text
      # (a dictionary entry), or an unknown dialect. Caller-fixable.
      class Error < Nabu::Error; end

      # One resolved token. +candidates+ is empty except for ambiguous
      # tokens; +codepoints+ nil when unresolved/unencoded; +glyph+ is the
      # OSL-rendered string (ucun) for the CLI columns — the JSON contract
      # carries codepoints only.
      Resolved = Data.define(:input_value, :status, :sign_name, :codepoints, :glyph,
                             :candidates, :language_qualifier, :determinative)
      Candidate = Data.define(:sign_name, :codepoints, :glyph, :status, :language_qualifier)
      Line = Data.define(:number, :urn, :text, :tokens)
      Result = Data.define(:mode, :urn, :language, :dialect, :source_slug, :license_class,
                           :lines, :skipped_lines)

      def initialize(sign_list:, catalog: nil)
        @list = sign_list
        @catalog = catalog
      end

      # Raw ATF text (catalog-free). Structural ATF lines are counted as
      # skipped, never resolved.
      def run_text(text, language: nil, dialect: :catf)
        tokenizer = tokenizer_for(dialect)
        lines = []
        skipped = 0
        text.each_line.map(&:chomp).reject { |line| line.strip.empty? }.each do |line|
          tokens = tokenizer.tokenize_line(line)
          next skipped += 1 if tokens.nil?

          lines << Line.new(number: lines.size + 1, urn: nil, text: line.strip,
                            tokens: resolve_tokens(tokens, tokenizer, language))
        end
        Result.new(mode: :text, urn: nil, language: language, dialect: tokenizer.dialect,
                   source_slug: nil, license_class: nil, lines: lines, skipped_lines: skipped)
      end

      # A passage, document, or range urn out of the catalog (read-only).
      # nil for an unknown urn; Error for a non-text urn (dictionary entry).
      # +dialect+ nil = auto by source (:etcsl for the etcsl shelf);
      # +language+ nil = the row's language.
      def run_urn(urn, language: nil, dialect: nil)
        result = Show.new(catalog: @catalog).run(urn)
        return nil if result.nil?
        raise Error, "#{urn} is not a transliterated text urn" unless text_result?(result)

        rows = passage_rows(result)
        lang = language || result.language
        tokenizer = tokenizer_for(dialect || (result.source_slug == "etcsl" ? :etcsl : :catf))
        lines, skipped = resolve_rows(rows, tokenizer, lang)
        Result.new(mode: :urn, urn: urn, language: lang, dialect: tokenizer.dialect,
                   source_slug: result.source_slug, license_class: result.license_class,
                   lines: lines, skipped_lines: skipped)
      end

      # -- the frozen JSON contract (Edubba's scripts consume this) ------------
      #
      # Per-token records carry exactly: input_value, status, sign_name,
      # codepoints[], candidates[], language_qualifier — sign_name null when
      # no single sign resolved, codepoints [] when none, candidates [] except
      # for ambiguous tokens (each candidate the same shape minus candidates)
      # — plus "determinative": true only on determinative tokens. Absent
      # data is null/[], never a placeholder. The envelope names the input
      # (mode/urn/language/dialect/source) and counts skipped structural
      # lines. Matching the export-jsonl precedent, the contract is pinned by
      # test + docs, not by a version key: existing keys never change or
      # disappear; additions are new, present-only keys.
      def self.json_payload(result)
        {
          "mode" => result.mode.to_s, "urn" => result.urn, "language" => result.language,
          "dialect" => result.dialect.to_s, "source" => result.source_slug,
          "lines" => result.lines.map do |line|
            { "n" => line.number, "urn" => line.urn, "text" => line.text,
              "tokens" => line.tokens.map { |token| token_record(token) } }
          end,
          "skipped_lines" => result.skipped_lines
        }
      end

      def self.token_record(token)
        record = {
          "input_value" => token.input_value, "status" => token.status,
          "sign_name" => token.sign_name, "codepoints" => token.codepoints || [],
          "candidates" => token.candidates.map do |candidate|
            { "input_value" => token.input_value, "status" => candidate.status,
              "sign_name" => candidate.sign_name, "codepoints" => candidate.codepoints || [],
              "language_qualifier" => candidate.language_qualifier }
          end,
          "language_qualifier" => token.language_qualifier
        }
        record["determinative"] = true if token.determinative
        record
      end

      private

      def tokenizer_for(dialect)
        AtfTokenizer.new(dialect: dialect)
      rescue ArgumentError => e
        raise Error, e.message
      end

      def text_result?(result)
        result.is_a?(Show::PassageResult) || result.is_a?(Show::DocumentResult) ||
          result.is_a?(Show::RangeResult)
      end

      # [urn, text] rows out of any Show result shape.
      def passage_rows(result)
        return [[result.urn, result.text]] if result.is_a?(Show::PassageResult)

        result.passages.map { |line| [line.urn, line.text] }
      end

      def resolve_rows(rows, tokenizer, language)
        lines = []
        skipped = 0
        rows.each do |row_urn, text|
          tokens = tokenizer.tokenize_line(text.to_s)
          next skipped += 1 if tokens.nil?

          lines << Line.new(number: lines.size + 1, urn: row_urn, text: text,
                            tokens: resolve_tokens(tokens, tokenizer, language))
        end
        [lines, skipped]
      end

      def resolve_tokens(tokens, tokenizer, language)
        tokens.flat_map { |token| resolve_token(token, tokenizer, language) }
      end

      def resolve_token(token, tokenizer, language)
        case token.kind
        when :broken then resolved(token.value, "broken", token)
        when :qualified then qualified(token)
        when :number then number(token, language)
        when :compound then from_records(token.value, [@list.sign(token.value)].compact, token)
        when :name then name(token, tokenizer, language)
        else value(token, language)
        end
      end

      def value(token, language)
        candidates = @list.lookup(token.value, language: language)
        from_records(token.value, candidates, token, value_key: token.value, language: language)
      end

      def qualified(token)
        input = "#{token.value}(#{token.sign_spec})"
        record = @list.sign(token.sign_spec) || @list.sign("|#{token.sign_spec}|")
        return resolved(input, "unknown", token) if record.nil?

        resolved(input, "qualified", token, record: record)
      end

      # A number's parenthesized notation is itself a value/sign lookup: the
      # whole spelling first (2(diš) is a real OSL value on MIN), then the
      # bare notation as value, then as sign name.
      def number(token, language)
        candidates = @list.lookup(token.value, language: language)
        candidates = @list.lookup(token.notation, language: language) if candidates.empty?
        if candidates.empty?
          record = @list.sign(token.notation)
          candidates = [record].compact
        end
        from_records(token.value, candidates, token, language: language)
      end

      # The documented uppercase-logogram order (class note): name → name
      # minus ~suffix → value fallback → compound-then-split for dotted
      # groups → unknown.
      def name(token, tokenizer, language)
        record = @list.sign(token.value) || suffixless_sign(token.value)
        return resolved(token.value, encoded_status(record), token, record: record) if record

        if token.value.include?(".")
          compound = @list.sign("|#{token.value}|")
          return resolved(token.value, encoded_status(compound), token, record: compound) if compound

          return split_dotted(token, tokenizer, language)
        end

        candidates = @list.lookup(token.value.downcase, language: language)
        from_records(token.value, candidates, token, language: language)
      end

      def suffixless_sign(name)
        base = name.sub(/(?:~[a-z0-9]+)+\z/, "")
        base == name ? nil : @list.sign(base)
      end

      def split_dotted(token, tokenizer, language)
        token.value.split(".").flat_map do |part|
          sub = AtfTokenizer::Token.new(raw: token.raw, value: part, kind: :name,
                                        determinative: token.determinative)
          name(sub, tokenizer, language)
        end
      end

      def from_records(input, records, token, value_key: nil, language: nil)
        case records.size
        when 0 then resolved(input, "unknown", token)
        when 1
          resolved(input, encoded_status(records.first), token, record: records.first,
                                                                value_key: value_key, language: language)
        else
          candidates = records.map do |record|
            Candidate.new(sign_name: record.name, codepoints: record.codepoints,
                          glyph: glyph(record), status: encoded_status(record),
                          language_qualifier: qualifier(record, value_key, language))
          end
          Resolved.new(input_value: input, status: "ambiguous", sign_name: nil,
                       codepoints: [], glyph: nil, candidates: candidates,
                       language_qualifier: nil, determinative: token.determinative)
        end
      end

      def resolved(input, status, token, record: nil, value_key: nil, language: nil)
        Resolved.new(
          input_value: input, status: status, sign_name: record&.name,
          codepoints: record&.codepoints, glyph: record ? glyph(record) : nil,
          candidates: [], language_qualifier: record ? qualifier(record, value_key, language) : nil,
          determinative: token.determinative
        )
      end

      def encoded_status(record)
        record.codepoints ? "deterministic" : "no-codepoint"
      end

      # The %lang qualifier of the value that matched this record, honoring
      # the active language filter (nil for name/compound/number-name paths).
      def qualifier(record, value_key, language)
        return nil if value_key.nil?

        match = record.values.find do |value|
          value.value == value_key && (language.nil? || value.language.nil? || value.language == language)
        end
        match&.language
      end

      def glyph(record)
        return record.ucun if record.ucun

        codepoints = record.codepoints or return nil
        chars = codepoints.filter_map { |code| code[/\AU\+(\h+)\z/, 1]&.to_i(16)&.chr(Encoding::UTF_8) }
        chars.empty? ? nil : chars.join
      end
    end
  end
end
