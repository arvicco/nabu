# frozen_string_literal: true

require "test_helper"

module Query
  # Nabu::Query::DictionaryLanguage (P153): the dictionary-keying folds.
  # The define tests cover the filter end-to-end over real GPC and OSHB
  # lexicon fixtures; these pin the spelling closure itself.
  class DictionaryLanguageTest < Minitest::Test
    # Languages.code_variants deliberately stays one-directional, but GPC
    # STORES the two-letter "cy" while the held Welsh text keys "wel" and
    # "cym": the lookup codes are the symmetric closure.
    def test_codes_fold_both_sides_including_the_two_letter_tag
      %w[cy cym wel].each do |code|
        assert_equal %w[cy cym wel], Nabu::Query::DictionaryLanguage.codes(code).sort, "from #{code}"
      end
      assert_equal %w[bo bod tib], Nabu::Query::DictionaryLanguage.codes("bod").sort
      assert_equal %w[ice is isl], Nabu::Query::DictionaryLanguage.codes("isl").sort
    end

    def test_codes_pass_unknown_codes_through_and_nil_folds_to_nothing
      assert_equal ["egy"], Nabu::Query::DictionaryLanguage.codes("egy")
      assert_equal [], Nabu::Query::DictionaryLanguage.codes(nil)
    end

    def test_code_variants_stays_one_directional_for_passage_filters
      assert_equal %w[cym wel], Nabu::Languages.code_variants("wel").sort
    end

    # The define gate must accept every spelling the filter can answer —
    # before this, `--lang wel` and `--lang arc` were rejected at
    # validation while the filter itself would have found their entries.
    def test_held_accepts_a_spelling_variant_of_a_shelf_language
      db = Sequel.sqlite
      db.create_table(:dictionary_entries) { String :annotations_json }
      assert Nabu::Query::DictionaryLanguage.held?(db, "wel", ["cy"])
      assert Nabu::Query::DictionaryLanguage.held?(db, "cym", ["cy"])
      refute Nabu::Query::DictionaryLanguage.held?(db, "arc", ["cy"])
    end

    def test_held_accepts_an_annotation_level_language
      db = Sequel.sqlite
      db.create_table(:dictionary_entries) { String :annotations_json }
      db[:dictionary_entries].insert(annotations_json: JSON.generate("language" => "arc"))
      assert Nabu::Query::DictionaryLanguage.held?(db, "arc", ["hbo"])
      refute Nabu::Query::DictionaryLanguage.held?(db, "syc", ["hbo"])
    end
  end
end
