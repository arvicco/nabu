# frozen_string_literal: true

require "test_helper"
require "json"

module Store
  # Nabu::Store::TimelineBuilder (P15-2): the date/place extractors over trimmed-real
  # HGV fixtures (test/fixtures/timeline/) + catalog-side goo300k/IMP year suffixes.
  # A fresh in-memory catalog seeded with the DDbDP documents the HGV records
  # join to, so the ddb-hybrid↔urn join is exercised end to end.
  class TimelineBuilderTest < Minitest::Test
    include StoreTestDB

    FIXTURE_DIR = File.expand_path("../fixtures/timeline", __dir__)

    def setup
      @db = store_test_db
      @source = Nabu::Store::Source.create(
        slug: "papyri-ddbdp", name: "DDbDP", adapter_class: "T", license_class: "open"
      )
    end

    def make_document(urn, source: @source, language: "grc")
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: language,
        content_sha256: urn, revision: 1, withdrawn: false
      )
    end

    def timeline_for(urn)
      doc = @db[:documents].where(urn: urn).first
      @db[:document_axes].where(document_id: doc.fetch(:id)).first
    end

    def build!
      Nabu::Store::TimelineBuilder.rebuild!(catalog: @db, canonical_dir: FIXTURE_DIR)
    end

    # -- MetadataDates (P47-r2): the shared EDR/Elephantine catalog shape ----

    def seed_metadata_doc(slug, urn, metadata)
      source = Nabu::Store::Source.where(slug: slug).first ||
               Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "T",
                                          license_class: "attribution")
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: urn, language: "arc",
        content_sha256: urn, revision: 1, withdrawn: false,
        metadata_json: JSON.generate(metadata)
      )
    end

    def test_metadata_dates_mint_axis_rows_for_both_shape_sources
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:100067",
                        { "date" => { "not_before" => -223, "raw" => "date in text" },
                          "place" => { "ancient" => "Elephantine" } })
      seed_metadata_doc("edr", "urn:nabu:edr:edr000001",
                        { "date" => { "not_before" => -50, "not_after" => 1, "raw" => "-50 BC - 1 AD" },
                          "place" => { "ancient" => "Roma" } })
      summary = build!
      assert_equal 1, summary.metadata_dates.fetch("elephantine")
      assert_equal 1, summary.metadata_dates.fetch("edr")

      row = timeline_for("urn:nabu:elephantine:100067")
      assert_equal(-223, row[:not_before])
      assert_nil row[:not_after]
      assert_equal "Elephantine", row[:place_name]
      assert_equal "elephantine", row[:axis_source]
      assert_equal 1, timeline_for("urn:nabu:edr:edr000001")[:not_after]
    end

    # P62-0: the ebl shape — the top-level `period` label banded through
    # the ruled config/period_bands.yml table (the P61-1 sweep's pending,
    # served: ~23k ebl docs carry these labels). An unruled label
    # (Standard Babylonian, Uncertain) mints nothing, honestly; the 40
    # Seleucid day/month objects band coarsely under "Seleucid".
    def test_metadata_dates_ebl_period_labels_band_via_the_ruled_table
      seed_metadata_doc("ebl", "urn:nabu:ebl:k1", { "period" => "Neo-Assyrian" })
      seed_metadata_doc("ebl", "urn:nabu:ebl:k2", { "period" => "Sargonic" })
      seed_metadata_doc("ebl", "urn:nabu:ebl:k3", { "period" => "Standard Babylonian" })
      summary = build!
      assert_equal 2, summary.metadata_dates.fetch("ebl")

      row = timeline_for("urn:nabu:ebl:k1")
      assert_equal(-911, row[:not_before])
      assert_equal(-612, row[:not_after])
      assert_equal "Neo-Assyrian", row[:date_raw]
      assert_equal "ebl", row[:axis_source]
      assert_equal(-2340, timeline_for("urn:nabu:ebl:k2")[:not_before], "ebl's Sargonic = Old Akkadian")
      assert_nil timeline_for("urn:nabu:ebl:k3"),
                 "a REGISTER label misfiled as a period mints no date claim"
    end

    # P104-1 (Q77 under №R-70): the seal shape — the Texts Hierarchy
    # period strings banded through the ruled table (the posture's own
    # named candidate, served), with the Provenance field riding as the
    # place name (the HGV place-only precedent; upstream's explicit
    # "Unknown" mints no place).
    def test_metadata_dates_seal_periods_band_and_provenance_places
      seed_metadata_doc("seal", "urn:nabu:seal:6",
                        { "period" => "Old Babylonian", "provenance" => "Sippar (mod. Tell Abu Ḥabbah)" })
      seed_metadata_doc("seal", "urn:nabu:seal:7",
                        { "period" => "Middle Babylonian/Assyrian", "provenance" => "Unknown" })
      seed_metadata_doc("seal", "urn:nabu:seal:8",
                        { "period" => "Later Periods (SB, NA, LB)" })
      summary = build!
      assert_equal 3, summary.metadata_dates.fetch("seal")

      row = timeline_for("urn:nabu:seal:6")
      assert_equal(-1900, row[:not_before])
      assert_equal(-1600, row[:not_after])
      assert_equal "Old Babylonian", row[:date_raw]
      assert_equal "Sippar (mod. Tell Abu Ḥabbah)", row[:place_name]
      assert_equal "seal", row[:axis_source]

      composite = timeline_for("urn:nabu:seal:7")
      assert_equal(-1400, composite[:not_before])
      assert_equal(-1000, composite[:not_after], "MB/MA composite = the two bands joined")
      assert_nil composite[:place_name], "upstream's explicit Unknown is not a findspot"

      later = timeline_for("urn:nabu:seal:8")
      assert_equal(-1000, later[:not_before])
      assert_equal 75, later[:not_after], "first millennium through the last dated cuneiform text"
    end

    # P104-1 (№R-70 grade 2): the cbeta shape — the header byline's
    # dynasty seat banded through the ruled table as an ERA claim
    # (precision "era", the distinct honestly-labeled date class; the
    # verbatim byline rides date_raw). No dynasty in the ruled table
    # (an Indian master, 失譯 "translator lost") mints nothing.
    def test_metadata_dates_cbeta_dynasty_bylines_band_as_era_claims
      seed_metadata_doc("cbeta", "urn:nabu:cbeta:T01n0001",
                        { "author" => "後秦 佛陀耶舍共竺佛念譯", "dynasty" => "後秦",
                          "translator" => "佛陀耶舍共竺佛念" })
      seed_metadata_doc("cbeta", "urn:nabu:cbeta:T30n1579",
                        { "author" => "唐 玄奘譯", "dynasty" => "唐", "translator" => "玄奘" })
      seed_metadata_doc("cbeta", "urn:nabu:cbeta:T99n9999", { "author" => "失譯" })
      summary = build!
      assert_equal 2, summary.metadata_dates.fetch("cbeta")

      row = timeline_for("urn:nabu:cbeta:T01n0001")
      assert_equal 384, row[:not_before]
      assert_equal 417, row[:not_after]
      assert_equal "era", row[:precision], "№R-70 grade 2: attributed-era dating wears its own label"
      assert_equal "後秦 佛陀耶舍共竺佛念譯", row[:date_raw]

      tang = timeline_for("urn:nabu:cbeta:T30n1579")
      assert_equal 618, tang[:not_before]
      assert_equal 907, tang[:not_after]
      assert_nil timeline_for("urn:nabu:cbeta:T99n9999"), "no dynasty seat — no claim invented"
    end

    # P81-1: the ebl era ladder — the exact lanes P62-0 deliberately left
    # out, now in at YEAR grain: a Seleucid-era date object converts
    # exactly (SE 1 begins Nisanu, spring 311 BCE, so SE Y spans the two
    # Julian years (312−Y)/(311−Y) BCE — month/day ride raw, never a
    # sub-year bound); a regnal date object bands to the king's own
    # upstream-stated reign span ("555–539", unsigned BCE, descending).
    # Regnal-year arithmetic stays deliberately out (accession-convention
    # judgment); broken/uncertain years fall through to the period band.
    def test_metadata_dates_ebl_seleucid_date_objects_convert_exactly
      # The real shape of urn:nabu:ebl's BM 1878,0730.7 (SE Arsaces 219).
      seed_metadata_doc("ebl", "urn:nabu:ebl:se1",
                        { "period" => "Parthian",
                          "date" => { "isSeleucidEra" => true,
                                      "year" => { "isBroken" => false, "isUncertain" => false,
                                                  "value" => "219" },
                                      "month" => { "isBroken" => false, "isIntercalary" => false,
                                                   "isUncertain" => false, "value" => "1" },
                                      "day" => { "isBroken" => false, "isUncertain" => false,
                                                 "value" => "28" } } })
      seed_metadata_doc("ebl", "urn:nabu:ebl:se2",
                        { "period" => "Hellenistic",
                          "date" => { "isSeleucidEra" => true,
                                      "year" => { "isBroken" => false, "isUncertain" => false,
                                                  "value" => "" } } })
      build!

      row = timeline_for("urn:nabu:ebl:se1")
      assert_equal(-93, row[:not_before], "SE 219 = 93/92 BCE, not the Parthian band")
      assert_equal(-92, row[:not_after])
      assert_equal "SE 219, month 1, day 28", row[:date_raw]
      blank = timeline_for("urn:nabu:ebl:se2")
      assert_equal(-323, blank[:not_before], "a blank SE year falls through to the period band")
      assert_equal "Hellenistic", blank[:date_raw]
    end

    def test_metadata_dates_ebl_regnal_dates_band_to_the_kings_reign
      # The real regnal shape: Nabonidus, reign 555–539 (Neo-Babylonian).
      seed_metadata_doc("ebl", "urn:nabu:ebl:rg1",
                        { "period" => "Neo-Babylonian",
                          "date" => { "isSeleucidEra" => false,
                                      "king" => { "date" => "555–539", "name" => "Nabonidus",
                                                  "dynastyName" => "Neo-Babylonian Dynasty" },
                                      "year" => { "isBroken" => false, "isUncertain" => false,
                                                  "value" => "3" } } })
      build!

      row = timeline_for("urn:nabu:ebl:rg1")
      assert_equal(-555, row[:not_before], "the king's reign envelope, finer than the NB band")
      assert_equal(-539, row[:not_after])
      assert_equal "Nabonidus (555–539)", row[:date_raw]
    end

    def test_metadata_dates_place_only_document_gets_a_place_row
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:100001",
                        { "place" => { "ancient" => "Syene" } })
      build!
      row = timeline_for("urn:nabu:elephantine:100001")
      assert_equal "Syene", row[:place_name]
      assert_nil row[:not_before]
    end

    def test_metadata_dates_skip_undated_unplaced_and_translation_docs
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:100002",
                        { "inventory" => "Ostr. X" })
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:100067-en",
                        { "kind" => "translation",
                          "date" => { "not_before" => -223 } })
      summary = build!
      assert_equal 0, summary.metadata_dates.fetch("elephantine")
      assert_nil timeline_for("urn:nabu:elephantine:100067-en"),
                 "a translation sibling never mints its own timeline row"
    end

    # P59-0: the projection repairs reversed upstream bounds for the
    # order-defect sources (EDR's "later - earlier" ranges, BFM's swapped
    # ISO attrs) — values verbatim from the 2026-08-04 reversed-interval
    # audit. Elephantine is deliberately NOT repaired here: its defects
    # need BCE-default negation plus a nested-TEI fallback, which only the
    # parser can see — its repair lands at parse (and re-parse regenerates).
    def test_metadata_dates_order_normalize_reversed_edr_and_bfm_bounds
      seed_metadata_doc("edr", "urn:nabu:edr:aedr016567",
                        { "date" => { "not_before" => 71, "not_after" => 70,
                                      "raw" => "71 AD - 70 AD" } })
      seed_metadata_doc("edr", "urn:nabu:edr:aedr071646",
                        { "date" => { "not_before" => -200, "not_after" => -230,
                                      "raw" => "-200 BC - -230 BC" } })
      seed_metadata_doc("bfm", "urn:nabu:bfm:ChastCygH",
                        { "date" => "entre 1170 et 1267 et même après 1190 et av. 1204",
                          "date_not_before" => "1204-01-01",
                          "date_not_after" => "1197-12-31" })
      build!
      first = timeline_for("urn:nabu:edr:aedr016567")
      assert_equal [70, 71], [first[:not_before], first[:not_after]]
      second = timeline_for("urn:nabu:edr:aedr071646")
      assert_equal [-230, -200], [second[:not_before], second[:not_after]]
      bfm = timeline_for("urn:nabu:bfm:ChastCygH")
      assert_equal [1197, 1204], [bfm[:not_before], bfm[:not_after]]
      assert_equal "entre 1170 et 1267 et même après 1190 et av. 1204", bfm[:date_raw],
                   "the raw rides verbatim — repair moves seats, never digits"
    end

    def test_metadata_dates_leave_elephantine_repair_to_the_parser
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:311616",
                        { "date" => { "not_before" => 550, "not_after" => 399,
                                      "raw" => "scholarly deduction" } })
      build!
      row = timeline_for("urn:nabu:elephantine:311616")
      assert_equal [550, 399], [row[:not_before], row[:not_after]],
                   "a blind projection swap would mint 399-550 CE for a BCE corpus — " \
                   "the parser's negation ladder owns this repair"
    end

    # P47-r3 (the generalized audit): the three shape handlers, values
    # verbatim from the live catalog inspection.
    def test_metadata_dates_shapes_for_itant_bfm_and_croala
      seed_metadata_doc("itant", "urn:nabu:itant:oscan-9",
                        { "date" => { "not_before" => -425, "not_after" => -375, "cert" => "low",
                                      "raw" => "end of the 5th - beginning of the 4th century BC" },
                          "place" => { "ancient" => "Bovianum, Samnium", "pleiades" => "432725",
                                       "geonames" => "https://sws.geonames.org/3180985",
                                       "modern" => "Boiano (CB)" } })
      seed_metadata_doc("bfm", "urn:nabu:bfm:AlexisRaM",
                        { "date" => "ca. 1050", "date_not_before" => "1025-01-01",
                          "date_not_after" => "1075-01-01" })
      seed_metadata_doc("croala", "urn:nabu:croala:grauisius",
                        { "date" => "1565-1650" })
      seed_metadata_doc("croala", "urn:nabu:croala:fuzzy",
                        { "date" => "saec. XVI" })
      seed_metadata_doc("croala", "urn:nabu:croala:split-doc",
                        { "date" => "1490", "place" => "Split" })
      # P94 (№R-59): dta rides the same :year_range shape — the sourceDesc
      # print year is a clean "1784" string on every document, and the
      # de:early staging depends on these envelopes existing.
      seed_metadata_doc("dta", "urn:nabu:dta:kant_aufklaerung_1784",
                        { "date" => "1784", "author" => "Kant, Immanuel" })
      # P96 timeline hygiene: the two top-level-bounds Dutch corpora
      # (dark lanes until now) and corpus-corporum's reversed envelope.
      seed_metadata_doc("corpus-gysseling", "urn:nabu:corpus-gysseling:0001",
                        { "not_before" => 1210, "not_after" => 1240,
                          "date_raw" => "1210-1240", "place" => "Gent" })
      seed_metadata_doc("corpus-corporum", "urn:nabu:corpus-corporum:rev",
                        { "date" => { "not_before" => 430, "not_after" => 354,
                                      "raw" => "430-354" } })
      summary = build!
      itant = timeline_for("urn:nabu:itant:oscan-9")
      assert_equal([-425, -375], [itant[:not_before], itant[:not_after]])
      # P63-4: the metadata place hash's bare pleiades id lifts into a
      # NAMESPACED ref (Dp-b) — itant's 497 measured ids stop being
      # metadata-only; the ancient name still rides place_name.
      # P73-2: the modern-findspot ref (place["geonames"], a verbatim URL)
      # lifts through the ONE ref reader alongside it — space-separated
      # namespaced tokens, the multi-claim convention consumers already
      # split on.
      assert_equal "Bovianum, Samnium", itant[:place_name]
      assert_equal "pleiades:432725 geonames:3180985", itant[:place_ref]
      bfm = timeline_for("urn:nabu:bfm:AlexisRaM")
      assert_equal([1025, 1075, "ca. 1050"], [bfm[:not_before], bfm[:not_after], bfm[:date_raw]])
      croala = timeline_for("urn:nabu:croala:grauisius")
      assert_equal([1565, 1650], [croala[:not_before], croala[:not_after]])
      assert_nil timeline_for("urn:nabu:croala:fuzzy"),
                 "an unparseable prose dating is skipped honestly, never guessed"
      split = timeline_for("urn:nabu:croala:split-doc")
      assert_equal ["Split", 1490], [split[:place_name], split[:not_before]],
                   "croala's STRING place (the P44-i4 shape) IS the place name"
      assert_equal 2, summary.metadata_dates.fetch("croala")
      kant = timeline_for("urn:nabu:dta:kant_aufklaerung_1784")
      assert_equal([1784, 1784], [kant[:not_before], kant[:not_after]],
                   "dta's print year mints a one-year envelope (№R-59's inference substrate)")
      gys = timeline_for("urn:nabu:corpus-gysseling:0001")
      assert_equal([1210, 1240, "Gent"], [gys[:not_before], gys[:not_after], gys[:place_name]],
                   "the top-level-bounds shape lights the dark Dutch lane, place riding like croala")
      rev = timeline_for("urn:nabu:corpus-corporum:rev")
      assert_equal([354, 430], [rev[:not_before], rev[:not_after]],
                   "corpus-corporum's reversed composition envelopes normalize (the health anomaly)")
    end

    # P73-2 (the itant TM lift, ex-Q20): the geonames-labeled findspot lane
    # measured 2026-08-10 — 508 real GeoNames URLs, 1 mislabeled
    # Trismegistos URL, 13 doubled-URL strays. Everything the ONE ref
    # reader honestly parses mints namespaced; malformed remainders mint
    # nothing, never a guess.
    def test_metadata_dates_lift_the_geonames_lane_through_the_one_ref_reader
      seed_metadata_doc("itant", "urn:nabu:itant:mislabeled-tm",
                        { "date" => { "not_before" => -300, "not_after" => -200 },
                          "place" => { "ancient" => "Teate",
                                       "geonames" => "https://www.trismegistos.org/place/2711" } })
      seed_metadata_doc("itant", "urn:nabu:itant:doubled-url",
                        { "date" => { "not_before" => -300, "not_after" => -200 },
                          "place" => { "ancient" => "Larinum",
                                       "geonames" =>
                                         "https://sws.geonames.org/https://sws.geonames.org/6543607" } })
      seed_metadata_doc("itant", "urn:nabu:itant:unparseable-ref",
                        { "date" => { "not_before" => -300, "not_after" => -200 },
                          "place" => { "ancient" => "Nola", "geonames" => "not-a-url" } })
      build!
      assert_equal "tm:2711", timeline_for("urn:nabu:itant:mislabeled-tm")[:place_ref],
                   "a Trismegistos URL riding the geonames label mints in its TRUE namespace"
      assert_equal "geonames:6543607", timeline_for("urn:nabu:itant:doubled-url")[:place_ref],
                   "the doubled-URL stray recovers its one honest id"
      assert_nil timeline_for("urn:nabu:itant:unparseable-ref")[:place_ref],
                 "an unparseable ref mints nothing — the row keeps its date and name"
    end

    # P73-2: a ref IS placement — a doc carrying only a parseable place ref
    # (no date, no ancient name — 8 measured live) still rows, the HGV
    # place-only precedent extended to refs.
    def test_metadata_dates_keep_a_ref_only_row
      seed_metadata_doc("itant", "urn:nabu:itant:ref-only",
                        { "place" => { "geonames" => "https://sws.geonames.org/3172394" } })
      build!
      row = timeline_for("urn:nabu:itant:ref-only")
      assert_equal "geonames:3172394", row[:place_ref]
      assert_nil row[:not_before]
      assert_nil row[:place_name]
    end

    # P107-2: the iedc iso-prefix shape — date_iso "1183-10" -> the 1183
    # one-year envelope, the prose date_text verbatim as raw; an item
    # without the parenthetical ISO mints nothing.
    def test_metadata_dates_iedc_iso_prefix_key
      seed_metadata_doc("iedc", "urn:nabu:iedc:iedc0201",
                        { "date_iso" => "1183-10",
                          "date_text" => "The Gregorian calendar: October 1183 (1183-10)" })
      seed_metadata_doc("iedc", "urn:nabu:iedc:iedc0002",
                        { "date_text" => "The Gregorian calendar: Before c. 705" })
      build!
      row = timeline_for("urn:nabu:iedc:iedc0201")
      assert_equal [1183, 1183], [row[:not_before], row[:not_after]]
      assert_includes row[:date_raw], "October 1183"
      assert_nil timeline_for("urn:nabu:iedc:iedc0002"),
                 "prose-only dates mint nothing — declared, never guessed"
    end

    # P108-8 (the Q83 dates/places slice) — four new shapes + the rsti
    # place lane, each against its live-censused metadata verbatim.

    def test_metadata_dates_syriac_when_key_with_per_doc_class
      seed_metadata_doc("syriac-corpus", "urn:nabu:syriac-corpus:c1",
                        { "orig_date" => { "text" => "337 CE", "type" => "composition",
                                           "when" => "0337" } })
      seed_metadata_doc("syriac-corpus", "urn:nabu:syriac-corpus:t1",
                        { "orig_date" => { "text" => "6th c. translation", "type" => "translation",
                                           "when" => "0550" } })
      build!
      comp = timeline_for("urn:nabu:syriac-corpus:c1")
      assert_equal [337, 337, "composition"], comp.values_at(:not_before, :not_after, :date_class)
      trans = timeline_for("urn:nabu:syriac-corpus:t1")
      assert_equal [550, 550, nil], trans.values_at(:not_before, :not_after, :date_class),
                   "a translation-typed date is dated but NOT composition-classed"
    end

    # The live census (2026-09-29): only 24 of 632 syriac docs carry a
    # `when` attribute — 608 date in century PROSE. The shape falls back
    # to the century grammar, and the grammar knows halves: "Second
    # half of the fifth century" is 450-500, never the 2nd century.
    def test_metadata_dates_syriac_prose_fallback_and_half_grammar
      seed_metadata_doc("syriac-corpus", "urn:nabu:syriac-corpus:p1",
                        { "orig_date" => { "text" => "Second half of the fifth century CE",
                                           "type" => "composition" } })
      seed_metadata_doc("syriac-corpus", "urn:nabu:syriac-corpus:p2",
                        { "orig_date" => { "text" => "Late 5th/early 6th century CE",
                                           "type" => "composition" } })
      build!
      p1 = timeline_for("urn:nabu:syriac-corpus:p1")
      assert_equal [450, 500, "composition"], p1.values_at(:not_before, :not_after, :date_class)
      p2 = timeline_for("urn:nabu:syriac-corpus:p2")
      assert_equal [450, 550], [p2[:not_before], p2[:not_after]]
    end

    def test_metadata_dates_obi_ce_year_text
      seed_metadata_doc("obi-burmese", "urn:nabu:obi-burmese:v1",
                        { "date" => "CS 586(580) = CE 1224(1218) CS 580 = CE 1218; CS 586 = CE 1224" })
      build!
      row = timeline_for("urn:nabu:obi-burmese:v1")
      assert_equal [1218, 1224], [row[:not_before], row[:not_after]],
                   "every CE year in the string joins the envelope"
      assert_includes row[:date_raw], "CS 586"
    end

    def test_metadata_dates_century_prose_bands
      seed_metadata_doc("ogham", "urn:nabu:ogham:o1",
                        { "date" => { "text" => "Fifth century or possibly early sixth century" } })
      seed_metadata_doc("ogham", "urn:nabu:ogham:o2",
                        { "date" => { "text" => "Sixth to the eighth century" } })
      seed_metadata_doc("soas-tibetan", "urn:nabu:soas-tibetan:s1",
                        { "period" => "13th century, ecclesiastical history" })
      build!
      o1 = timeline_for("urn:nabu:ogham:o1")
      assert_equal [400, 550], [o1[:not_before], o1[:not_after]],
                   "fifth century through EARLY sixth (its first half)"
      o2 = timeline_for("urn:nabu:ogham:o2")
      assert_equal [500, 800], [o2[:not_before], o2[:not_after]]
      s1 = timeline_for("urn:nabu:soas-tibetan:s1")
      assert_equal [1200, 1300], [s1[:not_before], s1[:not_after]]
    end

    def test_metadata_dates_local_library_year_key
      seed_metadata_doc("local-library", "urn:nabu:local-library:b1", { "year" => 2023 })
      build!
      row = timeline_for("urn:nabu:local-library:b1")
      assert_equal [2023, 2023], [row[:not_before], row[:not_after]]
    end

    def test_metadata_places_rsti_findspot
      seed_metadata_doc("rsti", "urn:nabu:rsti:r1", { "findspot" => "Kamid el-Loz" })
      seed_metadata_doc("rsti", "urn:nabu:rsti:r2", { "findspot" => "Not listed in TEO" })
      build!
      row = timeline_for("urn:nabu:rsti:r1")
      assert_equal "Kamid el-Loz", row[:place_name]
      assert_nil timeline_for("urn:nabu:rsti:r2"),
                 "the source's own not-listed sentinel is noise, never a place name"
    end

    # P109-4 (the Q83 drain): edition print years project with the
    # honestly-labeled "edition" date class — never composition, never
    # a bare typed date.
    def test_metadata_dates_edition_year_class
      seed_metadata_doc("cme", "urn:nabu:cme:c1", { "source_date" => "1904, 1905" })
      seed_metadata_doc("cme", "urn:nabu:cme:c2", { "source_date" => "c.1976" })
      seed_metadata_doc("cme", "urn:nabu:cme:c3", { "source_date" => "n.d." })
      seed_metadata_doc("openmgh", "urn:nabu:openmgh:m1", { "printed_date" => "2001" })
      build!
      c1 = timeline_for("urn:nabu:cme:c1")
      assert_equal [1904, 1905, "edition"], c1.values_at(:not_before, :not_after, :date_class)
      c2 = timeline_for("urn:nabu:cme:c2")
      assert_equal [1976, 1976, "edition"], c2.values_at(:not_before, :not_after, :date_class)
      assert_nil timeline_for("urn:nabu:cme:c3"), "a yearless edition string mints nothing"
      m1 = timeline_for("urn:nabu:openmgh:m1")
      assert_equal [2001, 2001, "edition"], m1.values_at(:not_before, :not_after, :date_class)
    end

    # P109-4: the eebo imprint place — the document IS the early-modern
    # print, so its imprint place is a real place claim, cleaned of the
    # ESTC transcription furniture; sine-loco marks mint nothing.
    def test_metadata_places_eebo_imprint_cleaning
      seed_metadata_doc("eebo-tcp", "urn:nabu:eebo-tcp:a1",
                        { "date" => { "not_before" => 1593, "raw" => "1593" },
                          "source_pub_place" => "[Imprynted at London :" })
      seed_metadata_doc("eebo-tcp", "urn:nabu:eebo-tcp:a2", { "source_pub_place" => "London]" })
      seed_metadata_doc("eebo-tcp", "urn:nabu:eebo-tcp:a3", { "source_pub_place" => "[S.l. :" })
      build!
      assert_equal "Imprynted at London", timeline_for("urn:nabu:eebo-tcp:a1")[:place_name],
                   "furniture stripped, the imprint statement verbatim"
      assert_equal "London", timeline_for("urn:nabu:eebo-tcp:a2")[:place_name],
                   "a place-only doc still rows (the HGV precedent)"
      assert_nil timeline_for("urn:nabu:eebo-tcp:a3"),
                 "sine loco is the imprint world's unknown — never a place name"
    end

    def test_metadata_places_rem_orig_place
      seed_metadata_doc("rem", "urn:nabu:rem:m1", { "orig_place" => "Siegburg (?)" })
      build!
      assert_equal "Siegburg (?)", timeline_for("urn:nabu:rem:m1")[:place_name],
                   "the scriptorium claim rides verbatim, uncertainty marker included"
    end

    # P47-r3: the per-source refresh seam SyncRunner calls post-load — the
    # lane never lags a sync again (the class this audit exists to kill).
    def test_metadata_dates_refresh_source_replaces_only_that_source
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:200001",
                        { "date" => { "not_before" => -450 } })
      seed_metadata_doc("edr", "urn:nabu:edr:edr900001",
                        { "date" => { "not_before" => -50 } })
      build!
      seed_metadata_doc("elephantine", "urn:nabu:elephantine:200002",
                        { "date" => { "not_before" => -410 } })
      rows = Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: @db, slug: "elephantine")
      assert_equal 2, rows
      refute_nil timeline_for("urn:nabu:elephantine:200002"), "the post-refresh doc joins the lane"
      refute_nil timeline_for("urn:nabu:edr:edr900001"), "other sources' rows survive untouched"
      assert_equal 0, Nabu::Store::TimelineBuilder::MetadataDates.refresh_source!(catalog: @db, slug: "papyri-ddbdp"),
                   "an unregistered slug is a no-op"
    end

    # -- P104-1 (Q77, №R-70): the metadata-drain shapes -----------------------
    # Values verbatim from the 2026-09-26 live-catalog census. №R-70 rules
    # ALL metadata mined for the axes, and grades composition-era
    # (author-era) dating as its OWN honestly-labeled class: those rows
    # carry date_class "composition"; artifact/typed dates keep NULL.

    def test_metadata_dates_fornsvenska_compact_bounds_mint_typed_envelopes
      seed_metadata_doc("fornsvenska", "urn:nabu:fornsvenska:aldre-vastgotalagen",
                        { "date" => "1280–1290", "datefrom" => "12800101",
                          "dateto" => "12901231" })
      seed_metadata_doc("fornsvenska", "urn:nabu:fornsvenska:dateless",
                        { "date" => "medeltida", "datefrom" => "", "dateto" => "" })
      summary = build!
      row = timeline_for("urn:nabu:fornsvenska:aldre-vastgotalagen")
      assert_equal [1280, 1290, "1280–1290"], [row[:not_before], row[:not_after], row[:date_raw]]
      assert_nil row[:date_class], "an upstream-typed text dating is NOT the composition class"
      assert_nil timeline_for("urn:nabu:fornsvenska:dateless"),
                 "empty compact bounds mint nothing — never guessed"
      assert_equal 1, summary.metadata_dates.fetch("fornsvenska")
    end

    def test_metadata_dates_disco_author_century_bands_carry_the_composition_class
      seed_metadata_doc("disco", "urn:nabu:disco:disco0001",
                        { "author" => "Joseph Aragonés", "birth_century" => "17",
                          "death_century" => "17", "period" => "15th-17th" })
      seed_metadata_doc("disco", "urn:nabu:disco:disco0002",
                        { "birth_century" => "19", "death_century" => "20" })
      build!
      row = timeline_for("urn:nabu:disco:disco0001")
      assert_equal [1601, 1700], [row[:not_before], row[:not_after]],
                   "the author's own century pair bounds the band — never a midpoint"
      assert_equal "composition", row[:date_class],
                   "author-era dating is №R-70 grade 2 — labeled, never passed off as an artifact date"
      span = timeline_for("urn:nabu:disco:disco0002")
      assert_equal [1801, 2000], [span[:not_before], span[:not_after]]
    end

    def test_metadata_dates_diorisis_creation_years_carry_the_composition_class
      seed_metadata_doc("diorisis", "urn:nabu:diorisis:tlg0001-tlg001",
                        { "creation_date" => "-245", "genre" => "Poetry" })
      seed_metadata_doc("diorisis", "urn:nabu:diorisis:undated",
                        { "genre" => "Oratory" })
      build!
      row = timeline_for("urn:nabu:diorisis:tlg0001-tlg001")
      assert_equal [-245, -245], [row[:not_before], row[:not_after]]
      assert_equal "-245", row[:date_raw]
      assert_equal "composition", row[:date_class]
      assert_nil timeline_for("urn:nabu:diorisis:undated")
    end

    def test_metadata_dates_glaux_start_end_bounds_carry_the_composition_class
      seed_metadata_doc("glaux", "urn:nabu:glaux:tlg0001",
                        { "start_date" => "-300", "end_date" => "-201" })
      build!
      row = timeline_for("urn:nabu:glaux:tlg0001")
      assert_equal [-300, -201], [row[:not_before], row[:not_after]]
      assert_equal "-300–-201", row[:date_raw]
      assert_equal "composition", row[:date_class]
    end

    def test_metadata_dates_croala_rows_join_the_composition_class
      seed_metadata_doc("croala", "urn:nabu:croala:grauisius-2",
                        { "date" => "1565-1650" })
      build!
      assert_equal "composition", timeline_for("urn:nabu:croala:grauisius-2")[:date_class],
                   "croala's author-era year ranges were the class's precedent — now labeled"
    end

    def test_metadata_dates_ogham_place_hash_mints_coordinates_and_logainm_refs
      seed_metadata_doc("ogham", "urn:nabu:ogham:i-ant-001",
                        { "layer" => "ogham",
                          "place" => { "country" => "Northern Ireland", "county" => "Co. Antrim",
                                       "geo" => "54.8045, -6.1961",
                                       "logainm" => ["https://www.logainm.ie/ga/61366"],
                                       "townland" => "Carncome (Carn Coim)" },
                          "date" => { "text" => "Fifth century" } })
      seed_metadata_doc("ogham", "urn:nabu:ogham:cai-001",
                        { "layer" => "ogham",
                          "place" => { "country" => "England", "county" => "Cornwall",
                                       "geo" => "50.640058, -4.675453" } })
      summary = build!
      row = timeline_for("urn:nabu:ogham:i-ant-001")
      assert_equal "Carncome (Carn Coim), Co. Antrim, Northern Ireland", row[:place_name],
                   "townland → county → country, the upstream ladder joined verbatim"
      assert_in_delta 54.8045, row[:place_lat]
      assert_in_delta(-6.1961, row[:place_lon])
      assert_equal "https://www.logainm.ie/ga/61366", row[:place_ref],
                   "the logainm gazetteer URL rides verbatim (the EDH URL precedent)"
      assert_equal [400, 500], [row[:not_before], row[:not_after]],
                   "P108-8 REVISES the old unparsed posture: the century-prose grammar bands it"
      no_townland = timeline_for("urn:nabu:ogham:cai-001")
      assert_equal "Cornwall, England", no_townland[:place_name]
      assert_equal 2, summary.metadata_dates.fetch("ogham")
    end

    def test_metadata_dates_menota_orig_place_rides_the_structured_rows
      seed_metadata_doc("menota", "urn:nabu:menota:am-1056-ix-4to",
                        { "date" => { "not_before" => 1280, "not_after" => 1310, "raw" => "c. 1300" },
                          "orig_place" => "Norway",
                          "repository" => "Den Arnamagnæanske Samling",
                          "settlement" => "Copenhagen" })
      build!
      row = timeline_for("urn:nabu:menota:am-1056-ix-4to")
      assert_equal [1280, 1310], [row[:not_before], row[:not_after]]
      assert_equal "Norway", row[:place_name],
                   "orig_place is the origin claim; repository/settlement (the holding " \
                   "library, a present location) deliberately never mint — the rundata stance"
    end

    # -- HGV extractor: the five date shapes ----------------------------------

    def test_bce_point_is_stored_verbatim
      make_document("urn:nabu:ddbdp:bgu:3:994")
      build!
      row = timeline_for("urn:nabu:ddbdp:bgu:3:994")
      assert_equal(-113, row.fetch(:not_before))
      assert_equal(-113, row.fetch(:not_after))
      assert_equal "exact", row.fetch(:precision)
      assert_equal "Pathyris", row.fetch(:place_name)
      assert_equal "26. Aug. 113 v.Chr.", row.fetch(:date_raw)
      assert_equal "hgv", row.fetch(:axis_source)
      assert_includes row.fetch(:place_ref), "pleiades.stoa.org/places/786084"
    end

    def test_ce_range_keeps_both_bounds_and_precision
      make_document("urn:nabu:ddbdp:bgu:2:402")
      build!
      row = timeline_for("urn:nabu:ddbdp:bgu:2:402")
      assert_equal 591, row.fetch(:not_before)
      assert_equal 602, row.fetch(:not_after)
      assert_equal "low", row.fetch(:precision)
      assert_equal "Arsinoites", row.fetch(:place_name)
    end

    def test_open_ended_notafter_leaves_not_before_null
      make_document("urn:nabu:ddbdp:p.cair.zen:1:59108")
      build!
      row = timeline_for("urn:nabu:ddbdp:p.cair.zen:1:59108")
      assert_nil row.fetch(:not_before) # −∞
      assert_equal(-257, row.fetch(:not_after))
    end

    def test_undated_but_placed_document_gets_a_place_only_row
      make_document("urn:nabu:ddbdp:sb:1:4471")
      build!
      row = timeline_for("urn:nabu:ddbdp:sb:1:4471")
      refute_nil row
      assert_nil row.fetch(:not_before)
      assert_nil row.fetch(:not_after)
      assert_equal "Pathyris", row.fetch(:place_name)
    end

    def test_multiple_alternative_origdates_envelope_min_max
      make_document("urn:nabu:ddbdp:p.cair.zen:3:59354")
      build!
      row = timeline_for("urn:nabu:ddbdp:p.cair.zen:3:59354")
      assert_equal(-244, row.fetch(:not_before)) # min of the two alternatives
      assert_equal(-243, row.fetch(:not_after))  # max of the two alternatives
    end

    def test_hgv_record_without_a_matching_document_is_skipped
      # No DDbDP document created for bgu;3;994 → no timeline row, no crash.
      build!
      assert_equal 0, @db[:document_axes].count
    end

    def test_summary_counts_files_and_rows
      make_document("urn:nabu:ddbdp:bgu:3:994")
      summary = build!
      assert_equal 7, summary.hgv_files # five date-shape fixtures + the two P100-3 keywords records
      assert_equal 1, summary.hgv       # one joined to a catalog document
    end

    # -- goo300k / IMP: year off the urn suffix -------------------------------

    def test_goo300k_year_from_urn_suffix
      src = Nabu::Store::Source.create(slug: "goo300k", name: "goo", adapter_class: "T", license_class: "open")
      make_document("urn:nabu:goo300k:zrc_00001-1584", source: src, language: "sla")
      summary = build!
      row = timeline_for("urn:nabu:goo300k:zrc_00001-1584")
      assert_equal 1584, row.fetch(:not_before)
      assert_equal 1584, row.fetch(:not_after)
      assert_equal "goo300k", row.fetch(:axis_source)
      assert_equal 1, summary.goo300k
    end

    def test_imp_year_from_urn_suffix
      src = Nabu::Store::Source.create(slug: "imp", name: "imp", adapter_class: "T", license_class: "open")
      make_document("urn:nabu:imp:wiki00266-1889", source: src, language: "sla")
      build!
      row = timeline_for("urn:nabu:imp:wiki00266-1889")
      assert_equal 1889, row.fetch(:not_before)
      assert_equal "imp", row.fetch(:axis_source)
    end

    # -- rebuild-safety: a second build replaces, never duplicates ------------

    def test_rebuild_is_idempotent
      make_document("urn:nabu:ddbdp:bgu:3:994")
      build!
      build!
      assert_equal 1, @db[:document_axes].where(document_id: @db[:documents].first[:id]).count
    end
  end
end
