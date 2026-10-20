# frozen_string_literal: true

require "json"

require_relative "pts_concordance"

module Nabu
  module Adapters
    # The `bilara-json` parser family (P26-1): SuttaCentral's bilara-data
    # segment files — one flat, ORDERED JSON map of "<segment-id>": "text"
    # per document (root text and every translation share the same shape and
    # THE SAME segment ids, which is what makes `-en` siblings align by
    # suffix equality without stored links).
    #
    # == Citations (FROZEN)
    #
    # Segment ids ARE SuttaCentral's citation scheme ("mn1:1.1"). The
    # citation is the segment id minus the redundant "<stem>:" prefix
    # ("mn1:1.1" in file mn1 → "1.1"); RANGE-STEM files (dhp21-32,
    # sn23.23-33, pli-tv-bu-vb-as1-7 — 6,707 segments corpus-wide) carry
    # per-item prefixes that do NOT start with the stem, and there the FULL
    # segment id is the citation, colons intact ("dhp21:1") — upstream's own
    # ids either way, never re-minted. Passage urn = <doc-urn>:<citation>.
    #
    # == Rules (censused at fixture time, see the fixture README)
    #
    # - JSON object order is document order; sequence is the running index
    #   over the KEPT segments.
    # - Blank segments (14 corpus-wide, e.g. sn35.24:1.5) are layout
    #   artifacts, skipped by rule — a translation may still carry text at
    #   that id (the sibling asymmetry stays honest, one-sided).
    # - Edge whitespace is stripped (trailing spaces are segment-join
    #   artifacts); interior text is verbatim NFC, including pdhp's inline
    #   editorial pseudo-markup (<unclear>…) — canonical means canonical.
    # - Title = the heading block: the leading "0"/"0.x" segments of the
    #   file's FIRST item prefix, joined " — " ("Majjhima Nikāya 1 —
    #   Mūlapariyāyasutta"); stem when a file has no heading block.
    #
    # == Sidecar segment maps (variant / reference / comment)
    #
    # bilara-data's sidecar trees are the SAME flat segment-map shape keyed
    # by THE SAME segment ids: +sidecars+ maps an annotation key ("variants",
    # "refs", "comments") to one such file, and each passage whose segment
    # id the file keys with a non-blank string carries that string under the
    # key — edge whitespace stripped (the segment-join artifact, as on the
    # text) and NFC at this boundary, interior verbatim (inline <a href>
    # markup in comments included). Blank values mint no key; data keyed to
    # a skipped blank segment or to an id the root lacks has no passage to
    # land on — never re-homed onto a neighbour, but COUNTED per annotation
    # key in the document's metadata["sidecar_unjoined"] ({"refs" => 1};
    # absent when everything joined). No sidecars → the annotations stay {}
    # exactly as before.
    #
    # The "refs" string is also the PTS / VRI concordance: its page tokens
    # fold into a "pts" key list ("PTS.S.4.16") and its VRI tokens into
    # "vri", beside the verbatim string (Adapters::PtsConcordance; the
    # adapter passes the root book's +pts_siglum+).
    #
    # A malformed file, a non-map top level, a non-string segment, or a file
    # with zero non-blank segments is damage → Nabu::ParseError (quarantine);
    # the same holds for a malformed sidecar (its path named).
    class BilaraJsonParser
      # Same keyword family as ConlluParser#parse. +stem+ is the upstream
      # text uid (the filename stem before the first "_"); +license_override+
      # is the P10-4 per-document class (the pdhp BY-SA translation);
      # +sidecars+ is { annotation key => sidecar segment-map path };
      # +pts_siglum+ the PTS siglum of the root's book (PtsConcordance) —
      # nil folds no PTS page keys (VRI tokens need none).
      def parse(path, urn:, stem:, language:, metadata: {}, license_override: nil, sidecars: {}, pts_siglum: nil)
        segments = read_segments(path)
        kept = segments.reject { |_id, text| text.strip.empty? }
        raise ParseError, "#{path}: no non-blank segments" if kept.empty?

        annotations = sidecar_annotations(sidecars, pts_siglum: pts_siglum)
        unjoined = unjoined_census(annotations, kept, sidecars.keys)
        metadata = metadata.merge("sidecar_unjoined" => unjoined) unless unjoined.empty?

        document = Nabu::Document.new(
          urn: urn, language: language, title: title(segments, stem),
          canonical_path: path.to_s, metadata: metadata, license_override: license_override
        )
        kept.each_with_index do |(id, text), sequence|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{citation(id, stem)}", language: language,
            text: Normalize.nfc(text.strip), sequence: sequence, annotations: annotations.fetch(id, {})
          )
        end
        document
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      # segment id → { annotation key => stripped NFC string }, over every
      # sidecar file's non-blank values; a "refs" string also yields its
      # folded "pts" / "vri" concordance keys (PtsConcordance).
      def sidecar_annotations(sidecars, pts_siglum:)
        sidecars.each_with_object({}) do |(key, sidecar_path), by_segment|
          read_segments(sidecar_path).each do |id, value|
            stripped = value.strip
            next if stripped.empty?

            annotations = (by_segment[id] ||= {})
            annotations[key] = Normalize.nfc(stripped)
            annotations.merge!(PtsConcordance.split(annotations[key], siglum: pts_siglum)) if key == "refs"
          end
        end
      end

      # annotation key → count of non-blank sidecar values keyed to a segment
      # id with no passage (a skipped blank segment, or an id the root
      # lacks). Counted, never re-homed onto a neighbouring passage.
      # Only the sidecar keys count — the folded pts/vri keys ride a refs
      # value and are not separate upstream data.
      def unjoined_census(annotations, kept, sidecar_keys)
        annotations.each_with_object(Hash.new(0)) do |(id, by_key), census|
          next if kept.key?(id)

          (by_key.keys & sidecar_keys).each { |key| census[key] += 1 }
        end.sort.to_h
      end

      def read_segments(path)
        parsed = JSON.parse(File.read(path))
        unless parsed.is_a?(Hash) && parsed.each_value.all?(String)
          raise ParseError, "#{path}: not a flat segment map (object of string values)"
        end

        parsed
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed JSON: #{e.message}"
      end

      def citation(segment_id, stem)
        prefixed = segment_id.delete_prefix("#{stem}:")
        prefixed.empty? ? segment_id : prefixed
      end

      # The leading heading segments of the FIRST item prefix: ids whose
      # citation part is "0" or "0.x" ("mn1:0.1"; pdhp numbers from 0.0).
      # Values stripped and joined " — "; nil-safe fallback to the stem.
      def title(segments, stem)
        first_id = segments.each_key.first
        item = first_id.to_s[/\A[^:]*/]
        headings = segments.filter_map do |id, text|
          prefix, rest = id.split(":", 2)
          next nil unless prefix == item && rest&.match?(/\A0(\.|\z)/)

          stripped = text.strip
          stripped.empty? ? nil : stripped
        end
        headings.empty? ? stem : headings.join(" — ")
      end
    end
  end
end
