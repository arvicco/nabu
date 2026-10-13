# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # The Bosworth-Toller → ASPR crosswalk (P123-1): B-T's <references>
    # blocks cite the Old English poems by Grein's sigla ("Gen. 375",
    # "B. 2575", "Cri. 1234") and the Paris Psalter by Thorpe's psalm/verse
    # ("Ps. Th. 103, 6"); this module resolves the subset whose numbering
    # the census PROVED to coincide with the held ASPR edition
    # (urn:nabu:aspr:<Cameron id>, passages = printed ASPR line numbers),
    # and carries everything else verbatim (cts_work nil) — the MwSigla
    # house pattern: resolve or carry, never guess.
    #
    # == The census (2026-10-13, the full 62,815-entry dump, read-only)
    #
    # 47,470 entries carry <references>; 200,798 reference units (a <ref>
    # element, or a ;-segment of an untagged block). Each candidate siglum
    # was validated EMPIRICALLY: for every reference sitting in an <ex>
    # beside its <oe> quotation, the quotation's words were looked up in
    # the ASPR line the reference names (window N-1..N+1) and anywhere in
    # the poem. "exact/located" below = quotations found AT the cited line
    # over those found anywhere in the poem (the located denominator
    # strips B-T's normalized spellings that no line matches at all).
    #
    # - passage grain where exact/located >= ~85%; where Grein's numbering
    #   drifts from Krapp-Dobbie's inside a poem the census found the
    #   boundary, and lines past it fall back to DOCUMENT grain (the poem
    #   itself — an honest claim, the line would not be);
    # - document grain where the numbering never matched (Guthlac +26..+30
    #   throughout, Solomon and Saturn, the Rune Poem, Maxims I);
    # - unresolved (verbatim): the Riddles (Grein's numbering ≠ Krapp-
    #   Dobbie's — KD = Grein-1 for most, then drifting; a concordance
    #   would be hand-built inference), Thorpe's page-cited editions
    #   (Cd./Exon./Th.), Kemble's and Thorpe's half-line Beowulf/Andreas/
    #   Elene numbering, every prose text, and the prose psalms 1-50.
    #
    # Predicted live: see the census comment on POEMS for per-siglum
    # counts; totals in the P123-1 report.
    module BosworthAsprRefs
      # One held poem: its ASPR document urn and the last line number the
      # census validated at passage grain (0 = document grain only).
      Poem = Data.define(:urn, :passage_through)

      ALL_LINES = 1_000_000

      def self.poem(cameron, through = ALL_LINES)
        Poem.new(urn: "urn:nabu:aspr:#{cameron}", passage_through: through)
      end

      # Single-number poem sigla ("Gen. 375"): siglum => Poem. Comments:
      # exact/located from the census (see module note).
      POEMS = {
        "Gen." => poem("A1.1", 2150),  # 700/903 overall; exact through ~2150, then +2/+3
        "Exod." => poem("A1.2"),       # 196/220
        "Dan." => poem("A1.3"),        # 159/179
        "Sat." => poem("A1.4", 230),   # 98/178; exact through ~230, then -2
        "An." => poem("A2.1", 750),    # 211/502; exact through ~750, then -2
        "Ap." => poem("A2.2"),         # 9/9   Fates of the Apostles
        "Kr." => poem("A2.5"),         # 37/41 Dream of the Rood
        "El." => poem("A2.6", 800),    # 232/287; exact through ~800, then -1
        "Cri." => poem("A3.1", 780),   # 390/477; exact through ~780, then -1
        "Gú." => poem("A3.2", 0),      # 0/382 — Grein runs +26..+30: document grain
        "Az." => poem("A3.3"),         # 24/26
        "Ph." => poem("A3.4"),         # 179/199
        "Jul." => poem("A3.5"),        # 190/202
        "Wand." => poem("A3.6"),       # 36/38
        "Crä." => poem("A3.7"),        # 30/33 Gifts of Men
        "Seef." => poem("A3.9"),       # 39/39
        "Mód." => poem("A3.10"),       # 26/26 Vainglory
        "Wíd." => poem("A3.11"),       # 18/18
        "Vy." => poem("A3.12"),        # 40/43 Fortunes of Men
        "Gn. Ex." => poem("A3.13", 0), # 70/91, drifting -1/-2: document grain
        "Reim." => poem("A3.15"),      # 16/16
        "Pa." => poem("A3.16"),        # 21/22 Panther
        "Wal." => poem("A3.17"),       # 27/28 Whale
        "Deór." => poem("A3.20"),      # 7/8
        "Dóm." => poem("A3.24"),       # 25/28 Judgment Day I
        "Hö." => poem("A3.26"),        # 25/29 Descent into Hell
        "B." => poem("A4.1"),          # 1,075/1,240 Beowulf (context-gated, see #beowulf_context?)
        "Jud." => poem("A4.2"),        # 82/94 Judith
        "Fin." => poem("A7"),          # 9/9
        "By." => poem("A9"),           # 94/99 Maldon
        "Æðelst." => poem("A10.1"),    # 15/16 Brunanburh
        "Rún." => poem("A12", 0),      # 0/11 — numbering differs: document grain
        "Sal." => poem("A13", 0),      # 6/132 — numbering differs: document grain
        "Men." => poem("A14"),         # 48/54
        "Gn. C." => poem("A15")        # 26/26 Maxims II
      }.transform_keys { |siglum| Nabu::Normalize.nfc(siglum) }.freeze

      # "Ps. Th. <psalm>, <verse>": the metrical Paris Psalter is held as
      # one ASPR document per psalm (A5.51 … A5.150; 541/639 quotations
      # located in the cited psalm). ASPR numbers metrical LINES, not
      # verses, so the verse cannot be honestly placed: document grain.
      # Psalms 1-50 are the prose psalter — not ASPR (101 such refs).
      PSALTER = "Ps. Th."
      METRICAL_PSALMS = (51..150)

      # "Met. <meter>, <line>": the Meters of Boethius, one ASPR document
      # per meter (A6.1 … A6.31), line-numbered as Grein numbers them —
      # 276/290 exact: passage grain.
      METERS = "Met."
      METER_NUMBERS = (1..31)

      # The B. siglum is Beowulf only beside Beowulf: B-T pairs it with
      # Thorpe's numbering ("Beo. Th. 1555; B. 775" — 2,911 bare "B. N"
      # segments follow a Beo. siglum), opens a block with it (736), or
      # continues a B. run (383); after another siglum ("Mone p. 398;
      # B. 3231" — the Mone glosses) it is not Beowulf.
      BEOWULF_COMPANIONS = %w[Beo. Bec. B.].freeze

      SINGLE = /\A(?<siglum>\D+?)\s*(?<n>\d+)\z/
      PAIR = /\A(?<siglum>\D+?)\s*(?<a>\d+)\s*,\s*(?<b>\d+)\z/

      module_function

      # One DictionaryCitation per reference unit of every <references>
      # block in the parsed body +fragment+: a <ref> element, or — in an
      # untagged block — each ;-segment of its text. Label/urn_raw are the
      # unit verbatim (whitespace collapsed, NFC); cts_work/citation are
      # the first resolvable segment's ASPR target, else nil.
      def citations(fragment)
        fragment.xpath(".//references").flat_map do |block|
          state = { previous: nil }
          units(block).map { |unit| citation(unit, state) }
        end
      end

      def units(block)
        refs = block.xpath(".//ref")
        texts = refs.empty? ? collapse(block.text).split(";") : refs.map(&:text)
        texts.map { |text| Nabu::Normalize.nfc(collapse(text)) }.reject(&:empty?)
      end

      def citation(unit, state)
        cts_work, cite = nil
        unit.split(/[;:]/).each do |raw|
          segment = raw.strip.sub(/[\s.,]+\z/, "")
          next if segment.empty?

          target = resolve(segment, state[:previous])
          cts_work, cite = target if target && cts_work.nil?
          siglum = segment[/\A\D+?(?=\s*\d|\z)/].to_s.strip
          state[:previous] = siglum unless siglum.empty?
        end
        Nabu::DictionaryCitation.new(urn_raw: unit, cts_work: cts_work, citation: cite, label: unit)
      end

      # [cts_work, citation] for one segment, or nil. +previous+ is the
      # last siglum seen in the block (the B. gate).
      def resolve(segment, previous)
        if (match = PAIR.match(segment))
          pair(match[:siglum].strip, match[:a].to_i, match[:b].to_i)
        elsif (match = SINGLE.match(segment))
          single(match[:siglum].strip, match[:n].to_i, previous)
        end
      end

      def single(siglum, line, previous)
        poem = POEMS[siglum]
        return nil if poem.nil? || line < 1
        return nil if siglum == "B." && !beowulf_context?(previous)

        [poem.urn, line <= poem.passage_through ? line.to_s : nil]
      end

      def pair(siglum, major, minor)
        case siglum
        when PSALTER
          ["urn:nabu:aspr:A5.#{major}", nil] if METRICAL_PSALMS.cover?(major)
        when METERS
          ["urn:nabu:aspr:A6.#{major}", minor.to_s] if METER_NUMBERS.cover?(major) && minor >= 1
        end
      end

      def beowulf_context?(previous)
        previous.nil? || BEOWULF_COMPANIONS.any? { |companion| previous.start_with?(companion) }
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
