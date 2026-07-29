# frozen_string_literal: true

require "csv"
require "digest"

require_relative "../errors"
require_relative "../data_build/csv_writer"

module Nabu
  module Ops
    # P50-W3: generator for lib/nabu/xct.rb — the Tibetan-script → EWTS
    # transcoder — from the AUTHORED rule table config/ewts/rules.csv. One
    # table, two consumers: this generator compiles the module Nabu's search
    # fold runs, and Nabu::DataBuild::WylieFoldBuilder publishes the same
    # table as the xct/wylie-fold nabu-data dataset. Dev-time ops code
    # (fingerprint-excluded): the GENERATED module is what shapes derivation,
    # and it is registered in DerivationFingerprint::FOLD_MODULE_PATHS so a
    # rule change dirties exactly the Tibetan-consulting sources.
    #
    # The render is deliberately timestamp-free: regeneration over an
    # unchanged rules.csv is byte-stable (pinned in tests); provenance is the
    # table's sha256, not a date.
    #
    # == Validation (violations raise rather than compile a lying table)
    #
    # - header exactly ID,Tibetan,EWTS,Kind,Codepoints,Comment
    # - IDs unique, CLDF-identifier-shaped; Tibetan forms unique, single
    #   NFC codepoint each; EWTS non-empty
    # - Codepoints column names the Tibetan form's actual codepoint (U+ hex)
    # - Kind one of consonant/subjoined/vowel/mark/punctuation/digit
    class XctFoldBuilder
      RULES_PATH = File.expand_path("../../../config/ewts/rules.csv", __dir__)
      COLUMNS = %w[ID Tibetan EWTS Kind Codepoints Comment].freeze
      KINDS = %w[consonant subjoined vowel mark punctuation digit].freeze

      # The validated rules, as CSV-shaped hashes (the dataset builder
      # re-emits these verbatim through CsvWriter).
      attr_reader :rows

      def initialize(rules_path: RULES_PATH)
        @rules_path = rules_path
        @rows = parse
        validate!
      end

      def rules_sha256
        Digest::SHA256.file(@rules_path).hexdigest
      end

      # The lib/nabu/xct.rb source text.
      def render
        <<~RUBY
          # frozen_string_literal: true

          # GENERATED FILE — do not edit by hand. Regenerate with:
          #   rake fold:xct             (reads config/ewts/rules.csv)
          #
          # Nabu::Xct (P50-W3): the Tibetan-script → EWTS (THL Extended Wylie)
          # transcoder, compiled from the AUTHORED rule table that the
          # xct/wylie-fold nabu-data dataset publishes — one table, two
          # consumers (Nabu::Ops::XctFoldBuilder is the compiler).
          #
          # A TRANSCODE, not a per-codepoint fold (the Deva precedent): the
          # inherent "a" is positional — its seat is the root of the syllable,
          # found by the classical prefix/suffix grammar (constants below) —
          # and vowel signs, subjoined stacks and the a-chung particles are
          # contextual. Runs BEFORE the generic fold so the \\p{Mn} vowel
          # signs are read, not stripped. ONE WAY by design: display keeps the
          # native script; search folds to the EWTS skeleton on both sides.
          #
          # Anything outside the inventory passes through unchanged — an
          # unknown character is more honestly kept than guessed at (the
          # Betacode stance). Spec-EWTS capitals (T, Sh, A, M …) are kept
          # here; the SEARCH grain case-folds them via LANGUAGE_FOLDS.
          #
          # Provenance: config/ewts/rules.csv sha256 #{rules_sha256}
          module Nabu
            module Xct
              RULES_SHA256 = "#{rules_sha256}"

              CONSONANTS = #{table_literal('consonant', indent: 4)}

              SUBJOINED = #{table_literal('subjoined', indent: 4)}

              VOWELS = #{table_literal('vowel', indent: 4)}

              MARKS = #{table_literal('mark', indent: 4)}

              OTHERS = #{table_literal('punctuation', 'digit', indent: 4)}

              # ཨ (a-chen), the vowel carrier: bare = "a", with a vowel sign
              # the sign's value alone (ཨོ = "o", never "ao").
              CARRIER = "\\u0F68"

              # The classical syllable grammar (the inherent-a seat finder).
              PREFIXES = %w[g d b m '].freeze
              SUFFIXES = %w[g ng d n b m ' r l s].freeze
              POSTSUFFIXES = %w[s d].freeze # d = the Old Tibetan da-drag
              PREFIX_PAIRS = {
                "g" => %w[c ny t d n ts zh z y sh s],
                "d" => %w[k g ng p b m],
                "b" => %w[k g c t d ts zh z sh s],
                "m" => %w[kh g ng ch j ny th d n tsh dz],
                "'" => %w[kh g ch j th d ph b tsh dz]
              }.freeze
              # Three bare letters where prefix+root and root+suffix+s are BOTH
              # grammatical: the attested common reading wins (curated; the
              # remaining prefix-default ambiguities are documented in the
              # dataset README).
              AMBIGUOUS_BARE = { "m ng s" => 0, "b g s" => 0 }.freeze
              VOWEL_COMBOS = { "Ai" => "I", "Au" => "U" }.freeze

              module_function

              # Transcode +text+ to EWTS, NFC-normalized (output is ASCII, so
              # this is the identity pass Deva also runs). Latin/unknown text
              # passes through — the transcoder is idempotent on EWTS.
              def to_ewts(text)
                to_ewts_with_map(text).first
              end

              # Transcode with a character-index map (the KWIC contract):
              # [ewts, map] where map[i] is the index, into +text+'s
              # characters, of the character that produced ewts[i]. The
              # inherent "a" attributes to its root stack's head letter;
              # multi-char values attribute every output char to the one
              # source char (the Deva discipline).
              def to_ewts_with_map(text)
                out = +""
                map = []
                emit = lambda do |piece, index|
                  piece.each_char do |produced|
                    out << produced
                    map << index
                  end
                end
                units = []
                text.to_s.each_char.with_index do |char, i|
                  if CONSONANTS.key?(char)
                    units << new_unit(char, i)
                  elsif (sub = SUBJOINED[char])
                    units << new_unit(nil, i) if units.empty? || units.last[:vowels].any? || units.last[:coda].any?
                    units.last[:base] << [sub, i]
                    units.last[:subjoined] = true
                  elsif (vowel = VOWELS[char])
                    units << new_unit(nil, i) if units.empty? || units.last[:coda].any?
                    units.last[:vowels] << [vowel, i]
                  elsif (mark = MARKS[char])
                    units << new_unit(nil, i) if units.empty?
                    units.last[:coda] << [mark, i]
                  else
                    render_units(units, emit)
                    units = []
                    emit.call(OTHERS[char] || char, i)
                  end
                end
                render_units(units, emit)
                [out.unicode_normalize(:nfc), map]
              end

              def new_unit(char, index)
                sounded = !char.nil? && char != CARRIER
                { base: sounded ? [[CONSONANTS.fetch(char), index]] : [],
                  subjoined: false, vowels: [], coda: [], head_index: index,
                  letter: char && (char == CARRIER ? "a" : CONSONANTS.fetch(char)) }
              end

              # Render one tsheg-group. A bare MEDIAL a-chung opens an inner
              # syllable (na'ang = na + 'ang, dga'am = dga + 'am), so the
              # group splits there and each segment seats its own inherent a.
              def render_units(units, emit)
                return if units.empty?

                parts = segments(units)
                parts.each_with_index do |segment, index|
                  render_segment(segment, emit, before_split: index < parts.size - 1)
                end
              end

              def segments(units)
                parts = [[]]
                units.each_with_index do |unit, index|
                  if index.positive? && index < units.size - 1 &&
                     unit[:letter] == "'" && !unit[:subjoined] && unit[:vowels].empty?
                    parts << []
                  end
                  parts.last << unit
                end
                parts
              end

              def render_segment(units, emit, before_split: false)
                a_seats = inherent_a_positions(units)
                # A segment cut off by a following a-chung particle ends in an
                # OPEN root (dga + 'am, mtha + 'am): its a seats on the last
                # letter, not per the closed-syllable rules.
                a_seats = [units.size - 1] if before_split && a_seats.any? && units.none? { |u| u[:vowels].any? }
                units.each_with_index do |unit, index|
                  unit[:base].each { |piece, i| emit.call(piece, i) }
                  if unit[:vowels].any?
                    collapse_vowels(unit[:vowels]).each { |piece, i| emit.call(piece, i) }
                  elsif a_seats.include?(index)
                    emit.call("a", unit[:head_index])
                  end
                  unit[:coda].each { |piece, i| emit.call(piece, i) }
                end
              end

              # A+i = I, A+u = U (the NFC decompositions of U+0F73/U+0F75).
              def collapse_vowels(vowels)
                vowels.each_with_object([]) do |(value, index), acc|
                  combo = acc.any? && VOWEL_COMBOS[acc.last[0] + value]
                  if combo
                    acc[-1] = [combo, acc.last[1]]
                  else
                    acc << [value, index]
                  end
                end
              end

              # Which units of one segment carry the inherent "a".
              def inherent_a_positions(units)
                vowelled = (0...units.size).select { |i| units[i][:vowels].any? }
                if vowelled == [units.size - 1] && units.size > 1 && units.last[:letter] == "'"
                  # The connective particles ('i 'is 'o 'am …) ride a SUFFIX
                  # a-chung: the root sits in the preceding letters, seated by
                  # the no-vowel rules (dga'i = dga' + i, not *daga'i).
                  return no_vowel_positions(units)
                end

                if vowelled.any?
                  return [] if vowelled.size == 1 && native_shape?(units, vowelled.first)

                  return (0...units.size).reject { |i| units[i][:vowels].any? }
                end
                no_vowel_positions(units)
              end

              def no_vowel_positions(units)
                return [0] if units.size == 1

                subbed = (0...units.size).select { |i| units[i][:subjoined] }
                return [subbed.first] if subbed.size == 1 && native_shape?(units, subbed.first)
                return (0...units.size).to_a if subbed.any? # loan stacks: ka rma

                bare_root_positions(units)
              end

              # Does prefix(≤1) + root-at(+root) + suffix(≤2) parse natively?
              def native_shape?(units, root)
                pre = units[0...root]
                post = units[(root + 1)..]
                return false if pre.size > 1 || post.size > 2
                return false unless pre.all? { |u| bare?(u) && PREFIXES.include?(u[:letter]) }
                return false unless post.all? { |u| bare?(u) }
                return false unless post.empty? || SUFFIXES.include?(post[0][:letter])

                post.size < 2 || POSTSUFFIXES.include?(post[1][:letter])
              end

              def bare?(unit)
                !unit[:subjoined] && !unit[:letter].nil? && unit[:vowels].empty?
              end

              # The classical positional rules over bare single letters.
              def bare_root_positions(units)
                return (0...units.size).to_a unless units.all? { |u| bare?(u) || u[:vowels].any? }

                letters = units.map { |u| u[:letter] }
                case letters.size
                when 2 then [0]
                when 3
                  return [1] if letters[2] == "'"
                  return [AMBIGUOUS_BARE.fetch(letters.join(" "))] if AMBIGUOUS_BARE.key?(letters.join(" "))

                  PREFIX_PAIRS.fetch(letters[0], []).include?(letters[1]) ? [1] : [0]
                when 4
                  PREFIX_PAIRS.fetch(letters[0], []).include?(letters[1]) ? [1] : (0...4).to_a
                else
                  (0...units.size).to_a
                end
              end
            end
          end
        RUBY
      end

      private

      def parse
        table = CSV.read(@rules_path)
        header = table.shift
        unless header == COLUMNS
          raise Nabu::ValidationError, "#{@rules_path}: header must be #{COLUMNS.join(',')}, got #{header.inspect}"
        end

        table.map { |values| COLUMNS.zip(values).to_h }
      end

      def validate!
        seen_ids = {}
        seen_forms = {}
        @rows.each do |row|
          id = row["ID"].to_s
          raise Nabu::ValidationError, "rule ID #{id.inspect} must match the CLDF identifier regex" unless
            id.match?(DataBuild::CsvWriter::ID_PATTERN)
          raise Nabu::ValidationError, "duplicate rule ID #{id.inspect}" if seen_ids.key?(id)

          seen_ids[id] = true
          validate_form!(row, seen_forms)
          raise Nabu::ValidationError, "#{id}: unknown kind #{row['Kind'].inspect}" unless KINDS.include?(row["Kind"])
          raise Nabu::ValidationError, "#{id}: EWTS value must be non-empty" if row["EWTS"].to_s.empty?
        end
      end

      def validate_form!(row, seen_forms)
        id = row["ID"]
        form = row["Tibetan"].to_s
        unless form.chars.size == 1 && form == form.unicode_normalize(:nfc)
          raise Nabu::ValidationError, "#{id}: Tibetan form must be one NFC codepoint, got #{form.inspect}"
        end
        raise Nabu::ValidationError, "duplicate Tibetan form #{form.inspect} (#{id})" if seen_forms.key?(form)

        seen_forms[form] = true
        declared = row["Codepoints"].to_s
        actual = format("U+%04X", form.ord)
        return if declared == actual

        raise Nabu::ValidationError, "#{id}: Codepoints says #{declared.inspect} but the Tibetan form is #{actual}"
      end

      # A `{ "ཀ" => "k", ... }.freeze` literal for the given kinds, chunked
      # into rubocop-clean lines.
      def table_literal(*kinds, indent:)
        pairs = @rows.select { |row| kinds.include?(row["Kind"]) }
                     .map { |row| "#{row['Tibetan'].inspect} => #{row['EWTS'].inspect}" }
        lines = pairs.each_slice(6).map { |slice| "#{' ' * (indent + 2)}#{slice.join(', ')}" }
        ["{", lines.join(",\n"), "#{' ' * indent}}.freeze"].join("\n")
      end
    end
  end
end
