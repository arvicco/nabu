# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::WorkEras: the ruled per-work attributed-era table
# (config/work_eras.yml). Tests read the REAL config — the table is ruled
# config (the period_bands precedent) and these pins are its contract:
# dynasty rows resolve through period_bands, explicit envelopes carry
# their own label, contested works declared out answer nil, and the
# work list stays in parity with the kind fold over the same key.
class WorkErasTest < Minitest::Test
  def teardown = Nabu::WorkEras.reset!

  def table = Nabu::WorkEras.default

  def test_a_dynasty_row_resolves_through_the_period_bands_table
    era = table.lookup("classical-modern", "史记")
    assert_equal [-206, 8], era.band, "前漢 — the sinological Western Han row"
    assert_equal "前漢", era.label
  end

  def test_an_explicit_envelope_carries_its_own_label
    era = table.lookup("classical-modern", "战国策")
    assert_equal [-475, 8], era.band
    assert_equal "戰國–前漢", era.label
  end

  def test_a_contested_work_declared_out_answers_nil
    assert_nil table.lookup("classical-modern", "文昌孝经")
    assert_includes table.works("classical-modern"), "文昌孝经", "declared, not forgotten"
  end

  def test_an_unknown_work_or_source_answers_nil
    assert_nil table.lookup("classical-modern", "不存在之书")
    assert_nil table.lookup("kanripo", "史记")
  end

  def test_the_table_keys_on_the_declared_metadata_field
    assert_equal "book", table.key_for("classical-modern")
  end

  def test_every_row_carries_its_reasoning_and_a_sane_band
    table.works("classical-modern").each do |work|
      assert table.note("classical-modern", work).to_s.strip.size.positive?, "#{work}: every row cites its reasoning"
      era = table.lookup("classical-modern", work) or next
      assert era.band[0] < era.band[1], "#{work}: band must run forward"
    end
  end

  # The 97 works censused 2026-10-19 (metadata.book, live catalog) — the
  # era table and the kind fold rule the SAME work list.
  def test_the_work_list_is_the_censused_97_and_matches_the_kind_fold
    works = table.works("classical-modern")
    assert_equal 97, works.size
    kinds = Nabu::Kinds.load(
      classes_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_classes.yml"),
      map_path: File.join(Nabu::Config::PROJECT_ROOT, "config", "kind_map.yml")
    )
    assert_equal ["book"], kinds.metadata_for("classical-modern")
    assert_equal works.sort, kinds.rule_for("classical-modern").map.keys.sort,
                 "every work carries exactly one era row and one kind fold"
  end

  def test_an_era_label_without_a_period_bands_row_is_a_config_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "work_eras.yml")
      File.write(path, <<~YAML)
        sources:
          demo:
            key: book
            works:
              "某书": {era: "無此朝", note: "a typo"}
      YAML
      assert_raises(Nabu::WorkEras::ConfigError) { Nabu::WorkEras.load(path) }
    end
  end

  def test_load_returns_nil_for_a_missing_file
    assert_nil Nabu::WorkEras.load("/nonexistent/work_eras.yml")
  end
end
