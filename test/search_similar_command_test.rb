# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# `nabu search --similar URN`: the semantic-neighbors lane's argument
# contract, mirroring the MCP similar_to ruling — --lang is HONORED (the
# anchor's own language pins the subpool; any other is refused by
# Query::Similar, never widened), --limit and the display mode ride, and
# every other filter option is REFUSED by name rather than silently
# dropped. The refusals fire before any store is opened; the --lang half
# reaches Query::Similar's same-language check, which needs no sqlite-vec
# extension.
class SearchSimilarCommandTest < Minitest::Test
  ANCHOR = "urn:d:1:a"

  def test_lang_is_honored_on_the_similar_lane
    with_vector_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["search", "--similar", ANCHOR, "--lang", "lat"]) }
      assert_equal 1, status
      assert_match(/same-language only/, err, "--lang reaches the lane (a mismatch is refused, never dropped)")
      assert_match(/grc/, err)
    end
  end

  def test_every_other_filter_option_is_refused_by_name
    [%w[--license open], %w[--source lit], %w[--from -300], %w[--century 4], %w[--kind literary],
     %w[--facet genre=x], %w[--place Athens], %w[--lect grc], %w[--script Grek], %w[--axis x],
     %w[--meter hex], %w[--gold-only]].each do |flag|
      _out, err, status = run_cli(["search", "--similar", ANCHOR, *flag])
      assert_equal 1, status, flag.first
      assert_match(%r{--similar composes with --lang/--limit only \(not #{Regexp.escape(flag.first)}\)}, err,
                   flag.first)
    end
  end

  def test_a_search_term_and_mode_flags_are_refused_together
    _out, err, status = run_cli(["search", "brothers", "--similar", ANCHOR, "--license", "open", "--fuzzy"])
    assert_equal 1, status
    assert_match(/the urn IS the query/, err)
    assert_match(/\(not a search term, /, err, "the term is named first")
    %w[--license --fuzzy].each { |flag| assert_match(/\(not [^)]*#{flag}/, err, "every conflict is named: #{flag}") }
  end

  private

  def with_vector_corpus
    Dir.mktmpdir("nabu-similar-desk") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: File.join(root, "config", "nabu.yml")
      )
      File.write(config.sources_path, "# none\n")
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      vectors = Nabu::Store.connect(config.vectors_path)
      Nabu::Embed.ensure_schema!(vectors)
      vectors[Nabu::Embed::META_TABLE].insert(model: Nabu::Embed::MODEL, dim: 4, encoding: "i8",
                                              worker_version: "test", updated_at: Time.now.utc.iso8601)
      vectors[Nabu::Embed::VECTORS_TABLE].insert(model: Nabu::Embed::MODEL, urn: ANCHOR, language: "grc",
                                                 text_sha: "sha", vec: Sequel.blob([127, 0, 0, 0].pack("c*")))
      vectors.disconnect
      catalog.disconnect
      yield config
    end
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
