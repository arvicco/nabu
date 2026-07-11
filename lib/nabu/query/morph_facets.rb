# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module Query
    # Morphology facets (P13-6): the `--morph case=dat,number=pl` filter that
    # rides on top of lemma search. A tiny query language (comma-joined
    # key=value pairs, ANDed) matched against the per-token morphology already
    # stored in annotations_json — no new index, no re-parse of canonical.
    #
    # == One façade over three tagsets (the vocabulary verdict)
    #
    # The gold shelves speak three morphology dialects, and this module folds
    # the two that HAVE inflectional morphology into ONE query vocabulary — the
    # Universal Dependencies feature names (case/number/gender/person/tense/
    # mood/voice/degree, values Nom/Plur/Aor…), because UD is (a) a documented
    # public standard a user can look up, and (b) already the STORED form for
    # the CoNLL-U family, so that family needs zero translation:
    #
    # - CoNLL-U / UD (grc-perseus, got, …): the token's `feats` string is
    #   `Case=Dat|Number=Plur|…` verbatim. Parsed as-is (lowercased). Any UD
    #   feature key is therefore queryable, not just the ones PROIEL decodes.
    # - PROIEL / TOROT (chu, orv, PROIEL grc/lat): the token's `morphology` is
    #   a 10-position positional tag (`-p---mgpwi` = plural masc genitive
    #   positive). DECODED here, position by position, into the SAME UD feature
    #   names. The decode table is the bounded, fiddly bit the design note flags
    #   — but it is a fixed 10×~8 code map, not open-ended.
    # - ORACC (akk, sux): tokens carry a NER-flavoured `pos` (N/PN/GN/DN/V…) and
    #   NO inflectional morphology (upstream `morph`/`base` is an un-ingested
    #   enrichment, conventions §6). So inflectional facets NEVER match ORACC —
    #   honest absence, not an error. A unified `pos` facet was deliberately
    #   left out of v1: ORACC's tagset is not UD upos, and welding a third
    #   incompatible pos scheme into the façade would be dishonest for the sake
    #   of one field. It is a clean follow-up.
    #
    # A query key that UD carries but the PROIEL decode does not (e.g. `aspect`,
    # `verbform`) simply matches UD passages and not PROIEL ones — the same
    # honest, documented cross-family divergence: the vocabulary is UD, and
    # where a treebank encodes a category UD's way (grc-perseus writes an aorist
    # as Aspect=Perf|Tense=Past, not Tense=Aor) the query must follow that
    # treebank's convention.
    module MorphFacets
      # A malformed --morph string (empty, no `=`, blank key/value). Caller-
      # fixable, so CLI/MCP surface it as a plain usage error.
      class Error < Nabu::Error; end

      # Query-value abbreviations a user is likely to type → the canonical UD
      # value (lowercased). Deliberately tiny: most UD values ARE what you'd
      # type lowercased (dat, gen, aor, opt, masc, act), so only the number
      # abbreviations genuinely need help.
      VALUE_ALIASES = {
        "sg" => "sing", "pl" => "plur", "du" => "dual"
      }.freeze

      # PROIEL positional morphology decode, position (0-based) → [UD facet key,
      # {code => UD value}]. Ten positions in order: person, number, tense,
      # mood, voice, gender, case, degree, strength, inflection. The last two
      # (Germanic strong/weak; inflecting flag) have no clean UD facet and are
      # intentionally left undecoded — absence over a wrong mapping.
      PROIEL_FIELDS = [
        ["person", { "1" => "1", "2" => "2", "3" => "3" }],
        ["number", { "s" => "sing", "d" => "dual", "p" => "plur" }],
        ["tense",  { "p" => "pres", "i" => "impf", "a" => "aor", "r" => "perf",
                     "l" => "plup", "f" => "fut", "t" => "futperf", "u" => "past", "s" => "res" }],
        ["mood",   { "i" => "ind", "s" => "sub", "m" => "imp", "o" => "opt",
                     "n" => "inf", "p" => "part", "d" => "ger", "g" => "gdv", "u" => "sup" }],
        ["voice",  { "a" => "act", "m" => "mid", "p" => "pass", "e" => "mp", "d" => "dep" }],
        ["gender", { "m" => "masc", "f" => "fem", "n" => "neut" }],
        ["case",   { "n" => "nom", "a" => "acc", "g" => "gen", "d" => "dat",
                     "b" => "abl", "v" => "voc", "l" => "loc", "i" => "ins" }],
        ["degree", { "p" => "pos", "c" => "cmp", "s" => "sup" }]
      ].freeze

      # Canonical order for rendering a token's decoded features as evidence
      # (keys outside the list sort last, alphabetically stable enough).
      DISPLAY_ORDER = %w[person number gender case tense mood voice aspect degree
                         verbform polarity prontype definite].freeze

      module_function

      # Parse "case=dat,number=pl" into [["case", "dat"], ["number", "plur"]] —
      # canonical (lowercased, aliases resolved), order preserved. Raises
      # MorphFacets::Error on anything malformed so the surfaces can report it.
      def parse(string)
        facets = string.to_s.split(",").filter_map do |chunk|
          chunk = chunk.strip
          next if chunk.empty?

          key, value = chunk.split("=", 2)
          key = key.to_s.strip.downcase
          value = value.to_s.strip.downcase
          if key.empty? || value.empty?
            raise Error, "malformed morph facet #{chunk.inspect} — expected key=value, e.g. case=dat"
          end

          [key, VALUE_ALIASES.fetch(value, value)]
        end
        raise Error, "empty --morph filter — give at least one facet, e.g. case=dat,number=pl" if facets.empty?

        facets
      end

      # Does +token+ satisfy every facet? A token with no decodable morphology
      # (ORACC, or a UD/PROIEL token whose features are all blank) matches
      # nothing — honest absence.
      def match?(token, facets)
        features = features(token)
        return false if features.empty?

        facets.all? { |key, value| features[key] == value }
      end

      # A token's morphology normalized to the UD facet vocabulary (see class
      # note). {} for ORACC and for featureless tokens.
      def features(token)
        return {} unless token.is_a?(Hash)

        if (morphology = token["morphology"])
          proiel_features(morphology)
        elsif (feats = token["feats"])
          ud_features(feats)
        else
          {}
        end
      end

      # Render a token's decoded features as `case=dat|number=plur|…` in a
      # readable category order — the per-hit morph evidence.
      def describe(token)
        features(token)
          .sort_by { |key, _| [DISPLAY_ORDER.index(key) || DISPLAY_ORDER.size, key] }
          .map { |key, value| "#{key}=#{value}" }
          .join("|")
      end

      # UD `feats`: "Case=Dat|Number=Plur" → {"case"=>"dat","number"=>"plur"}.
      def ud_features(feats)
        feats.to_s.split("|").each_with_object({}) do |pair, out|
          key, value = pair.split("=", 2)
          next if key.nil? || value.nil?

          out[key.strip.downcase] = value.strip.downcase
        end
      end

      # PROIEL `morphology`: positional string → UD-named facet hash.
      def proiel_features(morphology)
        chars = morphology.to_s.chars
        out = {}
        PROIEL_FIELDS.each_with_index do |(key, codes), index|
          code = chars[index]
          next if code.nil? || code == "-"

          value = codes[code]
          out[key] = value if value
        end
        out
      end
    end
  end
end
