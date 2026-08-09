# frozen_string_literal: true

module Nabu
  # Script dispatch for `nabu char` (P65-3): which desk card a given input
  # belongs to, decided purely from Unicode blocks — no catalog, no seam.
  #
  #   :cuneiform     every char in the Cuneiform blocks (base, Numbers &
  #                  Punctuation, Early Dynastic) — compound renderings
  #                  (𒋀𒀊) stay ONE sign identity, so multi-char is fine
  #   :hieroglyphic  every char in the Egyptian Hieroglyph blocks (basic,
  #                  format controls, Extended-A)
  #   :han           any other SINGLE character — the existing P37-4 card
  #                  path, unchanged (its own grain/shelf errors apply)
  #   :name          any other multi-char input — the sign-NAME lane (OSL
  #                  name/value first, then Gardiner-style code); never a
  #                  text lane, so the one-glyph grain rule survives
  module CharDispatch
    CUNEIFORM = [0x12000..0x123FF, 0x12400..0x1247F, 0x12480..0x1254F].freeze
    HIEROGLYPHIC = [0x13000..0x1342F, 0x13430..0x1345F, 0x13460..0x143FF].freeze

    # The sign-name character repertoire the :name lane accepts: ASCII
    # (C-ATF spellings, Gardiner codes, |compounds|) plus the OSL's own
    # letters and subscripts. Multi-char text in any other script is NOT a
    # name — the CLI keeps the classic one-glyph grain error for it.
    NAME_SHAPE = /\A[\x20-\x7EšṣṭŠṢṬŋŊʾ×₀-₉ₓ]+\z/

    def self.lane(input)
      ords = input.each_char.map(&:ord)
      return :cuneiform if ords.all? { |ord| CUNEIFORM.any? { |range| range.cover?(ord) } }
      return :hieroglyphic if ords.all? { |ord| HIEROGLYPHIC.any? { |range| range.cover?(ord) } }

      ords.size == 1 ? :han : :name
    end
  end
end
