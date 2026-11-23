# frozen_string_literal: true

module Nabu
  # The ONE detector for passage text that is an inspected Ruby object — a
  # parser that stringified a Hash or a node where it meant one of its
  # fields stores `{"key"=>…}` or `#<Nokogiri::XML::Element…>` as text,
  # which is valid NFC, non-empty and deterministic, so no other check sees
  # it. Shared by the adapter conformance invariant (test-time, every
  # fixture) and the `scrub:inspect_text` instrument (live rows already
  # loaded before a fix) — never a second regex.
  module InspectedText
    # The text shape of Hash#inspect (both the pre-3.4 `{"k"=>` and the
    # 3.4+ `{"k" => ` spellings, string or symbol keys, optionally inside an
    # Array) or of an object inspect (`#<Nokogiri::XML::Element…`,
    # `#<struct …`, `#<data …`) at the start of a passage. Anchored and
    # key-shaped on purpose: editorial braces/brackets (`{restored}`,
    # `<damaged>`) and an upstream `#` are real text, never matched.
    PATTERN = /\A\s*\[?\{\s*(?:"(?:[^"\\]|\\.)*"|:\w+)\s*=>|\A\s*#<(?:[A-Z][\w:]*|struct |data )/

    # The characters a PATTERN match can open with once leading whitespace
    # is trimmed — the cheap catalog-side prefilter (Store::InspectedTextScan)
    # narrows on these, PATTERN decides.
    OPENERS = ["{", "[", "#<"].freeze

    def self.match?(text)
      text.is_a?(String) && PATTERN.match?(text)
    end
  end
end
