# frozen_string_literal: true

require_relative "starling_dbf_parser"

module Nabu
  module Adapters
    # The StarLing / Tower of Babel adapter (P22-0 + P23-0;
    # docs/pie-survey.md §3.1): the Indo-European package (IE.exe — a plain
    # zip despite the name, 6.2 MB) from starlingdb.org, ingesting its FIVE
    # etymological bases as dictionary shelves — Moscow-school witnesses
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
    #                    BALT/GERM/LAT/ITAL/CELT/ALB/TOKH, plus the SLAVNUM/
    #                    BALTNUM/GERMNUM links into the subordinate bases —
    #                    live entry ids since P23-0 (censused: GERMNUM
    #                    1,965/1,965 and SLAVNUM 1,233/1,233 resolve; six
    #                    BALTNUM links dangle on baltet's own six
    #                    duplicate-NUMBER records, below).
    #   starling-vasmer (rus, P23-0) — 18,239 entries: M. Vasmer's
    #                    etymological dictionary of Russian (the Trubachev
    #                    Russian edition: TRUBACHEV = his bracketed
    #                    additions), scanned/OCR'd/database-converted by the
    #                    project; vasmer.inf is BLANK, so field labels come
    #                    from the live CGI (Word / Near etymology / Further
    #                    etymology / Trubachev's comments / Editorial
    #                    comments / Pages, web-verified 2026-07-15) and the
    #                    credit from the descrip.php roster. Prose fields
    #                    only — no reflex columns; the shelf is piet's
    #                    SLAVNUM target ("currently serving as a substitute
    #                    for the comparative Slavic database", roster).
    #   starling-germet (gem-pro, P23-0) — 1,994 Common Germanic
    #                    etymologies (S. Nikolayev, germet.inf DBINFO):
    #                    per-language columns GOT…HG, PRNUM → piet.
    #   starling-baltet (bat-pro, P23-0) — 1,651 Proto-Baltic etymologies
    #                    (S. Nikolayev, baltet.inf DBINFO): OLITH/LITH/LETT/
    #                    OPRUS columns, PRNUM → piet. Six records carry a
    #                    NUMBER another record already used (76/95/248/689/
    #                    1049/1394 — upstream defect, matching piet's six
    #                    dangling BALTNUM links): the first keeps the NUMBER
    #                    as entry id, a repeat gets a stable ".2" file-order
    #                    suffix (canonical bytes untouched).
    #
    # P22-0 promised the follow-up bases as CONFIGURATION, not code: BASES
    # rows name every per-base policy (dbf file, headword/gloss/body fields,
    # crosslink labels, reflex columns). P23-0 held that promise with four
    # measured exceptions, each the minimum: the second vendored conversion
    # table (chslav.lst — vasmer's OCS font range; StarlingText loads a table
    # LIST now), the duplicate-NUMBER suffix above (which also unblocks
    # piet's own #574 collision — the owner's live quarantine), the
    # "#NUMBER" placeholder for headword-less records (piet 6 / germet 6 /
    # baltet 7, censused — the second whole-file quarantine class), and the
    # censused STOP_TOKENS gate below.
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
    # == The reflex verdict (censused fixture-first; journaled P22-0/P23-0)
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
    # P23-0 extends the same discipline: germet's per-language columns are
    # the piet single-language shape and 19 of 21 mint (GOT joins the got
    # gold, OENGL the ang gold; the rest speak the Wiktionary codes the
    # kaikki crosswalk speaks). Bare dialect/variety LABELS lead ~75 cells
    # (CrimGot ×7, NIsl ×20, OGutn ×13, OWFris ×15 …) without the period
    # that self-filtered piet's "Khow." — the censused STOP_TOKENS list
    # gates them (zero piet/pokorny drift, measured). EASTFRIS and OLFRANK
    # stay body-only: variety-ambiguous columns (Fris/WFris/ONFrank/
    # SalFrank label mixes; EASTFRIS is ~47% label-led) — minting would
    # invent language codes. baltet's OLITH/LITH/LETT/OPRUS all mint
    # (96%+ clean, measured); vasmer mints nothing (prose fields only).
    #
    # == Encoding
    #
    # dBase III tables + StarLing-encoded .var text (starling-dbf family:
    # StarlingDbfParser + the table-driven StarlingText decoder; byte
    # meanings come from the vendored unipro.lst + chslav.lst, never
    # guessed — see config/starling/README.md and the fixture README for
    # the live-web verification of every fixture record).
    class Starling < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "starling",
        name: "StarLing / Tower of Babel — Indo-European etymological databases " \
              "(Pokorny IEW + PIET + Vasmer + Germanic + Baltic)",
        license: "Free for any use with acknowledgment (G. Starostin, e-mail 2026-07-15: \"all " \
                 "etymological data are free for anybody to use for any purposes as long as the " \
                 "source is properly acknowledged\"); required per-base credit — Pokorny base: " \
                 "\"scanned and recognized by George Starostin (Moscow), who has also added the " \
                 "English meanings\", \"further refurnished and corrected by A. Lubotsky\"; PIE " \
                 "base: \"compiled on the basis of Walde-Pokorny's dictionary by S. L. Nikolayev\", " \
                 "Hittite and Tokharian reflexes added by S. Starostin; Vasmer base: \"scanned, " \
                 "OCR'd, and database-converted versions of M. Vasmer's etymological dictionary of " \
                 "Russian\" (project roster); Germanic base: \"The Common Germanic database, " \
                 "compiled by S. Nikolayev and subordinate to the Common Indo-European database\"; " \
                 "Baltic base: \"The Baltic database, compiled by S. Nikolayev and subordinate to " \
                 "the Proto-Indo-European database\"",
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
        }.freeze,
        # P23-0. vasmer.inf is BLANK: labels are the live CGI's own field
        # labels (web-verified on #20, 2026-07-15); prose fields, no reflex
        # columns, no numeric links (the shelf is piet's SLAVNUM target).
        "starling-vasmer" => {
          dbf: "vasmer.dbf", language: "rus",
          title: "Vasmer's dictionary (M. Vasmer, Russian etymological dictionary, Trubachev edition; " \
                 "StarLing scan/OCR digitization)",
          headword: "WORD", gloss: nil,
          body: {
            "GENERAL" => "Near etymology", "ORIGIN" => "Further etymology",
            "TRUBACHEV" => "Trubachev's comments", "EDITORIAL" => "Editorial comments",
            "PAGES" => "Pages"
          }.freeze,
          crosslinks: {}.freeze,
          reflexes: {}.freeze
        }.freeze,
        # P23-0. Labels/credit: germet.inf. Reflex codes: got/ang are this
        # catalog's gold tags; the rest are the Wiktionary codes the kaikki
        # crosswalk speaks. EASTFRIS/OLFRANK body-only (variety-ambiguous).
        "starling-germet" => {
          dbf: "germet.dbf", language: "gem-pro",
          title: "Germanic etymology (Common Germanic database: S. Nikolayev, " \
                 "subordinate to the PIE database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "GOT" => "Gothic", "ONORD" => "Old Norse", "NORW" => "Norwegian",
            "OSWED" => "Old Swedish", "SWED" => "Swedish", "ODAN" => "Old Danish",
            "DAN" => "Danish", "OENGL" => "Old English", "MENGL" => "Middle English",
            "ENGL" => "English", "OFRIS" => "Old Frisian", "EASTFRIS" => "East Frisian",
            "OSAX" => "Old Saxon", "MDUTCH" => "Middle Dutch", "DUTCH" => "Dutch",
            "OLFRANK" => "Old Franconian", "MLG" => "Middle Low German",
            "LG" => "Low German", "OHG" => "Old High German",
            "MHG" => "Middle High German", "HG" => "German", "NOTES" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "IE etymology" }.freeze,
          reflexes: {
            "GOT" => %w[got Gothic].freeze, "ONORD" => ["non", "Old Norse"].freeze,
            "NORW" => %w[no Norwegian].freeze, "OSWED" => ["gmq-osw", "Old Swedish"].freeze,
            "SWED" => %w[sv Swedish].freeze, "ODAN" => ["gmq-oda", "Old Danish"].freeze,
            "DAN" => %w[da Danish].freeze, "OENGL" => ["ang", "Old English"].freeze,
            "MENGL" => ["enm", "Middle English"].freeze, "ENGL" => %w[en English].freeze,
            "OFRIS" => ["ofs", "Old Frisian"].freeze, "OSAX" => ["osx", "Old Saxon"].freeze,
            "MDUTCH" => ["dum", "Middle Dutch"].freeze, "DUTCH" => %w[nl Dutch].freeze,
            "MLG" => ["gml", "Middle Low German"].freeze, "LG" => ["nds", "Low German"].freeze,
            "OHG" => ["goh", "Old High German"].freeze,
            "MHG" => ["gmh", "Middle High German"].freeze, "HG" => %w[de German].freeze
          }.freeze
        }.freeze,
        # P23-0. Labels/credit: baltet.inf (PRNUM's alias there is the long
        # form, "Indo-European etymology" — the live CGI renders the same).
        "starling-baltet" => {
          dbf: "baltet.dbf", language: "bat-pro",
          title: "Baltic etymology (Baltic database: S. Nikolayev, subordinate to the PIE database)",
          headword: "PROTO", gloss: "MEANING",
          body: {
            "OLITH" => "Old Lithuanian", "LITH" => "Lithuanian", "LETT" => "Lettish",
            "OPRUS" => "Old Prussian", "NOTES" => "Comments"
          }.freeze,
          crosslinks: { "PRNUM" => "Indo-European etymology" }.freeze,
          reflexes: {
            "OLITH" => ["olt", "Old Lithuanian"].freeze, "LITH" => %w[lt Lithuanian].freeze,
            "LETT" => %w[lv Lettish].freeze, "OPRUS" => ["prg", "Old Prussian"].freeze
          }.freeze
        }.freeze
      }.freeze

      # A clean leading citation form: letters first, then letters/marks and
      # the notation the bases use inside forms (optional-segment parens,
      # morpheme hyphens/equals, variant slashes, apostrophe palatals) — and
      # never a trailing period (that is an abbreviation, not a form).
      CITATION_FORM = %r{\A\*?[\p{L}\p{M}][\p{L}\p{M}'’\-/=()\[\]]*\z}
      private_constant :CITATION_FORM

      # The censused dialect/variety LABELS that lead germet cells without
      # the abbreviating period (piet's "Khow." self-filtered; "CrimGot
      # marzus" would sail through CITATION_FORM). A cell led by one of
      # these mints nothing — the label is not a citation form. Every token
      # was censused over the full 2005 corpus (P23-0): Crimean Gothic /
      # Burgundian / Latin-attested leads in GOT; New Icelandic / North
      # Germanic / Old Norwegian in ONORD; Old Gutnish ("Outn" is its
      # upstream typo) / Middle Swedish / runic / personal-name leads in
      # OSWED-ODAN-SWED; West/East Old Frisian in OFRIS; Old Low German /
      # Middle Low German leads in MLG; Early Middle Dutch in MDUTCH;
      # Langobardic / "Lat-OHG" / name-label "N" in OHG; Early High German
      # in MHG; lowercase "dial" in SWED. Zero collisions with a legitimate
      # leading citation form anywhere in the package, and zero piet/pokorny
      # drift — both measured.
      STOP_TOKENS = %w[
        CrimGot Burg Burgund Lat NIsl NGerm ONorw OGutn Outn MSw Run PN ON
        dial OWFris OWFRis OFr OEFRis OEFris Fris OLG MLG EMDutch EaHG
        Langob Lat-OHG N
      ].to_set.freeze
      private_constant :STOP_TOKENS

      # The rider (P18 strategy): what this source witnesses about each
      # shelf language, accreted as dossier sections with per-record
      # provenance "starling".
      LANGUAGE_NOTES = [
        ["ine-pro", "witness:starling",
         "StarLing/Tower of Babel IE bases (G. Starostin's 2026-07-15 any-use-with-acknowledgment " \
         "grant): Pokorny's IEW complete (2,222 roots, the G. Starostin-scanned, Lubotsky-corrected " \
         "digitization) beside S. L. Nikolayev's Walde-Pokorny-based PIE database (3,291 " \
         "etymologies, traditional laryngeal-free notation, per-branch reflex columns with " \
         "S. Starostin's Hittite/Tocharian additions) — Moscow-school witnesses beside " \
         "kaikki/LIV/IE-CoR, expressly \"individual reconstructions\" that \"do not always " \
         "represent the most up-to-date, or the most 'consensus-approved' versions\" (Starostin)."].freeze,
        ["rus", "witness:starling",
         "StarLing/Tower of Babel Vasmer base (same grant): M. Vasmer's etymological dictionary " \
         "of Russian in the Trubachev Russian edition — 18,239 entries scanned, OCR'd and " \
         "database-converted by the project, with Trubachev's bracketed additions and editorial " \
         "comments as separate fields; the roster notes it \"currently serving as a substitute " \
         "for the comparative Slavic database\", and PIET's Slavic links point into it. Old " \
         "Cyrillic citations ride the Church Slavonic font range (decoded via chslav.lst)."].freeze,
        ["gem-pro", "witness:starling",
         "StarLing/Tower of Babel Common Germanic database (S. Nikolayev; same grant): 1,994 " \
         "Proto-Germanic etymologies in Nikolayev notation (*xálsa-z), subordinate to the PIE " \
         "database, with per-language columns from Gothic and Old Norse to modern German — a " \
         "Moscow-school gem-pro witness beside the kaikki Proto-Germanic shelf; Gothic and Old " \
         "English columns join this catalog's got/ang gold lemmas."].freeze,
        ["bat-pro", "witness:starling",
         "StarLing/Tower of Babel Baltic database (S. Nikolayev; same grant): 1,651 Proto-Baltic " \
         "etymologies subordinate to the PIE database, with Old Lithuanian/Lithuanian/Lettish/" \
         "Old Prussian reflex columns — this library's first Proto-Baltic shelf. The tag bat-pro " \
         "is minted by the family-code + -pro convention (Wiktionary reconstructs Balto-Slavic, " \
         "ine-bsl-pro, not Proto-Baltic — no upstream shelf to unify with)."].freeze
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
        seen = Hash.new(0)
        StarlingDbfParser.new(dbf_path: document_ref.path).each_record do |record|
          document << build_entry(base, record, seen)
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

      def build_entry(base, record, seen)
        number = record.fetch("NUMBER").to_s.strip
        raise Nabu::ParseError, "starling: #{base.fetch(:dbf)}: record without a NUMBER" if number.empty?

        entry_id = entry_id_for(base, number, seen[number] += 1)
        # Headword-less records are upstream reality (P23-0 census: piet 6 —
        # content-bearing Iranian stubs at the file tail the live CGI cannot
        # even serve — germet 6 / baltet 7 empty numbered slots; pokorny/
        # vasmer 0): they keep their slot under the mechanical "#NUMBER"
        # placeholder (the crosslink notation), so links pointing at those
        # numbers resolve and nothing upstream is hidden.
        key_raw = presence(record.fetch(base.fetch(:headword))) || "##{number}"
        headword = key_raw.delete_prefix("*").strip
        gloss = (field = base.fetch(:gloss)) && presence(record[field])
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: key_raw, language: base.fetch(:language),
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: fold_root(headword, base.fetch(:language)) || number,
          gloss: gloss && Nabu::Normalize.nfc(gloss),
          body: body_text(base, record, key_raw, collision_note(base, number, entry_id)),
          reflexes: build_reflexes(base, record)
        )
      end

      # Upstream NUMBER collisions, kept honest (P23-0 census: piet ×1 —
      # the owner's live quarantine, #574 twice, the second sitting where
      # the vacant 1574 belongs; baltet ×6; pokorny/vasmer/germet ×0): the
      # first record in file order keeps the plain NUMBER as its entry id —
      # so upstream "#NUMBER" crosslinks resolve to the first occurrence —
      # and each later collision mints a stable file-order suffix (-b, -c…).
      # File order is frozen with the 2005 package, so urns stay frozen;
      # upstream bytes are never renumbered (canonical means canonical).
      def entry_id_for(base, number, occurrence)
        return number if occurrence == 1

        suffixed = "#{number}-#{('a'.ord + occurrence - 1).chr}"
        unless occurrence <= 26
          raise Nabu::ParseError, "starling: #{base.fetch(:dbf)}: NUMBER #{number} repeats #{occurrence} times"
        end

        suffixed
      end

      # The honest note a suffixed entry carries in its body (nil on the
      # plain-id record): the collision is upstream's, the disambiguation
      # mechanical, the bytes untouched.
      def collision_note(base, number, entry_id)
        return nil if entry_id == number

        "note: upstream NUMBER collision — this record shares NUMBER #{number} with an earlier " \
          "record in #{base.fetch(:dbf)}; entry id disambiguated mechanically as #{entry_id} " \
          "(upstream data never renumbered; \"##{number}\" crosslinks resolve to the first occurrence)."
      end

      # Labeled body lines, upstream .inf aliases, non-empty fields only,
      # crosslink lines last ("Pokorny: #1089" — the number IS the target
      # shelf's entry id), then the collision note when one applies. Every
      # branch column rides here verbatim, whether or not it also minted a
      # reflex row.
      def body_text(base, record, fallback, note)
        lines = base.fetch(:body).filter_map do |field, label|
          value = presence(record[field])
          "#{label}: #{value}" if value
        end
        lines += base.fetch(:crosslinks).filter_map do |field, label|
          number = record[field].to_s.strip
          "#{label}: ##{number}" unless number.empty? || number == "0"
        end
        lines << note if note
        Nabu::Normalize.nfc(lines.empty? ? fallback : lines.join("\n"))
      end

      # The verdict's honest slice: one row per single-language branch cell
      # whose LEADING token is a clean citation form — and not one of the
      # censused bare dialect/variety labels (STOP_TOKENS); everything else
      # stays body-only (see the class comment).
      def build_reflexes(base, record)
        base.fetch(:reflexes).filter_map do |column, (language, name)|
          cell = presence(record[column]) or next
          word = cell.split(/[\s,]/).first.to_s
          next unless word.match?(CITATION_FORM)
          next if STOP_TOKENS.include?(word)

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
