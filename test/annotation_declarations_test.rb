# frozen_string_literal: true

require "test_helper"

# The declaration tranches of Nabu::AnnotationKeys pinned against ADAPTER
# OUTPUT: every declared key must come out of its source's adapter on the
# source's real fixture, carrying a known layer, with the fold (and object
# field) the census assigned it — the passage's own language unless the
# layer is plainly a declared metalanguage. cantus and korpus16 keep their
# own pins in annotation_keys_test.rb (korpus16's note-bearing book needs
# its rig).
class AnnotationDeclarationsTest < Minitest::Test
  Keys = Nabu::AnnotationKeys

  # slug => {key => [fold, field, a layer text the real fixture yields]}
  # (a nil specimen: no fixture document carries the layer — NO_FIXTURE).
  DECLARED = {
    "ticha" => { "regularized" => [:passage, nil, "En el nombre de la Santissima Trinidad"] },
    "grand-tour" => { "regularized" => [:passage, nil, "Man zeigete uns auch drey Schwerdter"],
                      "marginalia" => [:passage, "text", "Drengelburg"],
                      "editorial_notes" => [:passage, "text", "Korrespondierendes Verweiszeichen"] },
    "ninjal-textdb" => { "normalized" => [:passage, nil, "mundi jenbu."],
                         "kanji_kana" => [:passage, nil, "日本の"] },
    "emmo" => { "regularized" => [:passage, nil, "Right worshipful and my very much respected friend"] },
    "memis" => { "diplomatic" => [:passage, nil, "felix victor ac triumphator"] },
    "cbeta" => { "notes" => [:passage, nil, "二合"] },
    "sefaria" => { "footnotes" => [:passage, nil, "These are the names of nations listed in Genesis, chap. 10."] },
    "suda-translations" => { "notes" => [:passage, nil, "Aristophanes, Plutus [Wealth] 1052"] },
    "statutes-realm" => { "marginal_notes" => [:passage, nil, "No Meetings for Sports by People out of their own"],
                          "heading" => [:passage, nil, "Profanation of the Lord's Day;"] },
    "senie" => { "marginalia" => [:passage, nil, "o'd kogo innego?"] },
    "evans-tcp" => { "notes" => [:passage, "text", nil] },
    "ecco-tcp" => { "notes" => [:passage, "text", nil] },
    "suttacentral" => { "comments" => ["eng", nil, "Defined at AN 10.60:11.1 as non-attachment."],
                        "variants" => [:passage, nil, "amatapadaṁ → amataṁ padaṁ (sya-all, mr)"] },
    "socinian-letters" => { "notes" => ["deu", nil, "Der Eintrag steht in keinem inhaltlichen Zusammenhang"] },
    "corph" => { "textual_notes" => ["eng", nil, "Aed using a subscript beneath E."],
                 "latin_text" => ["lat", nil, "punicius"] },
    "litopys" => { "variants" => [:passage, nil, "1 Х. а се же суть."],
                   "notes" => ["orv", nil, "А Эта статья имѣется только въ Ип. и Х."] },
    "comenius" => { "notes" => [:generic, nil, "zevender maandIn Lv 25, 9"],
                    "marginalia" => [:passage, nil, "Jesaia 66,6"] },
    "coptic-scriptorium" => { "notes" => ["eng", nil, "damaged, blurry manuscript"] },
    "oshb" => { "notes" => ["eng", nil, "We read one or more vowels in L differently from BHS."] },
    "osta" => { "notes" => ["eng", nil, "6 lines of text in 18th century hand."] },
    "perseus-greek" => { "notes" => [:generic, "text", "The Athenians took Euboea from the Thebans in 357."] },
    "perseus-latin" => { "notes" => [:generic, "text", "TITUS' MISSION TO ROME"] },
    "first1k-greek" => { "notes" => [:generic, "text", "Ioannis Alex. Philoponi Schol."] },
    "pta" => { "notes" => [:generic, "text", nil] },
    "ja-wikisource" => { "kundoku" => ["jpn", nil, "天の香具山"], "kana" => ["jpn", nil, "あめのかぐやま"] },
    "aozora" => { "ruby" => [:passage, "reading", "いままで"] },
    "ko-wikisource-mk" => { "reading" => ["kor", nil, "해동육룡비"] },
    "stgall-priscian" => { "priscian" => ["lat", nil, "cum omnis eloquentiae doctrinam"] },
    "lotsawa-house" => { "phonetics" => [:generic, nil, "tongpé ngang lé pé nyi dü zhi teng"] }
  }.freeze

  # slug => [the adapter as sources.yml configures it, the fixture workdir]
  def self.rig(klass, slug, subdir = nil, **options)
    [-> { klass.new(**options) }, -> { File.join(*[Nabu::TestSupport.fixtures(slug), subdir].compact) }]
  end

  RIGS = {
    "ticha" => rig(Nabu::Adapters::Ticha, "ticha"),
    "grand-tour" => rig(Nabu::Adapters::GrandTour, "grand-tour"),
    "ninjal-textdb" => rig(Nabu::Adapters::NinjalTextdb, "ninjal-textdb"),
    "emmo" => rig(Nabu::Adapters::Emmo, "emmo"),
    "memis" => rig(Nabu::Adapters::Memis, "memis"),
    "cbeta" => rig(Nabu::Adapters::Cbeta, "cbeta"),
    "sefaria" => rig(Nabu::Adapters::Sefaria, "sefaria"),
    "suda-translations" => rig(Nabu::Adapters::SudaTranslations, "suda-translations"),
    "statutes-realm" => rig(Nabu::Adapters::StatutesRealm, "statutes-realm"),
    "senie" => rig(Nabu::Adapters::Senie, "senie"),
    "suttacentral" => rig(Nabu::Adapters::Suttacentral, "suttacentral"),
    "socinian-letters" => rig(Nabu::Adapters::SocinianLetters, "socinian-letters"),
    "corph" => rig(Nabu::Adapters::Corph, "corph"),
    "litopys" => rig(Nabu::Adapters::Litopys, "litopys"),
    "comenius" => rig(Nabu::Adapters::Comenius, "comenius"),
    "coptic-scriptorium" => rig(Nabu::Adapters::CopticScriptorium, "coptic-scriptorium"),
    "oshb" => rig(Nabu::Adapters::Oshb, "oshb"),
    "osta" => rig(Nabu::Adapters::Osta, "osta"),
    # The Olynthiac's Loeb notes sit in the inline-layer witness tree.
    "perseus-greek" => rig(Nabu::Adapters::Perseus, "perseus", "inline", translations: true),
    "perseus-latin" => rig(Nabu::Adapters::PerseusLatin, "perseus", "latinLit", translations: true),
    "first1k-greek" => rig(Nabu::Adapters::First1kGreek, "first1k", "greekLit", translations: true),
    "ja-wikisource" => rig(Nabu::Adapters::JaWikisource, "ja-wikisource"),
    "aozora" => rig(Nabu::Adapters::Aozora, "aozora"),
    "ko-wikisource-mk" => rig(Nabu::Adapters::KoWikisourceMk, "ko-wikisource-mk"),
    "stgall-priscian" => rig(Nabu::Adapters::StgallPriscian, "stgall-priscian"),
    "lotsawa-house" => rig(Nabu::Adapters::LotsawaHouse, "lotsawa-house", translations: true)
  }.freeze

  # Declared keys no fixture document carries (their trimmed editions keep
  # only header notes or none) — each still pinned below the adapter where
  # the code path allows.
  NO_FIXTURE = {
    "pta" => "the trimmed editions keep no <note> apparatus; the shape is the shared EpiDoc inline layer",
    "evans-tcp" => "the fixture prints carry only header NOTEs; the TCP parser's armed notes are pinned on CME",
    "ecco-tcp" => "the fixture prints carry only header NOTEs; the TCP parser's armed notes are pinned on CME"
  }.freeze

  # The registry and this pin agree key for key, fold for fold, field for
  # field: a new declaration lands with its fixture round-trip, never alone.
  def test_the_registry_is_exactly_the_pinned_tranches
    tranches = Keys::REGISTRY.except("cantus", "korpus16")
    assert_equal DECLARED.keys.sort, tranches.keys.sort
    tranches.each do |slug, specs|
      assert_equal DECLARED.fetch(slug).transform_values { |fold, field, _| [fold, field] },
                   specs.to_h { |spec| [spec.key, [spec.fold, spec.field]] }, slug
    end
    assert_equal NO_FIXTURE.keys.sort,
                 DECLARED.select { |_slug, keys| keys.values.any? { |(_, _, specimen)| specimen.nil? } }.keys.sort
  end

  def test_held_and_dropped_keys_stay_out
    refute Keys.registered?("eebo-tcp"), "eebo-tcp notes wait on their own sizing decision"
    refute Keys.registered?("otdo"), "otdo's letter-stack readings are no search layer"
    assert_equal ["priscian"], Keys.specs_for("stgall-priscian").map(&:key), "notes and terms stay held"
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
    assert_equal "ui", Keys.fold("vi", Keys.specs_for("corph").last, "sga"),
                 "the Latin source text folds as Latin on an Old Irish passage"
  end

  # The orv fold on litopys' pre-reform Russian notes is a findability
  # choice: a modern-spelling query meets the ѣ spelling the note carries.
  def test_litopys_notes_meet_a_modern_spelling_query
    folded = Keys.fold("Эта статья имѣется только въ Ип.", Keys.specs_for("litopys").last, "orv")
    assert(Nabu::Normalize.query_forms("имеется", language: nil).any? { |form| folded.include?(form) },
           "имеется reaches имѣется through the orv neutralization")
  end

  # The armed TCP notes path (TcpCollection hands notes: true to the shared
  # parser): real CME print, the {place:, n:, text:} objects the field reads.
  def test_tcp_notes_objects_yield_their_text
    document = Nabu::Adapters::TcpXmlParser.new.parse(
      File.join(Nabu::TestSupport.fixtures("cme"), "texts", "tenwives.xml"),
      urn: "urn:nabu:cme:tenwives", language: "enm", notes: true
    )
    texts = document.passages.flat_map { |passage| Keys.layers(passage.annotations, Keys.specs_for("evans-tcp")) }
    assert_includes texts.map(&:last), "Every final d, g, m, n, has a curl to it, which in some cases umst meane."
  end

  DECLARED.each do |slug, keys|
    next if NO_FIXTURE.key?(slug)

    define_method(:"test_#{slug.tr('-', '_')}_declarations_match_adapter_output") do
      layers = fixture_layers(slug)
      keys.each do |key, (_fold, _field, specimen)|
        texts = layers.select { |label, _text| label == key }.map(&:last)
        refute_empty texts, "#{slug} #{key}: the real fixture yields the layer"
        assert texts.any? { |text| text.include?(specimen) },
               "#{slug} #{key}: #{specimen.inspect} among #{texts.first(3)}"
      end
    end
  end

  private

  def fixture_layers(slug)
    build, workdir = RIGS.fetch(slug)
    adapter = build.call
    adapter.discover(workdir.call).flat_map do |ref|
      adapter.parse(ref).passages.flat_map { |passage| Keys.layers(passage.annotations, Keys.specs_for(slug)) }
    rescue Nabu::DocumentSkipped
      []
    end
  end
end
