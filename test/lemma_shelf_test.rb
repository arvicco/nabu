# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"

# The local-lemmas shelf's sanctioned write gateway (P84-1, architecture
# §16) — the FIFTH local-shelf gateway, NoteShelf/LanguageShelf's sibling
# at machine grain: the silver-lemma enricher's model output is
# NON-DERIVABLE (hours of compute), so it lands as append-only JSONL
# shards under local/shelves/local-lemmas/<language>/, written
# tmp+validate+rename, with a campaign state checkpoint (the
# corpus-corporum two-grain mold) so a crash at hour 3 loses at most one
# unflushed batch. Everything else — indexer, census — stays read-only.
class LemmaShelfTest < Minitest::Test
  def with_shelf
    Dir.mktmpdir("nabu-lemma-shelf") do |root|
      yield Nabu::LemmaShelf.new(dir: File.join(root, "local-lemmas"))
    end
  end

  def record(urn: "urn:nabu:edr:edr000001:t", tokens: [%w[Aureliae Aurelia PROPN]])
    Nabu::LemmaShelf::Record.new(
      urn: urn, language: "lat", source: "edr",
      model: "stanza", model_version: "1.14.0", package: "la:default(ittb)",
      tokens: tokens, generated_at: "2026-08-27T00:00:00Z"
    )
  end

  def test_append_batch_writes_a_numbered_shard_readable_back
    with_shelf do |shelf|
      path = shelf.append_batch!(language: "lat", records: [record])
      assert_equal File.join(shelf.dir, "lat", "shard-000001.jsonl"), path
      refute_path_exists "#{path}.tmp", "the tmp staging file is renamed away"

      records = []
      shelf.each_record(language: "lat") { |r| records << r }
      assert_equal 1, records.size
      r = records.first
      assert_equal "urn:nabu:edr:edr000001:t", r.urn
      assert_equal "lat", r.language
      assert_equal "edr", r.source
      assert_equal "stanza", r.model
      assert_equal "1.14.0", r.model_version
      assert_equal [%w[Aureliae Aurelia PROPN]], r.tokens
    end
  end

  def test_shard_numbering_continues_from_the_existing_maximum
    with_shelf do |shelf|
      shelf.append_batch!(language: "lat", records: [record])
      second = shelf.append_batch!(language: "lat", records: [record(urn: "urn:nabu:edr:edr000002:t")])
      assert_equal "shard-000002.jsonl", File.basename(second)
    end
  end

  def test_append_batch_refuses_an_invalid_record_writing_nothing
    with_shelf do |shelf|
      error = assert_raises(Nabu::LemmaShelf::Error) do
        shelf.append_batch!(language: "lat", records: [record(urn: "  ")])
      end
      assert_match(/urn/, error.message)
      assert_empty Dir[File.join(shelf.dir, "**", "*")], "a refusal writes nothing"
    end
  end

  def test_append_batch_refuses_a_language_mismatch
    with_shelf do |shelf|
      error = assert_raises(Nabu::LemmaShelf::Error) do
        shelf.append_batch!(language: "grc", records: [record])
      end
      assert_match(/language/, error.message)
    end
  end

  def test_append_batch_refuses_empty_batches_and_tokenless_records
    with_shelf do |shelf|
      assert_raises(Nabu::LemmaShelf::Error) { shelf.append_batch!(language: "lat", records: []) }
      error = assert_raises(Nabu::LemmaShelf::Error) do
        shelf.append_batch!(language: "lat", records: [record(tokens: [])])
      end
      assert_match(/token/, error.message)
    end
  end

  def test_each_record_raises_format_error_naming_the_malformed_line
    with_shelf do |shelf|
      shelf.append_batch!(language: "lat", records: [record])
      shard = File.join(shelf.dir, "lat", "shard-000001.jsonl")
      File.write(shard, "#{File.read(shard)}not json\n")
      error = assert_raises(Nabu::LemmaShelf::FormatError) do
        shelf.each_record(language: "lat") { |r| r }
      end
      assert_match(/shard-000001\.jsonl:2/, error.message)
    end
  end

  def test_urns_returns_the_covered_set_across_shards
    with_shelf do |shelf|
      shelf.append_batch!(language: "lat", records: [record])
      shelf.append_batch!(language: "lat", records: [record(urn: "urn:nabu:edr:edr000002:t")])
      assert_equal %w[urn:nabu:edr:edr000001:t urn:nabu:edr:edr000002:t].to_set,
                   shelf.urns(language: "lat")
      assert_empty shelf.urns(language: "grc"), "an absent language lane is an empty set"
    end
  end

  def test_state_checkpoint_round_trips_and_survives_partial_writes
    with_shelf do |shelf|
      assert_nil shelf.state(language: "lat"), "no campaign yet — no state"
      shelf.write_state!(language: "lat", payload: { "checkpoint_passage_id" => 42, "campaign" => "2026-08-27" })
      state = shelf.state(language: "lat")
      assert_equal 42, state["checkpoint_passage_id"]
      refute_path_exists File.join(shelf.dir, "lat", "#{Nabu::LemmaShelf::STATE_FILE}.tmp")
    end
  end

  def test_languages_lists_the_shelved_lanes
    with_shelf do |shelf|
      assert_empty shelf.languages, "an empty shelf has no lanes"
      shelf.append_batch!(language: "lat", records: [record])
      assert_equal %w[lat], shelf.languages
    end
  end

  def test_record_from_h_round_trips_through_json
    r = record
    json = JSON.generate(r.to_h)
    assert_equal r, Nabu::LemmaShelf::Record.from_h(JSON.parse(json))
  end
end
