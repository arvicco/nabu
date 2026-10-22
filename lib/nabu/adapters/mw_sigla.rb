# frozen_string_literal: true

require "yaml"

module Nabu
  module Adapters
    # MW's citation sigla (P17-4; mw-survey §3), data-driven from
    # config/mw_sigla.yml. MW cites literature through tagged <ls> elements
    # whose leading siglum comes from the dictionary's own works-and-authors
    # key; the config carries that key in full (871 rows, CDSL's digitization
    # — KEY, #key_rows: what every siglum expands to) plus two judgment
    # layers over it, each row reasoned there: the crosswalk of works the
    # GRETIL shelf actually holds (WORKS — stem + citation template) and
    # MW's lexicographic authority labels (AUTHORITY). Everything else
    # classifies :unheld and is REPORTED per-siglum at sync, never faked
    # (the LSJ honest-miss precedent). Census over the full mw.xml
    # (2026-10-22): the key names the siglum of 328,050 of 328,060
    # citations (868 distinct sigla seen, 858 keyed); recognizing its
    # multi-word sigla whole moves 6 citations off a held/authority siglum
    # (Sāy. on AitBr. ×4, RV. AnuvAnukr., Hariv. (Langlois' transl.)), and
    # its edition-qualified variants of held works (R. (B.), Śak. (Pi.) …)
    # and "Yājñ., Sch." (the Mitākṣarā) are crosswalked at document grain.
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
    #   :document   held work at document grain only — edition-numbering mismatches
    #               (Hariv.), prose/drama (Kathās., Śak.), or works whose
    #               passage grain is unverified against the live catalog.
    #   :authority  MW's lexicographer/author labels (L., W., Sāy. …) and
    #               an "ib." with nothing earlier in its entry to inherit —
    #               never passage-resolvable BY NATURE; excluded from the
    #               resolution denominator, rendered as labels. A propagated
    #               "ib. (= X.)" classifies as X. does (document grain at
    #               best — see #inherit).
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

      # One row of MW's works-and-authors key: CDSL's row id, the expansion
      # and CDSL's type (Title, Author, Literary category, subtitle …).
      KeyRow = Data.define(:id, :siglum, :expansion, :type)

      CONFIG_PATH = File.expand_path("../../../config/mw_sigla.yml", __dir__)
      CONFIG = YAML.safe_load_file(CONFIG_PATH)

      # siglum => [KeyRow] (an array: six sigla carry two expansions upstream).
      KEY = CONFIG.fetch("key")
                  .map { |id, siglum, expansion, type| KeyRow.new(id:, siglum:, expansion:, type:) }
                  .group_by(&:siglum).transform_values(&:freeze).freeze

      WORKS = CONFIG.fetch("crosswalk").to_h do |siglum, held|
        [siglum, Work.new(urn: "urn:nabu:gretil:#{held.fetch('gretil')}", format: held["format"])]
      end.freeze

      AUTHORITY = CONFIG.fetch("authority").freeze

      # Every recognized siglum, indexed by its first whitespace token (the
      # label's own first token picks the candidates), longest first within
      # a token so "MBh. (ed. Bomb.)" wins over "MBh." and "Sāy. on AitBr."
      # over "Sāy." — the boundary rule then needs a space or the end.
      KNOWN = (KEY.keys + WORKS.keys + AUTHORITY).uniq
                                                 .group_by { |siglum| siglum[/\A\S+/] }
                                                 .transform_values { |list| list.sort_by { -_1.length }.freeze }
                                                 .freeze

      # MW's ibidem. The parser rewrites an "ib." it can propagate (an
      # earlier citation in the SAME entry) to "ib. (= <siglum>)" — the work
      # inherited, the print's "ib." kept in urn_raw — so every consumer of
      # the label (coverage, display) sees which work it means.
      IBID = "ib."
      INHERITED = /\Aib\..*? \(= (?<siglum>[^()]+)\)\z/

      ROMAN = { "i" => 1, "v" => 5, "x" => 10, "l" => 50,
                "c" => 100, "d" => 500, "m" => 1000 }.freeze

      module_function

      # The leading siglum of a restored <ls> label: a known siglum at a
      # boundary wins (longest first); otherwise the leading token up to and
      # including its first "." (per-siglum aggregation for unheld sigla),
      # else the first whitespace token.
      def siglum_of(label)
        text = label.to_s.strip
        inherited = text.match(INHERITED)
        return inherited[:siglum] if inherited

        known = KNOWN.fetch(text[/\A\S+/].to_s, []).find do |siglum|
          text.start_with?(siglum) && (text.length == siglum.length || text[siglum.length] == " ")
        end
        return known if known

        head = text[/\A[^\s]*?\./] || text[/\A[^\s]+/]
        head.to_s.empty? ? nil : head
      end

      # The key rows a siglum expands to ([] for a siglum outside MW's key).
      def key_rows(siglum) = KEY.fetch(siglum, [])

      # Tier of a label: :passage / :document / :authority / :unheld.
      def classify(label)
        siglum = siglum_of(label)
        return :unheld if siglum.nil?
        return :authority if AUTHORITY.include?(siglum)

        held = WORKS[siglum]
        return :unheld if held.nil?

        resolve(label).last ? :passage : :document
      end

      # The propagated form of an "ib." label: "ib. (= Pāṇ.)" — the inherited
      # work at document grain (MW's ib. names the same TEXT, not the same
      # passage). nil +previous+ (nothing earlier in the entry) leaves the
      # bare authority label.
      def inherit(label, previous)
        previous ? "#{label} (= #{previous})" : label
      end

      def ibid?(label) = label.to_s.strip.start_with?(IBID) && !inherited?(label)

      def inherited?(label) = label.to_s.strip.match?(INHERITED)

      # [cts_work, citation] for a restored label — the dictionary_citations
      # row shape. Held work: its document urn, plus the normalized dot
      # citation when the tail parses onto the work's template (else nil —
      # document grain). Authority/unheld: [nil, nil].
      def resolve(label)
        siglum = siglum_of(label)
        held = siglum && WORKS[siglum]
        return [nil, nil] if held.nil?

        return [held.urn, nil] if inherited?(label)

        [held.urn, held.format && normalize_citation(label, siglum, held.format)]
      end

      # "RV. v, 86, 5" → "5.086.05": strip the siglum, split the tail on
      # commas and spaces, read roman/arabic numerals, apply the work's
      # template. nil — an honest document-grain fallback — when any
      # component is non-numeric or the count does not match the template.
      # Spaces separate too because the @n restoration joins with a space
      # and upstream's @n sometimes stops before its comma (<ls n="Pāṇ. iv,
      # 3">5</ls> → "Pāṇ. iv, 3 5"); ONE sentence-final period rides inside
      # the <ls> on about a quarter of numbered citations ("Mn. viii, 120.")
      # and is dropped. Anything else non-numeric ("viii f.", "ii, 54; 55")
      # still falls back.
      def normalize_citation(label, siglum, format)
        tail = label.to_s.strip.delete_prefix(siglum).strip.delete_suffix(".")
        return nil if tail.empty?

        parts = tail.split(/[,\s]+/).reject(&:empty?).map { |part| numeral(part) }
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
