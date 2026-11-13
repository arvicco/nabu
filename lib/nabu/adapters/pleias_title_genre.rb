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

      # \p{L}-aware word edges: Ruby's \b treats accented letters as word
      # characters already, so "Édict" and "édits" edge correctly.
      KEYWORDS = [
        # -- royal and judicial acts (the cone's dominant print class)
        kw(/\blettres?[\s-]+patentes\b/i, "Lettres patentes"),
        kw(/\blettres?\s+de\s+d[ée]claration\b/i, "Déclaration"),
        kw(/\b[ée]dicts?\b|\b[ée]dits?\b/i, "Édit"),
        kw(/\bd[ée]clarations?\b/i, "Déclaration"),
        kw(/\bordonnances?\b/i, "Ordonnance"),
        kw(/\barr[eê]s?ts?\b/i, "Arrêt"),
        kw(/\br[ée]glemens?\b|\br[ée]glements?\b/i, "Règlement"),
        kw(/\bstatuts?\b/i, "Statuts"),
        kw(/\bcou(?:s)?tumes?\b/i, "Coutume"),
        kw(/\bfactum\b/i, "Factum"),
        kw(/\bmandement\b/i, "Mandement"),
        # -- performance
        kw(/\btragi[\s-]*com[ée]dies?\b/i, "Tragi-comédie"),
        kw(/\btrag[ée]dies?\b/i, "Tragédie"),
        kw(/\bcom(?:[ée]|œ|oe)dies?\b/i, "Comédie"),
        kw(/\bpastorales?\b/i, "Pastorale"),
        kw(/\bballets?\b/i, "Ballet"),
        # -- verse
        kw(/\bpo[ëeè]mes?\b/i, "Poème"),
        kw(/\bpo[ée]sies?\b/i, "Poésie"),
        kw(/\bodes?\b/i, "Ode"),
        kw(/\bstances\b/i, "Stances"),
        kw(/\bsonnets?\b/i, "Sonnet"),
        kw(/\btriolets?\b/i, "Triolet"),
        kw(/\b[ée]l[ée]gies?\b/i, "Élégie"),
        kw(/\b[ée]pithalames?\b/i, "Épithalame"),
        kw(/\bchansons?\b/i, "Chanson"),
        kw(/\bsat[yi]res?\b/i, "Satire"),
        # -- address and the pulpit
        kw(/\boraisons?\s+fun[èe]bres?\b/i, "Oraison funèbre"),
        kw(/\bsermons?\b/i, "Sermon"),
        kw(/\bhom[ée]lies?\b/i, "Homélie"),
        kw(/\bharangues?\b/i, "Harangue"),
        kw(/\bpan[ée]gyriques?\b/i, "Panégyrique"),
        kw(/\bcat[ée]chismes?\b/i, "Catéchisme"),
        kw(/\b(?:[ée]pistres?|[ée]p[iî]tres?)\b/i, "Épître"),
        kw(/\blettres?\b/i, "Lettre"),
        # -- story, record, reference
        kw(/\bannales\b/i, "Annales"),
        kw(/\bchroniques?\b/i, "Chronique"),
        kw(/\bmaximes\b/i, "Maximes"),
        kw(/\bdialogues?\b/i, "Dialogue"),
        kw(/\bdictionnaires?\b/i, "Dictionnaire"),
        kw(/\bgrammaires?\b/i, "Grammaire")
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
