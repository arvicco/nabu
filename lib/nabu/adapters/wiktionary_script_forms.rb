# frozen_string_literal: true

require_relative "wiktionary_kaikki"

module Nabu
  module Adapters
    # The Han-derived vernacular scripts on the kaikki family (P156-7): chữ
    # Nôm (Vietnamese), Sawndip (Zhuang) and Nôm Tày, three scripts whose
    # Wiktionary data sits in record fields the shared wiktionary-jsonl
    # parser does not read. A parser SUBCLASS here carries them; the shared
    # parser and base stay byte-identical (the wiktionary-ar stance: no
    # other kaikki shelf's derivation stamp moves).
    #
    # == The two upstream shapes (census 2026-11-04, the three extracts)
    #
    # - READINGS — `related` items (record level or sense level) tagged
    #   `nom-reading` / `han-viet-reading`: the quốc ngữ readings of a
    #   Vietnamese character record (馬 → ngựa, mã, mựa …). Vietnamese only:
    #   11,299 rows, all on character records save 5.
    # - SCRIPT FORMS — `forms` items carrying a script tag the shelf
    #   declares (SCRIPT_FORMS): the Han-script spellings of a word (chó →
    #   㹥 𤝹 …, tag `CJK`; Zhuang de → 他 𬿇 …, tag `Sawndip`) and, on
    #   older Vietnamese character records, their readings (犭 → khuyển,
    #   tag `Hán-Nôm`).
    #
    # == How they land
    #
    # One body line per kind, after the family body, labels from the
    # shelf ("Nôm readings: ngựa, mã" / "Sawndip forms: 他, 𬿇"); the
    # values verbatim, upstream order, repeats once. And one crossref per
    # value (kind = the shelf's kind name, target = the value), so the
    # loader joins a reading to the same shelf's quốc ngữ headword and a
    # spelling to the character record, where exactly one matches.
    # Nothing else of the family moves: the parser runs with the family's
    # reflexes + etymons, and the crossrefs hook carries ONLY these
    # typed pointers (the generic synonyms/related lists stay off, as on
    # every other per-language shelf).
    #
    # == The parse rule: empty stubs skip by rule
    #
    # A record is an EMPTY STUB when it has no gloss, no reading, no
    # script form and no etymology text — a bare "(no-gloss)" body with
    # nothing to say. Those are skipped by rule and censused in
    # discovery_skips (the wiktionary-ar precedent, narrowed). A glossless
    # record that carries readings or script forms is KEPT: those are the
    # very Nôm data the shelf exists for (5,346 of the Vietnamese character
    # records are glossless with readings only). A glossless record with
    # etymology text alone is kept too ("Sino-Vietnamese word from 充").
    # Skipping happens after the id mint, so the surviving ids are the
    # ids an unfiltered parse mints.
    class WiktionaryScriptFormsParser < WiktionaryJsonlParser
      # The relation tags carrying readings => [body label, crossref kind].
      READING_RELATIONS = {
        "han-viet-reading" => ["Hán-Việt readings", "han-viet-reading"],
        "nom-reading" => ["Nôm readings", "nom-reading"]
      }.freeze

      attr_reader :census

      # +script_forms+: the shelf's form tags => [body label, crossref kind].
      def initialize(language:, script_forms:)
        super(language: language, reflexes: true, etymons: true, crossrefs: true)
        @script_forms = script_forms
        @census = { stub: 0, kept: 0, glossless_script: 0, glossless_etymology: 0 }
      end

      private

      def build_entry(record, minted, path:, line_number:)
        entry = super
        shape = glossless_shape(entry, record)
        @census[shape] += 1 if shape
        return nil if shape == :stub

        @census[:kept] += 1
        entry
      end

      # nil for a glossed entry; else what keeps it (or :stub).
      def glossless_shape(entry, record)
        return nil unless entry.gloss.nil?
        return :glossless_script if script_values(record).any?
        return :glossless_etymology unless record["etymology_text"].to_s.strip.empty?

        :stub
      end

      def body_text(record)
        lines = script_values(record).map { |(label, _kind), values| "#{label}: #{values.join(', ')}" }
        Nabu::Normalize.nfc([super, *lines].reject(&:empty?).join("\n"))
      end

      def crossrefs(record)
        script_values(record).flat_map do |(_label, kind), values|
          values.map do |value|
            Nabu::DictionaryCrossref.new(kind: kind, label: "#{kind} #{value}", target: value,
                                         target_folded: reflex_fold(value, @language))
          end
        end
      end

      # { [label, kind] => [value, …] } in first-appearance order: the
      # reading relations first (record level, then each sense), then the
      # script-tagged forms.
      def script_values(record)
        out = Hash.new { |hash, key| hash[key] = [] }
        [record, *Array(record["senses"])].each do |level|
          Array(level["related"]).each { |item| collect(out, item, "word", READING_RELATIONS) }
        end
        Array(record["forms"]).each { |item| collect(out, item, "form", @script_forms) }
        out
      end

      def collect(out, item, field, table)
        return unless item.is_a?(Hash)

        value = Nabu::Normalize.nfc(item[field].to_s.strip)
        return if value.empty?

        Array(item["tags"]).each do |tag|
          key = table[tag]
          out[key] << value if key && !out[key].include?(value)
        end
      end
    end

    # The shelf base for the three script shelves: the WiktionaryKaikki
    # mold with the parser above. A subclass declares the WiktionaryKaikki
    # constants plus SCRIPT_FORMS (form tag => [body label, crossref kind]).
    class WiktionaryScriptShelf < WiktionaryKaikki
      SCRIPT_FORMS = {}.freeze

      # The record-grain census of the last parse on this instance (sync
      # calls this right after its load). Without a parse it says so.
      def discovery_skips(_workdir)
        census = @census or
          return DiscoverySkips.new(notes: ["record-grain census rides the parse — none ran on this instance"])

        DiscoverySkips.new(
          skipped_by_rule: census[:stub],
          notes: ["#{census[:stub]} empty stub(s) skipped by rule — no gloss, no reading or script form, " \
                  "no etymology; #{census[:kept]} entries kept (#{census[:glossless_script]} glossless kept " \
                  "for their readings/script forms, #{census[:glossless_etymology]} for their etymology)"]
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: self.class::DICTIONARY_SLUG, language: self.class::LANGUAGE,
          title: self.class::TITLE, canonical_path: document_ref.path
        )
        parser = WiktionaryScriptFormsParser.new(language: self.class::LANGUAGE,
                                                 script_forms: self.class::SCRIPT_FORMS)
        parser.entries(document_ref.path).each { |entry| document << entry }
        @census = parser.census
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{manifest.id}: #{document_ref.id}: #{e.message}"
      end
    end
  end
end
