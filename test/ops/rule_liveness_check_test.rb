# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "nabu/ops/rule_liveness_check"

# The declared-rule liveness probe: a facet rule in lect_facet_rules.yml is
# inert until `nabu lect apply-rules` compiles it into the lect journal, so
# a rule can ship in config and never stage a single document (a P178 era
# rule sat uncompiled through a gate, 41 documents unstaged). The probe
# fails BY NAME on any declared rule whose source holds live documents of
# the rule's code while the journal carries zero rows of its making.
class RuleLivenessCheckTest < Minitest::Test
  RULES = <<~YAML
    rules:
      - id: live-applied
        sources: [alpha]
        code: akk
        facet: period
        map: { "Old Babylonian": "akk:ob" }
      - id: live-inert
        sources: [alpha, beta]
        code: akk
        facet: period
        map: { "Neo-Assyrian": "akk:na" }
      - id: empty-source
        sources: [gamma]
        code: sux
        facet: period
        map: { "Ur III": "sux:ur3" }
      - id: compose-applied
        kind: compose
        sources: [alpha]
        code: akk
        facet: genre
        match_prefix: CANONICAL
        variety: lit
        onto: ["akk:ob"]
  YAML

  def with_setup(rules_yaml: RULES, docs: [], journal: [])
    Dir.mktmpdir do |dir|
      rules_path = File.join(dir, "lect_facet_rules.yml")
      File.write(rules_path, rules_yaml)
      catalog_path = File.join(dir, "catalog.sqlite3")
      build_catalog(catalog_path, docs)
      journal_path = File.join(dir, "lects.sqlite3")
      build_journal(journal_path, journal)
      yield Nabu::Ops::RuleLivenessCheck.new(
        rules_paths: [rules_path], catalog_path: catalog_path, journal_path: journal_path
      ), dir
    end
  end

  def build_catalog(path, docs)
    db = Sequel.connect("sqlite://#{path}")
    db.create_table(:sources) do
      primary_key :id
      String :slug
    end
    db.create_table(:documents) do
      primary_key :id
      Integer :source_id
      String :urn
      String :language
      TrueClass :withdrawn, default: false
    end
    %w[alpha beta gamma].each { |slug| db[:sources].insert(slug: slug) }
    docs.each_with_index do |(slug, language, withdrawn), i|
      db[:documents].insert(source_id: db[:sources].first(slug: slug)[:id], urn: "urn:x:#{i}",
                            language: language, withdrawn: withdrawn || false)
    end
    db.disconnect
  end

  def build_journal(path, rows)
    db = Sequel.connect("sqlite://#{path}")
    db.create_table(:lect_assignments) do
      primary_key :id
      String :urn
      String :code
      String :lect_id
      String :basis
      String :note
    end
    rows.each { |row| db[:lect_assignments].insert(row) }
    db.disconnect
  end

  LIVE_DOCS = [%w[alpha akk], %w[beta akk]].freeze
  APPLIED = [
    { urn: "urn:x:0", code: "akk", lect_id: "akk:ob/lit", basis: "rule:live-applied",
      note: "Old Babylonian · +lit (rule:compose-applied): CANONICAL" },
    { urn: "urn:x:1", code: "akk", lect_id: "akk:na", basis: "rule:live-inert", note: "Neo-Assyrian" }
  ].freeze

  def test_every_live_rule_with_journal_rows_passes
    with_setup(docs: LIVE_DOCS, journal: APPLIED) do |check|
      report = check.run
      refute report.skipped
      assert report.clean?, report.findings.inspect
      assert_equal 4, report.rules
    end
  end

  def test_a_live_rule_with_zero_journal_rows_fails_by_name
    with_setup(docs: LIVE_DOCS, journal: [APPLIED.first]) do |check|
      report = check.run
      assert_equal 1, report.findings.size
      finding = report.findings.first
      assert_match(/declared rule live-inert \(alpha, beta\) has never produced a staging/, finding)
      assert_match(/nabu lect apply-rules --rule live-inert/, finding)
    end
  end

  def test_a_compose_rule_is_live_only_through_its_own_note_evidence
    plain = APPLIED.map { |row| row.merge(note: "plain") }
    with_setup(docs: LIVE_DOCS, journal: plain) do |check|
      findings = check.run.findings
      assert_equal 1, findings.size
      assert_match(/declared rule compose-applied \(alpha\)/, findings.first)
    end
  end

  def test_a_rule_whose_source_holds_no_live_documents_of_its_code_is_quietly_fine
    docs = LIVE_DOCS + [%w[gamma akk], ["gamma", "sux", true]]
    with_setup(docs: docs, journal: APPLIED) do |check|
      assert check.run.clean?, "gamma holds only other-code and withdrawn docs — empty-source is not yet live"
    end
  end

  def test_only_the_live_sources_are_named
    with_setup(docs: [%w[beta akk]], journal: [APPLIED.first]) do |check|
      finding = check.run.findings.find { |f| f.include?("live-inert") }
      assert_match(/live-inert \(beta\)/, finding)
    end
  end

  def test_absent_databases_are_an_announced_skip
    with_setup(docs: LIVE_DOCS) do |_check, dir|
      present = { catalog_path: File.join(dir, "catalog.sqlite3"), journal_path: File.join(dir, "lects.sqlite3") }
      %i[catalog_path journal_path].each do |missing|
        paths = present.merge(missing => File.join(dir, "absent.sqlite3"))
        report = Nabu::Ops::RuleLivenessCheck.new(
          rules_paths: [File.join(dir, "lect_facet_rules.yml")], **paths
        ).run
        assert report.skipped, "#{missing} absent — the probe skips cleanly"
        assert report.clean?
      end
    end
  end

  def test_an_absent_rules_file_is_an_announced_skip
    with_setup(docs: LIVE_DOCS) do |_check, dir|
      report = Nabu::Ops::RuleLivenessCheck.new(
        rules_paths: [File.join(dir, "absent.yml")],
        catalog_path: File.join(dir, "catalog.sqlite3"), journal_path: File.join(dir, "lects.sqlite3")
      ).run
      assert report.skipped
    end
  end
end
