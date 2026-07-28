# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# sources.bib (P50-W1): structured citations from the builder, keys citable
# from CSV Source columns (so they obey the CLDF identifier regex).
class DataBuildSourcesBibTest < Minitest::Test
  def render(citations)
    Dir.mktmpdir("nabu-bib") do |dir|
      path = Nabu::DataBuild::SourcesBib.write(dir: dir, citations: citations, slug: "san/test")
      assert_equal File.join(dir, "sources.bib"), path
      return File.read(path, encoding: Encoding::UTF_8)
    end
  end

  def test_renders_bibtex_entries_with_field_order_preserved
    bib = render([
                   Nabu::DataBuild::Citation.new(
                     key: "dcs", type: "misc",
                     fields: { "title" => "Digital Corpus of Sanskrit", "author" => "Hellwig, Oliver",
                               "url" => "http://www.sanskrit-linguistics.org/dcs/" }
                   )
                 ])
    assert_match(/^@misc\{dcs,$/, bib)
    title_at = bib.index("title = {Digital Corpus of Sanskrit}")
    author_at = bib.index("author = {Hellwig, Oliver}")
    refute_nil title_at
    refute_nil author_at
    assert_operator title_at, :<, author_at, "field order is the citation's own order"
    assert_match(/^\}$/, bib)
  end

  def test_an_empty_citation_list_still_ships_the_file_honestly
    bib = render([])
    assert_match(%r{san/test}, bib, "the header comment names the dataset")
    refute_match(/@/, bib)
  end

  def test_citation_keys_obey_the_cldf_identifier_regex
    error = assert_raises(Nabu::ValidationError) do
      Nabu::DataBuild::Citation.new(key: "no spaces", type: "misc", fields: { "title" => "x" })
    end
    assert_match(/no spaces/, error.message)
  end

  def test_resource_entry_is_non_tabular
    resource = Nabu::DataBuild::SourcesBib.resource
    assert_equal "sources.bib", resource.path
    assert_nil resource.fields
    assert_equal "bibtex", resource.format
    assert_equal "text/x-bibtex", resource.mediatype
  end
end
