# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::LanguageDossiers — the READ seam over the mul/language-dossiers overlay
# Nabu publishes to nabu-data and re-consumes under canonical/nabu-data/ (the
# FormLemma posture). Absent file → nil (the feature-module law); present →
# each language's curated overlay layer, grouped from the CLDF ValueTable.
class LanguageDossiersTest < Minitest::Test
  DATASET = File.join("mul", "language-dossiers", "language-dossiers.csv")

  def with_overlay(rows)
    Dir.mktmpdir("nabu-data") do |dir|
      path = File.join(dir, DATASET)
      FileUtils.mkdir_p(File.dirname(path))
      CSV.open(path, "w") do |csv|
        csv << %w[ID Language_ID Parameter_ID Value]
        rows.each { |row| csv << row }
      end
      yield Nabu::LanguageDossiers.load(dir)
    end
  end

  def test_load_default_is_nil_when_the_overlay_is_unsynced
    Dir.mktmpdir do |dir|
      config = Nabu::Config.load
      config.define_singleton_method(:canonical_dir) { dir }
      assert_nil Nabu::LanguageDossiers.load_default(config: config)
    end
  end

  def test_groups_the_value_table_into_a_per_code_dossier
    with_overlay([
                   %w[chu-name chu name] + ["Old Church Slavonic"],
                   %w[chu-family chu family] + ["South Slavic"],
                   %w[chu-context chu context] + ["The oldest attested Slavic literary language."],
                   %w[chu-period chu period] + ["9th–11th c."],
                   %w[chu-provenance chu provenance] + ["noted: 2026-08-02 (Wikipedia-derived)"]
                 ]) do |overlay|
      dossier = overlay.dossier("chu")
      refute_nil dossier
      assert_equal "Old Church Slavonic", dossier.name
      assert_equal "South Slavic", dossier.family
      assert_equal "The oldest attested Slavic literary language.", dossier.context
      assert_equal({ "period" => "9th–11th c." }, dossier.extras)
      assert_match(/Wikipedia-derived/, dossier.provenance)
    end
  end

  def test_an_absent_code_is_nil_and_absent_lanes_stay_nil
    with_overlay([%w[xyz-name xyz name] + ["Stub Language"]]) do |overlay|
      assert_nil overlay.dossier("chu"), "a code the overlay does not carry"
      stub = overlay.dossier("xyz")
      assert_equal "Stub Language", stub.name
      assert_nil stub.family, "absent lanes stay nil (binding honesty)"
      assert_nil stub.context
      assert_empty stub.extras
    end
  end

  def test_size_counts_distinct_codes
    with_overlay([
                   %w[chu-name chu name] + ["Old Church Slavonic"],
                   %w[chu-family chu family] + ["South Slavic"],
                   %w[aae-name aae name] + ["Arbëresh Albanian"]
                 ]) do |overlay|
      assert_equal 2, overlay.size
    end
  end
end
