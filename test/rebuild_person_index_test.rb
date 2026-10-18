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
end
