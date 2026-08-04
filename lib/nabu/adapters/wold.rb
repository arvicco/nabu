# frozen_string_literal: true

require "csv"
require "digest"

require_relative "../normalize"

module Nabu
  module Adapters
    # WOLD — the World Loanword Database (Haspelmath & Tadmor eds. 2009,
    # MPI-EVA; the lexibank CLDF edition, P46-6): 41 expert-curated
    # vocabularies × 1,814 meanings, 64,289 lexemes EACH carrying a curated
    # five-point borrowed status, plus 21,624 borrowing events naming the
    # donor languoid and (for 20,625 of them) the donor word itself. The
    # etym desk's structured loanword-FLOW layer: IE-CoR flags borrowed
    # cognate-set members, WOLD states who lent what to whom, word by word.
    #
    # == Surface: one dictionary shelf per vocabulary (the starling shape)
    #
    # One source (wold), 41 dictionary slugs (wold-english,
    # wold-oldhighgerman, …), each shelf in ITS vocabulary's language so
    # headword folding uses the right rules. One entry per FORM row
    # (entry_id = the upstream form ID, e.g. "English-5-92-1" — stable,
    # verbatim), headword = the lexeme, gloss = the WOLD meaning label,
    # body = the curated apparatus (borrowed status, age, contact
    # situation, comments, loan lines). Every lexeme mints an entry — the
    # per-word borrowed STATUS on unborrowed words is half the dataset's
    # value (English "world": "5. no evidence for borrowing").
    #
    # == Donor edges (the reflex verdict)
    #
    # Each borrowing event with a Source_word mints ONE DictionaryReflex,
    # borrowed: true — the donor side is where this library's held
    # languages live (Latin 949 events incl. Late/Neo-Latin, Sanskrit 613,
    # Classical Arabic 568, Old Chinese 208, Old Norse 67, Old French 67,
    # Anglo-Norman 134 — censused v4.2). So `etym vinum` walks from the
    # Latin gold side to English "wine" through the donor fold.
    #
    # DONOR_MAP keys on the curated languoid NAME, never the glottocode:
    # WOLD's donor glottocodes are demonstrably unreliable — its "Old
    # Norse" carries noon1243, which Glottolog resolves to Noone
    # (Atlantic-Congo, Cameroon); real Old Norse is oldn1244 (P46-6
    # scouting find, pinned in test/cldf_spine_test.rb). P57-5's hand-check
    # confirmed which side is wrong: every noon1243 row's Source_word is a
    # genuine Old Norse form (ský "cloud", lágr "low", hvirfla "to whirl",
    # húsbondi "husband", systir "sister") — upstream's NAME is right, its
    # GLOTTOCODE is wrong, so name-based resolution stays authoritative and
    # ALWAYS wins over the glottocode (see GLOTTOCODE_LANGUAGES below,
    # which deliberately excludes noon1243).
    #
    # P57-5: lang_code is now the RESOLVED catalog tag (it used to leak the
    # raw upstream glottocode, or the bare donor name for the ~72 rows with
    # no glottocode at all, straight into lang_code — 96 glottocodes + 2
    # verbal labels censused). Resolution order: DONOR_MAP by name, then
    # GLOTTOCODE_LANGUAGES by glottocode (a mechanical join against the
    # vendored Glottolog CLDF dump, canonical/cldf-spine/glottolog/
    # languages.csv — the same file Nabu::CldfSpine reads at query time;
    # not wired to CldfSpine itself here, since #parse has no config/spine
    # dependency and this table only needs 96 specific rows, not the whole
    # 27k-row spine), then `und` — never nil. The original upstream name or
    # (failing that) glottocode always still rides lang_name, so nothing
    # identifying is lost even when the language itself is `und`.
    #
    # Comma-multiform donor words ("asinus, asellus") split into one edge
    # per variant ONLY when every part is word-shaped; "elephas, -ntos"
    # stays one verbatim edge — splitting would mint the bare inflection
    # tail "-ntos" as a word.
    #
    # == Upstream artifact: the Zenodo versioned record (the iecor posture)
    #
    # 10.5281/zenodo.21415389 = lexibank/wold v4.2 — one immutable 16 MB
    # zip, ZipFetch + a hard sha256 pin (RELEASE_SHA256, verified against
    # the fresh 2026-07-26 download AND Zenodo's published md5
    # 841e4f39fb64b7486fe29b1802c8f087). A future release is a NEW DOI:
    # the owner re-pins URL + sha and re-syncs. sync_policy: manual.
    #
    # == License (verified 2026-07-26)
    #
    # cldf/README.md verbatim: "This dataset is licensed under a CC-BY-4.0
    # license"; the Zenodo record declares cc-by-4.0 → attribution. Cite:
    # Haspelmath, Martin & Tadmor, Uri (eds.) 2009, World Loanword
    # Database, MPI-EVA (wold.clld.org); per-vocabulary contributor
    # citations ride each shelf's title.
    class Wold < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "wold",
        name: "WOLD — World Loanword Database (Haspelmath & Tadmor eds.; lexibank/wold v4.2)",
        license: "CC BY 4.0 (cldf/README.md verbatim: \"This dataset is licensed under a CC-BY-4.0 " \
                 "license\"; Zenodo record cc-by-4.0; cite Haspelmath, Martin & Tadmor, Uri (eds.) " \
                 "2009, World Loanword Database, Leipzig: MPI-EVA — per-vocabulary contributor " \
                 "citations ride each shelf's title)",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/records/21415389",
        parser_family: "cldf-csv"
      )

      # The immutable versioned artifact (10.5281/zenodo.21415389 = v4.2;
      # concept DOI 10.5281/zenodo.1299889 always resolves to latest).
      ZENODO_ZIP_URL = "https://zenodo.org/records/21415389/files/lexibank/wold-v4.2.zip?download=1"

      # sha256 of the release zip, pinned from the 2026-07-26 download (md5
      # cross-checked against Zenodo's 841e4f39fb64b7486fe29b1802c8f087).
      RELEASE_SHA256 = "ada4e5a4e20bfcd3afe253e602b8bb8eb353521f5785d92136cf56ad166cda3c"

      CLDF_DIR = "cldf"
      ANCHOR_FILE = "forms.csv"

      # A word-shaped donor part LEADS with a word character (letter/mark,
      # optional paren or asterisk) — the comma-split guard's criterion
      # ("elephas, -ntos" fails it and stays one verbatim edge).
      WORD_SHAPED = /\A[(*]*[\p{L}\p{M}]/

      # The three vocabularies whose ISO639P3code column is BLANK upstream
      # (censused v4.2); every other vocabulary passes its ISO code through.
      # SeliceRomani has no ISO of its own — rmy (Vlax Romani, its Glottolog
      # parent language) is the honest nearest tag.
      VOCAB_TAG_MAP = {
        "OldHighGerman" => "goh",
        "Sakha" => "sah",
        "SeliceRomani" => "rmy"
      }.freeze

      # Donor languoid NAME → catalog tag (see the class note for why this
      # always wins over the glottocode). Censused v4.2, held-relevant
      # donors plus a couple P57-5 additions where the NAME alone is
      # unambiguous enough not to need the glottocode table at all
      # ("Nepali" — its glottocode, nepa1252, isn't even in the vendored
      # Glottolog dump). Everything else falls through to
      # GLOTTOCODE_LANGUAGES, then `und` (P57-5 — never nil, see #parse).
      DONOR_MAP = {
        "Latin" => "lat", "Late Latin" => "lat", "Neo-Latin" => "lat",
        "Sanskrit" => "san", "Old Norse" => "non", "Old French" => "fro",
        "French (Anglo-Norman)" => "xno", "Old Chinese" => "och",
        "Classical Greek" => "grc", "Arabic" => "ara", "Classical Arabic" => "ara",
        "Standard Arabic" => "ara", "Russian" => "rus", "Persian" => "fas",
        "Middle Low German" => "gml", "Middle High German" => "gmh",
        "Nepali" => "nep"
      }.freeze

      # Donor languoid GLOTTOCODE → catalog tag (P57-5, fallback only —
      # #resolved_donor_language always tries DONOR_MAP by name first).
      # Every value here is read directly off the vendored Glottolog CLDF
      # dump (canonical/cldf-spine/glottolog/languages.csv — the ISO
      # 639-3 ISO639P3code column, or for dialect-level rows with none of
      # their own, Closest_ISO369P3code: e.g. late1252 "Late Latin" → lat).
      # A mechanical join, never a guess. Family-level glottocodes map to
      # an ISO 639-5 collective ONLY when confident (ine, sla, gem, trk,
      # gmq, xgn, bnt, sit, aav, que); the rest — WOLD's own donor labels
      # in comments — map honestly to `und` rather than invent a code:
      #   finn1317 "Fennic" (narrower than any ISO 639-5 collective I know)
      #   mala1545 "Proto-Malayo-Polynesian" (a reconstruction stage, not
      #     just a family — no ISO 639-5 code fits)
      #   yuca1252 "Yucatecan" (a Mayan sub-branch narrower than myn)
      #   gbee1241 "Gbe" (no dedicated ISO 639-5 collective)
      #   high1289 "Early New High German" (a historical stage between
      #     gmh and deu with no ISO code of its own)
      #   east2832 "East Middle German" (a dialect grouping, same story)
      #
      # noon1243 is deliberately ABSENT (the P57-5 hand-check, class note):
      # WOLD's own name "Old Norse" is right and its glottocode is wrong,
      # so this fallback must never get a chance to mis-resolve it to
      # Glottolog's noon1243 = Noone.
      GLOTTOCODE_LANGUAGES = {
        "stan1288" => "spa", "mand1415" => "cmn", "stan1318" => "ara",
        "stan1290" => "fra", "stan1293" => "eng", "lati1261" => "lat",
        "hung1274" => "hun", "russ1263" => "rus", "moro1292" => "ary",
        "sans1269" => "san", "arab1395" => "ara", "stan1306" => "zsm",
        "port1283" => "por", "mong1329" => "xgn", "avar1256" => "ava",
        "dutc1256" => "nld", "stan1295" => "deu", "oldc1244" => "och",
        "slav1255" => "sla", "tokp1240" => "tpi", "mode1248" => "ell",
        "sran1240" => "srn", "west2369" => "pes", "djam1255" => "djd",
        "java1254" => "jav", "midd1344" => "ltc", "swah1253" => "swh",
        "bulg1262" => "bul", "angl1258" => "xno", "serb1264" => "srp",
        "miri1266" => "mep", "urdu1245" => "urd", "sund1252" => "sun",
        "amha1245" => "amh", "haus1257" => "hau", "kons1243" => "kxc",
        "ital1282" => "ita", "ward1246" => "wrr", "chol1282" => "ctu",
        "jaru1254" => "ddj", "slov1269" => "slk", "nucl1302" => "kat",
        "cent2050" => "knc", "laoo1244" => "lao", "nort3160" => "gmq",
        "finn1317" => "und", "cent1989" => "khm", "oldf1239" => "fro",
        "aust1305" => "aav", "late1252" => "lat",
        "croa1245" => "hrv", "czec1258" => "ces", "tuca1252" => "tuo",
        "quec1387" => "que", "bali1278" => "ban", "pali1273" => "pli",
        "mala1545" => "und", "uppe1395" => "hsb", "indo1319" => "ine",
        "turk1311" => "trk", "kare1335" => "krl", "nucl1301" => "tur",
        "germ1287" => "gem", "yuca1252" => "und", "daur1238" => "dta",
        "tosk1239" => "als", "ngal1294" => "djd", "halh1238" => "khk",
        "vili1238" => "vif", "midd1318" => "gml", "plat1254" => "plt",
        "guia1246" => "gcr", "barg1252" => "mlp", "gbee1241" => "und",
        "high1289" => "und", "mace1250" => "mkd", "bant1294" => "bnt",
        "sino1245" => "sit", "slov1268" => "slv", "azte1234" => "nah",
        "midd1343" => "gmh", "nucl1736" => "orm", "tama1365" => "taq",
        "even1259" => "evn", "lakk1252" => "lbe", "tami1289" => "tam",
        "mudb1240" => "dmw", "minn1241" => "nan", "nort2697" => "azj",
        "djin1251" => "jig", "east2832" => "und", "kawi1241" => "kaw",
        "kumy1244" => "kum", "oldh1241" => "goh"
      }.freeze

      # Labeled body lanes, curated (upstream column => label), rendered in
      # this order after the concept and status lines.
      BODY_FIELDS = {
        "Comment" => "comment",
        "comment_on_word_form" => "comment on word form",
        "original_script" => "original script",
        "comment_on_borrowed" => "comment on borrowing",
        "Age" => "age",
        "salience" => "salience",
        "effect" => "effect",
        "contact_situation" => "contact situation",
        "calqued" => "calqued",
        "grammatical_info" => "grammatical info",
        "etymological_note" => "etymological note",
        "lexical_stratum" => "lexical stratum"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # Donor edges mint reflex rows (health checks the promise, P18-7).
      def self.reflex_bearing? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "wold-v4.2.zip", zip_url: ZENODO_ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # +pin+ overrides the release sha (tests; a future owner re-pin drill).
      def initialize(pin: RELEASE_SHA256)
        super()
        @pin = pin
        @tables = {}
      end

      # One DocumentRef per vocabulary, languages.csv file order, all
      # pointing at the one CLDF table dir (located by its anchor table —
      # the iecor discovery shape). A workdir without the bundle yields
      # nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        anchor = Dir.glob(File.join(workdir, "**", CLDF_DIR, ANCHOR_FILE)).min
        return unless anchor

        dir = File.expand_path(File.dirname(anchor))
        tables(dir).fetch(:languages).each_value do |language|
          id = language.fetch("ID")
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "wold-#{id.downcase}:#{CLDF_DIR}",
            path: dir, metadata: { "vocabulary" => id }
          )
        end
      end

      def parse(document_ref)
        vocabulary = document_ref.metadata.fetch("vocabulary")
        all = tables(document_ref.path)
        language = all.fetch(:languages)[vocabulary] or
          raise Nabu::ParseError, "wold: #{document_ref.id}: vocabulary #{vocabulary.inspect} " \
                                  "missing from languages.csv"
        document = Nabu::DictionaryDocument.new(
          slug: "wold-#{vocabulary.downcase}", language: vocabulary_tag(language),
          title: vocabulary_title(vocabulary, all), canonical_path: document_ref.path
        )
        all.fetch(:forms).each do |form|
          next unless form.fetch("Language_ID") == vocabulary

          document << build_entry(form, all)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "wold: #{document_ref.id}: #{e.message}"
      end

      # ZipFetch with the phases driven by hand so the sha pin is checked
      # BETWEEN download and any tree mutation (the iecor choreography); a
      # 304 replays the stored pin and touches nothing.
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZENODO_ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "wold fetch failed into #{workdir}: #{e.message}"
      end

      private

      # -- tables (memoized per CLDF dir — 41 parses read one load) ---------------

      def tables(dir)
        @tables[dir] ||= {
          languages: csv_index(dir, "languages.csv"),
          parameters: csv_index(dir, "parameters.csv"),
          contributions: csv_rows(dir, "contributions.csv"),
          forms: csv_rows(dir, "forms.csv"),
          borrowings: csv_rows(dir, "borrowings.csv").group_by { |row| row.fetch("Target_Form_ID") }
        }
      end

      def csv_rows(dir, filename)
        path = File.join(dir, filename)
        return [] unless File.file?(path)

        CSV.read(path, headers: true, encoding: Encoding::UTF_8).map(&:to_h)
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "wold: malformed #{filename}: #{e.message}"
      end

      def csv_index(dir, filename)
        csv_rows(dir, filename).to_h { |row| [row.fetch("ID"), row] }
      end

      # -- the vocabulary shelf ---------------------------------------------------

      def vocabulary_tag(language)
        mapped = VOCAB_TAG_MAP[language.fetch("ID")]
        return mapped if mapped

        iso = language["ISO639P3code"].to_s
        return iso if iso.match?(Nabu::Model::Validation::LANGUAGE_SHAPE)

        raise Nabu::ParseError, "wold: vocabulary #{language.fetch('ID').inspect} has no usable " \
                                "language tag (blank ISO and no VOCAB_TAG_MAP row — census it)"
      end

      def vocabulary_title(vocabulary, all)
        contribution = all.fetch(:contributions).find { |row| row["Language_ID"] == vocabulary }
        name = contribution&.fetch("Name", nil) || "#{vocabulary} vocabulary"
        contributor = contribution && presence(contribution["Contributor"])
        credit = contributor ? " (#{contributor}; Haspelmath & Tadmor eds. 2009)" : ""
        "WOLD — #{name}#{credit}"
      end

      # -- entries ----------------------------------------------------------------

      def build_entry(form, all)
        language = vocabulary_tag(all.fetch(:languages).fetch(form.fetch("Language_ID")))
        headword = presence(form["Form"]) || presence(form["Value"]) || form.fetch("ID")
        events = all.fetch(:borrowings)[form.fetch("ID")] || []
        Nabu::DictionaryEntry.new(
          entry_id: form.fetch("ID"), key_raw: presence(form["Value"]) || headword,
          language: language,
          headword: Nabu::Normalize.nfc(headword),
          headword_folded: fold(headword, language) || form.fetch("ID"),
          gloss: gloss(form, all),
          body: body_text(form, events, all),
          reflexes: events.flat_map { |event| donor_reflexes(event) }
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "wold: form #{form['ID'].inspect}: #{e.message}"
      end

      def gloss(form, all)
        parameter = all.fetch(:parameters)[form.fetch("Parameter_ID")]
        name = parameter && presence(parameter["Name"])
        name && Nabu::Normalize.nfc(name)
      end

      def body_text(form, events, all)
        lines = [concept_line(form, all), status_line(form)]
        events.each { |event| lines << loan_line(event) }
        BODY_FIELDS.each do |field, label|
          value = presence(form[field])
          lines << "#{label}: #{value}" if value
        end
        Nabu::Normalize.nfc(lines.compact.join("\n"))
      end

      def concept_line(form, all)
        parameter = all.fetch(:parameters)[form.fetch("Parameter_ID")]
        return "concept: #{form.fetch('Parameter_ID')}" unless parameter

        concepticon = [parameter["Concepticon_ID"], parameter["Concepticon_Gloss"]]
                      .map { |part| presence(part) }.compact.join(" ")
        suffix = concepticon.empty? ? "" : " (Concepticon #{concepticon})"
        "concept: #{parameter['Name']}#{suffix}"
      end

      def status_line(form)
        status = presence(form["Borrowed"])
        status && "borrowed status: #{status}"
      end

      # "loan ← Latin vīnum ‘wine’ (earlier)" — languoid name + donor word
      # + its meaning, with the relation and uncertainty flags when curated.
      def loan_line(event)
        bits = ["loan ←", presence(event["Source_languoid"]) || "(unnamed source)",
                presence(event["Source_word"])]
        meaning = presence(event["Source_meaning"])
        bits << "‘#{meaning}’" if meaning
        line = bits.compact.join(" ")
        relation = presence(event["Source_relation"])
        line += " (#{relation})" if relation && relation != "immediate"
        line += " (uncertain)" if event["Source_certain"].to_s.strip.casecmp("no").zero?
        comment = presence(event["Comment"])
        line += " — #{comment}" if comment
        line
      end

      # -- donor edges ------------------------------------------------------------

      def donor_reflexes(event)
        word = presence(event["Source_word"]) or return []
        name = presence(event["Source_languoid"])
        glottocode = presence(event["Source_languoid_glottocode"])
        language = resolved_donor_language(name, glottocode)
        display = name || glottocode
        split_donor(word).map do |part|
          nfc = Nabu::Normalize.nfc(part)
          Nabu::DictionaryReflex.new(
            lang_code: language, language: language, word: nfc,
            word_folded: reflex_fold(nfc, language),
            borrowed: true, lang_name: display && Nabu::Normalize.nfc(display)
          )
        end
      end

      # P57-5 donor-language resolution, in priority order — the curated
      # NAME always wins (the noon1243 hand-check, class note): WOLD's
      # glottocodes are demonstrably unreliable even where the name is
      # completely unambiguous, so a glottocode match must never override
      # a trusted name. Falls through to the mechanical Glottolog join,
      # then to `und` — every donor edge now names a real (if
      # undetermined) catalog language; the original name/glottocode is
      # never lost, since it still rides lang_name (see #donor_reflexes).
      def resolved_donor_language(name, glottocode)
        (name && DONOR_MAP[name]) || (glottocode && GLOTTOCODE_LANGUAGES[glottocode]) || "und"
      end

      # Comma-variant split with the word-shape guard (class note): every
      # part must be word-shaped or the whole cell stays one verbatim edge.
      def split_donor(word)
        parts = word.split(/\s*,\s*/).map(&:strip).reject(&:empty?)
        return [word] unless parts.size > 1 && parts.all? { |part| part.match?(WORD_SHAPED) }

        parts
      end

      # Headword/donor folds: the iecor member rule — ?/* prefix and parens
      # off, trailing stem hyphen off, folded with the entry's language.
      def fold(text, language)
        cleaned = text.sub(/\A[?*\s]+/, "").delete("()⁽⁾").sub(/-\z/, "")
        folded = Nabu::Normalize.search_form(cleaned, language: language)
        folded.strip.empty? ? nil : folded
      end
      alias reflex_fold fold

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "wold: downloaded artifact misses the release sha256 pin (expected #{@pin}, got " \
              "#{fetch.sha}) — Zenodo records are immutable, so this is corruption or an " \
              "unannounced re-release; verify #{ZENODO_ZIP_URL} and re-pin RELEASE_SHA256 only " \
              "after reading the record"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "zenodo v4.2 sha pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
