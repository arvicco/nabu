# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "csv"

# The mul/lect-assignments builder (P73-3): the per-document
# historical-stage journal published at URN grain — license-class slicing
# (nc/odbl/research_private/unknown out, censused in-band), deterministic
# order, basis and note riding every row, contributing corpora cited.
class LectAssignmentsBuilderTest < Minitest::Test
  include StoreTestDB

  ManifestRig = Data.define(:name, :upstream_url, :license)
  EntryRig = Data.define(:manifest)

  def registry_rig
    {
      "alpha" => EntryRig.new(manifest: ManifestRig.new(
        name: "Alpha Corpus", upstream_url: "https://alpha.example", license: "CC BY 4.0"
      )),
      # The slug ≠ URN-namespace case (the live papyri-ddbdp lesson): the
      # source slug is papy-sharey, but its documents mint urn:nabu:sharey:…
      "papy-sharey" => EntryRig.new(manifest: ManifestRig.new(
        name: "Sharey Corpus", upstream_url: "https://sharey.example", license: "CC BY-SA 4.0"
      ))
    }
  end

  def setup
    @catalog = store_test_db
    sources = { "alpha" => "attribution", "papy-sharey" => "attribution",
                "closed" => "nc", "runic" => "odbl" }.to_h do |slug, klass|
      [slug, Nabu::Store::Source.create(slug: slug, name: slug.capitalize,
                                        adapter_class: "TestAdapter", license_class: klass)]
    end
    { "urn:nabu:alpha:d1" => "alpha", "urn:nabu:alpha:d2" => "alpha",
      "urn:nabu:sharey:d1" => "papy-sharey", "urn:nabu:closed:d1" => "closed",
      "urn:nabu:runic:d1" => "runic" }.each do |urn, slug|
      Nabu::Store::Document.create(source_id: sources.fetch(slug).id, urn: urn,
                                   title: urn, language: "akk",
                                   content_sha256: "x", revision: 1)
    end
    @journal = Nabu::Store::LectJournal.migrate!(Nabu::Store::LectJournal.connect("sqlite::memory:"))
    [
      ["urn:nabu:alpha:d2", "akk", "akk:ob", "rule:akk-period", "Old Babylonian"],
      ["urn:nabu:alpha:d1", "akk", "akk:nb", "rule:akk-period", "Neo-Babylonian"],
      ["urn:nabu:sharey:d1", "lat", "lat:class", "rule:date-band", "Classical Latin"],
      ["urn:nabu:closed:d1", "akk", "akk:ob", "rule:akk-period", "held at nc"],
      ["urn:nabu:runic:d1", "non", "non:runic", "rule:date-band", "ODbL slice"],
      ["urn:nabu:ghost:d1", "akk", "akk:ob", "rule:akk-period", "no cataloged document"]
    ].each do |urn, code, lect_id, basis, note|
      @journal[:lect_assignments].insert(urn: urn, code: code, lect_id: lect_id,
                                         basis: basis, note: note, created_at: Time.now)
    end
  end

  def teardown = @journal.disconnect

  def build!(out_dir)
    Nabu::DataBuild::LectAssignmentsBuilder
      .new(lects_db: @journal, registry: registry_rig)
      .build(catalog: @catalog, out_dir: out_dir)
  end

  def test_publishes_only_open_and_attribution_rows_in_urn_order
    Dir.mktmpdir do |dir|
      result = build!(dir)
      table = CSV.read(File.join(dir, "assignments.csv"), headers: true)
      assert_equal %w[ID URN Language_ID Lect_ID Basis Comment Source], table.headers
      assert_equal %w[urn:nabu:alpha:d1 urn:nabu:alpha:d2 urn:nabu:sharey:d1],
                   table.map { |row| row["URN"] },
                   "publishable license classes only, ordered by (urn, code)"
      first = table.first
      assert_equal %w[akk akk:nb rule:akk-period Neo-Babylonian alpha],
                   first.values_at("Language_ID", "Lect_ID", "Basis", "Comment", "Source")
      assert_match Nabu::DataBuild::CsvWriter::ID_PATTERN, first["ID"]
      sharey = table.find { |row| row["URN"] == "urn:nabu:sharey:d1" }
      assert_equal "papy-sharey", sharey["Source"],
                   "Source is the CATALOG slug via documents.urn — never a URN prefix parse"
      assert_equal 3, result.resources.first.rows
    end
  end

  def test_the_exclusion_census_rides_in_band
    Dir.mktmpdir do |dir|
      evaluation = build!(dir).evaluation
      assert_equal 6, evaluation["journal_rows"]
      assert_equal 3, evaluation["published_rows"]
      assert_equal({ "nc" => 1, "odbl" => 1, "uncataloged" => 1 },
                   evaluation["excluded_rows"],
                   "every unpublished row is censused by its exclusion reason")
    end
  end

  def test_contributing_sources_and_the_id_grammar_are_cited
    Dir.mktmpdir do |dir|
      citations = build!(dir).citations
      keys = citations.map(&:key)
      assert_includes keys, "alpha"
      assert_includes keys, "papy-sharey"
      assert_includes keys, "nabu-lects", "the lect id grammar is cited to its public registry"
      refute_includes keys, "closed", "an excluded source contributes no rows, so it is not cited"
      sharey = citations.find { |citation| citation.key == "papy-sharey" }
      assert_equal "Sharey Corpus", sharey.fields["title"]
      assert_match(/CC BY-SA 4\.0/, sharey.fields["note"])
    end
  end

  def test_the_recipe_digest_tracks_the_published_slice
    Dir.mktmpdir do |dir|
      first = build!(dir).recipe
      assert_match(/sha256=\h{64}/, first)

      @journal[:lect_assignments].where(urn: "urn:nabu:alpha:d1").update(lect_id: "akk:ob")
      changed = build!(dir).recipe
      refute_equal first, changed, "a changed published row must change the recipe (and the fingerprint)"

      @journal[:lect_assignments].where(urn: "urn:nabu:closed:d1").update(lect_id: "akk:nb")
      assert_equal changed, build!(dir).recipe,
                   "an excluded row's change never moves the published slice"
    end
  end

  def test_refuses_without_a_catalog
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::DataBuild::Error) do
        Nabu::DataBuild::LectAssignmentsBuilder
          .new(lects_db: @journal, registry: registry_rig)
          .build(catalog: nil, out_dir: dir)
      end
      assert_match(/catalog/, error.message)
    end
  end
end
