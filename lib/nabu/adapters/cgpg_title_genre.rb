# frozen_string_literal: true

module Nabu
  module Adapters
    # The cgpg kind fold's extraction half: a carved work's title (the
    # carve plan's own Latin "title" field — upstream carries no genre
    # label, and neither does the plan) → ONE keyword head, the facet
    # value config/kind_map.yml's cgpg section folds onto the ruled class
    # list (the aio precedent: the parser cuts heads out of upstream's
    # label, the map folds heads exactly). Deliberately mechanical; every
    # judgment lives in the map, line by line.
    #
    # The rule ladder:
    #
    # 1. The MAIN title is the text before the first "(" or "[" (the
    #    plan's parentheses are its own glosses: chapters, BHG/CPG
    #    numbers, recension notes).
    # 2. Every KEYWORD pattern is searched in the main title; the
    #    earliest match wins (a genre noun's object never re-heads it:
    #    "Expositio in Epistolam" is an exposition); at one position the
    #    earlier-listed pattern wins, so a compound head ("Historia
    #    martyrii", "Fragmenta in") outranks its first word.
    # 3. A PART word (fragment, excerpt, preface) names a piece of a
    #    work: the first non-part keyword in the main title heads it
    #    ("Fragmenta ex epistolis" → Epistulae); with none, the last part
    #    word does ("Prooemium excerptorum" → Excerpta; bare "Fragmenta").
    # 4. No keyword in the main title: the parenthesis is consulted for
    #    a GLOSS only — homily, sermon, chronicle, history — the plan's
    #    own genre gloss on a generic title ("Orationes (homiliae et
    #    panegyrici)"); its other words describe the book, not its genre.
    # 5. Still nothing: a title opening "In <book>" is the Latin
    #    commentary-title form → "In".
    # 6. Still nothing: the title itself, cut at its first clause break,
    #    is the head — a "De <topic>" treatise names its topic, and the
    #    map folds such titles one by one (or leaves them unmapped).
    #
    # A head never carries the kind fold's composite separators ("|",
    # ";") — the clause cut removes them.
    module CgpgTitleGenre
      Keyword = Data.define(:pattern, :head, :part)

      def self.kw(pattern, head, part: false) = Keyword.new(pattern: pattern, head: head, part: part)
      private_class_method :kw

      # Order matters only at a shared position (compounds first).
      KEYWORDS = [
        kw(/\bhistoria\s+martyri/i, "Martyrium"),
        kw(/\bfragment\w*\s+in\b/i, "Fragmenta in"),
        kw(/\bexpositio\s+in\b/i, "Expositio in"),
        kw(/\bquaestionum\s+naturalium\b/i, "Quaestiones naturales"),
        # part words
        kw(/\bfragment/i, "Fragmenta", part: true),
        kw(/\breliqui/i, "Fragmenta", part: true),
        kw(/\bexcerpt/i, "Excerpta", part: true),
        kw(/\bprooemi/i, "Prooemium", part: true),
        # letters, preaching, verse
        kw(/\bepist[uo]l/i, "Epistulae"),
        kw(/\bhomil/i, "Homiliae"),
        kw(/\bsermo/i, "Sermones"),
        kw(/\bcarm/i, "Carmina"),
        kw(/\bpoem/i, "Poemata"),
        kw(/\bversus\b/i, "Versus"),
        # history
        kw(/\bhistori/i, "Historia"),
        kw(/\bchronograph/i, "Chronographia"),
        kw(/\bchronic/i, "Chronicon"),
        kw(/\bannal/i, "Annales"),
        kw(/\bbasileiai\b/i, "Basileiai"),
        kw(/\bpatria\b/i, "Patria"),
        kw(/\bparastase/i, "Parastaseis"),
        # commentary
        kw(/\bcommentar/i, "Commentarius"),
        kw(/\benarratio/i, "Enarratio"),
        kw(/\bscholi/i, "Scholia"),
        kw(/\bamphilochi/i, "Amphilochia"),
        # rite, oracle, law, register, instruction, criticism
        kw(/\bexapostilari/i, "Exapostilaria"),
        kw(/\boracul/i, "Oracula"),
        kw(/\bnovell/i, "Novellae"),
        kw(/\bdelectus\b/i, "Delectus"),
        kw(/\btom[uo]s\b/i, "Tomus"),
        kw(/\bnotiti/i, "Notitiae"),
        kw(/\bparaenes/i, "Paraenesis"),
        kw(/\binstitutio\b/i, "Institutio"),
        kw(/\bcharacter/i, "Characteres"),
        # the heads with no ruled class yet (kind_map's unmapped-by-design block)
        kw(/\bquaestion/i, "Quaestiones"),
        kw(/\bvitae?\b/i, "Vita"),
        kw(/\bmartyri/i, "Martyrium"),
        kw(/\blaudatio/i, "Laudatio"),
        kw(/\bencomi/i, "Encomium"),
        kw(/\bmonodi/i, "Monodia"),
        kw(/\bapologi/i, "Apologia"),
        kw(/\blegatio\b/i, "Legatio"),
        kw(/\bcohortatio/i, "Cohortatio"),
        kw(/\badversus\b/i, "Adversus"),
        kw(/\brefutatio/i, "Refutatio"),
        kw(/\bconfutatio/i, "Confutatio"),
        kw(/\bantirrhetic/i, "Antirrhetici"),
        kw(/\birrisio/i, "Irrisio"),
        kw(/\bdialog/i, "Dialogus"),
        kw(/\bconfessio\b/i, "Confessio")
      ].freeze

      # The genre glosses a parenthesis may lend a keywordless title.
      GLOSS_HEADS = %w[Homiliae Sermones Chronicon Historia].freeze

      IN_TITLE = /\AIn\s/
      CLAUSE_BREAK = %r{\s*(?:[(\[,;:]|\s/\s|\s-\s|\s=\s|\s\+\s)}

      # +title+ → the head String, nil for a blank title.
      def self.head(title)
        title = title.to_s.strip
        return nil if title.empty?

        main = title.split(/[(\[]/, 2).first.to_s.strip
        keyword_head(main) || gloss_head(title.delete_prefix(main)) ||
          (main.match?(IN_TITLE) ? "In" : nil) || main.split(CLAUSE_BREAK, 2).first.strip
      end

      # Rule 2 + 3 over the main title.
      def self.keyword_head(text)
        hits = hits_in(text)
        return nil if hits.empty?

        (hits.find { |hit| !hit.part } || hits.last).head
      end

      # Rule 4: the first gloss keyword in the parenthetical remainder.
      def self.gloss_head(rest)
        hits_in(rest).find { |hit| GLOSS_HEADS.include?(hit.head) }&.head
      end

      # Keywords by first match position; at a shared position the
      # earlier-listed keyword alone counts.
      def self.hits_in(text)
        KEYWORDS.filter_map { |keyword| (at = text.index(keyword.pattern)) && [at, keyword] }
                .group_by(&:first).sort.map { |_, group| group.first.last }
      end
      private_class_method :keyword_head, :gloss_head, :hits_in
    end
  end
end
