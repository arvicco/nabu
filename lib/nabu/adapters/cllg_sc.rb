# frozen_string_literal: true

require_relative "cllg_catalog"
require_relative "cllg_tei_parser"

module Nabu
  module Adapters
    # CLLG Sources Chrétiennes — the Inria CLLG corpus of the Greek (and a
    # few Latin) texts of the Éditions du Cerf *Sources chrétiennes* series
    # (gitlab.inria.fr/almanach/cllg/sources-chretiennes; Corpus Liberatum
    # Linguae Graecae, dir. Thibault Clérice, ANR-24-RRII-0002 + Programme
    # Inria Quadrant): patristic and Byzantine authors from the Apostolic
    # Fathers to Nicholas Cabasilas, in the series' own critical editions
    # (1941–2025), Irenaeus excluded upstream. TEI P5 with citeStructure
    # trees — the cllg-tei parser family. 118 MB clone (data/ 95 MB):
    # a plain shallow GitFetch, no sparse cone needed.
    #
    # == License (provenance facts)
    #
    # README "License": "The corpus is distributed under an open license
    # (CC-BY)." README "Data and Processing": "Texts are distributed under
    # French law, which holds that the texts of critical editions are not
    # subject to copyright protection, as they do not constitute an
    # expression of the editor's personality (CA Paris, Pôle 5, 2ème Ch.,
    # 9 June 2017, no. 16/00005)." No LICENSE file; the per-file headers
    # carry the CLLG respStmt/funder but no licence element. CC-BY is the
    # stated floor → license_class attribution.
    #
    # == Grains (census over the 219176d8 clone, 2026-11-12)
    #
    # Upstream serves 371 edition files under data/<author>/<slug>.xml
    # (plus data/spurious-and-dubia/<author>/), 103 per-author metadata.xml
    # catalog records (CllgCatalog — structure, never documents) listed by
    # the root cllg-sc.xml, and three SC↔TLG alignment CSVs at the root.
    # The document = one edition file a metadata.xml <resource> claims,
    # its urn the resource identifier (urn:cts:greekLit:tlg2042.tlg001.
    # sc-cllg-grc1; latinLit + cllg-lat1/sc-cllg-lat1 for the Latin).
    # Reconciliation against upstream's 371 files / 368 resources: 368
    # catalogued (362 grc + 6 Latin; one grc file also declares Latin
    # passages — the FIRST langUsage language is the document's) + 3
    # uncatalogued skipped by rule (tlg4089/epistulae_collectio_
    # conciliaris_grecques, tlg4110/lettre_sur_la_foi, tlg4110/lettres_
    # fragments_grecs: no resource claims them, and their in-file edition
    # urns collide with catalogued works) = 371, residue 0. Of the 368,
    # 2 declare a tree that opens no citable unit (cllg0010's homily
    # cites p by @n, no p carries one; tlg3116's hymn table cites a list
    # by @n, the list carries none) → DocumentSkipped at parse, counted by
    # the loader as skipped-by-rule: 366 documents load (360 grc + 6 lat;
    # 94,713 passages through this adapter over the clone at census).
    #
    # sc_tlg.csv / sc_tlg_authors.csv (an SC-volume ↔ TLG alignment, every
    # link agent-checked per upstream's README) are future edition-pairing
    # material — not ingested by this adapter.
    #
    # == Metadata mining (the aggressive-mining law)
    #
    # From the catalog record: "author" (the author collection title,
    # French: "Origène"), "work_title" ("Contre Celse"), "description",
    # "creator", the work's dc identifiers ("CPG 1502" → "cpg", others
    # verbatim under "catalog_identifiers"), "tlg" (the urn's
    # tlgNNNN.tlgNNN pair when both are TLG ids — the cross-source join
    # key with perseus-greek / first1k-greek / cllg-freed). Four edition
    # urns here are minted by cllg-freed too (same cllg-grc1 version id,
    # different text state); this corpus is the owner of record — freed
    # defers them by rule (CllgFreed::SC_OVERLAP carries the census).
    # From the teiHeader sourceDesc (one <bibl> per printed volume):
    # "editions" (each volume: n, title, editors, date, publisher, place,
    # series, volume, identifiers), "sc_volumes", "editors", "identifiers"
    # (the volumes' typed idnos — ISBN, CPG, CPL …; repeated types keep the
    # first) and "edition_year" (the distinct volume years, comma-joined —
    # MetadataDates::EDITION_FALLBACK reads it, date_class edition).
    # "date" is minted ONLY from upstream's own composition claim: the
    # APA-style "(Original work published ca. 3th century)" a few catalog
    # descriptions carry (7 of 368) → a century envelope, class
    # composition. The rest stay composition-undated (the edition year
    # falls back on the timeline).
    # "genre": the earliest genre noun of the French/Latin work title
    # (TITLE_GENRES; the cgpg title-keyword precedent) — "Homélie",
    # "Lettre", "Commentaire", "Vie" … — folded in config/kind_map.yml;
    # a title with no genre noun ("Sur la prière", "Contre Celse") makes no
    # kind claim.
    class CllgSc < Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "cllg-sc",
        name: "CLLG Sources Chrétiennes (Inria) — Greek and Latin patristic editions",
        license: "CC-BY (README: \"The corpus is distributed under an open license (CC-BY).\"); texts per " \
                 "French law not protected as critical editions (CA Paris, Pôle 5, 2ème Ch., 9 June 2017, " \
                 "no. 16/00005). Cite the Corpus Liberatum Linguae Graecae (dir. Thibault Clérice, Inria) and " \
                 "each Sources chrétiennes edition (Éditions du Cerf)",
        license_class: "attribution",
        upstream_url: "https://gitlab.inria.fr/almanach/cllg/sources-chretiennes.git",
        parser_family: "cllg-tei"
      )

      LANGUAGES = { "grc" => "grc", "la" => "lat", "lat" => "lat" }.freeze

      # "(Original work published ca. 3th century)" — upstream's ordinal
      # spelling verbatim ("3th").
      ORIGINAL_CENTURY = /\(Original work published (?<raw>ca\. (?<century>\d{1,2})(?:st|nd|rd|th) century)\)/
      TLG_PAIR = /\Aurn:cts:greekLit:(?<pair>tlg\d{4}\.tlg\d{3})\./
      CPG = /\ACPG\s+(?<id>\S.*)\z/

      # Genre nouns of the work titles, earliest occurrence wins (a later
      # list position only breaks ties at the same offset — "Éloge funèbre"
      # before "Éloge"). The label is the noun's head form; every label
      # has its fold (or its declared non-fold) in config/kind_map.yml.
      TITLE_GENRES = [
        ["Préface", /\bPréface\b/],
        ["Table", /\bTable\b/],
        ["Homélie", /\b(?:Homélies?|homélies?|Homiliae?|sermo|Sermons?)\b/],
        ["Lettre", /\b(?:Lettres?|Épîtres?|Epistulae?|Correspondance)\b/],
        ["Commentaire", /\b(?:Commentaire|Scholies?|Chaîne)\b/],
        ["Éloge funèbre", /(?:Éloge funèbre|\bFunebris\b)/],
        ["Éloge", /(?:Éloge|\bPanégyriques?\b)/],
        ["Vie", /\bVie d(?:e |['’])/], # a life OF someone — never "La Vie en Christ"
        ["Martyre", /\b(?:Martyre|Martyrs|Passion)\b/],
        ["Histoire ecclésiastique", /\bHistoire ecclésiastique\b/],
        ["Hymne", /\b(?:Hymnes?)\b/],
        ["Prière", /\bPrière\b/],
        ["Catéchèse", /\b(?:[Cc]atéchèses?|catéchétique)\b/],
        ["Questions", /\bQuestions\b/],
        ["Dialogue", /\bDialogues?\b/],
        ["Épigramme", /Épigrammes?/],
        ["Vers", /\b(?:Vers|Centons)\b/],
        ["Sentences", /\b(?:Sentences|Apophtegmes)\b/],
        # Title-initial only: "Réfutation de la Profession de foi d'Eunome"
        # refutes a creed, it is not one.
        ["Profession de foi", /\A(?:Profession de foi|Exposé de la profession de foi|Symbolum)/],
        ["Constitutions", /\A(?:Constitutions apostoliques|Didachè)/]
      ].freeze

      def self.manifest = MANIFEST

      # The earliest genre noun of +title+, or nil.
      def self.title_genre(title)
        return nil if title.nil?

        hits = TITLE_GENRES.each_with_index.filter_map do |(label, pattern), order|
          offset = title =~ pattern
          [offset, order, label] if offset
        end
        hits.min&.last
      end

      def repo_url = manifest.upstream_url

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        CllgCatalog.new(workdir).resources.each do |resource|
          next unless File.file?(resource.path)

          yield DocumentRef.new(source_id: manifest.id, id: resource.urn, path: resource.path,
                                metadata: ref_metadata(resource))
        end
      end

      def discovery_skips(workdir)
        catalog = CllgCatalog.new(workdir)
        uncatalogued = catalog.uncatalogued.map { |path| catalog.relative(path) }
        missing = catalog.missing.map(&:urn)
        notes = []
        unless uncatalogued.empty?
          notes << "#{uncatalogued.size} uncatalogued edition file#{'s' unless uncatalogued.size == 1} " \
                   "(no metadata.xml resource claims it): #{listing(uncatalogued)}"
        end
        unless missing.empty?
          notes << "#{missing.size} catalog resource#{'s' unless missing.size == 1} whose file is absent: " \
                   "#{listing(missing)}"
        end
        Adapter::DiscoverySkips.new(skipped_by_rule: uncatalogued.size, unrecognized: missing.size, notes: notes)
      end

      def parse(document_ref)
        header = CllgTeiParser.header(document_ref.path)
        CllgTeiParser.new.parse(
          document_ref.path, urn: document_ref.id, language: language(header, document_ref.path),
                             title: document_ref.metadata["title"], header: header,
                             metadata: metadata(document_ref, header)
        )
      end

      private

      def listing(items)
        "#{items.sort.first(5).join(', ')}#{', …' if items.size > 5}"
      end

      def ref_metadata(resource)
        {
          "title" => resource.title, "work_title" => resource.work_title, "author" => resource.author,
          "creator" => resource.creator, "description" => resource.description,
          "catalog_identifiers" => (resource.identifiers unless resource.identifiers.empty?)
        }.compact
      end

      def language(header, path)
        declared = header.languages.first or return "grc"
        LANGUAGES.fetch(declared) { raise ParseError, "#{path}: unclassed langUsage #{declared.inspect}" }
      end

      def metadata(document_ref, header)
        catalog = document_ref.metadata
        editions = header.editions
        identifiers = editions.flat_map { |edition| edition.identifiers.to_a }.uniq(&:first).to_h
        years = editions.filter_map { |edition| edition.date&.[](/\b\d{4}\b/) }.uniq.sort
        cpg = Array(catalog["catalog_identifiers"]).filter_map { |id| id[CPG, :id] }.first
        catalog.except("title").merge(
          "tlg" => document_ref.id[TLG_PAIR, :pair],
          "cpg" => cpg,
          "editions" => editions.map { |edition| edition_hash(edition) },
          "sc_volumes" => editions.filter_map(&:volume),
          "editors" => editions.flat_map(&:editors).uniq,
          "identifiers" => (identifiers unless identifiers.empty?),
          "edition_year" => (years.join(", ") unless years.empty?),
          "date" => composition_date(catalog["description"]),
          "genre" => self.class.title_genre(catalog["work_title"])
        ).reject { |_key, value| value.nil? || value == [] }
      end

      def edition_hash(edition)
        edition.to_h.transform_keys(&:to_s).reject { |_key, value| value.nil? || value == [] || value == {} }
      end

      def composition_date(description)
        match = ORIGINAL_CENTURY.match(description.to_s) or return nil
        century = Integer(match[:century], 10)
        { "not_before" => ((century - 1) * 100) + 1, "not_after" => century * 100, "raw" => match[:raw],
          "class" => "composition" }
      end
    end
  end
end
