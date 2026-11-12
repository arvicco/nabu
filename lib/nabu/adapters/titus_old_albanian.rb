# frozen_string_literal: true

require_relative "titus_levels_adapter"

module Nabu
  module Adapters
    # TITUS Old Albanian texts — the five Albanian editions TITUS hosts as
    # retrievable text (J. W. Goethe-Universität Frankfurt, Prof. Jost
    # Gippert), censused from TITUS's own text index (texte2.htm,
    # 2026-11-12): Buzuku's Missal (1555, the first Albanian book), Bardhi's
    # (Blanchus's) Dictionarium Latino-Epiroticum, Bogdani's Cuneus
    # Prophetarum, Casasi's Breve compendio della dottrina christiana and
    # Matrënga's Dottrina christiana. Language `sqi` (the lect posture stages
    # it sq:old — config/lect_overrides.yml).
    #
    # == Terms and the credit duty
    #
    # Gated — contact TITUS for a license grant. The titus-avestan
    # mechanisms verbatim: `grant_required: true` guards the fetch right;
    # license_class `nc` + the manifest +credit+ line carry the display duty
    # (every edition's data-entry editors; each document's "editors").
    #
    # == Delivery grains (census 2026-11-12) and the reconciliation
    #
    # Each edition is its own frameset (<dir>/<prefix>.htm → text frame
    # <prefix>001.htm; the index frames <prefix>x.htm / <prefix>x<n>.htm
    # whose option lists ARE the page map). Index census, pages per
    # edition: buzuku 146 (chapters 1-146), blanchus 9 (the introduction,
    # the alphabet, chapters 1-8), bogdani 15 (two parts: Prim. + Scala I-IV
    # + Lig.I-VI, then Scala I-IV), casasi 114 (46 text pages + 68 pages
    # keyed "n<page><A|B>" — the edition's notes/facing pages, classified at
    # the first sync), matranga 2 (the preface + version C1) — 286 pages.
    # Accepted grain: a page carrying a run of the Albanian lanes is one
    # document; a page with none skips by rule (discovery_skips). The
    # framesets and index frames are navigation. EXPECTED FIRST SYNC: 286
    # pages → ≤286 documents (the exact split reconciles here after the
    # retrieval).
    #
    # == Lanes (see Nabu::Adapters::TitusLevelsParser)
    #
    # The Albanian lanes are `bual*` with the typography flavors the sample
    # census shows (x fragment, b bold, i italic); the Latin of the prints
    # and the dictionary (`wela*`) rides the `latin` annotation. Units:
    # Buzuku's printed LINE (XLevel), Bogdani's and Blanchus's paragraphs,
    # Matrënga's manuscript line.
    #
    # Matrënga PROVISIONAL: the edition header states that Sciambra's
    # "pseudo-phonological interpretation" of the Albanian is given
    # "interlinearly and typed in slanted letters" — the italic flavor
    # (`buali*`) on the matranga pages therefore rides the `interpretation`
    # annotation, never the manuscript text. The lane id is confirmed on
    # the held pages at the first sync (the content page was not in the
    # fixture census); any other lane there quarantines loudly.
    #
    # == Dating and place: what the pages state
    #
    # Blanchus's title page: "Romae, Typis Sac.Congr.de Propag. Fide.
    # 1635" (class edition, Rome); Matrënga's TITUS header: "Dottrina
    # Christiana (1592)" — the autograph manuscript (class composition).
    # Buzuku's only copy lacks its title page; Bogdani's and Casasi's
    # title pages were not in the fixture census — read from the held
    # pages after the first retrieval, never supplied from scholarship.
    class TitusOldAlbanian < TitusLevelsAdapter
      SLUG = "titus-old-albanian"
      LANGUAGE = "sqi" # Albanian (the lect stage sq:old via lect_overrides)
      NAME = "TITUS Old Albanian Texts"
      TITLE = "Old Albanian"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/alban/"

      # The other-language lanes, classified from the first retrieval's 121
      # quarantined pages (2026-11-12, the loud-quarantine discipline). The
      # editions' lane grammar is a language-coded stem family: bu-al the
      # Albanian text, bu-la the LATIN parallel (Bogdani's "PROPTEREA
      # captivus ductus est…", bulai its italic), we-la Latin, we-it
      # ITALIAN (Casasi's imprint and parallel — "In Roma, MDCCXLIII,
      # nella…"), we-tk TURKISH (Bardhi's occasional Turkish equivalents —
      # "Bunda"), gr(x) the GREEK letters of the editorial legends. The
      # bual flavor c carries Bogdani's marginal verse-concordance NUMBER
      # (a bare "2077" between the Verse header and the text) — its own
      # annotation, never the text.
      LANES = TitusLevelsParser::Lanes.new(
        prefixes: %w[bual], text_flavors: "bix",
        others: { /\Awela/ => "latin", /\Abula/ => "latin", /\Aweit/ => "italian",
                  /\Awetk/ => "turkish", /\Agrx?\d/ => "greek" },
        flavor_annotations: { "c" => "margin_number" }
      )

      # Matrënga's interlinear modern interpretation (PROVISIONAL — class doc).
      MATRANGA_LANES = TitusLevelsParser::Lanes.new(
        prefixes: %w[bual], text_flavors: "bx",
        others: { /\Awela/ => "latin", /\Abula/ => "latin", /\Aweit/ => "italian",
                  /\Awetk/ => "turkish", /\Agrx?\d/ => "greek" },
        flavor_annotations: { "i" => "interpretation", "c" => "margin_number" }
      )

      # census: 5 Albanian editions on texte2.htm, 2026-11-12 (names and
      # editors verbatim from the index)
      EDITIONS = {
        "buzuku" => Edition.new(path: "buzuku/buzuk.htm", prefix: "buzuk", name: "Buzuku, Missale",
                                editors: "W. Hock (Berlin)", credit_name: "Hock"),
        "blanchus" => Edition.new(path: "blanchus/blanc.htm", prefix: "blanc",
                                  name: "Franciscus Blanchus, Dictionarium Latino-Epiroticum",
                                  editors: "M. de Vaan (Leiden)", credit_name: "de Vaan",
                                  date: { "not_before" => 1635, "not_after" => 1635,
                                          "raw" => "Romae, Typis Sac.Congr.de Propag. Fide. 1635",
                                          "class" => "edition" }.freeze,
                                  place: "Rome"),
        "bogdani" => Edition.new(path: "bogdani/bogda.htm", prefix: "bogda", name: "Bogdani, Cuneus Prophetarum",
                                 editors: "M. de Vaan (Leiden)", credit_name: "de Vaan"),
        "casasi" => Edition.new(path: "casasi/casas.htm", prefix: "casas",
                                name: "Casasi, Breve compendio della dottrina christiana",
                                editors: "B. Demiraj (Munich)", credit_name: "Demiraj"),
        "matranga" => Edition.new(path: "matranga/matra.htm", prefix: "matra", name: "Matranga, Dottrina christiana",
                                  editors: "M. de Vaan (Leiden)", credit_name: "de Vaan",
                                  date: { "not_before" => 1592, "not_after" => 1592,
                                          "raw" => "Dottrina Christiana (1592)", "class" => "composition" }.freeze,
                                  lanes: MATRANGA_LANES)
      }.freeze

      LICENSE = "gated — contact TITUS for a license grant; held on the TITUS family terms: one " \
                "retrieval, local research use only, no redistribution; TITUS and the editors " \
                "clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Old Albanian text editions, data entry " \
               "#{EDITIONS.values.map(&:credit_name).uniq.join(', ')} " \
               "(each document names its edition's editors).".freeze
    end
  end
end
