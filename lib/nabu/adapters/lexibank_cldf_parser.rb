# frozen_string_literal: true

require "csv"

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The lexibank-cldf parser family: ONE reader for the lexibank
    # ecosystem's CLDF Wordlist bundles (github.com/lexibank — the
    # standardized cognate-coded wordlists of the CLDF/Concepticon/
    # Glottolog world), generalizing the IE-CoR seam (iecor_cldf_parser)
    # that iecor and meloniromance hand-wrote per dataset. Every lexibank
    # bundle shares the same table spine:
    #
    #   forms.csv        the lexemes (ID, Language_ID, Parameter_ID, Value,
    #                    Form, Loan, Doubt …)
    #   languages.csv    the varieties (Name, Glottocode, ISO639P3code,
    #                    Is_Proto where the dataset marks reconstructions)
    #   parameters.csv   the concepts (Name, Concepticon ids)
    #   cognates.csv     the cognate JUDGMENTS (Form_ID × Cognateset_ID,
    #                    Doubt) — the CognateTable, the dataset's own claim
    #
    # plus three optional tables the family reads where present:
    #
    #   cognatesets.csv  set-level records: Description, Name, Comment,
    #                    Source, Doubt, and — in the comparative
    #                    dictionaries (acd, mcd, tlopo, csd) — Form_ID, the
    #                    set's RECONSTRUCTION (a form row of an Is_Proto
    #                    variety), plus tlopo's Level and acd's Etymon_ID
    #   borrowings.csv   Target_Form_ID → a loan event on that form
    #                    (SourceLanguoid / Likelihood where given)
    #   etyma.csv        acd's etymon records (Name + Description), joined
    #                    through cognatesets.Etymon_ID
    #
    # == The seam: one entry per cognate set (the IE-CoR shape)
    #
    # ONE dictionary shelf per dataset, ONE entry per cognate set
    # (entry_id = upstream's Cognateset_ID verbatim, so the URN
    # urn:nabu:dict:<slug>:<set> never depends on a curatable field), each
    # member form a DictionaryReflex row — define/etym/cognates and the
    # reflex-roots closure read it with no new query code.
    #
    # - HEADWORD: the set's reconstruction when the dataset carries one —
    #   cognatesets.Form_ID first, else the first member that is a
    #   reconstruction: a variety upstream flags Is_Proto, or one the
    #   dataset DECLARES (+proto_varieties+ — uralex's "Proto-Uralic*"
    #   row carries no Is_Proto column). Never sniffed from a leading
    #   asterisk: sagartst writes Baxter-Sagart Old Chinese as *daŋʔ-s, a
    #   cognate member, not the set's ancestor. The form is taken
    #   VERBATIM (acd/tlopo write proto forms without the asterisk; the
    #   set's own Name — "PAN *baNaw 'a thorny vine'" — rides the body).
    #   A dataset with no reconstructions (dyen, saenko, sagartst) has no
    #   honest word to head a set with, so the set's CONCEPT label stands
    #   in (the body says so) — sets sharing a concept are that concept's
    #   cognate classes; the set id is the identity.
    # - MEMBERS: every judged form except the headword's own row, in
    #   cognates.csv order. Placeholder forms (lexibank's "---" for an
    #   unrecorded lexeme) mint nothing; a set left with neither a
    #   reconstruction nor a real member mints no entry (the iecor
    #   no-members-no-entry rule), and neither does a cognatesets row with
    #   no judgment at all — both counted in the census.
    # - FLAGS: borrowed = forms.Loan "true" OR the form is a borrowings
    #   target; uncertain = the judgment's or the form's Doubt "true".
    #   relation stays nil (descendant/cognate rows state no typed edge —
    #   the IE-CoR rule).
    # - LANGUAGES: a dataset's +varieties+ map (variety ID → catalog code)
    #   wins — the hook for reconstructed varieties whose registry code is
    #   known (Proto-Oceanic → poz-oce-pro); else the ISO 639-3 code passes
    #   through when shape-valid; else nil (display-only, never a join
    #   candidate). lang_code: the mapped code, else ISO, else Glottocode —
    #   EXCEPT for a reconstructed variety, which never wears its family's
    #   Glottocode as a language code (ocea1241 is the Oceanic family, not
    #   Proto-Oceanic) and falls back to the namespaced "<slug>-<variety>".
    #
    # == Word strategies (declared per dataset, never sniffed)
    #
    # :form          Form verbatim — lexibank's cleaned form column (the
    #                default)
    # :value         Value verbatim — for datasets whose Form column is a
    #                segmentation artifact (sagartst writes "s.t.e.ŋ" for
    #                Old Tibetan steŋ)
    # :value_braces  saenkoromance's Value grammar: variants joined by "~",
    #                each "transcription {orthography}" — the orthography
    #                is the word, the transcription rides roman (a variant
    #                with only one half keeps that half as the word)
    #
    # Folds: the headword strips a leading ?/* and parens and folds under
    # the dictionary language; members also strip the trailing stem hyphen
    # (gold lemmas carry neither) and fold under their own language — the
    # iecor convention, both rules stated there.
    class LexibankCldfParser
      # What one read yields: the entries plus a census of what was read
      # and what was skipped by rule (never dropped silently).
      Result = Data.define(:entries, :census)

      WORD_STRATEGIES = %i[form value value_braces].freeze

      # lexibank's spelling of "no form recorded" (ielexfinal ships every
      # one of its 21,483 forms as "---"), plus blank cells.
      PLACEHOLDER = /\A[\s\-–—?]*\z/

      VARIANT_SPLIT = /\s*~\s*/
      BRACED = /\A(?<trans>[^{}]*?)\s*\{(?<orth>[^{}]*)\}\s*\z/

      def initialize(slug:, language:, label:, word_from: :form, varieties: {}, proto_varieties: [])
        unless WORD_STRATEGIES.include?(word_from)
          raise ArgumentError, "word_from must be one of #{WORD_STRATEGIES.join(', ')}"
        end

        @slug = slug
        @language = language
        @label = label
        @word_from = word_from
        @varieties = varieties
        @proto_varieties = proto_varieties.to_set
      end

      def read(cldf_dir)
        tables = load_tables(cldf_dir)
        census = Hash.new(0)
        entries = ordered_set_ids(tables).filter_map do |set_id|
          judgments = tables.fetch(:judgments)[set_id]
          if judgments.nil?
            census[:sets_without_judgments] += 1
            next nil
          end

          entry = build_entry(set_id, judgments, tables)
          census[entry ? :sets_minted : :sets_without_forms] += 1
          entry
        end
        census[:forms_unjudged] = unjudged_forms(tables)
        Result.new(entries: entries, census: census.to_h)
      end

      private

      # -- tables ----------------------------------------------------------------

      def load_tables(dir)
        judgments = {}
        csv_rows(dir, "cognates.csv", required: true).each do |row|
          (judgments[row.fetch("Cognateset_ID")] ||= []) << row
        end
        {
          forms: csv_index(dir, "forms.csv", required: true),
          languages: csv_index(dir, "languages.csv", required: true),
          parameters: csv_index(dir, "parameters.csv", required: true),
          judgments: judgments,
          cognatesets: csv_rows(dir, "cognatesets.csv").to_h { |row| [row.fetch("ID"), row] },
          borrowings: csv_rows(dir, "borrowings.csv").group_by { |row| row.fetch("Target_Form_ID") },
          etyma: csv_index(dir, "etyma.csv")
        }
      end

      def csv_rows(dir, filename, required: false)
        path = File.join(dir, filename)
        unless File.file?(path)
          raise Nabu::ParseError, "lexibank-cldf #{@slug}: missing #{filename} in #{dir}" if required

          return []
        end

        text = SourceRead.utf8_file(path, label: "#{@slug} #{filename}")
        CSV.parse(text, headers: true).map(&:to_h)
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "lexibank-cldf #{@slug}: malformed #{filename}: #{e.message}"
      end

      def csv_index(dir, filename, required: false)
        csv_rows(dir, filename, required: required).to_h { |row| [row.fetch("ID"), row] }
      end

      # cognatesets.csv order first (the dataset's own sequence), then any
      # judged set the table does not list, in first-judgment order.
      def ordered_set_ids(tables)
        listed = tables.fetch(:cognatesets).keys
        listed + (tables.fetch(:judgments).keys - listed)
      end

      def unjudged_forms(tables)
        judged = tables.fetch(:judgments).values.flatten.to_set { |row| row.fetch("Form_ID") }
        heads = tables.fetch(:cognatesets).values.filter_map { |set| set["Form_ID"] }.to_set
        tables.fetch(:forms).keys.count { |id| !judged.include?(id) && !heads.include?(id) }
      end

      def form!(tables, form_id, set_id)
        tables.fetch(:forms).fetch(form_id) do
          raise Nabu::ParseError, "lexibank-cldf #{@slug}: cognate set #{set_id} names unknown form #{form_id}"
        end
      end

      def variety!(tables, form)
        tables.fetch(:languages).fetch(form.fetch("Language_ID")) do
          raise Nabu::ParseError, "lexibank-cldf #{@slug}: form #{form['ID']} names unknown variety " \
                                  "#{form['Language_ID']}"
        end
      end

      # -- entries ---------------------------------------------------------------

      def build_entry(set_id, judgments, tables)
        set = tables.fetch(:cognatesets)[set_id] || {}
        members = judgments.map { |judgment| [judgment, form!(tables, judgment.fetch("Form_ID"), set_id)] }
        head = head_form(set, members, tables)
        reflexes = members.reject { |_, form| head && form.fetch("ID") == head.fetch("ID") }
                          .flat_map { |judgment, form| form_reflexes(judgment, form, tables) }
        head_word = head && words(head).first&.first
        return nil if head_word.nil? && reflexes.empty?

        concept = set_concept(set, head, members, tables)
        key = head_word || concept || set_id
        Nabu::DictionaryEntry.new(
          entry_id: set_id, key_raw: key, language: @language,
          headword: nfc(key), headword_folded: fold_head(key) || set_id,
          gloss: gloss(set, concept),
          body: body_text(set_id, set, head, concept, members, tables),
          reflexes: reflexes
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "lexibank-cldf #{@slug}: cognate set #{set_id.inspect}: #{e.message}"
      end

      def head_form(set, members, tables)
        return form!(tables, set["Form_ID"], set["ID"]) unless blank?(set["Form_ID"])

        members.map(&:last).find { |form| proto_variety?(variety!(tables, form)) }
      end

      def proto_variety?(variety)
        variety["Is_Proto"].to_s.casecmp?("true") || @proto_varieties.include?(variety.fetch("ID"))
      end

      # The set's meaning: the reconstruction's concept; without one, the
      # set's own Description (csd labels head-less sets "vermin (6)" while
      # their members gloss "ant") before the first member's concept.
      def set_concept(set, head, members, tables)
        return concept_name(head, tables) if head
        return set["Description"].strip unless blank?(set["Description"])

        concept_name(members.first.last, tables)
      end

      def concept_name(form, tables)
        parameter = tables.fetch(:parameters)[form["Parameter_ID"]]
        name = parameter && parameter["Name"]
        blank?(name) ? nil : name.strip
      end

      def gloss(set, concept)
        text = blank?(set["Description"]) ? concept : set["Description"]
        blank?(text) ? nil : nfc(text.gsub(/\s+/, " ").strip)
      end

      def body_text(set_id, set, head, concept, members, tables)
        lines = ["#{@label} cognate set #{set_id} — concept: #{concept || '(unknown)'}"]
        lines << (if head
                    reconstruction_line(head, set,
                                        tables)
                  else
                    "no reconstruction in this dataset — the concept heads the set"
                  end)
        lines << "set: #{set['Name'].strip}" if informative_name?(set, set_id, head)
        lines.concat(etymon_lines(set, tables))
        lines << "comment: #{set['Comment'].strip}" unless blank?(set["Comment"])
        lines << "source: #{set['Source'].strip}" unless blank?(set["Source"])
        lines << "(doubtful set)" if set["Doubt"].to_s.casecmp?("true")
        lines.concat(loan_lines(members, tables))
        nfc(lines.join("\n"))
      end

      # The set's own Name earns a body line unless it merely repeats the
      # set id (csd numbers its sets by name) or the headword (mcd's "*fiti"
      # over the headword fiti) — acd's "PAN *baNaw 'a thorny vine'" and
      # tlopo's variant lists ("tanum, tanum-i-") carry information.
      def informative_name?(set, set_id, head)
        name = set["Name"].to_s.strip
        return false if name.empty? || name == set_id
        return true unless head

        name.delete_prefix("*") != words(head).first&.first
      end

      def reconstruction_line(head, set, tables)
        variety = variety!(tables, head)
        level = blank?(set["Level"]) ? "" : " (level #{set['Level'].strip})"
        "reconstruction: #{variety.fetch('Name')} #{words(head).map(&:first).join(' ~ ')}#{level}"
      end

      def etymon_lines(set, tables)
        etymon = tables.fetch(:etyma)[set["Etymon_ID"]] or return []
        description = blank?(etymon["Description"]) ? "" : " — #{etymon['Description'].strip}"
        ["etymon #{etymon.fetch('ID')}: #{etymon['Name']}#{description}"]
      end

      def loan_lines(members, tables)
        members.flat_map do |_, form|
          events = tables.fetch(:borrowings)[form.fetch("ID")] || []
          next [] if events.empty? && !loan_flag?(form)

          who = "#{variety!(tables, form).fetch('Name')} #{words(form).map(&:first).join(' ~ ')}"
          next ["loan: #{who}"] if events.empty?

          events.map { |event| "loan: #{who}#{loan_source(event)}" }
        end.uniq # acd records one event per cf. set: source-less twins render once
      end

      def loan_source(event)
        source = event["SourceLanguoid"].to_s.strip
        likelihood = event["Likelihood"].to_s.strip
        text = source.empty? ? "" : " ← #{source}"
        likelihood.empty? ? text : "#{text} (#{likelihood})"
      end

      # -- reflexes --------------------------------------------------------------

      def form_reflexes(judgment, form, tables)
        variety = variety!(tables, form)
        language = variety_language(variety)
        borrowed = loan_flag?(form) || tables.fetch(:borrowings).key?(form.fetch("ID"))
        uncertain = [judgment["Doubt"], form["Doubt"]].any? { |flag| flag.to_s.casecmp?("true") }
        words(form).map do |word, roman|
          Nabu::DictionaryReflex.new(
            lang_code: variety_code(variety), language: language,
            word: word, roman: roman,
            word_folded: fold_member(word, language), roman_folded: roman && fold_member(roman, language),
            borrowed: borrowed, uncertain: uncertain,
            lang_name: nfc(variety.fetch("Name").to_s.tr("_", " ").strip)
          )
        end
      end

      def loan_flag?(form) = form["Loan"].to_s.casecmp?("true")

      # [[word, roman_or_nil], ...] — placeholders dropped, NFC applied.
      def words(form)
        pairs =
          case @word_from
          when :form then [[form["Form"].to_s, nil]]
          when :value then [[form["Value"].to_s, nil]]
          when :value_braces then braced_variants(form["Value"].to_s)
          end
        pairs.filter_map do |word, roman|
          word = word.strip
          next nil if word.match?(PLACEHOLDER)

          [nfc(word), blank?(roman) ? nil : nfc(roman.strip)]
        end
      end

      def braced_variants(value)
        value.split(VARIANT_SPLIT).map do |variant|
          match = BRACED.match(variant.strip)
          next [variant, nil] unless match

          trans = match[:trans].strip
          orth = match[:orth].strip
          next [trans, nil] if orth.empty?
          next [orth, nil] if trans.empty?

          [orth, trans]
        end
      end

      def variety_language(variety)
        id = variety.fetch("ID")
        return @varieties[id] if @varieties.key?(id)

        iso = variety["ISO639P3code"].to_s.strip
        iso.match?(Nabu::Model::Validation::LANGUAGE_SHAPE) ? iso : nil
      end

      def variety_code(variety)
        id = variety.fetch("ID")
        mapped = @varieties[id]
        return mapped if mapped

        iso = variety["ISO639P3code"].to_s.strip
        return iso unless iso.empty?

        glottocode = variety["Glottocode"].to_s.strip
        return glottocode unless glottocode.empty? || proto_variety?(variety)

        "#{@slug}-#{id}"
      end

      # -- folds -------------------------------------------------------------------

      def fold_head(text)
        cleaned = text.sub(/\A[?*\s]+/, "").delete("()⁽⁾")
        folded = Nabu::Normalize.search_form(cleaned, language: @language)
        folded.strip.empty? ? nil : folded
      end

      def fold_member(text, language)
        cleaned = text.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/-\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language || @language)
        folded.strip.empty? ? nil : folded
      end

      def nfc(text) = Nabu::Normalize.nfc(text)

      def blank?(value) = value.to_s.strip.empty?
    end
  end
end
