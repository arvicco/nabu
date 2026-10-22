# frozen_string_literal: true

require "fileutils"
require "yaml"

module Nabu
  module Adapters
    # The etruscan-loans adapter: curated Etruscan → Latin loan edges — the
    # sabellic-loans recipe (the P17-3 `borrowed` pattern) for the library's
    # non-Indo-European donor, as one dictionary shelf (Etruscan ett), the
    # companion of the open-etruscan/larth-etp epigraphic witnesses: `nabu
    # etym persona` answers with 𐌘𐌄𐌓𐌔𐌖 and the edge's loan flag.
    #
    # == The curation (config/etruscan_loans.yml — the artifact itself)
    #
    # Curated 2026-10-22 from the en.wiktionary category pages ("Latin
    # terms borrowed from Etruscan" ×69 / "derived from Etruscan" ×200
    # pages, the borrowed set a subset of the derived one), member lists
    # via the MediaWiki API, each Latin entry's OWN etymology read for the
    # Etruscan etymon by Nabu::WiktionaryLoanCuration (its rules in that
    # class note): 199 Latin lemmas — 69 explicit borrowings mint
    # borrowed=true reflex edges, 130 derived-only lemmas borrowed=false
    # (the P17-3 no-marker semantics). Excluded and named in the config
    # header: Reconstruction:Latin/piltrum (not an attested lemma) and the
    # category's 4 subcategories. Etymon residue, declared row by row and
    # never dropped: 76 rows cite an Etruscan form (Old Italic script
    # verbatim — the U+10300 display note in docs/display.md applies), 119
    # name Etruscan but cite no form (`no_etymon: unstated` — mostly
    # gentilicia, toponyms and words whose Etruscan source is inferred), 4
    # carry no Etruscan etymology template at all (`no_etymon:
    # no-template` — membership inherited through another word's
    # etymology: titulo via titulus). Where no form is cited the LATIN
    # lemma stands as the headword and the body says which case it is.
    # The 2026-07-13 survey's census read 66/191; this is the fresh
    # curation at the retrieval date's counts.
    #
    # == Shape
    #
    # One DictionaryDocument: slug etruscan-ett (urn:nabu:dict:
    # etruscan-ett:<latin lemma>), entry per Latin lemma, one lat reflex
    # row each — the reflex-roots walk and `etym`/`cognates` read it with
    # no new query code. A split-page member ("a/languages A to L") rows
    # under its lemma, the page title in the body.
    #
    # == fetch / sync policy — a REPO-CURATED shelf
    #
    # No upstream and no network, ever: en.wiktionary is the cited
    # PROVENANCE, not a fetch target — re-curation is a deliberate repo
    # change. `Adapter#fetch` (the one sanctioned canonical writer)
    # materializes the vendored file under canonical/etruscan-loans/
    # (tmp+rename, byte-identical copy), then the house LocalFetch scan
    # pins it — sync_policy frozen (the sabellic-loans posture).
    #
    # == License
    #
    # Wiktionary's dual grant (CC BY-SA + GFDL) → attribution.
    class EtruscanLoans < Nabu::Adapter
      CONFIG_PATH = File.expand_path("../../../config/etruscan_loans.yml", __dir__)
      FILENAME = "etruscan_loans.yml"
      SLUG = "etruscan-ett"
      LANGUAGE = "ett"
      NAME = "Etruscan"
      TITLE = "Etruscan loans — Etruscan → Latin (en.wiktionary curation)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "etruscan-loans",
        name: "Etruscan → Latin loans — en.wiktionary curation",
        license: "CC BY-SA + GFDL (the Wiktionary dual grant; curated word lists from the " \
                 "en.wiktionary 'Latin terms borrowed/derived from Etruscan' category pages, " \
                 "retrieved 2026-10-22)",
        license_class: "attribution",
        upstream_url: "https://en.wiktionary.org/wiki/Category:Latin_terms_derived_from_Etruscan",
        parser_family: "curated-yaml"
      )

      LANGUAGE_NOTES = [
        ["ett", "witness:etruscan-loans",
         "en.wiktionary loan curation (retrieved 2026-10-22): 199 Latin lemmas derived from " \
         "Etruscan, 69 of them explicit borrowings (Roma, atrium, Aulus, lucumo, tina…), 76 with " \
         "the Etruscan form cited (persona ← 𐌘𐌄𐌓𐌔𐌖) — Etruscan's lexical shadow in Latin, beside " \
         "the OpenEtruscan inscriptions."].freeze
      ].freeze

      NO_ETYMON = {
        "unstated" => "the entry names Etruscan as the source but cites no Etruscan form",
        "no-template" => "its Latin entry carries no Etruscan etymology template (the category " \
                         "membership comes through another word's etymology)"
      }.freeze

      def self.manifest = MANIFEST

      # No git upstream: config/etruscan_loans.yml IS the vendored artifact.
      def self.upstream_repo_urls = []

      def self.content_kind = :dictionary

      def self.language_notes = LANGUAGE_NOTES

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: MANIFEST.id, id: "#{SLUG}:#{FILENAME}",
          path: File.expand_path(path), metadata: { "dictionary" => SLUG }
        )
      end

      def parse(document_ref)
        data = read_config(document_ref.path)
        document = Nabu::DictionaryDocument.new(
          slug: SLUG, language: LANGUAGE, title: TITLE, canonical_path: document_ref.path
        )
        data.fetch("sources").fetch(LANGUAGE).fetch("words").each do |word|
          document << build_entry(word, retrieved: data.fetch("retrieved"))
        end
        document
      rescue Nabu::ValidationError, KeyError => e
        raise Nabu::ParseError, "etruscan-loans: #{document_ref.id}: #{e.message}"
      end

      # Materialize the vendored curation under canonical/ (tmp+rename,
      # write only when the bytes differ), then the LocalFetch pin.
      def fetch(workdir, progress: nil, force: false)
        FileUtils.mkdir_p(workdir)
        target = File.join(workdir, FILENAME)
        unless File.file?(target) && FileUtils.compare_file(CONFIG_PATH, target)
          progress&.call("Vendoring #{FILENAME}…\n")
          FileUtils.cp(CONFIG_PATH, "#{target}.tmp")
          File.rename("#{target}.tmp", target)
        end
        result = LocalFetch.sync!(dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), force: force)
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        repos: result.files.merge(result.vanished).transform_keys { |rel| "local:#{rel}" })
      rescue LocalFetch::Error => e
        raise FetchError, "#{manifest.id}: #{e.message}"
      end

      private

      def read_config(path)
        YAML.safe_load_file(path) || {}
      rescue Psych::SyntaxError => e
        raise Nabu::ParseError, "etruscan-loans: malformed YAML at #{path}: #{e.message}"
      end

      def build_entry(word, retrieved:)
        latin = Nabu::Normalize.nfc(word.fetch("latin"))
        etymon = word["etymon"] && Nabu::Normalize.nfc(word["etymon"])
        headword = etymon || latin
        borrowed = word.fetch("relation") == "borrowed"
        Nabu::DictionaryEntry.new(
          entry_id: latin, key_raw: latin, language: LANGUAGE,
          headword: headword, headword_folded: folded(headword, LANGUAGE) || latin.downcase,
          body: body_for(word, latin: latin, etymon: etymon, borrowed: borrowed, retrieved: retrieved),
          reflexes: [Nabu::DictionaryReflex.new(
            lang_code: "la", language: "lat", word: latin,
            word_folded: folded(latin, "lat"), borrowed: borrowed
          )]
        )
      end

      def folded(text, language)
        form = Nabu::Normalize.search_form(text.delete_prefix("*"), language: language)
        form.empty? ? nil : form
      end

      def body_for(word, latin:, etymon:, borrowed:, retrieved:)
        relation = borrowed ? "an explicit borrowing from" : "derived (transmission unspecified) from"
        origin = if etymon
                   translit = word["translit"] && Nabu::Normalize.nfc(word["translit"])
                   "#{NAME} #{etymon}#{" (#{translit})" if translit}"
                 else
                   "#{NAME} — no #{NAME} form is cited: #{NO_ETYMON.fetch(word.fetch('no_etymon'))}"
                 end
        page = word["page"] ? " (Wiktionary page \"#{word['page']}\")" : ""
        "Latin #{latin}#{page} is #{relation} #{origin}. Curated from the en.wiktionary category " \
          "\"Latin terms #{borrowed ? 'borrowed' : 'derived'} from #{NAME}\", retrieved #{retrieved}."
      end
    end
  end
end
