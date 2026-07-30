# frozen_string_literal: true

require_relative "adapters/asl_parser"

module Nabu
  # A pure READ seam over the Oracc Sign List (P53-1): given an OSL-spelled
  # value (reading) return the candidate sign record(s), and given a sign
  # name or @aka alias return the record — the CldfSpine/Lila feature-module
  # posture. There is NO catalog table and NO migration: osl is a feature
  # module (kind: module) whose canonical asset is the one ASL file landed
  # by `nabu sync osl` under canonical/osl/00lib/osl.asl, parsed by
  # Nabu::Adapters::AslParser. First consumer: the P53-2 `nabu signs`
  # surface (ATF transliteration → signs with Unicode codepoints, for the
  # Edubba downstream).
  #
  # The API contract P53-2 builds on:
  #
  #   lookup(value, language: nil)  OSL-spelled value → ALL candidate
  #                                 records in file order (deterministic
  #                                 single hit for unambiguous values;
  #                                 ambiguity — upstream idₓ lives on six
  #                                 signs — returns every candidate, never
  #                                 one silently). %lang-qualified values
  #                                 pass only a matching language: filter;
  #                                 unqualified values pass every filter.
  #                                 Deprecated values still resolve (texts
  #                                 transliterated with them exist).
  #   sign(name)                    sign name → record, falling back to
  #                                 @aka aliases, then variant-form names
  #                                 (uppercase-logogram and valueₓ(SIGN)
  #                                 resolution).
  #
  # Candidates are AslParser::SignRecord values: name, codepoints (single
  # or sequence, or nil = honestly unencoded), rendered ucun string where
  # present, oid. A value found on a variant @form yields the FORM record
  # itself — it carries its own encoding. NOTE the C-ATF ASCII→Unicode fold
  # (u2→u₂, sz→š, …) is the P53-2 tokenizer's concern: this seam looks up
  # values exactly as OSL spells them.
  class SignList
    ASL_FILE = File.join("00lib", "osl.asl")
    SLUG = "osl"

    # Build a sign list from an osl.asl-shaped file.
    def self.load(path)
      new(Nabu::Adapters::AslParser.new.parse_file(path))
    end

    # Feature-detect the sign list from the owner's canonical tree: nil when
    # `nabu sync osl` has not landed the file, so a corpus without the sign
    # list behaves byte-identically (the lila posture). The parse (~979 KB
    # upstream) is memoized per path; reset! clears the cache (tests).
    def self.load_default(config: Nabu::Config.load)
      path = File.join(config.canonical_dir, SLUG, ASL_FILE)
      return nil unless File.file?(path)

      (@cache ||= {})[path] ||= load(path)
    end

    def self.reset!
      @cache = nil
    end

    def initialize(result)
      @result = result
      @by_value = Hash.new { |hash, key| hash[key] = [] }
      @by_name = {}
      @by_aka = {}
      @by_form_name = {}
      index(result.signs)
    end

    # OSL-spelled value → every candidate record, in file order. With a
    # +language:+ filter, a candidate matched only through %lang-qualified
    # values must match the filter; unqualified values pass any filter.
    def lookup(value, language: nil)
      candidates = @by_value[value.to_s]
      return candidates.map(&:first).uniq if language.nil?

      candidates.select { |_record, qualifier| qualifier.nil? || qualifier == language }
                .map(&:first).uniq
    end

    # Sign name → record, then @aka alias, then variant-form name. Top-level
    # signs win over forms (upstream reuses sign names as form names).
    def sign(name)
      key = name.to_s
      @by_name[key] || @by_aka[key] || @by_form_name[key]
    end

    # Top-level signs only (forms are reachable via their parent records
    # and the name/value indexes).
    def sign_count = @result.signs.size

    private

    def index(signs)
      signs.each do |record|
        @by_name[record.name] ||= record
        record.aka.each { |alias_name| @by_aka[alias_name] ||= record }
        index_values(record)
        record.forms.each do |form|
          @by_form_name[form.name] ||= form
          index_values(form)
        end
      end
    end

    def index_values(record)
      values = record.values
      values.each do |value|
        @by_value[value.value] << [record, value.language]
      end
    end
  end
end
