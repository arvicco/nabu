# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"

module Nabu
  module Adapters
    # The oncoj-lexicon family (P32-2): lexicon.xml of the ONCOJ release —
    # "the dictionary database for the corpus" (upstream README §B). A TEI-
    # namespaced <div> of 5,527 <superEntry> groups / 5,871 <entry> records:
    # romanized headword orths with grammatical group (pos + iType inflection
    # notes), geo usage marks (EOJ — the Eastern Old Japanese variants),
    # numbered senses, and <re> relation sections (compound/derivation/
    # related/… — members are <ref target> pointers into other entries).
    #
    # == What one <entry> yields (Nabu::DictionaryEntry)
    #
    # - entry_id: xml:id verbatim — the exact id space corpus tokens
    #   reference via w/@lemma (the join contract with the oncoj corpus
    #   source). The ONE upstream duplicate (l090819, censused) re-mints its
    #   file-order repeat as "l090819-b" with an honest body note (the
    #   starling collision precedent); key_raw keeps the upstream id.
    # - headword: the first form/orth, NFC — also what the corpus adapter's
    #   lemma resolution mints as the token lemma form, so token lemmas and
    #   shelf headwords fold identically by construction.
    # - gloss: the first sense <def>; nil for the 223 censused def-less
    #   entries.
    # - body: forms/pos/inflection/usage/corresp lines, numbered senses,
    #   notes, then one line per <re> relation naming members with their
    #   entry ids. Upstream relation-type typos ("transitivty", "relared")
    #   ride verbatim — canonical means canonical.
    # - citations/reflexes: always empty — the lexicon cites no CTS urns and
    #   names no descendants.
    class OncojLexiconParser
      TEI_NS = "http://www.tei-c.org/ns/1.0"

      # Parse the lexicon file, yielding Nabu::DictionaryEntry per <entry>
      # in file order. Raises Nabu::ParseError on malformed XML.
      def each_entry(path)
        return enum_for(:each_entry, path) unless block_given?

        seen = Hash.new(0)
        entries(path).each do |entry|
          yield build_entry(entry, seen, path)
        end
      end

      # { upstream entry id => headword } for the corpus adapter's lemma
      # resolution — keyed on the VERBATIM id space w/@lemma speaks; the
      # duplicate id keeps its first (file-order) headword.
      def headword_index(path)
        index = {}
        entries(path).each do |entry|
          id = entry["xml:id"].to_s
          headword = first_orth(entry)
          index[id] = headword unless id.empty? || headword.nil? || index.key?(id)
        end
        index
      end

      private

      def entries(path)
        doc = Nokogiri::XML(File.read(path), &:strict)
        doc.xpath("//tei:entry", "tei" => TEI_NS)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def build_entry(entry, seen, path)
        upstream_id = entry["xml:id"].to_s
        raise Nabu::ParseError, "#{path}: <entry> without xml:id" if upstream_id.empty?

        nth = seen[upstream_id]
        seen[upstream_id] += 1
        headword = first_orth(entry)
        raise Nabu::ParseError, "#{path}: entry #{upstream_id}: no <orth> headword" if headword.nil?

        gloss = squeeze(entry.at_xpath("./tei:sense/tei:def", "tei" => TEI_NS)&.text)
        Nabu::DictionaryEntry.new(
          entry_id: nth.zero? ? upstream_id : "#{upstream_id}-#{('b'..'z').to_a.fetch(nth - 1)}",
          key_raw: upstream_id, language: "ojp",
          headword: Normalize.nfc(headword),
          headword_folded: Normalize.search_form(headword, language: "ojp"),
          gloss: gloss && Normalize.nfc(gloss),
          body: Normalize.nfc(body_text(entry, duplicate: nth.positive?))
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "#{path}: entry #{entry['xml:id'].inspect}: #{e.message}"
      end

      def first_orth(entry)
        squeeze(entry.at_xpath("./tei:form/tei:orth", "tei" => TEI_NS)&.text)
      end

      def body_text(entry, duplicate:)
        lines = [forms_line(entry), *grammar_lines(entry), *usage_lines(entry), corresp_line(entry),
                 *sense_lines(entry), *note_lines(entry), *relation_lines(entry)].compact
        lines << "upstream entry id #{entry['xml:id']} also names another entry (kept in file order)" if duplicate
        lines.empty? ? "(lexicon entry — no further detail recorded)" : lines.join("\n")
      end

      def forms_line(entry)
        orths = entry.xpath("./tei:form/tei:orth", "tei" => TEI_NS).filter_map { |orth| squeeze(orth.text) }
        return nil if orths.size < 2

        "forms: #{orths.join(' · ')}"
      end

      def grammar_lines(entry)
        entry.xpath("./tei:form/tei:gramGrp | ./tei:gramGrp", "tei" => TEI_NS).flat_map do |gram|
          [labeled("pos", gram.at_xpath("./tei:pos", "tei" => TEI_NS)&.text),
           inflection_line(gram.at_xpath("./tei:iType", "tei" => TEI_NS))]
        end
      end

      def inflection_line(itype)
        return nil if itype.nil?

        kind = [itype["affixType"], itype["type"]].compact.reject(&:empty?).join(" ")
        text = squeeze(itype.text)
        parts = [kind, text].reject { |part| part.nil? || part.empty? }
        return nil if parts.empty?

        "inflection: #{parts.join(' — ')}"
      end

      def usage_lines(entry)
        entry.xpath(".//tei:usg", "tei" => TEI_NS).filter_map do |usg|
          text = squeeze(usg.text)
          text && "usage (#{usg['type'] || 'unmarked'}): #{text}"
        end
      end

      def corresp_line(entry)
        labeled("upstream corresp", entry["corresp"])
      end

      def sense_lines(entry)
        entry.xpath("./tei:sense", "tei" => TEI_NS).flat_map do |sense|
          n = sense["n"]
          sense.xpath("./tei:def", "tei" => TEI_NS).filter_map do |definition|
            text = squeeze(definition.text)
            text && (n ? "#{n}. #{text}" : text)
          end
        end
      end

      def note_lines(entry)
        entry.xpath("./tei:note | ./tei:form/tei:note", "tei" => TEI_NS).filter_map do |note|
          labeled("note", squeeze(note.text))
        end
      end

      # One line per <re>: "compound: titi (l050641) · papa (l051720)" — the
      # relation type verbatim (upstream typos included), members from the
      # orth/ref texts with their target entry ids.
      def relation_lines(entry)
        entry.xpath("./tei:re", "tei" => TEI_NS).filter_map do |re|
          members = re.xpath(".//tei:orth", "tei" => TEI_NS).filter_map { |orth| member_text(orth) }
          next nil if members.empty?

          "#{re['type'] || 'related'}: #{members.join(' · ')}"
        end
      end

      def member_text(orth)
        ref = orth.at_xpath("./tei:ref", "tei" => TEI_NS)
        text = squeeze((ref || orth).text)
        return nil if text.nil?

        target = ref && ref["target"]
        target ? "#{text} (#{target})" : text
      end

      def labeled(label, value)
        text = squeeze(value)
        text && "#{label}: #{text}"
      end

      def squeeze(text)
        cleaned = text.to_s.gsub(/\s+/, " ").strip
        cleaned.empty? ? nil : cleaned
      end
    end
  end
end
