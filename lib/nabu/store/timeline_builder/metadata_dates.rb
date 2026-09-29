# frozen_string_literal: true

require "json"

require_relative "../../period_bands"
require_relative "../../place_refs"
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
      #   :year_key — a top-level integer "year" (okhc P92-6/Q64: the
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
      #   :place_only — no date reading at all; the source registers for
      #     the PLACE lane below (ogham P104-1: its "date" is free prose,
      #     honestly unparsed, but the place hash carries townland/county/
      #     country + WGS84 "geo" + logainm refs).
      #
      # == The composition class (№R-70 grade 2, ruled 2026-09-26)
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
          "edr" => :structured,
          "elephantine" => :structured,
          "itant" => :structured,
          "sillok" => :structured, # P78-1: the volume's 서기 year, one-year envelope
          "sjw" => :structured,    # P78-2: same shape, per reign-year member
          "itkc" => :structured,   # P78-7: the 원문간행년 original print year, per work
          "bdcamoes" => :structured, # P80-7: the header's YY: publication year, per work;
          #                            unresolved "18??" marks carry raw only and mint nothing
          "ctilc" => :structured, # P80-8: the ANY publication year, one-year envelope
          "ref" => :structured, # P81-1: the header date lane (clean parses) with the
          #                       century-half time grid as the prose fallback
          "corpus-corporum" => :structured, # P81-1: work_composition / author life band
          #                                   (fetch checkpoint) / teiHeader author_date
          "menota" => :structured, # P82-1: the msDesc origDate's own notBefore/notAfter
          #                          attrs, raw text preserved; attr-less dates ride raw only
          "eebo-tcp" => :structured, # P83-1: the BIBLFULL imprint year through the censused
          #                            molds (85.7% dated on the 3,325-file sample); ?/ca.
          #                            uncertainty stays raw-only — no bounds invented
          "dacon" => :structured, # P88-A4: the deposit's own century attributions
          #                         (cnew<cc> stems) as per-document envelopes
          "ko-wikisource-mk" => :structured, # P96 hygiene: the per-work year envelope was
          #                                      minted at parse but never projected (the
          #                                      health timeline-dark anomaly, cleared)
          "viet-wikisource" => :structured, # P96 hygiene: same shape, same clearing
          "corpus-gysseling" => :bounds_keys, # P96 hygiene: TOP-LEVEL integer not_before/
          #                                     not_after + date_raw (+ a string place —
          #                                     the croala mold); dark until now
          "corpus-oudnederlands" => :bounds_keys, # P96 hygiene: same top-level bounds shape
          "ccmh" => :bounds_keys, # P105-5c: the curated witness-dating overlay (the five
          #                         codices' paleographic century bands; Adapters::Ccmh::
          #                         DATING) — the vitae stay declared-undated
          "okhc" => :year_key, # P92-6 (Q64): the per-record integer year — projected
          #                      from the CATALOG's stored metadata, no re-parse of the
          #                      1.2M documents (the whole point of the lane)
          "bfm" => :iso_keys,
          "croala" => :year_range,
          "prilit" => :year_range, # P95-1: the printSource date @when, clean "1696" strings
          "dta" => :year_range, # P94 (№R-59): the sourceDesc print year, clean "1784"
          #                       strings on every document; the de:early staging rides
          #                       LectDates date-band inference off these envelopes
          "ebl" => :period_label,
          "fornsvenska" => :compact_date_keys, # P104-1: upstream's own per-text
          #                                      datefrom/dateto, the pending posture served
          "diorisis" => :signed_year_key, # P104-1: creation_date — composition class
          "glaux" => :signed_bounds_keys, # P104-1: start_date/end_date — composition class
          "disco" => :author_century_band, # P104-1: author life band — composition class
          "ogham" => :century_prose, # P104-1 places; P108-8: the century-prose date
          #                              grammar bands the "Fifth century …" texts too
          "seal" => :period_label, # P104-1 (Q77 under №R-70): the Texts Hierarchy period
          #                          strings (Old Babylonian …, on ALL 408 docs) band via
          #                          the ruled table — the posture's own named candidate;
          #                          the Provenance field rides as place (PLACE_KEYS)
          "iedc" => :iso_prefix_key, # P107-2: the parenthesized ISO substring the
          #                              adapter extracts from the prose date string
          #                              ("… (1183-10)" -> date_iso); year envelope,
          #                              date_text verbatim as raw
          "syriac-corpus" => :when_key, # P108-8 (the Q83 slice): orig_date.when zero-padded
          #                                 year; the per-doc type field classes composition
          #                                 rows itself (translations dated, class-less)
          "obi-burmese" => :ce_year_text, # P108-8: every CE year in the CS=CE date string
          #                                 joins the envelope (typed upstream dates)
          "soas-tibetan" => :century_prose, # P108-8: "13th century, …" period strings
          "local-library" => :year_key, # P108-8: the shelf's own integer year
          "rsti" => :place_only, # P108-8: the findspot lane (PLACE_KEYS); no typed dates
          "cbeta" => :dynasty_band, # P104-1 (№R-70 grade 2): the header byline's dynasty
          #                          seat bands via the ruled table as an ERA claim —
          #                          precision "era", verbatim byline in date_raw
          "cme" => :edition_year_text, # P109-4 (the Q83 drain): the source EDITION's print
          #                              year(s) — date_class "edition", never composition
          #                              (the e-text pub_date stays machinery)
          "openmgh" => :printed_year_text, # P109-4: the MGH volume's print year — the same
          #                                  honestly-labeled "edition" class
          "rem" => :place_only # P109-4: the header's orig_place scriptorium claims
          #                       (79 of 406 docs; PLACE_KEYS) — dating already rides
          #                       its own lane
        }.freeze

        SLUGS = SHAPES.keys.freeze

        # №R-70 grade 2 (P104-1): sources whose envelopes date the WORK's
        # composition era (author-era), not an object — their rows carry
        # date_class "composition". croala's year ranges were the class's
        # precedent (its lect=dates posture rides exactly these bands).
        COMPOSITION = %w[croala diorisis glaux disco].freeze

        # P104-1: sources whose place claim rides a differently-named
        # metadata field. An override key is a findspot vocabulary with
        # explicit unknown-class values ("Unknown"), which mint no place
        # — the coptic-lane NO_PLACE stance; the default "place" key's
        # behavior is untouched.
        PLACE_KEYS = {
          "seal" => "provenance", "rsti" => "findspot",
          # P109-4: eebo-tcp documents ARE the early-modern prints — the
          # imprint place is the artifact's own production place (39k+
          # London), cleaned of the ESTC-style bracket/colon furniture.
          # The TCP's own pub_place (Ann Arbor) is lineage, exempted.
          "eebo-tcp" => "source_pub_place",
          # P109-4: the ReM header's origin scriptorium ("Vorau",
          # "Siegburg (?)") — uncertainty markers ride verbatim.
          "rem" => "orig_place"
        }.freeze
        # "not listed in teo" — rsti's own absent-findspot sentinel;
        # "s.l" — the imprint world's sine loco (eebo, 1,311 docs).
        NO_PLACE = ["unknown", "unclear", "uncertain", "none", "not listed in teo",
                    "s.l", "s.l."].freeze

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

        module_function

        # Returns {slug => rows} for every registered source.
        def build(catalog:, canonical_dir: nil) # rubocop:disable Lint/UnusedMethodArgument
          SLUGS.to_h { |slug| [slug, build_source(catalog, slug)] }
        end

        # The per-source seam (P47-r3): drop this source's rows, re-project
        # — SyncRunner calls it post-load so the lane never lags a sync.
        def refresh_source!(catalog:, slug:)
          return 0 unless SHAPES.key?(slug)

          catalog[:document_axes].where(axis_source: slug).delete
          build_source(catalog, slug)
        end

        def build_source(catalog, slug)
          shape = SHAPES.fetch(slug)
          source_id = catalog[:sources].where(slug: slug).get(:id)
          return 0 if source_id.nil?

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
                                         place_key: PLACE_KEYS.fetch(slug, "place"))
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
        def axis_row(doc, shape, reorder: false, composition: false, place_key: "place")
          meta = JSON.parse(doc[:metadata_json].to_s)
          not_before, not_after, raw, precision, own_class = send(shape, meta)
          not_before, not_after = Timeline.normalize_interval(not_before, not_after, raw: raw) if reorder
          place, place_ref, lat, lon = place_claim(meta, key: place_key)
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
        # P73-2 (ex-Q20): the "geonames" findspot ref (a verbatim URL —
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
          place = meta[key]
          if key != "place"
            # An overridden place key is a findspot vocabulary with explicit
            # unknown-class values -- those mint no place (never a name).
            # P109-4: imprint-catalog furniture (leading "[", trailing
            # ":"/","/"."/brackets — the ESTC transcription style eebo
            # carries) strips before the sentinel check and the mint.
            place = place.to_s.strip.sub(/\A[\[\s]+/, "").sub(/[\s:,.;\[\]]+\z/, "") unless place.nil?
            return [nil, nil, nil, nil] if place.nil? || place.empty? ||
                                           NO_PLACE.include?(place.downcase)

            return [place, nil, nil, nil]
          end
          return [meta["orig_place"], nil, nil, nil] if place.nil?
          return [place, nil, nil, nil] unless place.is_a?(Hash)

          refs = []
          pleiades = place["pleiades"].to_s.strip
          refs << "pleiades:#{pleiades}" if pleiades.match?(/\A\d+\z/)
          refs += Nabu::PlaceRefs.ids(place["geonames"]).map { |ns, id| "#{ns}:#{id}" }
          refs += Array(place["logainm"]).map(&:to_s).reject(&:empty?)
          name = place["ancient"] ||
                 place.values_at("townland", "county", "country").compact.then do |ladder|
                   ladder.empty? ? nil : ladder.join(", ")
                 end
          [name, refs.empty? ? nil : refs.uniq.join(" "), *coordinates(place["geo"])]
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

        # P104-1 (№R-70 grade 2): the cbeta header byline's dynasty seat
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
        # year in the string joins the envelope; CS-only strings mint
        # nothing (never converted here — the CE equivalences are
        # upstream's own).
        def ce_year_text(meta)
          text = meta["date"].to_s
          years = text.scan(/CE\s*(\d{3,4})(?:\((\d{3,4})\))?/).flatten.compact.map { |y| Integer(y, 10) }
          return [nil, nil, nil] if years.empty?

          [years.min, years.max, text.strip]
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

        def structured(meta)
          date = meta["date"]
          return [nil, nil, nil] unless date.is_a?(Hash)

          [date["not_before"], date["not_after"], date["raw"]]
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

        # P109-4 (the Q83 drain, №R-70): the source EDITION's print year —
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
