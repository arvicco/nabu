# frozen_string_literal: true

require_relative "cllg_catalog"
require_relative "cllg_tei_parser"

module Nabu
  module Adapters
    # CLLG Freed Corpus — the TLG E canon, freed: the Inria CLLG
    # (Corpus Liberatum Linguae Graecae, dir. Thibault Clérice;
    # gitlab.inria.fr/almanach/cllg/freed-corpus) re-release of the
    # Thesaurus Linguae Graecae CD-ROM E texts as TEI, by way of Peter
    # Heslin's Diogenes 4.6.2 export, with citeStructure trees, bibliographic
    # metadata and Leiden sigla encoded as TEI added by the CLLG — Homer to
    # the Byzantine chroniclers, 6,626 works by 1,835 authors (TLG author
    # numbering preserved; dubia and spuria rehomed under
    # data/spurious-and-dubia/ with their TLG urns). The cllg-tei parser
    # family.
    #
    # == License (provenance facts)
    #
    # README "License", verbatim in every file's publicationStmt: "Texts:
    # CC0 1.0. Texts of critical editions are not subject to copyright
    # protection under French law, as they do not constitute an expression
    # of the editor's personality (CA Paris, Pôle 5, 2ème Ch., 9 June 2017,
    # no. 16/00005)." — "Citation structure and metadata: CC-BY 4.0".
    # CITATION.cff: license [CC0-1.0, CC-BY-4.0]. CC-BY is the floor →
    # license_class attribution.
    #
    # == Fetch: the sparse cone (GitFetch sparse:, P26-0)
    #
    # A depth-1 full clone lands 3.2 GB: data/ 1.0 GB, .git 1.0 GB, and
    # scripts/out/paren_clf 1.1 GB of committed classifier working data no
    # adapter needs. The fetch is a blobless sparse clone of the cone
    # SPARSE (data/ + the root catalog + README/CITATION.cff, the licence
    # provenance) — only the cone's blobs transfer, so the canonical tree
    # is ~1.0 GB of TEI plus the cone's history objects. Pure git tree:
    # nothing is materialized beside upstream's files (materialized_paths
    # stays []).
    #
    # == Grains and reconciliation (census over the 281049a3 clone,
    # 2026-11-12)
    #
    # Upstream serves 6,626 edition files — data/<author>/<work>/<urn>.xml
    # and data/spurious-and-dubia/<group>/<work>/<urn>.xml — and 1,839
    # per-author metadata.xml catalog records (CllgCatalog; 1,823 author
    # dirs + 16 groups under spurious-and-dubia/ — 12 cllg-spuria groups
    # and 4 dubia dirs of held TLG authors; 1,823 + 12 = the site's "1,835
    # authors") listed by the root cllg-freed.xml. Every
    # file is claimed by exactly one resource (6,626 = 6,626, no orphan,
    # no missing file). The document = one claimed edition file, its urn
    # the resource identifier (urn:cts:greekLit:tlg0012.tlg001.cllg-grc1).
    # 331 files declare NO citation tree at all (no encodingDesc — the
    # site's own "Without citeStructure: 331"; 316 of them carry real
    # text, ~1.96 M characters, honestly uncitable until upstream declares
    # a tree) → skipped by rule at discovery (a header peek, counted in
    # #discovery_skips). Reconciliation: 6,295 refs + 331 skipped = 6,626 =
    # the site's text count, residue 0. At parse, the cllg-tei family over
    # the 6,295 (census 2026-11-12, ~15 min on the probe box): 6,294 parse
    # (1,256,190 passages through the parser; the site's 1,408,724
    # "citation units" counts every level of every tree, not leaves) and 1
    # quarantines — tlg2021.tlg037 declares use="n", an upstream typo for
    # "@n", refused loudly rather than guessed. No declared tree in freed
    # opens zero units (a ZeroMatchTree would skip by rule).
    #
    # Language: the files declare none (no xml:lang, no langUsage) — the
    # TLG is the Greek canon; every document is grc.
    #
    # == Metadata mining (the aggressive-mining law)
    #
    # The catalog resource description is the TLG canon line —
    # "Homerus Epic. (c. 8 B.C.), Ilias (0012: 001) "Homeri Ilias, vols.
    # 2 3", Ed. Allen, T.W. Oxford: Clarendon Press, 1931." — verbatim in
    # "description". Its first "(…), " group is the TLG canon's dating of
    # the AUTHOR (all 6,626 carry one: 6,139 century claims, 442 "Varia",
    # 45 "Incertum") → "tlg_date" verbatim and, when it parses
    # (TlgDate), "date" {not_before, not_after, raw, class composition} —
    # an attributed composition-era envelope, the composition class of
    # MetadataDates :structured. The author label "Homerus Epic. Homer"
    # (the teiHeader titleStmt author, verbatim in "author") carries the
    # TLG canon EPITHETS — "Epic.", "Hist.", "Comic.", "Scr. Eccl." … —
    # extracted against the closed EPITHETS list → "epithets" and "genre"
    # ("|"-joined), folded onto the kind axis in config/kind_map.yml; a
    # label carrying none ("Homerica", "Iambica Adespota (IEG)") makes no
    # kind claim. The sourceDesc biblStruct (one printed edition) →
    # "editions", "editors", "edition_year" (MetadataDates::EDITION_FALLBACK
    # — the timeline row for the Varia/Incertum works, date_class edition).
    # "tlg" = the tlgNNNN.tlgNNN pair (the cross-source join key with
    # perseus-greek / first1k-greek / cllg-sc); "dubia" = true under
    # data/spurious-and-dubia/.
    class CllgFreed < Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "cllg-freed",
        name: "CLLG Freed Corpus (Inria) — the TLG canon as TEI",
        license: "Texts CC0 1.0 (\"Texts of critical editions are not subject to copyright protection under " \
                 "French law\" — CA Paris, Pôle 5, 2ème Ch., 9 June 2017, no. 16/00005); citation structure " \
                 "and metadata CC-BY 4.0 (README; every file's publicationStmt). Cite the Corpus Liberatum " \
                 "Linguae Graecae (dir. Thibault Clérice, Inria), Diogenes (Peter Heslin) and each edition",
        license_class: "attribution",
        upstream_url: "https://gitlab.inria.fr/almanach/cllg/freed-corpus.git",
        parser_family: "cllg-tei"
      )

      # The sparse cone (no-cone pattern grammar; class note).
      SPARSE = ["/data/", "/cllg-freed.xml", "/README.md", "/CITATION.cff"].freeze

      DUBIA_DIR = "spurious-and-dubia"
      TLG_PAIR = /\Aurn:cts:greekLit:(?<pair>tlg\d{4}\.tlg\d{3})\./
      # The first "(…), " group of the TLG canon line.
      CANON_DATE = /\((?<date>[^()]*)\),\s/
      CPG = /\ACPG:\s*(?<id>\S.*)\z/

      # The TLG canon epithets the author labels carry (census over the
      # 1,839 records, 2026-11-12). Closed: a token not listed is never an
      # epithet (name parts, collection sigla like "(Suppl. Com.)").
      EPITHETS = %w[
        Alchem. Apol. Astrol. Astron. Attic. Biogr. Bucol. Choliamb. Chronogr. Comic. Didac. Doxogr. Eleg.
        Epic. Epigr. Epist. Erot. Fab. Geogr. Geom. Gnom. Gnost. Gramm. Hist. Iamb. Lexicogr. Lyr. Math.
        Mech. Med. Mimogr. Mus. Myth. Onir. Orat. Paradox. Paroemiogr. Perieg. Phil. Philol. Poet. Poeta
        Polyhist. Rhet. Soph. Sophista Tact. Theol. Trag.
      ].push("Scr. Eccl.", "Scr. Erot.", "Scr. Rerum Nat.").freeze
      # Longest first, so "Scr. Eccl." wins over any shorter overlap.
      EPITHET_ALTERNATION = EPITHETS.sort_by { |epithet| -epithet.length }.map { |e| Regexp.escape(e) }.join("|")
      EPITHET = /(?<![^\s])(#{EPITHET_ALTERNATION})(?=\s|\z|,)/

      # The TLG canon's century notation → a signed-year envelope.
      # "c. A.D. 4-5" (4th–5th c. AD), "c. 5-4 B.C.", "c. 3 B.C./A.D. 3"
      # (either), "c. 1 B.C.-A.D. 1", "?" (the canon's own doubt — the
      # bounds stay the claim, raw keeps the mark), "a."/"p." (ante/post:
      # ONE open bound — the century's far edge — never a guessed other
      # side; "p. 6 B.C. a. A.D. 3" bounds both). Non-dates ("Varia",
      # "Incertum") and anything unparsed mint nothing.
      module TlgDate
        TOKEN = /\b[ap]\.(?=\s)|A\.D\.|B\.C\.|\d+/
        LEFTOVER = %r{\b[ap]\.(?=\s)|A\.D\.|B\.C\.|\d+|[\s\-/?]}

        module_function

        def parse(raw)
          text = raw.to_s.strip.sub(/\Ac\.\s*/, "")
          return nil if text.empty? || !text.gsub(LEFTOVER, "").empty?

          groups = centuries(text.scan(TOKEN)) or return nil
          envelope(groups)&.merge("raw" => raw.strip, "class" => "composition")
        end

        # [[qualifier, [signed centuries]], …] or nil when malformed.
        def centuries(tokens)
          groups = [[nil, []]]
          pending = []
          era = nil
          tokens.each do |token|
            case token
            when "a.", "p."
              return nil unless pending.empty?

              groups << [token, []]
              era = nil
            when "A.D."
              return nil unless pending.empty?

              era = :ad
            when "B.C."
              return nil if pending.empty?

              groups.last.last.concat(pending.map(&:-@))
              pending = []
              era = nil
            else
              number = Integer(token, 10)
              era == :ad ? groups.last.last << number : pending << number
            end
          end
          return nil unless pending.empty?

          groups.reject { |(_, list)| list.empty? }.then { |kept| kept.empty? ? nil : kept }
        end

        def envelope(groups)
          lows = []
          highs = []
          groups.each do |qualifier, list|
            spans = list.map { |century| span(century) }
            lows << spans.map(&:first).min unless qualifier == "a."
            highs << spans.map(&:last).max unless qualifier == "p."
          end
          bounds = { "not_before" => lows.min, "not_after" => highs.max }.compact
          bounds.empty? ? nil : bounds
        end

        # A signed century → [first year, last year]: 4 → 301..400,
        # -4 (4th c. BC) → -400..-301.
        def span(century)
          century.positive? ? [((century - 1) * 100) + 1, century * 100] : [century * 100, (century * 100) + 99]
        end
      end

      def self.manifest = MANIFEST

      # The TLG epithets of an author label, in label order.
      def self.epithets(label)
        label.to_s.gsub(/\([^()]*\)/, " ").scan(EPITHET).flatten.uniq
      end

      def repo_url = manifest.upstream_url

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE)
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        census(workdir)[:cited].each do |resource|
          yield DocumentRef.new(source_id: manifest.id, id: resource.urn, path: resource.path,
                                metadata: ref_metadata(resource))
        end
      end

      def discovery_skips(workdir)
        found = census(workdir)
        catalog = found[:catalog]
        uncited = found[:uncited].map { |resource| catalog.relative(resource.path) }
        uncatalogued = catalog.uncatalogued.map { |path| catalog.relative(path) }
        missing = catalog.missing.map(&:urn)
        notes = []
        unless uncited.empty?
          notes << "#{uncited.size} edition file#{'s' unless uncited.size == 1} declaring no citeStructure " \
                   "(no citation tree — upstream's \"Without citeStructure\"): #{listing(uncited)}"
        end
        unless uncatalogued.empty?
          notes << "#{uncatalogued.size} uncatalogued edition file#{'s' unless uncatalogued.size == 1} " \
                   "(no metadata.xml resource claims it): #{listing(uncatalogued)}"
        end
        unless missing.empty?
          notes << "#{missing.size} catalog resource#{'s' unless missing.size == 1} whose file is absent: " \
                   "#{listing(missing)}"
        end
        Adapter::DiscoverySkips.new(skipped_by_rule: uncited.size + uncatalogued.size,
                                    unrecognized: missing.size, notes: notes)
      end

      def parse(document_ref)
        header = CllgTeiParser.header(document_ref.path)
        CllgTeiParser.new.parse(document_ref.path, urn: document_ref.id, language: "grc",
                                                   title: document_ref.metadata["title"], header: header,
                                                   metadata: metadata(document_ref, header))
      end

      private

      def listing(items)
        "#{items.sort.first(5).join(', ')}#{', …' if items.size > 5}"
      end

      # Catalogued + present resources split by the header peek: does the
      # header declare a citeStructure at all? (A string test on the
      # header slice — the element, never the word in publicationStmt prose.)
      def census(workdir)
        @census ||= {}
        @census[workdir] ||= begin
          catalog = CllgCatalog.new(workdir)
          present = catalog.resources.select { |resource| File.file?(resource.path) }
          cited, uncited = present.partition do |resource|
            CllgTeiParser.header_slice(resource.path).include?("<citeStructure")
          end
          { catalog: catalog, cited: cited, uncited: uncited }
        end
      end

      def ref_metadata(resource)
        {
          "title" => resource.title, "work_title" => resource.work_title, "author_label" => resource.author,
          "description" => resource.description,
          "dubia" => (true if resource.path.include?("#{File::SEPARATOR}#{DUBIA_DIR}#{File::SEPARATOR}")),
          "spuria_of" => resource.spuria_of,
          "catalog_identifiers" => (resource.identifiers unless resource.identifiers.empty?),
          "cpg" => resource.identifiers.filter_map { |id| id[CPG, :id] }.first
        }.compact
      end

      def metadata(document_ref, header)
        catalog = document_ref.metadata
        editions = header.editions
        years = editions.filter_map { |edition| edition.date&.[](/\b\d{4}\b/) }.uniq.sort
        canon_date = catalog["description"].to_s[CANON_DATE, :date]
        epithets = self.class.epithets(header.author || catalog["author_label"])
        catalog.except("title").merge(
          "author" => header.author,
          "tlg" => document_ref.id[TLG_PAIR, :pair],
          "tlg_date" => canon_date,
          "date" => TlgDate.parse(canon_date),
          "epithets" => epithets,
          "genre" => (epithets.join("|") unless epithets.empty?),
          "editions" => editions.map { |edition| edition_hash(edition) },
          "editors" => editions.flat_map(&:editors).uniq,
          "edition_year" => (years.join(", ") unless years.empty?)
        ).reject { |_key, value| value.nil? || value == [] }
      end

      def edition_hash(edition)
        edition.to_h.transform_keys(&:to_s).reject { |_key, value| value.nil? || value == [] || value == {} }
      end
    end
  end
end
