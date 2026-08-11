# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "tmpdir"

# Nabu::PlaceDossiers (P64-4, ruling Dp-e): owner-authored place essays
# under canonical/local-place/, matched to desk cards by namespaced refs.
# v1 reads files at desk time — no catalog table, no scaffolder (dossiers
# are authored, never seeded; the Q3 discipline).
class PlaceDossiersTest < Minitest::Test
  BODY = <<~MD
    ---
    key: girsu
    title: Girsu
    refs: [pleiades:912855, cigs:GIR, "tm:2810"]
    ---
    The sacred city of Ningirsu.
  MD

  # P71-2: all/for_ids take the SHELF dir itself (Config#source_workdir
  # resolves it — local/shelves/local-place).
  def with_shelf
    Dir.mktmpdir do |dir|
      shelf = File.join(dir, "local-place")
      FileUtils.mkdir_p(shelf)
      File.write(File.join(shelf, "girsu.md"), BODY)
      yield shelf
    end
  end

  def test_a_dossier_parses_with_refs_and_body
    with_shelf do |dir|
      d = Nabu::PlaceDossiers.all(dir).first
      assert_equal "girsu", d.key
      assert_equal %w[pleiades:912855 cigs:GIR tm:2810], d.refs
      assert_includes d.body, "Ningirsu"
    end
  end

  def test_for_ids_matches_any_intersecting_ref
    with_shelf do |dir|
      assert_equal 1, Nabu::PlaceDossiers.for_ids(dir, [%w[pleiades 912855]]).size
      assert_equal 1, Nabu::PlaceDossiers.for_ids(dir, [%w[cigs GIR], %w[pleiades 999]]).size
      assert_empty Nabu::PlaceDossiers.for_ids(dir, [%w[pleiades 999]])
    end
  end

  def test_absent_shelf_is_empty_and_malformed_files_raise_loudly
    Dir.mktmpdir do |dir|
      shelf = File.join(dir, "local-place")
      assert_empty Nabu::PlaceDossiers.all(shelf)
      FileUtils.mkdir_p(shelf)
      File.write(File.join(shelf, "bad.md"), "no front matter\n")
      error = assert_raises(Nabu::Error) { Nabu::PlaceDossiers.all(shelf) }
      assert_match(/front-matter/, error.message)
    end
  end

  def test_refless_front_matter_is_refused
    Dir.mktmpdir do |dir|
      shelf = File.join(dir, "local-place")
      FileUtils.mkdir_p(shelf)
      File.write(File.join(shelf, "x.md"), "---\nkey: x\n---\nbody\n")
      assert_raises(Nabu::Error) { Nabu::PlaceDossiers.all(shelf) }
    end
  end

  def test_the_desk_card_carries_matching_dossiers
    db = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(db)
    with_shelf do |dir|
      result = Nabu::Query::Place.new(catalog: db, pleiades: nil, place_shelf_dir: dir)
                                 .run("912855")
      assert_equal ["Girsu"], result.cards.first.dossiers.map(&:title)
    end
  ensure
    db&.disconnect
  end
end
