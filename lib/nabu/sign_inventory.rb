# frozen_string_literal: true

module Nabu
  # The passage→sign-inventory resolver behind the sign-coverage lane
  # (P77-r16, sign-learning survey P-3): tokenize one ATF passage and
  # resolve each token to its top-level OSL sign name(s), counting what
  # cannot be resolved. The value/name maps fold a form's readings under
  # its parent sign (the SignTableBuilder rule), built once per SignList.
  #
  # Coverage semantics (documented, deliberately conservative):
  # - a :value token resolves through value→sign(s); an AMBIGUOUS value
  #   contributes EVERY candidate sign (a stranger candidate makes the
  #   passage foreign rather than silently covered);
  # - a :name token (bare logogram) and a :compound (|A.B|) resolve when
  #   the sign list carries that name; a :qualified token resolves by its
  #   explicit sign spec;
  # - :number tokens count as READABLE (numerals are universal — neither
  #   sign nor stray);
  # - :broken tokens and anything unresolved count as STRAYS — damaged or
  #   unknown text disqualifies a passage from graded reading honestly.
  class SignInventory
    # One passage's inventory: +signs+ = distinct top-level sign names,
    # +strays+ = tokens that resolved to nothing (incl. broken).
    Line = Data.define(:signs, :strays)

    def initialize(sign_list, dialect: :catf)
      @list = sign_list
      @tokenizer = Nabu::AtfTokenizer.new(dialect: dialect)
      @value_map, @name_set = reading_maps(sign_list)
    end

    # The inventory of one passage text (possibly multi-line), or nil
    # when no line yields tokens (structural/empty text).
    def scan(text)
      signs = Set.new
      strays = 0
      any = false
      text.to_s.each_line do |line|
        tokens = @tokenizer.tokenize_line(line) or next
        any = true unless tokens.empty?
        tokens.each { |token| strays += 1 unless resolve_token?(token, signs) }
      end
      any ? Line.new(signs: signs, strays: strays) : nil
    end

    # Resolve one signset entry the way a curriculum names signs: an OSL
    # sign name (ŠEŠ, |A.BARA₂|, aliases and form names included), or a
    # reading value (ses, ak — every candidate sign joins). Returns the
    # top-level sign names, or nil for an unknown entry.
    def signs_for(entry)
      record = @list.sign(entry)
      return [top_name(record)] if record

      folded = entry.to_s
      return @value_map[folded].to_a if @value_map.key?(folded)

      downcased = folded.downcase
      @value_map.key?(downcased) ? @value_map[downcased].to_a : nil
    end

    private

    # true when the token lands in +signs+ or is benignly readable;
    # false = a stray. The per-kind resolvers return the sign names
    # (possibly empty for a benign token) or nil for a stray —
    # :broken and anything unplaced falls through the case as nil.
    def resolve_token?(token, signs)
      names = case token.kind
              when :number then [] # numerals read universally
              when :value, :name then resolved_names(token.value)
              when :compound then named_sign(token.value)
              when :qualified then named_sign(token.sign_spec)
              end
      return false unless names

      names.each { |name| signs << name }
      true
    end

    def resolved_names(value)
      return @value_map[value] if @value_map.key?(value)
      return [value] if @name_set.include?(value)

      downcased = value.downcase
      @value_map.key?(downcased) ? @value_map[downcased] : nil
    end

    def named_sign(name)
      record = name && @list.sign(name)
      record && [top_name(record)]
    end

    # A variant-form hit folds under its parent sign, like its readings do.
    def top_name(record) = record.parent_name || record.name

    # value → Set of top-level sign names; the bare name set — a form's
    # readings fold under its parent sign (the SignTableBuilder rule).
    def reading_maps(list)
      value_map = Hash.new { |hash, key| hash[key] = Set.new }
      name_set = Set.new
      list.signs.each do |sign|
        name_set << sign.name
        ([sign] + sign.forms).each do |record|
          record.values.reject(&:deprecated).each { |value| value_map[value.value] << sign.name }
        end
      end
      [value_map, name_set]
    end
  end
end
