# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Store::ArtifactScripts (P61-3, D60-b): the artifact-script lane —
# config rows compiled into document_axes under the dedicated
# "artifact-script" axis_source, minted only where the artifact's script
# differs from the held surface (which is what earns a code its config
# row). Wholesale supersede; other lanes untouched; registry-validated.
class ArtifactScriptsTest < Minitest::Test
  FIXTURES = Nabu::TestSupport.fixtures("nabu-lects")

  def registry
    @registry ||= Nabu::Lects.load(FIXTURES)
  end

  def with_catalog
    catalog = Nabu::Store.connect("sqlite::memory:")
    Nabu::Store.migrate!(catalog)
    src = catalog[:sources].insert(slug: "eleph", name: "E", adapter_class: "X", license_class: "open")
    demotic = catalog[:documents].insert(source_id: src, urn: "u:demotic", language: "egy-Egyd",
                                         content_sha256: "x")
    bare = catalog[:documents].insert(source_id: src, urn: "u:bare", language: "egy", content_sha256: "x")
    catalog[:document_axes].insert(document_id: demotic, not_before: -300, not_after: -200,
                                   axis_source: "eleph")
    yield catalog, demotic, bare
  ensure
    catalog&.disconnect
  end

  def config_file(dir, body)
    path = File.join(dir, "artifact_scripts.yml")
    File.write(path, body)
    path
  end

  def test_derives_the_lane_only_for_configured_codes_and_leaves_other_lanes_alone
    with_catalog do |catalog, demotic, bare|
      Dir.mktmpdir do |dir|
        path = config_file(dir, <<~YAML)
          sources:
            eleph:
              egy-Egyd:
                script: egyd
                note: Demotic original
        YAML
        report = Nabu::Store::ArtifactScripts.derive!(catalog, config_path: path, registry: registry)
        assert_equal 1, report.minted

        row = Nabu::Store::ArtifactScripts.for_document(catalog, demotic)
        assert_equal "egyd", row[:artifact_script]
        assert_equal "Demotic original", row[:artifact_script_note]
        assert_nil Nabu::Store::ArtifactScripts.for_document(catalog, bare),
                   "an unconfigured code mints nothing — the lane exists on difference only"
        assert_equal 1, catalog[:document_axes].exclude(axis_source: "artifact-script").count,
                     "the dating lane's row is untouched"
      end
    end
  end

  def test_rederive_supersedes_wholesale_and_is_idempotent
    with_catalog do |catalog, _demotic, _bare|
      Dir.mktmpdir do |dir|
        path = config_file(dir, "sources:\n  eleph:\n    egy-Egyd: {script: egyd}\n")
        2.times { Nabu::Store::ArtifactScripts.derive!(catalog, config_path: path, registry: registry) }
        assert_equal 1, catalog[:document_axes].where(axis_source: "artifact-script").count,
                     "re-derive never duplicates the lane"
      end
    end
  end

  def test_an_unregistered_script_tag_is_refused_loudly
    with_catalog do |catalog, _demotic, _bare|
      Dir.mktmpdir do |dir|
        path = config_file(dir, "sources:\n  eleph:\n    egy-Egyd: {script: qqqq}\n")
        error = assert_raises(Nabu::Error) do
          Nabu::Store::ArtifactScripts.derive!(catalog, config_path: path, registry: registry)
        end
        assert_match(/qqqq/, error.message)
      end
    end
  end

  def test_absent_config_is_the_honest_no_op
    with_catalog do |catalog, _demotic, _bare|
      report = Nabu::Store::ArtifactScripts.derive!(catalog, config_path: "/nonexistent.yml",
                                                             registry: registry)
      assert_equal 0, report.minted
    end
  end
end
