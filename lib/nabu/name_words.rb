# frozen_string_literal: true

module Nabu
  # The word grain of the alphabetic-script name lanes (the person mine's
  # word lane, the person-name candidate recipe): one passage or name key
  # cut into words the same way on both sides, so a name matches as a
  # whole-word SEQUENCE, never as a substring.
  #
  # A matching form, never a cleaned text (canonical stays canonical):
  # Leiden sigla that sit INSIDE a word — expansions "C(aius)",
  # restorations "Sex[tius]", the Elephantine half-brackets ⸢ ⸣ — are
  # dropped so the word reads whole, the rule Nabu::EdhPersons already
  # applies to its name keys; the combining dot below (U+0323, the Leiden
  # uncertain letter) drops for the same reason. Everything else that is
  # not a letter, mark or digit separates words. Spelling stays verbatim
  # (V/U, I/J are not merged: the inscription's own spelling is the claim).
  module NameWords
    INNER_SIGLA = /[\[\]()<>{}⟦⟧⸢⸣̣]/
    SEPARATOR = /[^\p{L}\p{M}\p{N}]+/

    module_function

    # The case-preserving words of +text+ (the candidate recipe reads
    # capitalization off these).
    def surface(text)
      text.to_s.gsub(INNER_SIGLA, "").split(SEPARATOR).reject(&:empty?)
    end

    # The folded words of +text+ — the shared name-key fold (Unicode case
    # fold, Pleiades.name_key's rule, restated here so the candidate
    # producer's code closure stays out of the gazetteer), word by word.
    def folded(text)
      surface(text).map { |word| fold(word) }
    end

    def fold(word) = word.downcase(:fold)

    # A folded name key in its word-lane form: its words joined by one space.
    def key(name) = folded(name).join(" ")
  end
end
