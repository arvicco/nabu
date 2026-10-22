# frozen_string_literal: true

require "test_helper"

# The annotation-held translation registry (Nabu::TranslationKeys): which
# annotation keys carry a passage's translation, per source, and how a
# stored annotations hash becomes [label, text] layers.
class TranslationKeysTest < Minitest::Test
  Keys = Nabu::TranslationKeys

  def test_scalar_keys_become_labeled_layers_in_registry_order
    annotations = { "translation" => "  She labored to stop him. ", "translation_ar" => "أما هي",
                    "tokens" => [{ "form" => "x" }] }
    assert_equal [["translation", "She labored to stop him."], ["translation_ar", "أما هي"]],
                 Keys.layers(annotations, Keys.specs_for("coptic-scriptorium"))
  end

  def test_the_atf_tr_lane_keeps_every_language_but_the_ts_transcription
    annotations = { "tr" => { "en" => "scribe,", "ts" => "ṭupšarrum", "de" => "Schreiber" } }
    assert_equal [["tr.en", "scribe,"], ["tr.de", "Schreiber"]],
                 Keys.layers(annotations, Keys.specs_for("cdli"))
  end

  def test_conllu_translation_comments_are_nested_layers
    annotations = { "translations" => { "text_en" => "He built a replica of Esagil." } }
    assert_equal [["translations.text_en", "He built a replica of Esagil."]],
                 Keys.layers(annotations, Keys.specs_for("ud"))
  end

  def test_letterless_values_and_declared_placeholders_mint_nothing
    assert_empty Keys.layers({ "translation" => "..." }, Keys.specs_for("coptic-scriptorium"))
    assert_empty Keys.layers({ "gloss" => " |  | " }, Keys.specs_for("aclt"))
    assert_empty Keys.layers({ "translation" => "[nog vertalen]" }, Keys.specs_for("corpus-oudnederlands"))
    assert_empty Keys.layers({ "translation" => "[translation to be added ]" }, Keys.specs_for("tamilex"))
    assert_equal [["translation", "Brood moet wegen"]],
                 Keys.layers({ "translation" => "Brood moet wegen" }, Keys.specs_for("corpus-oudnederlands"))
  end

  def test_unregistered_keys_and_sources_mint_nothing
    assert_empty Keys.layers({ "gloss" => "NOM.SG.C | CNJ" }, Keys.specs_for("hittite-glossed")),
                 "hittite-glossed gloss is grammatical tagging, not a rendering"
    assert_empty Keys.layers({ "translation_ref" => "ITKC_BT_1550A" }, Keys.specs_for("itkc"))
    refute Keys.registered?("perseus")
  end

  def test_stored_json_is_probed_before_parsing
    specs = Keys.specs_for("cdli")
    assert_empty Keys.layers('{"tokens":[]}', specs)
    assert_equal [["tr.en", "king of Ur,"]], Keys.layers('{"tr":{"en":"king of Ur,"}}', specs)
  end

  # The registry is a claim about adapter OUTPUT: every registered key must
  # actually come out of the source's adapter on its real fixture, or the
  # index silently goes dark the day an adapter renames a field.
  FIXTURE_WORKDIRS = {
    "aclt" => :local, "corpus-oudnederlands" => :local
  }.freeze

  Keys::REGISTRY.each_key do |slug|
    define_method("test_registry_matches_adapter_output_for_#{slug.tr('-', '_')}") do
      workdir = fixture_workdir(slug)
      adapter = Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)[slug].build_adapter
      layers = adapter.discover(workdir).flat_map do |ref|
        adapter.parse(ref).passages.flat_map { |passage| Keys.layers(passage.annotations, Keys.specs_for(slug)) }
      rescue Nabu::DocumentSkipped
        [] # a rejected-grain specimen (tombstone, skeleton) — skipped by rule
      end
      refute_empty layers, "#{slug}: no fixture passage carries a registered translation key"
    end
  end

  private

  def fixture_workdir(slug)
    return Nabu::TestSupport.fixtures(slug) unless FIXTURE_WORKDIRS[slug] == :local

    skip "#{slug}: restricted fixture absent (local/fixtures/#{slug})" unless Nabu::TestSupport.local_fixtures?(slug)
    Nabu::TestSupport.local_fixtures(slug)
  end
end
