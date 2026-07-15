# frozen_string_literal: true

require_relative "starling_dbf_parser"

module Nabu
  module Adapters
    # The StarLing / Tower of Babel adapter (P22-0; docs/pie-survey.md §3.1):
    # the Indo-European package (IE.exe — a plain zip despite the name,
    # 6.2 MB) from starlingdb.org, ingesting its TWO Pokorny-family bases as
    # dictionary shelves — the first Moscow-school reconstruction witnesses
    # beside kaikki/LIV/IE-CoR:
    #
    #   starling-pokorny (ine-pro) — 2,222 IEW roots: J. Pokorny's
    #                    Indogermanisches Etymologisches Wörterbuch, scanned
    #                    and recognized by George Starostin, corrected by
    #                    A. Lubotsky (the in-package pokorny.inf DBINFO).
    #                    ROOT/MEANING/GER_MEAN/MATERIAL/PAGES + the PIET
    #                    crosslink into the second base.
    #   starling-piet   (ine-pro) — 3,291 etymologies: S. L. Nikolayev's
    #                    Walde-Pokorny-based PIE database, Hittite/Tocharian
    #                    reflexes added by S. Starostin (piet.inf DBINFO);
    #                    traditional laryngeal-free notation; per-branch
    #                    reflex columns HITT/IND/AVEST/IRAN/ARM/GREEK/SLAV/
    #                    BALT/GERM/LAT/ITAL/CELT/ALB/TOKH.
    #
    # The remaining package bases (germet 1,994 / baltet 1,651 / vasmer
    # 18,239) are follow-up CONFIGURATION, not code: BASES rows name every
    # per-base policy (dbf file, headword/gloss/body fields, crosslink
    # labels, reflex columns), so adding a base is one more row + fixtures.
    #
    # == License (the 2026-07-15 grant — attribution is a hard condition)
    #
    # G. Starostin, e-mail 2026-07-15: "all etymological data are free for
    # anybody to use for any purposes as long as the source is properly
    # acknowledged" — with the EXPRESS condition that attribution name the
    # SPECIFIC compilers of each database (roster:
    # starlingdb.org/descrip.php?lan=en#bases), because the databases are
    # "individual reconstructions with the subjective input of their
    # original creators, and do not always represent the most up-to-date,
    # or the most 'consensus-approved' versions" — the non-consensus caveat
    # rides verbatim in docs/02-sources.md (the Larth-caveat treatment).
    # The per-base credits below quote the roster and the in-package .inf
    # DBINFO texts; they travel in MANIFEST.license, which is the string
    # every serving surface (define/etym/cognates/MCP) renders.
    #
    # == The reflex verdict (censused fixture-first; journaled in P22-0)
    #
    # piet's branch columns are scholarly prose, not word lists. The honest
    # split: SINGLE-LANGUAGE attested columns (HITT/IND/AVEST/ARM/LAT/ALB)
    # mint ONE DictionaryReflex per cell — the leading citation form only,
    # and only when it IS a clean form token (dialect-prefixed cells like
    # "Khow. yor" and ?-doubt cells mint nothing); lang_code = the upstream
    # column name verbatim, language = the catalog tag, lang_name = the
    # .inf field alias (feeds the language-names census). GREEK is Latin
    # TRANSCRIPTION (ǟ̂ri — script-mismatched against grc gold), SLAV/BALT/
    # GERM are Nikolayev-notation branch PROTOFORMS (their honest lane is
    # the body plus the SLAVNUM/BALTNUM/GERMNUM links into the subordinate
    # bases), IRAN/ITAL/CELT/TOKH mix languages per cell — none of these
    # mint rows; every column rides the body verbatim either way.
    #
    # == Encoding
    #
    # dBase III tables + StarLing-encoded .var text (starling-dbf family:
    # StarlingDbfParser + the table-driven StarlingText decoder; byte
    # meanings come from the vendored unipro.lst, never guessed — see
    # config/starling/README.md and the fixture README for the live-web
    # verification of every fixture record).
    class Starling < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "starling",
        name: "StarLing / Tower of Babel — Indo-European etymological databases (Pokorny IEW + PIET)",
        license: "Free for any use with acknowledgment (G. Starostin, e-mail 2026-07-15: \"all " \
                 "etymological data are free for anybody to use for any purposes as long as the " \
                 "source is properly acknowledged\"); required per-base credit — Pokorny base: " \
                 "\"scanned and recognized by George Starostin (Moscow), who has also added the " \
                 "English meanings\", \"further refurnished and corrected by A. Lubotsky\"; PIE " \
                 "base: \"compiled on the basis of Walde-Pokorny's dictionary by S. L. Nikolayev\", " \
                 "Hittite and Tokharian reflexes added by S. Starostin",
        license_class: "attribution",
        upstream_url: "https://starlingdb.org/download/IE.exe",
        parser_family: "starling-dbf"
      )

      # Per-base ingestion policy (registry order = discover order). Labels
      # are the upstream .inf field aliases verbatim; :crosslinks maps a
      # numeric link column to its alias ("#%s" fills the target record
      # NUMBER — pokorny⇄piet numbers are the entry ids of these shelves);
      # :reflexes maps a branch column to [catalog language, .inf alias].
      BASES = {
        "starling-pokorny" => {
          dbf: "pokorny.dbf", language: "ine-pro",
          title: "Pokorny, Indogermanisches Etymologisches Wörterbuch " \
                 "(StarLing digitization: G. Starostin, corr. A. Lubotsky)",
          headword: "ROOT", gloss: "MEANING",
          body: {
            "GER_MEAN" => "German meaning", "GRAMMAR" => "Grammatical comments",
            "COMMENTS" => "General comments", "DERIVATIVE" => "Derivatives",
            "MATERIAL" => "Material", "REF" => "References",
            "SEEALSO" => "See also", "PAGES" => "Pages"
          }.freeze,
          crosslinks: { "PIET" => "PIE database" }.freeze,
          reflexes: {}.freeze
        }.freeze,
        "starling-piet" => {
          dbf: "piet.dbf", language: "ine-pro",
          title: "Indo-European etymology (PIET: S. L. Nikolayev, after Walde-Pokorny; " \
                 "Hitt./Tokh. by S. Starostin)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "RUSMEAN" => "Russ. meaning", "HITT" => "Hittite", "IND" => "Old Indian",
            "AVEST" => "Avestan", "IRAN" => "Other Iranian", "ARM" => "Armenian",
            "GREEK" => "Old Greek", "SLAV" => "Slavic", "BALT" => "Baltic",
            "GERM" => "Germanic", "LAT" => "Latin", "ITAL" => "Other Italic",
            "CELT" => "Celtic", "ALB" => "Albanian", "TOKH" => "Tokharian",
            "COMMENT" => "Comments", "REFER" => "References"
          }.freeze,
          crosslinks: {
            "REFERNUM" => "Pokorny", "PRNUM" => "Nostratic etymology", "SLAVNUM" => "Vasmer",
            "BALTNUM" => "Baltic etymology", "GERMNUM" => "Germanic etymology"
          }.freeze,
          reflexes: {
            "HITT" => %w[hit Hittite].freeze, "IND" => ["san", "Old Indian"].freeze,
            "AVEST" => %w[ae Avestan].freeze, "ARM" => %w[xcl Armenian].freeze,
            "LAT" => %w[lat Latin].freeze, "ALB" => %w[sq Albanian].freeze
          }.freeze
        }.freeze
      }.freeze

      # A clean leading citation form: letters first, then letters/marks and
      # the notation the bases use inside forms (optional-segment parens,
      # morpheme hyphens/equals, variant slashes, apostrophe palatals) — and
      # never a trailing period (that is an abbreviation, not a form).
      CITATION_FORM = %r{\A\*?[\p{L}\p{M}][\p{L}\p{M}'’\-/=()\[\]]*\z}
      private_constant :CITATION_FORM

      # The rider (P18 strategy): what this source witnesses about ine-pro,
      # accreted as a dossier section with per-record provenance "starling".
      LANGUAGE_NOTES = [
        ["ine-pro", "witness:starling",
         "StarLing/Tower of Babel IE bases (G. Starostin's 2026-07-15 any-use-with-acknowledgment " \
         "grant): Pokorny's IEW complete (2,222 roots, the G. Starostin-scanned, Lubotsky-corrected " \
         "digitization) beside S. L. Nikolayev's Walde-Pokorny-based PIE database (3,291 " \
         "etymologies, traditional laryngeal-free notation, per-branch reflex columns with " \
         "S. Starostin's Hittite/Tocharian additions) — Moscow-school witnesses beside " \
         "kaikki/LIV/IE-CoR, expressly \"individual reconstructions\" that \"do not always " \
         "represent the most up-to-date, or the most 'consensus-approved' versions\" (Starostin)."].freeze
      ].freeze

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      # piet mints reflex rows (health checks the promise, P18-7).
      def self.reflex_bearing? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "IE.exe", zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # [lang_code, kind, body] rows for the language-notes rider.
      def self.language_notes = LANGUAGE_NOTES

      # One DocumentRef per base, BASES order; a workdir without a base's
      # .dbf simply yields fewer refs (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        BASES.each do |slug, base|
          Dir.glob(File.join(workdir, "**", base.fetch(:dbf))).first(1).each do |path|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id, id: "#{slug}:#{base.fetch(:dbf)}",
              path: File.expand_path(path), metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        base = BASES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: base.fetch(:language),
          title: base.fetch(:title), canonical_path: document_ref.path
        )
        StarlingDbfParser.new(dbf_path: document_ref.path).each_record do |record|
          document << build_entry(base, record)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "starling: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: manifest.upstream_url, dir: workdir,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [result.not_modified ? "unchanged (304)" : nil, attic_notes(result.atticked)].compact
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes.empty? ? nil : notes.join("; "))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "starling fetch failed into #{workdir}: #{e.message}"
      end

      private

      def build_entry(base, record)
        number = record.fetch("NUMBER").to_s.strip
        raise Nabu::ParseError, "starling: #{base.fetch(:dbf)}: record without a NUMBER" if number.empty?

        key_raw = record.fetch(base.fetch(:headword)).to_s.strip
        headword = key_raw.delete_prefix("*").strip
        gloss = presence(record[base.fetch(:gloss)])
        Nabu::DictionaryEntry.new(
          entry_id: number, key_raw: key_raw, language: base.fetch(:language),
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: fold_root(headword, base.fetch(:language)) || number,
          gloss: gloss && Nabu::Normalize.nfc(gloss),
          body: body_text(base, record, key_raw),
          reflexes: build_reflexes(base, record)
        )
      end

      # Labeled body lines, upstream .inf aliases, non-empty fields only,
      # crosslink lines last ("Pokorny: #1089" — the number IS the target
      # shelf's entry id). Every branch column rides here verbatim, whether
      # or not it also minted a reflex row.
      def body_text(base, record, fallback)
        lines = base.fetch(:body).filter_map do |field, label|
          value = presence(record[field])
          "#{label}: #{value}" if value
        end
        lines += base.fetch(:crosslinks).filter_map do |field, label|
          number = record[field].to_s.strip
          "#{label}: ##{number}" unless number.empty? || number == "0"
        end
        Nabu::Normalize.nfc(lines.empty? ? fallback : lines.join("\n"))
      end

      # The verdict's honest slice: one row per single-language branch cell
      # whose LEADING token is a clean citation form; everything else stays
      # body-only (see the class comment).
      def build_reflexes(base, record)
        base.fetch(:reflexes).filter_map do |column, (language, name)|
          cell = presence(record[column]) or next
          word = cell.split(/[\s,]/).first.to_s
          next unless word.match?(CITATION_FORM)

          nfc = Nabu::Normalize.nfc(word)
          Nabu::DictionaryReflex.new(
            lang_code: column, language: language, word: nfc,
            word_folded: reflex_fold(nfc, language),
            borrowed: false, lang_name: name
          )
        end
      end

      # Root fold (the iecor/kaikki convention): first comma-variant, ?/*
      # prefix and parens off, the IEW homonym digit off ("aig-2" → "aig-"),
      # trailing stem hyphen KEPT — cross-witness define/closure joins run
      # through this key.
      def fold_root(headword, language)
        first = headword.split(/,\s*/).first.to_s
        cleaned = first.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/(?<=-)\d+\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language)
        folded.strip.empty? ? nil : folded
      end

      # Member fold (the iecor member rule): parens and the trailing stem
      # hyphen off — gold lemmas carry neither.
      def reflex_fold(word, language)
        cleaned = word.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/-\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language)
        folded.strip.empty? ? nil : folded
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
