# frozen_string_literal: true

require "test_helper"

module MCP
  # nabu_define `root` (contract bump 2026-11-27, the CLI's `define --root`):
  # a consonantal Arabic root — Arabic, Buckwalter or DMG — answers the
  # entries Lane files under it. Real-fixture rig: Lane's sample shelf with
  # its entry facets (root keys included) built under the shipped rule.
  class ToolsRootTest < Minitest::Test
    include StoreTestDB

    LANE = Nabu::TestSupport.fixtures("lane-lexicon")

    def setup
      @catalog = class_template_db do |db|
        lane = Nabu::Store::Source.create(slug: "lane-lexicon", name: "Lane", adapter_class: "Nabu::Adapters::LaneLexicon",
                                          license_class: "attribution")
        Nabu::Store::DictionaryLoader.new(db: db, source: lane)
                                     .load_from(Nabu::Adapters::LaneLexicon.new, workdir: LANE)
        map = Nabu::FacetMap.load(File.join(Nabu::Config::PROJECT_ROOT, "config", "facet_map.yml"))
        Nabu::Store::EntryFacetBuilder.rebuild!(catalog: db, facet_map: map)
      end
    end

    def call(args) = Nabu::MCP::Tools.new(catalog: @catalog, fulltext: nil).call("nabu_define", args)
    def payload(args) = JSON.parse(call(args)[:content].fetch(0).fetch(:text))

    def test_a_root_answers_its_entries_with_the_link_facts
      answer = payload("root" => "*mr", "limit" => 2)
      assert_equal %w[*mr buckwalter ذمر strict], answer.values_at("root", "scheme", "arabic", "tier")
      assert_equal ["ذمر"], answer.fetch("headings")
      assert_equal 16, answer.fetch("total")
      assert_equal 2, answer.fetch("entries").size
      entries = answer.fetch("entries")
      assert(entries.all? { |entry| entry.fetch("dictionary") == "lane" && entry.key?("license_class") })
      assert_equal "2 of 16 entries — raise limit (max #{Nabu::MCP::Tools::DEFINE_MAX_LIMIT})", answer.fetch("note")
      assert_equal answer.fetch("entries"), payload("root" => "ḏmr", "limit" => 2).fetch("entries"), "DMG alike"
    end

    def test_misses_and_argument_errors
      miss = payload("root" => "ktb")
      assert_nil miss.fetch("tier")
      assert_empty miss.fetch("entries")
      assert_equal "no dictionary heading carries this root", miss.fetch("note")
      unmapped = payload("root" => "ʾūl")
      assert_nil unmapped.fetch("arabic")
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("root" => "rHm", "lemma" => "λόγος") }
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call({}) }
      assert_raises(Nabu::MCP::Tools::InvalidArguments) { call("root" => "rHm", "scheme" => "ipa") }
    end

    def test_the_schema_documents_root_and_scheme
      keys = Nabu::MCP::Tools::DEFINE_SCHEMA.fetch(:properties).keys
      assert_equal %i[lemma lang limit lect facets root scheme include_restricted], keys
    end
  end
end
