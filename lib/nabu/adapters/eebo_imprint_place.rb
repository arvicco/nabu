# frozen_string_literal: true

module Nabu
  module Adapters
    # The eebo-tcp imprint place: the BIBLFULL PUBPLACE (ESTC-style
    # transcription of the title-page imprint, "Imprinted at London :",
    # "[London? :", "Londini :", "In the Savoy [i.e. London] :") reduced at
    # parse time to the bare town name the place registry can key on. The
    # verbatim PUBPLACE keeps riding as source_pub_place; this is a
    # derived reading beside it, never a rewrite of it.
    #
    # Census (canonical/, 2026-10-20, all 60,326 files, first BIBLFULL
    # PUBPLACE per file — the parser's first-wins rule): 1,676 distinct
    # raw strings → 56,678 files (94.0%) with a certain town, 2,293
    # (3.8%) with a ?-marked conjecture, 1,355 unplaced (1,330 of them
    # upstream's own s.l./n.p. sine-loco answer). London alone is 51,697.
    #
    # The reading, in order:
    #   1. NFC; "[sic]" noted and dropped; scribal brackets spliced back
    #      into their word ("Lo[n]don" → "London").
    #   2. A cataloguer "[i.e. X]" correction outranks the printed imprint
    #      (the dating molds' CORRECTED precedent): "Oxford [i.e. London]"
    #      is London.
    #   3. The printed text outside cataloguer brackets is the claim; when
    #      it reads nothing (the whole imprint supplied, "[London] :"),
    #      the first bracket's content answers.
    #   4. Period furniture strips: the printing verb in its many
    #      spellings (Imprinted/Imprynted/Enprynted/Imprentit/Excusum/
    #      Printiedig/…), the preposition (at/in/yn/tot/à …), a leading
    #      dateline, "the famous cyte of", trailing "printed", and any
    #      shop/street/printer tail ("in Powles Churchyarde", "by Robert
    #      Barker"). A reprint names the artifact's own place: "Printed at
    #      London, and re-printed at Edinburgh" is Edinburgh.
    #   5. Latin, Welsh, French and period spellings fold to the English
    #      town through ALIASES (Londini/Llundain/Londres → London,
    #      Oxoniæ/Rhydychen → Oxford, Doway → Douai, Hage → The Hague …);
    #      misprints fold only where the cataloguer's own [sic] marks them.
    #   6. "?" anywhere in the segment read → the conjecture key, never the
    #      certain one (the dating stance: uncertainty never reads as a
    #      claim). s.l./s.n./n.p., "abroad", "unknown", and anything that
    #      does not read as a name (prose, damaged fragments under four
    #      letters) mint nothing.
    #
    # DECLARED COARSENESS:
    #   - a false or clandestine imprint no cataloguer corrected rides AS
    #     WRITTEN ("Amsterdam" on an English-printed tract, "Ratisbonne",
    #     fictitious towns): the imprint is the claim, the correction is
    #     the cataloguer's to make, not ours;
    #   - a region or country imprint ("[England]", "[Scotland?]",
    #     "Holland") rides as that region's name — the coarse grain is
    #     upstream's own;
    #   - two-place imprints ("London and Oxford", "Oxford or London",
    #     the conjecture "[Edinburgh? or St. Andrews?]") ride as written
    #     (no split, no pick); the name-shape word cap applies to each
    #     town of the pair, so a pair of multi-word towns still reads;
    #   - unmarked misspellings ("Lodnon", "Londou") ride as written — a
    #     fold needs the cataloguer's [sic], never our guess;
    #   - Westminster and Southwark stay their own towns (they were);
    #     the Savoy folds to London, ESTC's own reading;
    #   - "Boston" is not disambiguated here (the corpus's Boston prints
    #     are New England's — the place registry carries that decision);
    #     Cambridge alone splits, by the imprint's own Mass./New England
    #     signal, into "Cambridge" and "Cambridge, Mass.".
    module EeboImprintPlace
      CORRECTION = /\[\s*i\.\s*e\.?,?\s*([^\]]*)\]?/i
      SIC = /\[\s*sic\s*\]/i
      # A bracket splicing letters into a word: Lo[n]don, [Lo]ndon.
      SPLICE = /(?<=[[:alpha:]])\[([[:alpha:]]{1,3})\]|\[([[:alpha:]]{1,3})\](?=[[:alpha:]])/
      VERB = /(?:[ij]mp[rk]|e[mn]pr|inpr|pr[iyaeo]{1,2}n|prentid|pranted|printhed|reprinted|re-printed|excu|
                impress|imprim|stampato|g(?:h)?edruckt|printiedig|argraphwyd|made\b)/ix
      LEAD_VERB = /\A(?:(?:and\s+)?(?:be\s+)?(?:newe?l[yi]e?|first|re-?)\s*)?#{VERB}[[:alpha:]\[\]]*[\s,.]*/i
      LEAD_PREP = /\A(?:and|at|att|ad|in|yn|yng|tot|en|à|â|á|a|to|from|de|the|theat(?:er|re)\s+in)\s+/i
      LEAD_JUNK = /\A(?:by|secretly|first|newly|for)\b.*?\b(?:at|in)\s+/i
      WELSH = /\byn\s+(?:y\s+|ninas\s+)?(.+)/i
      CITY_OF = /\A.*?\b(?:cyte|city|citie|cittie)\s+of\s+/i
      REPRINT = /\b(?:re-?printed|nowe?)\s+(?:at|in)\s+(.+)/i
      TRAIL_VERB = /\s+(?:re-?)?(?:printed|imprinted|reprinted)\b.*\z/i
      LEAD_DATE = /\A(?:(?:[[:alpha:]]+\.|(?:jan|feb|mar|apr|may|jun|jul|aug|sep|set|oct|nov|dec)[[:alpha:]]*)?
                     \s*\d{1,4}\.?\s+)+/ix
      CUT = /\s*[,:;]\s*|\s+(?:in|by|of|within|neere|near|for|a\s+city)\s+/i
      US = /\bMass(?:achusetts|achusets)?\b|\bN(?:ew)?[\s.=-]*E(?:ngland)?\b|Nov:?\s*Ang/
      SINE = /\A(?:s\.?\s*[l1]|s\.?\s*n|n\.?\s*p)\.?\z/i
      NOT_A_PLACE = %w[abroad unknown].freeze
      # A leading function word means the reading landed on prose.
      PROSE_HEAD = %w[by for and our].freeze
      # Cataloguer qualifiers riding after the town ("Oxford [Oxfordshire]").
      QUALIFIER = /\s+(?:mass(?:achusetts?)?|nov\b.*|oxfordshire|cambridgeshire|yorkshire|england)\z/i

      # The cataloguer's own [sic] marks a misprint of the town it spells.
      SIC_MISPRINTS = {
        "loudon" => "London", "londn" => "London", "lodon" => "London", "lonon" => "London",
        "londgn" => "London", "londom" => "London", "londod" => "London", "oondon" => "London",
        "londoon" => "London", "warerford" => "Waterford", "amstredam" => "Amsterdam"
      }.freeze

      # Imprint forms → the English town (keys downcased). Each line is an
      # attested census form; Latin locatives, Welsh/French/Italian/Dutch
      # exonyms, and period spellings.
      ALIASES = {
        # London: Latin locatives, French/Italian/Dutch/Welsh/Gaelic
        # exonyms, Caer Ludd, the "Nod-nol" reversal, ESTC's Savoy reading
        "londini" => "London", "londoni" => "London", "londinensis" => "London", "lond" => "London",
        "londres" => "London", "londre" => "London", "londrez" => "London", "londra" => "London",
        "londen" => "London", "llundain" => "London", "lundain" => "London", "llùndain" => "London",
        "lunnduin" => "London", "haerludd" => "London", "ghaer ludd" => "London", "ludd" => "London",
        "nod-nol" => "London", "nod-lon" => "London", "savoy" => "London", "the savoy" => "London",
        "oxoniæ" => "Oxford", "oxoniae" => "Oxford", "oxonii" => "Oxford", "oxon" => "Oxford",
        "oxforde" => "Oxford", "rhydychen" => "Oxford",
        "cantabrigiæ" => "Cambridge", "cantabrigiae" => "Cambridge", "cantebrigiæ" => "Cambridge",
        "edinburgi" => "Edinburgh", "edenburgi" => "Edinburgh", "edinburghi" => "Edinburgh",
        "edinbvrgh" => "Edinburgh", "edenburgh" => "Edinburgh", "edinborough" => "Edinburgh",
        "eclinburgh" => "Edinburgh", "edingburgh" => "Edinburgh", "edinburg" => "Edinburgh",
        "edenborough" => "Edinburgh", "edenburg" => "Edinburgh", "edenbrough" => "Edinburgh",
        "edynburgh" => "Edinburgh", "holy-rood-house" => "Edinburgh",
        "aberdene" => "Aberdeen", "aberdoniæ" => "Aberdeen", "abredoniæ" => "Aberdeen", "abredeis" => "Aberdeen",
        "dvblin" => "Dublin", "dublinii" => "Dublin",
        "yorke" => "York", "bristoll" => "Bristol", "exon" => "Exeter", "colechester" => "Colchester",
        "ippeswich" => "Ipswich", "ippeswych" => "Ipswich", "ippyswiche" => "Ipswich",
        "cantorbury" => "Canterbury", "gateside" => "Gateshead",
        "westmestre" => "Westminster", "westmynstre" => "Westminster", "westminister" => "Westminster",
        "westmester" => "Westminster", "westmynster" => "Westminster",
        "southwarke" => "Southwark", "sowthwarke" => "Southwark",
        "mwŷthig" => "Shrewsbury", "mwythig" => "Shrewsbury",
        "corke" => "Cork", "corck" => "Cork", "corcke" => "Cork", "vvaterford" => "Waterford",
        "sanctandrois" => "St Andrews", "sainct-andrewes" => "St Andrews", "sainct-andrews" => "St Andrews",
        "doway" => "Douai", "douay" => "Douai", "duaci" => "Douai", "doüay" => "Douai", "dovvay" => "Douai",
        "st. omer" => "Saint-Omer", "s. omers" => "Saint-Omer", "st. omers" => "Saint-Omer",
        "st.-omer" => "Saint-Omer", "saint omers" => "Saint-Omer", "audomari" => "Saint-Omer",
        "louanii" => "Leuven", "lovanii" => "Leuven", "lovanni" => "Leuven", "louaine" => "Leuven",
        "louain" => "Leuven", "lovain" => "Leuven", "louvain" => "Leuven",
        "antwerpe" => "Antwerp", "antvverpe" => "Antwerp", "antwarp" => "Antwerp", "antwerpiæ" => "Antwerp",
        "antverpiæ" => "Antwerp", "antuerpiae" => "Antwerp", "antuerpiæ" => "Antwerp", "anwerp" => "Antwerp",
        "anwerpe" => "Antwerp", "anvverpe" => "Antwerp", "andwerpe" => "Antwerp", "antworp" => "Antwerp",
        "amstelredam" => "Amsterdam", "amstelrodam" => "Amsterdam", "ampsterdam" => "Amsterdam",
        "amsterodam" => "Amsterdam", "amsterledam" => "Amsterdam",
        "middelburgh" => "Middelburg", "middleburg" => "Middelburg", "middleburgh" => "Middelburg",
        "middelborough" => "Middelburg", "midlebrugh" => "Middelburg",
        "hague" => "The Hague", "hage" => "The Hague", "hagh" => "The Hague", "haghe" => "The Hague",
        "the hague" => "The Hague", "the hage" => "The Hague", "gravenhagh" => "The Hague",
        "leyden" => "Leiden", "leida" => "Leiden", "dort" => "Dordrecht", "roterdame" => "Rotterdam",
        "delph" => "Delft", "delf" => "Delft", "delff" => "Delft",
        "flushing" => "Vlissingen", "flishing" => "Vlissingen",
        "parisius" => "Paris", "parys" => "Paris", "roan" => "Rouen", "roane" => "Rouen", "roüen" => "Rouen",
        "rowen" => "Rouen", "rhemes" => "Reims", "rheims" => "Reims", "rheins" => "Reims",
        "rochell" => "La Rochelle", "lyons" => "Lyon",
        "collen" => "Cologne", "cullen" => "Cologne", "frankofourd" => "Frankfurt", "hamburgh" => "Hamburg",
        "stutgart" => "Stuttgart", "marpurg" => "Marburg", "strasburgh" => "Strasbourg",
        "gant" => "Ghent", "gante" => "Ghent", "bruxelles" => "Brussels", "mackline" => "Mechelen",
        "mechlin" => "Mechelen", "liege" => "Liège", "lvyck" => "Liège",
        "geneua" => "Geneva", "genevah" => "Geneva", "basil" => "Basel",
        "zurych" => "Zürich", "zurich" => "Zürich", "venetiis" => "Venice", "venetia" => "Venice",
        "gottenberge" => "Gothenburg"
      }.freeze

      module_function

      # {"imprint_place" => town} for a certain reading,
      # {"imprint_place_conjecture" => town} for a ?-marked one, {} when
      # the imprint names no place (or nothing at all).
      def call(raw)
        return {} if raw.nil?

        text = raw.unicode_normalize(:nfc).gsub(/[[:space:]]+/, " ").strip
        return {} if text.empty?

        sic = SIC.match?(text)
        text = text.gsub(SIC, "").gsub("[[", "[").sub(/\A(?:\.\.\.\s*)+/, "").sub(/\A\[\s*\.\.\.\s*/, "[")
        text = text.gsub(SPLICE) { Regexp.last_match(1) || Regexp.last_match(2) }
        us = US.match?(text)
        name, segment = reading(text, sic: sic)
        return {} if name.nil?

        name = "Cambridge, Mass." if us && name == "Cambridge"
        { segment.include?("?") ? "imprint_place_conjecture" : "imprint_place" => name }
      end

      # [town, the segment it was read from] or nil.
      def reading(text, sic:)
        if (match = CORRECTION.match(text))
          segment = match[1]
          name = finish(clean(segment), sic: sic)
          return name && [name, segment]
        end
        outside = text.gsub(/\[[^\]]*\]?/, " ")
        name = finish(clean(outside), sic: sic)
        return [name, outside] if name

        supplied = text.scan(/\[([^\]]*)\]?/).flatten.first.to_s
        name = finish(clean(supplied), sic: sic)
        name && [name, supplied]
      end

      def clean(text)
        s = text.delete("?").gsub(/\([^)]*\)?/, " ").strip
        s = s.sub(LEAD_DATE, "") if s.match?(/\d/)
        if (match = REPRINT.match(s))
          s = match[1]
        end
        s = s.sub(CITY_OF, "")
        if (match = WELSH.match(s))
          s = match[1]
        end
        s = s.sub(LEAD_VERB, "").sub(LEAD_JUNK, "")
        s = s.sub(LEAD_PREP, "") while s.match?(LEAD_PREP)
        s = s.sub(TRAIL_VERB, "")
        s = s.split(CUT).first.to_s
        s.gsub(/[\[\]()"]/, "").sub(/[\s.']+\z/, "").strip
      end

      def finish(cleaned, sic:)
        return nil if cleaned.empty? || SINE.match?(cleaned)

        cleaned = cleaned.sub(QUALIFIER, "")
        key = cleaned.downcase
        name = (sic && SIC_MISPRINTS[key]) || ALIASES[key] || cleaned
        name = name[0].upcase + name[1..] if name.match?(/\A[[:lower:]]/)
        name_shaped?(name) ? name : nil
      end

      # The joint of a two-place imprint ("Oxford or London").
      PAIR = /\s+(?:or|and)\s+/i

      def name_shaped?(name)
        return false if NOT_A_PLACE.include?(name.downcase)
        return false unless name.match?(/\A[[:alpha:]][[:alpha:]'. -]*\z/)
        return false unless name.split(PAIR).all? { |town| !town.empty? && town.split.size <= 3 }
        return false if name.gsub(/[^[:alpha:]]/, "").length < 4
        return false if name.split.any? { |word| word.gsub(/[^[:alpha:]]/, "").length < 2 }

        !PROSE_HEAD.include?(name.split.first.downcase)
      end
    end
  end
end
