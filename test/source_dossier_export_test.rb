# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::SourceDossierExport (P24-0): the owner-fired seed — a dossier for
# EVERY registered source, descriptions from the best EXISTING prose
# (docs/library.md sections and bullets, sources.yml standalone comments),
# honest stubs where none exists, idempotent at the file grain, dry-run
# honest.
class SourceDossierExportTest < Minitest::Test
  LIBRARY_MD = <<~MD
    # The Library — content review

    Header prose that belongs to no shelf.

    ## 1. Latin inscriptions (EDH)

    | | |
    |---|---|
    | **Category** | Epitaphs and dedications |
    | **Source** | `edh` (Epigraphic Database Heidelberg), license: `attribution` |

    The third documentary genre: epitaphs, dedications and milestones from
    the whole empire. The largest shelf by documents. Facets make the
    epigraphic habit queryable. A fourth sentence that must be capped away.

    **Research uses:** epigraphy proper; onomastics.

    ## 2. The etymological witnesses

    The three adapters were synced live:

    - **`iecor`** — IE-CoR: the expert-curated Indo-European cognacy matrix
      as a dictionary shelf. An independent third etymological witness.
    - **`liv`** — LIV-LOD: 305 PIE verbal etymons.

    ## 3. Shared shelf (two sources)

    | | |
    |---|---|
    | **Source** | `perseus-greek` + `first1k-greek`, license: `attribution` |

    The Greek canon and its long tail, one parser family.
  MD

  SOURCES_YML = <<~YAML
    edh:
      adapter: Nabu::Adapters::Edh
      enabled: true
      sync_policy: frozen

    iecor:
      adapter: Nabu::Adapters::Iecor
      enabled: true    # inline flag comment — a process note, never prose
      sync_policy: manual

    sl-lexica:
      adapter: Nabu::Adapters::SlLexica
      enabled: false
      # The Slovenian historical dictionary shelf (ZRC SAZU / CLARIN.SI).
      # The deposits are frozen uploads: re-fetch is an owner decision.
      sync_policy: manual
      # license_watch: https://example.org/record

    bare:
      adapter: Nabu::Adapters::Edh
      enabled: false
      sync_policy: manual
  YAML

  def with_rig
    Dir.mktmpdir do |dir|
      library = File.join(dir, "library.md")
      File.write(library, LIBRARY_MD)
      yml = File.join(dir, "sources.yml")
      File.write(yml, SOURCES_YML)
      yield dir, library, yml
    end
  end

  FakeRegistry = Struct.new(:slugs)

  def export(dir, library:, yml:, slugs: %w[edh iecor sl-lexica bare], dry_run: false)
    Nabu::SourceDossierExport.new(
      registry: FakeRegistry.new(slugs), dir: File.join(dir, "shelf"),
      library_md: library, sources_yml: yml, now: Time.new(2026, 7, 16)
    ).run!(dry_run: dry_run)
  end

  def test_seeds_every_registered_source_from_the_best_existing_prose
    with_rig do |dir, library, yml|
      report = export(dir, library: library, yml: yml)
      assert_equal 4, report.written
      assert_equal 1, report.stubs
      assert_equal %w[bare], report.stub_slugs
      shelf = Nabu::SourceShelf.new(dir: File.join(dir, "shelf"))

      edh = shelf.load("edh")
      assert_match(/\AThe third documentary genre/, edh.description, "section prose seeds the description")
      refute_match(/capped away/, edh.description, "descriptions cap at three sentences")
      assert_match(%r{docs/library\.md}, edh.provenance.fetch("seeded_from"))

      iecor = shelf.load("iecor")
      assert_match(/cognacy matrix/, iecor.description, "a slug-specific bullet wins")
      refute_match(/inline flag comment/, iecor.description.to_s, "inline comments are never prose")

      sl = shelf.load("sl-lexica")
      assert_match(/\AThe Slovenian historical dictionary shelf/, sl.description,
                   "sources.yml standalone comments fill the library.md gap")
      refute_match(/license_watch/, sl.description)

      bare = shelf.load("bare")
      assert_nil bare.description, "no prose exists — the stub never invents"
      assert_match(/honest stub/, bare.provenance.fetch("seeded_from"))
    end
  end

  def test_a_multi_source_section_seeds_each_of_its_slugs
    with_rig do |dir, library, yml|
      export(dir, library: library, yml: yml, slugs: %w[perseus-greek first1k-greek])
      shelf = Nabu::SourceShelf.new(dir: File.join(dir, "shelf"))
      assert_match(/Greek canon/, shelf.load("perseus-greek").description)
      assert_match(/Greek canon/, shelf.load("first1k-greek").description)
    end
  end

  def test_export_is_idempotent_and_never_touches_an_existing_dossier
    with_rig do |dir, library, yml|
      shelf = Nabu::SourceShelf.new(dir: File.join(dir, "shelf"))
      shelf.write!(Nabu::SourceDossier.new(slug: "edh", description: "Owner-edited description."))
      report = export(dir, library: library, yml: yml)
      assert_equal 3, report.written
      assert_equal 1, report.unchanged
      assert_equal "Owner-edited description.", shelf.load("edh").description, "existing dossier = no-op"

      again = export(dir, library: library, yml: yml)
      assert_equal 0, again.written
      assert_equal 4, again.unchanged
    end
  end

  def test_dry_run_reports_without_writing
    with_rig do |dir, library, yml|
      report = export(dir, library: library, yml: yml, dry_run: true)
      assert_equal 4, report.written
      refute Dir.exist?(File.join(dir, "shelf")), "dry-run touches nothing"
    end
  end

  def test_degrades_without_library_or_yml
    Dir.mktmpdir do |dir|
      report = Nabu::SourceDossierExport.new(
        registry: FakeRegistry.new(%w[edh]), dir: File.join(dir, "shelf"), now: Time.new(2026, 7, 16)
      ).run!
      assert_equal 1, report.written
      assert_equal 1, report.stubs
    end
  end
end
