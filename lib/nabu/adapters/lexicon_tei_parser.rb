# frozen_string_literal: true

require "nokogiri"

require_relative "../betacode"
require_relative "../normalize"

module Nabu
  module Adapters
    # The lexicon-tei parser family (P11-4): Perseus dictionary TEI — P4
    # (<TEI.2> + PersDict DTD, unfetchable offline; the Reader streams past
    # it, the P9-2 experience) with entryFree entries under
    # div0[@type="alphabetic letter"]. Streams with Nokogiri::XML::Reader
    # (LSJ letter files run to 43 MB, Lewis & Short to 77 MB — CLAUDE.md's
    # no-DOM-over-5MB rule) and DOM-parses one ENTRY at a time, which is the
    # natural unit and never large (the ~300 KB λόγος entry is the known
    # maximum).
    #
    # == What one entry yields (Nabu::DictionaryEntry)
    #
    # - headword: the first <orth> (fallback: the @key), betacode-decoded for
    #   LSJ (+betacode: true+ — its keys, orths and Greek quotes are all
    #   betacode; Lewis & Short eng2 is already Unicode).
    # - headword_folded: minted from the @key — decoded, stem hyphens and
    #   trailing homograph digits stripped ("mh=nis" → μηνισ, "a2" → a) —
    #   through Normalize.search_form with the dictionary language, the same
    #   both-sides fold contract as lemma search (conventions §9).
    # - gloss: the first <tr>; when a lexicon glosses in italics instead
    #   (Lewis & Short), the first non-abbreviation <hi rend="ital"> of the
    #   FIRST sense (an italic run ending in "." is a grammatical
    #   abbreviation — "gen. plur." — not a gloss). Best-effort: nil is
    #   honest for cross-reference stubs.
    # - body: the whole entry as plain text, whitespace collapsed, each
    #   <sense> starting a new line prefixed with its @n label, Greek decoded.
    # - citations: one DictionaryCitation per <bibl> whose @n is a urn:cts:
    #   value (the 2014 upstream revision put CTS urns there); the @n is kept
    #   verbatim, the work-level prefix and dot-joined citation are derived
    #   for query-time resolution. URN-less and non-CTS bibls ("Dig. 33.6.9")
    #   mint no row — their display text still reads in the body.
    # - crossrefs (P123-1): one DictionaryCrossref per <xr>/<ref> pointer
    #   (kind from the <lbl>, target decoded and folded like @key) — see
    #   XR_KINDS for the census.
    class LexiconTeiParser
      ENTRY_ELEMENT = "entryFree"

      # First <tr> or italic run of the FIRST sense, in document order,
      # skipping quote translations (anything inside <cit>) and grammatical
      # abbreviations (italic runs ending in "." — "gen. plur."). Best-effort:
      # nil is honest (see #gloss).
      GLOSS_XPATH = %(.//tr[not(ancestor::cit)] | .//hi[@rend="ital"][not(ancestor::cit)])

      # P123-1: LSJ's <xr><lbl>v.</lbl> <ref>mu=qos</ref></xr> pointers —
      # the label names the relation, the ref the headword (betacode).
      # Normalized label (downcased, spaces dropped) => kind. Census
      # 2026-10-13 over the 27 LSJ files (116,497 entries): 27,091
      # pointers on 23,204 entries — equals 14,719 ("="), see 7,647 ("v.",
      # "s.v.", unlabeled), variant 2,346 ("v.l.", "v.l. for"),
      # false-reading 998 ("f.l. for"), gloss 877 ("gloss on"), like 504;
      # 15,501 resolve to a unique LSJ headword, 1,137 are ambiguous
      # homographs (left verbatim), the rest point at phrases or unheld
      # forms. Lewis & Short carries no <xr>. An unlisted or absent label
      # reads as a plain "see".
      XR_KINDS = {
        "=" => "equals", "v." => "see", "s.v." => "see",
        "v.l." => "variant", "v.l.for" => "variant",
        "f.l." => "false-reading", "f.l.for" => "false-reading",
        "glosson" => "gloss", "like" => "like"
      }.freeze

      # == <etym> mining (opt-in per lexicon: the +etym:+ mode)
      #
      # :lsj — every <etym lang="greek"> names the base word(s) the
      # headword is formed from, "(fr. X)" (census 2026-10-19 over the 27
      # letter files: 9,703 tags on 8,554 entries, 7,223 at entry level and
      # 2,480 inside senses — the in-sense ones are the same parenthetical
      # pointer, often a preverb "(kat-)"). One "etym" crossref per comma
      # item, betacode-decoded, a leading "=" equation mark dropped, folded
      # exactly like @key — exact-headword resolution only; a phrase or
      # preverb target ("ὁ λ.", "κατ-") simply never resolves and renders
      # verbatim.
      #
      # :lewis_short — the 21,805 <etym> tags of the Unicode eng2 file (the
      # 43k figure counts both shipped copies; only eng2 is ingested) fall
      # into three shapes, each classified whole:
      #   BASE (12,781 + the homograph/sense-labelled variants): the etym
      #     is a Latin word, comma list or hyphen compound ("abnuo",
      #     "bis-metrum", "clarus - facio", "2. in-partibilis",
      #     "durus, II. B.") — the homograph number and trailing sense
      #     label are pointers INTO the base entry and fold off; one "etym"
      #     crossref per hyphen part, exact-headword resolution.
      #   COGNATE CHAIN (~2k): the etym carries a language label from
      #     LS_LANGUAGE_LABELS or a "Gr." Greek run — one "cognate" reflex
      #     per labeled form (the first word after the label, "root"
      #     skipped) and per Greek item of each <foreign lang="greek">.
      #   GREEK SOURCE: the etym is nothing but Greek <foreign> runs
      #     ("ὕδωρ" under hydrius) — the Latin word's own source, a
      #     "derived" (UP) reflex per Greek item.
      # Everything else is prose ("id.", "from the root tem, whence also
      # temno") and mints nothing — never a guess at prose.
      #
      # Lewis & Short's cognate-language labels → catalog tags, the closed
      # table (label census over the 1,995 cognate-chain etyms, counts in
      # parentheses). Codes align with the kaikki crosswalk and MW's
      # COGNATE_LANGS so rows meet on (language, word_folded); modern
      # national languages take their modern code (the MW Germ./Eng.
      # precedent). nil = a recognised label with no honest single code:
      # the label rides lang_code verbatim, language nil (display-only).
      # "Lat." (216) is deliberately absent — an intra-Latin relative is
      # no cognate edge; Greek dialect labels (Dor. 7, Aeol. 4, Ion. 2) and
      # "Gr." (700) only mark the chain — Greek forms come from <foreign>.
      LS_LANGUAGE_LABELS = {
        "Sanscr." => "san", "Sanscr" => "san", # 585 + 10 — Sanskrit
        "Goth." => "got", # 57
        "O. H. Germ." => "goh", # 41 — Old High German, explicit
        "Germ." => "de", "Ger." => "de", "mod. Germ." => "de", # 187 + 3 — modern German (MW)
        "Low Germ." => "nds", # Low German
        "Engl." => "en", "Eng." => "en", "Engl" => "en", # 143 + 11 + 2 — English (MW)
        "Angl.-Sax." => "ang", "Angl. -Sax." => "ang", "Angl. - Sax." => "ang", # Anglo-Saxon = Old English,
        "Ang.-Sax." => "ang", "Angl.Sax." => "ang", "Angl. Sax." => "ang", # spelled every way
        "Anglo-Saxon" => "ang", "Anglo-Sax." => "ang", "AngloSax." => "ang", "Angl. S." => "ang",
        "old Sax." => "osx", # Old Saxon
        "Lith." => "lit", # 10 — Lithuanian
        "Zend." => "ae", "Zend" => "ae", # 6 + 3 — Avestan (MW Zd.)
        "Umbr." => "xum", # 5 — Umbrian
        "Osc." => "osc", "Oscan" => "osc", # Oscan
        "Etrusc." => "ett", "Etrusk." => "ett", "Etruscan" => "ett", # 5 + 5 + 2
        "Heb." => "hbo", "Hebr." => "hbo", # 8 + 4 — Biblical Hebrew, L&S's Hebrew
        "Chald." => "arc", # Chaldee = Biblical Aramaic
        "Syr." => "syc", # Classical Syriac
        "Phoen." => "phn", # Phoenician
        "Copt." => "cop", # 2
        "Arab." => "ar", # 2
        "Pers." => "fa", # Persian (modern code, the MW national-language rule)
        "Slav." => "sla", # 7 — the Slavic collective (MW "Slav." precedent)
        "Norse" => "non", "old Norse" => "non", # Old Norse
        "Swed." => "sv", "Dutch" => "nl", "Fr." => "fr", "Ital." => "it", # 2, -, 19, 5
        "Welsh" => "cy", "Wal." => "cy", # 4 — Welsh
        "Breton." => "br", "Armor." => "br", # Breton (Armorican)
        "Irish" => "gle", # MW Hib. precedent: Irish, period unstated
        "old Irish" => "sga", # Old Irish, explicit
        "Celt." => nil, "Celtic" => nil, "Gallic" => nil, # 4 + 4 + 4 — a family, not a language
        "Sabine" => nil, # 7 — no ISO code
        "Old Germ." => nil, "O. Germ." => nil, "old Germ." => nil # 3 + 3 — OHG vs MHG unstated
      }.freeze

      # Longest first, so "O. H. Germ." wins over "Germ.", "Low Germ." over
      # "Germ.", "old Irish" over "Irish".
      LS_LABEL = Regexp.union(LS_LANGUAGE_LABELS.keys.sort_by { |label| -label.size })
      LS_CHAIN_MARKERS = /(?<![[:alpha:]])(?:Gr\.|Greek|Dor\.|Aeol\.|Ion\.)/
      # Not a cognate form: grammar/prose words that can follow a label.
      LS_STOPWORDS = %w[root in cf and also the etc perh prob acc lit orig prop plur from with].freeze
      LS_BASE_WORD = /\A[[:alpha:]]+(?:-[[:alpha:]]+)*\z/
      LS_SENSE_LABEL = /,\s*[IVX]+\.(?:\s*[A-Z]\.)?(?:\s*\d+\.)?\z/
      GREEK_ITEM = /\A\p{L}[\p{L}\p{M}'’-]*\z/
      # The form after a label: an optional comma, "root"/"root in"
      # skipped, one word-shaped token (possessive — never backtracked
      # short), and whether an abbreviation dot follows it.
      LS_FORM_AFTER_LABEL = /\A,?\s*(?:root\s+(?:in\s+)?)?(?<word>\p{L}[\p{L}\p{M}'’-]*+)(?<abbrev>\.?)/

      # Parse +path+ and return its DictionaryEntry values in file order.
      # +etym+ turns on <etym> mining (:lsj or :lewis_short, class note);
      # nil (the default) reads none.
      def entries(path, language:, betacode: false, etym: nil)
        collected = []
        File.open(path) do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
            next unless node.name == ENTRY_ELEMENT

            collected << build_entry(entry_element(node), language: language, betacode: betacode, etym: etym)
          end
        end
        collected
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "lexicon-tei: malformed XML in #{path}: #{e.message}"
      end

      private

      # One entry's subtree as its own small DOM (entries never nest).
      def entry_element(node)
        fragment = Nokogiri::XML.fragment(node.outer_xml)
        fragment.children.find(&:element?)
      end

      def build_entry(elem, language:, betacode:, etym:)
        key = elem["key"]
        raise Nabu::ParseError, "lexicon-tei: entryFree without @key (id #{elem['id'].inspect})" if key.nil?

        entry_id = elem["id"] || key
        etym_crossrefs, etym_reflexes = etym_edges(elem, mode: etym, language: language)
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: key, language: language,
          headword: headword(elem, key, betacode: betacode),
          headword_folded: fold_key(key, language: language, betacode: betacode),
          gloss: gloss(elem),
          body: body(elem, betacode: betacode),
          citations: citations(elem),
          crossrefs: crossrefs(elem, language: language, betacode: betacode) + etym_crossrefs,
          reflexes: etym_reflexes
        )
      end

      # -- <etym> mining (class note) -------------------------------------------------

      # [crossrefs, reflexes] for one entry; both empty unless +mode+ is set.
      def etym_edges(elem, mode:, language:)
        case mode
        when :lsj then [lsj_etym_crossrefs(elem, language: language), []]
        when :lewis_short then lewis_short_etym_edges(elem, language: language)
        else [[], []]
        end
      end

      def lsj_etym_crossrefs(elem, language:)
        elem.xpath(".//etym").flat_map do |etym|
          collapse(etym.text).split(",").filter_map do |item|
            raw = item.strip.sub(/\A=\s*/, "")
            next if raw.empty?

            target = Nabu::Normalize.nfc(Betacode.decode(raw)).strip
            # A bare betacode diacritic run decodes to nothing — no pointer
            # (and never a validation error quarantining the letter file).
            next if target.empty?

            etym_crossref(target, label: "etym #{target}", language: language)
          end
        end.uniq(&:target)
      end

      def lewis_short_etym_edges(elem, language:)
        crossrefs = []
        reflexes = []
        elem.xpath(".//etym").each do |etym|
          if (parts = ls_base_parts(etym))
            printed = parts.join(", ")
            parts.flat_map { |part| part.split("-") }.each do |base|
              crossrefs << etym_crossref(base, label: "etym #{printed}", language: language)
            end
          else
            reflexes.concat(ls_etym_reflexes(etym))
          end
        end
        [crossrefs.uniq(&:target), reflexes.uniq { |r| [r.lang_code, r.word] }]
      end

      # The BASE shape's Latin parts, or nil: an element-free etym whose
      # text — spaced hyphens closed, homograph number and trailing sense
      # label dropped — is a comma list of words/hyphen compounds.
      def ls_base_parts(etym)
        return nil unless etym.element_children.empty?

        text = collapse(etym.text).gsub(/\s+-\s+/, "-").sub(/\A\d\.\s*/, "").sub(LS_SENSE_LABEL, "")
        parts = text.split(/\s*,\s*/)
        parts if !parts.empty? && parts.all? { |part| part.match?(LS_BASE_WORD) }
      end

      # COGNATE CHAIN or GREEK SOURCE reflexes (class note), document
      # order; [] for prose.
      def ls_etym_reflexes(etym)
        pieces = etym_pieces(etym)
        plain = pieces.map { |kind, value| kind == :text ? value : " § " }.join.gsub(/\s+/, " ").strip
        ordered = pieces.flat_map do |kind, value|
          kind == :text ? ls_labeled_forms(collapse(value)) : value.map { |word| [:greek, word] }
        end
        labeled = ordered.any?(Nabu::DictionaryReflex)
        if labeled || plain.match?(LS_CHAIN_MARKERS)
          ordered.map { |item| item.is_a?(Array) ? reflex("grc", item.last, relation: "cognate") : item }
        elsif ordered.any? && plain.match?(/\A[\s,;.§]*\z/)
          ordered.map { |(_, word)| reflex("grc", word, relation: "derived") }
        else
          []
        end
      end

      # The etym's direct children as [:text, string] or [:greek, [word,
      # …]] — labels are read from the Latin-script prose, Greek forms from
      # the tagged runs (a non-Greek <foreign> reads as a blank).
      def etym_pieces(etym)
        etym.children.map do |child|
          next [:text, child.text] unless child.element? && child.name == "foreign"

          child["lang"] == "greek" ? [:greek, greek_items(child)] : [:text, " "]
        end
      end

      def greek_items(node)
        collapse(node.text).split(/\s*[,;]\s*/).filter_map do |item|
          word = Nabu::Normalize.nfc(item.strip)
          word if word.match?(GREEK_ITEM)
        end
      end

      # One reflex per label occurrence: the first word after it (an
      # optional comma, "root"/"root in" skipped), word-shaped, ≥ 2
      # letters, not an abbreviation (no trailing "."), not a stopword.
      def ls_labeled_forms(plain)
        plain.to_enum(:scan, LS_LABEL).filter_map do
          match = Regexp.last_match
          next unless label_boundary?(plain, match)

          form = plain[match.end(0)..].match(LS_FORM_AFTER_LABEL)
          next if form.nil? || form[:abbrev] == "."

          word = form[:word]
          next if word.delete("-").size < 2 || LS_STOPWORDS.include?(word.downcase)

          code = LS_LANGUAGE_LABELS.fetch(match[0])
          reflex(code || match[0], word, relation: "cognate", language: code)
        end
      end

      # A label must stand as its own token: not the tail of a longer word
      # ("Germ." inside "O. H. Germ." is consumed by the longer label —
      # the union is longest-first — but "Engl" must not match "English").
      def label_boundary?(plain, match)
        before = match.begin(0).zero? ? " " : plain[match.begin(0) - 1]
        after = plain[match.end(0)] || " "
        !before.match?(/[[:alpha:]]/) && (match[0].end_with?(".") || !after.match?(/[[:alpha:]]/))
      end

      def reflex(code, word, relation:, language: code)
        nfc = Nabu::Normalize.nfc(word)
        folded = Nabu::Normalize.search_form(nfc.sub(/-+\z/, ""), language: language)
        Nabu::DictionaryReflex.new(lang_code: code, language: language, word: nfc,
                                   word_folded: folded.strip.empty? ? nil : folded, relation: relation)
      end

      def etym_crossref(target, label:, language:)
        folded = Nabu::Normalize.search_form(target.delete("-").sub(/\d+\z/, ""), language: language)
        Nabu::DictionaryCrossref.new(kind: "etym", label: Nabu::Normalize.nfc(label), target: target,
                                     target_folded: folded.strip.empty? ? nil : folded)
      end

      # P123-1: one crossref per <xr>/<ref>; kind per XR_KINDS (census there).
      def crossrefs(elem, language:, betacode:)
        elem.xpath(".//xr").flat_map do |xr|
          lbl = collapse(xr.at_xpath("./lbl")&.text.to_s)
          kind = XR_KINDS.fetch(lbl.downcase.delete(" "), "see")
          xr.xpath("./ref").filter_map { |ref| crossref(ref, lbl, kind, language: language, betacode: betacode) }
        end
      end

      def crossref(ref, lbl, kind, language:, betacode:)
        raw = collapse(ref.text)
        return nil if raw.empty?

        greek = betacode && ref["lang"] == "greek" # the body walk's decode rule
        target = Nabu::Normalize.nfc(greek ? Betacode.decode(raw) : raw)
        folded = Nabu::Normalize.search_form(target.delete("-").sub(/\d+\z/, ""), language: language)
        Nabu::DictionaryCrossref.new(kind: kind, label: [lbl, target].reject(&:empty?).join(" "),
                                     target: target, target_folded: folded.strip.empty? ? nil : folded)
      end

      def headword(elem, key, betacode:)
        orth = elem.at_xpath(".//orth")
        raw = orth ? collapse(orth.text) : key
        raw = Betacode.decode(raw) if betacode
        Nabu::Normalize.nfc(raw)
      end

      # The lookup key: decoded @key, stem hyphens and trailing homograph
      # digits dropped, folded per the language rule table.
      def fold_key(key, language:, betacode:)
        source = betacode ? Betacode.decode(key) : key
        source = source.delete("-").sub(/\d+\z/, "")
        Nabu::Normalize.search_form(source, language: language)
      end

      def gloss(elem)
        scope = elem.at_xpath(".//sense") || elem
        scope.xpath(GLOSS_XPATH)
             .map { |node| collapse(node.text) }
             .find { |text| !text.empty? && !text.end_with?(".") }
      end

      # Linearize the entry: text in document order, whitespace collapsed,
      # sense boundaries as labeled line breaks, Greek decoded when the
      # lexicon is betacode-encoded.
      def body(elem, betacode:)
        buffer = +""
        walk(elem, buffer, greek: false, betacode: betacode)
        text = buffer.gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").strip
        Nabu::Normalize.nfc(text)
      end

      def walk(node, buffer, greek:, betacode:)
        node.children.each do |child|
          if child.text?
            text = child.text
            text = Betacode.decode(text) if betacode && greek
            buffer << text.gsub(/\s+/, " ")
          elsif child.element?
            buffer << sense_break(child) if child.name == "sense"
            walk(child, buffer, greek: greek || child["lang"] == "greek", betacode: betacode)
          end
        end
      end

      def sense_break(sense)
        label = sense["n"]
        label ? "\n#{label}. " : "\n"
      end

      def citations(elem)
        elem.xpath(".//bibl[@n]").filter_map do |bibl|
          urn_raw = bibl["n"]
          next unless urn_raw.start_with?("urn:cts:")

          label = collapse(bibl.text)
          next if label.empty?

          cts_work, citation = cite_parts(urn_raw)
          Nabu::DictionaryCitation.new(urn_raw: urn_raw, cts_work: cts_work,
                                       citation: citation, label: Nabu::Normalize.nfc(label))
        end
      end

      # "urn:cts:latinLit:phi0474.phi055.perseus-lat1:1:2:4" →
      # ["urn:cts:latinLit:phi0474.phi055", "1.2.4"]. Edition tokens are
      # dropped from the work prefix (see class note); colon-separated
      # citation parts join with dots (the catalog's citation-suffix shape).
      # Malformed urns still split honestly — they resolve to nothing later.
      #
      # A WORK-LEVEL reference carries no passage suffix: either exactly four
      # parts ("urn:cts:greekLit:tlg0012.tlg001") or a trailing colon that
      # splits to an empty suffix ("urn:cts:greekLit:tlg0027.tlg00101:" — 61 in
      # LSJ's α file, some in θ). Both mint citation nil, not "" — an empty
      # citation is not a valid DictionaryCitation and would quarantine the whole
      # letter file (the P11-7 census misread α/θ as "alternate editions"; they
      # are the largest and one ordinary letter sections, ~21k entries).
      def cite_parts(urn_raw)
        parts = urn_raw.split(":", -1)
        return [nil, nil] if parts.length < 4

        work = "urn:cts:#{parts[2]}:#{parts[3].split('.').first(2).join('.')}"
        citation = parts.length > 4 ? parts[4..].join(".") : nil
        citation = nil if citation && citation.empty?
        [work, citation]
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
