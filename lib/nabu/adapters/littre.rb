# frozen_string_literal: true

require_relative "littre_tei_parser"

module Nabu
  module Adapters
    # Littré: Émile Littré, Dictionnaire de la langue française (Hachette,
    # 1863–1872, with its 1877 supplement merged in) — the historical
    # dictionary of classical French, its citations drawn from the
    # 17th-century canon (Molière, Corneille, Racine, Bossuet, La
    # Fontaine) and its HISTORIQUE sections quoting the Old and Middle
    # French texts century by century. For the held French text
    # (theatre-classique's 17th-century stage, bfm's Old French).
    #
    # Stored language fra (theatre-classique's own tag; bare — the shelf's
    # object is literary French from the 17th century to Littré's own day,
    # deliberately not staged).
    #
    # == Upstream / grains (verified 2026-11-02)
    #
    # github.com/oeuvres/littre (pushed 2020-11-10): a TEI P5 conversion
    # of François Gannaz's XMLittré v1.3, plus a servlet application. The
    # xml/ directory serves:
    #
    # - a.xml … z.xml — the dictionary, one file per letter, ACCEPTED (one
    #   DictionaryDocument each, one shared shelf "littre");
    # - preface.html (Littré's preface) and causerie.html (his "Comment
    #   j'ai rédigé mon dictionnaire") — front matter prose, REJECTED by
    #   rule (not dictionary articles);
    # - test.tei — a 4-article test sample duplicating letter-file
    #   articles, REJECTED by rule;
    # - littre.rng, schema.html — the schema and its documentation, not
    #   data.
    #
    # Reconciliation (upstream advertises no total; census of the 26
    # files): 78,394 <entry> + 89 <entryFree> = 78,483 articles parsed
    # (one further <entry> sits inside an XML comment, an editor's
    # deletion — the survey's 78,484 tag-match count). Ids unique after
    # the parser's two rules (2 in-file repeats numbered, 4 off-letter
    # articles suffixed — LittreTeiParser note). Census through the house
    # parser: 793 glossless (citation-only articles), 76,634 with a
    # printed gram, 21,539 with a first-attested century (XVIe 8,603 ·
    # XIIIe 3,779 · XIVe 2,719 · XIIe 2,609 · XVe 2,279 · XIe 1,368 …).
    # Upstream caveat (XMLittré): the markup is imperfect and Greek
    # etymons are mostly absent — the text is carried as keyed.
    #
    # == License
    #
    # Every file's teiHeader <availability>, verbatim: "Licence Creative
    # Commons : Paternité – Partage des Conditions Initiales à l'Identique
    # – 2.0 France" (creativecommons.org/licenses/by-sa/2.0/fr/) … "En
    # adoptant une licence CreativeCommons by-sa, les contributeurs de ce
    # travail souhaitent que la ressource soit librement diffusée,
    # notamment pour la recherche." Read 2026-11-02 in xml/b.xml. The
    # 1863–1877 text is public domain by age → license_class
    # "attribution" (CC BY-SA on the digitization).
    class Littre < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "littre",
        name: "Littré, Dictionnaire de la langue française (1863–1877) — oeuvres/littre TEI",
        license: "CC BY-SA 2.0 FR (verbatim teiHeader: \"Licence Creative Commons : Paternité – Partage des " \
                 "Conditions Initiales à l'Identique – 2.0 France\"); XMLittré v1.3 (François Gannaz); " \
                 "the 1863–1877 text is public domain",
        license_class: "attribution",
        upstream_url: "https://github.com/oeuvres/littre",
        parser_family: "littre-tei"
      )

      DICTIONARY_SLUG = "littre"
      TITLE = "Littré, Dictionnaire de la langue française (1863–1877)"
      REJECTED_PATHS = {
        "xml/preface.html" => "Littré's preface — front-matter prose, not dictionary articles",
        "xml/causerie.html" => "Littré's causerie on writing the dictionary — front-matter prose",
        "xml/test.tei" => "a 4-article test sample duplicating letter-file articles"
      }.freeze

      def self.manifest = MANIFEST

      # Entries, not passages — SyncRunner/Rebuild load through
      # Store::DictionaryLoader (architecture §11).
      def self.content_kind = :dictionary

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ("a".."z").each do |letter|
          path = File.join(workdir, "xml", "#{letter}.xml")
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{letter}.xml",
            path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG, "letter" => letter }
          )
        end
      end

      def discovery_skips(workdir)
        present = REJECTED_PATHS.select { |rel, _| File.file?(File.join(workdir, rel)) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: present.size,
          notes: present.map { |rel, why| "#{rel}: skipped by rule — #{why}" }
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LittreTeiParser::LANGUAGE, title: TITLE,
          canonical_path: document_ref.path
        )
        LittreTeiParser.new.entries(document_ref.path, letter: document_ref.metadata.fetch("letter"))
                       .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "littre: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # Split out so fetch tests can point a singleton at a local git tmpdir.
      def repo_url = manifest.upstream_url
    end
  end
end
