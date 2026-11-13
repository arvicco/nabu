# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::DharmaEpidocParser — the undetermined-language lane (the
# und-admission ruling, 2026-11-13). An adapter that opts in
# (admit_undetermined: true) admits real text whose upstream tag is
# missing, "und" or "unknown"(-Script) as language "und" — searchable, no
# language claim — with upstream's raw tag kept where it differs. Without
# the opt-in the family stance holds (quarantine), and a tag that is NOT a
# declaration of undetermined language (the "languageb-Latn" template bug)
# quarantines either way. The per-adapter specimens are real upstream
# files (dharma-nusantara, dharma-javanese-texts, dharma-deccan,
# sii-clean); this file pins the shared rule on the synthetic minimum and
# the no-lect-claim half against the house config.
class DharmaEpidocParserTest < Minitest::Test
  Parser = Nabu::Adapters::DharmaEpidocParser
  ALLOWED = %w[kaw-Latn san-Latn].freeze
  UND_SOURCES = %w[sii-clean dharma-nusantara dharma-javanese-texts dharma-deccan].freeze

  def edition(lang_attr, inner_lang: nil)
    inner = inner_lang ? %( xml:lang="#{inner_lang}") : ""
    xml = <<~XML
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><text><body>
        <div type="edition"#{lang_attr}><p#{inner}><lb n="1"/>real text here</p></div>
      </body></text></TEI>
    XML
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!
    doc
  end

  def parse(doc, admit: true)
    Parser.parse_doc(doc, path: "DHARMA_INSProbe.xml", allowed_languages: ALLOWED,
                          admit_undetermined: admit)
  end

  def test_undetermined_tags_are_recognized_and_nothing_else
    [nil, "", "und", "und-Latn", "unknown", "unknown-Latn"].each do |tag|
      assert Parser.undetermined_tag?(tag), "#{tag.inspect} declares no language"
    end
    %w[languageb-Latn kaw-Latn thai-Thai Und unknown-latin].each do |tag|
      refute Parser.undetermined_tag?(tag), "#{tag.inspect} is not an undetermined declaration"
    end
  end

  def test_a_lang_less_edition_admits_as_und_with_no_raw_tag
    result = parse(edition(""))
    assert_equal "und", result.language
    assert_nil result.language_raw, "no upstream tag to keep"
    assert_equal ["und"], result.passages.map(&:language).uniq
  end

  def test_an_und_edition_admits_and_needs_no_raw_tag
    result = parse(edition(' xml:lang="und"'))
    assert_equal "und", result.language
    assert_nil result.language_raw, "the raw tag IS und — nothing differs"
  end

  def test_an_unknown_script_tag_admits_as_und_keeping_the_raw_tag
    result = parse(edition(' xml:lang="unknown-Latn"'))
    assert_equal "und", result.language
    assert_equal "unknown-Latn", result.language_raw
  end

  def test_an_inner_undetermined_tag_reads_the_raw_from_the_minted_unit
    result = parse(edition("", inner_lang: "unknown-Latn"))
    assert_equal "und", result.language
    assert_equal "unknown-Latn", result.language_raw
  end

  def test_a_held_code_is_untouched_and_carries_no_raw_tag
    result = parse(edition(' xml:lang="kaw-Latn"'))
    assert_equal "kaw-Latn", result.language
    assert_nil result.language_raw
  end

  def test_the_template_bug_quarantines_even_when_undetermined_admits
    error = assert_raises(Nabu::ParseError) { parse(edition(' xml:lang="languageb-Latn"')) }
    assert_match(/languageb-Latn/, error.message)
  end

  def test_without_the_opt_in_undetermined_still_quarantines
    error = assert_raises(Nabu::ParseError) { parse(edition(' xml:lang="und"'), admit: false) }
    assert_match(/"und"/, error.message)
    error = assert_raises(Nabu::ParseError) { parse(edition(""), admit: false) }
    assert_match(/code nil/, error.message)
  end

  # -- no language claim: "und" lands on no registry node --------------------

  def test_und_resolves_to_no_registry_lect
    registry = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                                overrides_path: File.join(Nabu::Config::PROJECT_ROOT, "config",
                                                          "lect_overrides.yml"))
    UND_SOURCES.each do |slug|
      assert_equal "und", registry.resolve("und", source: slug), "#{slug}: und stays the bare non-claim"
    end
    assert_nil registry.lect("und"), "the registry defines no und anchor — no facet node to claim"
  end

  def test_no_house_rule_or_override_claims_und_for_these_sources
    rules = Nabu::LectRules.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_facet_rules.yml"))
    claiming = rules.rules.select { |rule| rule.code == "und" && rule.sources.intersect?(UND_SOURCES) }
    assert_empty claiming.map(&:id), "no facet rule lifts the undetermined lane onto a lect"
    overrides = YAML.safe_load_file(File.join(Nabu::Config::PROJECT_ROOT, "config", "lect_overrides.yml"))
    rows = (overrides["sources"] || {}).slice(*UND_SOURCES).select { |_slug, codes| (codes || {}).key?("und") }
    assert_empty rows, "no per-source override reads und as a language"
  end
end
