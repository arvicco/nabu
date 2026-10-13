# frozen_string_literal: true

require "test_helper"

# The source-dossier coverage guard (owner-ruled 2026-10-13, after 92
# descriptionless sources accumulated unseen): on a box carrying the
# local-source shelf, the suite itself runs the dossier-drift check that
# `rake site:check` runs at gates — a registered source without a
# written dossier description, a placeholder left unwritten, or a
# described live source the public map (docs/library.md) never mentions
# is a FAILURE here, not a lapse to notice months later. Public clones
# carry no local/ shelf and skip (the StrictSkips rationale: on this
# box, a skip would be missing coverage; elsewhere it is honest).
class SourceDossierCoverageTest < Minitest::Test
  def test_every_registered_source_carries_a_written_dossier_and_rides_the_map
    config = Nabu::Config.load
    shelf_dir = Nabu::SourceShelf.dir(config)
    skip "local-source shelf absent (public clone)" unless Dir.exist?(shelf_dir)

    findings = Nabu::Ops::DossierDrift.new(
      shelf_dir: shelf_dir,
      registry: Nabu::SourceRegistry.load(config.sources_path),
      library_md: File.expand_path("../docs/library.md", __dir__),
      site_library_md: File.expand_path("../site/library.md", __dir__)
    ).findings
    assert_empty findings.map { |f| "#{f.slug}: #{f.message}" },
                 "dossier drift — every registered source needs its written description " \
                 "(nabu list --export-source-dossiers scaffolds; the shelf file carries the prose) " \
                 "and every described live source belongs on docs/library.md"
  end
end
