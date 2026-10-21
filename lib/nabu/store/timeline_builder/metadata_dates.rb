# frozen_string_literal: true

require "json"

require_relative "../../archive_axes"
require_relative "../../period_bands"
require_relative "../../place_refs"
require_relative "../../work_eras"
require_relative "../../timeline"

module Nabu
  module Store
    module TimelineBuilder
      # Catalog-metadata dates (P47-r2, generalized P47-r3 — the owner's
      # "let's find out what else could've been impacted" audit). Sources
      # whose parsers persist dating in documents.metadata_json get their
      # timeline rows projected FROM THE CATALOG (the shape is already
      # derived and load-verified there; no canonical walk) — one
      # document-grain row per dated document, place_name riding when an
      # ancient place is named, place-only rows for undated-but-placed
      # records (the HGV precedent). Translation siblings never row.
      #
      # Shapes, per the 2026-07-27 audit of every date-bearing source
      # without timeline rows:
      #   :structured — "date" => {"not_before"/"not_after"/"raw"} signed
      #     years (EDR P46-4, Elephantine P47-1, ItAnt P39 — identical).
      #   :iso_keys — top-level "date_not_before"/"date_not_after" ISO
      #     date strings (BFM P45-4: "1025-01-01" → 1025).
      #   :year_range — "date" => "1565-1650" | "1565" strings (CroALa
      #     P44): both bounds from a clean YYYY[-YYYY] parse; anything
      #     else (ca., floruit prose) is skipped honestly.
      #   :year_key — a top-level integer "year" (okhc P92-6: the
      #     deposit's own per-record year, 490,014 of 1,198,779 rows
      #     censused 2026-09-01, range 695–1995, every value an integer
      #     — a one-year envelope; year-less records mint nothing).
      #   :period_label — top-level "period" Assyriological labels banded
      #     through the ruled config/period_bands.yml table (ebl, P62-0 —
      #     the P61-1 sweep's pending served; unruled labels mint nothing).
      #   :compact_date_keys — top-level "datefrom"/"dateto" YYYYMMDD
      #     strings (fornsvenska P104-1: "12800101"/"12901231" → 1280/1290;
      #     the display "date" string rides raw).
      #   :signed_year_key — a top-level signed-year STRING "creation_date"
      #     (diorisis P104-1: "-245" → a one-year envelope; year 0 or
      #     non-numeric mints nothing).
      #   :signed_bounds_keys — top-level "start_date"/"end_date" signed-
      #     year strings (glaux P104-1: "-300"/"-201").
      #   :author_century_band — top-level "birth_century"/"death_century"
      #     CE-century integer strings (disco P104-1: "17"/"17" → 1601–1700,
      #     the author's own life band, never a midpoint).
      #   :script_band / :time_slot_band — a label field (ociana's script
      #     tradition, dcs's composition time slot) banded through ruled
      #     period_bands.yml rows, precision "era".
      #   :work_era / :archive_axes — per-source ruled tables
      #     (config/work_eras.yml per work; config/archive_axes.yml per
      #     archive: reign volume → regnal span, stated span, corpus band,
      #     and the archive's findspot).
      #   :place_only — no date reading at all; the source registers for
      #     the PLACE lane below (ogham P104-1: its "date" is free prose,
      #     honestly unparsed, but the place hash carries townland/county/
      #     country + WGS84 "geo" + logainm refs).
      #
      # == The composition class (aggressive-mining law grade 2, ruled 2026-09-26)
      #
      # Author-era composition dating — the work's era, not an object's —
      # is ruled IN as its OWN honestly-labeled class: rows from the
      # COMPOSITION sources carry date_class "composition" (migration 034);
      # artifact/typed dates keep NULL. A label, never a behavior switch.
      #     P81-1 adds the era ladder ABOVE the band for ebl's date
      #     objects: a Seleucid-era year converts exactly (SE Y = the two
      #     Julian years (312−Y)/(311−Y) BCE; month/day ride raw, never a
      #     sub-year bound), a regnal object bands to the king's own
      #     stated reign span ("555–539" descending BCE; regnal-YEAR
      #     arithmetic stays deliberately out — accession conventions are
      #     judgment, the envelope is upstream's claim); broken/uncertain
      #     years fall through to the period band.
      # (Ogham's free-prose "date" stays deliberately unparsed — the source
      # registers :place_only for its coordinates lane, P104-1.)
      module MetadataDates
        # slug => shape (the audit roster; a new metadata-dating source
        # registers here and the health lane-drift check flags it if it
        # doesn't).
        SHAPES = {
          "achemenet" => :archive_axes, # the archive table (config/archive_axes.yml): reign
          #                               volumes via the held regnal table, else the volume's
          #                               stated span, else the corpus band; archive findspots
          "africa-pd" => :structured, # P124-1: each work's edition year (the slavistics-pd
          #                             mold); the imprint rides "imprint" — no place claim
          "aozora" => :structured, # the index's 初出 first publication (class composition),
          #                          else the 底本 first-edition year (class edition)
          "archiv-slav-phil" => :structured, # each volume's title-page year
          "bdcamoes" => :structured,
          "bfm" => :iso_keys,
          "bg-wikisource" => :structured,
          "bu-ajami" => :structured, # P124-1: a typed source-reference year or a date the item
          #                            page states (authorship eras class "composition");
          #                            place = the manuscript's Provenance
          "cbeta" => :dynasty_band,
          "ccmh" => :bounds_keys,
          "classical-modern" => :work_era, # the work's attributed era (config/work_eras.yml,
          #                                  keyed on metadata "book"), composition class
          "cme" => :edition_year_text,
          "corpus-corporum" => :structured,
          "corpus-gysseling" => :bounds_keys,
          "corpus-oudnederlands" => :bounds_keys,
          "croala" => :year_range,
          "cs-wikisource" => :edition_year_text,
          "ctilc" => :structured,
          "dacon" => :structured,
          "dcs" => :time_slot_band, # the chapter's DCS composition time slot → the ruled
          #                           "DCS time slot N" period_bands rows, composition class
          "damos" => :period_label, # the Aegean ceramic-phase chronology ("LM IIIA2 or LM
          #   IIIB") bands only once period_bands.yml carries ruled rows; the
          #   site/findspot place hash projects meanwhile

          "dharma-deccan" => :structured, # P118-2: Ollett's origDate + the Vengī metadata TSV;
          #                                 place = the origPlace placeName (findspot)
          "dharma-mdt" => :structured, # P118-4: the rows' own Date CE / range envelopes
          #                              (certainty + evidence ride the date hash)
          "dharma-tamil" => :structured, # P120: the title's era-typed year (Śaka, Kollam —
          #                                config/eras.yml); regnal years stay verbatim
          "diccas" => :structured, # each book's byline author-life span (AH/CE pairs read
          #                          by magnitude), its own class composition; the
          #                          Qurʾān book has no byline and stays undated
          "diorisis" => :signed_year_key,
          "disco" => :author_century_band,
          "dta" => :year_range,
          "ebl" => :period_label,
          "edr" => :structured,
          "eebo-tcp" => :structured,
          "elektire" => :structured, # P117-2: the portal's century of origin as an
          #                            envelope (composition class)
          "elephantine" => :structured,
          "eltec-srp" => :structured, # P117-2: the firstEdition's typed years, place
          #                             = its pubPlace (publication place)
          "first1k-greek" => :edition_year_text,
          "fornsvenska" => :compact_date_keys,
          "gams-zrcalo" => :structured,
          "glaux" => :signed_bounds_keys,
          "gu-wikisource" => :edition_year_text, # P120-3: the scan Index's verbatim
          #                                         વર્ષ= print year (date_class edition)
          "guaman-poma" => :structured,
          "honkoku" => :ndl_catalog_date, # the NDL catalog record the HonkokuNdlCatalog join
          #                                  writes for NDL-held materials (出版日 envelope),
          #                                  else the label's nengō "date" (parse time)
          "hr-wikisource" => :era_band_key,
          "iedc" => :iso_prefix_key,
          "ig-cyprus" => :structured, # IG XV 1,1: origDate prose, unsigned BCE years and
          #                             centuries (the syllabary's era); place = origPlace
          "itant" => :structured,
          "itkc" => :structured,
          "ja-wikisource" => :header_year_or_era_band, # the page {{header}} year= (the work's
          #                                               own year, composition class) else the
          #                                               era-category band (precision era)
          "ko-wikisource-mk" => :structured,
          "kannada-texts" => :structured, # P118-3: the repo README's work dates
          #                                 (941, 953, ca. 1042), composition class
          "kdsp" => :structured,
          "korba" => :structured,
          "litopys" => :era_band_key,
          "local-library" => :year_key,
          "mdz-protestant" => :structured,
          "menota" => :structured,
          "mk-wikisource" => :structured,
          "ms-wikisource" => :structured, # P120-3: the manuscript's stated date (header
          #                                 year= / Index Year=; "abad ke-N" a century)
          "ndl-kotenseki" => :structured,
          "obi-burmese" => :ce_year_text,
          "ociana" => :script_band, # the record's script TRADITION banded through the ruled
          #                           ANA period_bands rows (precision era); site + region/
          #                           country + the WGS84 pair place it; its findDate is the
          #                           DISCOVERY date (survey year), never a dating claim
          "ogham" => :century_prose,
          "okhc" => :year_key,
          "openmgh" => :printed_year_text,
          "papyri-ddbdp" => :structured, # the DCLP literary documents' header origDate
          #                                envelope + findspot (PapyriHeader); the DDbDP
          #                                texts carry no date/place keys — their rows are
          #                                the HGV walk's (axis_source hgv), never doubled
          # the Perseus family: the sourceDesc imprint year of the printed
          # edition each encoding follows (date_class edition); the works'
          # composition eras come from the TLG concordance lane instead
          "perseus-greek" => :edition_year_text,
          "perseus-latin" => :edition_year_text,
          "pl-wikisource" => :era_band_key,
          "prague-bible-1488" => :structured,
          "prilit" => :year_range,
          "ref" => :structured,
          "rem" => :structured,
          "ren" => :structured,
          "rsti" => :place_only,
          "ru-wikisource" => :era_band_key,
          "scat" => :structured, # the release catalog's century (the witness's, beside the
          #                        shelfmark) as a century envelope; no place claim
          "seal" => :period_label,
          "siddham" => :structured, # P118-4: the title's era-typed year (config/eras.yml)
          #                           or century attribution
          "sii-clean" => :structured, # P122-3: the SII heading's A.D. / Śaka year or the
          #                             summary's reign line; place = the heading's village
          "sillok" => :structured,
          "sjw" => :structured,
          "sl-wikisource" => :structured,
          "slavistics-pd" => :structured, # the text's own edition year (a facsimile
          #                                 reprint keeps its first edition's); the imprint
          #                                 rides "imprint", never "place" — no place claim
          "soas-tibetan" => :century_prose,
          "stgall-priscian" => :structured, # the manuscript's copying (AD 850–1, upstream's
          #                                   statement) on every page; orig_place "Ireland (?)"
          #                                   — upstream's hedge — while St Gallen (the holding
          #                                   library) rides "repository", never a place claim
          "syriac-corpus" => :when_key,
          "th-wikisource" => :edition_year_text, # P120-3: the Index ปี= print year,
          #                                         BE converted to CE (date_class edition)
          "ticha" => :structured,
          "titus-bactrian" => :structured,
          "titus-manichaica" => :place_only,
          "titus-sogdian" => :place_only, # the page findspot (one site every line resolves to)
          "titus-tocharian-a" => :place_only,
          "titus-tocharian-b" => :place_only, # the A family's findspot mining
          "uk-wikisource" => :era_band_key,
          "viet-wikisource" => :structured,
          "vuk-danicic" => :structured, # P117-2: the translation era per testament
          #                               (NT 1847, OT 1865–1868), composition class
          "zh-wikisource" => :dynasty_band
        }.freeze

        SLUGS = SHAPES.keys.freeze

        # Attributed-era dating, its own labeled class (P104-1): sources whose envelopes date the WORK's
        # composition era (author-era), not an object — their rows carry
        # date_class "composition". croala's year ranges were the class's
        # precedent (its lect=dates posture rides exactly these bands).
        COMPOSITION = %w[croala diorisis glaux disco vuk-danicic elektire kannada-texts].freeze

        # P104-1: sources whose place claim rides a differently-named
        # metadata field. An override key is a findspot vocabulary with
        # explicit unknown-class values ("Unknown"), which mint no place
        # — the coptic-lane NO_PLACE stance; the default "place" key's
        # behavior is untouched.
        PLACE_KEYS = {
          "seal" => "provenance", "rsti" => "findspot", "titus-tocharian-a" => "findspot",
          "titus-manichaica" => "findspot",
          "titus-sogdian" => "findspot",
          "titus-tocharian-b" => "findspot",
          # P109-4: eebo-tcp documents ARE the early-modern prints — the
          # imprint place is the artifact's own production place (39k+
          # London). The parse-time bare town (imprint_place) is the
          # registry-shaped key and answers first; a conjecture doc
          # carries none and falls back to the verbatim imprint, cleaned
          # of the ESTC-style bracket/colon furniture — uncertainty never
          # reads as a claim, and no placed doc loses its name. The TCP's
          # own pub_place (Ann Arbor) is lineage, exempted.
          "eebo-tcp" => %w[imprint_place source_pub_place],
          # P109-4: the ReM header's origin scriptorium ("Vorau",
          # "Siegburg (?)") — uncertainty markers ride verbatim.
          "rem" => "orig_place",
          # P118-R4 S5: the IEDC record's toponym LIST (143 of 1,316 docs,
          # censused 2026-10-11) — see #toponym_claim.
          "iedc" => "toponyms",
          # The OBI header's PLACE OF ORIGIN (720 of 1,121 files, census
          # 2026-10-18: "Mt. Tuyin, Bagan", "Hsu-pyu-kun village, Natogyi").
          "obi-burmese" => "place_of_origin",
          # The places sweep (census 2026-10-21): the Gysseling atlas
          # localizes 63 of 2,226 texts to a dialect REGION only
          # ("Holland-West", "Zeeland") — the region answers when no town
          # does, a declared-coarse claim at region grain; the region
          # itself facets on every doc (config/facet_map.yml).
          "corpus-gysseling" => %w[place region],
          # The Old Dutch witnessLocalization: 7 of the 17 region-bearing
          # works name no place ("Zuid-Nederrijn", "Utrecht") — same rule.
          "corpus-oudnederlands" => %w[place region],
          # KorBa's pubPlace role=region (the corpus's own classification
          # of the print/writing place) answers for the 117 of 2,091
          # texts with no role=place town (sejm acts, sermons).
          "korba" => %w[place region],
          # The NDL bibliographic record's 出版地 list (6,037 of 41,685
          # docs, ~5,040 naming a real place; census 2026-10-21). The
          # digitized item IS the print or manuscript, so its production
          # place is the artifact's own — the eebo imprint stance. Names
          # ride verbatim (京 · 東都 · 浪華 … — the historical spellings;
          # no registry rows yet, so unresolved: declared coarse).
          "ndl-kotenseki" => "publication_places",
          # ReF: the prints place by "place" (92 of 190), the manuscripts by
          # the header text-place — the Schreibort, the writing place (36;
          # the two never co-occur, census 2026-10-21).
          "ref" => %w[place text-place]
        }.freeze
        # ReF's text-place label ("Schreibort:", "(Schreibort)",
        # "Herstellungsort/Schreibort") — furniture, stripped before the
        # sentinel check; the hedges beside it ("(?)", "wahrsch.") stay.
        PLACE_LABEL = %r{\(?\s*(?:Herstellungsort/)?Schreiborte?\s*\)?\s*[:.]?}i
        # "not listed in teo" — rsti's own absent-findspot sentinel;
        # "s.l" — the imprint world's sine loco (eebo, 1,311 docs);
        # "?" — a bare unknown mark (obi-burmese's PLACE OF ORIGIN, 29);
        # "zagranica" (abroad, 17) / "inny" (other, 6) — KorBa's region
        # classes that name no place (they still facet, as claims);
        # "place of origin unknown" — gams-zrcalo's TEI origPlace absence;
        # 出版地不明 / 製作地不明 / 書写地不明 — the NDL record's publication /
        # production / copying place unknown (ndl-kotenseki, 855 docs).
        NO_PLACE = ["unknown", "unclear", "uncertain", "none", "not listed in teo",
                    "s.l", "s.l.", "?", "zagranica", "inny", "place of origin unknown",
                    "出版地不明", "製作地不明", "書写地不明", "unbekannt"].freeze

        # P59-0: sources whose reversed upstream bounds order-normalize at
        # projection (EDR's "later - earlier" ranges, BFM's swapped ISO
        # attrs — signs are upstream-explicit, so a swap is always safe).
        # Elephantine is deliberately absent: its repair (BCE-default
        # negation + a nested-TEI fallback) needs the origDate nodes and
        # lives in ElephantineTeiParser — a blind swap here would mint
        # "399-550 CE" out of an unsigned BCE pair.
        # corpus-corporum joined P96 (the health reversed-bounds anomaly: 23
        # rows where the composition-envelope ladder minted "later-earlier";
        # signs are upstream-explicit CE years, so the swap is safe).
        # fornsvenska/glaux/disco joined P104-1: signs are upstream-explicit
        # (all-CE compact dates, signed year strings, CE centuries), so the
        # defensive swap stays safe.
        REORDER = %w[edr bfm itant croala corpus-corporum corpus-gysseling
                     corpus-oudnederlands fornsvenska glaux disco].freeze

        BATCH = 2_000

        # Shapes whose ruled table is keyed per source — called with the
        # slug beside the metadata (config/work_eras.yml,
        # config/archive_axes.yml).
        TABLE_SHAPES = %i[work_era archive_axes].freeze

        # P118-R4 S3 (the held-but-dark audit): per-id date LISTS a source
        # ships beside its texts (canonical/<slug>/<file>, "ID<TAB>date"
        # lines) — a builder-side JOIN on the metadata "idno" that dates
        # documents the header date left unbounded. A FALLBACK only: a
        # header-bounded document keeps its own envelope. eebo-tcp: the
        # TCP's per-phase lists (fetched by EeboTcpFetch since P109; ~10.3k
        # of the 60,325 docs carried only an unparseable imprint date such
        # as "1700?]" or "[between 1670-1696]").
        SIDECAR_DATES = {
          "eebo-tcp" => %w[eebo_phase1_IDs_and_dates.txt EEBO_Phase2_IDs_and_dates.txt].freeze
        }.freeze

        # One side of a TCP list date: four characters, digits or "u"
        # (unknown digit — widened to 0 on the lower side, 9 on the upper),
        # an optional "?" (the list's own uncertainty mark; the bounds stay
        # the claim). "9999" and "uuuu" are the open-ended sentinels.
        TCP_SIDE = /\A(\d[\du]{3}|uuuu)\??\z/

        module_function

        # Returns {slug => rows} for every registered source.
        def build(catalog:, canonical_dir: nil)
          SLUGS.to_h { |slug| [slug, build_source(catalog, slug, canonical_dir: canonical_dir)] }
        end

        # The per-source seam (P47-r3): drop this source's rows, re-project
        # — SyncRunner calls it post-load so the lane never lags a sync.
        # +canonical_dir+ arms the SIDECAR_DATES join (absent = header
        # dates only, the pre-P118 projection).
        def refresh_source!(catalog:, slug:, canonical_dir: nil)
          return 0 unless SHAPES.key?(slug)

          catalog[:document_axes].where(axis_source: slug).delete
          build_source(catalog, slug, canonical_dir: canonical_dir)
        end

        # {id => raw date} from the source's declared list files (absent
        # files or directory → empty: lane off, never an error).
        def sidecar_dates(slug, canonical_dir)
          files = SIDECAR_DATES[slug]
          return {} if files.nil? || canonical_dir.nil?

          files.each_with_object({}) do |name, dates|
            path = File.join(canonical_dir, slug, name)
            next unless File.file?(path)

            File.foreach(path, chomp: true) do |line|
              id, raw = line.delete("\r").split("\t", 2)
              dates[id.strip] = raw.strip unless id.nil? || raw.nil? || id.strip.empty?
            end
          end
        end

        # A TCP list date ("1625", "1670-1696?", "16uu", "1688-9999?") →
        # [not_before, not_after], or nil when it does not parse.
        def tcp_list_years(raw)
          sides = raw.to_s.strip.split("-", 2)
          return nil if sides.empty? || sides.any? { |side| !side.match?(TCP_SIDE) }

          low = sides.first.delete("?")
          high = (sides[1] || sides.first).delete("?")
          lower = low == "uuuu" ? nil : Integer(low.tr("u", "0"), 10)
          upper = %w[uuuu 9999].include?(high) ? nil : Integer(high.tr("u", "9"), 10)
          return nil if lower.nil? && upper.nil?
          # One descending range in the lists (A87970 "1704-1689", header
          # imprint "1689?]"): the TCP lists are all-CE unsigned years, so
          # the order-normalizing swap is always safe; the raw keeps the
          # upstream spelling.
          return [upper, lower] if lower && upper && lower > upper

          [lower, upper]
        end

        def build_source(catalog, slug, canonical_dir: nil)
          shape = SHAPES.fetch(slug)
          source_id = catalog[:sources].where(slug: slug).get(:id)
          return 0 if source_id.nil?

          listed = sidecar_dates(slug, canonical_dir)
          inserted = 0
          buffer = []
          catalog[:documents]
            .where(source_id: source_id, withdrawn: false)
            .exclude(Sequel.like(:metadata_json, '%"kind":"translation"%'))
            .select(:id, :metadata_json)
            .order(:id)
            .paged_each do |doc|
              row = axis_row(doc, shape, reorder: REORDER.include?(slug),
                                         composition: COMPOSITION.include?(slug),
                                         place_key: PLACE_KEYS.fetch(slug, "place"),
                                         listed: listed, slug: slug)
              next if row.nil?

              buffer << row.merge(axis_source: slug)
              if buffer.size >= BATCH
                catalog[:document_axes].multi_insert(buffer)
                inserted += buffer.size
                buffer = []
              end
            end
          catalog[:document_axes].multi_insert(buffer) unless buffer.empty?
          inserted + buffer.size
        end

        # One document's axis row, or nil when it carries neither a date
        # bound nor a place claim (name, ref or coordinates).
        def axis_row(doc, shape, reorder: false, composition: false, place_key: "place", listed: {}, slug: nil)
          meta = JSON.parse(doc[:metadata_json].to_s)
          not_before, not_after, raw, precision, own_class =
            TABLE_SHAPES.include?(shape) ? send(shape, meta, slug) : send(shape, meta)
          if not_before.nil? && not_after.nil? && (list_raw = listed[meta["idno"].to_s]) &&
             (years = tcp_list_years(list_raw))
            not_before, not_after = years
            raw = list_raw
          end
          not_before, not_after = Timeline.normalize_interval(not_before, not_after, raw: raw) if reorder
          place, place_ref, lat, lon = if shape == :archive_axes
                                         archive_place(meta, slug)
                                       else
                                         place_claim(meta, key: place_key)
                                       end
          # A ref IS placement (P73-2): a doc carrying only a parseable
          # place ref rows too — the HGV place-only precedent extended.
          # P104-1 extends it once more: a coordinate pair alone places.
          return nil if not_before.nil? && not_after.nil? && place_ref.nil? && lat.nil? &&
                        (place.nil? || place.to_s.strip.empty?)

          dated = !(not_before.nil? && not_after.nil?)
          { document_id: doc[:id], not_before: not_before, not_after: not_after,
            date_raw: raw, place_name: place, place_ref: place_ref,
            place_lat: lat, place_lon: lon, precision: precision,
            date_class: own_class || (composition && dated ? "composition" : nil) }
        rescue JSON::ParserError
          nil
        end

        # "place" is a Hash ({"ancient" => …}, EDR/Elephantine; ogham's
        # townland/county/country ladder) or a bare string (croala — the
        # P44-i4 shape); the string IS the name. Returns
        # [name, ref, lat, lon].
        # P63-4: a hash carrying a bare "pleiades" id (itant — 497 docs
        # measured 2026-08-08, ALL joining the held index) lifts it into
        # place_ref, namespaced per Dp-b (a derivation mint, never a
        # verbatim upstream URL). Non-numeric values never mint.
        # P73-2: the "geonames" findspot ref (a verbatim URL —
        # 508 real GeoNames, 1 mislabeled Trismegistos URL, 13 doubled-URL
        # strays, measured 2026-08-10) lifts through the ONE ref reader:
        # whatever PlaceRefs honestly parses mints in its true namespace,
        # space-separated per the multi-claim convention; malformed
        # remainders mint nothing.
        # P104-1 (ogham): "logainm" gazetteer URLs ride verbatim (the EDH
        # URL precedent — no logainm namespace is minted); the WGS84 "geo"
        # pair lands in place_lat/place_lon (the rundata coordinates lane),
        # both-or-nothing; an "ancient"-less hash names itself from the
        # townland → county → country ladder, joined verbatim.
        # P104-1 (menota): a top-level "orig_place" string is the origin
        # claim and answers when no "place" key exists; repository/
        # settlement (the holding library — a PRESENT location) stay
        # metadata-only, the rundata origin-axis stance.
        def place_claim(meta, key: "place")
          # An ordered key list tries each in turn — the first key
          # carrying a value answers.
          key = key.find { |k| !meta[k].to_s.strip.empty? } || key.last if key.is_a?(Array)
          place = meta[key]
          return string_list_claim(place) if place.is_a?(Array) && place.all?(String)
          return toponym_claim(place) if place.is_a?(Array)

          if key != "place"
            # An overridden place key is a findspot vocabulary with explicit
            # unknown-class values -- those mint no place (never a name).
            # P109-4: imprint-catalog furniture (leading "[", trailing
            # ":"/","/"."/brackets — the ESTC transcription style eebo
            # carries) strips before the sentinel check and the mint.
            # The places sweep: the ReF header's "Schreibort" label is
            # catalog furniture too ("(Schreibort) Regensburg (?)").
            unless place.nil?
              place = place.to_s.gsub(PLACE_LABEL, " ").strip.sub(/\A[\[\s.:,;]+/, "")
                           .sub(/[\s:,.;\[\]]+\z/, "")
            end
            return [nil, nil, nil, nil] if place.nil? || !place.match?(/\p{L}/) ||
                                           NO_PLACE.include?(place.downcase)

            return [place, nil, nil, nil]
          end
          return [present_place(meta["orig_place"]), nil, nil, nil] if place.nil?
          return [place, string_place_ref(meta), nil, nil] unless place.is_a?(Hash)

          refs = []
          pleiades = place["pleiades"].to_s.strip
          refs << "pleiades:#{pleiades}" if pleiades.match?(/\A\d+\z/)
          refs += Nabu::PlaceRefs.ids(place["geonames"]).map { |ns, id| "#{ns}:#{id}" }
          # A generic "ref" field (papyri-ddbdp's DCLP findspot: verbatim
          # Trismegistos/Pleiades URLs) lifts through the same one reader.
          refs += Nabu::PlaceRefs.ids(place["ref"]).map { |ns, id| "#{ns}:#{id}" }
          refs += Array(place["logainm"]).map(&:to_s).reject(&:empty?)
          name = place["ancient"] ||
                 place.values_at("townland", "county", "country").compact.then do |ladder|
                   ladder.empty? ? nil : ladder.join(", ")
                 end
          [name, refs.empty? ? nil : refs.uniq.join(" "), *coordinates(place["geo"])]
        end

        # The orig_place fallback's value, nil for an unknown-class
        # sentinel (gams-zrcalo's "place of origin unknown").
        def present_place(value)
          value.nil? || NO_PLACE.include?(value.to_s.strip.downcase) ? nil : value
        end

        # A string place's sibling "place_ref" (croala's creation placeName
        # @ref — a Wikidata place URL) rides verbatim, the logainm precedent:
        # no wikidata namespace is minted. Only a URL self-identifies its
        # gazetteer; a bare number (2 croala files) or blank → nil.
        def string_place_ref(meta)
          ref = meta["place_ref"].to_s.strip
          ref.match?(%r{\Ahttps?://\S+\z}) ? ref : nil
        end

        # P118-R4 S5: a toponym list [{"name", "latitude", "longitude", …}]
        # (iedc). Every name joins the claim ("; ", the multi-place
        # convention); coordinates mint ONLY when exactly one toponym
        # carries a full pair — with two, which is THE document's point
        # is never guessed. Alternative readings stay metadata.
        def toponym_claim(list)
          topos = list.select { |topo| topo.is_a?(Hash) && !topo["name"].to_s.strip.empty? }
          return [nil, nil, nil, nil] if topos.empty?

          points = topos.filter_map do |topo|
            pair = coordinates("#{topo['latitude']}, #{topo['longitude']}")
            pair unless pair.include?(nil)
          end
          lat, lon = points.size == 1 ? points.first : [nil, nil]
          [topos.map { |topo| topo["name"].strip }.uniq.join("; "), nil, lat, lon]
        end

        # The places sweep: a bare string list (ndl-kotenseki's 出版地
        # list — co-publishers' cities). Catalog brackets anywhere in a
        # name are furniture ([京城], 〔江戸〕, 大[坂] — the cataloger's
        # supplied reading, the ESTC precedent); unknown markers and empty
        # brackets drop; the rest join "; " deduped, verbatim otherwise.
        LIST_FURNITURE = /[\[\]〔〕]/
        def string_list_claim(list)
          names = list.map { |name| name.gsub(LIST_FURNITURE, "").gsub(/\s+/, " ").strip }
                      .reject { |name| name.empty? || NO_PLACE.include?(name.downcase) }.uniq
          [names.empty? ? nil : names.join("; "), nil, nil, nil]
        end

        # A WGS84 "lat, lon" string → [lat, lon] floats, both-or-nothing
        # (a lone or malformed coordinate is not a point — never guessed).
        GEO_PAIR = /\A(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\z/
        def coordinates(geo)
          match = GEO_PAIR.match(geo.to_s.strip) or return [nil, nil]

          [Float(match[1]), Float(match[2])]
        end

        def period_label(meta)
          seleucid_era(meta["date"]) || king_reign(meta["date"]) || period_band(meta)
        end

        # P104-1 (attributed-era dating, its own labeled class): the cbeta header byline's dynasty seat
        # (metadata "dynasty", minted by CbetaTeiParser from the
        # teiHeader <author> — "後秦 佛陀耶舍共竺佛念譯") bands through the
        # ruled table's sinological rows. The claim is an ATTRIBUTED
        # TRANSLATION ERA, not a typed date, so the row wears precision
        # "era" — the distinct honestly-labeled class the ruling names —
        # and date_raw carries the whole byline verbatim. An unruled seat
        # (an Indian master's attribution, 失譯 "translator lost", 日本 —
        # a country, not an era claim) mints nothing.
        def dynasty_band(meta)
          band = Nabu::PeriodBands.default&.lookup(meta["dynasty"])
          return [nil, nil, nil, nil] if band.nil?

          [band[0], band[1], meta["author"] || meta["dynasty"], "era"]
        end

        # ociana: the record's script TRADITION (Safaitic, Hismaic,
        # Dadanitic, Taymanitic) bands through the ruled ANA rows of
        # period_bands.yml — the tradition's conventional span, an
        # attributed claim worn as precision "era" (the deposit dates no
        # inscription). A script without a ruled row (the Thamudic
        # pending file, the non-ANA scripts) mints no date.
        def script_band(meta)
          band = Nabu::PeriodBands.default&.lookup(meta["script"])
          return [nil, nil, nil] if band.nil?

          [band[0], band[1], "#{meta['script']} script tradition", "era"]
        end

        # dcs: the chapter's composition time slot (chapter-info.xml
        # dcsTimeSlot "1".."5") bands through the ruled "DCS time slot N"
        # rows — attributed composition-era dating, its own class. The
        # "None" slot (17 chapters) has no row and mints nothing.
        def time_slot_band(meta)
          slot = meta["dcs_time_slot"].to_s.strip
          band = Nabu::PeriodBands.default&.lookup("DCS time slot #{slot}") unless slot.empty?
          return [nil, nil, nil] if band.nil?

          [band[0], band[1], "DCS time slot #{slot}", "era", "composition"]
        end

        # The ruled per-work era table (config/work_eras.yml): the work
        # named by the table's key field bands to its attributed
        # composition era — class composition, precision era, the raw
        # naming the work and the era label. A work declared without an
        # era (contested) or absent from the table mints nothing.
        def work_era(meta, slug)
          table = Nabu::WorkEras.default
          work = table && meta[table.key_for(slug).to_s]
          era = work && table.lookup(slug, work)
          return [nil, nil, nil] if era.nil?

          [era.band[0], era.band[1], "#{work} — attributed composition era #{era.label}", "era", "composition"]
        end

        # The ruled archive table (config/archive_axes.yml): reign volume →
        # the held regnal table's whole-reign span, else the archive's own
        # stated span, else the source's corpus band.
        def archive_axes(meta, slug)
          dating = Nabu::ArchiveAxes.default&.dating(slug, meta["archive"], meta["designation"])
          return [nil, nil, nil] if dating.nil?

          [dating.band[0], dating.band[1], dating.raw, dating.precision]
        end

        # The archive's findspot at archive grain, with the held refs.
        def archive_place(meta, slug)
          name, ref = Nabu::ArchiveAxes.default&.place(slug, meta["archive"])
          [name, ref, nil, nil]
        end

        # A bare integer year → a one-year envelope (okhc). Anything else
        # (absent, string, float) mints nothing — no bounds invented.
        def year_key(meta)
          year = meta["year"]
          return [nil, nil, nil] unless year.is_a?(Integer)

          [year, year, year.to_s]
        end

        # P108-8: orig_date {"when" => "0337", "type" => …} — the zero-
        # padded year is the envelope; a composition-typed row classes
        # itself (the 5th tuple element), translations stay class-less.
        def when_key(meta)
          date = meta["orig_date"]
          return [nil, nil, nil] unless date.is_a?(Hash)

          klass = date["type"] == "composition" ? "composition" : nil
          year = date["when"].to_s[/\A0*(\d{3,4})\z/, 1]
          return [Integer(year, 10), Integer(year, 10), date["text"] || date["when"], nil, klass] if year

          # The live census (2026-09-29): 608 of 632 docs date in century
          # PROSE only — the century grammar is the fallback lane.
          nb, na, raw = century_prose({ "period" => date["text"] })
          [nb, na, raw, nil, nb && klass]
        end

        # P108-8: obi-burmese "CS 586(580) = CE 1224(1218) …" — every CE
        # year in the string joins the envelope. The CE equivalences are
        # upstream's own, but their arithmetic is wrong on two live rows
        # (vol4 n°65 "CE 7380", vol6 n°28 "CE 2960" — a BE year mislabeled
        # CS), so a CE year beyond the corpus ceiling (the 1998 edition;
        # nothing it prints postdates it) never joins the envelope. When a
        # string's CE years are ALL implausible, its CS years convert here
        # instead (CE = CS + 638, same ceiling); CS-only strings still
        # mint nothing — the deliberate P108-8 scope.
        OBI_CE_CEILING = 2000

        def ce_year_text(meta)
          text = meta["date"].to_s
          years = era_years(text, "CE")
          return [nil, nil, nil] if years.empty?

          plausible = years.select { |y| y <= OBI_CE_CEILING }
          if plausible.empty?
            plausible = era_years(text, "CS").map { |y| y + 638 }
                                             .select { |y| y <= OBI_CE_CEILING }
          end
          return [nil, nil, nil] if plausible.empty?

          [plausible.min, plausible.max, text.strip]
        end

        # Every year in the contiguous span after an era label — the
        # censused grammar covers plain years, parenthetical alternates
        # "586(580)", dash ranges "1763-1776" (and chains "1341-1342-…"),
        # and the open-ended "1000+".
        def era_years(text, label)
          text.scan(/\b#{label}\s*([\d()+\-–]+)/)
              .flatten
              .flat_map { |span| span.scan(/\d{3,4}/) }
              .map { |y| Integer(y, 10) }
        end

        ORDINAL_WORDS = %w[zeroth first second third fourth fifth sixth seventh eighth
                           ninth tenth eleventh twelfth thirteenth fourteenth fifteenth
                           sixteenth seventeenth eighteenth nineteenth twentieth].freeze

        # P108-8: the censused ogham/soas century grammar — ordinal words
        # or digit ordinals, optional early/mid/late halves, ranges via
        # "to". Century N spans [100(N-1), 100N]; early = its first half,
        # late = its second, mid = the middle half. Every century mention
        # joins the envelope; an unparseable text mints no dates (raw
        # rides only when a place mints the row).
        def century_prose(meta)
          text = meta.dig("date", "text") || meta["period"]
          text = text.to_s
          mentions = century_mentions(text)
          return [nil, nil, nil] if mentions.empty?

          [mentions.map(&:first).min, mentions.map(&:last).max, text.strip]
        end

        # "first/second half of the Nth century" folds into the
        # early/late vocabulary BEFORE scanning — otherwise "Second"
        # would read as the 2nd century (the syriac-corpus prose,
        # live-censused 2026-09-29).
        def fold_half_phrases(text)
          text.gsub(/first\s+half\s+of\s+(?:the\s+)?/i, "early ")
              .gsub(/second\s+half\s+of\s+(?:the\s+)?/i, "late ")
              .gsub(/middle\s+of\s+(?:the\s+)?/i, "mid ")
        end

        def century_mentions(text)
          text = fold_half_phrases(text)
          found = []
          text.scan(/(?:(early|mid|late)[- ])?(?:(\d{1,2})(?:st|nd|rd|th)\b|\b([A-Za-z]+)\b)/i) do |half, digit, word|
            n = digit ? Integer(digit, 10) : ORDINAL_WORDS.index(word.to_s.downcase)
            next if n.nil? || n.zero?

            base = [(n - 1) * 100, n * 100]
            found << case half&.downcase
                     when "early" then [base[0], base[0] + 50]
                     when "late" then [base[0] + 50, base[1]]
                     when "mid" then [base[0] + 25, base[1] - 25]
                     else base
                     end
          end
          found
        end

        def period_band(meta)
          band = Nabu::PeriodBands.default&.lookup(meta["period"])
          band ? [band[0], band[1], meta["period"]] : [nil, nil, nil]
        end

        # The exact Seleucid conversion (P81-1). SE 1 begins Nisanu
        # (spring) 311 BCE; a clean SE year Y therefore spans the two
        # Julian years (312−Y) and (311−Y) BCE, crossing into CE with no
        # year 0 (SE 311 = 1 BCE–1 CE). Year grain only — the Babylonian
        # lunar months drift against Julian years, so month/day refine
        # the RAW, never the bounds.
        def seleucid_era(date)
          return nil unless date.is_a?(Hash) && date["isSeleucidEra"] == true

          se = clean_component(date["year"])
          return nil if se.nil? || !se.positive?

          tail = %w[month day].filter_map do |part|
            value = clean_component(date[part])
            value && "#{part} #{value}"
          end
          [signed_from_bce(312 - se), signed_from_bce(311 - se), (["SE #{se}"] + tail).join(", ")]
        end

        # A regnal date object bands to the king's OWN reign span — the
        # "555–539" upstream string, unsigned BCE, descending. Anything
        # else (ascending, era-crossing, prose) is ambiguous and skips to
        # the period band.
        KING_REIGN = /\A(\d{1,4})\s*[–-]\s*(\d{1,4})\z/
        def king_reign(date)
          king = date.is_a?(Hash) ? date["king"] : nil
          return nil unless king.is_a?(Hash)

          match = KING_REIGN.match(king["date"].to_s.strip) or return nil

          from = Integer(match[1], 10)
          to = Integer(match[2], 10)
          return nil unless from > to # descending = unambiguously BCE

          [-from, -to, "#{king['name']} (#{king['date']})".strip]
        end

        # A date-object component's integer value, nil when broken,
        # uncertain or non-numeric — never a guessed digit.
        def clean_component(field)
          return nil unless field.is_a?(Hash)
          return nil if field["isBroken"] || field["isUncertain"]

          value = field["value"].to_s
          /\A\d+\z/.match?(value) ? Integer(value, 10) : nil
        end

        # Signed historical year from a BCE magnitude that may cross the
        # era: 93 → −93 (93 BCE), 0 → 1 (1 CE — there is no year 0).
        def signed_from_bce(bce)
          bce >= 1 ? -bce : 1 - bce
        end

        # A per-document "class" => "composition" (bu-ajami, P124-1: one
        # source dating some items by witness and others by authorship era)
        # classes its own row — the when_key precedent; "edition" likewise
        # (aozora: the 底本 print year where no first publication is
        # stated); any other value, or none, stays class-less.
        STRUCTURED_CLASSES = %w[composition edition].freeze

        def structured(meta)
          date = meta["date"]
          return [nil, nil, nil] unless date.is_a?(Hash)

          klass = STRUCTURED_CLASSES.include?(date["class"]) ? date["class"] : nil
          [date["not_before"], date["not_after"], date["raw"], nil, klass]
        end

        # iedc (P107-2): date_iso is "YYYY", "YYYY-MM" or "YYYY-MM-DD" —
        # the leading year is the one-year envelope; the prose date_text
        # rides as raw.
        def iso_prefix_key(meta)
          match = meta["date_iso"].to_s.match(/\A(\d{3,4})/)
          year = match && Integer(match[1], 10)
          [year, year, meta["date_text"]]
        end

        def iso_keys(meta)
          not_before = iso_year(meta["date_not_before"])
          not_after = iso_year(meta["date_not_after"])
          [not_before, not_after, meta["date"]]
        end

        def iso_year(value)
          match = value.to_s.match(/\A(-?\d{1,4})-\d{2}-\d{2}\z/)
          match && Integer(match[1], 10)
        end

        # Top-level integer bounds (corpus-gysseling / corpus-oudnederlands):
        # not_before/not_after ride the metadata root beside date_raw; a
        # string "place" (the Gysseling atlas resolution) rides place_name
        # exactly like croala's.
        def bounds_keys(meta)
          [meta["not_before"], meta["not_after"], meta["date_raw"]]
        end

        # fornsvenska (P104-1): upstream's own compact YYYYMMDD bounds —
        # "12800101"/"12901231" → 1280/1290, the display "date" string as
        # raw. Anything not eight digits mints nothing.
        COMPACT_DATE = /\A(\d{4})\d{4}\z/
        def compact_date_keys(meta)
          not_before = compact_year(meta["datefrom"])
          not_after = compact_year(meta["dateto"])
          return [nil, nil, nil] if not_before.nil? && not_after.nil?

          [not_before, not_after, meta["date"]]
        end

        def compact_year(value)
          match = COMPACT_DATE.match(value.to_s.strip)
          match && Integer(match[1], 10)
        end

        # diorisis (P104-1): the signed composition year string ("-245") —
        # a one-year envelope. Year 0 or non-numeric mints nothing.
        def signed_year_key(meta)
          year = signed_year(meta["creation_date"])
          year ? [year, year, meta["creation_date"].to_s.strip] : [nil, nil, nil]
        end

        # glaux (P104-1): signed composition bounds strings.
        def signed_bounds_keys(meta)
          not_before = signed_year(meta["start_date"])
          not_after = signed_year(meta["end_date"])
          return [nil, nil, nil] if not_before.nil? && not_after.nil?

          [not_before, not_after, [not_before, not_after].compact.join("–")]
        end

        def signed_year(value)
          match = /\A(-?\d{1,4})\z/.match(value.to_s.strip) or return nil

          year = Integer(match[1], 10)
          year.zero? ? nil : year # no year 0 — skipped honestly, never shifted
        end

        # disco (P104-1): the author's own birth/death CE centuries band
        # the composition envelope ("17"/"17" → 1601–1700 — honest bounds,
        # never a midpoint). The author "birthplace" is biography, not a
        # composition place — deliberately never projected.
        def author_century_band(meta)
          birth = century_int(meta["birth_century"])
          death = century_int(meta["death_century"])
          return [nil, nil, nil] if birth.nil? && death.nil?

          raw = ["b. #{meta['birth_century']}th c.", "d. #{meta['death_century']}th c."].join(", ")
          [birth && (((birth - 1) * 100) + 1), death && (death * 100), raw]
        end

        def century_int(value)
          match = /\A\d{1,2}\z/.match(value.to_s.strip)
          match && Integer(match[0], 10)
        end

        # P109-4 (the unmined-metadata drain, aggressive-mining law): the source EDITION's print year —
        # cme's source_date ("1988", "c.1976", "1904, 1905") and openmgh's
        # printed_date. Every plausible 4-digit year in the string joins
        # the envelope; the row carries date_class "edition" (the 5th
        # tuple element) so an edition date NEVER masquerades as the
        # text's composition or artifact dating on the timeline.
        def edition_year_text(meta) = edition_years(meta["source_date"])
        def printed_year_text(meta) = edition_years(meta["printed_date"])

        def edition_years(text)
          years = text.to_s.scan(/\b(1[4-9]\d\d|20\d\d)\b/).flatten.map { |y| Integer(y, 10) }
          return [nil, nil, nil] if years.empty?

          [years.min, years.max, text.to_s.strip, nil, "edition"]
        end

        # ja-wikisource (P109-1): the adapter's era-category envelope —
        # {"not_before", "not_after", "raw" => "平安時代"} — rides as an
        # era attribution (precision "era", the cbeta dynasty precedent).
        # honkoku: the "ndl_catalog" record (Nabu::HonkokuNdlCatalog) — the
        # NDL item's own 出版日 envelope, the raw labeled with the record it
        # came from so no reader takes it for honkoku's claim. The material
        # IS the NDL item transcribed, so the row keeps the artifact class.
        # Without a record, the material label's own nengō date (the
        # adapter's parse-time "date", owner-ruled 2026-10-20) answers.
        def ndl_catalog_date(meta)
          record = meta["ndl_catalog"]
          date = record.is_a?(Hash) ? record["date"] : nil
          return structured(meta) unless date.is_a?(Hash)

          [date["not_before"], date["not_after"], "NDL catalog record (pid #{record['pid']}): #{date['raw']}"]
        end

        # ja-wikisource: the header's integer "year" — a one-year envelope,
        # its own labeled class "composition" (the work's year as the wiki
        # states it) — outranks the coarser era-category band. An era-typed
        # year= (寛政2, converted at parse) keeps its spelling as the raw.
        def header_year_or_era_band(meta)
          year = meta["year"]
          return [year, year, meta["year_raw"] || year.to_s, nil, "composition"] if year.is_a?(Integer)

          era_band_key(meta)
        end

        def era_band_key(meta)
          band = meta["era_band"]
          return [nil, nil, nil] unless band.is_a?(Hash) && band["not_before"] && band["not_after"]

          [band["not_before"], band["not_after"], band["raw"], "era"]
        end

        # ogham (P104-1): no date lane at all — the "date" is free prose
        # ("Fifth century…"), honestly unparsed; registration serves the
        # place hash (townland/county/country + geo + logainm) alone.
        def place_only(_meta)
          [nil, nil, nil]
        end

        def year_range(meta)
          date = meta["date"]
          return [nil, nil, nil] unless date.is_a?(String)

          case date.strip
          when /\A(\d{3,4})\s*[-–]\s*(\d{3,4})\z/
            [Integer(::Regexp.last_match(1), 10), Integer(::Regexp.last_match(2), 10), date]
          when /\A(\d{3,4})\z/
            year = Integer(::Regexp.last_match(1), 10)
            [year, year, date]
          else
            # ca./floruit/prose datings: skipped honestly, never guessed.
            [nil, nil, nil]
          end
        end
      end
    end
  end
end
