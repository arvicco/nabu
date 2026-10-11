# frozen_string_literal: true

require "json"
require_relative "ticha_tei_parser"

module Nabu
  module Adapters
    # ticha — the Ticha project's TEI transcriptions of colonial Valley
    # Zapotec texts (Haverford College Digital Scholarship;
    # github.com/HCDigitalScholarship/ticha-xml-tei; P117-5). The library's
    # first American source: four printed and manuscript works of the
    # Dominican Zapotec tradition plus the project's manuscript
    # transcriptions — most of them the period SPANISH TRANSLATIONS of
    # Zapotec testaments and bills of sale, made by the colonial
    # interpreters.
    #
    # == Shape (censused 2026-10-11 @ 2d6af302, the repo's 2022-03-10 HEAD)
    #
    # 97 XML files: cordova-arte/ (Juan de Córdova, Arte en lengua
    # zapoteca, México 1578 — the one file with a teiHeader), aguero-
    # miscelaneo/ (Cristóbal de Agüero, Miscelaneo espiritual en el idioma
    # zapoteco, México 1666), levanto-arte/ (an Arte de lengua zapoteca —
    # the file carries no date or imprint), levanto-cathecismo/ (Leonardo
    # Levanto's Cathecismo de la lengua zaapoteca, reprinted Puebla 1766),
    # Te744/ (the 1744 San Sebastián Teitipac testament in Zapotec) +
    # Te744T/ (its Spanish translation), and manuscripts/encoded/ (89
    # files). Ticha's manuscript ids are <town code><year − 1000>[letter]
    # [T]: Al642T = San Pedro el Alto, 1642, the T marking the Spanish
    # translation (the Teitipac file comments say so for Te744/Te744T).
    #
    # Discovery yields 93 documents. Skipped by rule (counted, never
    # silent): schema/ (the TEI customization), cordova-arte/transform/
    # (a FLEx-export HTML table, not TEI), "Tl675T_example doc.xml" (an
    # encoding example), and manuscripts/encoded/Te744T.xml — superseded
    # by the cleaner re-encoding Te744T/Te744T.xml (a stem present both
    # as a work directory and under manuscripts/encoded/ keeps the work
    # directory's file; the two encodings share one Ticha id).
    #
    # Census (the 93 documents): 1,103 pages carrying text; 272,531 words
    # of the original-reading layer — 126,543 Zapotec (111,036 of them
    # Agüero's Miscelaneo, 9,586 Córdova's marked forms, 4,181 Levanto's
    # Arte, 825 the Cathecismo, 915 the 1744 testament), 143,212 Spanish,
    # 2,758 Latin, 18 Nahuatl (Córdova).
    #
    # == Language and text role, per document
    #
    # The encoding marks the non-default language; the unmarked default is
    # declared per file (UNMARKED_ZAPOTEC: Agüero's Miscelaneo and the 1744
    # testament; everything else Spanish-unmarked). Document.language and
    # each Passage.language are the MAJORITY language by word count over
    # the original-reading layer (so Córdova and Levanto read spa, with
    # their Zapotec as foreign spans + a per-page "languages" census;
    # Agüero and Te744 read zap). Zapotec rides the bare macrolanguage
    # code zap (the lect posture names the Colonial Valley Zapotec stage
    # candidate — no registry node exists yet). text_role:
    #
    #   zapotec-original    aguero-miscelaneo, Te744
    #   bilingual-work      cordova-arte, levanto-arte, levanto-cathecismo
    #                       (Spanish-matrix grammars/catechism of Zapotec)
    #   spanish-translation a *T id (Ticha's own convention; the original's
    #                       id rides as translation_of — 78 documents, all
    #                       but Te744T's original absent from the repo)
    #   spanish-unmarked    no T and no Zapotec: Al724a, Ri832, the eight
    #                       AGEO_* files (the AGEO header declares only
    #                       "Early Modern Spanish") — the asset does not say
    #                       translation or Spanish original
    #
    # A manuscript whose text attests its own translation — the
    # interpreter ("ynterprete"/"interprete") or "traducido/tradusido del
    # ydioma zapoteco" — records translation_statement: true (census:
    # 68 of the 89 manuscript documents — the 87 manuscripts/encoded
    # files + Te744/Te744T).
    #
    # == Axes (the aggressive-mining policy)
    #
    # Dates: a Ticha manuscript id's year (the ORIGINAL document's year —
    # a translation is dated by its original; its own later date, often in
    # the interpreter's attestation, stays in the text) and the printed
    # works' title-page years (Córdova 1578, Agüero 1666, Levanto's
    # Cathecismo 1766 — a reprint, its approvals dated 1732) → "date"
    # (MetadataDates :structured). Undated: levanto-arte and the AGEO files.
    # Places: the town of the manuscript id's code (TOWN_CODES — the
    # Ticha site's own town pages, censused 2026-10-11, names verbatim
    # from the repo's places.json) and the works' imprint (México, Puebla
    # de los Ángeles). places.json coordinates ride metadata-only as
    # ticha_place — three of its 22 points fall far outside the Valley of
    # Oaxaca (lon −98.2/−98.0, lat 18.1), so none are projected.
    # Translations carry their original's town (the translation itself was
    # made by the interpreter, mostly in Antequera — in the text).
    #
    # == License
    #
    # The repository's license.txt (read 2026-10-11), verbatim: "License:
    # cc-by-sa-4.0 | SPDX ID CC-BY-SA-4.0 | SPDX Name Creative Commons
    # Attribution Share Alike 4.0" → attribution. Only the repository's
    # contents are used; the Ticha website itself is a separate (NC)
    # publication and is never fetched.
    class Ticha < Nabu::Adapter
      REPO_URL = "https://github.com/HCDigitalScholarship/ticha-xml-tei"
      URN_PREFIX = "urn:nabu:ticha:"

      # Files that are not documents (class note: skipped by rule).
      SKIP_DIRS = %w[schema cordova-arte/transform].freeze
      EXAMPLE_FILE = /_example\b/
      ENCODED_DIR = "manuscripts/encoded"

      # The files whose UNMARKED language is Zapotec (everything else is
      # Spanish-unmarked — census-verified per file, class note).
      UNMARKED_ZAPOTEC = %w[aguero-miscelaneo Te744].freeze

      # Ticha manuscript ids: town code, year − 1000, optional letter,
      # optional T (translation).
      DOCUMENT_COMMENT = /\A(?:Translation of )?Testament from /

      TRANSLATION_STATEMENT = /[iy]nterprete|tradu[csz]/i

      MANUSCRIPT_ID = /\A(?<code>[A-Za-z]+)(?<yy>\d{3})(?<letter>[a-z]?)(?<t>T?)\z/

      # Town codes → the repo's places.json name, verified against the
      # Ticha site's town pages (2026-10-11). AI is the corpus's capital-I
      # misspelling of Al (the site lists AI714T/AI724bT/AI741T as Al…);
      # SDA740fT is listed by the site as SDE740fT. Tl and Xx are the
      # site's "Unknown Towns" — unplaced.
      TOWN_CODES = {
        "Al" => "San Pedro el Alto", "AI" => "San Pedro el Alto",
        "An" => "Oaxaca de Juárez", "Ay" => "Ayoquezco",
        "Co" => "San Bartholomé Coyotepec", "Fr" => "San Francisco del Valle",
        "Ma" => "San Mateo Macuilxóchitl/San Mateo Macuilzochitl",
        "Oc" => "San Antonio Ocotlán", "Qu" => "Santa Catarina Quiané",
        "Ri" => "San Juan del Río", "SDE" => "Santo Domingo Etla", "SDA" => "Santo Domingo Etla",
        "Sd" => "Santo Domingo del Valle", "Te" => "San Sebastián Teitipac",
        "Th" => "Theozapotlan", "Tv" => "Teotitlán del Valle", "Za" => "Villa de Zaachila"
      }.freeze

      # The printed/bound works (title pages read in the files themselves).
      WORKS = {
        "cordova-arte" => { "title" => "Arte en lengua zapoteca", "author" => "Juan de Córdova",
                            "year" => 1578, "raw" => "title page: Año de. 1578", "place" => "México",
                            "imprint" => "En México, en casa de Pedro Balli", "work_type" => "arte" },
        "aguero-miscelaneo" => { "title" => "Miscelaneo espiritual en el idioma zapoteco",
                                 "author" => "Cristóbal de Agüero", "year" => 1666,
                                 "raw" => "title page: Año de 1666", "place" => "México",
                                 "imprint" => "Con licencia. En México, por la Viuda de Bernardo Calderón",
                                 "work_type" => "miscelaneo" },
        "levanto-cathecismo" => { "title" => "Cathecismo de la lengua zaapoteca", "author" => "Leonardo Levanto",
                                  "year" => 1766, "raw" => "title page: Reimpresso … Año de 1766 " \
                                                           "(a reprint; its approvals are dated 1732)",
                                  "place" => "Puebla de los Ángeles",
                                  "imprint" => "Reimpresso en la Imprenta del Colegio Real de San Ignacio " \
                                               "de la Puebla de los Angeles",
                                  "work_type" => "catecismo" },
        "levanto-arte" => { "title" => "Arte de lengua zapoteca", "work_type" => "arte" }
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "ticha",
        name: "Ticha — colonial Valley Zapotec texts in TEI (Haverford College)",
        license: "CC BY-SA 4.0 — the repository's license.txt, verbatim: \"License: cc-by-sa-4.0 | " \
                 "SPDX ID CC-BY-SA-4.0 | SPDX Name Creative Commons Attribution Share Alike 4.0\". " \
                 "Ticha: a digital text explorer for Colonial Zapotec (Brook Danielle Lillehaugen et " \
                 "al., Haverford College). Repository contents only — the Ticha website is a separate " \
                 "publication.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "ticha-tei"
      )

      def self.manifest = MANIFEST

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_files(workdir).each do |path|
          stem = Normalize.nfc(File.basename(path, ".xml"))
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{stem}",
                                      path: File.expand_path(path), metadata: { "stem" => stem })
        end
      end

      def discovery_skips(workdir)
        skipped = Dir.glob(File.join(workdir, "**", "*.xml")).size - document_files(workdir).size
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        stem = document_ref.metadata.fetch("stem") { File.basename(document_ref.path, ".xml") }
        default = UNMARKED_ZAPOTEC.include?(stem) ? "zap" : "spa"
        result = TichaTeiParser.new.parse(document_ref.path, default_language: default)
        raise Nabu::ParseError, "#{document_ref.id}: no text" if result.pages.empty?

        totals = language_totals(result.pages)
        language = majority(totals) || default
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, canonical_path: document_ref.path,
          title: title_for(stem, result), metadata: metadata_for(stem, document_ref, result, totals, default)
        )
        add_passages(document, result.pages, default)
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # Split out so the fetch test points at a local git repo.
      def repo_url = REPO_URL

      # The document XML files (class note: skip rules).
      def document_files(workdir)
        all = Dir.glob(File.join(workdir, "**", "*.xml")).reject do |path|
          rel = path.delete_prefix("#{workdir}/")
          SKIP_DIRS.any? { |dir| rel.start_with?("#{dir}/") } || File.basename(path).match?(EXAMPLE_FILE)
        end
        work_stems = all.reject { |p| p.include?("/#{ENCODED_DIR}/") }.to_set { |p| File.basename(p, ".xml") }
        all.reject { |p| p.include?("/#{ENCODED_DIR}/") && work_stems.include?(File.basename(p, ".xml")) }.sort
      end

      def add_passages(document, pages, default)
        seen = Hash.new(0)
        pages.each_with_index do |page, index|
          citation = page.n ? Normalize.nfc(page.n.strip) : "s#{index + 1}"
          seen[citation] += 1
          citation = "#{citation}##{seen[citation]}" if seen[citation] > 1
          document << Nabu::Passage.new(
            urn: "#{document.urn}:#{citation}", language: majority(page.languages) || default,
            text: Normalize.nfc(page.text), sequence: index + 1, annotations: annotations_for(page)
          )
        end
      end

      def annotations_for(page)
        annotations = { "page" => page.n, "facs" => page.facs.empty? ? nil : page.facs }.compact
        annotations["languages"] = page.languages unless page.languages.empty?
        regularized = Normalize.nfc(page.regularized)
        annotations["regularized"] = regularized unless regularized == Normalize.nfc(page.text.tr("\n", " "))
        annotations["foreign"] = deep_nfc(page.foreign) unless page.foreign.empty?
        annotations["outline"] = deep_nfc(page.outline) unless page.outline.empty?
        annotations["apparatus"] = deep_nfc(page.apparatus) unless page.apparatus.empty?
        annotations["forme_work"] = deep_nfc(page.forme_work) unless page.forme_work.empty?
        annotations
      end

      def language_totals(pages)
        pages.each_with_object(Hash.new(0)) { |page, totals| page.languages.each { |k, v| totals[k] += v } }
      end

      # The language with the most words (ties: alphabetical, stable).
      def majority(counts)
        counts.max_by { |lang, words| [words, lang] }&.first
      end

      def title_for(stem, result)
        work = WORKS[stem]
        return work["title"] if work

        # The AGEO files' teiHeader titles ("Testament AGEO 35"); Córdova's
        # header title is the template placeholder "Title" (its WORKS row wins).
        header = result.header_title
        return Normalize.nfc(header) if header && !header.empty? && header != "Title"

        # The Teitipac files name their document in a prolog comment.
        named = result.prolog_comments.find { |comment| comment.match?(DOCUMENT_COMMENT) }
        return Normalize.nfc(named) if named

        match = MANUSCRIPT_ID.match(stem)
        return "Ticha manuscript #{stem}" if match.nil?

        role = match[:t].empty? ? "" : " (Spanish translation of #{stem.delete_suffix('T')})"
        "Ticha manuscript #{stem}#{role}"
      end

      def metadata_for(stem, document_ref, result, totals, default)
        meta = { "ticha_id" => stem, "unmarked_language" => default, "languages" => totals,
                 "text_role" => text_role(stem, totals) }
        meta["markup_repairs"] = result.repairs if result.repairs.positive?
        meta["unknown_lang_tags"] = result.unknown_lang_tags unless result.unknown_lang_tags.empty?
        meta["header_languages"] = result.header_languages unless result.header_languages.empty?
        meta.merge!(work_metadata(stem))
        meta.merge!(manuscript_metadata(stem, document_ref))
        meta.compact
      end

      def text_role(stem, totals)
        return "zapotec-original" if UNMARKED_ZAPOTEC.include?(stem)
        return "bilingual-work" if WORKS.key?(stem)

        match = MANUSCRIPT_ID.match(stem)
        return "spanish-translation" if match && match[:t] == "T"

        totals.key?("zap") ? "bilingual-work" : "spanish-unmarked"
      end

      def work_metadata(stem)
        work = WORKS[stem] or return {}

        meta = work.slice("author", "imprint", "work_type")
        if work["year"]
          meta["date"] =
            { "not_before" => work["year"], "not_after" => work["year"], "raw" => work["raw"] }
        end
        meta["place"] = work["place"] if work["place"]
        meta["place_role"] = "imprint" if work["place"]
        meta["facets"] = { "work_type" => { "value" => work["work_type"], "raw" => work["work_type"] } }
        meta
      end

      def manuscript_metadata(stem, document_ref)
        return {} if WORKS.key?(stem)

        meta = { "work_type" => "manuscript", "translation_statement" => translation_statement?(document_ref.path) }
        meta["facets"] = { "work_type" => { "value" => "manuscript", "raw" => "manuscript" } }
        match = MANUSCRIPT_ID.match(stem) or return meta

        year = 1000 + Integer(match[:yy], 10)
        meta["date"] = { "not_before" => year, "not_after" => year,
                         "raw" => "Ticha id #{stem} (the original document's year)" }
        meta["translation_of"] = stem.delete_suffix("T") if match[:t] == "T"
        town = TOWN_CODES[match[:code]]
        return meta if town.nil?

        meta["place"] = town
        meta["town_code"] = match[:code]
        meta["ticha_place"] = ticha_place(document_ref.path, town)
        meta
      end

      def translation_statement?(path)
        File.read(path, encoding: "UTF-8").match?(TRANSLATION_STATEMENT)
      end

      # The repo's places.json entry for +town+ (name + coordinates,
      # verbatim, metadata-only — class note), or nil.
      def ticha_place(path, town)
        places = places_json(path) or return nil
        entry = places.find { |place| place["name"] == town } or return nil

        geom = entry["geom"] || {}
        { "name" => town, "lon" => geom["x"], "lat" => geom["y"], "ticha_place_id" => entry["id"] }
      end

      # places.json sits at the repo root — found by walking up from the
      # document (the attic mirrors the same relative shape).
      def places_json(path)
        dir = File.dirname(path)
        @places ||= {}
        4.times do
          file = File.join(dir, "places.json")
          return @places[file] ||= JSON.parse(File.read(file)) if File.file?(file)

          dir = File.dirname(dir)
        end
        nil
      rescue JSON::ParserError
        nil
      end

      def deep_nfc(value)
        case value
        when String then Normalize.nfc(value)
        when Hash then value.transform_values { |v| deep_nfc(v) }
        when Array then value.map { |v| deep_nfc(v) }
        else value
        end
      end
    end
  end
end
