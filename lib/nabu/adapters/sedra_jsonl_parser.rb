# frozen_string_literal: true

require "json"
require "zlib"
require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # The `sedra-jsonl` parser family: the Sedra V data release (Beth
    # Mardutho's Syriac lexical database) as its own README describes it —
    # one gzip-compressed JSON Lines file per database table, one JSON
    # object per row, ids the permanent Sedra ids, every `<x>_id` column a
    # reference into the table it names (`lexeme_id` → lexemes, `kaylo_id`
    # → kaylos). FORMAT only: this class reads the tables and joins one
    # lexeme into one Nabu::DictionaryEntry; which tables are accepted, the
    # dictionary slug and the license live in the adapter.
    #
    # == The entry (one per lexeme)
    #
    # - entry_id: the lexeme id; key_raw and headword: the consonantal
    #   Syriac (`syriac`, the form unvocalized texts are written in);
    #   headword_folded: its search form.
    # - gloss: the first English gloss (sort_order, then id), else the
    #   first gloss in any language, its markup stripped.
    # - body: plain text — headword with its vocalization, the category
    #   and the root, the glosses grouped by language (prefix, meaning,
    #   postfix, notes before/after as the row places them), the
    #   etymologies, the word forms.
    # - reflexes: each etymology row naming a word as an UP edge (relation "derived" —
    #   upstream's word_origin states a source, never the mechanism) in
    #   the row's language: the language table's iso_code verbatim as
    #   lang_code, mapped onto a catalog code only where certain
    #   (CATALOG_LANGUAGES; the rest display-only). The 83 rows naming
    #   only a language ("from Greek", no word) ride the annotations and
    #   the body, never a reflex.
    # - annotations: the lexeme's structured claims verbatim — ids,
    #   transliterations, root, category ("pos"), verb class, flags,
    #   glosses, etymologies, the word forms with their morphology names.
    #
    # Gloss/note values carry HTML spans (1,359 of 67,692 meanings:
    # `<span class="selectableFont">ܕܰܐܝܟ</span> of what kind`): rendered
    # to their text, never kept as markup. All text NFC.
    class SedraJsonlParser
      # Sedra language iso_code → catalog language, where certain.
      CATALOG_LANGUAGES = {
        "grc" => "grc", "lat" => "lat", "akk" => "akk", "ara" => "ara", "san" => "san",
        "cop" => "cop", "pal" => "pal", "peo" => "peo", "syr" => "syc"
      }.freeze

      # The display order of the gloss languages in the body (the rest
      # follow by name).
      GLOSS_ORDER = %w[English French Arabic Latin Greek].freeze

      # The lexeme boolean columns that ride annotations as flag labels.
      FLAGS = { "is_idiom" => "idiom", "is_liturgical" => "liturgical", "is_grammatical" => "grammatical",
                "is_kthobonoyo" => "kthobonoyo", "is_merged" => "merged", "seyame" => "seyame" }.freeze

      attr_reader :dir

      def initialize(dir)
        @dir = dir
        @tables = {}
      end

      # Every row of +name+.jsonl.gz, in file order.
      def table(name)
        @tables[name] ||= begin
          path = File.join(dir, "#{name}.jsonl.gz")
          raise Nabu::ParseError, "#{path}: missing Sedra table" unless File.file?(path)

          SourceRead.utf8_lines(path, label: "sedra", gzip: true).each_with_index.map do |line, index|
            row(line, path: path, number: index + 1)
          end
        rescue Zlib::Error => e
          raise Nabu::ParseError, "#{path}: not gzip: #{e.message}"
        end
      end

      # { id => row } for a lookup table.
      def index(name)
        @indexes ||= {}
        @indexes[name] ||= table(name).to_h { |r| [r.fetch("id"), r] }
      end

      # { lexeme_id => [rows] } for a dependent table.
      def by_lexeme(name)
        @by_lexeme ||= {}
        @by_lexeme[name] ||= table(name).group_by { |r| r["lexeme_id"] }
      end

      # The lexeme rows that mint no entry: no consonantal headword at all
      # (censused: one, the empty Sedra III row 28521 with an empty word
      # form and no gloss).
      def headwordless
        table("lexemes").select { |lexeme| lexeme["syriac"].to_s.strip.empty? }
      end

      # One DictionaryEntry per lexeme with a headword, in lexeme-file order.
      def entries(language:)
        table("lexemes").filter_map do |lexeme|
          next if lexeme["syriac"].to_s.strip.empty?

          entry(lexeme, language: language)
        end
      end

      def self.plain(html)
        return nil if html.nil?

        text = html.include?("<") ? Nokogiri::HTML::DocumentFragment.parse(html).text : html
        text = Nabu::Normalize.nfc(text.gsub(/\s+/, " ").strip)
        # A value of only spaces and format controls (the no-break space,
        # the RLM some Arabic/French gloss cells hold) is absence; inside
        # real text the controls stay verbatim.
        text.gsub(/[\p{Z}\p{Cf}]/, "").empty? ? nil : text
      end

      private

      def row(line, path:, number:)
        JSON.parse(line)
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}:#{number}: malformed JSON row: #{e.message}"
      end

      def entry(lexeme, language:)
        headword = Nabu::Normalize.nfc(lexeme["syriac"].strip)
        glosses = gloss_rows(lexeme["id"])
        etymologies = etymology_rows(lexeme["id"])
        forms = form_rows(lexeme["id"])
        Nabu::DictionaryEntry.new(
          entry_id: lexeme.fetch("id").to_s, key_raw: headword, language: language,
          headword: headword, headword_folded: Nabu::Normalize.search_form(headword, language: language),
          gloss: (glosses.find { |g| g["language"] == "eng" } || glosses.first)&.fetch("text"),
          body: body(lexeme, headword, glosses, etymologies, forms),
          reflexes: etymologies.select { |e| e["word"] }.map { |e| reflex(e) },
          annotations: annotations(lexeme, glosses, etymologies, forms)
        )
      end

      def gloss_rows(lexeme_id)
        rows = by_lexeme("glosses").fetch(lexeme_id, []).sort_by { |g| [g["sort_order"].to_i, g["id"]] }
        rows.filter_map do |g|
          text = gloss_text(g)
          next if text.nil?

          language = index("languages")[g["language_id"]]
          { "id" => g["id"], "language" => language&.fetch("iso_code"), "language_name" => language&.fetch("name"),
            "text" => text, "source" => source_name(g["source_id"]),
            "verb_type" => g["verb_type"] }.compact
        end
      end

      def gloss_text(gloss)
        meaning = self.class.plain(gloss["meaning"])
        return nil if meaning.nil?

        core = [self.class.plain(gloss["prefix"]), meaning, self.class.plain(gloss["postfix"])].compact.join(" ")
        notes = self.class.plain(gloss["notes"])
        return core unless notes

        gloss["notes_position"] == "before" ? "#{notes} #{core}" : "#{core} #{notes}"
      end

      def etymology_rows(lexeme_id)
        rows = by_lexeme("etymologies").fetch(lexeme_id, []).sort_by { |e| [e["sort_order"].to_i, e["id"]] }
        rows.filter_map do |e|
          word = self.class.plain(e["source_word"])
          language = index("languages")[e["language_id"]]
          next if word.nil? && language.nil?

          { "id" => e["id"], "language" => language&.fetch("iso_code"), "language_name" => language&.fetch("name"),
            "word" => word, "meaning" => self.class.plain(e["meaning"]),
            "notes" => self.class.plain(e["notes"]) }.compact
        end
      end

      def form_rows(lexeme_id)
        by_lexeme("words").fetch(lexeme_id, []).sort_by { |w| w["id"] }.filter_map do |w|
          syriac = w["syriac"].to_s.strip
          next if syriac.empty?

          {
            "id" => w["id"], "syriac" => Nabu::Normalize.nfc(syriac),
            "vocalized_west" => nfc(w["syriac_vocalized_west"]), "vocalized_east" => nfc(w["syriac_vocalized_east"]),
            "translit_sedra3" => presence(w["translit_sedra3"]),
            "kaylo" => name_of("kaylos", w["kaylo_id"]), "tense" => name_of("tenses", w["tense_id"]),
            "person" => name_of("persons", w["person_id"]), "gender" => name_of("genders", w["gender_id"]),
            "number" => name_of("numbers", w["number_id"]), "state" => name_of("states", w["state_id"]),
            "suffix_person" => name_of("persons", w["suffix_person_id"]),
            "suffix_gender" => name_of("genders", w["suffix_gender_id"]),
            "suffix_number" => name_of("numbers", w["suffix_number_id"]),
            "lexical_form" => (true if w["is_lexeme"]), "enclitic" => (true if w["is_enclitic"])
          }.compact
        end
      end

      def body(lexeme, headword, glosses, etymologies, forms)
        lines = [[headword, nfc(lexeme["syriac_vocalized"])].compact.uniq.join(" ")]
        head = [category(lexeme), root_line(lexeme)].compact
        lines << head.join(" · ") unless head.empty?
        glosses.group_by { |g| g["language_name"] || "?" }
               .sort_by { |name, _| [GLOSS_ORDER.index(name) || GLOSS_ORDER.size, name] }
               .each { |name, rows| lines << "#{name}: #{rows.map { |g| g['text'] }.join('; ')}" }
        etymologies.each do |e|
          lines << ["Etymology:", e["language_name"], e["word"], e["meaning"] && "“#{e['meaning']}”"].compact.join(" ")
        end
        lines << "Forms: #{forms.map { |f| f['syriac'] }.uniq.join(', ')}" unless forms.empty?
        Nabu::Normalize.nfc(lines.join("\n"))
      end

      def annotations(lexeme, glosses, etymologies, forms)
        root = index("roots")[lexeme["root_id"]]
        {
          "lexeme_id" => lexeme["id"], "uuid" => lexeme["uuid"],
          "vocalized" => nfc(lexeme["syriac_vocalized"]),
          "translit_sedra3" => presence(lexeme["translit_sedra3"]),
          "translit_leiden" => presence(lexeme["translit_leiden"]),
          "pos" => category(lexeme), "verb_class" => lexeme["verb_class"],
          "kaylo" => name_of("kaylos", lexeme["kaylo_id"]),
          "root" => root && { "id" => root["id"], "syriac" => Nabu::Normalize.nfc(root["syriac"]),
                              "kind" => root["kind"] }.compact,
          "source" => source_name(lexeme["source_id"]),
          "flags" => flags(lexeme),
          "glosses" => glosses, "etymologies" => etymologies,
          "etymon_languages" => etymologies.filter_map { |e| e["language"] }.uniq,
          "forms" => forms
        }.reject { |_, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      end

      def flags(lexeme) = FLAGS.filter_map { |key, label| label if lexeme[key] }

      def reflex(etymology)
        Nabu::DictionaryReflex.new(
          lang_code: etymology["language"] || "und", word: etymology["word"],
          language: CATALOG_LANGUAGES[etymology["language"]], lang_name: etymology["language_name"],
          relation: "derived"
        )
      end

      def category(lexeme) = name_of("category_types", lexeme["category_type_id"])

      def root_line(lexeme)
        root = index("roots")[lexeme["root_id"]]
        root && "root #{Nabu::Normalize.nfc(root['syriac'])}"
      end

      def source_name(id)
        source = id && index("sources")[id]
        source && self.class.plain(source["abbreviation"] || source["full_name"])
      end

      def name_of(table, id)
        return nil if id.nil?

        index(table)[id]&.fetch("name")
      end

      def nfc(value)
        text = presence(value)
        text && Nabu::Normalize.nfc(text)
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
