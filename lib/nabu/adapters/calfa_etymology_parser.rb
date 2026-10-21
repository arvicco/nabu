# frozen_string_literal: true

require "nokogiri"
require "stringio"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # Parser for Calfa's Ačaṙean etymology file (the `calfa-etymology`
    # family): etymology/etymology01.xml in calfa-co/lexical-databases — a
    # "working document, AI processed" (upstream README) of Hr. Ačaṙean,
    # Hayerēn armatakan baṙaran (Erevan, 1926). 12.9 MB, so it streams
    # (Nokogiri::XML::Reader, one small DOM per <entry> — the no-DOM-over-
    # 5MB rule). Census 2026-10-21 at upstream 71109ce: 11,326 <entry>
    # elements, never nested, children in document order:
    #
    #   <headword>        11,326 — Ačaṙean's capitals; "*" (3,762) and "+"
    #                     (504) lead marks, " կամ " ("or") variant forms
    #                     (409); 10,989 distinct (duplicates are homographs)
    #   <content>         11,323 — meaning in «…» + attestations
    #   <egal>             4,787 — the etymology, opening with Ačaṙean's "="
    #   <indent_content>   7,440 — earlier explanations / literature
    #   <ԳՒՌ>              2,661 — dialect forms ("ԳՒՌ.-…")
    #   <ՓՈԽ>              1,061 — loans out of Armenian ("ՓՈԽ.-…")
    #   <other_pox/>, <indent/>  1 each — EMPTY page-break marks
    #
    # == Etymology shape — why no reflex rows
    #
    # The etymologies are PROSE: language abbreviations in Armenian
    # ("ասոր.", "եբր.", "արաբ."), forms in Latin transliteration, and the
    # AI-processing placeholders "[arabic word]" / "[hebrew word]" /
    # "[syriac word]" / "[ethiopian word]" where the print had a non-Latin
    # script (7,880 of them). No element types a relation (inherited /
    # borrowed / donor language), so nothing maps onto the reflex/etymon
    # store (DictionaryReflex ETYMON_RELATIONS) without inventing it; the
    # whole text rides the entry body, every section in upstream order.
    # What the "*" and "+" marks mean is not stated upstream — recorded
    # verbatim as annotations.headword_mark, never interpreted.
    #
    # == Entry shape
    #
    # entry_id = the headword verbatim, whitespace runs as "_" (+ occurrence
    # suffix — the monlam idiom); key_raw = the headword; headword = the
    # headword (marks and variants on display); headword_folded = the FIRST
    # form, marks stripped, folded (the define/etym convention); each further
    # " կամ " form → a "variant" crossref (resolved by the loader when that
    # form is its own unique headword); gloss = the first «…» meaning in
    # <content> (nil when none); body = the headword line, then each
    # non-empty child's text, whitespace-squished, one line each.
    class CalfaEtymologyParser
      VARIANT = " կամ "
      MARKS = %w[* +].freeze
      GUILLEMETS = /«([^«»]+)»/

      # Parse +text+ (the whole file, already UTF-8) into DictionaryEntry
      # values in document order. +label+ names the file in errors.
      def entries(text, language:, label:)
        occurrences = Hash.new(0)
        collected = []
        Nokogiri::XML::Reader(StringIO.new(text), label).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.name == "entry"

          collected << build_entry(entry_element(node), language: language, occurrences: occurrences,
                                                        label: label)
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "calfa-etymology: malformed XML in #{label}: #{e.message}"
      end

      private

      def entry_element(node) = Nokogiri::XML(node.outer_xml, &:strict).root

      def build_entry(elem, language:, occurrences:, label:)
        headword = section_text(elem.at_xpath("headword"), language)
        if headword.nil?
          raise Nabu::ParseError, "calfa-etymology: #{label}: entry ##{occurrences.values.sum + 1} has no headword"
        end

        first, *variants = headword.split(VARIANT).map(&:strip)
        sections = elem.element_children
                       .reject { |child| child.name == "headword" }
                       .filter_map { |child| section_text(child, language) }
        Nabu::DictionaryEntry.new(
          entry_id: entry_id(headword, occurrences), key_raw: headword, language: language,
          headword: headword,
          headword_folded: Normalize.search_form(unmarked(first), language: language),
          gloss: gloss_of(elem, language),
          body: [headword, *sections].join("\n"),
          crossrefs: variants.map { |form| variant(form, language) },
          annotations: annotations_of(headword)
        )
      end

      def section_text(node, language)
        return nil if node.nil?

        text = squish(nfc(node.text, language))
        text.empty? ? nil : text
      end

      def entry_id(headword, occurrences)
        base = headword.gsub(/\s+/, "_")
        occurrences[base] += 1
        occurrences[base] > 1 ? "#{base}:#{occurrences[base]}" : base
      end

      def gloss_of(elem, language)
        content = section_text(elem.at_xpath("content"), language) or return nil
        match = GUILLEMETS.match(content) or return nil
        gloss = match[1].strip
        gloss.empty? ? nil : gloss
      end

      def variant(form, language)
        folded = Normalize.search_form(unmarked(form), language: language)
        Nabu::DictionaryCrossref.new(kind: "variant", label: form, target: form,
                                     target_folded: folded.empty? ? nil : folded)
      end

      def annotations_of(headword)
        mark = MARKS.find { |candidate| headword.start_with?(candidate) }
        mark ? { "headword_mark" => mark } : {}
      end

      def unmarked(form) = form.sub(/\A[*+]+/, "")

      def squish(text) = text.gsub(/[[:space:]]+/, " ").strip

      def nfc(text, language) = SourceRead.nfc(text, language: language)
    end
  end
end
