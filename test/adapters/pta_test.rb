# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# PTA — the Patristic Text Archive (BBAW) adapter tests (P154). The repo is
# CapiTainS/EpiDoc (the Perseus layout), so the adapter subclasses Perseus;
# what it adds is the per-document licence law, the grain rules (Greek
# editions only — manuscript transcriptions, biblical-excerpt files, other
# languages and the Bible textgroup's held/encumbered editions skip by rule),
# the critical-apparatus policy and the __cts__.xml dct:* mining. Fixtures:
# trimmed real files, test/fixtures/pta/README.md.
class PtaTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("pta")

  PAENITENTIA = "urn:cts:pta:pta0001.pta002.pta-grc1"   # CC BY-SA 4.0
  CAINI_CRIT = "urn:cts:pta:pta0001.pta024.pta-grc1"    # CC BY 4.0, Uthemann 1994
  CAINI_SAVILE = "urn:cts:pta:pta0001.pta024.pta-grc2"  # CC BY 4.0, Savile 1612
  NOE = "urn:cts:pta:pta0001.pta036.pta-grc1"           # CC BY 4.0, apparatus
  CYZICENUS = "urn:cts:pta:pta0036.pta001.pta-grc1"     # CC BY-NC-SA 3.0
  ARIUS_DOK = "urn:cts:pta:pta0100.pta001.pta-grc1"     # CC BY 4.0, unfilled metadata
  ACCEPTED = [PAENITENTIA, CAINI_CRIT, CAINI_SAVILE, NOE, CYZICENUS, ARIUS_DOK].freeze

  def conformance_adapter
    Nabu::Adapters::Pta.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "pta"
  end

  def adapter
    @adapter ||= Nabu::Adapters::Pta.new
  end

  def refs
    @refs ||= adapter.discover(FIXTURES).to_h { |ref| [ref.id, ref] }
  end

  def parsed(urn)
    adapter.parse(refs.fetch(urn))
  end

  # --- manifest ---------------------------------------------------------------

  def test_manifest
    manifest = Nabu::Adapters::Pta.manifest

    assert_equal "pta", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "https://github.com/PatristicTextArchive/pta_data", manifest.upstream_url
    assert_equal "epidoc", manifest.parser_family
    assert_equal manifest, adapter.manifest
  end

  # --- discovery: every Greek edition, the grains skipped by rule -----------------

  def test_discover_takes_every_greek_edition_including_both_editions_of_one_work
    assert_equal ACCEPTED.sort, refs.keys
    assert(refs.values.all? { |ref| ref.metadata["language"] == "grc" })
  end

  def test_discovery_skips_count_every_rejected_grain_by_rule
    skips = adapter.discovery_skips(FIXTURES)

    assert_predicate skips, :clean?
    assert_equal 7, skips.skipped_by_rule
    notes = skips.notes.join("\n")

    assert_match(/1 unlicensed file.*pta0001\.pta025\.pta-MsKa/, notes)
    assert_match(/1 manuscript transcription/, notes)
    assert_match(/1 biblical-excerpt file/, notes)
    assert_match(/2 editions in other languages \(deu 1, syc 1\)/, notes)
    assert_match(/1 Rahlfs Septuagint edition.*pta9999\.pta001\.pta-grc1/, notes)
    assert_match(/1 SBL Greek New Testament edition.*pta9999\.pta063\.pta-grc1/, notes)
    assert_match(%r{analyzed/ tree: 1 automatically tokenized twin}, notes)
  end

  # --- the per-document licence law ---------------------------------------------

  def test_each_document_carries_its_own_licence
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", refs[PAENITENTIA].metadata["license"]
    assert_equal "https://creativecommons.org/licenses/by/4.0/", refs[CAINI_CRIT].metadata["license"]
    assert_equal "https://creativecommons.org/licenses/by-nc-sa/3.0/deed.de", refs[CYZICENUS].metadata["license"]
  end

  def test_attribution_licences_ride_the_source_class_and_nc_overrides
    assert_nil parsed(PAENITENTIA).license_override
    assert_nil parsed(CAINI_CRIT).license_override
    assert_equal "nc", parsed(CYZICENUS).license_override
  end

  def test_licence_classes_cover_every_target_upstream_ships
    law = Nabu::Adapters::Pta::LICENCE_CLASSES

    assert_equal "attribution", law.fetch("https://creativecommons.org/licenses/by-sa/4.0/")
    assert_equal "attribution", law.fetch("https://creativecommons.org/licenses/by/4.0/")
    assert_equal "nc", law.fetch("https://creativecommons.org/licenses/by-nc/4.0/")
    assert_equal "nc", law.fetch("https://creativecommons.org/licenses/by-nc/3.0/de/")
    assert_equal "nc", law.fetch("https://creativecommons.org/licenses/by-nc-sa/3.0/")
    assert_equal "nc", law.fetch("https://creativecommons.org/licenses/by-nc-sa/3.0/deed.de")
  end

  def test_an_unknown_licence_on_a_greek_edition_stops_discovery_loudly
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, "data"), dir)
      path = File.join(dir, "data/pta0001/pta002/pta0001.pta002.pta-grc1.xml")
      File.write(path, File.read(path).sub("licenses/by-sa/4.0/", "licenses/by-nd/4.0/"))

      error = assert_raises(Nabu::FetchError) { Nabu::Adapters::Pta.new.discover(dir).to_a }
      assert_includes error.message, "by-nd/4.0"
    end
  end

  # --- parsing ----------------------------------------------------------------------

  def test_sections_are_the_citation_units
    doc = parsed(PAENITENTIA)

    assert_equal %W[#{PAENITENTIA}:1 #{PAENITENTIA}:2], doc.passages.map(&:urn)
    assert_equal "De paenitentia et compunctione", doc.title
    assert doc.passages.first.text.start_with?("Πάντοτε μὲν ὁ θεῖος ἀπόστολος")
  end

  def test_the_critical_apparatus_leaves_the_text
    text = parsed(NOE).passages.first.text

    assert_includes text, "Τοῦτο γὰρ καὶ ὁ λόγος ὑμῖν ἐπαγγέλλεται"
    refute_includes text, "παραλείπωμεν"
  end
end
