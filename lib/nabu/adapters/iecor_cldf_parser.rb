# frozen_string_literal: true

require "csv"

require_relative "../normalize"

module Nabu
  module Adapters
    # The cldf-csv parser family (P18-5; .docs/surveys/pie-survey.md §1 is the design
    # source): CLDF — the Cross-Linguistic Data Formats standard — ships a
    # dataset as a bundle of csvw tables. IE-CoR's bundle joins six of them:
    #
    #   cognatesets.csv  one row per expert-curated cognate set → one
    #                    DictionaryEntry (entry_id = the set id; the URN
    #                    namespace urn:nabu:dict:iecor:<set_id> therefore
    #                    never depends on any curatable field)
    #   cognates.csv     the membership judgments (set × form), file order
    #   forms.csv        the lexemes (romanized Form + native_script + the
    #                    per-variety comment/source apparatus)
    #   languages.csv    the 160 varieties (names, Glottocodes, ISO codes,
    #                    clade paths, historical flags) — the language-info
    #                    rider's raw material
    #   parameters.csv   the 170 Concepticon-linked meanings (gloss fallback)
    #   loans.csv        curated per-SET loan events → borrowed=true
    #
    # == Headwords (the root side)
    #
    # headword = Root_Form VERBATIM (falling back to Root_Form_calc — 655
    # computed roots live; every set carries one or the other), asterisk,
    # ?-doubt prefix and inline parens included: upstream writes the
    # asterisk exactly on reconstructions, so display honesty is free and
    # canonical stays canonical. headword_folded strips the leading [?*]
    # prefix and the parens characters ((), ⁽⁾ — "?*pel(h₁)-" → "pelh₁-"),
    # keeps the trailing stem hyphen, and folds under the "ine" PROTO_FOLD
    # (conventions §9) — byte-equal to the kaikki shelves' convention, so
    # IE-CoR *k̑erd- (k + U+0311) and kaikki *ḱerd- (U+1E31) meet at "kerd-"
    # (the survey's spot-checked cross-witness join).
    #
    # == Members (the reflex side)
    #
    # One judgment mints one reflex — or several, under the multiform split
    # policy pinned at fixture time: upstream packs orthographic variants
    # comma-joined ("попєлъ, пєпєлъ") and stem alternants spaced-slash-joined
    # ("ker / kard(i)-") into ONE field; both split, native_script and Form
    # paired by index when their part counts agree (a mismatch falls back to
    # one unsplit verbatim reflex — never a misaligned pair). word =
    # native_script when present else Form; roman = Form beside a native
    # word (the got 𐌷𐌰𐌹𐍂𐍄𐍉/hairto script bridge, exactly the kaikki
    # convention). Member folds strip parens and the TRAILING hyphen (gold
    # lemmas carry neither); root headword folds keep the hyphen (the shelf
    # convention above) — two join targets, two rules, both stated.
    #
    # == The honest gaps (survey §1, handled as stated, never fudged)
    #
    # - san forms are accented nom.sg. (hā́rdi) where UD-Vedic/GRETIL gold
    #   lemmas are stem-shaped: the roman fold is minted anyway; the join is
    #   expected depressed, measured at query time, not promised.
    # - hit forms are hyphenated sign-joined stems: the paren/hyphen strip
    #   gives clean fold keys, but hit gold is ~14 lemmas — ≈0 join either
    #   way (corpus-side gap, per .docs/surveys/recon2-survey.md).
    # - orv is the Novgorod DIALECT (сердьце with polnoglasie vs TOROT's
    #   OCS-leaning lemmas): partial join by nature; nothing rewritten.
    # - per-judgment Doubt flags and alignment strings have no home in the
    #   entry model — dropped, named here (revisit if a second cognacy
    #   source makes set-grain storage worth its own surface).
    #
    # == Loans
    #
    # loans.csv is per-SET (set ← named source languoid / source set): the
    # event ORs into EVERY member edge as borrowed=true — the survey's
    # explicit design ("loans.csv ORs into member edges the same way the
    # hlaibaz proto-to-proto flag does"): the closure's flag is path-grained,
    # and each member descends through the borrowing event. Members of
    # event-less sets parse false (never NULL — the migration-010 contract).
    #
    # == The language-info rider (P18-4's first programmatic writer)
    #
    # languages.csv rows become LanguageNote values (kind "iecor", source
    # "iecor"): one note per CATALOG-FACING code — the 12-variety held map's
    # tags plus every other variety's ISO/Glottocode — with varieties
    # sharing a code (Greek: Ancient + Greek: New Testament → grc) grouped
    # into ONE deterministic body, so the append-only ledger contract
    # (append only when the latest body differs) never ping-pongs.
    class IecorCldfParser
      # What one read of a CLDF dir yields: entries for the dictionary
      # shelf, language notes for the ledger accretion.
      Result = Data.define(:entries, :language_notes)

      # The held-variety map (.docs/surveys/pie-survey.md §1, owner-approved): IE-CoR
      # variety id → the catalog's language tag. Keyed by variety ID, not
      # ISO code, so an upstream re-tagging can never silently remap; the
      # two rows the map actually CHANGES are Slovene: Early Modern
      # (ISO slv → our goo300k tag sl) and both Greek varieties collapsing
      # onto grc. Mycenaean rides as gmy — shape-valid, honestly off-gold.
      VARIETY_MAP = {
        "80" => "hit",    # Hittite
        "100" => "chu",   # Old Church Slavonic
        "105" => "san",   # Vedic: Early
        "110" => "grc",   # Greek: Ancient
        "177" => "grc",   # Greek: New Testament
        "173" => "gmy",   # Greek: Mycenaean (off-gold, stated)
        "112" => "lat",   # Latin
        "129" => "xcl",   # Armenian: Classical
        "245" => "orv",   # Old Novgorod
        "259" => "sl",    # Slovene: Early Modern
        "298" => "ang",   # Old English
        "303" => "got"    # Gothic
      }.freeze

      DICTIONARY_LANGUAGE = "ine"
      NOTE_KIND = "iecor"
      NOTE_SOURCE = "iecor"

      # Orthographic-variant / stem-alternant separators (the fixture-pinned
      # split policy): comma, and slash ONLY when spaced (an unspaced slash
      # inside a transliteration is not a separator).
      MULTIFORM_SPLIT = %r{\s*,\s*|\s+/\s+}

      # Parse the CLDF table dir into entries + language notes.
      def read(cldf_dir)
        tables = load_tables(cldf_dir)
        minted = Hash.new(0) # variety id => reflex rows minted
        entries = tables.fetch(:cognatesets).filter_map do |set|
          judgments = tables.fetch(:judgments)[set.fetch("ID")]
          # 58 sets live carry no membership judgment at all (editorial
          # residue) — no members, no entry, skipped by rule.
          next nil if judgments.nil?

          build_entry(set, judgments, tables, minted)
        end
        Result.new(entries: entries, language_notes: language_notes(tables, minted))
      end

      private

      def load_tables(dir)
        judgments = {}
        csv_each(dir, "cognates.csv") do |row|
          (judgments[row.fetch("Cognateset_ID")] ||= []) << row
        end
        {
          languages: csv_index(dir, "languages.csv"),
          parameters: csv_index(dir, "parameters.csv"),
          forms: csv_index(dir, "forms.csv"),
          cognatesets: csv_rows(dir, "cognatesets.csv"),
          judgments: judgments,
          loans: csv_rows(dir, "loans.csv").group_by { |row| row.fetch("Cognateset_ID") }
        }
      end

      def csv_rows(dir, filename)
        path = File.join(dir, filename)
        return [] unless File.file?(path)

        CSV.read(path, headers: true, encoding: Encoding::UTF_8).map(&:to_h)
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "cldf-csv: malformed #{filename}: #{e.message}"
      end

      def csv_each(dir, filename, &)
        csv_rows(dir, filename).each(&)
      end

      def csv_index(dir, filename)
        csv_rows(dir, filename).to_h { |row| [row.fetch("ID"), row] }
      end

      # -- entries ---------------------------------------------------------------

      def build_entry(set, judgments, tables, minted)
        reflexes = judgments.flat_map do |judgment|
          form = tables.fetch(:forms)[judgment.fetch("Form_ID")] or next []
          variety = tables.fetch(:languages)[form.fetch("Language_ID")] or next []
          minted[variety.fetch("ID")] += 0 # mark seen even if a part yields nothing
          rows = form_reflexes(form, variety, borrowed: tables.fetch(:loans).key?(set.fetch("ID")))
          minted[variety.fetch("ID")] += rows.size
          rows
        end
        root = blank?(set["Root_Form"]) ? set["Root_Form_calc"] : set["Root_Form"]
        # Every live set carries a curated or computed root (measured:
        # 4,384 + 655 = 5,039); the set-id fallback guards the model's
        # non-empty contracts against a future rootless or all-punctuation
        # row rather than quarantining the whole file.
        root = set.fetch("ID") if blank?(root)
        Nabu::DictionaryEntry.new(
          entry_id: set.fetch("ID"), key_raw: root, language: DICTIONARY_LANGUAGE,
          headword: Nabu::Normalize.nfc(root),
          headword_folded: fold_root(root) || set.fetch("ID"),
          gloss: gloss(set, judgments, tables),
          body: body_text(set, judgments, tables),
          citations: [], reflexes: reflexes
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "cldf-csv: cognate set #{set['ID'].inspect}: #{e.message}"
      end

      # Root fold: drop the ?/* prefix and parens, KEEP the trailing hyphen
      # (the kaikki shelf convention — cross-witness joins run through it).
      def fold_root(root)
        cleaned = root.sub(/\A[?*\s]+/, "").delete("()⁽⁾")
        folded = Nabu::Normalize.search_form(cleaned, language: DICTIONARY_LANGUAGE)
        folded.strip.empty? ? nil : folded
      end

      def gloss(set, judgments, tables)
        text = blank?(set["Root_Gloss"]) ? concept_name(judgments, tables) : set["Root_Gloss"]
        blank?(text) ? nil : Nabu::Normalize.nfc(text.gsub(/\s+/, " ").strip)
      end

      def concept_name(judgments, tables)
        form = tables.fetch(:forms)[judgments.first.fetch("Form_ID")] or return nil
        parameter = tables.fetch(:parameters)[form.fetch("Parameter_ID")]
        parameter && parameter["Name"]
      end

      def body_text(set, judgments, tables)
        lines = ["IE-CoR cognate set #{set.fetch('ID')} — concept: #{concept_name(judgments, tables) || '(unknown)'}"]
        lines << root_line(set)
        (tables.fetch(:loans)[set.fetch("ID")] || []).each { |event| lines << loan_line(event) }
        lines << set["Comment"] unless blank?(set["Comment"])
        lines << "(ideophonic)" if set["Ideophonic"] == "true"
        lines << "(parallel derivation)" if set["parallelDerivation"] == "true"
        Nabu::Normalize.nfc(lines.compact.join("\n"))
      end

      def root_line(set)
        if blank?(set["Root_Form"])
          language = blank?(set["Root_Language_calc"]) ? "" : " (#{set['Root_Language_calc']})"
          "root (computed): #{set['Root_Form_calc']}#{language}"
        else
          language = blank?(set["Root_Language"]) ? "" : " (#{set['Root_Language']})"
          "root: #{set['Root_Form']}#{language}"
        end
      end

      def loan_line(event)
        source = [event["Source_languoid"], event["Source_form"]].reject { |part| blank?(part) }
        source << "cognate set #{event['SourceCognateset_ID']}" unless blank?(event["SourceCognateset_ID"])
        line = "loan ← #{source.empty? ? '(unnamed source)' : source.join(' ')}"
        line += " (parallel loan event)" if event["Parallel_loan_event"] == "true"
        line += " — #{event['Comment']}" unless blank?(event["Comment"])
        line
      end

      # -- reflexes --------------------------------------------------------------

      def form_reflexes(form, variety, borrowed:)
        native = form["native_script"].to_s.strip
        roman = form["Form"].to_s.strip
        return [] if native.empty? && roman.empty?

        word_parts = split_multiform(native.empty? ? roman : native)
        roman_parts = native.empty? ? [] : split_multiform(roman)
        pairs =
          if native.empty?
            word_parts.map { |part| [part, nil] }
          elsif word_parts.size == roman_parts.size
            word_parts.zip(roman_parts)
          else
            [[native, roman]] # mismatched multiform counts: one unsplit pair
          end
        pairs.map { |word, rom| build_reflex(variety, word, rom, borrowed: borrowed) }
      end

      def split_multiform(text)
        parts = text.split(MULTIFORM_SPLIT).map(&:strip).reject(&:empty?)
        parts.empty? ? [text] : parts
      end

      def build_reflex(variety, word, roman, borrowed:)
        language = variety_language(variety)
        word = Nabu::Normalize.nfc(word)
        roman = blank?(roman) ? nil : Nabu::Normalize.nfc(roman)
        Nabu::DictionaryReflex.new(
          lang_code: variety_code(variety), language: language,
          word: word, roman: roman,
          word_folded: reflex_fold(word, language),
          roman_folded: roman && reflex_fold(roman, language),
          borrowed: borrowed,
          lang_name: Nabu::Normalize.nfc(variety.fetch("Name"))
        )
      end

      # The upstream code verbatim: ISO 639-3 when the variety carries one,
      # else its Glottocode, else the numeric variety id namespaced.
      def variety_code(variety)
        return variety["ISO639P3code"] unless blank?(variety["ISO639P3code"])
        return variety["Glottocode"] unless blank?(variety["Glottocode"])

        "iecor-#{variety.fetch('ID')}"
      end

      # The held map first; unmapped varieties pass their ISO code through
      # when it is a shape-valid tag (display + honest card counts), else
      # nil (display-only, never a join candidate) — the kaikki precedent.
      def variety_language(variety)
        mapped = VARIETY_MAP[variety.fetch("ID")]
        return mapped if mapped

        iso = variety["ISO639P3code"].to_s
        iso.match?(Nabu::Model::Validation::LANGUAGE_SHAPE) ? iso : nil
      end

      # Member fold: parens and the trailing stem hyphen strip (gold lemmas
      # carry neither); leading asterisk strip mirrors the kaikki reflex
      # rule. nil when the fold comes out empty or stays multiword (a
      # spaced alternant that failed to split cleanly joins nothing).
      def reflex_fold(text, language)
        cleaned = text.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/-\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language || DICTIONARY_LANGUAGE)
        folded.strip.empty? ? nil : folded
      end

      # -- the language-info rider -------------------------------------------------

      # One note per catalog-facing code, for every variety that minted (or
      # was seen minting) reflexes in this read PLUS the held-map varieties
      # present in languages.csv. Varieties sharing a code group into one
      # body, ordered by upstream variety id — deterministic, so the
      # ledger's append-only idempotency holds across reparses.
      def language_notes(tables, minted)
        varieties = tables.fetch(:languages).values.select do |variety|
          minted.key?(variety.fetch("ID")) || VARIETY_MAP.key?(variety.fetch("ID"))
        end
        varieties.group_by { |variety| VARIETY_MAP[variety.fetch("ID")] || variety_code(variety) }
                 .sort
                 .map do |code, group|
          group = group.sort_by { |variety| variety.fetch("ID").to_i }
          Nabu::DictionaryLanguageNote.new(
            lang_code: code, kind: NOTE_KIND, source: NOTE_SOURCE,
            body: Nabu::Normalize.nfc(note_body(group))
          )
        end
      end

      def note_body(varieties)
        label = varieties.size == 1 ? "IE-CoR variety" : "IE-CoR varieties"
        "#{label}: #{varieties.map { |variety| variety_blurb(variety) }.join(' · ')}"
      end

      def variety_blurb(variety)
        bits = []
        clade = variety["Clade"].to_s.split(";").join(" > ")
        bits << "clade #{clade}" unless clade.empty?
        bits << "Glottocode #{variety['Glottocode']}" unless blank?(variety["Glottocode"])
        bits << (variety["historical"] == "true" ? "historical" : "modern")
        "#{variety.fetch('Name')} (#{bits.join('; ')})"
      end

      def blank?(value)
        value.to_s.strip.empty?
      end
    end
  end
end
