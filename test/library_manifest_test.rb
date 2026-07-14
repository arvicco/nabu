# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LibraryManifest (P19-4): one collection's manifest.yml — the shelf's
# source of record. The research_private DEFAULT is applied here (and only
# here); explicit classes are honored; structural defects fail loudly.
class LibraryManifestTest < Minitest::Test
  FIXTURE = File.join(Nabu::TestSupport.fixtures("local-library"), "shelf", "slavistics", "manifest.yml")

  def load_fixture = Nabu::LibraryManifest.load(FIXTURE)

  def with_manifest(yaml)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "manifest.yml")
      File.write(path, yaml)
      yield path
    end
  end

  def test_loads_the_fixture_collection_in_manifest_order
    entries = load_fixture.entries
    assert_equal %w[leskien-1871-handbuch.pdf jagic-notes.txt scan-plate.pdf codex-plate.png missing-notes.txt],
                 entries.map(&:file)
  end

  def test_license_class_defaults_to_research_private_when_silent
    leskien = load_fixture.entries.first
    assert_equal "research_private", leskien.license_class,
                 "silence must mean the conservative class — the shelf's whole licensing point"
  end

  def test_an_explicit_open_entry_is_honored
    jagic = load_fixture.entries.find { |entry| entry.file == "jagic-notes.txt" }
    assert_equal "open", jagic.license_class
  end

  def test_entry_fields_round_trip_from_yaml
    leskien = load_fixture.entries.first
    assert_equal "Handbuch der altbulgarischen (altkirchenslavischen) Sprache", leskien.title
    assert_equal "A. Leskien", leskien.creator
    assert_equal 1871, leskien.year
    assert_equal %w[deu], leskien.languages
    assert_equal %w[grammar ocs], leskien.tags
    assert_equal ["urn:nabu:local-library:slavistics:jagic-notes", "chu"], leskien.related
    assert_match(/public domain/, leskien.provenance)
  end

  def test_title_defaults_to_the_file_stem
    with_manifest("- file: untitled-scan.pdf\n") do |path|
      entry = Nabu::LibraryManifest.load(path).entries.first
      assert_equal "untitled-scan", entry.title
      assert_empty entry.languages
      assert_empty entry.related
      assert_nil entry.year
    end
  end

  def test_source_url_lane_parses_and_is_nil_when_absent
    with_manifest("- file: a.pdf\n  source_url: https://archive.org/download/x/a.pdf\n") do |path|
      entry = Nabu::LibraryManifest.load(path).entries.first
      assert_equal "https://archive.org/download/x/a.pdf", entry.source_url
    end
    with_manifest("- file: a.pdf\n") do |path|
      assert_nil Nabu::LibraryManifest.load(path).entries.first.source_url,
                 "local ingests carry no source_url lane"
    end
  end

  # P20-1 (the 2026-07-14 "chu (body ger)" incident): language tags are
  # validated at PARSE with the model's own rule — a hand-edited bad tag
  # fails early and named, never deep in the loader scan.
  def test_a_bad_language_tag_fails_at_parse_naming_file_and_entry
    with_manifest("- file: a.pdf\n- file: b.pdf\n  languages: [\"chu (body ger)\"]\n") do |path|
      error = assert_raises(Nabu::LibraryManifest::FormatError) { Nabu::LibraryManifest.load(path) }
      assert_match(/entry 2 \(b\.pdf\)/, error.message, "per-entry defects name the entry")
      assert_includes error.message, path, "…and the file"
      assert_match(%r{BCP-47/ISO-639}, error.message, "the model's rule, reused verbatim")
      assert_match(/chu \(body ger\)/, error.message)
    end
  end

  def test_good_language_tags_including_the_subtag_form_pass
    with_manifest("- file: a.pdf\n  languages: [chu, grc-Grek, deu]\n") do |path|
      assert_equal %w[chu grc-Grek deu], Nabu::LibraryManifest.load(path).entries.first.languages
    end
  end

  def test_unknown_license_class_fails_loudly_never_defaults_down
    with_manifest("- file: a.pdf\n  license_class: public\n") do |path|
      error = assert_raises(Nabu::LibraryManifest::FormatError) { Nabu::LibraryManifest.load(path) }
      assert_match(/license_class/, error.message)
      assert_match(/a\.pdf/, error.message)
    end
  end

  def test_structural_defects_raise_format_error
    ["file: not-a-list\n", "[]\n", "- just a string\n", "- title: no file key\n",
     "- file: ../escape.pdf\n", "- file: a.pdf\n  year: \"1871\"\n",
     "- file: a.pdf\n  related: chu\n", "- {file: a.pdf}\n- {file: a.pdf}\n",
     "- file: a.pdf\n  source_url: 42\n"].each do |yaml|
      with_manifest(yaml) do |path|
        assert_raises(Nabu::LibraryManifest::FormatError, "expected FormatError for #{yaml.inspect}") do
          Nabu::LibraryManifest.load(path)
        end
      end
    end
  end

  def test_unparseable_yaml_raises_format_error_naming_the_file
    with_manifest("- file: [unclosed\n") do |path|
      error = assert_raises(Nabu::LibraryManifest::FormatError) { Nabu::LibraryManifest.load(path) }
      assert_match(/unparseable YAML/, error.message)
    end
  end
end
