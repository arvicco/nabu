# frozen_string_literal: true

require "json"

require_relative "normalize"
require_relative "query/token_glosses"

module Nabu
  # The gloss-lines lane's extraction contract (Store::GlossLineIndex,
  # architecture §5): a passage's upstream TOKEN glosses read in token
  # order — its interlinear gloss line ("and speak the Chaldean to the
  # king in Aramaic king to eternity live", Dan 2:4 in BHSA's English).
  #
  # == One declaration, two lanes
  #
  # The sources and their gloss keys are Query::TokenGlosses' registry —
  # the same declaration the word-grain lane (Store::GlossIndex), the
  # token-gloss display and the `--lemma X --gloss Y` filter read. A
  # second registry would restate it; a source reaches this lane only by
  # a FIELDS line there (declared, never sniffed). Each Field declares the
  # gloss's OWN language, and that is the fold language here:
  #
  #   bhsa       en  per-lexeme English gloss
  #   achemenet  en  BabyLemmatizer English
  #   aes        de  German contextual translation (cotext_translation)
  #   tlhdig     de  German, on the selected analysis
  #
  # The passage language (Hebrew, Akkadian, Egyptian, Hittite) never
  # folds a gloss: Akkadian's sign-join fold would open "son-in-law" to
  # three words, Egyptian's ꜣ/ꜥ fold has nothing to act on. en and de
  # carry no extra rules today, so the fold is the generic one in effect —
  # declared per language so a future German rule reaches the lane
  # through the declaration, not an edit here.
  module GlossLines
    module_function

    def slugs = Query::TokenGlosses.sources

    def registered?(slug) = Query::TokenGlosses::FIELDS.key?(slug)

    # The declared gloss (= fold) language of +slug+'s gloss key.
    def language(slug) = Query::TokenGlosses::FIELDS.fetch(slug).language

    # The upstream token key that carries +slug+'s gloss.
    def key(slug) = Query::TokenGlosses::FIELDS.fetch(slug).key

    # The distinct declared gloss languages, in registry order.
    def languages = slugs.map { |slug| language(slug) }.uniq

    # The search form of one gloss under +slug+'s declared language.
    def fold(text, slug) = Normalize.search_form(text, language: language(slug))

    # The query side: one fold per declared gloss language, distinct —
    # the index folded each gloss by one of them, so the union cannot
    # miss (the fold-both-sides argument at the gloss grain).
    def query_forms(query) = languages.map { |code| Normalize.search_form(query.to_s, language: code) }.uniq

    # The passage's glossed tokens: [[token index, surface form, gloss],
    # …] in token order. +annotations+ is the parsed hash or the stored
    # JSON string (probed for the key before any parse); an unregistered
    # source has none.
    def entries(annotations, slug)
      return [] unless registered?(slug)

      if annotations.is_a?(String)
        return [] unless annotations.include?("\"#{key(slug)}\"")

        annotations = JSON.parse(annotations)
      end
      tokens = annotations.is_a?(Hash) ? annotations["tokens"] : nil
      return [] unless tokens.is_a?(Array)

      tokens.each_with_index.filter_map do |token, index|
        gloss = Query::TokenGlosses.gloss(token, source: slug)
        [index, token["form"].is_a?(String) ? token["form"] : "", gloss] if gloss
      end
    end

    # The gloss line: the glosses in token order, one space apart — so a
    # quoted phrase may run across adjacent tokens' glosses ("the king"
    # spans BHSA's article and noun), the interlinear reading.
    def line(entries) = entries.map(&:last).join(" ")
  end
end
