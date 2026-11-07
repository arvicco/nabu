# frozen_string_literal: true

require "test_helper"

# The per-source registry of SEARCHABLE annotation layers
# (Nabu::AnnotationKeys): which annotation keys carry passage-grain text a
# reader searches for — a standardized spelling, margin notes — and how a
# stored annotations hash becomes [label, text] layers. Declared, never
# sniffed: an unregistered key is never indexed.
class AnnotationKeysTest < Minitest::Test
  Keys = Nabu::AnnotationKeys

  # The first two consumers (the second tranche is pinned key by key in
  # annotation_declarations_test.rb).
  def test_the_first_declared_consumers
    assert_includes Keys.slugs, "cantus"
    assert_includes Keys.slugs, "korpus16"
    assert_equal ["standardized"], Keys.specs_for("cantus").map(&:key)
    assert_equal ["notes"], Keys.specs_for("korpus16").map(&:key)
    refute Keys.registered?("perseus")
    assert_empty Keys.specs_for("perseus")
  end

  # The fold-language law: a layer in the passage's OWN language (cantus
  # Latin, korpus16 Slovene) folds by it — never the generic fold the
  # translations lane uses for its foreign-language renderings.
  def test_own_language_layers_fold_with_the_passage_language
    %w[cantus korpus16].each do |slug|
      Keys.specs_for(slug).each { |spec| assert_equal :passage, spec.fold, "#{slug} #{spec.key}" }
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

  # The field: law — a layer stored as a LIST OF OBJECTS (grand-tour's
  # marginalia {place:, text:}, the TCP notes {n:, place:, text:}) is
  # declared with the object key holding the text: each object is one
  # layer, the sibling keys (place, type, resp) never index, and a bare
  # string or an object without the field mints nothing — the declared
  # shape is the contract, never a sniff.
  def test_field_reads_the_declared_key_of_each_object
    spec = Keys::Spec.new(key: "marginalia", field: "text")
    annotations = { "marginalia" => [{ "place" => "margin_right", "text" => " Drengelburg " },
                                     { "place" => "margin_left", "text" => "2 M." },
                                     { "place" => "margin_left", "text" => "12." },
                                     { "place" => "margin_left" }, "stray string", 7,
                                     { "place" => "margin_right", "text" => "Cassel" }] }
    assert_equal [%w[marginalia Drengelburg], ["marginalia", "2 M."], %w[marginalia Cassel]],
                 Keys.layers(annotations, [spec]),
                 "a letterless text still mints nothing; objects without the field and non-objects are skipped"
  end

  def test_without_field_objects_mint_nothing
    annotations = { "marginalia" => [{ "place" => "margin_right", "text" => "Cassel" }] }
    assert_empty Keys.layers(annotations, [Keys::Spec.new(key: "marginalia")])
  end

  def test_field_must_be_a_non_empty_string
    assert_raises(ArgumentError) { Keys::Spec.new(key: "x", field: :text) }
    assert_raises(ArgumentError) { Keys::Spec.new(key: "x", field: "") }
  end

  # markup: :html — a layer upstream ships as an HTML fragment
  # (suttacentral's comments: <a href> cross-references, <i lang='pi'>
  # Pali words) indexes and snippets its TEXT, never its tag soup.
  def test_html_markup_is_stripped_before_indexing
    spec = Keys::Spec.new(key: "comments", markup: :html)
    value = "Defined at <a href='https://suttacentral.net/an10.60/en/sujato#11.1'>AN 10.60:11.1</a> " \
            "as <i lang='pi' translate='no'>asaṅga</i>."
    assert_equal [["comments", "Defined at AN 10.60:11.1 as asaṅga."]], Keys.layers({ "comments" => value }, [spec])
    assert_empty Keys.layers({ "comments" => "<i>12</i>" }, [spec]), "markup alone carries no letter"
    assert_raises(ArgumentError) { Keys::Spec.new(key: "x", markup: :tei) }
  end

  # A layer plainly in a metalanguage other than the passage's (English
  # notes on Coptic, German notes on Latin letters) declares ITS language:
  # it folds by that language's rules, never the passage's.
  def test_a_declared_language_fold
    german = Keys::Spec.new(key: "notes", fold: "deu")
    assert_equal "deu", Keys.fold_language(german, "lat")
    assert_equal "jahr", Keys.fold("Jahr", german, "lat"), "German notes escape the Latin j→i rule"
    assert_equal "iam", Keys.fold("jam", Keys::Spec.new(key: "x"), "lat")
    assert_equal "lat", Keys.fold_language(Keys::Spec.new(key: "x"), "lat")
    assert_nil Keys.fold_language(Keys::Spec.new(key: "x", fold: :generic), "lat")
    assert_raises(ArgumentError) { Keys::Spec.new(key: "x", fold: "German") }
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
