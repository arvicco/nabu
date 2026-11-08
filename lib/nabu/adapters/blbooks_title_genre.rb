# frozen_string_literal: true

module Nabu
  module Adapters
    # The blbooks kind fold's extraction half: a BL catalogue title → ONE
    # form-noun head, the facet value config/kind_map.yml's blbooks
    # section folds onto the ruled class list (the cgpg precedent:
    # upstream carries no genre field, so the title IS the label).
    # Deliberately mechanical; every judgment lives in the map.
    #
    # The BL titles carry two layers of form words: the print's own title
    # page ("The Roman Actor; a tragædie", "Poems on several occasions")
    # and the cataloguer's bracketed gloss ("[in five acts and in verse]",
    # "[In verse.]"). The rule ladder:
    #
    # 1. The MAIN title (before the first "[") is searched first; the
    #    earliest keyword match wins ("A poetical epistle" is verse, read
    #    at "poetical"); at one position the earlier-listed pattern wins
    #    (a compound before its parts: "tragi-comedy" before "comedy").
    # 2. No keyword in the main title: the bracketed gloss is consulted —
    #    the act count first ("in five acts" is a play even when the same
    #    gloss says "in verse"), then the same keywords ("[Poems. By R.
    #    Colvill.]", "[A dramatic piece …]"), then the bare verse marker
    #    ("[In verse.]").
    # 3. Still nothing: no claim (nil) — the facet is simply absent.
    #
    # Period spellings are the patterns' business, never the map's:
    # "Comœdie", "Tragædie", "tragæcomedie", "Comoedie" all head as
    # Comedy/Tragedy/Tragicomedy.
    module BlbooksTitleGenre
      Keyword = Data.define(:pattern, :head)

      def self.kw(pattern, head) = Keyword.new(pattern: pattern, head: head)
      private_class_method :kw

      # Order matters only at a shared position (compounds first).
      KEYWORDS = [
        # -- performance
        kw(/\btrag(?:i|y|æ|ae|œ|oe|e)?[\s-]*com(?:e|œ|oe|æ)d(?:y|ie)/i, "Tragicomedy"),
        kw(/\btrag(?:e|æ|ae|œ|oe)d(?:y|ie)/i, "Tragedy"),
        kw(/\bcom(?:e|œ|oe|æ)d(?:y|ie)/i, "Comedy"),
        kw(/\bfarce\b/i, "Farce"),
        kw(/\bopera\b/i, "Opera"),
        kw(/\bburletta\b/i, "Burletta"),
        kw(/\boratorio\b/i, "Oratorio"),
        kw(/\bmasque\b/i, "Masque"),
        kw(/\binterlude\b/i, "Interlude"),
        kw(/\b(?:musical|dramatic|comic|dramatick) entertainment\b/i, "Entertainment"),
        kw(/\bdramatic(?:k|al)? (?:piece|poem|tale|work|romance)s?\b/i, "Play"),
        kw(/\bdrama\b/i, "Play"),
        kw(/\bplay(?:s|es)?\b/i, "Play"),
        kw(/\bacted\b/i, "Play"),
        # -- verse
        kw(/\bpoem(?:s|es|a|ata)?\b/i, "Poem"),
        kw(/\bpoetic(?:al|all|k|ke)?\b/i, "Poem"),
        kw(/\bpoetry\b/i, "Poem"),
        kw(/\bverses\b/i, "Poem"),
        kw(/\bcanto\b/i, "Poem"),
        kw(/\bmonody\b/i, "Poem"),
        kw(/\bidyl+s?\b/i, "Poem"),
        kw(/\beclogues?\b/i, "Poem"),
        kw(/\bodes?\b/i, "Ode"),
        kw(/\belegy\b|\belegies\b/i, "Elegy"),
        kw(/\bsonnets?\b/i, "Sonnet"),
        kw(/\bballads?\b/i, "Ballad"),
        kw(/\bsongs?\b/i, "Song"),
        kw(/\bepigrams?\b/i, "Epigram"),
        kw(/\bhymns?\b/i, "Hymn"),
        kw(/\bsatyr(?:e|es|s)?\b|\bsatires?\b/i, "Satire"),
        # -- prose and address
        kw(/\bepistle\b/i, "Epistle"),
        kw(/\bletters?\b/i, "Letter"),
        kw(/\bsermons?\b/i, "Sermon"),
        kw(/\bnovel\b/i, "Novel"),
        kw(/\btales?\b/i, "Tale"),
        kw(/\bessay(?:e?s)?\b/i, "Essay")
      ].freeze

      # The cataloguer's bracketed gloss: the act-count marker, then (after
      # the keywords) the bare verse marker.
      ACTS = /\bin (?:one|two|three|four|five|six|seven) acts?\b/i
      IN_VERSE = /\bin verse\b/i

      # The head for +title+, or nil (no claim).
      def self.head(title)
        return nil if title.nil?

        main, bracket, gloss = title.to_s.partition("[")
        earliest(main) || (bracket.empty? ? nil : gloss_head(gloss))
      end

      def self.earliest(text)
        best = nil
        KEYWORDS.each_with_index do |keyword, rank|
          match = keyword.pattern.match(text) or next
          candidate = [match.begin(0), rank, keyword.head]
          best = candidate if best.nil? || (candidate <=> best).negative?
        end
        best&.last
      end
      private_class_method :earliest

      def self.gloss_head(gloss)
        return "Play" if gloss.match?(ACTS)

        earliest(gloss) || ("Verse" if gloss.match?(IN_VERSE))
      end
      private_class_method :gloss_head
    end
  end
end
