# frozen_string_literal: true

require "test_helper"

# The declaration tranche of Nabu::AnnotationKeys pinned against ADAPTER
# OUTPUT: every declared key must come out of its source's adapter on the
# source's real fixture, carrying a known layer, with the fold the census
# assigned it (the passage's own language unless the layer is plainly a
# declared metalanguage). cantus and korpus16 keep their own pins in
# annotation_keys_test.rb (korpus16's note-bearing book needs its rig).
class AnnotationDeclarationsTest < Minitest::Test
  Keys = Nabu::AnnotationKeys

  # slug => {key => [fold, a layer text the real fixture yields]}
  DECLARED = {
    "ticha" => { "regularized" => [:passage, "En el nombre de la Santissima Trinidad"] },
    "grand-tour" => { "regularized" => [:passage, "Man zeigete uns auch drey Schwerdter"] },
    "ninjal-textdb" => { "normalized" => [:passage, "mundi jenbu."] },
    "emmo" => { "regularized" => [:passage, "Right worshipful and my very much respected friend"] },
    "memis" => { "diplomatic" => [:passage, "felix victor ac triumphator"] },
    "cbeta" => { "notes" => [:passage, "二合"] },
    "sefaria" => { "footnotes" => [:passage, "These are the names of nations listed in Genesis, chap. 10."] },
    "suda-translations" => { "notes" => [:passage, "Aristophanes, Plutus [Wealth] 1052"] },
    "statutes-realm" => { "marginal_notes" => [:passage, "No Meetings for Sports by People out of their own"],
                          "heading" => [:passage, "Profanation of the Lord's Day;"] },
    "senie" => { "marginalia" => [:passage, "o'd kogo innego?"] },
    "suttacentral" => { "comments" => ["eng", "Defined at AN 10.60:11.1 as non-attachment."],
                        "variants" => [:passage, "amatapadaṁ → amataṁ padaṁ (sya-all, mr)"] },
    "socinian-letters" => { "notes" => ["deu", "Der Eintrag steht in keinem inhaltlichen Zusammenhang"] },
    "corph" => { "textual_notes" => ["eng", "Aed using a subscript beneath E."] },
    "litopys" => { "variants" => [:passage, "1 Х. а се же суть."],
                   "notes" => ["rus", "А Эта статья имѣется только въ Ип. и Х."] },
    "comenius" => { "notes" => [:generic, "zevender maandIn Lv 25, 9"],
                    "marginalia" => [:passage, "Jesaia 66,6"] },
    "coptic-scriptorium" => { "notes" => ["eng", "damaged, blurry manuscript"] },
    "oshb" => { "notes" => ["eng", "We read one or more vowels in L differently from BHS."] },
    "osta" => { "notes" => ["eng", "6 lines of text in 18th century hand."] }
  }.freeze

  ADAPTERS = {
    "ticha" => Nabu::Adapters::Ticha, "grand-tour" => Nabu::Adapters::GrandTour,
    "ninjal-textdb" => Nabu::Adapters::NinjalTextdb, "emmo" => Nabu::Adapters::Emmo,
    "memis" => Nabu::Adapters::Memis, "cbeta" => Nabu::Adapters::Cbeta, "sefaria" => Nabu::Adapters::Sefaria,
    "suda-translations" => Nabu::Adapters::SudaTranslations, "statutes-realm" => Nabu::Adapters::StatutesRealm,
    "senie" => Nabu::Adapters::Senie, "suttacentral" => Nabu::Adapters::Suttacentral,
    "socinian-letters" => Nabu::Adapters::SocinianLetters, "corph" => Nabu::Adapters::Corph,
    "litopys" => Nabu::Adapters::Litopys, "comenius" => Nabu::Adapters::Comenius,
    "coptic-scriptorium" => Nabu::Adapters::CopticScriptorium, "oshb" => Nabu::Adapters::Oshb,
    "osta" => Nabu::Adapters::Osta
  }.freeze

  # The registry and this pin agree key for key, fold for fold: a new
  # declaration lands with its fixture round-trip, never alone.
  def test_the_registry_is_exactly_the_pinned_tranche
    tranche = Keys::REGISTRY.except("cantus", "korpus16")
    assert_equal DECLARED.keys.sort, tranche.keys.sort
    tranche.each do |slug, specs|
      assert_equal DECLARED.fetch(slug).transform_values(&:first),
                   specs.to_h { |spec| [spec.key, spec.fold] }, slug
    end
  end

  def test_metalanguage_layers_escape_the_passage_rules
    socinian = Keys.specs_for("socinian-letters").first
    assert_equal "sondern dieses ist auf ein blatt notiert, auf dem sich jener eintrag",
                 Keys.fold("sondern dieses ist auf ein Blatt notiert, auf dem sich jener Eintrag", socinian, "lat"),
                 "German commentary on a Latin letter keeps its j"
    comenius = Keys.specs_for("comenius").first
    assert_equal "jesaia", Keys.fold("Jesaia", comenius, "lat"), "Czech/Dutch editorial notes fold generically"
    marginalia = Keys.specs_for("comenius").last
    assert_equal "iesaia", Keys.fold("Jesaia", marginalia, "lat"), "the print's own margin folds as its passage"
    variants = Keys.specs_for("litopys").first
    assert_equal Nabu::Normalize.search_form("будущімъ", language: "orv"), Keys.fold("будущімъ", variants, "orv"),
                 "witness readings are the chronicle's own Old East Slavic"
  end

  DECLARED.each do |slug, keys|
    define_method(:"test_#{slug.tr('-', '_')}_declarations_match_adapter_output") do
      layers = fixture_layers(slug)
      keys.each do |key, (_fold, specimen)|
        texts = layers.select { |label, _text| label == key }.map(&:last)
        refute_empty texts, "#{slug} #{key}: the real fixture yields the layer"
        assert texts.any? { |text| text.include?(specimen) },
               "#{slug} #{key}: #{specimen.inspect} among #{texts.first(3)}"
      end
    end
  end

  private

  def fixture_layers(slug)
    adapter = ADAPTERS.fetch(slug).new
    adapter.discover(Nabu::TestSupport.fixtures(slug)).flat_map do |ref|
      adapter.parse(ref).passages.flat_map { |passage| Keys.layers(passage.annotations, Keys.specs_for(slug)) }
    rescue Nabu::DocumentSkipped
      []
    end
  end
end
