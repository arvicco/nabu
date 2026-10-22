# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # The vakk-html family: one VAKK text page (vakk.ut.ee/tekstid.php,
    # the per-page reading view) → its page label, the page-selector
    # values, and the page's sentences with their annotated tokens.
    #
    # Markup (censused 2026-10-21 on fifteen live pages): the reading
    # view holds `.lehekylg_tekst` with one `div.lause` per sentence; each
    # word is a `span.sone` whose own text is the surface form (wrapped in
    # `span.stiil <style>` for headings and margin notes — "pealkiri",
    # "markus") and whose `span.soneinfo` carries the annotation: `lemma`
    # (the modern-Estonian headword), `tahendus` (a gloss), `liik` (part
    # of speech: s, v, adj, pron, adp, konj, s_nimi …), `vorm` (the form:
    # "sg.gen.", "pers.ind.pr.sg.3."), `keel` (the token's language:
    # eesti, saksa, ladina, kirjavahemärk — punctuation, number, viide —
    # a reference mark) and `kommentaar` ("sic!"). Compound halves are
    # separate tokens marked with a joining plus ("Pea+" "+tük").
    # `.lknr` names the page ("Lehekülg 1", "Eeltekst" for front
    # matter) and `select#lehekyljed` lists every page of the text by
    # value (signed integers: the front matter counts down from -1).
    class VakkPageParser
      Token = Data.define(:form, :lemma, :gloss, :pos, :morph, :lang, :comment, :style)
      Sentence = Data.define(:text, :tokens)
      Page = Data.define(:label, :page_values, :selected, :sentences)

      # Tokens that close up against the preceding word in the passage
      # string (sentence-final and clause punctuation, closing brackets).
      CLOSING = /\A[.,;:!?)\]»”]+\z/
      JOIN_MARK = "+"

      def parse(html)
        doc = Nokogiri::HTML(html)
        options = doc.css("select#lehekyljed option")
        selected = options.find { |option| option.key?("selected") }&.[]("value")
        Page.new(
          label: clean(doc.at_css(".lknr")&.text),
          page_values: options.map { |option| option["value"].to_s.strip },
          selected: selected&.strip,
          sentences: doc.css(".lehekylg_tekst div.lause").filter_map { |lause| sentence(lause) }
        )
      end

      # True when the HTML is a VAKK reading view at all (an unknown text
      # id answers the site's generic page instead).
      def reading_view?(html)
        html.include?("lehekylg_tekst")
      end

      private

      def sentence(lause)
        tokens = lause.css("> span.sone").filter_map { |sone| token(sone) }
        return nil if tokens.empty?

        text = surface(tokens)
        text.empty? ? nil : Sentence.new(text: text, tokens: tokens)
      end

      def token(sone)
        info = sone.at_css("> span.soneinfo")
        bare = sone.dup
        bare.css("span.soneinfo").each(&:remove)
        form = clean(bare.text)
        return nil if form.nil?

        style = sone.at_css("span.stiil")&.[]("class").to_s.split.reject { |c| c == "stiil" }.first
        Token.new(form: form, lemma: field(info, "lemma"), gloss: field(info, "tahendus"),
                  pos: field(info, "liik"), morph: field(info, "vorm"), lang: field(info, "keel"),
                  comment: field(info, "kommentaar"), style: style)
      end

      def field(info, klass)
        info && clean(info.at_css("span.#{klass}")&.text)
      end

      # The passage string: tokens space-joined, a compound's "X+" "+Y"
      # halves closed up into "XY" (the marks are VAKK's segmentation, not
      # the text's), closing punctuation against the word before it.
      def surface(tokens)
        tokens.each_with_index.with_object(+"") do |(token, index), out|
          previous = index.positive? ? tokens[index - 1].form : nil
          form = token.form
          if previous&.end_with?(JOIN_MARK) && form.start_with?(JOIN_MARK)
            out.chomp!(JOIN_MARK)
            out << form.delete_prefix(JOIN_MARK)
          elsif out.empty? || form.match?(CLOSING)
            out << form
          else
            out << " " << form
          end
        end.strip
      end

      def clean(value)
        text = value.to_s.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : Normalize.nfc(text)
      end
    end
  end
end
