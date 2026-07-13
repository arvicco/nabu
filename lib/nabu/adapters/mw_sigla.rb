# frozen_string_literal: true

module Nabu
  module Adapters
    # The curated MW sigla → GRETIL crosswalk (P17-4; mw-survey §3). MW cites
    # literature through tagged <ls> elements whose leading siglum comes from
    # the dictionary's own works-and-authors key (871 rows upstream); this
    # module is the deliberately SMALL curated slice of it — the works the
    # GRETIL shelf actually holds (filenames verified against the
    # mmehner/gretil-corpus-tei mirror listing, 2026-07-13) plus MW's
    # lexicographic authority labels. Everything else classifies :unheld and
    # is REPORTED per-siglum at sync, never faked (the LSJ honest-miss
    # precedent).
    #
    # == The four tiers (survey §3 "honest projection")
    #
    #   :passage    held work whose GRETIL parse is verse-grained AND whose
    #               MW citation tail normalizes onto the edition's citation
    #               format (roman → arabic + per-work zero-pad template;
    #               "RV. v, 86, 5" → 5.086.05, resolved at QUERY time with
    #               pada-suffix probing → …:5.086.05a — end-to-end verified
    #               in the survey). A held work whose tail does NOT parse
    #               falls back to :document, honestly.
    #   :document   held work at document grain only — single-blob GRETIL
    #               parses (Mn., Pāṇ.), edition-numbering mismatches
    #               (Hariv.), prose/drama (Kathās., Śak.), or works whose
    #               passage grain is unverified against the live catalog.
    #   :authority  MW's lexicographer/author labels (L., W., Sāy., ib. …) —
    #               never passage-resolvable BY NATURE; excluded from the
    #               resolution denominator, rendered as labels.
    #   :unheld     everything else — a GRETIL-coverage fact (MBh., Vedic
    #               prose, Suśruta), not a parser deficiency.
    #
    # Passage-grain formats beyond RV. (which the survey verified end to
    # end) encode the survey's live-catalog census shapes; a wrong template
    # yields an honest query-time miss, never an invented link.
    # DEFERRED-TO-REVIEW (2026-07-13): re-verifying the non-RV templates
    # against the live catalog (the packet ran without live-db access).
    module MwSigla
      # One held work: the GRETIL document urn (urn:nabu:gretil:<file-stem>)
      # and the sprintf template its passage citations follow — nil template
      # means document grain.
      Work = Data.define(:urn, :format)

      def self.work(stem, format = nil)
        Work.new(urn: "urn:nabu:gretil:#{stem}", format: format)
      end

      WORKS = {
        # -- passage grain (survey §3 verse-grain census) -------------------
        "RV." => work("sa_Rgveda-edAufrecht", "%d.%03d.%02d"),
        "BhP." => work("sa_bhAgavatapurANa", "%02d.%02d.%03d"),
        "R." => work("sa_rAmAyaNa", "%d.%03d.%03d"),
        "Ragh." => work("sa_kAlidAsa-raghuvaMza", "%d.%d"),
        "Yājñ." => work("sa_yAjJavalkyasmRti", "%d.%d"),
        "Kum." => work("sa_kAlidAsa-kumArasaMbhava", "%d.%d"),
        "Sāh." => work("sa_vizvanAthakavirAja-sAhityadarpaNa", "%d.%d"),
        "MārkP." => work("sa_mArkaNDeyapurANa1-93", "%d.%d"),
        "VP." => work("sa_viSNupurANa", "%d,%d.%d"),
        "Daś." => work("sa_daNDin-dazakumAracarita", "%d,%d.%d"),
        # -- document grain --------------------------------------------------
        "Mn." => work("sa_manusmRti"),                       # single-blob parse
        "Pāṇ." => work("sa_pANini-aSTAdhyAyI"),              # single-blob parse
        "Hariv." => work("sa_harivaMza"),                    # crit.-ed. numbering ≠ MW's Calcutta
        "Kathās." => work("sa_somadeva-kathAsaritsAgara"),
        "Pañcat." => work("sa_viSNuzarman-paJcatantra"),
        "Hit." => work("sa_nArAyaNa-hitopadeza"),
        "Śak." => work("sa_kAlidAsa-abhijJAnazakuntala"),
        "VarBṛS." => work("sa_varAhamihira-bRhatsaMhitA"),
        "Bhaṭṭ." => work("sa_bhaTTi-rAvaNavadha"),
        "Megh." => work("sa_kAlidAsa-meghadUta"),
        "Kir." => work("sa_bhAravi-kirAtArjunIya"),
        "Śiś." => work("sa_mAgha-zizupAlavadha"),
        "Nir." => work("sa_yAska-nirukta"),
        "Gīt." => work("sa_jayadeva-gItagovinda")
      }.freeze

      # MW's lexicographic authority labels (survey §3): citations of
      # lexicographers/authorities, not of passages.
      AUTHORITY = %w[L. W. MW. Cat. ib. Kāv. Buddh. Pur. Br. Gal. Sāy.].freeze

      # Known sigla, longest first, so "RV." wins over "R." and "MārkP."
      # over "Mn."-style shorter keys.
      KNOWN = (WORKS.keys + AUTHORITY).sort_by { |siglum| -siglum.length }.freeze

      ROMAN = { "i" => 1, "v" => 5, "x" => 10, "l" => 50,
                "c" => 100, "d" => 500, "m" => 1000 }.freeze

      module_function

      # The leading siglum of a restored <ls> label: a known siglum at a
      # boundary wins (longest first); otherwise the leading token up to and
      # including its first "." (per-siglum aggregation for unheld sigla),
      # else the first whitespace token.
      def siglum_of(label)
        text = label.to_s.strip
        known = KNOWN.find do |siglum|
          text.start_with?(siglum) && (text.length == siglum.length || text[siglum.length] == " ")
        end
        return known if known

        head = text[/\A[^\s]*?\./] || text[/\A[^\s]+/]
        head.to_s.empty? ? nil : head
      end

      # Tier of a label: :passage / :document / :authority / :unheld.
      def classify(label)
        siglum = siglum_of(label)
        return :unheld if siglum.nil?
        return :authority if AUTHORITY.include?(siglum)

        held = WORKS[siglum]
        return :unheld if held.nil?

        held.format && normalize_citation(label, siglum, held.format) ? :passage : :document
      end

      # [cts_work, citation] for a restored label — the dictionary_citations
      # row shape. Held work: its document urn, plus the normalized dot
      # citation when the tail parses onto the work's template (else nil —
      # document grain). Authority/unheld: [nil, nil].
      def resolve(label)
        siglum = siglum_of(label)
        held = siglum && WORKS[siglum]
        return [nil, nil] if held.nil?

        [held.urn, held.format && normalize_citation(label, siglum, held.format)]
      end

      # "RV. v, 86, 5" → "5.086.05": strip the siglum, split the tail on
      # commas, read roman/arabic numerals, apply the work's template. nil —
      # an honest document-grain fallback — when any component is
      # non-numeric or the count does not match the template.
      def normalize_citation(label, siglum, format)
        tail = label.to_s.strip.delete_prefix(siglum).strip
        return nil if tail.empty?

        parts = tail.split(",").map { |part| numeral(part.strip) }
        return nil if parts.any?(&:nil?)
        return nil unless parts.length == format.scan("%").length

        Kernel.format(format, *parts)
      end

      def numeral(part)
        return part.to_i if part.match?(/\A\d+\z/)
        return nil unless part.match?(/\A[ivxlcdm]+\z/)

        roman_to_arabic(part)
      end

      def roman_to_arabic(roman)
        values = roman.chars.map { |ch| ROMAN.fetch(ch) }
        values.each_with_index.sum do |value, index|
          value < (values[(index + 1)..].max || 0) ? -value : value
        end
      end
    end
  end
end
