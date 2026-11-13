# frozen_string_literal: true

require_relative "titus_levels_adapter"

module Nabu
  module Adapters
    # TITUS Old Frisian texts — the two Old Frisian editions TITUS hosts as
    # retrievable text (J. W. Goethe-Universität Frankfurt, Prof. Jost
    # Gippert), censused from TITUS's own text index (texte2.htm,
    # 2026-11-12): Thomas F. Shannon's Corpus of Old East and West Frisian
    # Texts (the Ten Commandments and the Seventeen Statutes after the
    # Hunsingo manuscripts, the Londriucht, Fon alra Fresena fridome — the
    # privilege of Charlemagne —, Thet Freske Riim, the Skeltana Riucht)
    # and the Brokmer Recht after Buma and Ebel's critical edition. Language
    # `ofs` throughout.
    #
    # == Terms and the credit duty
    #
    # Gated — contact TITUS for a license grant. The titus-avestan
    # mechanisms verbatim: `grant_required: true` guards the fetch right;
    # license_class `nc` + the manifest +credit+ line carry the display duty.
    # The Brokmer Recht's own editorial note (brokm001) states that the
    # editors' German translations are protected and may not be released:
    # the public edition this adapter walks carries the Frisian only.
    #
    # == Delivery grains (census 2026-11-12) and the reconciliation
    #
    # Two framesets (afrcorp/afrco.htm, brokmrx/brokm.htm), whose index
    # frames' option lists ARE the page map: afrcorp 6 pages (one per text:
    # 10_Gebote, 17_Küren, Londriucht, Fres.Frid., Fr.Riim, Skelt.Riucht),
    # brokmrx 242 pages (one per paragraph of the law, 1…180+) — 248 pages.
    # Accepted grain: a page carrying a run of the Old Frisian lane is one
    # document; a page with none skips by rule (discovery_skips). Rejected:
    # the separately served Brokmer edition carrying the German translation
    # (a frameset on another host — the translation is protected),
    # the runic-inscriptions project (an introduction only, "under
    # preparation"), and the framesets/index frames (navigation). EXPECTED
    # FIRST SYNC: 248 pages → 248 documents (the exact split reconciles
    # here after the retrieval).
    #
    # == Lanes and units (see Nabu::Adapters::TitusLevelsParser)
    #
    # The Old Frisian lane is `weaf*`; the Latin incipits ("Primun
    # mandatum,") ride the `latin` annotation. Units: the SENTENCE (Level 4
    # in the corpus, Level 3 in the Brokmer Recht).
    #
    # == Dating and place: deliberately none
    #
    # The headers state only the modern editions' years (Steller 1928,
    # Heuser 1903, Buma/Ebel 1965) — never a manuscript or composition
    # date; the codices' dates are scholarship, not a header. No claim.
    class TitusOldFrisian < TitusLevelsAdapter
      SLUG = "titus-old-frisian"
      LANGUAGE = "ofs" # Old Frisian
      NAME = "TITUS Old Frisian Texts"
      TITLE = "Old Frisian"

      BASE_URL = "https://titus.uni-frankfurt.de/texte/etcs/germ/afries/"

      LANES = TitusLevelsParser::Lanes.new(prefixes: %w[weaf], text_flavors: "bix", others: { /\Awela/ => "latin" })

      # census: 2 Old Frisian editions on texte2.htm, 2026-11-12 (names and
      # editors verbatim from the index)
      EDITIONS = {
        "afrcorp" => Edition.new(path: "afrcorp/afrco.htm", prefix: "afrco",
                                 name: "Corpus of Old East and West Frisian Texts",
                                 editors: "Thomas F. Shannon (Berkeley)", credit_name: "Shannon"),
        "brokmrx" => Edition.new(path: "brokmrx/brokm.htm", prefix: "brokm", name: "Brokmer Recht",
                                 editors: "Forschungsstelle des Deutschen Rechtswörterbuchs (Heidelberg)",
                                 credit_name: "Forschungsstelle des Deutschen Rechtswörterbuchs")
      }.freeze

      LICENSE = "gated — contact TITUS for a license grant; held on the TITUS family terms: one " \
                "retrieval, local research use only, no redistribution; TITUS and the editors " \
                "clearly indicated wherever displayed"

      CREDIT = "TITUS (J. Gippert, Frankfurt) — Old Frisian text editions, data entry " \
               "#{EDITIONS.values.map(&:credit_name).join(', ')} " \
               "(each document names its edition's editors).".freeze

      # The corpus page's own Level-2 "Text:" header.
      TEXT_HEADER = /<!Level 2>Text:\s*([^<]+?)\s*</

      private

      # The corpus holds six texts, one per page: each page's kind key is
      # its Text header ("17_Küren"), absent on none in the census.
      def work_for(edition_id, html)
        return edition_id unless edition_id == "afrcorp"

        html[TEXT_HEADER, 1] || edition_id
      end
    end
  end
end
