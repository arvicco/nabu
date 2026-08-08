# frozen_string_literal: true

require "test_helper"
require "digest"
require "fileutils"
require "json"
require "tmpdir"

# Nabu::ManualDrop (P63-1, ruling Dp-a) — the Manual Adapter pattern's shared
# machinery for high-value, HUMAN-only-accessible upstreams (captcha walls,
# POST forms, account gates): `nabu sync <slug>` prints an acquisition
# instruction card while the drop is absent, and once the owner places the
# download under incoming/<slug>/ it validates, attics the previous holding,
# ingests into canonical/<slug>/ and stamps `.manual-fetch.json` provenance —
# the `.zip-fetch.json` analogue, so idempotency (same bytes = no-op) and
# pinning work identically to fetched sources.
class ManualDropTest < Minitest::Test
  CSV_BODY  = %("id","name"\n"1","Pompeii";\n)
  JSON_BODY = %({"type": "FeatureCollection", "features": []}\n)

  def spec
    Nabu::ManualDrop::Spec.new(
      slug: "tm-test",
      upstream_url: "https://example.org/dataservices/",
      steps: ["Solve the captcha", "Tick every field", "Download as CSV"],
      files: [
        Nabu::ManualDrop::FileSpec.new(
          name: "TM_geo.csv", description: "the Geo table dump, CSV", required: true,
          sniff: ->(path) { File.read(path).start_with?(%("id")) ? nil : "does not start with the id header" }
        ),
        Nabu::ManualDrop::FileSpec.new(
          name: "TM_geo.json", description: "the same dump as JSON (optional)", required: false,
          sniff: ->(path) { File.read(path).include?("FeatureCollection") ? nil : "not a FeatureCollection" }
        )
      ],
      refresh_hint: "gazetteer changes slowly; re-acquire on demand"
    )
  end

  def with_layout
    Dir.mktmpdir do |root|
      drop = File.join(root, "incoming", "tm-test")
      dir = File.join(root, "canonical", "tm-test")
      FileUtils.mkdir_p(dir)
      yield drop, dir, File.join(dir, ".attic")
    end
  end

  def drop!(drop_dir, name, body)
    FileUtils.mkdir_p(drop_dir)
    File.write(File.join(drop_dir, name), body)
  end

  def sync!(drop, dir, attic)
    Nabu::ManualDrop.sync!(spec: spec, drop_dir: drop, dir: dir, attic_dir: attic)
  end

  # --- awaiting acquisition ---------------------------------------------------

  def test_an_absent_drop_raises_the_instruction_card_not_a_stack
    with_layout do |drop, dir, attic|
      error = assert_raises(Nabu::ManualDrop::AwaitingAcquisition) { sync!(drop, dir, attic) }
      assert_kind_of Nabu::FetchError, error, "awaiting is an honest abort, rescued clean by the CLI"
      card = error.message
      assert_includes card, "https://example.org/dataservices/"
      assert_includes card, "Solve the captcha", "the steps ride the card"
      assert_includes card, "TM_geo.csv"
      assert_includes card, drop, "the card names the exact drop path"
      refute_includes card, "TM_geo.json is required", "optional files are never demanded"
      assert_includes card, "(optional)", "optional files are still listed"
    end
  end

  def test_a_missing_required_file_is_awaiting_even_when_optional_files_landed
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.json", JSON_BODY)
      assert_raises(Nabu::ManualDrop::AwaitingAcquisition) { sync!(drop, dir, attic) }
    end
  end

  # --- validation -------------------------------------------------------------

  def test_a_malformed_drop_is_refused_with_one_plain_sentence
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.csv", "<!doctype html>captcha page")
      error = assert_raises(Nabu::FetchError) { sync!(drop, dir, attic) }
      refute_kind_of Nabu::ManualDrop::AwaitingAcquisition, error, "malformed is NOT awaiting — say what broke"
      assert_includes error.message, "TM_geo.csv"
      assert_includes error.message, "does not start with the id header"
      assert File.exist?(File.join(drop, "TM_geo.csv")), "a refused drop is never consumed or deleted"
    end
  end

  # --- ingest -----------------------------------------------------------------

  def test_first_ingest_moves_files_and_stamps_provenance
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.csv", CSV_BODY)
      drop!(drop, "TM_geo.json", JSON_BODY)
      result = sync!(drop, dir, attic)
      assert result.ingested
      refute result.not_modified
      assert_equal CSV_BODY, File.read(File.join(dir, "TM_geo.csv"))
      assert_equal JSON_BODY, File.read(File.join(dir, "TM_geo.json"))
      refute File.exist?(File.join(drop, "TM_geo.csv")), "an accepted drop is CONSUMED (moved, not copied)"
      state = JSON.parse(File.read(File.join(dir, ".manual-fetch.json")))
      assert_equal Digest::SHA256.hexdigest(CSV_BODY), state.dig("files", "TM_geo.csv")
      assert_equal "https://example.org/dataservices/", state["upstream_url"]
      refute_nil state["acquired_at"], "provenance carries the acquisition (file) time"
      refute_nil state["ingested_at"]
      assert_equal result.sha, Nabu::ManualDrop.pin(dir), "the returned sha IS the stored pin"
    end
  end

  def test_ingest_without_the_optional_file_holds_only_the_required_one
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.csv", CSV_BODY)
      result = sync!(drop, dir, attic)
      assert result.ingested
      refute File.exist?(File.join(dir, "TM_geo.json"))
      state = JSON.parse(File.read(File.join(dir, ".manual-fetch.json")))
      assert_equal ["TM_geo.csv"], state["files"].keys
    end
  end

  # --- idempotency + replacement ---------------------------------------------

  def test_a_byte_identical_redrop_is_a_no_op_and_never_touches_canonical
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.csv", CSV_BODY)
      first = sync!(drop, dir, attic)
      drop!(drop, "TM_geo.csv", CSV_BODY)
      held_mtime = File.mtime(File.join(dir, "TM_geo.csv"))
      second = sync!(drop, dir, attic)
      assert second.not_modified
      refute second.ingested
      assert_equal first.sha, second.sha, "a no-op repeats the stored pin"
      assert_equal held_mtime, File.mtime(File.join(dir, "TM_geo.csv"))
      assert File.exist?(File.join(drop, "TM_geo.csv")),
             "identical drop copies stay in incoming/ (the owner's file is never deleted)"
    end
  end

  def test_a_changed_redrop_attics_the_previous_holding_before_the_swap
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.csv", CSV_BODY)
      sync!(drop, dir, attic)
      updated = %(#{CSV_BODY}"2","Capua";\n)
      drop!(drop, "TM_geo.csv", updated)
      result = sync!(drop, dir, attic)
      assert result.ingested
      assert_equal updated, File.read(File.join(dir, "TM_geo.csv"))
      atticked = Dir.glob(File.join(attic, "**", "TM_geo.csv"))
      assert_equal 1, atticked.size, "the replaced holding lands in the attic, never vanishes"
      assert_equal CSV_BODY, File.read(atticked.first)
    end
  end

  def test_a_clean_sync_with_no_drop_over_a_held_ingest_reports_held_not_awaiting
    with_layout do |drop, dir, attic|
      drop!(drop, "TM_geo.csv", CSV_BODY)
      first = sync!(drop, dir, attic)
      result = sync!(drop, dir, attic) # drop consumed; nothing new offered
      assert result.not_modified
      assert_equal first.sha, result.sha,
                   "a held shelf with an empty drop is up to date, never re-demanded"
    end
  end
end
