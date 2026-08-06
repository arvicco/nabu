# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family `derom-xml` (P56-4): one DÉRom article XML → at most one
    # Nabu::DictionaryEntry. The schema (derom.xsd, bespoke to the project)
    # has three article shapes — all pinned by real fixtures:
    #
    # - FULL article (DÉRom 1–3): <Article><Lemme> (Signifiant = the etymon
    #   in DÉRom phonological notation, ˈlakt-e / kaˈβall-u; catgramm;
    #   Signifie = the French definition) + <Materiaux> with <subdiv>
    #   sections (titre, etym, <cognats> of <premier.cognat>/<cognat>) +
    #   <Commentaire> paragraphs (+ Bibliographie/Signatures/Notes, which
    #   stay OUT of the body — sigla lists and apparatus, not article text).
    # - RENVOI stub (collection 5): Lemme + <Lien> to a Mertens 2021 PDF —
    #   an entry with gloss, zero reflexes, the link in the body.
    # - POTICHE placeholder (collection 6): bare <Signifiant> +
    #   <NonRedige/>, no Lemme — upstream's own "not written yet" flag; the
    #   parser returns nil and the article claims no entry.
    #
    # == The positional cognat walk (fixture-pinned quirk)
    #
    # One <cognat> can interleave several idiome→signifiant runs
    # ("gal. cabalo, port. cavalo" is ONE cognat with two <idiome>
    # children); each <signifiant> attaches to the NEAREST PRECEDING
    # <idiome>, and one idiome run can carry several variant signifiants
    # (romanch. lat / latg). Exact duplicate (idiome, word) pairs across
    # subdivs are deduped (lakt-e repeats ast. lleche under the masculine
    # and feminine subdivs).
    #
    # == The headword fold
    #
    # DÉRom notation carries the U+02C8/U+02CC stress marks (Lm — the
    # generic Mn strip never touches them) and the phoneme letters
    # β ɸ ɛ ɔ ɪ ʊ. The fold maps them exactly as upstream's own ASCII
    # filename convention does ('lakt-e.xml, ka'Ball-u.xml, 'dEke.xml:
    # B=β, F=ɸ, E=ɛ, O=ɔ, I=ɪ, U=ʊ, '=ˈ) — stress dropped, letters to
    # their plain counterparts — so `define lakt-e` and `define kaball-u`
    # are typeable. Morph-boundary hyphens stay: they are DÉRom's citation
    # form.
    class DeromXmlParser
      # idiome abbreviation (upstream, French) → the catalog-side language
      # tag the crosswalk join speaks. lang_code is the RESOLVED catalog tag
      # (P57-5 — DÉRom's own idiome abbreviation used to leak through
      # verbatim even though this table already resolved `language`);
      # unmapped idiomes fall back to the verbatim idiome string,
      # display-only (language nil, never a join candidate) — as of P59-1
      # that fallback is the DELIBERATE home of exactly four ambiguous
      # dialect-geography labels (extension note below). gasc./lang. fold
      # into oci — ISO 639-3 retired Gascon/Languedocien into Occitan.
      #
      # P57-5 completed the table (four idiomes had no target at all):
      #   "arag." => Aragonese (arg); "végl." => Vegliote, the island
      #   dialect of Dalmatian (dlm — same target as dalm.); "logoud." =>
      #   Logudorese Sardinian (src); "itsept." => northern/septentrional
      #   Italian, no dedicated ISO code — mapped to `it` (ISO 639-1)
      #   DISTINCT from plain it.'s `ita` (ISO 639-3) so the two idiomes
      #   stay distinguishable rather than conflated into one language.
      # The fifth gap, the composite "gal./port." citation, is not a
      # missing mapping — split_idiome below splits it into its two
      # component idiomes before lookup (the smaller honest diff versus a
      # synthetic roa-opt code; see #reflexes).
      # P59-1 extended the table again: the live census surfaced ~60 FINER
      # sub-idiome labels (198 reflex rows) riding the verbatim fallback —
      # DÉRom cites dialect geography below the language grain. They fold
      # into their ISO languages per the gasc.→oci precedent; the Italian
      # dialect-geography labels follow the Ethnologue groupings (Continental
      # South = nap, Extreme South = scn, central dialects = ita). Four stay
      # deliberately unmapped — "cal." (spans the nap/scn split),
      # "itcentr.-mérid." (spans ita/nap), "trent." (Lombard-Venetian
      # transition), "émil.-romagn." (ISO retired eml into egl+rgn) — the
      # verbatim fallback IS their honest resolution.
      IDIOME_LANGUAGES = {
        "dacoroum." => "ron", "istroroum." => "ruo", "méglénoroum." => "ruq",
        "aroum." => "rup", "sard." => "srd", "dalm." => "dlm", "istriot." => "ist",
        "it." => "ita", "frioul." => "fur", "lad." => "lld", "romanch." => "roh",
        "fr." => "fra", "frpr." => "frp", "occit." => "oci", "gasc." => "oci",
        "lang." => "oci", "vén." => "vec", "cat." => "cat", "esp." => "spa",
        "ast." => "ast", "gal." => "glg", "port." => "por",
        "arag." => "arg", "végl." => "dlm", "logoud." => "src", "itsept." => "it",
        # Gallo-Italic / Venetan-adjacent
        "lomb." => "lmo", "piém." => "pms", "lig." => "lij",
        # Extreme South (the Sicilian group)
        "sic." => "scn", "salent." => "scn", "cal. centr.-mérid." => "scn",
        # Continental South (the Neapolitan group)
        "camp." => "nap", "cal. sept." => "nap", "luc." => "nap",
        "luc.-cal." => "nap", "apul." => "nap", "abr." => "nap",
        "itmérid." => "nap", "laz. mérid." => "nap",
        # Central Italian (Standard Italian's own dialect ground)
        "tosc." => "ita", "flor." => "ita", "ombr." => "ita", "laz." => "ita",
        "laz. centr.-sept." => "ita", "itcentr." => "ita", "march." => "ita",
        "march. sept." => "ita", "march. centr." => "ita",
        # Islands
        "cors." => "cos", "campid." => "sro",
        # Romansh varieties (Sursilvan / Vallader / Puter)
        "surs." => "roh", "bas-engad." => "roh", "haut-engad." => "roh",
        # Ladin valleys (Fascia / Gherdëina / Badia / Mareo)
        "fasc." => "lld", "gherd." => "lld", "bad." => "lld", "mar." => "lld",
        # Friulian
        "carn." => "fur",
        # Occitan dialects
        "prov." => "oci", "rouerg." => "oci", "auv." => "oci",
        "viv.-alp." => "oci", "béarn." => "oci", "périg." => "oci",
        # Catalan (Roussillonnais IS Northern Catalan)
        "rouss." => "cat", "baléar." => "cat", "cat. centr." => "cat",
        # Francoprovençal
        "sav." => "frp", "lyonn." => "frp", "aost." => "frp", "SRfrpr." => "frp",
        # Oïl: own-code varieties, then the codeless ones folding into fra
        "pic." => "pcd", "norm." => "nrf", "wall." => "wln", "agn." => "xno",
        "lorr." => "fra", "bourg." => "fra", "frcomt." => "fra",
        "saint." => "fra", "bourb." => "fra", "oïl." => "fra",
        # Romanian dialect geography
        "mold." => "ron", "ban." => "ron"
      }.freeze

      # The DÉRom notation → typeable-ASCII fold (class note; mirrors the
      # upstream filename convention).
      NOTATION_FOLD = { "ˈ" => "", "ˌ" => "", "β" => "b", "ɸ" => "f",
                        "ɛ" => "e", "ɔ" => "o", "ɪ" => "i", "ʊ" => "u" }.freeze

      LANGUAGE = "la-vul"

      # Parse one article file. Returns a DictionaryEntry, or nil for a
      # <NonRedige/> potiche. +entry_id+ is the upstream filename stem.
      def parse_entry(path, entry_id:)
        article = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict).at_xpath("/DERom/Article") or
          raise Nabu::ValidationError, "no <DERom><Article> element"
        return nil if article.at_xpath("NonRedige")

        lemme = article.at_xpath("Lemme") or
          raise Nabu::ValidationError, "no <Lemme> and no <NonRedige/> — an unknown article shape"
        build_entry(article, lemme, entry_id)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ValidationError, "malformed XML: #{e.message}"
      end

      private

      def build_entry(article, lemme, entry_id)
        signifiant = text(lemme.at_xpath("Signifiant"))
        raise Nabu::ValidationError, "empty <Signifiant>" if signifiant.nil? || signifiant.empty?

        reflexes = reflexes(article)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: signifiant, language: LANGUAGE,
          headword: Nabu::Normalize.nfc(signifiant),
          headword_folded: fold_headword(signifiant),
          gloss: text(lemme.at_xpath("Signifie")),
          body: body_text(article, lemme, signifiant),
          reflexes: reflexes
        )
      end

      def fold_headword(signifiant)
        Nabu::Normalize.search_form(signifiant.gsub(/[ˈˌβɸɛɔɪʊ]/, NOTATION_FOLD), language: LANGUAGE)
      end

      # -- reflexes ---------------------------------------------------------------

      # Depth-first over Materiaux subdivs, cognats in document order, the
      # positional idiome→signifiant walk (class note), exact duplicates
      # deduped, THEN composite citations split (P57-5) so dedup sees the
      # original upstream pair, not an already-split one.
      def reflexes(article)
        article.xpath("Materiaux/subdiv/cognats/*[self::premier.cognat or self::cognat]")
               .flat_map { |cognat| idiome_runs(cognat).flat_map { |idiome, words| words.map { |w| [idiome, w] } } }
               .uniq
               .flat_map { |idiome, word| split_idiome(idiome).map { |single| [single, word] } }
               .map { |idiome, word| build_reflex(idiome, word) }
      end

      # A composite citation like "gal./port." names two idiomes sharing one
      # signifiant (P57-5: DÉRom's own citation shorthand — "leite" serves
      # both Galician and Portuguese — not upstream error). Split on "/"
      # into the component idiomes (each already ends in its own "."), so
      # each mints its own resolved reflex row instead of one display-only
      # joint label. Idiomes without a "/" pass through unchanged.
      def split_idiome(idiome)
        idiome.include?("/") ? idiome.split("/") : [idiome]
      end

      # [[idiome, [word, …]], …] in document order — each signifiant
      # attaches to the nearest preceding idiome.
      def idiome_runs(cognat)
        runs = []
        cognat.element_children.each do |child|
          case child.name
          when "idiome" then runs << [text(child), []]
          when "signifiant" then runs.last&.last&.push(text(child))
          end
        end
        runs.reject { |idiome, words| idiome.to_s.empty? || words.empty? }
      end

      def build_reflex(idiome, word)
        language = IDIOME_LANGUAGES[idiome]
        nfc = Nabu::Normalize.nfc(word)
        folded = Nabu::Normalize.search_form(nfc, language: language)
        Nabu::DictionaryReflex.new(
          lang_code: language || idiome, language: language, word: nfc,
          word_folded: folded.empty? ? nil : folded,
          borrowed: false
        )
      end

      # -- body -------------------------------------------------------------------

      # The readable article: the lemma line, the materials (one titre line
      # per subdiv, one line per cognat), the Commentaire paragraphs, the
      # renvoi link. Bibliographie/Signatures/Notes stay out (class note).
      def body_text(article, lemme, signifiant)
        lines = [lemma_line(lemme)]
        article.xpath("Materiaux/subdiv").each { |subdiv| lines.concat(subdiv_lines(subdiv)) }
        commentaire = article.xpath("Commentaire/p").map { |p| text(p) }.reject(&:empty?)
        lines.push("Commentaire", *commentaire) unless commentaire.empty?
        lien = text(article.at_xpath("Lien"))
        lines << "Renvoi : #{lien}" if lien && !lien.empty?
        Nabu::Normalize.nfc(lines.compact.reject(&:empty?).join("\n"))
                       .then { |body| body.empty? ? Nabu::Normalize.nfc(signifiant) : body }
      end

      def lemma_line(lemme)
        catgramm = text(lemme.at_xpath("catgramm"))
        signifie = text(lemme.at_xpath("Signifie"))
        [catgramm, signifie && !signifie.empty? ? "« #{signifie} »" : nil].compact.join(" ")
      end

      def subdiv_lines(subdiv)
        titre = text(subdiv.at_xpath("titre"))
        etym = text(subdiv.at_xpath("etym"))
        header = [titre, etym && !etym.empty? ? "*/#{etym}/" : nil].compact.reject(&:empty?).join(" — ")
        lines = header.empty? ? [] : [header]
        subdiv.xpath("cognats/*[self::premier.cognat or self::cognat]").each do |cognat|
          lines << cognat_line(cognat)
        end
        lines
      end

      # "dacoroum. lapte s.n. « … »"; variant signifiants of one idiome run
      # join with ", ", successive idiome runs with " ; ".
      def cognat_line(cognat)
        runs = idiome_runs(cognat).map { |idiome, words| "#{idiome} #{words.join(', ')}" }
        catgramm = text(cognat.at_xpath("catgramm"))
        signifie = text(cognat.at_xpath("signifie"))
        [runs.join(" ; "), catgramm, signifie && !signifie.empty? ? "« #{signifie} »" : nil]
          .compact.reject(&:empty?).join(" ")
      end

      # Collapsed text of +node+ (the files are pretty-printed — inner
      # whitespace runs are formatting, never content); nil for nil nodes.
      def text(node)
        node && node.text.gsub(/\s+/, " ").strip
      end
    end
  end
end
