# frozen_string_literal: true

module Nabu
  # The language-note addressing (P85-A, №R-48-2): personal, per-language notes
  # ride the SAME note mechanism as URN- and source-bound notes (`nabu note`),
  # kept local/ and private — the FOURTH layer of the language card, composed
  # beneath the published universal overlay (nabu-data mul/language-dossiers)
  # and never itself published.
  #
  # A language is addressed by a canonical pseudo-URN, urn:nabu:lang:<code>, so
  # the whole existing note pipeline (the NoteShelf gateway, the urn_notes
  # index, `nabu note --list/--rm`, the surgical fast-refresh) carries language
  # notes with no new storage. `nabu note chu "…"` mints it: a bare language
  # code is deliberately NOT colon-bearing, so it can never be mistaken for a
  # corpus URN, and any colon-bearing target stays an ordinary URN note.
  module LanguageNote
    PREFIX = "urn:nabu:lang:"

    # A language-code target shape — the Nabu language-code namespace:
    # lower-case alphanumerics in hyphen-joined segments (chu, zle-ort,
    # roa-opt). No colon by construction (that is a URN's mark).
    CODE = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

    module_function

    def urn(code) = "#{PREFIX}#{code}"

    # The language code a note target names, or nil when the target is a
    # corpus URN (colon-bearing) or not a bare language code at all.
    def code_for(target)
      text = target.to_s.strip
      return nil if text.empty? || text.include?(":")

      text.match?(CODE) ? text : nil
    end

    # The code carried by a language pseudo-URN, or nil for any other urn.
    def code_of(urn)
      text = urn.to_s
      text.start_with?(PREFIX) ? text.delete_prefix(PREFIX) : nil
    end
  end
end
