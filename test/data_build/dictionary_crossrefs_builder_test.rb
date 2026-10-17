# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"
require "digest"

# The mul/dictionary-crossrefs builder: the catalog's dictionary_crossrefs
# published as the cross-dictionary reference graph — one row per edge,
# entries referenced by their stable URNs (never the volatile integer id),
# unresolved edges published with empty target-entry fields, and license
# screening on BOTH endpoints: an edge publishes only when its own
# dictionary's source AND (when resolved) its target entry's dictionary's
# source are open/attribution — an nc endpoint on either side drops the
# edge, censused per endpoint role and class.
class DictionaryCrossrefsBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    { "lexica" => EntryRig.new(manifest: ManifestRig.new(
      name: "Lexica", upstream_url: "https://lexica.example", license: "CC BY-SA 4.0"
    )),
      "hebrew-lexicon" => EntryRig.new(manifest: ManifestRig.new(
        name: "Hebrew Lexicon", upstream_url: "https://hebrew.example", license: "CC BY 4.0"
      )) }
  end

  def source(slug, license_class)
    Nabu::Store::Source.create(slug: slug, name: slug, adapter_class: "TestAdapter", license_class: license_class)
  end

  def dictionary(source, slug, language)
    @catalog[:dictionaries].insert(source_id: source.id, slug: slug, title: slug.upcase, language: language)
  end

  def entry(dictionary_id, slug, entry_id, headword, withdrawn: false)
    @catalog[:dictionary_entries].insert(
      dictionary_id: dictionary_id, urn: "urn:nabu:dict:#{slug}:#{entry_id}", entry_id: entry_id,
      key_raw: entry_id, headword: headword, headword_folded: headword, body: headword,
      content_sha256: Digest::SHA256.hexdigest(headword), withdrawn: withdrawn
    )
  end

  def crossref(from, seq, kind, label, target, to: nil, folded: nil, target_id: nil, to_dictionary: nil)
    @catalog[:dictionary_crossrefs].insert(
      dictionary_entry_id: from, seq: seq, kind: kind, label: label, target: target,
      target_folded: folded, to_entry_id: to, target_id: target_id, to_dictionary: to_dictionary
    )
  end

  def setup
    @catalog = store_test_db
    lexica = source("lexica", "attribution")
    hebrew = source("hebrew-lexicon", "open")
    sanskrit = source("cdsl", "nc")
    lsj = dictionary(lexica, "lsj", "grc")
    bdb = dictionary(hebrew, "bdb", "hbo")
    oshb = dictionary(hebrew, "oshb-lex", "hbo")
    mw = dictionary(sanskrit, "mw", "san")

    @mythos = entry(lsj, "lsj", "n70000", "μῦθος")
    @logos = entry(lsj, "lsj", "n63000", "λόγος")
    @ab = entry(bdb, "bdb", "b.aa.ab", "אָב")
    @lex = entry(oshb, "oshb-lex", "aaa", "אב")
    @deva = entry(mw, "mw", "93123", "deva")
    @agni = entry(mw, "mw", "1001", "agni")
    @gone = entry(lsj, "lsj", "n1", "ἀάατος", withdrawn: true)

    # Same-dictionary, resolved.
    crossref(@logos, 1, "see", "v. μῦθος", "μῦθος", to: @mythos, folded: "μυθος")
    # Same-dictionary, unresolved (an ambiguous homograph pointer).
    crossref(@logos, 2, "like", "cf. λέγω", "λέγω", folded: "λεγω")
    # Cross-dictionary, resolved by id (oshb-lex -> bdb).
    crossref(@lex, 1, "equals", "bdb b.aa.ab", "b.aa.ab", to: @ab, target_id: "b.aa.ab", to_dictionary: "bdb")
    # Cross-dictionary, unresolved (a dictionary the catalog does not hold).
    crossref(@lex, 2, "equals", "twot 4a", "4a", target_id: "4a", to_dictionary: "twot")
    # The nc SOURCE endpoint: mw's own edges, resolved and not.
    crossref(@deva, 1, "see", "s.v. agni", "agni", to: @agni, folded: "agni")
    crossref(@deva, 2, "see", "s.v. soma", "soma", folded: "soma")
    # The nc TARGET endpoint: an open entry pointing INTO mw.
    crossref(@mythos, 1, "related", "cf. deva", "deva", to: @deva, to_dictionary: "mw")
    # An edge from a withdrawn entry: never published, censused.
    crossref(@gone, 1, "see", "v. λόγος", "λόγος", to: @logos, folded: "λογος")
  end

  def build!(out_dir)
    Nabu::DataBuild::DictionaryCrossrefsBuilder.new(registry: registry_rig)
                                               .build(catalog: @catalog, out_dir: out_dir)
  end

  def table(dir) = CSV.read(File.join(dir, "dictionary-crossrefs.csv"), headers: true)

  def test_publishes_one_row_per_edge_in_dictionary_entry_seq_order
    Dir.mktmpdir do |dir|
      result = build!(dir)
      csv = table(dir)
      assert_equal %w[ID Language_ID Dictionary Entry_URN Headword Seq Kind Label Target Target_Folded
                      Target_ID Target_Dictionary Target_Entry_URN Target_Headword Source], csv.headers
      assert_equal [["lsj", "urn:nabu:dict:lsj:n63000", "1"],
                    ["lsj", "urn:nabu:dict:lsj:n63000", "2"],
                    ["oshb-lex", "urn:nabu:dict:oshb-lex:aaa", "1"],
                    ["oshb-lex", "urn:nabu:dict:oshb-lex:aaa", "2"]],
                   csv.map { |row| row.values_at("Dictionary", "Entry_URN", "Seq") },
                   "publishable edges only, ordered (dictionary, entry URN, seq)"
      assert_equal 4, result.resources.first.rows
      assert_equal "dictionary_crossrefs", result.resources.first.name
    end
  end

  def test_a_resolved_edge_publishes_the_target_entry_by_urn
    Dir.mktmpdir do |dir|
      build!(dir)
      see = table(dir).find { |row| row["Label"] == "v. μῦθος" }
      assert_equal ["grc", "λόγος", "see", "μῦθος", "μυθος", nil, "lsj", "urn:nabu:dict:lsj:n70000", "μῦθος",
                    "lexica"],
                   see.values_at("Language_ID", "Headword", "Kind", "Target", "Target_Folded", "Target_ID",
                                 "Target_Dictionary", "Target_Entry_URN", "Target_Headword", "Source")
      cross = table(dir).find { |row| row["Label"] == "bdb b.aa.ab" }
      assert_equal ["b.aa.ab", "bdb", "urn:nabu:dict:bdb:b.aa.ab", "אָב"],
                   cross.values_at("Target_ID", "Target_Dictionary", "Target_Entry_URN", "Target_Headword"),
                   "a cross-dictionary edge names the target entry's own dictionary"
    end
  end

  def test_an_unresolved_edge_is_still_an_edge
    Dir.mktmpdir do |dir|
      build!(dir)
      csv = table(dir)
      homograph = csv.find { |row| row["Label"] == "cf. λέγω" }
      assert_equal ["λέγω", "λεγω", "lsj", nil, nil],
                   homograph.values_at("Target", "Target_Folded", "Target_Dictionary", "Target_Entry_URN",
                                       "Target_Headword"),
                   "an unresolved same-dictionary pointer names its own dictionary, target entry empty"
      twot = csv.find { |row| row["Label"] == "twot 4a" }
      assert_equal ["4a", "twot", nil, nil],
                   twot.values_at("Target_ID", "Target_Dictionary", "Target_Entry_URN", "Target_Headword"),
                   "an unresolved cross-dictionary pointer keeps the named dictionary verbatim"
    end
  end

  def test_an_nc_endpoint_on_either_side_contributes_nothing
    Dir.mktmpdir do |dir|
      build!(dir)
      csv = table(dir)
      refute_includes csv.map { |row| row["Dictionary"] }, "mw", "nc SOURCE endpoint: mw's own edges drop"
      refute_includes csv.map { |row| row["Target_Dictionary"] }, "mw", "nc TARGET endpoint: edges into mw drop"
      refute_includes csv.map { |row| row["Label"] }, "cf. deva"
      refute(csv.any? { |row| row.fields.compact.any? { |cell| cell.include?("deva") || cell.include?("agni") } },
             "no nc headword, URN or label survives anywhere in the table")
      refute_includes csv.map { |row| row["Source"] }, "cdsl"
    end
  end

  def test_an_edge_from_a_withdrawn_entry_is_never_published
    Dir.mktmpdir do |dir|
      build!(dir)
      refute_includes table(dir).map { |row| row["Entry_URN"] }, "urn:nabu:dict:lsj:n1"
    end
  end

  def test_ids_are_legal_stable_and_keyed_on_the_entry_digest
    Dir.mktmpdir do |dir|
      build!(dir)
      ids = table(dir).map { |row| row["ID"] }
      ids.each { |id| assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, id }
      assert_equal ids.uniq, ids
      see = table(dir).find { |row| row["Label"] == "v. μῦθος" }
      assert_equal "lsj-E#{Digest::SHA256.hexdigest('n63000')[0, 12]}-1", see["ID"]
    end
  end

  def test_the_census_rides_in_band_per_role_class_and_resolution
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 8, evaluation["crossref_rows"]
      assert_equal 1, evaluation["withdrawn_entry_edges_skipped"]
      assert_equal 4, evaluation["published_edges"]
      assert_equal({ "resolved" => 2, "unresolved" => 2 }, evaluation["published_by_resolution"])
      assert_equal({ "lsj" => 2, "oshb-lex" => 2 }, evaluation["published_by_dictionary"])
      assert_equal({ "source" => { "nc" => 2 }, "target" => { "nc" => 1 } }, evaluation["excluded_edges"])
      assert_equal({ "lsj" => 1, "mw" => 2 }, evaluation["excluded_by_dictionary"])
      assert_equal({ "resolved" => 2, "unresolved" => 1 }, evaluation["excluded_by_resolution"])
    end
  end

  def test_a_doubly_nc_edge_is_censused_once_under_its_source_role
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      # deva -> agni is nc on BOTH sides: one edge, counted under "source".
      excluded = evaluation["excluded_edges"].values.sum { |classes| classes.values.sum }
      assert_equal 3, excluded
    end
  end

  def test_citations_cover_the_published_endpoint_sources_only
    Dir.mktmpdir do |dir|
      assert_equal %w[hebrew-lexicon lexica], build!(dir).citations.map(&:key)
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)
      @catalog[:dictionary_crossrefs].where(dictionary_entry_id: @deva).update(label: "moved")
      @catalog[:dictionary_crossrefs].where(dictionary_entry_id: @mythos).update(label: "moved too")
      assert_equal first, build!(dir).recipe, "a screened edge never moves the published fingerprint"
      @catalog[:dictionary_crossrefs].where(label: "cf. λέγω").update(label: "cf. λέγω (2)")
      refute_equal first, build!(dir).recipe
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::DictionaryCrossrefsBuilder.new(registry: registry_rig).build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
