# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::ReuseProfiles (P122-2): config/reuse_profiles.yml, the declared
# per-language tuning profiles of the parallels batch producer. Loading is
# strict — an unknown key or a mistyped knob is refused loudly, never
# silently ignored (a typo'd `gram_sise` would otherwise mine with the
# default and record a tuning that never happened).
class ReuseProfilesTest < Minitest::Test
  def with_profiles(yaml)
    Dir.mktmpdir("nabu-reuse") do |dir|
      path = File.join(dir, "reuse_profiles.yml")
      File.write(path, yaml)
      yield path
    end
  end

  VALID = <<~YAML
    profiles:
      demo:
        lang: lat
        serves: a test scope
        gram_size: 3
        min_score: 0.1
        per_anchor: 4
        candidate_pool: 50
        stop_tokens: [Et, IN, vel]
        rationale: because
  YAML

  def test_loads_every_declared_knob
    with_profiles(VALID) do |path|
      profile = Nabu::ReuseProfiles.load(path).fetch("demo")
      assert_equal "demo", profile.name
      assert_equal "lat", profile.lang
      assert_equal [3, 0.1, 4, 50], [profile.gram_size, profile.min_score, profile.per_anchor, profile.candidate_pool]
      assert_equal "because", profile.rationale
    end
  end

  def test_stop_tokens_fold_to_the_languages_search_form
    with_profiles(VALID) do |path|
      assert_equal %w[et in uel], Nabu::ReuseProfiles.load(path).fetch("demo").stop_tokens,
                   "lowercased and Latin v→u folded — they must compare against search-form gram tokens"
    end
  end

  def test_omitted_knobs_are_nil_so_the_engine_defaults_apply
    with_profiles("profiles:\n  bare:\n    serves: x\n    rationale: y\n") do |path|
      profile = Nabu::ReuseProfiles.load(path).fetch("bare")
      assert_nil profile.gram_size
      assert_nil profile.lang
      assert_equal [], profile.stop_tokens
    end
  end

  def test_unknown_profile_key_is_refused_loudly
    with_profiles("profiles:\n  demo:\n    serves: x\n    rationale: y\n    gram_sise: 3\n") do |path|
      error = assert_raises(Nabu::ReuseProfiles::Error) { Nabu::ReuseProfiles.load(path) }
      assert_match(/demo: unknown key\(s\) gram_sise/, error.message)
      assert_includes error.message, path, "the error names the file"
    end
  end

  def test_unknown_top_level_key_is_refused
    with_profiles("profiles: {}\nprofile: {}\n") do |path|
      assert_raises(Nabu::ReuseProfiles::Error) { Nabu::ReuseProfiles.load(path) }
    end
  end

  def test_rationale_and_serves_are_required
    with_profiles("profiles:\n  demo:\n    serves: x\n    gram_size: 3\n") do |path|
      error = assert_raises(Nabu::ReuseProfiles::Error) { Nabu::ReuseProfiles.load(path) }
      assert_match(/demo: rationale is required/, error.message)
    end
  end

  def test_mistyped_knobs_are_refused
    { "gram_size: 1" => /gram_size/, "gram_size: three" => /gram_size/, "min_score: -1" => /min_score/,
      "per_anchor: 0" => /per_anchor/, "candidate_pool: 2.5" => /candidate_pool/,
      "stop_tokens: et" => /stop_tokens/ }.each do |line, message|
      with_profiles("profiles:\n  demo:\n    serves: x\n    rationale: y\n    #{line}\n") do |path|
        error = assert_raises(Nabu::ReuseProfiles::Error, line) { Nabu::ReuseProfiles.load(path) }
        assert_match message, error.message
      end
    end
  end

  def test_fetching_an_undeclared_profile_names_the_declared_ones
    with_profiles(VALID) do |path|
      error = assert_raises(Nabu::ReuseProfiles::Error) { Nabu::ReuseProfiles.load(path).fetch("greek") }
      assert_match(/unknown reuse profile "greek" — declared: demo/, error.message)
    end
  end

  def test_a_missing_file_declares_no_profiles
    profiles = Nabu::ReuseProfiles.load("/nonexistent/reuse_profiles.yml")
    assert_empty profiles.names
  end

  # The shipped table: the two first profiles load, validate, and carry
  # their tuning (a regression pin on the config itself).
  def test_the_shipped_profiles_load_with_their_rationale
    profiles = Nabu::ReuseProfiles.default
    assert_equal %w[chinese latin], profiles.names.sort
    latin = profiles.fetch("latin")
    assert_equal ["lat", 3], [latin.lang, latin.gram_size]
    assert_includes latin.stop_tokens, "uel", "the Latin stop list is search-form folded"
    chinese = profiles.fetch("chinese")
    assert_equal ["lzh", 4], [chinese.lang, chinese.gram_size]
    [latin, chinese].each { |profile| refute_empty profile.rationale.strip }
  end
end
