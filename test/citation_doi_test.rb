# frozen_string_literal: true

require "test_helper"
require "yaml"

# The README's DOI badge cites the CONCEPT DOI (the all-versions record,
# which always resolves to the latest release) — the same DOI CITATION.cff
# declares. A version DOI there would pin readers to one old release.
class CitationDoiTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def concept_doi = YAML.safe_load_file(File.join(ROOT, "CITATION.cff")).fetch("doi")

  def test_readme_doi_badge_cites_the_concept_doi
    readme = File.read(File.join(ROOT, "README.md"))
    badge = readme[%r{\[!\[DOI\]\([^)]*\)\]\(https://doi\.org/([^)]+)\)}, 1]
    refute_nil badge, "README carries a DOI badge linking doi.org"
    assert_equal concept_doi, badge, "the README DOI badge links the concept DOI from CITATION.cff"
    assert_includes readme[/\[!\[DOI\]\([^)]*\)/], concept_doi.sub("/", "%2F"),
                    "the badge image text names the concept DOI too"
  end
end
