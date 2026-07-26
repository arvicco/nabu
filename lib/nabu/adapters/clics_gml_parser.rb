# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module Adapters
    # The clics-gml parser family (P46-6): a dependency-free reader for the
    # CLICS³ released network artifact — a GML (Graph Modelling Language)
    # file whose machine-emitted shape is rigidly line-based:
    #
    #   graph [
    #     node [
    #       id 1855
    #       ID "2264"            (= label = ConcepticonId)
    #       Gloss "DAUGHTER-IN-LAW (OF WOMAN)"
    #       Semanticfield "Kinship"
    #       Category "Person/Thing"
    #       FamilyFrequency 54   LanguageFrequency 295  WordFrequency 359
    #       Words "…"            (the per-word attestation list — skipped)
    #     ]
    #     edge [
    #       source 1855
    #       target 2550
    #       families "Atlantic-Congo;…"   (the family-aware lane — kept)
    #       words/languages/wofam "…"     (the bulk lists — skipped)
    #       WordWeight 8  FamilyWeight 6  LanguageWeight 7
    #     ]
    #   ]
    #
    # One attribute per line, values either bare integers or one-line
    # double-quoted strings — so a full GML grammar would be a parser for
    # shapes the artifact never emits (the lila line-parser posture; no new
    # gem). The heavy list attributes are recognized and skipped by NAME so
    # the aggregate scope is explicit, not accidental.
    class ClicsGmlParser
      Node = Data.define(:id, :concepticon_id, :gloss, :semantic_field, :category,
                         :family_frequency, :language_frequency, :word_frequency)
      Edge = Data.define(:source, :target, :families,
                         :family_weight, :language_weight, :word_weight)
      Result = Data.define(:nodes, :edges)

      ATTRIBUTE = /\A(\w+)\s+(?:"(.*)"|(-?\d+))\z/

      # The bulk attestation lists the aggregate grain deliberately drops
      # (class note): recognized by name so a future rename is loud.
      SKIPPED = %w[Words Languages Families words languages wofam].freeze

      def read(path)
        nodes = []
        edges = []
        block = nil
        attrs = nil
        File.open(path, "r:UTF-8") do |io|
          io.each_line do |line|
            stripped = line.strip
            case stripped
            when "node [", "edge [" then (block = stripped.split.first) && (attrs = {})
            when "]"
              flush!(block, attrs, nodes, edges, path)
              block = nil
            else collect(attrs, stripped) if block
            end
          end
        end
        Result.new(nodes: nodes, edges: edges)
      end

      private

      def collect(attrs, stripped)
        match = ATTRIBUTE.match(stripped) or return
        key = match[1]
        return if SKIPPED.include?(key)

        attrs[key] = match[2] || Integer(match[3])
      end

      def flush!(block, attrs, nodes, edges, path)
        case block
        when "node" then nodes << build_node(attrs, path)
        when "edge" then edges << build_edge(attrs, path)
        end
      end

      def build_node(attrs, path)
        concepticon = attrs["ConcepticonId"] || attrs["ID"] || attrs["label"]
        gloss = attrs["Gloss"]
        unless attrs["id"] && concepticon && gloss
          raise Nabu::ParseError, "clics-gml: #{path}: node missing id/ConcepticonId/Gloss " \
                                  "(got #{attrs.keys.sort.inspect})"
        end

        Node.new(id: attrs.fetch("id"), concepticon_id: concepticon.to_s, gloss: gloss,
                 semantic_field: attrs["Semanticfield"], category: attrs["Category"],
                 family_frequency: attrs["FamilyFrequency"],
                 language_frequency: attrs["LanguageFrequency"],
                 word_frequency: attrs["WordFrequency"])
      end

      def build_edge(attrs, path)
        unless attrs["source"] && attrs["target"]
          raise Nabu::ParseError, "clics-gml: #{path}: edge missing source/target"
        end

        Edge.new(source: attrs.fetch("source"), target: attrs.fetch("target"),
                 families: attrs["families"].to_s.split(";").map(&:strip).reject(&:empty?),
                 family_weight: attrs["FamilyWeight"], language_weight: attrs["LanguageWeight"],
                 word_weight: attrs["WordWeight"])
      end
    end
  end
end
