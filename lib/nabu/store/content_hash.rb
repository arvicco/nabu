# frozen_string_literal: true

require "digest"
require "json"

module Nabu
  module Store
    # Canonical content hashing — the backbone of loader idempotency
    # (architecture §3). Two loads of semantically identical content must
    # produce the same sha, and *only* identical content may: the encoding is
    # made unambiguous by netstring-style length prefixes (no separator that
    # could occur inside a field can forge a boundary) and an explicit nil
    # marker, and JSON is canonicalized by recursively sorting hash keys so
    # annotation key order never causes a spurious revision.
    #
    # Changing this encoding invalidates every stored content_sha256 (the next
    # full load would revise every row), so treat it as a persistent format:
    # never change it casually, and never without a migration story.
    module ContentHash
      module_function

      # sha256 over (urn, language, text, text_normalized, canonical
      # annotations JSON, sequence). Covers every content column of the
      # passages table except revision/withdrawn, which are bookkeeping.
      def passage(passage)
        digest(
          passage.urn, passage.language, passage.text, passage.text_normalized,
          canonical_json(passage.annotations), passage.sequence.to_s
        )
      end

      # sha256 over the document's own fields plus its passages' hashes in
      # sequence order — so any passage change, addition, removal or reorder
      # changes the document hash too.
      def document(document, passage_hashes)
        digest(document.urn, document.language, document.title, document.canonical_path, *passage_hashes)
      end

      # sha256 over a dictionary entry's content columns (P11-4) — everything
      # except revision/withdrawn bookkeeping. Citations are content: a
      # citation change is a real upstream revision. Reflexes (P14-1) are
      # content too, but are appended ONLY when present: this module is a
      # persistent format, and the guard keeps every reflex-less entry on
      # every pre-P14-1 shelf at its stored sha (pinned in the ContentHash
      # test) — no revision storm on the next full load.
      def dictionary_entry(entry)
        citations = entry.citations.map do |citation|
          { "urn_raw" => citation.urn_raw, "cts_work" => citation.cts_work,
            "citation" => citation.citation, "label" => citation.label }
        end
        digest(
          entry.entry_id, entry.key_raw, entry.language, entry.headword,
          entry.headword_folded, entry.gloss, entry.body, canonical_json(citations),
          *reflex_fields(entry)
        )
      end

      # The only-when-non-empty guard: an empty reflex list contributes NO
      # fields (the pre-P14-1 encoding, byte for byte). `borrowed` (P17-3)
      # is deliberately part of the encoding: flag-bearing reparses change
      # the sha of every reflex-carrying entry, so the next owner-fired
      # `sync <shelf> --parse-only` re-mints those revisions and backfills
      # migration 010's column — the P16-5 recovery pattern, on purpose.
      def reflex_fields(entry)
        return [] if entry.reflexes.empty?

        reflexes = entry.reflexes.map do |reflex|
          { "lang_code" => reflex.lang_code, "language" => reflex.language,
            "word" => reflex.word, "roman" => reflex.roman,
            "word_folded" => reflex.word_folded, "roman_folded" => reflex.roman_folded,
            "borrowed" => reflex.borrowed }
        end
        [canonical_json(reflexes)]
      end

      # JSON with hash keys sorted recursively (by string form), so
      # semantically equal structures serialize — and therefore hash — equal.
      # Also used for the stored annotations_json, keeping rows byte-stable
      # across rebuilds.
      def canonical_json(value)
        JSON.generate(canonicalize(value))
      end

      def canonicalize(value)
        case value
        when Hash
          value.sort_by { |key, _| key.to_s }.to_h { |key, element| [key.to_s, canonicalize(element)] }
        when Array
          value.map { |element| canonicalize(element) }
        else
          value
        end
      end

      # Unambiguous serialization: each field is length-prefixed
      # ("<bytesize>:<bytes>"), nil is the bare marker "~" (distinct from the
      # empty string's "0:"), fields joined with "|" for debuggability only —
      # the length prefixes alone carry the structure.
      def digest(*fields)
        encoded = fields.map { |field| field.nil? ? "~" : "#{field.bytesize}:#{field}" }
        Digest::SHA256.hexdigest(encoded.join("|"))
      end
    end
  end
end
