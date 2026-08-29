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
  #   :marks         a single editorial/house mark (⟦ ⌈ ⸀ ⿰ …) — the
  #                  library's own convention card (config/editorial_marks.yml).
  #                  P85: no external tool answers "what does ⟦ mean HERE"
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

    # Kana input of length ≥ 2 is a reading query for the :name lane (no
    # single identity exists for ひと). A SINGLE kana routes to the
    # single-char lane instead (P86-5/Q50, deliberately flipping the P65-3
    # "one-kana is a reading query" pin): its card renders the kana IDENTITY
    # first and composes the reading matches as a labeled panel beside it —
    # `--as reading` keeps the pure query.
    KANA = /\A[\p{Hiragana}\p{Katakana}ー]+\z/

    # The editorial/house marks that get their own card (P85): the exact
    # code points documented in config/editorial_marks.yml. A single such
    # char routes to the marks card; the two must agree — the char-dispatch
    # test pins this set against the config keys, so a new mark added to the
    # table without a code point here (or vice versa) turns the suite red.
    MARKS = [
      0x27E6, 0x27E7,           # ⟦ ⟧ erasure brackets
      0x2308, 0x2309,           # ⌈ ⌉ substitute brackets
      0x2B1A,                   # ⬚ gaiji placeholder
      0x2E00, 0x2E02, 0x2E03,   # ⸀ ⸂ ⸃ apparatus sigla
      0x2FF0, 0x2FF1            # ⿰ ⿱ IDS operators
    ].to_set.freeze

    def self.lane(input)
      ords = input.each_char.map(&:ord)
      return :cuneiform if ords.all? { |ord| CUNEIFORM.any? { |range| range.cover?(ord) } }
      return :hieroglyphic if ords.all? { |ord| HIEROGLYPHIC.any? { |range| range.cover?(ord) } }
      return :marks if ords.size == 1 && MARKS.include?(ords.first)
      return :name if ords.size > 1 && input.match?(KANA)

      ords.size == 1 ? :han : :name
    end
  end
end
