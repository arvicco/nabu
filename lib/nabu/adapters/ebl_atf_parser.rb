# frozen_string_literal: true

require_relative "atf_parser"

module Nabu
  module Adapters
    # The eBL-ATF dialect of the atf family (P31-3) — the Electronic
    # Babylonian Library's flavor of ATF (reference: the Lark grammar in
    # github.com/ElectronicBabylonianLiterature/ebl-api, ebl/transliteration/
    # domain/atf_parsers/lark_parser/*.lark, studied 2026-07-19, and docs/
    # ebl-atf.md). The line grammar core is inherited untouched; everything
    # here is the censused delta over the whole Zenodo-snapshot corpus
    # (23,289 fragments / 440,118 non-blank atf lines):
    #
    #   #tr.en: …                    per-LINE translations, like C-ATF — but
    #   #tr.en.(o 4): …              with an optional EXTENT ("the
    #                                translation runs to obverse 4"): 24,138
    #                                lines (en 22,932 · de 594 · ar 481 ·
    #                                typo codes eN/em/ebn/enb/ed keyed
    #                                verbatim), 2,014 with extents. The
    #                                sloppy real spellings — extent without
    #                                the dot, "." for ":", no terminator at
    #                                all — are matched tolerantly; the value
    #                                rides the open line under "tr" (the
    #                                P31-2 per-line rider decision, kept —
    #                                the data shape is identical), the
    #                                extent verbatim under "tr_extents". A
    #                                bare "#tr:" keys "en", the grammar's
    #                                own default. @i{…}/@sup{…} markup rides
    #                                verbatim inside the value.
    #   #note: …                     per-line apparatus (15,277 lines) →
    #                                "notes" on the open line; before any
    #                                line → document "note_lines".
    #   #lem: …                      ORACC-style lemmatization exists on ONE
    #                                fragment corpus-wide (BM.47447, 71
    #                                lines) → carried verbatim as "lem" on
    #                                the open line, and nothing ever reaches
    #                                the lemma index (the source is not
    #                                lemma-bearing; census verdict in
    #                                sources.yml).
    #   // F K.2198+ 1'-2'           parallel lines (10,893 — eBL's spelling
    #   // (UḪ V 52)                 of the C-ATF "||" rider): verbatim
    #   // cf. F K.13930 r 8'        strings under "parallels" on the open
    #                                line; the 2 corpus-wide cases before
    #                                any text line land in document
    #                                "parallels".
    #   @obverse! / @column 1'?      structure statuses ' ′ ’ ʾ ? ! * °
    #                                (ebl_atf_common.lark) are stripped for
    #                                CLASSIFICATION only — the segment stays
    #                                verbatim (the C-ATF "obverse?"
    #                                precedent). @colophon/@date/@catchline/
    #                                @end …/@m=division/@witnesses are
    #                                divisions via the core's open-vocabulary
    #                                default, kept verbatim.
    #   $ single ruling / $ (…)      the core's state mechanics carry eBL's
    #                                structured $-lines verbatim.
    #
    # == Language: the %-shift census, not a guess
    #
    # eBL-ATF has no #atf lang protocol; its own spec rules "if no shifts
    # are present Akkadian is used as the default language" (ebl-atf.md).
    # The document language is therefore the adapter default (akk) unless
    # the FIRST text line opens with a %-shift that the adapter-supplied
    # language_map resolves (%sux → sux, %es Emesal → sux; 5,183 fragments
    # open shifted) — first code wins, the C-ATF multi-language precedent.
    # A resolved shift is recorded verbatim ("language_shift"); an
    # unresolvable one falls to the default with the verbatim value kept
    # ("language_raw" — %su, %SUX case junk). Mid-line and later shifts ride
    # in the passage text verbatim, never re-labeled.
    #
    # There are no & headers (each fragment's atf field IS one block) and no
    # >>/=:/|| riders in the corpus; those C-ATF cases stay inherited and
    # simply never fire.
    class EblAtfParser < AtfParser
      # #tr[.code][.(extent)] with the censused sloppy variants: optional
      # dot before the extent, ":" or "." or no terminator. The lookahead
      # keeps "#traces…"-style comments out.
      EBL_TRANSLATION = /\A#tr(?=[.:(])(?:\.\s*([a-zA-Z]+))?\s*\.?\s*(?:\(([^)]*)\))?\s*[:.]?\s*(.*)\z/
      EBL_NOTE = /\A#note\b[:.]?\s*(.*)\z/
      EBL_LEM = /\A#lem:\s*(.*)\z/

      # Structure status marks (ebl_atf_common.lark status: prime, legacy
      # primes, uncertain, correction, collation, no-longer-visible).
      STRUCTURE_STATUS = /[?!*°'′’ʾ]+\z/

      private

      # -- the # seam -----------------------------------------------------------

      def directive(text, state)
        if (match = EBL_NOTE.match(text))
          note(match[1], state)
        elsif (match = EBL_LEM.match(text))
          rider(state, "lem", Normalize.nfc(match[1].rstrip))
        elsif (match = EBL_TRANSLATION.match(text)) && !(match[3].empty? && match[2].nil?)
          translation_with_extent(match, state)
        else
          super
        end
      end

      def note(text, state)
        value = Normalize.nfc(text.rstrip)
        return if value.empty?

        if (line = state[:lines].last)
          (line.annotations["notes"] ||= []) << value
        else
          (state[:doc_notes] ||= []) << value
        end
      end

      # The translation value joins the open line's "tr" hash exactly as the
      # core's does; the extent is a sibling annotation, verbatim.
      def translation_with_extent(match, state)
        code = match[1] || "en"
        value = Normalize.nfc(match[3].rstrip)
        line = state[:lines].last
        return comment("tr.#{code}: #{value}", state) if line.nil?

        translations = (line.annotations["tr"] ||= {})
        translations[code] = [translations[code], value].compact.reject(&:empty?).join("\n")
        return if match[2].nil?

        extents = (line.annotations["tr_extents"] ||= {})
        extent = Normalize.nfc(match[2].strip)
        extents[code] = [extents[code], extent].compact.reject(&:empty?).join("\n")
      end

      # -- the @ seam -----------------------------------------------------------

      # Status marks classify away; the face/column/object segment itself
      # stays verbatim (core slugify of the untouched body).
      def classify_at(token)
        super(token.sub(STRUCTURE_STATUS, ""))
      end

      # -- the fall-through seam: // parallels ----------------------------------

      def unrecognized(text, state)
        return super unless text.start_with?("//")

        entry = Normalize.nfc(text.delete_prefix("//").strip)
        if state[:lines].last
          rider(state, "parallels", entry)
        else
          (state[:doc_parallels] ||= []) << entry
        end
      end

      # -- language: the first text line's leading shift ------------------------

      def document_language(state)
        shift = state[:lines].first&.text&.[](/\A%(\S+)\s/, 1)
        return super if shift.nil?

        mapped = @language_map[shift]
        if mapped
          state[:language_shift] = "%#{shift}"
          mapped
        else
          state[:unmapped_language] = "%#{shift}"
          super
        end
      end

      def document_metadata(state, base)
        result = super
        result["language_shift"] = state[:language_shift] if state[:language_shift]
        result["note_lines"] = state[:doc_notes] if state[:doc_notes]
        result["parallels"] = state[:doc_parallels] if state[:doc_parallels]
        result
      end
    end
  end
end
