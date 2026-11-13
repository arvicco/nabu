# frozen_string_literal: true

module Nabu
  module Adapters
    # The pleias-french-books kind fold's extraction half: a Gallica
    # catalogue title (early-modern French print) → ONE form-noun head, the
    # facet value config/kind_map.yml's pleias-french-books section folds
    # onto the ruled class list (the blbooks/cgpg precedent: upstream
    # carries no genre field, so the title IS the label). Deliberately
    # mechanical; every judgment lives in the map.
    #
    # The rule: the EARLIEST keyword match in the title wins ("Lettres
    # patentes … portant … édict" heads as Lettres patentes); at one
    # position the earlier-listed pattern wins (a compound before its
    # parts: "tragi-comédie" before "comédie", "lettres patentes" before
    # "lettre"). No keyword, no claim (nil — the facet is simply absent).
    #
    # Period spellings are the patterns' business, never the map's:
    # Édict/Edict/Édit/Edit/Edicts, Arrest/Arrêt, Traicté, Responce,
    # Poëme/Poème, Epistre/Épître, Comœdie. Words that are also common
    # prepositions or topics stay OUT on purpose ("vers" is "towards" as
    # often as "verse"; "histoire" heads novels and chronicles alike;
    # "discours" and "traité" are topic-neutral in the period;
    # "requestes" is as often the maître des requêtes's office as a
    # petition; "mémoires", "voyage" and "roman" head as many topical
    # titles — "sur le voyage du roi" verse, "tiré des Mémoires" — as
    # memoirs, travels and novels; "épigramme" heads treatises on verse)
    # — a keyword that cannot tell its genre from its title makes no
    # claim (census over the 6,477 cone titles, 2026-11-13).
    module PleiasTitleGenre
      Keyword = Data.define(:pattern, :head)

      def self.kw(pattern, head) = Keyword.new(pattern: pattern, head: head)
      private_class_method :kw

      # \p{L}-aware word edges: Ruby's (?!\p{L}) treats accented letters as word
      # characters already, so "Édict" and "édits" edge correctly.
      KEYWORDS = [
        # -- royal and judicial acts (the cone's dominant print class)
        kw(/(?<!\p{L})lettres?[\s-]+patentes(?!\p{L})/i, "Lettres patentes"),
        kw(/(?<!\p{L})lettres?\s+de\s+d[ée]claration(?!\p{L})/i, "Déclaration"),
        kw(/(?<!\p{L})[ée]dicts?(?!\p{L})|(?<!\p{L})[ée]dits?(?!\p{L})/i, "Édit"),
        kw(/(?<!\p{L})d[ée]clarations?(?!\p{L})/i, "Déclaration"),
        kw(/(?<!\p{L})ordonnances?(?!\p{L})/i, "Ordonnance"),
        kw(/(?<!\p{L})arr[eê]s?ts?(?!\p{L})/i, "Arrêt"),
        kw(/(?<!\p{L})r[ée]glemens?(?!\p{L})|(?<!\p{L})r[ée]glements?(?!\p{L})/i, "Règlement"),
        kw(/(?<!\p{L})statuts?(?!\p{L})/i, "Statuts"),
        kw(/(?<!\p{L})cou(?:s)?tumes?(?!\p{L})/i, "Coutume"),
        kw(/(?<!\p{L})factum(?!\p{L})/i, "Factum"),
        kw(/(?<!\p{L})mandement(?!\p{L})/i, "Mandement"),
        # -- performance
        kw(/(?<!\p{L})tragi[\s-]*com[ée]dies?(?!\p{L})/i, "Tragi-comédie"),
        kw(/(?<!\p{L})trag[ée]dies?(?!\p{L})/i, "Tragédie"),
        kw(/(?<!\p{L})com(?:[ée]|œ|oe)dies?(?!\p{L})/i, "Comédie"),
        kw(/(?<!\p{L})pastorales?(?!\p{L})/i, "Pastorale"),
        kw(/(?<!\p{L})ballets?(?!\p{L})/i, "Ballet"),
        # -- verse
        kw(/(?<!\p{L})po[ëeè]mes?(?!\p{L})/i, "Poème"),
        kw(/(?<!\p{L})po[ée]sies?(?!\p{L})/i, "Poésie"),
        kw(/(?<!\p{L})odes?(?!\p{L})/i, "Ode"),
        kw(/(?<!\p{L})stances(?!\p{L})/i, "Stances"),
        kw(/(?<!\p{L})sonnets?(?!\p{L})/i, "Sonnet"),
        kw(/(?<!\p{L})triolets?(?!\p{L})/i, "Triolet"),
        kw(/(?<!\p{L})[ée]l[ée]gies?(?!\p{L})/i, "Élégie"),
        kw(/(?<!\p{L})[ée]pithalames?(?!\p{L})/i, "Épithalame"),
        kw(/(?<!\p{L})chansons?(?!\p{L})/i, "Chanson"),
        kw(/(?<!\p{L})sat[yi]res?(?!\p{L})/i, "Satire"),
        # -- address and the pulpit
        kw(/(?<!\p{L})oraisons?\s+fun[èe]bres?(?!\p{L})/i, "Oraison funèbre"),
        kw(/(?<!\p{L})sermons?(?!\p{L})/i, "Sermon"),
        kw(/(?<!\p{L})hom[ée]lies?(?!\p{L})/i, "Homélie"),
        kw(/(?<!\p{L})harangues?(?!\p{L})/i, "Harangue"),
        kw(/(?<!\p{L})pan[ée]gyriques?(?!\p{L})/i, "Panégyrique"),
        kw(/(?<!\p{L})cat[ée]chismes?(?!\p{L})/i, "Catéchisme"),
        kw(/(?<!\p{L})(?:[ée]pistres?|[ée]p[iî]tres?)(?!\p{L})/i, "Épître"),
        kw(/(?<!\p{L})lettres?(?!\p{L})/i, "Lettre"),
        # -- story, record, reference
        kw(/(?<!\p{L})annales(?!\p{L})/i, "Annales"),
        kw(/(?<!\p{L})chroniques?(?!\p{L})/i, "Chronique"),
        kw(/(?<!\p{L})maximes(?!\p{L})/i, "Maximes"),
        kw(/(?<!\p{L})dialogues?(?!\p{L})/i, "Dialogue"),
        kw(/(?<!\p{L})dictionnaires?(?!\p{L})/i, "Dictionnaire"),
        kw(/(?<!\p{L})grammaires?(?!\p{L})/i, "Grammaire")
      ].freeze

      # The title's form-noun head, or nil.
      def self.head(title)
        return nil if title.nil? || title.strip.empty?

        best = nil
        KEYWORDS.each_with_index do |keyword, rank|
          match = keyword.pattern.match(title) or next
          key = [match.begin(0), rank]
          best = [key, keyword.head] if best.nil? || (key <=> best.first).negative?
        end
        best&.last
      end
    end
  end
end
