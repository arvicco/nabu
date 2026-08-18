# frozen_string_literal: true

module Nabu
  module Adapters
    # The BabyLemmatizer CoNLL-U-Plus family (P77-r18, first consumer:
    # achemenet). NOT the UD shape: a `# global.columns = …` line
    # declares a custom column set (17 for achemenet: id form lemma
    # upos xpos feats head deprel deps misc eng norm lang formctx
    # xposctx score lock); documents are delimited ONLY by
    # `# <id> = <designation>` comment lines (no blank lines, no
    # sent_id/newdoc); head/deprel are dummy (root/child-1 — no real
    # syntax rides here). Token cells `_` mean absent, kept nil.
    class BabyConlluParser
      # One document block: +id+ as written (P261571 / X000428),
      # +designation+ the publication citation, +tokens+ an array of
      # {column name => value} hashes (declared columns only).
      Doc = Data.define(:id, :designation, :tokens)

      DOC_HEADER = /\A#\s+([PX]\d+)\s+=\s+(.+?)\s*\z/
      COLUMNS_HEADER = /\A#\s*global\.columns\s*=\s*(.+)\z/

      # Parse one .conllu file into Doc blocks, in file order. A file
      # without a global.columns declaration is not this format — loud.
      def parse_file(path)
        columns = nil
        docs = []
        current = nil
        File.foreach(path) do |line|
          line = line.chomp
          if (match = line.match(COLUMNS_HEADER))
            columns = match[1].split(/\s+/)
          elsif (match = line.match(DOC_HEADER))
            docs << current if current
            current = { id: match[1], designation: match[2], tokens: [] }
          elsif line.start_with?("#") || line.strip.empty?
            next
          elsif current
            raise Nabu::ParseError, "#{File.basename(path)}: token line before any global.columns" if columns.nil?

            current[:tokens] << token(line, columns)
          end
        end
        docs << current if current
        raise Nabu::ParseError, "#{File.basename(path)}: no global.columns declaration" if columns.nil?

        docs.map { |doc| Doc.new(id: doc[:id], designation: doc[:designation], tokens: doc[:tokens]) }
      end

      private

      def token(line, columns)
        cells = line.split("\t", -1)
        columns.each_with_index.with_object({}) do |(name, index), token|
          value = cells[index]
          token[name] = value unless value.nil? || value == "_" || value.empty?
        end
      end
    end
  end
end
