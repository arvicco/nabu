# frozen_string_literal: true

require_relative "starling_dbf_parser"

module Nabu
  module Adapters
    # The StarLing IE package's lexicostatistical WORDLIST tables (P113-2):
    # the ten wide `LEXSTAT/*.dbf` tables shipped inside IE.exe beside the
    # five etymological bases (fetched with the package since P22-0, never
    # parsed before). Read from the files themselves — the starling-dbf
    # family reads them unchanged: plain dBase III, INLINE character cells
    # only (no var-pointers, no .var siblings upstream).
    #
    # == The table shape (censused over all ten, 2026-10-01)
    #
    # NUMBER (the wordlist item, 1..110 — the 100-item Swadesh list plus
    # ten) + WORD (its English meaning) + one FORM column per language, each
    # followed by its <COL>NUM cognation number. A meaning may take several
    # rows (synonym slots: balt #26 'fat n.' riebalaĩ / taukaĩ), each row
    # filling only the columns that have a further form.
    #
    # - The cognation number: a POSITIVE value is an entry id in the
    #   etymology table the table's .inf names (`proto = \data\ie\baltet.dbf`
    #   …) — censused: every positive cell of balt/celt/dard/germ/ind/iran/
    #   pi/rom/slav resolves into its target (mix: 858 of 861), so the body
    #   line "<target label>: #N" names a live entry of the target shelf
    #   (starling-baltet / -germet / -piet, and the three LEXSTAT etymology
    #   tables landed beside these as BASES rows). Zero and negative values
    #   (-1 … -113, -666, -777, -99 …) carry no base entry; they ride the
    #   body VERBATIM ("Cognation number: -2") — their semantics are not
    #   documented in-package and are never interpreted here. A cognation
    #   number in a cell with NO form (the -666 Yatvingian gaps, germ's -100
    #   Gothic gaps) mints nothing: there is no word to shelve.
    # - File position 0 is the per-language DATE ROW in every table (all 61
    #   LEXSTAT tables across the eight packages carry one; NUMBER/WORD
    #   there are junk — 123, 427, "20", blank): integer cells read as the
    #   centuries of each column's attestation (HIT -15, SKR -10, AVE/GRK -6,
    #   LAT -3, GOT 4, AEG 8, AHD/OIR 9, JAT 18, modern columns 20). It mints
    #   no entry; each form's entry carries its column's value as
    #   "Century (header row): N".
    # - Forms are verbatim upstream cells (15–20 char fields, so a few are
    #   cut mid-parenthesis upstream — "ką́sti (kánd-"); apparatus rides
    #   verbatim too: comma/semicolon variants, optional-segment parens, the
    #   undocumented "$" marker (804 cells, dard/ind/iran/pi), "?" doubts.
    #   The FOLD takes the first form token, apparatus off (the iecor/kaikki
    #   first-variant convention).
    #
    # == The grain and the language posture
    #
    # ONE ENTRY PER FORM CELL: entry id "<item>.<column>" ("58.lit"), a
    # synonym slot's repeat taking the family's stable file-order suffix
    # ("26.lit-b" — upstream design, not a defect, so no collision note);
    # headword = the form, gloss = the meaning, body = language + item +
    # cognation + date lines. The SHELF language is the branch's collective
    # code (ISO 639-5 bat/cel/gem/inc/ira/ine/roa/sla; Wiktionary's inc-dar
    # for Dardic) — DECLARED COARSENESS: dictionary_entries persist no
    # per-entry language, so a wordlist shelf can only claim its branch. The
    # per-column code (LANGUAGES, below) drives the entry's FOLD and is
    # minted only where the .inf alias names the language unambiguously;
    # cover terms (Pahari, West Pahari, Pashai, Tat, Sak) and the alias-less
    # LUV column fold under the shelf code instead. No reflex edges: the
    # wordlists are the cognation evidence, not etymologies (the reflex
    # verdict belongs to the BASES rows).
    #
    # pi.dbf is the package's union table (every other table's columns but
    # LUV, cognation numbers at the PIE level — the branch tables number
    # into their branch bases instead): the same forms classed at two
    # depths, so both shelves land — two honest groupings, never deduped.
    class StarlingLexstat
      DIR = "LEXSTAT"

      # Column siglum => [catalog code or nil, upstream label]. Labels are
      # pi.inf's field aliases verbatim — the package's one full alias set
      # (balt.inf/germ.inf repeat it; celt/dard/ind/iran/mix/rom/slav.inf
      # carry none). Codes: ISO 639-1 where one exists, else 639-3 (the
      # Wiktionary codes the germet/baltet reflex rows already speak; lat/
      # san/ae/sq/hit as piet mints them). nil = no unambiguous code — the
      # entry folds under its shelf's branch code. Judgement calls, each
      # from the alias + the table's own date row: ARM "Armenian" dated 20
      # → hy (modern; piet's ARM column is Classical, xcl); AIS "Old
      # Icelandic" → non (Old Norse); RKS "Riksmal" → no; VAL "Valencian"
      # → ca and PRV "Provencal" (dated 20) → oc (ISO 639-1 names them so);
      # GYP "Gypsy" → rom (Romani); MAY "Maiya" → mvy (Indus Kohistani);
      # BSK "Bashkarik" → gwc (Kalami); GAE "Gaelic" beside Irish → gd.
      LANGUAGES = {
        # Indo-Aryan
        "SKR" => ["san", "Old Indian"], "HND" => %w[hi Hindi], "PNJ" => %w[pa Panjabi],
        "PAR" => [nil, "Pahari"], "LHD" => %w[lah Lahnda], "SND" => %w[sd Sindhi],
        "GYP" => %w[rom Gypsy], "GUJ" => %w[gu Gujarati], "MAR" => %w[mr Marathi],
        "BNG" => %w[bn Bengali], "ASS" => %w[as Assamese], "NEP" => %w[ne Nepali],
        "SNG" => %w[si Sinhalese], "WPH" => [nil, "West Pahari"],
        # Dardic
        "KSM" => %w[ks Kashmiri], "BSK" => %w[gwc Bashkarik], "TOR" => %w[trw Torwali],
        "MAY" => %w[mvy Maiya], "SHN" => %w[scl Shina], "PHL" => %w[phl Phalura],
        "SAV" => %w[sdg Savi], "TIR" => %w[tra Tirahi], "GAW" => %w[gwt Gawar-Bati],
        "SHU" => %w[sts Shumashti], "WOT" => %w[wsv Wotapuri], "PSH" => [nil, "Pashai"],
        "KHO" => %w[khw Khowar], "KAL" => %w[kls Kalasha],
        # Iranian
        "AVE" => %w[ae Avestan], "CPE" => %w[fa Persian], "TAT" => [nil, "Tat"],
        "KRD" => %w[ku Kurdish], "GIL" => %w[glk Gilaki], "BAL" => %w[bal Baluchi],
        "TAL" => %w[tly Talysh], "PRR" => %w[prc Parachi], "ORM" => %w[oru Ormuri],
        "AFG" => %w[ps Pashto], "MNJ" => %w[mnj Munji], "SHG" => %w[sgh Shughni],
        "WKH" => %w[wbl Wakhi], "ISH" => %w[isk Ishkashimi], "YAG" => %w[yai Yagnobi],
        "OSS" => %w[os Ossetic], "SAK" => [nil, "Sak"], "SOG" => %w[sog Sogdian],
        # Slavic
        "RUS" => %w[ru Russian], "UKR" => %w[uk Ukrainian], "BLR" => %w[be Belorussian],
        "BUL" => %w[bg Bulgarian], "MAC" => %w[mk Macedonian], "SRB" => %w[sr Serbian],
        "POL" => %w[pl Polish], "SLN" => %w[sl Slovenian], "SLC" => %w[sk Slovak],
        "CHH" => %w[cs Czech], "VLU" => ["hsb", "Upper Sorbian"], "NLU" => ["dsb", "Lower Sorbian"],
        "LAB" => %w[pox Polabian],
        # Baltic
        "LIT" => %w[lt Lithuanian], "LET" => %w[lv Lettish], "JAT" => %w[xsv Yatvingian],
        "PRU" => %w[prg Prussian],
        # Germanic
        "GRM" => %w[de German], "ENG" => %w[en English], "HOL" => %w[nl Dutch],
        "ISL" => %w[is Icelandic], "GJS" => %w[nn Nynorsk], "RKS" => %w[no Riksmal],
        "SWD" => %w[sv Swedish], "DAT" => %w[da Danish], "GOT" => %w[got Gothic],
        "AIS" => ["non", "Old Icelandic"], "AEG" => ["ang", "Old English"],
        "AHD" => ["goh", "Old High German"],
        # Italic / Romance
        "LAT" => %w[lat Latin], "ITA" => %w[it Italian], "FRA" => %w[fr French],
        "PRT" => %w[pt Portuguese], "ESP" => %w[es Spanish], "GAL" => %w[gl Galician],
        "VAL" => %w[ca Valencian], "PRV" => %w[oc Provencal], "ROM" => %w[ro Romanian],
        # Celtic
        "WLS" => %w[cy Welsh], "BRT" => %w[br Breton], "CRN" => %w[kw Cornish],
        "OIR" => ["sga", "Old Irish"], "IRL" => %w[ga Irish], "GAE" => %w[gd Gaelic],
        # the rest (mix.dbf)
        "TOA" => ["xto", "Tocharian A"], "TOB" => ["txb", "Tocharian B"],
        "ALB" => %w[sq Albanian], "GRK" => ["grc", "Ancient Greek"], "MGR" => ["el", "Modern Greek"],
        "HIT" => %w[hit Hittite], "ARM" => %w[hy Armenian],
        # mix.dbf's LUV has no alias in any .inf of the package: the siglum
        # stays its own label and the entry folds under the shelf code.
        "LUV" => [nil, "LUV"]
      }.transform_values(&:freeze).freeze

      # Per-table policy (registry order = discover order). +cognation+ is
      # the body label of a positive cognation number, naming the base the
      # table's .inf `proto =` line points at.
      TABLES = {
        "starling-lexstat-balt" => {
          dbf: "balt.dbf", language: "bat", cognation: "Baltic etymology",
          title: "Baltic lexicostatistical wordlist (StarLing IE package LEXSTAT/balt; " \
                 "cognation numbers into the Baltic database)"
        }.freeze,
        "starling-lexstat-celt" => {
          dbf: "celt.dbf", language: "cel", cognation: "IE etymology",
          title: "Celtic lexicostatistical wordlist (StarLing IE package LEXSTAT/celt; " \
                 "cognation numbers into the PIE database)"
        }.freeze,
        "starling-lexstat-dard" => {
          dbf: "dard.dbf", language: "inc-dar", cognation: "Dardic etymology",
          title: "Dardic lexicostatistical wordlist (StarLing IE package LEXSTAT/dard; " \
                 "cognation numbers into the LEXSTAT Dardic etymology table)"
        }.freeze,
        "starling-lexstat-germ" => {
          dbf: "germ.dbf", language: "gem", cognation: "Germanic etymology",
          title: "Germanic lexicostatistical wordlist (StarLing IE package LEXSTAT/germ; " \
                 "cognation numbers into the Common Germanic database)"
        }.freeze,
        "starling-lexstat-ind" => {
          dbf: "ind.dbf", language: "inc", cognation: "Indo-Aryan etymology",
          title: "Indo-Aryan lexicostatistical wordlist (StarLing IE package LEXSTAT/ind; " \
                 "cognation numbers into the LEXSTAT Indo-Aryan etymology table)"
        }.freeze,
        "starling-lexstat-iran" => {
          dbf: "iran.dbf", language: "ira", cognation: "Iranian etymology",
          title: "Iranian lexicostatistical wordlist (StarLing IE package LEXSTAT/iran; " \
                 "cognation numbers into the LEXSTAT Iranian etymology table)"
        }.freeze,
        "starling-lexstat-mix" => {
          dbf: "mix.dbf", language: "ine", cognation: "IE etymology",
          title: "Indo-European isolates lexicostatistical wordlist — Prussian, Tocharian, Albanian, " \
                 "Greek, Hittite, Armenian, Luwian (StarLing IE package LEXSTAT/mix; cognation numbers " \
                 "into the PIE database)"
        }.freeze,
        "starling-lexstat-pi" => {
          dbf: "pi.dbf", language: "ine", cognation: "IE etymology",
          title: "Indo-European lexicostatistical wordlist, all branches (StarLing IE package " \
                 "LEXSTAT/pi; cognation numbers into the PIE database)"
        }.freeze,
        "starling-lexstat-rom" => {
          dbf: "rom.dbf", language: "roa", cognation: "IE etymology",
          title: "Romance lexicostatistical wordlist (StarLing IE package LEXSTAT/rom; " \
                 "cognation numbers into the PIE database)"
        }.freeze,
        "starling-lexstat-slav" => {
          dbf: "slav.dbf", language: "sla", cognation: "IE etymology",
          title: "Slavic lexicostatistical wordlist (StarLing IE package LEXSTAT/slav; " \
                 "cognation numbers into the PIE database)"
        }.freeze
      }.freeze

      INTEGER = /\A-?\d+\z/
      private_constant :INTEGER

      # { siglum => label } for the BASES rows whose per-language columns
      # share these sigla (the three LEXSTAT etymology tables).
      def self.labels(sigla) = sigla.to_h { |siglum| [siglum, LANGUAGES.fetch(siglum).last] }.freeze

      # One wordlist table → one DictionaryDocument (+languages+ is a test
      # seam: the census guard must quarantine an unknown siglum).
      def parse(slug:, path:, languages: LANGUAGES)
        table = TABLES.fetch(slug)
        parser = StarlingDbfParser.new(dbf_path: path)
        columns = form_columns(parser.fields, table, languages)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: table.fetch(:language), title: table.fetch(:title), canonical_path: path
        )
        seen = Hash.new(0)
        dates = {}
        parser.each_record.with_index do |record, index|
          if index.zero? && date_row?(record, columns)
            dates = columns.to_h { |column| [column, presence(record[column])] }
            next
          end
          entries(table, record, columns, dates, seen, languages).each { |entry| document << entry }
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "starling: #{DIR}/#{table&.fetch(:dbf)}: #{e.message}"
      end

      private

      # The form columns, field order: every column with a <COL>NUM sibling.
      # An unknown siglum quarantines the table — a language is never guessed.
      def form_columns(fields, table, languages)
        names = fields.map(&:name)
        columns = names.select { |name| name != "NUMBER" && names.include?("#{name}NUM") }
        unknown = columns.reject { |column| languages.key?(column) }
        unless unknown.empty?
          raise Nabu::ParseError, "starling: #{DIR}/#{table.fetch(:dbf)}: column(s) #{unknown.join(', ')} " \
                                  "have no LANGUAGES row — census the .inf alias before shelving"
        end
        columns
      end

      def date_row?(record, columns)
        values = columns.filter_map { |column| presence(record[column]) }
        !values.empty? && values.all? { |value| value.match?(INTEGER) }
      end

      def entries(table, record, columns, dates, seen, languages)
        number = record.fetch("NUMBER").to_s.strip
        unless number.match?(/\A\d+\z/)
          raise Nabu::ParseError, "starling: #{DIR}/#{table.fetch(:dbf)}: wordlist row without an item NUMBER"
        end

        # Numeric cells are raw dBase bytes; digits-only, so relabel as UTF-8
        # (the id doubles as the fold of a token-less cell — dard's bare "?").
        number = number.dup.force_encoding(Encoding::UTF_8)

        meaning = presence(record["WORD"])
        columns.filter_map do |column|
          form = presence(record[column]) or next
          code, name = languages.fetch(column)
          language = code || table.fetch(:language)
          entry_id = entry_id_for(table, "#{number}.#{column.downcase}", seen)
          Nabu::DictionaryEntry.new(
            entry_id: entry_id, key_raw: form, language: language,
            headword: Nabu::Normalize.nfc(form),
            headword_folded: fold(form, language) || entry_id,
            gloss: meaning && Nabu::Normalize.nfc(meaning),
            body: body(table, number: number, meaning: meaning, name: name,
                              cognation: record["#{column}NUM"].to_s.strip, date: dates[column])
          )
        end
      end

      # Synonym slots repeat an item's column: the first keeps the plain
      # id, each repeat the family's stable file-order suffix (-b, -c…).
      def entry_id_for(table, base_id, seen)
        occurrence = (seen[base_id] += 1)
        return base_id if occurrence == 1
        if occurrence > 26
          raise Nabu::ParseError, "starling: #{DIR}/#{table.fetch(:dbf)}: #{base_id} repeats #{occurrence} times"
        end

        "#{base_id}-#{('a'.ord + occurrence - 1).chr}"
      end

      def body(table, number:, meaning:, name:, cognation:, date:)
        lines = ["Language: #{name}", ["Wordlist item: ##{number}", meaning].compact.join(" ")]
        if cognation.match?(/\A\d+\z/) && cognation.to_i.positive?
          lines << "#{table.fetch(:cognation)}: ##{cognation}"
        elsif !cognation.empty?
          lines << "Cognation number: #{cognation}"
        end
        lines << "Century (header row): #{date}" if date
        Nabu::Normalize.nfc(lines.join("\n"))
      end

      # The lookup key: the FIRST form token, leading doubt/asterisk and
      # apparatus characters off, optional-segment parens opened.
      def fold(form, language)
        lead = form.sub(/\A[?*\s]+/, "").split(/[\s,;]+/).first.to_s.delete("()$?!")
        folded = Nabu::Normalize.search_form(lead, language: language)
        folded.strip.empty? ? nil : folded
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
