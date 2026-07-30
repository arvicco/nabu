# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # The asl parser family (P53-1): the Oracc Sign List's line-oriented ASL
    # grammar (github.com/oracc/osl, 00lib/osl.asl — CC0) → sign records for
    # the Nabu::SignList read seam. Grounded in the real bytes (fixture
    # test/fixtures/osl/, retrieved 2026-07-29):
    #
    #   @sign ŠEŠ            a sign block (@sign- = deprecated), tab- OR
    #   @list  MZL535        space-separated; @list carries BOTH the print
    #   @list  U+122C0       concordances (MZL/LAK/ABZL/…) and the single
    #   @uname CUNEIFORM …   Unicode codepoint (the U+xxxxx payload)
    #   @ucun  𒋀            the rendered glyph string
    #   @v     šeš           a value (@v- = deprecated; "%akk ṣillu" = a
    #   @form |X.Y|          language-qualified value); @form opens a variant
    #   …                    sub-record with its own values/encodings (@form-
    #   @@                   = deprecated, @form+ = plain variant), closed by
    #   @end sign            @@ (upstream once closes a form with a bare
    #                        @end sign — tolerated)
    #
    # Compounds carry @useq (component codepoint sequences, x122C0.x1200A →
    # U+122C0 U+1200A; a component can be a bare X/O = an unencodable part,
    # kept verbatim); @upua is a private-use codepoint. ~660 signs carry NO
    # encoding at all — that absence is data (codepoints == nil), never an
    # error.
    #
    # Unknown/unmodeled directives (@link, @inote, @uage, @ref, @pcun blocks,
    # the @listdef/@scriptdef headers, wrapped continuation lines, …) are
    # SKIPPED WITHOUT ERROR but COUNTED — Result#ignored is the censused
    # ignore tally, directive token → count. Sign-shaped directives outside
    # any @sign block (the @pcun ACN-proposal innards) fall into the same
    # census rather than leaking into records. Malformed STRUCTURAL lines
    # (nested @sign, @end sign / @@ without an open block, @form outside a
    # sign, a nameless @sign/@form, an unclosed block at EOF, a non-directive
    # line) raise Nabu::ParseError.
    class AslParser
      # One sign value (reading). +language+ is the bare %-qualifier token
      # when present ("akk", "akk/n", "elx", …), nil for plain values.
      Value = Data.define(:value, :deprecated, :language) do
        def initialize(deprecated: false, language: nil, **) = super
      end

      # One sign or variant-form record. +codepoint+ is the single "U+xxxxx"
      # (from "@list U+xxxxx"), +useq+ the component sequence (from @useq),
      # +upua+ a private-use "U+Fxxxx" — any may be nil; a record with none
      # is honestly unencoded. +forms+ is always [] on form records.
      # +parent_name+ is nil on top-level signs and the owning sign's name on
      # form records — the kunga₃ incident (2026-07-29): a value can live on
      # both an independent sign AND a same-named form of another sign, and
      # without the parent the two candidates are indistinguishable.
      SignRecord = Data.define(:name, :oid, :deprecated, :uname, :ucun,
                               :codepoint, :useq, :upua, :values, :aka,
                               :list_numbers, :forms, :parent_name) do
        # The effective codepoint list: single → one-element array, else the
        # @useq sequence, else nil (honestly unencoded).
        def codepoints = codepoint ? [codepoint] : useq

        def encoded? = !codepoints.nil?
      end

      # The parse product: +signs+ in file order (forms nested), +ignored+
      # the censused ignore tally ({directive token => count}).
      Result = Data.define(:signs, :ignored)

      CODEPOINT = /\AU\+\h+\z/
      USEQ_COMPONENT = /\Ax(\h+)\z/

      def parse_file(path)
        parse(File.read(path, encoding: Encoding::UTF_8), origin: path)
      end

      def parse(text, origin: "asl")
        @origin = origin
        @signs = []
        @ignored = Hash.new(0)
        @sign = @form = nil
        Nabu::Normalize.nfc(text).each_line.with_index(1) do |line, number|
          @line_number = number
          consume(line.chomp)
        end
        fail_parse("unclosed @sign #{@sign[:name]} at EOF") if @sign
        Result.new(signs: @signs, ignored: @ignored)
      end

      private

      def consume(line)
        return if line.strip.empty?
        return @ignored["(continuation)"] += 1 if line.match?(/\A[ \t]/)

        fail_parse("non-directive line #{line.inspect}") unless line.start_with?("@")

        directive, rest = line.split(/[ \t]+/, 2)
        rest = rest.to_s.strip
        dispatch(directive, rest.empty? ? nil : rest)
      end

      def dispatch(directive, rest)
        case directive
        in "@sign" | "@sign-" then open_sign(rest, deprecated: directive.end_with?("-"))
        in "@form" | "@form-" | "@form+" then open_form(rest, deprecated: directive.end_with?("-"))
        in "@@" then close_form
        in "@end" if rest == "sign" then close_sign
        in "@v" | "@v-" if target then add_value(rest, deprecated: directive.end_with?("-"))
        in "@list" if target then add_list(rest)
        in "@aka" if target then target[:aka] << require_payload("@aka", rest)
        in "@oid" if target then target[:oid] = require_payload("@oid", rest)
        in "@uname" if target then target[:uname] = require_payload("@uname", rest)
        in "@ucun" if target then target[:ucun] = require_payload("@ucun", rest)
        in "@upua" if target then target[:upua] = require_payload("@upua", rest)
        in "@useq" if target then target[:useq] = parse_useq(require_payload("@useq", rest))
        in "@end" then @ignored["@end #{rest}"] += 1 # @end pcun etc.
        else @ignored[directive] += 1
        end
      end

      # The innermost open record builder: an open @form, else the open
      # @sign, else nil (header / @pcun territory — censused, not modeled).
      def target = @form || @sign

      def open_sign(name, deprecated:)
        fail_parse("nested @sign #{name}") if @sign
        @sign = builder(fail_if_nameless("@sign", name), deprecated)
      end

      def open_form(name, deprecated:)
        fail_parse("@form #{name} outside a @sign block") unless @sign
        finish_form # upstream chains forms without @@ once; tolerate
        @form = builder(fail_if_nameless("@form", name), deprecated)
      end

      def close_form
        fail_parse("@@ without an open @form") unless @form
        finish_form
      end

      def close_sign
        fail_parse("@end sign without an open @sign") unless @sign
        finish_form # the one upstream form closed by @end sign, no @@
        @signs << build_record(@sign)
        @sign = nil
      end

      def finish_form
        return unless @form

        @form[:parent_name] = @sign[:name]
        @sign[:forms] << build_record(@form)
        @form = nil
      end

      def builder(name, deprecated)
        { name: name, deprecated: deprecated, oid: nil, uname: nil, ucun: nil,
          codepoint: nil, useq: nil, upua: nil, values: [], aka: [],
          list_numbers: [], forms: [], parent_name: nil }
      end

      def build_record(fields)
        SignRecord.new(**fields)
      end

      # @list carries both the print-list concordances (MZL535, LAK032^a, …)
      # and the sign's single Unicode codepoint (U+122C0).
      def add_list(rest)
        payload = require_payload("@list", rest)
        if payload.match?(CODEPOINT)
          target[:codepoint] = payload
        else
          target[:list_numbers] << payload
        end
      end

      # "@v šeš" | "@v- aŋ" | "@v %akk ṣillu" — the %-qualifier names the
      # language the reading belongs to; the value string stays verbatim
      # (subscripts, ₓ, query marks and all).
      def add_value(rest, deprecated:)
        payload = require_payload("@v", rest)
        language = nil
        if payload.start_with?("%")
          qualifier, payload = payload.split(/[ \t]+/, 2)
          fail_parse("language-qualified @v without a value: #{qualifier}") if payload.nil?
          language = qualifier.delete_prefix("%")
        end
        target[:values] << Value.new(value: payload, deprecated: deprecated, language: language)
      end

      # "x122C0.x1200A" → ["U+122C0", "U+1200A"]. A component that is not an
      # x-hex token (upstream uses bare X, once O, for unencodable parts) is
      # kept verbatim — partial encoding is data, not an error.
      def parse_useq(payload)
        payload.split(".").map do |component|
          (m = USEQ_COMPONENT.match(component)) ? "U+#{m[1].upcase}" : component
        end
      end

      def require_payload(directive, rest)
        fail_parse("#{directive} without a payload") if rest.nil?
        rest
      end

      def fail_if_nameless(directive, name)
        fail_parse("#{directive} without a sign name") if name.nil?
        name
      end

      def fail_parse(message)
        raise Nabu::ParseError, "#{@origin}:#{@line_number}: #{message}"
      end
    end
  end
end
