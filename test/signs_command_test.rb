# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# `nabu signs <urn|text>` (P53-2): ATF transliteration → sign identities
# through the SignList seam. Raw-text mode needs no catalog; urn mode opens
# the catalog read-only; the sign list absent = the honest refusal with the
# sync hint (the feature-module lane-off rule), byte-identical everything
# else. Output in the `nabu char` mold: absent data ABSENT, never "—".
class SignsCommandTest < Minitest::Test
  OSL_FIXTURE = File.join(Nabu::TestSupport.fixtures("osl"), "osl.asl")

  # -- raw text mode (no catalog needed) --------------------------------------

  def test_raw_text_resolves_values_to_signs
    with_signs_config do |config|
      out, _err, status = with_config(config) { run_cli(%w[signs szesz]) }
      assert_nil status
      assert_match(/šeš/, out)
      assert_match(/deterministic/, out)
      assert_match(/ŠEŠ/, out)
      assert_match(/U\+122C0/, out)
      assert_match(/𒋀/, out)
    end
  end

  def test_ambiguity_lists_every_candidate
    with_signs_config do |config|
      out, = with_config(config) { run_cli(%w[signs idₓ]) }
      assert_match(/ambiguous/, out)
      assert_match(/\|A\.BARA₂\|/, out)
      assert_match(/\|UD\.ŠEŠ\.KI\|/, out)
    end
  end

  def test_unknown_and_unencoded_are_honest_never_dashed
    with_signs_config do |config|
      out, = with_config(config) { run_cli(["signs", "blah99 |AxAN|"]) }
      assert_match(/not in the sign list/, out)
      assert_match(/unencoded/, out)
      refute_match(/—$/, out, "no bare em-dash placeholder anywhere")
    end
  end

  def test_etcsl_dialect_flag_folds_c_and_j
    with_signs_config do |config|
      out, = with_config(config) { run_cli(%w[signs --dialect etcsl aj]) }
      assert_match(/aŋ/, out)
      assert_match(/AK/, out)
    end
  end

  def test_unknown_dialect_errors
    with_signs_config do |config|
      _out, err, status = with_config(config) { run_cli(%w[signs --dialect klingon aj]) }
      assert_equal 1, status
      assert_match(/dialect/, err)
    end
  end

  # -- the lane-off rule -------------------------------------------------------

  def test_without_the_sign_list_the_command_refuses_with_the_sync_hint
    with_signs_config(osl: false) do |config|
      _out, err, status = with_config(config) { run_cli(%w[signs szesz]) }
      assert_equal 1, status
      assert_match(/nabu sync osl/, err)
    end
  end

  # -- urn mode ----------------------------------------------------------------

  def test_urn_mode_reads_the_passage_from_the_catalog
    with_signs_config do |config|
      urn = seed_cdli(config)
      out, _err, status = with_config(config) { run_cli(["signs", urn]) }
      assert_nil status
      assert_match(/#{Regexp.escape(urn)}/, out)
      assert_match(/sux/, out)
      assert_match(/1\(geš₂\)/, out, "the real P469841 line, folded")
      assert_match(/guruš/, out)
    end
  end

  def test_urn_mode_unknown_urn_errors
    with_signs_config do |config|
      seed_cdli(config)
      _out, err, status = with_config(config) { run_cli(%w[signs urn:nabu:cdli:p9999999]) }
      assert_equal 1, status
      assert_match(/urn not found/, err)
    end
  end

  def test_urn_mode_without_a_catalog_errors
    with_signs_config do |config|
      _out, err, status = with_config(config) { run_cli(%w[signs urn:nabu:cdli:p469841]) }
      assert_equal 1, status
      assert_match(/no corpus/, err)
    end
  end

  # -- --json: the frozen contract --------------------------------------------

  def test_json_emits_the_frozen_contract
    with_signs_config do |config|
      out, _err, status = with_config(config) { run_cli(%w[signs --json szesz]) }
      assert_nil status
      payload = JSON.parse(out)
      assert_equal "text", payload.fetch("mode")
      token = payload.fetch("lines").first.fetch("tokens").first
      assert_equal(
        { "input_value" => "šeš", "status" => "deterministic", "sign_name" => "ŠEŠ",
          "codepoints" => ["U+122C0"], "candidates" => [], "language_qualifier" => nil },
        token
      )
    end
  end

  def test_json_urn_mode_carries_urn_language_and_source
    with_signs_config do |config|
      urn = seed_cdli(config)
      out, = with_config(config) { run_cli(["signs", "--json", urn]) }
      payload = JSON.parse(out)
      assert_equal "urn", payload.fetch("mode")
      assert_equal urn, payload.fetch("urn")
      assert_equal "sux", payload.fetch("language")
      assert_equal "cdli", payload.fetch("source")
      assert_equal urn, payload.fetch("lines").first.fetch("urn")
    end
  end

  # -- rig ---------------------------------------------------------------------

  def with_signs_config(osl: true)
    Dir.mktmpdir("nabu-signs") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      if osl
        dir = File.join(config.canonical_dir, "osl", "00lib")
        FileUtils.mkdir_p(dir)
        FileUtils.cp(OSL_FIXTURE, File.join(dir, "osl.asl"))
      end
      Nabu::SignList.reset!
      yield config
    ensure
      Nabu::SignList.reset!
    end
  end

  def seed_cdli(config)
    FileUtils.mkdir_p(config.db_dir)
    db = Nabu::Store.connect(config.catalog_path)
    Nabu::Store.migrate!(db)
    Nabu::Store.setup!(db)
    source = Nabu::Store::Source.create(
      slug: "cdli", name: "CDLI", adapter_class: "Nabu::Adapters::Cdli",
      license_class: "attribution"
    )
    adapter = Nabu::Adapters::Cdli.new
    ref = adapter.discover(Nabu::TestSupport.fixtures("cdli"))
                 .find { |r| r.id == "urn:nabu:cdli:p469841" }
    document = adapter.parse(ref)
    Nabu::Store::Loader.new(db: db, source: source).load([document], full: false)
    document.passages.first.urn
  ensure
    db&.disconnect
  end

  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end
end
