# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# The person-index replay (Rebuild#replay_person_index): an incremental
# run skips a clean producer only when ITS OWN authority slice is already
# populated — another authority's slice says nothing about it (cbdb being
# derived must not strand an empty elephantine slice).
class RebuildPersonIndexTest < Minitest::Test
  include StoreTestDB

  Entry = Struct.new(:slug, :adapter_class)
  Registry = Struct.new(:sources) do
    def each_source(&) = sources.each(&)
  end
  Config = Struct.new(:root) do
    def source_workdir(slug) = File.join(root, slug)
  end

  def setup
    @catalog = store_test_db
    @root = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@root, "elephantine"))
    FileUtils.cp(File.join(Nabu::TestSupport.fixtures("elephantine"), "elephantine_erc_db_ancient_persons.tei.xml"),
                 File.join(@root, "elephantine"))
    Nabu::Store::PersonIndex.derive!(@catalog, authority: "cbdb", persons: [
                                       Nabu::Store::PersonIndex::Person.new(
                                         authority: "cbdb", person_id: "1", name: "x", name_han: nil,
                                         birth_year: nil, death_year: nil, index_year: nil, dynasty: nil,
                                         dynasty_han: nil, female: false, name_keys: ["x"]
                                       )
                                     ])
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_a_clean_producer_with_an_empty_slice_still_derives
    registry = Registry.new([Entry.new("elephantine", Nabu::Adapters::Elephantine)])
    rebuild = Nabu::Rebuild.new(config: Config.new(@root), registry: registry)
    rebuild.send(:replay_person_index, @catalog, dirty: [])
    assert Nabu::Store::PersonIndex.populated?(@catalog, authority: "elephantine"),
           "the cbdb slice must not stand in for the elephantine one"
  end

  # The pna producer resolves its links against the HELD oracc/cdli
  # documents, so a dirty oracc must re-derive a clean pna slice — else an
  # incremental run would keep links a full rebuild would re-resolve.
  def test_a_clean_producer_re_derives_when_a_source_it_reads_is_dirty
    FileUtils.mkdir_p(File.join(@root, "pna"))
    PnaFixtureZips.pack!(Nabu::TestSupport.fixtures("pna"), File.join(@root, "pna"))
    stale = Nabu::Store::PersonIndex::Person.new(
      authority: "pna", person_id: "stale_1", name: "stale", name_han: nil, birth_year: nil, death_year: nil,
      index_year: nil, dynasty: nil, dynasty_han: nil, female: false, name_keys: []
    )
    Nabu::Store::PersonIndex.derive!(@catalog, authority: "pna", persons: [stale])
    registry = Registry.new([Entry.new("pna", Nabu::Adapters::Pna)])
    rebuild = Nabu::Rebuild.new(config: Config.new(@root), registry: registry)

    rebuild.send(:replay_person_index, @catalog, dirty: ["dprr"])
    assert_equal 1, Nabu::Store::PersonIndex.resolver(@catalog, authority: "pna").size,
                 "an unrelated dirty source leaves the populated slice alone"

    rebuild.send(:replay_person_index, @catalog, dirty: ["oracc"])
    assert_equal 8, Nabu::Store::PersonIndex.resolver(@catalog, authority: "pna").size
  end
end
