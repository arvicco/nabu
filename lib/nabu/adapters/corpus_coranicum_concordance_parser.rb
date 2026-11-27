# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"

module Nabu
  module Adapters
    # One sura file of the Corpus Coranicum concordance
    # (data/quran_concordance/suraNNN.xml, the family corpus-coranicum-tei):
    # Rafael Talmon's grammatical parse of every word of the Qurʾān as
    # edited by the project, one <w> per ANALYSIS, each a flat run of
    # <seg type="…"> fields (body > div > ab > w > seg; no ids — the row
    # names its word by its sura / verse / word_number segs).
    #
    # Returns {[verse, word number] => [row …]} in file order, a row being
    # {seg type => decoded text} ("" for an empty seg). The seg vocabulary
    # is CLOSED (SEGMENTS, the 43 types every row of all 114 files carries,
    # census 2026-11-27): an unknown type is a ParseError, as is a row of
    # another sura or one without a numeric verse / word_number — the join
    # to the Cairo words is exact or loud, never guessed. Streamed with
    # Nokogiri::XML::Reader over the belt-read string (sura002.xml is
    # 15 MB).
    class CorpusCoranicumConcordanceParser
      SEGMENTS = %w[
        sura verse word_number word_rafi_talmon word_corpus_coranicum analysis_number
        base_rafi_talmon base_corpus_coranicum root_rafi_talmon root_corpus_coranicum
        analyse_prefix1 analyse_prefix1_part_of_speech analyse_prefix1_semantic
        analyse_prefix2 analyse_prefix2_part_of_speech analyse_prefix2_semantic
        analyse_prefix3 analyse_prefix3_part_of_speech analyse_prefix3_semantic
        analyse_part_of_speech analyse_subcategory analyse_semantic analyse_semantic2
        analyse_pattern analyse_aspect analyse_actpass analyse_mortality analyse_mood
        analyse_prefix analyse_gender analyse_number analyse_casefld analyse_person
        analyse_dependent_pron analyse_dependent_person analyse_dependent_number
        analyse_dependent_gender analyse_definite analyse_diptotic analyse_full_analyse
        created_at updated_at
      ].freeze

      NUMBER = /\A\d+\z/
      private_constant :NUMBER

      READER = Nokogiri::XML::Reader
      private_constant :READER

      # +sura+: the sura the file must hold (its file name's number).
      def analyses(path, sura:)
        rows = Hash.new { |hash, key| hash[key] = [] }
        each_row(path) do |row|
          rows[key_of(row, path, sura)] << row
        end
        rows.default_proc = nil
        rows
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      private

      def each_row(path)
        row = nil
        field = nil
        Nokogiri::XML::Reader(SourceRead.utf8_file(path, label: "corpus-coranicum concordance"), path).each do |node|
          case node.node_type
          when READER::TYPE_ELEMENT
            case node.local_name
            when "w" then row = {}
            when "seg"
              raise ParseError, "#{path}: a <seg> outside any <w>" if row.nil?

              field = seg_type(node, path)
              row[field] = +""
              field = nil if node.empty_element?
            end
          when READER::TYPE_END_ELEMENT
            case node.local_name
            when "seg" then field = nil
            when "w"
              yield row.transform_values(&:strip)
              row = nil
            end
          when READER::TYPE_TEXT, READER::TYPE_CDATA
            row[field] << node.value if row && field
          end
        end
      end

      def seg_type(node, path)
        type = node.attribute("type").to_s
        return type if SEGMENTS.include?(type)

        raise ParseError, "#{path}: unknown concordance segment type #{type.inspect}"
      end

      def key_of(row, path, sura)
        sura_s, verse, word = row.values_at("sura", "verse", "word_number")
        unless [sura_s, verse, word].all? { |value| NUMBER.match?(value.to_s) }
          raise ParseError, "#{path}: a row without its sura/verse/word_number " \
                            "(#{row.slice('sura', 'verse', 'word_number')})"
        end
        raise ParseError, "#{path}: a row of sura #{sura_s} in the file of sura #{sura}" unless sura_s.to_i == sura

        [verse.to_i, word.to_i]
      end
    end
  end
end
