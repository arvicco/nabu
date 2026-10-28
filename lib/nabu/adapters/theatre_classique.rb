# frozen_string_literal: true

require_relative "theatre_classique_tei_parser"

module Nabu
  module Adapters
    # theatre-classique — Théâtre Classique (theatre-classique.fr), Paul
    # Fièvre's corpus of French plays, encoded by him in TEI since 2007:
    # the classical repertoire whole (Corneille, Molière, Racine, Quinault,
    # Dancourt, Marivaux, Voltaire, Beaumarchais) with the minor and
    # occasional theatre around it — comedies, tragedies, tragi-comedies,
    # proverbes, saynètes, monologues, dialogues, parodies, opéras-comiques
    # — reaching back to a handful of medieval and sixteenth-century farces
    # and mystères (modernized or translated) and forward to Becque,
    # Courteline, Tristan Bernard and Giraudoux. Each file transcribes one
    # printed edition (its Gallica permalink rides the header) with the
    # print's front matter: title page, privilege, dedication, preface,
    # cast list, first-performance note.
    #
    # == Shape and fetch
    #
    # theatre-classique.fr serves each play's XML under /pages/documents/,
    # and its robots.txt disallows exactly that path for every user agent
    # ("User-Agent:* Disallow: /pages/documents/", read 2026-10-28) — the
    # site itself fails the unattended-fetch bar, and this adapter never
    # touches it. The fetch is the DraCor project's verbatim mirror,
    # github.com/dracor-org/theatre-classique (main: "XML files as obtained
    # from http://theatre-classique.fr/pages/programmes/PageEdition.php";
    # the dracor branch, DraCor's edits, is NOT fetched). Sparse cone:
    # xml/ + README.md (the repo's update scripts stay out).
    #
    # == Identity and grains
    #
    # Document = one play file: urn:nabu:theatre-classique:<filename stem
    # downcased> (MOLIERE_MISANTHROPE.xml → moliere_misanthrope). The
    # filename, never <idno>: idno disagrees with the filename on 421 of
    # 1,940 files (copy-paste residue — ANONYME_PRUDECOQUETTE carries
    # ANONYME_DIALOGUEDESYEUXETDELABOUCHE) and is absent on others.
    # Passages = the theatre-classique-tei family's blocks (front matter,
    # act/scene heads, verse lines, prose speeches, stage directions),
    # citation <div ordinals>.<block>.
    #
    # Reconciliation (census 2026-10-28, mirror main @d6ed03d8, pushed
    # 2024-09-02): 1,940 files in xml/ (1,939 .xml + 1 .XML), all well-
    # formed, all admitted → 1,939 documents / 1,601,085 passages + 1
    # quarantined: CORNEILLET_LAODICE declares encoding="iso-8859-1" and
    # carries Latin-1 bytes, which the UTF-8 encoding belt refuses. The
    # site's home page advertises 2,180 "pièces de théâtre et spectacles"
    # today; the ~240 residue is the mirror's lag behind the live site
    # (the mirror is refreshed by hand by DraCor), not a skip.
    #
    # == The admission rule (in-copyright works excluded by rule)
    #
    # The site presents its texts as "oeuvres libres de droit quant à leur
    # contenu". A play is admitted only when every textual author (author
    # @type texte/text/traduction, or untyped) whose death year the header
    # records died at or before AUTHOR_DEATH_CUTOFF — 1955, the last year
    # whose authors' works are free on 1 January 2026 (France: life + 70);
    # the constant is advanced deliberately each January. Collaborators
    # (musique, decor, costume …) contribute no text and are not tested.
    # Censused 2026-10-28: zero exclusions (the latest textual death is
    # Jean Drault, 1951); the rule stands guard for the mirror's growth.
    #
    # == Axes (the mining policy)
    #
    # Date: docDate@value — the year printed on the transcribed edition's
    # title page (1,933 of 1,940 files), date class "edition"; else the
    # site's <periode> decade band ("1501-1600"), class "composition" —
    # MetadataDates :structured. The first performance (premiere@date/
    # @location, ISO on 992 files) rides as metadata "premiere". Place: the
    # imprint city read from the title-page imprint ("À PARIS, chez JEAN
    # RIBOU …" → Paris; Amsterdam, Liège, Rouen, La Haye …), declared
    # coarse — the full imprint rides "imprint"; <set> (the play's
    # fictional setting) rides "setting" and is never a place claim.
    # Genre: the site's own <genre> verbatim ("Comédie", "Tragédie",
    # "Proverbe" …) with <inspiration>, <structure>, <type> (vers/prose/
    # mixte → "form"), <periode>, <taille>, keywords and the Gallica
    # permalink. Authors: every titleStmt author with role, ISNI and
    # life years; "author" is the first textual author.
    #
    # == License
    #
    # Three statements, read 2026-10-28, recorded together:
    # - each file's publicationStmt: "<rights>Creative Commons
    #   BY-NC-SA</rights>" (1,854 of 1,940; 9 more spell it "BY-NC-sA";
    #   95 carry no rights element and ride the site's statements);
    # - the site's rights page (pages/droits.html): "la réutilisation à
    #   usage personnel ou pédagogique et non commerciale de ces contenus
    #   est libre et gratuite, dans le respect de la législation en vigueur
    #   et notamment du maintien de la mention de source"; commercial reuse
    #   "doit faire l'objet d'un accord préalable";
    # - the home-page footer: "L'utilisation des ressources mises en ligne
    #   n'est pas autorisée sans accord préalable. Ce site est mise à
    #   disposition selon les termes de la Licence Creative Commons
    #   Attribution - Pas d'Utilisation Commerciale - Pas de Modification
    #   4.0 International."
    # The per-file grant (CC BY-NC-SA) and the rights page agree on free
    # non-commercial reuse with the source credited → class nc; the
    # footer's broader prior-agreement sentence is recorded, not resolved.
    class TheatreClassique < Nabu::Adapter
      REPO_URL = "https://github.com/dracor-org/theatre-classique.git"
      SPARSE_PATHS = ["xml", "README.md"].freeze
      TEXT_DIR = "xml"
      LANGUAGE = "fra"
      URN_PREFIX = "urn:nabu:theatre-classique:"
      TEXTUAL_ROLES = [nil, "texte", "text", "traduction"].freeze

      # const: the life+70 boundary as of 1 January 2026 — advance each January, not a corpus claim
      AUTHOR_DEATH_CUTOFF = 1955

      IMPRINT_CITY = /\A(?:À|A)\s+(\p{Lu}[\p{L}' -]*?)\s*(?:[,.;:]|\s+(?i:chez)\b|\z)/

      MANIFEST = Nabu::SourceManifest.new(
        id: "theatre-classique",
        name: "Théâtre Classique — Paul Fièvre's TEI corpus of French plays",
        license: "CC BY-NC-SA — each file's TEI header: \"<rights>Creative Commons BY-NC-SA</rights>\". " \
                 "The site's rights page: \"la réutilisation à usage personnel ou pédagogique et non " \
                 "commerciale de ces contenus est libre et gratuite, dans le respect de la législation " \
                 "en vigueur et notamment du maintien de la mention de source\"; commercial reuse needs " \
                 "prior agreement. Cite: Paul Fièvre, Théâtre Classique, https://www.theatre-classique.fr " \
                 "(fetched via the DraCor mirror github.com/dracor-org/theatre-classique). Works whose " \
                 "textual author died after #{AUTHOR_DEATH_CUTOFF} are excluded by rule (life + 70).",
        license_class: "nc",
        upstream_url: "https://www.theatre-classique.fr",
        parser_family: "theatre-classique-tei"
      )

      def self.manifest = MANIFEST

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        candidates(workdir).each do |path, header|
          next unless admitted?(header)

          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn_for(path),
                                      path: File.expand_path(path), metadata: {})
        end
      end

      def discovery_skips(workdir)
        excluded = candidates(workdir).reject { |_path, header| admitted?(header) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: excluded.size,
          notes: excluded.map do |path, header|
            "#{File.basename(path)}: #{late_authors(header).map { |a| "#{a.name} d. #{a.death}" }.join('; ')} " \
              "— in copyright (life + 70; cutoff #{AUTHOR_DEATH_CUTOFF})"
          end
        )
      end

      def parse(document_ref)
        parsed = parser.parse(document_ref.path)
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE,
                                      canonical_path: document_ref.path, title: parsed.header.title,
                                      metadata: metadata_for(parsed, document_ref.path))
        parsed.blocks.each_with_index do |block, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{block.citation}", language: LANGUAGE,
                                        text: block.text, sequence: index + 1,
                                        annotations: annotations_for(block))
        end
        raise Nabu::ParseError, "#{document_ref.id}: no text blocks" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      # Split out so the fetch test can point a singleton at a local repo.
      def repo_url = REPO_URL

      def parser = @parser ||= TheatreClassiqueTeiParser.new

      # Case-insensitive on the extension: the mirror holds one ".XML"
      # (and a Dir.glob "{xml,XML}" pair double-counts on a
      # case-insensitive filesystem).
      def candidates(workdir)
        dir = File.join(workdir, TEXT_DIR)
        return [] unless Dir.exist?(dir)

        Dir.children(dir).grep(/\.xml\z/i).sort.map do |name|
          path = File.join(dir, name)
          [path, readable_header(path)]
        end
      end

      # A header the belt or the XML parser refuses (nil) never aborts
      # discovery: the file is yielded, and its parse raises the same
      # ParseError — the document quarantines, named, the sync goes on.
      def readable_header(path)
        parser.header(path)
      rescue Nabu::ParseError
        nil
      end

      def admitted?(header) = header.nil? || late_authors(header).empty?

      def late_authors(header)
        header.authors.select do |author|
          TEXTUAL_ROLES.include?(author.role) && author.death && author.death > AUTHOR_DEATH_CUTOFF
        end
      end

      def urn_for(path) = "#{URN_PREFIX}#{File.basename(path, File.extname(path)).downcase}"

      def annotations_for(block)
        { "kind" => block.kind, "who" => block.who, "speaker" => block.speaker,
          "n" => block.n, "part" => block.part }.compact
      end

      def metadata_for(parsed, path)
        header = parsed.header
        front = parsed.front
        lead = header.authors.find { |a| TEXTUAL_ROLES.include?(a.role) }
        {
          "tc_id" => File.basename(path, File.extname(path)),
          "idno" => header.idno,
          "author" => lead&.name,
          "author_birth" => lead&.birth,
          "author_death" => lead&.death,
          "authors" => presence(header.authors.map { |a| author_hash(a) }),
          "genre" => header.source_desc["genre"],
          "inspiration" => header.source_desc["inspiration"],
          "structure" => header.source_desc["structure"],
          "form" => header.source_desc["form"],
          "periode" => header.source_desc["periode"],
          "size" => header.source_desc["size"],
          "keywords" => presence(header.keywords),
          "permalink" => header.permalink,
          "date" => date_for(header, front),
          "premiere" => premiere_for(front),
          "imprint" => front.printer,
          "place" => imprint_city(front.printer),
          "setting" => presence(front.setting),
          "statements" => presence(header.statements),
          "rights" => header.rights,
          "lang_tag" => header.lang_tag,
          "tei_root" => header.root == "TEI" ? nil : header.root
        }.compact
      end

      def author_hash(author)
        { "name" => author.name, "role" => author.role, "isni" => author.isni,
          "birth" => author.birth, "death" => author.death }.compact
      end

      # The transcribed edition's title-page year (class edition); else the
      # site's periode band (class composition).
      def date_for(header, front)
        if (year = front.doc_date_value.to_s[/\A(\d{4})\z/, 1])
          year = Integer(year, 10)
          return { "not_before" => year, "not_after" => year,
                   "raw" => front.doc_date_text || front.doc_date_value, "class" => "edition" }
        end

        band = header.source_desc["periode"].to_s.match(/\A(\d{3,4})-(\d{3,4})\z/) or return nil
        { "not_before" => Integer(band[1], 10), "not_after" => Integer(band[2], 10),
          "raw" => "periode #{band[0]}", "class" => "composition" }
      end

      def premiere_for(front)
        presence({ "date" => front.premiere_date, "location" => front.premiere_location,
                   "note" => front.premiere_text }.compact)
      end

      # "À PARIS, chez …" → "Paris": the city is title-cased word by word
      # (LA HAYE → La Haye; the stray "PARIs" typo → Paris) so one city is
      # one axis key — the imprint itself rides verbatim beside it.
      def imprint_city(imprint)
        city = imprint.to_s[IMPRINT_CITY, 1] or return nil

        city.split(/(?<=[\s'-])/).map(&:capitalize).join
      end

      def presence(value)
        value.nil? || (value.respond_to?(:empty?) && value.empty?) ? nil : value
      end
    end
  end
end
