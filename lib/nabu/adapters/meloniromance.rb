# frozen_string_literal: true

require "csv"

require_relative "source_read"

module Nabu
  module Adapters
    # meloniromance — the lexibank CLDF edition (J.-M. List, maintainer) of
    # the Romance cognate dataset published with Meloni, Ravfogel &
    # Goldberg, "Ab Antiquo: Neural Proto-language Reconstruction" (NAACL
    # 2021): 5,419 expert cognate sets, each a Latin etymon with its
    # Romanian / French / Italian / Spanish / Portuguese reflexes — 21,350
    # forms (Latin 5,419 · ita 4,012 · spa 3,817 · por 3,442 · fra 3,154 ·
    # ron 1,506; census 2026-10-22), sets of 2–6, no singletons.
    #
    # == The seam: the IE-CoR dictionary-reflex shape, argued
    #
    # Cognate data enters this library one way: a dictionary shelf whose
    # entries carry DictionaryReflex rows (IE-CoR, the kaikki descendants
    # trees, DÉRom, the starling bases). The reflex-roots closure, `etym`,
    # `define`, `cognates` and MCP read those rows with no source-specific
    # code. So: ONE shelf (slug meloniromance), ONE entry per cognate set
    # (entry_id = upstream's Cognateset_ID verbatim — urn:nabu:dict:
    # meloniromance:<set>), headword = the set's Latin form, the Romance
    # members as reflex rows in upstream file order. Unlike IE-CoR the
    # root language never varies — every set has exactly one Latin form —
    # so the shelf is honestly `lat` (IE-CoR needed the `ine` collective).
    # A set without its Latin form is a ParseError (censused: none), never
    # a guessed headword.
    #
    # == The transcription caveat (stated, never fudged)
    #
    # Every form is BROAD IPA, automatically transcribed by the authors —
    # Latin with vowel length and accusative endings (aːbɪlɛm, albeːskɛrɛ),
    # Spanish -aβle, Portuguese ɐbʒũŋʒiɹ — not orthography. Folds run the
    # house search form (conventions §9) on the IPA as written, so the
    # shelf answers IPA lookups; joins to the orthographic gold lemmas are
    # expected near-zero and are not promised. The 5,419 placeholder
    # concepts (`concept_N`) carry no meaning, so entries have no gloss.
    # Upstream's Loan column is empty throughout: reflexes mint
    # borrowed false, relation nil (descendant rows, the IE-CoR rule).
    # Segments, graphemes and the expert-judgment columns (all "expert",
    # no doubt flags) have no home in the entry model and are dropped.
    #
    # == Grains
    #
    # The repository serves the CLDF wordlist (cldf/ — accepted, ONE
    # document) and raw/data.tsv, the pre-CLDF table the lexibank script
    # converts (same sets, a column per language) — skipped by rule and
    # counted; etc/ and the build script are machinery.
    #
    # == Upstream + fetch
    #
    # github.com/lexibank/meloniromance, rolling main (no tags, no GitHub
    # release, no Zenodo record at 2026-10-22; head 08f4ceec). The house
    # GitFetch of the repository (attic + breaker + ff-merge); sync_policy
    # manual.
    #
    # == License (verified 2026-10-22, four ways agreeing)
    #
    # The repository LICENSE (the CC BY 4.0 legal code), the GitHub
    # license field CC-BY-4.0, the README ("This dataset is licensed under
    # a CC-BY-4.0 license") and cldf-metadata.json's dc:license → attribution.
    # Provenance caveat: the authors' repository (shauli-ravfogel/
    # Latin-Reconstruction-NAACL) carries no license file; the grant is
    # the lexibank edition's. That README: the complete Ciobanu & Dinu-based
    # set "is not publicly available … Here, we publish the entires which
    # we added to the original dataset" — the 5,419 sets are those.
    class Meloniromance < Nabu::Adapter
      REPO_URL = "https://github.com/lexibank/meloniromance"

      MANIFEST = Nabu::SourceManifest.new(
        id: "meloniromance",
        name: "Meloni et al. 2021 Romance cognate sets (lexibank/meloniromance CLDF)",
        license: "CC BY 4.0 (README verbatim: \"This dataset is licensed under a CC-BY-4.0 license\"; " \
                 "cldf-metadata.json dc:license; cite Meloni, Ravfogel & Goldberg 2021, \"Ab Antiquo: " \
                 "Neural Proto-language Reconstruction\", NAACL-HLT 2021, pp. 4460–4473)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "cldf-csv"
      )

      DICTIONARY_SLUG = "meloniromance"
      LANGUAGE = "lat"
      TITLE = "Meloni et al. 2021 — Latin → Romance cognate sets (IPA)"
      CLDF_DIR = "cldf"
      ANCHOR_FILE = "forms.csv"
      RAW_TABLE = "raw/data.tsv"
      LATIN = "Latin"

      # Upstream variety id → catalog tag (the DÉRom ISO 639-3 spellings
      # for the same five languages).
      VARIETIES = {
        "Romanian" => "ron", "French" => "fra", "Italian" => "ita",
        "Spanish" => "spa", "Portuguese" => "por"
      }.freeze

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      # Members mint dictionary_reflexes rows (health holds the promise).
      def self.reflex_bearing? = true

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        anchor = Dir.glob(File.join(workdir, "**", CLDF_DIR, ANCHOR_FILE)).min
        return unless anchor

        yield Nabu::DocumentRef.new(
          source_id: MANIFEST.id, id: "#{DICTIONARY_SLUG}:#{CLDF_DIR}",
          path: File.expand_path(File.dirname(anchor)), metadata: {}
        )
      end

      def discovery_skips(workdir)
        raw = File.join(workdir, RAW_TABLE)
        return Nabu::Adapter::DiscoverySkips.new unless File.file?(raw)

        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: 1,
          notes: ["pre-CLDF raw table (the same sets, unconverted), not ingested: #{RAW_TABLE}"]
        )
      end

      def parse(document_ref)
        dir = document_ref.path
        forms = csv(dir, "forms.csv")
        languages = csv(dir, "languages.csv").to_h { |row| [row.fetch("ID"), row] }
        sets = Hash.new { |hash, key| hash[key] = [] }
        csv(dir, "cognates.csv").each { |row| sets[row.fetch("Cognateset_ID")] << row.fetch("Form_ID") }
        by_id = forms.to_h { |row| [row.fetch("ID"), row] }
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE, canonical_path: dir
        )
        sets.each do |set_id, form_ids|
          members = form_ids.map { |id| by_id.fetch(id) { raise Nabu::ParseError, "set #{set_id}: unknown form #{id}" } }
          document << build_entry(set_id, members, languages)
        end
        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "meloniromance: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      def csv(dir, filename)
        text = SourceRead.utf8_file(File.join(dir, filename), label: "meloniromance #{filename}")
        CSV.parse(text, headers: true).map(&:to_h)
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "meloniromance: malformed #{filename}: #{e.message}"
      end

      def build_entry(set_id, members, languages)
        latin, romance = members.partition { |form| form.fetch("Language_ID") == LATIN }
        raise Nabu::ParseError, "meloniromance: set #{set_id} carries no Latin form" if latin.empty?

        headword = form_text(latin.first)
        reflexes = romance.map { |form| build_reflex(form, languages) }
        Nabu::DictionaryEntry.new(
          entry_id: set_id, key_raw: headword, language: LANGUAGE,
          headword: headword, headword_folded: fold(headword, LANGUAGE) || set_id,
          body: body(set_id, headword, romance, languages), reflexes: reflexes
        )
      end

      def build_reflex(form, languages)
        variety = form.fetch("Language_ID")
        language = VARIETIES.fetch(variety) { raise Nabu::ParseError, "meloniromance: unmapped variety #{variety}" }
        word = form_text(form)
        Nabu::DictionaryReflex.new(
          lang_code: language, language: language, word: word,
          word_folded: fold(word, language), borrowed: false,
          lang_name: Nabu::Normalize.nfc(languages.fetch(variety).fetch("Name"))
        )
      end

      def form_text(form) = Nabu::Normalize.nfc(form.fetch("Form").strip)

      def fold(text, language)
        folded = Nabu::Normalize.search_form(text, language: language)
        folded.strip.empty? ? nil : folded
      end

      def body(set_id, headword, romance, languages)
        members = romance.map do |form|
          "#{languages.fetch(form.fetch('Language_ID')).fetch('Name')} #{form_text(form)}"
        end
        lines = ["Meloni et al. 2021 Romance cognate set #{set_id} (broad IPA, automatically transcribed; " \
                 "Latin with vowel length)",
                 "Latin #{headword} → #{members.join(' · ')}"]
        Nabu::Normalize.nfc(lines.join("\n"))
      end
    end
  end
end
