# frozen_string_literal: true

module Nabu
  # The language desk reference (P18-4, rehomed by P19-1) — the merged read
  # over the per-language data, all of it DERIVED now:
  #
  # - RECORDS (catalog, migration 014): the canonical/local-language dossier
  #   shelf's index — curated name/family/context lanes, front-matter extras
  #   (period, scripts), and the provenance-headed accretion sections
  #   (witness:<slug>, iecor). One row per (code, kind), replaced from the
  #   dossier files at every local-language sync/rebuild. The AUTHORED
  #   knowledge itself lives in the dossier FILES (architecture §16) — the
  #   catalog only indexes it, which is what the P18-4 ledger layer broke and
  #   this read repairs.
  # - CENSUS (catalog, migration 011): the language_names census — what
  #   kaikki's descendants nodes call each lang_code, counted raw per
  #   dictionary by DictionaryLoader. Reduced at read time: plausibility
  #   filter, then the mode over the summed counts.
  # - NOTES (ledger, ledger migration 004 — TRANSITIONAL): the retiring
  #   P18-4 accumulated layer. Read as the per-(code, kind) FALLBACK wherever
  #   no catalog record exists, so a library whose owner has not yet fired
  #   the dossier export (`nabu language --export-dossiers` + `nabu sync
  #   local-language`) serves exactly what it served before. A later packet
  #   drops the table once parity is verified; this fallback goes with it.
  #
  # Every handle is optional and every table guarded (a catalog before 011 or
  # 014, a ledger before 004, or no db at all reads as "no data" — the honest
  # degradation every read surface here practices).
  class Languages
    NOTE_KINDS = %w[name family context].freeze

    # ISO 639-2 kept TWO codes for twenty languages — a bibliographic (B)
    # and a terminological (T) spelling — and upstream corpora pick either
    # (owner report 2026-07-18: aes minted German "ger", tla-hf "deu").
    # Queries accept both, fold-both-sides style: every user-facing --lang /
    # --parallel filter expands through .code_variants. STORED codes stay
    # whatever the adapter minted — this is query-side equivalence, never a
    # migration.
    ISO_639_2_BT_PAIRS = [
      %w[alb sqi], %w[arm hye], %w[baq eus], %w[bur mya], %w[chi zho],
      %w[cze ces], %w[dut nld], %w[fre fra], %w[geo kat], %w[ger deu],
      %w[gre ell], %w[ice isl], %w[mac mkd], %w[mao mri], %w[may msa],
      %w[per fas], %w[rum ron], %w[slo slk], %w[tib bod], %w[wel cym]
    ].freeze

    # The pairs as a code → full-equivalence-set map.
    CODE_VARIANTS = ISO_639_2_BT_PAIRS.each_with_object({}) do |pair, map|
      pair.each { |code| map[code] = pair }
    end.freeze

    # Common ISO 639-1 two-letter spellings for languages the catalog hosts
    # (typing convenience; the 639-3 code is the resolution target).
    ISO_639_1 = {
      "de" => "deu", "en" => "eng", "fr" => "fra", "it" => "ita",
      "la" => "lat", "el" => "ell", "nl" => "nld", "cs" => "ces",
      "cy" => "cym", "is" => "isl", "sq" => "sqi", "eu" => "eus",
      "fa" => "fas", "ro" => "ron", "sk" => "slk", "mk" => "mkd",
      "ka" => "kat", "hy" => "hye"
    }.freeze

    # Every code that means the same language as +code+ (itself included);
    # unknown codes pass through untouched, nil folds to []. Filters use the
    # returned array in their WHERE so either spelling lands.
    def self.code_variants(code)
      return [] if code.nil?

      canonical = code.to_s.downcase
      canonical = ISO_639_1.fetch(canonical, canonical)
      CODE_VARIANTS.fetch(canonical, [canonical])
    end

    Family = Data.define(:code, :name, :context)

    def initialize(catalog: nil, ledger: nil)
      @catalog = catalog
      @ledger = ledger
    end

    # Curated name > census mode > nil.
    def name(code)
      lane(code, "name") || census_name(code)
    end

    def context(code) = lane(code, "context")
    def family(code) = lane(code, "family")

    # P18-6: the per-source witness notes for a code — what each SOURCE says
    # about the language stage it carries (kind "witness:<slug>", one lane
    # per source so witnesses never supersede each other or the curated
    # "context"). Returns { source-slug => body }, kind order.
    def witnesses(code)
      lanes(code) { |dataset| dataset.where(Sequel.like(:kind, "witness:%")) }
        .transform_keys { |kind| kind.delete_prefix("witness:") }
    end

    # P18-5: the accretion kinds beyond the curated three — programmatic
    # writers ("iecor") and dossier front-matter extras (period, scripts)
    # file under their own kind, so they can never supersede curated
    # name/family/context. Kinds sorted (deterministic card order).
    def extra_notes(code)
      lanes(code) { |dataset| dataset.exclude(kind: NOTE_KINDS).exclude(Sequel.like(:kind, "witness:%")) }
    end

    def curated?(code)
      (records? && !@catalog[:language_records].where(lang_code: code.to_s).empty?) ||
        (notes? && !@ledger[:language_notes].where(lang_code: code.to_s).empty?)
    end

    # The family fallback for a hyphenated etymology code: "zle-ort" looks
    # up the lanes filed under "zle" (Wiktionary's own family-code
    # namespace). nil when the prefix carries nothing — no guessing.
    def family_fallback(code)
      prefix = code.to_s.split("-").first
      return nil if prefix.nil? || prefix.empty? || prefix == code.to_s

      fam_name = lane(prefix, "name")
      fam_context = lane(prefix, "context")
      return nil unless fam_name || fam_context

      Family.new(code: prefix, name: fam_name, context: fam_context)
    end

    # -- census (derived) ----------------------------------------------------------

    # The read-side reduction of the raw census: sum occurrences across
    # dictionaries per (code, name), drop implausible names, take the mode.
    def census_name(code)
      return nil unless census?

      rows = @catalog[:language_names]
             .where(lang_code: code.to_s)
             .select_group(:name)
             .select_append { sum(:occurrences).as(:total) }
             .all
      best = rows.select { |row| self.class.plausible_name?(row[:name]) }
                 .max_by { |row| row[:total] }
      best && best[:name]
    end

    # The plausibility filter (census 2026-07-14 over the eight live kaikki
    # extracts): "unknown" placeholder nodes, script wrapper nodes ("Old
    # Cyrillic script" outnumbers "Old Church Slavonic" under cu), and
    # free-text fragments (") dialect words", "→ Baltic German") — all real
    # upstream noise the mode must not crown. Filtering happens at READ so a
    # rule change never needs a reparse.
    def self.plausible_name?(name)
      text = name.to_s
      return false if text.empty? || text == "unknown"
      return false if text.match?(/script\z/i)

      text.match?(/\A\p{Lu}/)
    end

    private

    # One (code, kind) lane: the catalog record wins; the transitional
    # ledger note answers only where no record exists.
    def lane(code, kind)
      record(code, kind) || note(code, kind)
    end

    # A kind → body map for +code+ over both layers, records winning per
    # kind. +scope+ narrows both datasets identically (witness lanes,
    # extra kinds).
    def lanes(code)
      merged = {}
      if notes?
        yield(@ledger[:language_notes].where(lang_code: code.to_s))
          .order(:kind, :id)
          .each { |row| merged[row[:kind]] = row[:body] } # duplicate kinds: the latest id wins
      end
      if records?
        yield(@catalog[:language_records].where(lang_code: code.to_s))
          .order(:kind)
          .each { |row| merged[row[:kind]] = row[:body] }
      end
      merged.sort.to_h
    end

    def record(code, kind)
      return nil unless records?

      @catalog[:language_records].where(lang_code: code.to_s, kind: kind).get(:body)
    end

    def note(code, kind)
      return nil unless notes?

      @ledger[:language_notes]
        .where(lang_code: code.to_s, kind: kind)
        .order(Sequel.desc(:id))
        .get(:body)
    end

    def records?
      !@catalog.nil? && @catalog.table_exists?(:language_records)
    end

    def census?
      !@catalog.nil? && @catalog.table_exists?(:language_names)
    end

    def notes?
      !@ledger.nil? && @ledger.table_exists?(:language_notes)
    end
  end
end
