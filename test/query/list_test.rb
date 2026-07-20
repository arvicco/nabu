# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::List (P22-1): the what-is-held read surface behind
  # `nabu list` — the shelf census, one source's card, and the bounded
  # document/entry/collection enumerations. Catalog is a fresh in-memory
  # SQLite; rows are created directly (the export-test pattern).
  class ListTest < Minitest::Test
    include StoreTestDB

    def setup
      @catalog = store_test_db
      @ccmh = make_source(slug: "ccmh", name: "CCMH", license_class: "nc",
                          license: "CC BY-NC 4.0 (Helsinki corpus)")
      @library = make_source(slug: "local-library", name: "Local library", license_class: "research_private")
    end

    # -- helpers -------------------------------------------------------------

    def make_source(slug:, name:, license_class:, license: nil)
      Nabu::Store::Source.create(
        slug: slug, name: name, adapter_class: "TestAdapter",
        license: license, license_class: license_class, enabled: true
      )
    end

    def make_document(source:, urn:, language: "chu", title: nil, license_override: nil,
                      withdrawn: false, retired: false)
      Nabu::Store::Document.create(
        source_id: source.id, urn: urn, title: title || urn, language: language,
        license_override: license_override, content_sha256: "x", revision: 1,
        withdrawn: withdrawn, retired_upstream: retired
      )
    end

    def make_passage(document, urn:, sequence:, language: "chu", withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: language,
        text: "text #{sequence}", text_normalized: "text #{sequence}",
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_dictionary(source:, slug:, language:, title: nil)
      @catalog[:dictionaries].insert(source_id: source.id, slug: slug,
                                     title: title || slug, language: language)
    end

    def make_entry(dictionary_id, entry_id:, headword:, folded:, gloss: nil, withdrawn: false)
      @catalog[:dictionary_entries].insert(
        dictionary_id: dictionary_id, urn: "urn:nabu:dict:d#{dictionary_id}:#{entry_id}",
        entry_id: entry_id, key_raw: headword, headword: headword, headword_folded: folded,
        gloss: gloss, body: "#{headword} body", content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def make_axis(doc, not_before:, not_after:)
      @catalog[:document_axes].insert(document_id: doc.id, not_before: not_before,
                                      not_after: not_after, axis_source: "hgv")
    end

    def list
      Nabu::Query::List.new(catalog: @catalog)
    end

    def seed_ccmh
      doc = make_document(source: @ccmh, urn: "urn:nabu:ccmh:mt", title: "Marianus Matthew")
      make_passage(doc, urn: "urn:nabu:ccmh:mt:1", sequence: 0)
      make_passage(doc, urn: "urn:nabu:ccmh:mt:2", sequence: 1)
      doc
    end

    # -- census ---------------------------------------------------------------

    def test_census_counts_docs_passages_languages_and_license_mix
      seed_ccmh
      rows = list.census
      row = rows.find { |r| r.slug == "ccmh" }
      assert_equal 1, row.docs
      assert_equal 2, row.passages
      assert_equal 0, row.entries
      assert_equal ["chu"], row.languages
      assert_equal ["nc"], row.license_classes
      assert_equal 0, row.withdrawn
    end

    def test_census_excludes_withdrawn_from_live_counts_but_counts_them
      seed_ccmh
      gone = make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:gone", withdrawn: true)
      make_passage(gone, urn: "urn:nabu:ccmh:mar:gone:1", sequence: 0)
      row = list.census.find { |r| r.slug == "ccmh" }
      assert_equal 1, row.docs, "withdrawn documents are not live"
      assert_equal 2, row.passages
      assert_equal 1, row.withdrawn
    end

    def test_census_counts_dictionary_entries_and_dictionary_languages
      dict = make_dictionary(source: @ccmh, slug: "lsj", language: "grc")
      make_entry(dict, entry_id: "n1", headword: "μῆνις", folded: "μηνισ", gloss: "wrath")
      make_entry(dict, entry_id: "n2", headword: "λόγος", folded: "λογοσ", withdrawn: true)
      row = list.census.find { |r| r.slug == "ccmh" }
      assert_equal 1, row.entries, "withdrawn entries are not live"
      assert_includes row.languages, "grc"
    end

    def test_census_license_mix_includes_document_overrides
      seed_ccmh
      make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:open", license_override: "open")
      row = list.census.find { |r| r.slug == "ccmh" }
      assert_equal %w[nc open], row.license_classes.sort
    end

    def test_census_source_without_content_reads_source_license_class
      row = list.census.find { |r| r.slug == "local-library" }
      assert_equal 0, row.docs
      assert_equal ["research_private"], row.license_classes
    end

    # -- card -----------------------------------------------------------------

    def test_card_carries_identity_counts_languages_and_credit
      seed_ccmh
      card = list.card("ccmh")
      assert_equal "ccmh", card.slug
      assert_equal "CCMH", card.name
      assert_equal "TestAdapter", card.adapter_class
      assert card.enabled
      assert_equal "CC BY-NC 4.0 (Helsinki corpus)", card.license_text
      assert_equal ["nc"], card.license_classes
      assert_equal 1, card.docs
      assert_equal 2, card.passages
      assert_equal({ "chu" => 2 }, card.languages)
      assert_nil card.dated
      assert_empty card.facets
      assert_nil card.collections
    end

    def test_card_dated_coverage_when_axis_rows_exist
      doc = seed_ccmh
      make_axis(doc, not_before: -113, not_after: 602)
      card = list.card("ccmh")
      assert_equal 1, card.dated.docs
      assert_equal(-113, card.dated.min)
      assert_equal 602, card.dated.max
    end

    def test_card_facets_summary_when_facet_rows_exist
      doc = seed_ccmh
      @catalog[:document_facets].insert(document_id: doc.id, facet: "genre", value: "epitaph", raw: "titsep")
      @catalog[:document_facets].insert(document_id: doc.id, facet: "genre", value: "votive", raw: "titsac")
      card = list.card("ccmh")
      genre = card.facets.find { |f| f.facet == "genre" }
      assert_equal 2, genre.values
      assert_equal 1, genre.docs
    end

    def test_card_collections_for_manifest_collection_urns
      make_document(source: @library, urn: "urn:nabu:local-library:slavistics:leskien", language: "deu")
      make_document(source: @library, urn: "urn:nabu:local-library:slavistics:jagic", language: "deu")
      make_document(source: @library, urn: "urn:nabu:local-library:articles:vaillant", language: "fra")
      card = list.card("local-library")
      assert_equal({ "slavistics" => 2, "articles" => 1 }, card.collections)
    end

    def test_card_dictionaries_listed_for_dictionary_sources
      dict = make_dictionary(source: @ccmh, slug: "lsj", language: "grc", title: "A Greek-English Lexicon")
      make_entry(dict, entry_id: "n1", headword: "μῆνις", folded: "μηνισ")
      card = list.card("ccmh")
      assert_equal 1, card.dictionaries.size
      assert_equal "lsj", card.dictionaries.first.slug
      assert_equal 1, card.dictionaries.first.entries
    end

    def test_card_unknown_source_raises_naming_valid_slugs
      error = assert_raises(Nabu::Query::List::Error) { list.card("nope") }
      assert_match(/unknown source "nope"/, error.message)
      assert_match(/ccmh/, error.message)
    end

    # -- documents -------------------------------------------------------------

    def seed_document_pile
      make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:mt", title: "Matthew")
      make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:mk", title: "Mark", language: "grc")
      make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:lk", title: "Luke", withdrawn: true)
      make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:jn", title: "John", retired: true)
    end

    def test_documents_enumerate_in_urn_order_with_flags
      seed_document_pile
      page = list.documents("ccmh")
      assert_equal 4, page.total
      assert_equal %w[urn:nabu:ccmh:mar:jn urn:nabu:ccmh:mar:lk urn:nabu:ccmh:mar:mk urn:nabu:ccmh:mar:mt],
                   page.rows.map(&:urn)
      assert page.rows.find { |r| r.urn.end_with?(":lk") }.withdrawn
      assert page.rows.find { |r| r.urn.end_with?(":jn") }.retired
    end

    def test_documents_limit_pages_and_total_stays_honest
      seed_document_pile
      page = list.documents("ccmh", limit: 2)
      assert_equal 2, page.rows.size
      assert_equal 4, page.total
      assert_equal 4, list.documents("ccmh", limit: 0).rows.size, "limit 0 is unlimited"
    end

    def test_documents_lang_license_and_withdrawn_filters
      seed_document_pile
      assert_equal ["urn:nabu:ccmh:mar:mk"], list.documents("ccmh", lang: "grc").rows.map(&:urn)
      assert_equal 4, list.documents("ccmh", license: "nc").total
      assert_equal %w[urn:nabu:ccmh:mar:jn urn:nabu:ccmh:mar:lk],
                   list.documents("ccmh", withdrawn_only: true).rows.map(&:urn)
    end

    def test_documents_date_window_filters_on_the_axis
      seed_document_pile
      dated = @catalog[:documents].where(urn: "urn:nabu:ccmh:mar:mt").first
      @catalog[:document_axes].insert(document_id: dated[:id], not_before: 850, not_after: 900,
                                      axis_source: "hgv")
      page = list.documents("ccmh", from: 800, to: 1000)
      assert_equal ["urn:nabu:ccmh:mar:mt"], page.rows.map(&:urn)
    end

    def test_documents_unknown_source_raises
      assert_raises(Nabu::Query::List::Error) { list.documents("nope") }
    end

    # -- entries ---------------------------------------------------------------

    def seed_dictionary_shelf
      dict = make_dictionary(source: @ccmh, slug: "sla-pro", language: "sla-pro")
      make_entry(dict, entry_id: "n1", headword: "bʰer-", folded: "bher-", gloss: "to carry")
      make_entry(dict, entry_id: "n2", headword: "bogъ", folded: "bogъ", gloss: "god")
      make_entry(dict, entry_id: "n3", headword: "gone", folded: "gone", withdrawn: true)
      dict
    end

    def test_entries_enumerate_headword_and_gloss_live_only
      seed_dictionary_shelf
      page = list.entries("ccmh")
      assert_equal 2, page.total
      assert_equal ["bʰer-", "bogъ"], page.rows.map(&:headword)
      assert_equal "to carry", page.rows.first.gloss
    end

    def test_entries_prefix_filters_by_folded_prefix
      seed_dictionary_shelf
      # ASCII "bh" reaches the folded "bher-" through the proto fold (ʰ→h),
      # and the comparativist's leading asterisk is stripped.
      page = list.entries("ccmh", prefix: "*bʰ")
      assert_equal ["bʰer-"], page.rows.map(&:headword)
      assert_equal ["bʰer-"], list.entries("ccmh", prefix: "bh").rows.map(&:headword)
    end

    def test_entries_lang_filter_scopes_to_one_dictionary_language
      seed_dictionary_shelf
      other = make_dictionary(source: @ccmh, slug: "lsj", language: "grc")
      make_entry(other, entry_id: "g1", headword: "μῆνις", folded: "μηνισ")
      assert_equal ["μῆνις"], list.entries("ccmh", lang: "grc").rows.map(&:headword)
    end

    def test_entries_on_a_non_dictionary_source_returns_nil
      seed_ccmh
      assert_nil list.entries("local-library")
    end

    # -- collections -------------------------------------------------------------

    def test_collections_census_counts_manifest_segments
      make_document(source: @library, urn: "urn:nabu:local-library:slavistics:leskien")
      make_document(source: @library, urn: "urn:nabu:local-library:slavistics:jagic")
      make_document(source: @library, urn: "urn:nabu:local-library:articles:vaillant")
      assert_equal({ "slavistics" => 2, "articles" => 1 }, list.collections("local-library"))
    end

    def test_collections_nil_for_sources_without_collection_segments
      make_document(source: @ccmh, urn: "urn:cts:greekLit:tlg0012.tlg001.perseus-grc2")
      assert_nil list.collections("ccmh")
    end

    # -- the dossier shelf (P22-1 live gap: language grain) --------------------

    def test_group_derivation_falls_back_to_iecor_clade_when_family_lane_absent
      # The live gap (2026-07-18): sga's dossier has no family lane, but its
      # iecor accretion says "clade Celtic" — corph misfiled under Greek &
      # Latin because the derivation fell through to its minority Latin.
      source = make_source(slug: "corph-like", name: "CorPH-like", license_class: "attribution")
      doc = make_document(source: source, urn: "urn:nabu:corph-like:1", language: "sga")
      make_passage(doc, urn: "urn:nabu:corph-like:1:1", sequence: 0, language: "sga")
      @catalog[:language_records].insert(lang_code: "sga", kind: "iecor",
                                         body: "IE-CoR variety: Old Irish (clade Celtic < Indo-European)",
                                         source: "iecor")
      groups = list.source_groups.to_h
      celtic = groups.fetch("Celtic", []).map(&:slug)
      assert_includes celtic, "corph-like", "iecor clade evidence must route the family"
    end

    def test_group_derivation_reads_indo_iranic_clade_spelling
      # IE-CoR spells the clade "Indo-Iranic" (pli: "clade Indo-Iranic >
      # Indic") — the live suttacentral shelf leaked it as its own heading
      # instead of landing under Indic & Iranian.
      source = make_source(slug: "pali-like", name: "Pali-like", license_class: "open")
      doc = make_document(source: source, urn: "urn:nabu:pali-like:1", language: "pli")
      make_passage(doc, urn: "urn:nabu:pali-like:1:1", sequence: 0, language: "pli")
      @catalog[:language_records].insert(lang_code: "pli", kind: "iecor",
                                         body: "IE-CoR variety: Pali (clade Indo-Iranic > Indic; Glottocode pali1273)",
                                         source: "iecor")
      groups = list.source_groups.to_h
      indic = groups.fetch("Indic & Iranian", []).map(&:slug)
      assert_includes indic, "pali-like", "Indo-Iranic must hit the Indic & Iranian net"
    end

    def test_dominance_prefers_source_language_over_english_translation_layer
      # The live damaskini shape: the aligned -en siblings hold MORE passages
      # (6,036 eng vs 5,123 bul), so the translation layer outvoted the source
      # language and the shelf read Germanic. English never outvotes an
      # attested source language; an all-English shelf still reads Germanic.
      source = make_source(slug: "dam-like", name: "Damaskini-like", license_class: "open")
      bul_doc = make_document(source: source, urn: "urn:nabu:dam-like:1", language: "bul")
      make_passage(bul_doc, urn: "urn:nabu:dam-like:1:1", sequence: 0, language: "bul")
      eng_doc = make_document(source: source, urn: "urn:nabu:dam-like:1-en", language: "eng")
      make_passage(eng_doc, urn: "urn:nabu:dam-like:1-en:1", sequence: 0, language: "eng")
      make_passage(eng_doc, urn: "urn:nabu:dam-like:1-en:2", sequence: 1, language: "eng")
      @catalog[:language_records].insert(lang_code: "bul", kind: "family", body: "South Slavic", source: "dossier")
      @catalog[:language_records].insert(lang_code: "eng", kind: "family", body: "West Germanic", source: "dossier")
      groups = list.source_groups.to_h
      slavic = groups.fetch("Slavic", []).map(&:slug)
      assert_includes slavic, "dam-like", "eng translation passages must not outvote bul"
    end

    def make_language_shelf
      source = Nabu::Store::Source.create(
        slug: "local-language", name: "Language dossiers",
        adapter_class: "Nabu::Adapters::LocalLanguage", license_class: "open", enabled: true
      )
      [["chu", "name", "Church Slavonic"], %w[chu family slavic], %w[chu context curated],
       %w[got name Gothic], ["got", "witness:liv", "wrote"]].each do |code, kind, body|
        @catalog[:language_records].insert(lang_code: code, kind: kind, body: body, source: "dossier")
      end
      source
    end

    def test_census_counts_dossiers_for_the_language_shelf
      make_language_shelf
      row = list.census.find { |r| r.slug == "local-language" }
      assert_equal 2, row.dossiers, "199 dossiers must never render as empty (live gap 2026-07-15)"
      assert_equal 0, row.docs
    end

    def test_card_carries_dossier_count_and_record_kinds
      make_language_shelf
      card = list.card("local-language")
      assert_equal 2, card.dossiers
      assert_equal({ "name" => 2, "context" => 1, "family" => 1, "witness:liv" => 1 }, card.record_kinds)
    end

    def test_documents_on_the_language_shelf_enumerates_dossiers
      make_language_shelf
      page = list.documents("local-language", limit: 10)
      assert_equal 2, page.total
      codes = page.rows.map(&:code)
      assert_equal %w[chu got], codes
      chu = page.rows.first
      assert_equal "Church Slavonic", chu.name
      assert_equal "slavic", chu.family
    end

    def test_dossier_enumeration_honors_prefix_and_limit
      make_language_shelf
      page = list.documents("local-language", prefix: "ch", limit: 10)
      assert_equal %w[chu], page.rows.map(&:code)
      page = list.documents("local-language", limit: 1)
      assert_equal 2, page.total, "the tail stays honest under --limit"
    end

    def test_prefix_on_a_document_grain_shelf_is_a_named_inapplicability
      make_document(source: @ccmh, urn: "urn:nabu:ccmh:mar:mt")
      error = assert_raises(Nabu::Query::List::Error) { list.documents("ccmh", prefix: "urn") }
      assert_match(/headwords and dossier codes/, error.message)
    end

    def test_document_filters_are_named_inapplicable_on_the_dossier_shelf
      make_language_shelf
      error = assert_raises(Nabu::Query::List::Error) { list.documents("local-language", lang: "chu") }
      assert_match(/dossier/, error.message)
    end

    # -- the source-dossier shelf (P24-0) ------------------------------------

    def make_source_shelf
      source = Nabu::Store::Source.create(
        slug: "local-source", name: "Source dossiers",
        adapter_class: "Nabu::Adapters::LocalSource", license_class: "open", enabled: true
      )
      [["ccmh", "description", "OCS gospel codices with a diplomatic layer."],
       ["edh", "description", "Latin inscriptions, empire-wide."],
       %w[edh theme epigraphy],
       ["edh", "witness:survey", "surveyed"]].each do |slug, kind, body|
        @catalog[:source_records].insert(slug: slug, kind: kind, body: body, provenance: "dossier")
      end
      source
    end

    def test_card_renders_the_dossier_description
      make_source_shelf
      assert_equal "OCS gospel codices with a diplomatic layer.", list.card("ccmh").description
    end

    def test_card_description_nil_without_a_dossier_record
      assert_nil list.card("ccmh").description
    end

    def test_descriptions_map_serves_the_census
      make_source_shelf
      assert_equal({ "ccmh" => "OCS gospel codices with a diplomatic layer.",
                     "edh" => "Latin inscriptions, empire-wide." }, list.descriptions)
    end

    def test_census_and_card_count_source_dossiers
      make_source_shelf
      row = list.census.find { |r| r.slug == "local-source" }
      assert_equal 2, row.dossiers, "the source shelf must never render as empty (the P22-1 gap class)"
      card = list.card("local-source")
      assert_equal 2, card.dossiers
      assert_equal({ "description" => 2, "theme" => 1, "witness:survey" => 1 }, card.record_kinds)
    end

    def test_documents_on_the_source_shelf_is_a_named_miss
      make_source_shelf
      error = assert_raises(Nabu::Query::List::Error) { list.documents("local-source") }
      assert_match(/card/, error.message)
    end

    # -- source_groups (P28-4: the one-page grouped map) ---------------------

    def seed_family_lanes
      { "chu" => "South Slavic", "grc" => "Hellenic < Indo-European", "lat" => "Italic < Indo-European",
        "sla-pro" => "Slavic < Balto-Slavic < Indo-European (reconstructed)",
        "ine-pro" => "Indo-European trunk (reconstructed)", "zle" => "East Slavic" }.each do |code, body|
        @catalog[:language_records].insert(lang_code: code, kind: "family", body: body, source: "dossier")
      end
    end

    def group_of(slug)
      list.source_groups.find { |_group, lines| lines.any? { |line| line.slug == slug } }&.first
    end

    def test_source_groups_pins_the_curated_header_order
      assert_equal ["Greek & Latin", "Biblical & Near Eastern", "Slavic", "Celtic",
                    "Indic & Iranian", "Egyptian & Coptic", "Germanic & Old English",
                    "Reference & dictionaries", "Your shelves", "Other"],
                   Nabu::Query::List::GROUP_ORDER
    end

    def test_source_groups_join_census_languages_to_family_lanes
      seed_family_lanes
      seed_ccmh
      assert_equal "Slavic", group_of("ccmh"), "chu's South Slavic lane lands the shelf under Slavic"
      assert_equal "Other", group_of("local-library"), "no languages, no family lane — the honest residue"
    end

    def test_source_groups_dominant_language_family_decides_multi_family_shelves
      seed_family_lanes
      doc = make_document(source: @ccmh, urn: "urn:nabu:ccmh:mix", language: "grc")
      make_passage(doc, urn: "urn:nabu:ccmh:mix:1", sequence: 0, language: "grc")
      make_passage(doc, urn: "urn:nabu:ccmh:mix:2", sequence: 1, language: "grc")
      make_passage(doc, urn: "urn:nabu:ccmh:mix:3", sequence: 2, language: "chu")
      assert_equal "Greek & Latin", group_of("ccmh"), "the dominant language's family wins"
    end

    def test_source_groups_dictionary_spanning_families_reads_reference
      seed_family_lanes
      grc_dict = make_dictionary(source: @ccmh, slug: "lsj", language: "grc")
      make_entry(grc_dict, entry_id: "g1", headword: "μῆνις", folded: "μηνισ")
      slav = make_dictionary(source: @ccmh, slug: "sla-pro", language: "sla-pro")
      make_entry(slav, entry_id: "n1", headword: "bogъ", folded: "bogъ")
      assert_equal "Reference & dictionaries", group_of("ccmh")
    end

    def test_source_groups_single_family_dictionary_stays_in_its_family
      seed_family_lanes
      dict = make_dictionary(source: @ccmh, slug: "sla-pro", language: "sla-pro")
      make_entry(dict, entry_id: "n1", headword: "bogъ", folded: "bogъ")
      assert_equal "Slavic", group_of("ccmh")
    end

    def test_source_groups_local_shelves_read_your_shelves
      %w[LocalLanguage LocalSource LocalNotes LocalLibrary].each_with_index do |cls, i|
        Nabu::Store::Source.create(slug: "shelf-#{i}", name: cls, adapter_class: "Nabu::Adapters::#{cls}",
                                   license_class: "open", enabled: true)
      end
      4.times { |i| assert_equal "Your shelves", group_of("shelf-#{i}") }
    end

    def test_source_groups_override_lane_wins_over_derivation
      seed_family_lanes
      seed_ccmh
      make_source_shelf
      @catalog[:source_records].insert(slug: "ccmh", kind: "group", body: "Celtic", provenance: "dossier")
      assert_equal "Celtic", group_of("ccmh"), "the dossier's group: lane wins over the derived Slavic"
    end

    def test_source_groups_unknown_labels_append_before_other
      seed_family_lanes
      doc = make_document(source: @ccmh, urn: "urn:nabu:ccmh:ie", language: "ine-pro")
      make_passage(doc, urn: "urn:nabu:ccmh:ie:1", sequence: 0, language: "ine-pro")
      groups = list.source_groups.map(&:first)
      assert_includes groups, "Indo-European trunk",
                      "an unmatched family derives its own label, parenthetical stripped"
      assert_operator groups.index("Indo-European trunk"), :<, groups.index("Other"),
                      "unknown derived families append before Other"
    end

    def test_source_groups_hyphen_code_falls_back_to_the_family_prefix_lane
      seed_family_lanes
      doc = make_document(source: @ccmh, urn: "urn:nabu:ccmh:orth", language: "zle-ort")
      make_passage(doc, urn: "urn:nabu:ccmh:orth:1", sequence: 0, language: "zle-ort")
      assert_equal "Slavic", group_of("ccmh"), "zle-ort reads the zle family lane"
    end

    def test_source_groups_lines_carry_description_and_enabled
      seed_family_lanes
      seed_ccmh
      make_source_shelf
      @catalog[:sources].where(slug: "ccmh").update(enabled: false)
      line = list.source_groups.flat_map(&:last).find { |l| l.slug == "ccmh" }
      assert_equal "OCS gospel codices with a diplomatic layer.", line.description
      refute line.enabled
    end

    def test_source_groups_orders_present_groups_by_the_curated_constant
      seed_family_lanes
      seed_ccmh
      latin = make_source(slug: "anthology", name: "Anthology", license_class: "open")
      doc = make_document(source: latin, urn: "urn:nabu:anthology:a", language: "lat")
      make_passage(doc, urn: "urn:nabu:anthology:a:1", sequence: 0, language: "lat")
      assert_equal([["Greek & Latin", %w[anthology]], ["Slavic", %w[ccmh]], ["Other", %w[local-library]]],
                   list.source_groups.map { |group, lines| [group, lines.map(&:slug)] })
    end

    # -- the loans facet on list (P34-2): census + per-code enumeration ------

    # A passage carrying the P17-1 loans annotation shape, written with the
    # loader's own serializer, so list reads the stored contract.
    def make_loan_passage(document, urn:, sequence:, loans:, withdrawn: false)
      Nabu::Store::Passage.create(
        document_id: document.id, urn: urn, sequence: sequence, language: "cop",
        text: "text #{sequence}", text_normalized: "text #{sequence}",
        annotations_json: Nabu::Store::ContentHash.canonical_json(
          { "tokens" => [], "loans" => loans }
        ),
        content_sha256: "x", revision: 1, withdrawn: withdrawn
      )
    end

    def seed_loans_shelf
      cs = make_source(slug: "cs", name: "Coptic", license_class: "open")
      a = make_document(source: cs, urn: "urn:cs:a", language: "cop", title: "Mark")
      b = make_document(source: cs, urn: "urn:cs:b", language: "cop", title: "Besa")
      make_loan_passage(a, urn: "urn:cs:a:1", sequence: 0, loans: { "grc" => 2, "hbo" => 1 })
      make_loan_passage(a, urn: "urn:cs:a:2", sequence: 1, loans: { "grc" => 1 })
      make_loan_passage(b, urn: "urn:cs:b:1", sequence: 0, loans: { "grc" => 3 })
      make_passage(b, urn: "urn:cs:b:2", sequence: 1, language: "cop") # loan-free
      cs
    end

    def test_loans_census_tallies_codes_docs_passages_and_tokens
      seed_loans_shelf
      rows = list.loans_census("cs")
      assert_equal [["grc", 2, 3, 6], ["hbo", 1, 1, 1]],
                   rows.map { |r| [r.code, r.docs, r.passages, r.tokens] },
                   "token-count order: grc 2 docs / 3 passages / 6 tokens, then hbo"
    end

    def test_loans_census_excludes_withdrawn_rows
      cs = seed_loans_shelf
      gone = make_document(source: cs, urn: "urn:cs:w", language: "cop", withdrawn: true)
      make_loan_passage(gone, urn: "urn:cs:w:1", sequence: 0, loans: { "grc" => 9 })
      c = make_document(source: cs, urn: "urn:cs:c", language: "cop")
      make_loan_passage(c, urn: "urn:cs:c:1", sequence: 0, loans: { "grc" => 9 }, withdrawn: true)
      rows = list.loans_census("cs")
      assert_equal [["grc", 2, 3, 6], ["hbo", 1, 1, 1]],
                   rows.map { |r| [r.code, r.docs, r.passages, r.tokens] },
                   "withdrawn documents and passages contribute nothing"
    end

    def test_loans_census_is_empty_for_a_loanless_source
      seed_ccmh
      assert_empty list.loans_census("ccmh")
    end

    def test_loans_census_unknown_source_raises
      assert_raises(Nabu::Query::List::Error) { list.loans_census("nope") }
    end

    def test_loan_documents_ranks_documents_by_token_count
      seed_loans_shelf
      page = list.loan_documents("cs", code: "grc")
      assert_equal 2, page.total
      assert_equal [["urn:cs:a", "Mark", "cop", 3, 2], ["urn:cs:b", "Besa", "cop", 3, 1]],
                   page.rows.map { |r| [r.urn, r.title, r.language, r.tokens, r.passages] },
                   "token-count desc, urn as the tiebreak"
    end

    def test_loan_documents_matches_the_code_case_insensitively_and_honors_limit
      seed_loans_shelf
      page = list.loan_documents("cs", code: "GRC", limit: 1)
      assert_equal 2, page.total, "the total stays honest past the page"
      assert_equal %w[urn:cs:a], page.rows.map(&:urn)
      assert_empty list.loan_documents("cs", code: "xyz").rows, "an unattested code is an honest miss"
    end
  end
end
