# frozen_string_literal: true

require "test_helper"

# The divinum-officium-txt parser family against real upstream files
# (test/fixtures/divinum-officium/web/www/...): the file-local grammar of
# Divinum Officium's data format — sections, conditionals, @-references
# preserved verbatim and never resolved, the three passage layouts.
class DivinumOfficiumParserTest < Minitest::Test
  LATIN = File.join(Nabu::TestSupport.fixtures("divinum-officium"), "web", "www")
  PARSER = Nabu::Adapters::DivinumOfficiumParser

  def parse(rel, layout: :sections)
    PARSER.new.parse(File.join(LATIN, rel), urn: "urn:test:#{rel}", layout: layout)
  end

  def passage(document, key)
    document.find { |p| p.urn == "#{document.urn}:#{key}" } || flunk("no passage #{key} in #{document.urn}")
  end

  # --- sections ------------------------------------------------------------------

  def test_sections_become_passages_and_officium_the_title
    agnes = parse("horas/Latin/Sancti/01-21.txt")
    assert_equal "S. Agnetis Virginis et Martyris", agnes.title
    assert_equal "lat", agnes.language
    assert_equal 21, agnes.size
    assert_equal(%w[Officium Ant_1 Oratio Ant_Matutinum], agnes.first(4).map { |p| p.urn.split(":").last })
    assert_equal "S. Agnetis Virginis et Martyris", passage(agnes, "Officium").text
    assert_equal "Ant 1", passage(agnes, "Ant_1").annotations["section"], "the header name rides verbatim"
  end

  def test_rank_and_rule_are_machine_data_never_passages
    agnes = parse("horas/Latin/Sancti/01-21.txt")
    refute(agnes.any? { |p| p.urn.end_with?(":Rank", ":Rule") })
    rank = agnes.metadata.fetch("rank").first
    assert_equal ";;Duplex;;3;;vide C6-1", rank["lines"].first
    assert_includes rank["lines"], "(sed rubrica cisterciensis)", "the variants and their conditions ride whole"
    assert_equal "Duplex", agnes.metadata["rank_class"], "the unconditioned class is the facet value"
    assert_equal ["vide C6-1;", "9 lectiones", "Psalm5 Vespera=116", "Psalm5 Vespera3=147",
                  "in 1 Nocturno Lectiones ex Commune in 2 loco"], agnes.metadata["rule"].first["lines"]
  end

  def test_name_section_is_machine_data
    florian = parse("horas/Latin/Sancti/Bavaria/Passaviensis/05-04-Florianus.txt")
    assert_equal ["Floriáni", "Postcommunio=Floriáno"], florian.metadata["name"].first["lines"]
    refute(florian.any? { |p| p.urn.end_with?(":Name") })
  end

  def test_rubrics_stay_in_the_text_and_calls_ride_annotations
    agnes = parse("horas/Latin/Sancti/01-21.txt")
    lectio = passage(agnes, "Lectio4")
    assert lectio.text.start_with?("Ex libro S. Ambrósii Epíscopi de Virgínibus\nLiber 1, post initium\nHódie natális")
    assert_equal ["Liber 1, post initium"], lectio.annotations["rubrics"]
    oratio = passage(agnes, "Oratio")
    assert_equal ["$Per Dominum"], oratio.annotations["calls"]
    refute_includes oratio.text, "$Per", "a call is a directive, not text"
    assert_equal ["&Gloria"], passage(agnes, "Responsory3").annotations["calls"]
  end

  def test_reference_only_sections_mint_no_passage_and_ride_metadata_verbatim
    agnes = parse("horas/Latin/Sancti/01-21.txt")
    assert_equal({ "Ant Vespera" => ["@:Ant Laudes"], "Versum 0" => ["@Commune/C6::s/N\\./Agnes/"],
                   "Capitulum Laudes" => ["@Commune/C7"] }, agnes.metadata["reference_sections"])
    refute(agnes.any? { |p| p.urn.end_with?(":Ant_Vespera") })
  end

  def test_whole_file_inheritance_and_conditioned_repeat_sections
    c10a = parse("horas/Latin/Commune/C10a.txt")
    assert_equal ["@Commune/C10"], c10a.metadata["inherits"]
    assert_equal ["@Commune/C12:Oratio 2"], c10a.metadata["reference_sections"]["Oratio"]
    assert_equal ["@Commune/C12:Oratio 2:1", "$Per eundem"],
                 c10a.metadata["reference_sections"]["Oratio (ad missam)"], "a conditioned repeat keeps its condition"
    introitus = passage(c10a, "Introitus")
    assert_equal ["Is 45:8", "Ps 84:2"], introitus.annotations["rubrics"]
    assert_equal ["&Gloria"], introitus.annotations["calls"]
  end

  def test_conditionals_are_directives_and_header_conditions_ride_the_passage
    hildegard = parse("horas/Latin/SanctiM/09-17M.txt")
    officium = passage(hildegard, "Officium")
    assert_equal "S Hildegardis Virginum O. N.\nS. Hildegardis, Virginis (1965)", officium.text,
                 "both variants stay; the conditional line between them is a directive"
    assert_equal ["(sed rubrica cisterciensis)"], officium.annotations["conditions"]
    assert_equal "S Hildegardis Virginum O. N.", hildegard.title
    assert_equal "(nisi rubrica cisterciensis)", passage(hildegard, "Ant_2").annotations["condition"]
    assert_equal "Simplex", hildegard.metadata["rank_class"]
  end

  def test_capitalized_parentheticals_are_text
    ordo = parse("missa/Latin/Ordo/Ordo.txt")
    incipit = passage(ordo, "Incipit")
    assert_includes incipit.text, "(Osculatur Altare in medio) quorum relíquiæ hic sunt"
    refute incipit.annotations.key?("conditions")
  end

  def test_crlf_files_parse_clean
    antonius = parse("horas/Latin/Sancti/Brasilia/06-13.txt")
    assert_equal "Sancti Antonii de Padua Confessoris et Ecclesiae Doctoris", antonius.title
    antonius.each { |p| refute_includes p.text, "\r" }
  end

  def test_an_inclusion_stub_is_declined_by_rule
    assert_raises(Nabu::DocumentSkipped) { parse("horas/Latin/CommuneCist/C10c.txt") }
    refute PARSER.own_text?(File.join(LATIN, "horas/Latin/SanctiM/08-18bmv.txt")),
           "@-references between bare ';;' antiphon slots carry no own text"
    assert PARSER.own_text?(File.join(LATIN, "horas/Latin/Sancti/01-21.txt"))
  end

  # --- header-less layouts --------------------------------------------------------

  def test_ordo_headings_segment_a_header_less_file
    ordo = parse("missa/Latin/Ordo/Ordo.txt")
    assert_equal(%w[Incipit Incensatio], ordo.map { |p| p.urn.split(":").last })
    assert_equal({ "preamble" => ["&Vidiaquam"], "Introitus" => ["&introitus"] },
                 ordo.metadata["reference_sections"])
    incipit = passage(ordo, "Incipit")
    assert incipit.text.start_with?("Sacerdos paratus cum ingreditur ad Altare")
    assert_equal ["!*D", "!*&Introibo", "!*S"], incipit.annotations["directives"]
  end

  def test_psalm_verses_layout
    psalm = parse("horas/Latin/Psalterium/Psalmorum/Psalm1.txt", layout: :verses)
    assert_equal(%w[1.1 1.2 1.3a 1.3b 1.4 1.5 1.6], psalm.map { |p| p.urn.split(":").last })
    verse = passage(psalm, "1.3a")
    assert_equal "Et erit tamquam lignum, quod plantátum est secus decúrsus aquárum, * quod fructum suum dabit " \
                 "in témpore suo:", verse.text
    assert_equal "1:3a", verse.annotations["verse"]
  end

  def test_necrology_layout_days_and_entry_years
    necrology = parse("horas/Latin/Necrologium/Januarius.txt", layout: :necrology)
    assert_equal(%w[1 2], necrology.map { |p| p.urn.split(":").last })
    day = passage(necrology, "1")
    assert day.text.start_with?("Die 1. mensis januarii pie in Domino obdormierunt:")
    assert_equal [1531, 1746, 1760, 1764, 1789, 1793, 1808, 1816, 1887, 1947, 1948], day.annotations["entry_years"]
  end

  def test_unknown_layout_is_loud
    assert_raises(ArgumentError) { parse("horas/Latin/Sancti/01-21.txt", layout: :chapters) }
  end
end
