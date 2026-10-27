# frozen_string_literal: true

require "json"

require_relative "types"
require_relative "align_hub"
require_relative "../lemma_keys"
require_relative "../query/morph_facets"

module Nabu
  module Export
    # `nabu export align` (P145): verse pairs off the alignment hub (§10) —
    # per attested ref, the BASE witness paired with every other witness
    # that attests the ref. The base is the registry's first witness (the
    # curated display order — Align's and Collation's convention) unless
    # --base names one; a ref the base does not attest yields no pairs and
    # is counted (refs_without_base), never re-anchored on another witness,
    # so every pair in a file shares one pivot. --witness narrows the other
    # side. Pairs, not N-way rows, because a parallel-corpus consumer (an
    # aligner, a translation-equivalence study) reads source↔target.
    #
    # Each side carries its passage urns, its text, the refs its sentences
    # cover (sentence≠verse: a PROIEL sentence spanning a verse boundary
    # says so in *_covers, as `nabu align` labels it), its source and its
    # EFFECTIVE license class; the pair draws on both sides, so under
    # --license-class it survives only when both classes are allowed.
    #
    # == --with-morph: gold tokens only
    #
    # Each side gains *_tokens — the stored upstream tokens of its sentences,
    # in order, each {form, lemma, feats, citation}: lemma through the
    # per-source key registry (LemmaKeys), feats the token's morphology
    # DECODED through the morph façade (Query::MorphFacets — PROIEL/AGDT
    # positional tags, UD feats, the Hebrew and Coptic tagsets, one UD-named
    # vocabulary, rendered `person=3|number=plur|…`), citation the token's
    # own citation_part where the treebank stores one (how a consumer trims
    # a verse-spanning sentence to the verse). Absent values are null.
    # *_morph is "gold" when any token carries a lemma or decodable
    # features, else null — a form-only witness (a verse-grain CTS edition)
    # claims nothing. Silver (machine) lemmas are NOT carried: they live in
    # the enrichment lane, outside the stored annotations this reads.
    class AlignPairs
      NAME = "align"
      SUMMARY = "Verse pairs off the alignment hub: per attested ref, the base witness against every other " \
                "attesting witness, each side with urns, text, source and license (with --with-morph, the " \
                "gold tokens with lemma and decoded morphology)"

      SIDES = { "base" => "the base (pivot) witness", "witness" => "the paired witness" }.freeze

      def self.side_columns(side, about)
        [Column.new(name: side == "base" ? "base_witness" : "witness", description: "#{about}'s registry label"),
         Column.new(name: "#{side}_document_urn", description: "#{about}'s document urn (the book that attests)"),
         Column.new(name: "#{side}_urns", description: "#{about}'s passage urns for the ref, |-joined, in order"),
         Column.new(name: "#{side}_covers",
                    description: "every ref #{about}'s sentences cover, |-joined (more than the ref = a " \
                                 "sentence spanning a verse boundary)"),
         Column.new(name: "#{side}_language", description: "#{about}'s document language"),
         Column.new(name: "#{side}_text", description: "#{about}'s sentence text(s), space-joined, as stored"),
         Column.new(name: "#{side}_source", description: "#{about}'s source slug"),
         Column.new(name: "#{side}_license_class", description: "#{about}'s effective license class")]
      end

      COLUMNS = ([Column.new(name: "work", description: "alignment work id (config/alignments.yml)"),
                  Column.new(name: "ref", description: "the normalized citation both sides attest")] +
                 SIDES.flat_map { |side, about| side_columns(side, about) }).freeze

      MORPH_COLUMNS = SIDES.flat_map do |side, about|
        [Column.new(name: "#{side}_morph",
                    description: "gold when #{about}'s tokens carry a lemma or decodable morphology, else null"),
         Column.new(name: "#{side}_tokens",
                    description: "#{about}'s stored tokens in order, each {form, lemma, feats (UD-named, " \
                                 "decoded), citation}; null values where the source has none")]
      end.freeze

      def initialize(catalog:, fulltext:, registry:, ref: nil, work: nil, base: nil, witnesses: nil,
                     with_morph: false)
        @catalog = catalog
        @hub = AlignHub.new(catalog: catalog, fulltext: fulltext, registry: registry, ref: ref, work: work)
        @base = base.to_s.strip.empty? ? nil : base.to_s.strip
        @witnesses = Array(witnesses).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        @witnesses = nil if @witnesses.empty?
        @with_morph = with_morph
        @refs = 0
        @without_base = 0
      end

      def columns = @with_morph ? COLUMNS + MORPH_COLUMNS : COLUMNS

      def filters
        { "ref" => @hub.scope, "base" => @base, "witness" => @witnesses, "with_morph" => @with_morph }
      end

      def notes = { "refs" => @refs, "refs_without_base" => @without_base }

      # +license_classes+ is enforced by the frame (both sides' classes).
      def each_row(license_classes: nil)
        _ = license_classes
        @hub.each_group(on_work: ->(work) { validate_labels!(work) }) do |group|
          @refs += 1
          attesting = group.witnesses.select { |witness| witness.status == :ok }
          base = attesting.find { |witness| witness.label == @base_label }
          next @without_base += 1 unless base

          others = attesting.reject { |witness| witness.equal?(base) }.select { |witness| wanted?(witness) }
          tokens = @with_morph ? tokens_by_urn([base, *others]) : {}
          others.each { |witness| yield build(@hub.work, group.ref, base, witness, tokens) }
        end
      end

      private

      # The base label (the registry's first witness by default) and every
      # --witness must name a witness of the resolved work.
      def validate_labels!(work)
        @base_label = (@base ? registry_witness(work, @base) : work.witnesses.first).label
        @witness_labels = @witnesses&.map { |wanted| registry_witness(work, wanted).label }
      end

      def registry_witness(work, wanted)
        work.witnesses.find { |witness| AlignHub.witness_match?(witness, wanted) } ||
          raise(Error, "no witness #{wanted.inspect} in work #{work.id} — witnesses: " \
                       "#{work.witnesses.map(&:label).join(', ')}")
      end

      def wanted?(witness) = @witness_labels.nil? || @witness_labels.include?(witness.label)

      def build(work, ref, base, witness, tokens)
        values = [work.id, ref, *side(base), *side(witness)]
        values.concat(morph(base, tokens) + morph(witness, tokens)) if @with_morph
        Row.new(values: values,
                draws: [[base.source_slug, base.license_class], [witness.source_slug, witness.license_class]])
      end

      def side(witness)
        sentences = witness.sentences
        [witness.label, witness.document_urn, sentences.map(&:urn).join("|"),
         sentences.flat_map(&:refs).uniq.join("|"), witness.language, sentences.map(&:text).join(" "),
         witness.source_slug, witness.license_class]
      end

      def morph(witness, tokens)
        list = witness.sentences.flat_map { |sentence| tokens.fetch(sentence.urn, []) }
        gold = list.any? { |token| token["lemma"] || token["feats"] }
        [gold ? "gold" : nil, list]
      end

      # { passage urn => [token hash] } for the group's sentences — one
      # batched catalog read.
      def tokens_by_urn(witnesses)
        slugs = {}
        witnesses.each { |witness| witness.sentences.each { |sentence| slugs[sentence.urn] = witness.source_slug } }
        @catalog[:passages].where(urn: slugs.keys).select_hash(:urn, :annotations_json).to_h do |urn, json|
          [urn, decode(json, slugs[urn])]
        end
      end

      def decode(json, slug)
        tokens = json ? JSON.parse(json)["tokens"] : nil
        return [] unless tokens.is_a?(Array)

        spec = LemmaKeys.spec_for(slug)
        tokens.grep(Hash).map do |token|
          feats = Query::MorphFacets.describe(token, source: slug)
          { "form" => token["form"], "lemma" => LemmaKeys.lemmas(token, spec).first,
            "feats" => feats.empty? ? nil : feats, "citation" => token["citation_part"] }
        end
      end
    end
  end
end
