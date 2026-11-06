# frozen_string_literal: true

require "test_helper"

# The per-source registry of SEARCHABLE annotation layers
# (Nabu::AnnotationKeys): which annotation keys carry passage-grain text a
# reader searches for — a standardized spelling, margin notes — and how a
# stored annotations hash becomes [label, text] layers. Declared, never
# sniffed: an unregistered key is never indexed.
class AnnotationKeysTest < Minitest::Test
  Keys = Nabu::AnnotationKeys

  def test_the_two_declared_consumers
    assert_equal %w[cantus korpus16], Keys.slugs.sort
    assert_equal ["standardized"], Keys.specs_for("cantus").map(&:key)
    assert_equal ["notes"], Keys.specs_for("korpus16").map(&:key)
    refute Keys.registered?("perseus")
    assert_empty Keys.specs_for("perseus")
  end

  # The fold-language law: annotations fold with the passage's OWN
  # language (cantus Latin, korpus16 Slovene) — never the generic fold the
  # translations lane uses for its foreign-language renderings.
  def test_every_declared_key_folds_with_the_passage_language
    Keys::REGISTRY.each do |slug, specs|
      specs.each { |spec| assert_equal :passage, spec.fold, "#{slug} #{spec.key}" }
    end
    assert_equal "praesul iam iesu", Keys.fold("Praesul jam Jesu", Keys.specs_for("cantus").first, "lat"),
                 "the Latin rules (j→i) apply to cantus' standardized text"
    assert_equal "praesul jam jesu", Keys.fold("Praesul jam Jesu", Keys::Spec.new(key: "x", fold: :generic), "lat")
    assert_equal "ſkusi", Nabu::Normalize.search_form("ſkusi", language: nil), "generic leaves long s alone"
    assert_equal "skusi", Keys.fold("ſkusi", Keys.specs_for("korpus16").first, "sl"), "Slovene folds ſ→s"
  end

  def test_an_undeclared_fold_choice_is_refused
    assert_raises(ArgumentError) { Keys::Spec.new(key: "x", fold: :english) }
  end

  def test_scalar_keys_become_labeled_layers
    annotations = { "text_form" => "manuscript", "standardized" => "  Tamdiu quippe praesul ", "volpiano" => "1--g" }
    assert_equal [["standardized", "Tamdiu quippe praesul"]], Keys.layers(annotations, Keys.specs_for("cantus"))
  end

  def test_string_arrays_become_one_layer_per_item
    annotations = { "notes" => ["Sobbota ali prasnik.", "Gen, 12", "", 7], "catchword" => "na" }
    assert_equal [["notes", "Sobbota ali prasnik."], ["notes", "Gen, 12"]],
                 Keys.layers(annotations, Keys.specs_for("korpus16"))
  end

  def test_letterless_values_and_declared_placeholders_mint_nothing
    assert_empty Keys.layers({ "standardized" => "LACUNA" }, Keys.specs_for("cantus")),
                 "Cantus' lost-text marker is not a spelling"
    assert_empty Keys.layers({ "standardized" => "{#}" }, Keys.specs_for("cantus"))
    assert_empty Keys.layers({ "notes" => ["*", "12."] }, Keys.specs_for("korpus16"))
  end

  def test_stored_json_is_probed_before_parsing
    specs = Keys.specs_for("korpus16")
    assert_empty Keys.layers('{"folio":"I,56a"}', specs)
    assert_equal [["notes", "Kadilu."]], Keys.layers('{"notes":["Kadilu."]}', specs)
  end

  # The registry is a claim about adapter OUTPUT: every declared key must
  # come out of the source's adapter on its real fixture. korpus16's
  # note-bearing page (Dalmatin's Bible, I,56a) belongs to a book whose
  # crawl the fixture holds only partially — discovery skips it by rule —
  # so its document is parsed straight from its ref.
  def test_registry_matches_adapter_output_for_cantus
    adapter = Nabu::Adapters::Cantus.new
    workdir = Nabu::TestSupport.fixtures("cantus")
    layers = adapter.discover(workdir).flat_map do |ref|
      adapter.parse(ref).passages.flat_map { |passage| Keys.layers(passage.annotations, Keys.specs_for("cantus")) }
    rescue Nabu::DocumentSkipped
      []
    end
    assert_includes layers.map(&:last).join("\n"), "praesul"
  end

  def test_registry_matches_adapter_output_for_korpus16
    document = Nabu::TestSupport.korpus16_bible_document
    layers = document.passages.flat_map { |passage| Keys.layers(passage.annotations, Keys.specs_for("korpus16")) }
    assert_includes layers, ["notes", "Sobbota ali prasnik."]
  end
end
