# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"
require "digest"

# The mul/reflex-chains builder: the held etymological dictionaries'
# reconstruction→reflex edges (dictionary_reflexes) as one table, license
# screening row-by-row (nc dictionaries contribute nothing, censused per
# class and source), withdrawn entries skipped, and the Attested join —
# a reflex's stored folded form (word, else romanization) EQUAL to a gold
# lemma_rollup key under the same catalog language code, counted from
# publishable sources only.
class ReflexChainsBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "wiktionary-recon" => EntryRig.new(manifest: ManifestRig.new(
      name: "Wiktionary reconstructions", upstream_url: "https://wikt.example", license: "CC BY-SA 4.0"
    )),
      "starling" => EntryRig.new(manifest: ManifestRig.new(
        name: "Tower of Babel", upstream_url: "https://starling.example", license: "CC BY 4.0"
      )) }
  end

  def source(slug, license_class)
    Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: license_class)
  end

  def dictionary(slug, language, source)
    @catalog[:dictionaries].insert(slug: slug, title: slug, language: language, source_id: source.id)
  end

  def entry(dictionary_id, slug, entry_id, headword, withdrawn: false)
    @catalog[:dictionary_entries].insert(
      dictionary_id: dictionary_id, urn: "urn:nabu:dict:#{slug}:#{entry_id}", entry_id: entry_id,
      key_raw: headword, headword: headword, headword_folded: headword.delete("*"), body: headword,
      content_sha256: Digest::SHA256.hexdigest(headword), withdrawn: withdrawn
    )
  end

  def reflex(entry_id, seq, lang_code, language, word, folded, roman: nil, roman_folded: nil,
             borrowed: false, uncertain: false)
    @catalog[:dictionary_reflexes].insert(
      dictionary_entry_id: entry_id, seq: seq, lang_code: lang_code, language: language, word: word,
      word_folded: folded, roman: roman, roman_folded: roman_folded, borrowed: borrowed, uncertain: uncertain
    )
  end

  def rollup(lemma, language, grade, source, occurrences, century: nil)
    @catalog[:lemma_rollup].insert(lemma: lemma, language: language, century: century, basis: nil,
                                   grade: grade, source_id: source.id, occurrences: occurrences, documents: 1)
  end

  def setup
    @catalog = store_test_db
    wikt = source("wiktionary-recon", "attribution")
    star = source("starling", "attribution")
    derom = source("derom", "nc")
    mw = source("mw", "nc")
    treebank = source("treebank", "open")
    ebl = source("ebl", "nc")

    gem = dictionary("wiktionary-gem-pro", "gem-pro", wikt)
    germet = dictionary("starling-germet", "gem-pro", star)
    derom_dict = dictionary("derom", "la-vul", derom)
    mw_dict = dictionary("mw", "san", mw)

    hlaibaz = entry(gem, "wiktionary-gem-pro", "hlaibaz", "*hlaibaz")
    # Gothic via the romanization bridge (the Gothic-script form folds to
    # itself; the gold lemma is the romanized "hlaifs").
    reflex(hlaibaz, 1, "got", "got", "𐌷𐌻𐌰𐌹𐍆𐍃", "𐌷𐌻𐌰𐌹𐍆𐍃", roman: "hlaifs", roman_folded: "hlaifs")
    reflex(hlaibaz, 2, "ang", "ang", "hlāf", "hlaf")
    # A display-only node: no catalog language, so no join is attempted.
    reflex(hlaibaz, 3, "sla-pro", nil, "*xlěbъ", "xlebъ", borrowed: true)
    # Attested ONLY in a screened (nc) source: the count stays empty.
    reflex(hlaibaz, 4, "non", "non", "hleifr", "hleifr", borrowed: nil, uncertain: true)
    # Same form, different code: no cross-language matching.
    reflex(hlaibaz, 5, "goh", "goh", "hleib", "hleib")

    germet_entry = entry(germet, "starling-germet", "hlaib", "*hlaib-")
    reflex(germet_entry, 1, "got", "got", "hlaifs", "hlaifs")

    gone = entry(gem, "wiktionary-gem-pro", "withdrawn", "*gone", withdrawn: true)
    reflex(gone, 1, "ang", "ang", "hlāf", "hlaf")

    reflex(entry(derom_dict, "derom", "pane", "*pane"), 1, "ron", "ron", "pâine", "paine")
    mw_entry = entry(mw_dict, "mw", "deva", "deva")
    reflex(mw_entry, 1, "pi", "pli", "deva", "deva")
    reflex(mw_entry, 2, "pra", "pra", "deva", "deva")

    rollup("hlaifs", "got", "gold", treebank, 5, century: 4)
    rollup("hlaifs", "got", "gold", treebank, 2)
    rollup("hlaifs", "got", "gold", ebl, 100) # screened: never counted
    rollup("hlaf", "ang", "gold", treebank, 3)
    rollup("hlaf", "ang", "silver", treebank, 50) # silver grade: never counted
    rollup("hleifr", "non", "gold", ebl, 9)
    rollup("hleib", "gml", "gold", treebank, 4)
    rollup("paine", "ron", "gold", treebank, 6)
  end

  def build!(out_dir)
    Nabu::DataBuild::ReflexChainsBuilder.new(registry: registry_rig).build(catalog: @catalog, out_dir: out_dir)
  end

  # The table ships gzipped (the plain CSV crosses the platform's 100 MB
  # limit live); reading back through GzipReader is part of the contract.
  def table(dir)
    raw = Zlib::GzipReader.open(File.join(dir, "reflex-chains.csv.gz"), &:read)
    CSV.parse(raw, headers: true)
  end

  def test_publishes_reflex_rows_of_publishable_dictionaries_in_dictionary_entry_seq_order
    Dir.mktmpdir do |dir|
      result = build!(dir)
      csv = table(dir)
      order = csv.map { |row| row.values_at("Dictionary", "Seq", "Lang_Code") }
      assert_equal %w[ID Dictionary URN Headword Headword_Language Seq Lang_Code Language_ID Form Roman
                      Form_Folded Roman_Folded Borrowed Uncertain Attested Attested_Via Source], csv.headers
      assert_equal [%w[starling-germet 1 got], %w[wiktionary-gem-pro 1 got], %w[wiktionary-gem-pro 2 ang],
                    %w[wiktionary-gem-pro 3 sla-pro], %w[wiktionary-gem-pro 4 non],
                    %w[wiktionary-gem-pro 5 goh]],
                   order
      assert_equal 6, result.resources.first.rows
      assert_equal "reflex_chains", result.resources.first.name
    end
  end

  def test_rows_carry_headword_and_reflex_verbatim_with_flags
    Dir.mktmpdir do |dir|
      build!(dir)
      gothic = table(dir).find { |row| row["Dictionary"] == "wiktionary-gem-pro" && row["Seq"] == "1" }
      assert_equal ["urn:nabu:dict:wiktionary-gem-pro:hlaibaz", "*hlaibaz", "gem-pro", "got", "𐌷𐌻𐌰𐌹𐍆𐍃",
                    "hlaifs", "𐌷𐌻𐌰𐌹𐍆𐍃", "hlaifs", "false", "false", "wiktionary-recon"],
                   gothic.values_at("URN", "Headword", "Headword_Language", "Language_ID", "Form", "Roman",
                                    "Form_Folded", "Roman_Folded", "Borrowed", "Uncertain", "Source")
      slavic = table(dir).find { |row| row["Lang_Code"] == "sla-pro" }
      assert_nil slavic["Language_ID"], "a display-only node carries no catalog language"
      assert_equal "true", slavic["Borrowed"]
      norse = table(dir).find { |row| row["Lang_Code"] == "non" }
      assert_nil norse["Borrowed"], "an unknown (NULL) flag stays empty, never a claimed false"
      assert_equal "true", norse["Uncertain"]
    end
  end

  def test_the_attested_join_is_folded_equality_under_the_same_language_from_publishable_gold
    Dir.mktmpdir do |dir|
      build!(dir)
      attested = table(dir).to_h do |row|
        [[row["Dictionary"], row["Seq"]], row.values_at("Attested", "Attested_Via")]
      end
      assert_equal %w[7 roman], attested[%w[wiktionary-gem-pro 1]],
                   "the romanization bridge; the nc gold row (100) never adds"
      assert_equal %w[7 form], attested[%w[starling-germet 1]], "the form itself matches first"
      assert_equal %w[3 form], attested[%w[wiktionary-gem-pro 2]], "the silver grade (50) never adds"
      assert_equal [nil, nil], attested[%w[wiktionary-gem-pro 3]], "display-only: no join attempted"
      assert_equal [nil, nil], attested[%w[wiktionary-gem-pro 4]], "attested only in a screened source"
      assert_equal [nil, nil], attested[%w[wiktionary-gem-pro 5]], "no cross-language matching"
    end
  end

  def test_nc_dictionaries_contribute_nothing_and_are_censused_per_class_and_source
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      csv = table(dir)
      refute_includes csv.map { |row| row["Dictionary"] }, "derom"
      refute_includes csv.map { |row| row["Dictionary"] }, "mw"
      refute_includes csv.map { |row| row["Source"] }, "derom"
      refute_includes csv.map { |row| row["Form"] }, "pâine"
      assert_equal({ "nc" => 3 }, evaluation["excluded_rows"])
      assert_equal({ "nc/derom" => 1, "nc/mw" => 2 }, evaluation["excluded_rows_by_source"])
    end
  end

  def test_the_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 10, evaluation["reflex_rows"]
      assert_equal 1, evaluation["withdrawn_entry_rows_skipped"]
      assert_equal 6, evaluation["published_rows"]
      assert_equal({ "starling" => 1, "wiktionary-recon" => 5 }, evaluation["published_rows_by_source"])
      assert_equal({ "attested" => 3, "via_form" => 2, "via_roman" => 1, "display_only" => 1,
                     "attested_only_in_screened_sources" => 1 }, evaluation["attestation"])
      assert_equal({ "ang" => { "attested" => 1, "missed" => 0 },
                     "goh" => { "attested" => 0, "missed" => 1 },
                     "got" => { "attested" => 2, "missed" => 0 },
                     "non" => { "attested" => 0, "missed" => 1 } },
                   evaluation["attestation_by_language"])
    end
  end

  def test_ids_are_legal_unique_and_keyed_on_the_entry_digest
    Dir.mktmpdir do |dir|
      build!(dir)
      ids = table(dir).map { |row| row["ID"] }
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }
      assert_equal ids.uniq, ids
      assert_equal "wiktionary-gem-pro-E#{Digest::SHA256.hexdigest('hlaibaz')[0, 12]}-2", ids[2]
    end
  end

  def test_citations_cover_the_published_sources_only
    Dir.mktmpdir do |dir|
      assert_equal %w[starling wiktionary-recon], build!(dir).citations.map(&:key)
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      assert_match(/folded/, first, "the join rule is stated in the recipe")
      assert_match(/No fuzzy matching, no cross-language\s+matching/, build!(dir).notes,
                   "the join rule is stated in the README")
      @catalog[:dictionary_reflexes].where(word: "pâine").update(word: "pîine")
      assert_equal first, build!(dir).recipe, "a screened row never moves the published fingerprint"
      @catalog[:lemma_rollup].where(lemma: "hlaf", grade: "gold").update(occurrences: 4)
      refute_equal first, build!(dir).recipe, "the attested count is part of the published slice"
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::ReflexChainsBuilder.new(registry: registry_rig).build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
