# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # Parser for one DillmannData TEI entry file (P46-2) — the `dillmann-tei`
    # family. Each upstream file is ONE <entry>: a Gǝʿǝz headword in
    # <form>/<foreign xml:lang="gez">, Latin (Dillmann 1865) and English
    # (TraCES additions) senses, biblical citations as display text, and
    # comparative Semitic forms inline.
    #
    # - entry_id: the entry @xml:id (== the filename stem — the id the
    #   TraCES corpus's `lex` lemma links point at, the crosswalk key).
    # - key_raw: the entry @n — Dillmann's running number — falling back to
    #   the id when absent.
    # - headword: the <form> foreign fidäl, verbatim (NFC is a no-op on
    #   Ethiopic); headword_folded through the standard gez search form.
    # - gloss: the first <cit type="translation"> quote (Dillmann's leading
    #   Latin equivalent — "os"); nil when the entry has none (the TraCES
    #   additions often gloss nothing — honest).
    # - body: one line per <sense> in document order (nested lettered
    #   senses included), each line prefixed with the sense @n label when
    #   present ("a. ዐፅመ፡ ርእስ፡ cranium , calvaria …"); a sense's own text
    #   excludes its nested senses' text, so nothing doubles. Prefixed-
    #   namespace elements (<t:quote>) read like any other — the parser
    #   matches local names throughout.
    class DillmannTeiParser
      def entry(path)
        doc = read_xml(path)
        node = doc.at_xpath("//*[local-name()='entry']") or
          raise ParseError, "#{path}: no <entry> element"
        headword = headword_for(node, path)
        Nabu::DictionaryEntry.new(
          entry_id: identity_for(node, path),
          key_raw: presence(node["n"]) || identity_for(node, path),
          language: "gez",
          headword: headword,
          headword_folded: Normalize.search_form(headword, language: "gez"),
          gloss: gloss_for(node),
          body: body_for(node, path)
        )
      rescue Nabu::ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end

      private

      def read_xml(path)
        Nokogiri::XML(File.read(path), &:strict)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      def identity_for(node, path)
        presence(node["xml:id"]) || File.basename(path, ".xml")
      end

      def headword_for(node, path)
        foreign = node.at_xpath("./*[local-name()='form']//*[local-name()='foreign']")
        headword = foreign && Normalize.nfc(flat(foreign.text))
        raise ParseError, "#{path}: entry has no <form> headword" if headword.nil? || headword.empty?

        headword
      end

      def gloss_for(node)
        quote = node.at_xpath(".//*[local-name()='cit'][@type='translation']" \
                              "/*[local-name()='quote']")
        quote && presence(Normalize.nfc(flat(quote.text)))
      end

      # One body line per <sense> anywhere under the entry, document order.
      # own_text excludes nested senses (they get their own lines).
      def body_for(node, path)
        lines = node.xpath(".//*[local-name()='sense']").filter_map do |sense|
          text = presence(flat(own_text(sense)))
          next unless text

          label = presence(sense["n"])
          label ? "#{label}. #{text}" : text
        end
        raise ParseError, "#{path}: entry has no sense text" if lines.empty?

        Normalize.nfc(lines.join("\n"))
      end

      def own_text(element)
        buffer = +""
        element.children.each do |child|
          if child.text? || child.cdata?
            buffer << child.text
          elsif child.element? && child.name != "sense"
            buffer << own_text(child) << " "
          end
        end
        buffer
      end

      def flat(text)
        text.gsub(/[[:space:]]+/, " ").strip
      end

      def presence(value)
        value if value && !value.empty?
      end
    end
  end
end
