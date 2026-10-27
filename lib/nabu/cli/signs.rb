# frozen_string_literal: true

# Nabu::CLI — character and sign desks: char, signs, info. Carved out of
# lib/nabu/cli.rb, the registry that loads it.
module Nabu
  class CLI < Thor
    desc "char CHAR", "The character/sign desk card: Han, Cuneiform, or Egyptian Hieroglyphs"
    long_desc <<~HELP, wrap: false
      The character card (P37-4; sign legs P65): one glyph in, the full held
      identity out — dispatched by script. A Han character gets the P37-4
      dictionary-shelf card below; a CUNEIFORM glyph (𒊬, compounds like
      𒋀𒀊 included) gets the OSL sign card (name · @aka · MZL/LAK/ABZL/
      HZL/ŠL list concordances · the OSL 00etc concordances: Labat/AKS/ATU/
      PGSL, MZL↔KWU, eBL names, Attinger/short-form value maps · values by
      language · CDLI meaning glosses · variant forms · fulltext
      attestation); an EGYPTIAN HIEROGLYPH (𓅃)
      gets the Unikemet card (Gardiner-plus catalog code · description ·
      function · phonetic value · JSesh/Hieroglyphica/IFAO concordances ·
      aes corpus attestation). Multi-character input is the sign-NAME lane,
      never a text lane: an OSL sign name or value spelling (SAR, szesz,
      |ŠEŠ.AB| — C-ATF ASCII folds apply, and a trailing x reads as the ₓ
      subscript: idx → idₓ), then a sign-list concordance number — MZL535
      qualified, or bare 535/852 matched across every held list (MZL, LAK,
      ABZL, HZL, ŠL, …), each hit naming the token that matched — then a
      Gardiner-style code (G5, N35). The sign cards need their modules
      synced: nabu sync osl / nabu sync unikemet. A Han READING also
      resolves: pinyin (wen · wén — toneless input folds tones) via Unihan
      kMandarin, and Japanese via KANJIDIC2 on/kun — as kana (ひと · タイ,
      hiragana/katakana fold together, okurigana dots are notation) or as
      ROMAJI on the dictionary-caps convention, no kana keyboard needed:
      ALL-CAPS is an on'yomi (TAI · KOKU), lowercase a kun'yomi (hito ·
      kuni; lowercase also answers as pinyin, each hit labeled). Every
      lane lists every character that carries the reading.

      --json emits the frozen machine contract the Edubba downstream
      consumes — the cuneiform/hieroglyph sign cards (P65) and the Han
      card (P72-2) alike; an ambiguous value input lists ALL candidate
      signs, never one silently.

      The Han card composes every shelf the library holds — the join no
      single dictionary site offers. It matches Jisho's synchronic
      completeness field-for-field where a shelf backs it, and exceeds it
      diachronically with a column no online dictionary carries. The binding
      rule everywhere: a field whose shelf can't back THIS character is
      ABSENT, never rendered "—".

      Sections, in render order (each names its backing shelf; absent
      sections are silently omitted):

        header        glyph · total strokes · KangXi radical number+name
                      (Unihan kRSUnicode/kTotalStrokes)
        decomposition the IDS structure + its components, each with the
                      follow-up commands to walk into it (BabelStone IDS)
        components    the flat component index Jisho searches (KRADFILE)
        variants      trad/simp/semantic/z-variant forms (Unihan)
        readings ja   on/kun/nanori + meanings (KANJIDIC2)
        readings      Mandarin/Korean/Vietnamese + the Unihan kJapanese layer
        pedagogy      Jōyō grade · JLPT · newspaper frequency (KANJIDIC2)
        desk-ref      the reference codes, zero suppressed — Unicode always,
                      four-corner/SKIP/JIS/dic numbers where KANJIDIC2 holds
                      them
        — the diachronic column (where nabu exceeds Jisho) —
        Old Chinese   Baxter-Sagart reconstruction + gloss
        phonetic series 諧聲 neighbours — the other held characters of the
                      glyph's Karlgren GSR series, with their OC readings
                      (Baxter-Sagart's GSR column)
        Middle Chinese Qieyun reading, 反切, 音韻地位 (tshet-uinh)
        early Japan   positions in the Heian hanzi dictionaries (HDIC)
        TLS           sense-level concepts + classical attestation counts
        corpus        attestation frequency across the held corpora
        search        the printed `search CHAR*`-family follow-ups

      The card's grain is ONE glyph (or one sign name/code). The
      component-search siblings are `nabu search --radical N`,
      `--strokes A-B` and `--char-component C`.

      Examples:
        nabu char 棄       # reject/abandon — radical 75 木, the whole card
        nabu char 木       # the component itself; its containment neighbours
        nabu char 𒊬       # the cuneiform sign card (SAR)
        nabu char idₓ      # an ambiguous value — every candidate listed
        nabu char 𓅃       # the falcon — Unikemet card
        nabu char G5       # the same sign by Gardiner-style code
        nabu char wen      # every Han character read wén/wěn/wèn…
        nabu char ひと     # every kanji with the kun reading ひと
        nabu char TAI      # CAPS romaji = on'yomi タイ
        nabu char kuni     # lowercase romaji = kun'yomi くに
    HELP
    option :json, type: :boolean, default: false,
                  desc: "Sign cards only: emit the frozen machine-readable contract"
    option :as, type: :string,
                desc: "Narrow an ambiguous input to ONE lens: identity · reading · sign · han " \
                      "(P86-5 — `char a` is a Latin letter AND a reading AND a sign value)"
    def char(glyph = nil)
      input = Nabu::Normalize.nfc(glyph.to_s.strip)
      if input.empty?
        raise Thor::Error, "char: give a character (e.g. nabu char 棄) or a sign name/code " \
                           "(nabu char SAR · nabu char G5)"
      end

      config = Nabu::Config.load
      return char_as_lens(config, input) if options[:as]

      case Nabu::CharDispatch.lane(input)
      when :cuneiform then cuneiform_char_card(config, input)
      when :hieroglyphic then hieroglyphic_char_card(config, input)
      when :marks then editorial_marks_char_card(config, input)
      when :name then name_char_card(config, input)
      else han_char_card(config, input)
      end
    end

    desc "signs URN|TEXT", "Sign-by-sign reading of ATF transliteration through the Oracc Sign List"
    long_desc <<~HELP, wrap: false
      The cuneiform sign desk (P53-2): ATF transliteration resolved token by
      token through the Oracc Sign List (the osl module, `nabu sync osl`)
      into sign identities — value → sign name → Unicode codepoint(s)/glyph.
      The sign list adds IDENTITY, not curriculum: what each spelled value
      is, never what to make of it.

      Input is EITHER a passage/document urn out of the ATF corpora
      (cdli/oracc/ebl/etcsl shelves — the catalog is opened read-only,
      language taken from the row) OR raw ATF transliteration text
      (language via --lang; no catalog needed). C-ATF ASCII folds apply
      (sz→š, s,→ṣ, t,→ṭ, '→ʾ, u2→u₂); the ETCSL romanization (c→š, j→ŋ)
      folds automatically for etcsl urns and under --dialect etcsl for raw
      text.

      Every token carries one honest status: deterministic · qualified
      (valueₓ(SIGN) — the explicit sign resolved) · ambiguous (ALL candidate
      signs listed, never one silently) · no-codepoint (sign resolved,
      honestly unencoded upstream) · broken (x, [...]) · unknown (not in the
      OSL — said plainly). Determinatives ({d}, {gesz}) are unbraced and
      marked det. Absent data is ABSENT, never "—".

      --json emits the frozen machine contract (one object: mode/urn/
      language/dialect/source envelope, per-line token records with
      input_value · status · sign_name · codepoints[] · candidates[] ·
      language_qualifier) — the same shape the MCP nabu_signs tool serves;
      downstream consumers (Edubba reading panels) script against it.

      Examples:
        nabu signs 'lugal-e {d}en-lil2-ra'      # raw C-ATF, folded and resolved
        nabu signs --dialect etcsl 'cag4-ta'    # ETCSL romanization
        nabu signs urn:nabu:cdli:p469841        # every line of the tablet
        nabu signs --json 'szesz' | jq .        # the frozen contract
    HELP
    option :lang, type: :string, banner: "CODE",
                  desc: "Language filter for %lang-qualified sign readings (urn mode " \
                        "defaults to the passage's language)"
    option :dialect, type: :string, banner: "NAME",
                     desc: "Transliteration dialect: etcsl (c→š, j→ŋ; auto for etcsl urns)"
    option :json, type: :boolean, default: false,
                  desc: "Emit the frozen machine-readable contract instead of columns"
    def signs(*input)
      raw = input.join(" ").strip
      if raw.empty?
        raise Thor::Error, "signs: give a passage urn or raw ATF transliteration " \
                           "(e.g. nabu signs 'lugal-e {d}en-lil2-ra')"
      end

      config = Nabu::Config.load
      list = Nabu::SignList.load_default(config: config)
      if list.nil?
        raise Thor::Error, "signs: no sign list on this box yet — run `nabu sync osl` " \
                           "(the Oracc Sign List module), then retry"
      end

      dialect = signs_dialect(options[:dialect])
      catalog = nil
      if raw.start_with?("urn:")
        catalog = open_catalog(config)
        raise Thor::Error, "signs: no corpus — run nabu sync or nabu rebuild" unless catalog

        result = signs_urn_result(raw, list: list, catalog: catalog, dialect: dialect)
      else
        result = Nabu::Query::Signs.new(sign_list: list)
                                   .run_text(raw, language: options[:lang], dialect: dialect || :catf)
      end

      if options[:json]
        say JSON.generate(Nabu::Query::Signs.json_payload(result))
      else
        print_signs(result)
      end
    ensure
      catalog&.disconnect
    end

    desc "info QUERY", "One front door: the character, language/lect, or script dossier card for QUERY"
    long_desc <<~HELP, wrap: false
      The dossier front door (P90-5): one command that answers "what is
      this?" across the three desk namespaces, dispatching to the existing
      cards byte-identically — an alias, never a reimplementation:

        1. a single character (any non-ASCII grapheme) or a Gardiner-style
           sign code (G5, Aa27)                → the `nabu char` card
        2. a known language code or lect id (chu, grc:koi, sla-pro)
                                               → the `nabu language` card
        3. a script tag or script name (glag / Glagolitic — the curated
           dossiers of config/script_dossiers.yml) → the script card

      Earlier rungs win; when a language code shadows a script tag the
      language card renders and a footer names the shadowed reading.
      Anything else misses honestly, naming all three namespaces.
    HELP
    def info(query = nil)
      term = Nabu::Normalize.nfc(query.to_s.strip)
      raise Thor::Error, "info: give a character, a language/lect code, or a script tag/name" if term.empty?
      return char(term) if term.grapheme_clusters.size == 1 && !term.match?(/\A[[:ascii:]]\z/)
      return char(term) if term.match?(/\A[A-Z][a-z]?\d+[a-z]?\z/) # Gardiner-style sign codes

      config = Nabu::Config.load
      lects = Nabu::Lects.load_default(config: config, overlay: {})
      if info_language?(config, term, lects)
        language(term)
        if (tag = info_script_tag(term))
          say "(#{term.inspect} is also script tag #{tag.inspect} — languages resolve first; " \
              "`nabu info #{Nabu::ScriptDossiers.lookup(tag).name}` shows the script card)"
        end
        return
      end
      return print_script_card(tag, lects) if (tag = info_script_tag(term))

      raise Thor::Error,
            "info: #{term.inspect} is not a known character, language/lect code, or script — " \
            "try nabu char CHAR, nabu language --list, or a script tag from config/script_dossiers.yml"
    end

    no_commands do
      # -- nabu signs (P53-2) ----------------------------------------------------

      def signs_dialect(name)
        return nil if name.nil?
        return name.to_sym if Nabu::AtfTokenizer::DIALECTS.map(&:to_s).include?(name)

        raise Thor::Error, "signs: unknown dialect #{name.inspect} — the known dialects are " \
                           "#{Nabu::AtfTokenizer::DIALECTS.join(', ')} (catf is the default)"
      end

      # Urn mode: language from the row (--lang overrides), the :etcsl
      # dialect auto-selected for the etcsl shelf (--dialect overrides).
      def signs_urn_result(urn, list:, catalog:, dialect:)
        result = Nabu::Query::Signs.new(sign_list: list, catalog: catalog)
                                   .run_urn(urn, language: options[:lang], dialect: dialect)
        raise Thor::Error, "signs: urn not found: #{urn}" if result.nil?

        result
      rescue Nabu::Query::Signs::Error => e
        raise Thor::Error, "signs: #{e.message}"
      end

      # The `nabu char` mold: readable columns, absent data ABSENT (a broken
      # token's row is its status; an unknown one says so plainly).
      def print_signs(result)
        say signs_header(result)
        result.lines.each do |line|
          say ""
          say "#{line.urn || "line #{line.number}"}  ·  #{line.text}"
          line.tokens.each { |token| print_signs_token(token) }
        end
        say ""
        say signs_footer(result)
      end

      def signs_header(result)
        parts = [result.mode == :urn ? result.urn : "raw ATF"]
        parts << result.language if result.language
        parts << "[#{result.source_slug}]" if result.source_slug
        parts << "dialect etcsl (c→š, j→ŋ)" if result.dialect == :etcsl
        parts.join("  ·  ")
      end

      def print_signs_token(token)
        columns = [token.input_value.ljust(14), (token.determinative ? "det" : "   "),
                   token.status.ljust(13), signs_token_detail(token)]
        say "  #{columns.join(' ')}".rstrip
        token.candidates.each do |candidate|
          say "  #{' ' * 19}#{candidate.status.ljust(13)} #{signs_candidate_detail(candidate)}"
        end
      end

      def signs_token_detail(token)
        case token.status
        when "ambiguous" then "#{token.candidates.size} candidates:"
        when "unknown" then "not in the sign list"
        when "broken" then nil
        else signs_candidate_detail(token)
        end
      end

      # sign name · codepoints · glyph · (%lang) · (form of X) — only what
      # the record holds; an unencoded sign says "unencoded". The form-of
      # tail is the kunga₃ fix: a sign and its same-named variant form of
      # ANOTHER sign must never render as indistinguishable twins.
      def signs_candidate_detail(token)
        parts = [token.sign_name]
        parts << (token.codepoints ? token.codepoints.join(" ") : "unencoded")
        parts << token.glyph if token.glyph
        parts << "(%#{token.language_qualifier})" if token.language_qualifier
        parts << "(form of #{token.form_of})" if token.form_of
        parts.compact.join("  ")
      end

      def signs_footer(result)
        tokens = result.lines.flat_map(&:tokens)
        tally = tokens.group_by(&:status).transform_values(&:size)
        parts = ["#{tokens.size} token(s)"]
        %w[deterministic qualified ambiguous no-codepoint broken unknown].each do |status|
          parts << "#{status} #{tally[status]}" if tally[status]
        end
        parts << "#{result.skipped_lines} structural line(s) skipped" if result.skipped_lines.positive?
        parts.join("  ·  ")
      end

      # -- the P65 `nabu char` dispatch lanes --------------------------------

      # The original P37-4 Han path; --json emits the P72-2 frozen contract
      # (the sign cards' P65 pattern extended to the Han card). A single
      # glyph OUTSIDE \p{Han} takes the reduced lane (P84-5) — the Han
      # card's shelf pipeline must never run for it (the define join's
      # Sanskrit stem expansion turned "a" into the TLS concept "AS").
      def han_char_card(config, input)
        return non_han_char_card(config, input) unless input.match?(/\p{Han}/)

        catalog = open_catalog(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
        unless catalog.table_exists?(:dictionary_entries)
          raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync unihan " \
                             "(or nabu rebuild after one)"
        end

        fulltext = open_fulltext(config)
        query = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext)
        card = query.run(input)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::Char.json_payload(input, card))
        else
          print_char_card(card, held_cjk: query.held_cjk_sources)
        end
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # The non-Han card. With the UCD identity floor synced (P85-B2) this is
      # the UNIVERSAL card (owner ruling: Shape C): name, category, numeric value and
      # decomposition for any writing system. Without it, the P84-5 reduced
      # card — glyph, codepoint, script probe — byte-identical (the feature-
      # module law). Pure Unicode either way, so no catalog is opened.
      def non_han_char_card(config, input, panels: nil)
        panels ||= char_ambiguity_panels(config, input)
        universal = Nabu::Ucd.load_default(config: config)&.then do |ucd|
          Nabu::Query::Char.universal(input, ucd)
        end
        return print_universal_char_card(input, universal, panels: panels) if universal

        reduced = Nabu::Query::Char.reduced(input)
        if options[:json]
          payload = Nabu::Query::Char.reduced_json_payload(input, reduced)
                                     .merge(char_panels_json(panels))
          return say(JSON.pretty_generate(payload))
        end

        say "#{reduced.glyph}  #{reduced.codepoint}#{"  ·  #{reduced.script}" if reduced.script}"
        noun = case reduced.script
               when "Hangul" then "a Hangul syllable"
               when nil then "not a Han character"
               else "a #{reduced.script} letter"
               end
        say ""
        say "#{reduced.glyph} is #{noun} — the char card's shelf lanes cover Han characters; " \
            "no CJK shelf claims it"
        print_ambiguity_panels(input, panels)
        say ""
        say "search: nabu search #{reduced.glyph}"
      end

      # -- the ambiguity layer (P86-5) ---------------------------------------
      # A single glyph can carry several identities at once: `a` is a Latin
      # letter AND a pinyin/romaji reading; `と` is a hiragana letter AND a
      # kun reading; `α` looks like `a` and `а`. The card leads with the
      # IDENTITY and composes every other lens as a labeled, capped panel;
      # `--as <lens>` narrows to one.

      def char_as_lens(config, input)
        case options[:as]
        when "identity" then identity_char_card(config, input)
        when "reading" then reading_lens_card(config, input)
        when "sign" then sign_lens_card(config, input)
        when "han" then han_char_card(config, input)
        else
          raise Thor::Error, "char --as: one of identity · reading · sign · han (got #{options[:as]})"
        end
      end

      # The pure identity lens: the universal card with no panels — works for
      # ANY code point, Han included (`char 木 --as identity`).
      def identity_char_card(config, input)
        raise Thor::Error, "char --as identity: the identity lens is one glyph (#{input})" unless input.each_char.one?

        non_han_char_card(config, input, panels: {})
      end

      def reading_lens_card(config, input)
        return if reading_char_card(config, input)

        raise Thor::Error, "#{input}: no held Han reading matches (kana kun/on · CAPS/lowercase " \
                           "romaji · pinyin) — is a dictionary shelf synced?"
      end

      def sign_lens_card(config, input)
        return cuneiform_char_card(config, input) if
          Nabu::CharDispatch.lane(input) == :cuneiform

        name_char_card(config, input)
      end

      # Gather the other-lens panels for a single glyph: the reverse-reading
      # matches (the same query the :name lane runs), the UTS #39 confusables
      # cluster, and (non-ASCII only — plain letters occur everywhere and
      # attest nothing) the corpus-attestation postings. Multi-char input
      # never panels.
      def char_ambiguity_panels(config, input)
        return {} unless input.each_char.one?

        panels = {}
        if (ucd = Nabu::Ucd.load_default(config: config))
          partners = ucd.confusables(input.each_char.first.ord)
                        .map { |other| [format("U+%04X", other), ucd.lookup(other)] }
          panels[:looks_like] = partners if partners.any?
        end
        catalog = open_catalog(config)
        if catalog&.table_exists?(:dictionary_entries)
          matches = Nabu::Query::Char.new(catalog: catalog).characters_for_reading(input)
          panels[:readings] = matches if matches.any?
        end
        if catalog && input.match?(/[^\x00-\x7F]/)
          fulltext = open_fulltext(config)
          corpus = Nabu::Query::Char.new(catalog: catalog, fulltext: fulltext)
                                    .universal_corpus(input)
          panels[:corpus] = corpus if corpus
        end
        panels
      ensure
        fulltext&.disconnect
        catalog&.disconnect
      end

      def print_ambiguity_panels(input, panels)
        if (matches = panels[:readings])
          shown = matches.first(Nabu::Query::Char::READING_PANEL_CAP)
          labels = shown.map do |match|
            kind = match.kind == "pinyin" ? "" : " (#{match.kind})"
            "#{match.glyph} #{match.reading}#{kind}"
          end
          say ""
          say "also a #{reading_panel_noun(matches)} — #{matches.size} Han character(s): " \
              "#{labels.join(' · ')}"
          say "  … nabu char #{input} --as reading for all #{matches.size}" if matches.size > shown.size
        end
        if (partners = panels[:looks_like])
          shown = partners.first(Nabu::Query::Char::LOOKS_LIKE_CAP)
          pieces = shown.map do |(hex, char)|
            [char&.glyph, hex, char&.display_name].compact.join(" ")
          end
          say ""
          say "looks like: #{pieces.join(' · ')}" \
              "#{" · … #{partners.size - shown.size} more" if partners.size > shown.size}"
        end
        print_corpus_panel(panels[:corpus])
      end

      # 88-B2: the last option-(a) members (owner-ruled 2026-08-28) render — encoded variants, named
      # sequences (capped, truncation announced), discouraged-sequence
      # warnings, Tangut/Nushu source fields. Absent = absent.
      def print_universal_extras(card)
        card.variants.each do |variant|
          say format("encoded variants: %<desc>s (U+%<sel>04X)",
                     desc: variant.description, sel: variant.selector)
        end
        shown = card.named_sequences.first(3) # const: a render cap, not a corpus census
        say "named sequences: #{shown.join(' · ')}" if shown.any?
        if card.named_sequences.size > shown.size
          say "named sequences: … #{card.named_sequences.size - shown.size} more"
        end
        card.discouraged.first(2).each do |row| # const: a render cap, not a corpus census
          preferred = row.preferred.split.map { |hex| Integer(hex, 16).chr(Encoding::UTF_8) }.join
          say "discouraged sequence (#{row.type}): heads #{row.sequence} — prefer #{preferred}"
        end
        return unless card.char_sources

        register, fields = card.char_sources
        pairs = fields.sort.map { |key, value| "#{key} #{value}" }
        say "#{register} sources: #{pairs.join(' · ')}"
      end

      # The B3 corpus line, era-honest: counts from a current-class index;
      # zero on a current-class index is a real zero; a miss on a legacy
      # (pre-widening) index names the rebuild instead of lying "0".
      def print_corpus_panel(corpus)
        return unless corpus

        say ""
        if corpus.counts.any?
          ranked = corpus.counts.sort_by { |_, docs| -docs }
          say "corpus attestation: #{ranked.map { |lang, docs| "#{lang || '?'} #{docs}" }.join(' · ')}"
        elsif corpus.class_stamp
          say "corpus attestation: no live passage carries it"
        else
          say "corpus attestation: the char index predates the P86 non-ASCII widening — " \
              "the next rebuild re-accumulates it"
        end
      end

      def reading_panel_noun(matches)
        kinds = matches.map(&:kind).uniq
        return "pinyin reading" if kinds == ["pinyin"]
        return "Japanese reading" if (kinds - %w[kun on]).empty?

        "Han reading"
      end

      def char_panels_json(panels)
        out = {}
        if (matches = panels[:readings])
          out["readings"] = matches.map do |match|
            { "glyph" => match.glyph, "reading" => match.reading, "kind" => match.kind }
          end
        end
        if (partners = panels[:looks_like])
          out["looks_like"] = partners.map do |(hex, char)|
            { "codepoint" => hex, "glyph" => char&.glyph, "name" => char&.display_name }
          end
        end
        if (corpus = panels[:corpus])
          out["corpus"] = { "counts" => corpus.counts, "class" => corpus.class_stamp }
        end
        out.empty? ? {} : { "panels" => out }
      end

      # The universal char card (P85-B2): the UCD identity layer, rendered.
      # Absent layers stay absent (binding-honesty) — numeric value, combining
      # class and decomposition print only when the character carries them.
      def print_universal_char_card(input, card, panels: {})
        payload = Nabu::Query::Char.universal_json_payload(input, card)
                                   .merge(char_panels_json(panels))
        return say(JSON.pretty_generate(payload)) if options[:json]

        say "#{card.glyph}  #{card.codepoint}#{"  ·  #{card.script}" if card.script}"
        say ""
        say "#{card.name} — #{card.category}"
        print_universal_context(card)
        say "numeric value: #{card.numeric}" if card.numeric
        say "combining class: #{card.combining_class}" if card.combining_class.positive?
        print_universal_decomposition(card.decomposition) if card.decomposition
        print_universal_charts(card)
        print_universal_extras(card)
        print_ambiguity_panels(input, panels)
        say ""
        say "search: nabu search #{card.glyph}"
      end

      # The member-context tier (P86-1): block, script identity, age, formal
      # aliases. Absent member → absent line (the P85 floor, byte-identical).
      def print_universal_context(card)
        say "block: #{card.block}" if card.block
        say "script: #{card.script} (#{card.script_code})" if card.script_code
        say "in Unicode since #{card.age}" if card.age
        card.numerals.each do |numeral|
          suffix = numeral.extended ? ", extended/sofit convention" : ""
          say "numeric (#{numeral.scheme}): #{numeral.value}#{suffix} — #{numeral.name}"
        end
        say "script context: #{card.script_context}" if card.script_context
        say "desk: #{card.script_desk}" if card.script_desk
        say "reading: #{card.reading}" if card.reading
        card.aliases.each do |a|
          say "#{a.type == 'correction' ? 'corrected name' : "#{a.type} alias"}: #{a.name}"
        end
      end

      # The NamesList charts annotation layer — informative, labeled as the
      # charts' voice, capped at render (truncation announced; caps live on
      # Nabu::Query::Char beside the card shape).
      def print_universal_charts(card)
        card.chart_aliases.each { |a| say "charts: = #{a}" }
        card.chart_notes.first(Nabu::Query::Char::CHART_NOTE_CAP).each { |n| say "charts: * #{n}" }
        if card.chart_notes.size > Nabu::Query::Char::CHART_NOTE_CAP
          say "charts: … #{card.chart_notes.size - Nabu::Query::Char::CHART_NOTE_CAP} more note(s)"
        end
        card.see_also.first(Nabu::Query::Char::CHART_SEE_ALSO_CAP).each do |ref|
          say "see also: #{"#{ref.glyph} " if ref.glyph}#{ref.codepoint} #{ref.text}".rstrip
        end
        return unless card.see_also.size > Nabu::Query::Char::CHART_SEE_ALSO_CAP

        say "see also: … #{card.see_also.size - Nabu::Query::Char::CHART_SEE_ALSO_CAP} more"
      end

      def print_universal_decomposition(decomp)
        pieces = decomp.parts.map do |part|
          "#{part.glyph} (#{part.codepoint}#{" #{part.name}" if part.name})"
        end
        label = decomp.kind ? "decomposes (#{decomp.kind})" : "decomposes"
        say "#{label}: #{pieces.join(' + ')}"
      end

      # The editorial/house-mark card (P85): what a single mark (⟦ ⌈ ⸀ ⿰ …)
      # MEANS in this library — its convention, the `--display` knob that
      # transforms it, and where it comes from. Pure config read (Nabu's own
      # convention, config/editorial_marks.yml), no catalog. The one card no
      # external Unicode tool can supply.
      def editorial_marks_char_card(config, input)
        mark = Nabu::EditorialMarks.lookup(input)
        # The dispatch set and the table are pinned to agree, so a routed mark
        # is always found; fall back to the universal/reduced card if it drifts.
        return non_han_char_card(config, input) unless mark

        if options[:json]
          return say(JSON.pretty_generate(
                       "glyph" => mark.glyph, "codepoint" => mark.codepoint, "class" => "editorial-mark",
                       "name" => mark.name, "meaning" => mark.meaning,
                       "display" => mark.display_rule, "seen_in" => mark.seen_in
                     ))
        end

        say "#{mark.glyph}  #{mark.codepoint}  ·  editorial mark"
        say ""
        say "#{mark.name} — #{mark.meaning}"
        say ""
        say "display: #{mark.display_rule}" if mark.display_rule
        say "seen in: #{mark.seen_in}" if mark.seen_in
      end

      def cuneiform_char_card(config, input)
        result = run_sign_card(config, input)
        emit_sign_card(result)
      end

      def hieroglyphic_char_card(config, input)
        emit_hiero_card(run_hiero_card(config, input))
      end

      # The multi-char NAME lane (P65-3): an OSL sign name/value first
      # (SZESZ, szesz, |ŠEŠ.AB| — C-ATF folds apply), then a Gardiner-style
      # Unikemet code (G5) — whichever held module resolves it wins; both
      # absent = name the modules. Non-name-shaped input (multi-char text
      # in another script) keeps the classic one-glyph grain error.
      def name_char_card(config, input)
        kana = input.match?(Nabu::Query::Char::KANA_INPUT)
        name_shaped = input.match?(Nabu::CharDispatch::NAME_SHAPE)
        reading_shaped = input.match?(Nabu::Query::Char::PINYIN_INPUT)
        unless kana || name_shaped || reading_shaped
          raise Thor::Error, "char: the card's grain is a single character — give one glyph " \
                             "(#{input}); search --char-component #{input.each_char.first} finds " \
                             "characters that contain one"
        end

        if name_shaped
          if Nabu::SignList.load_default(config: config)
            result = run_sign_card(config, input)
            return emit_sign_card(result) if result.card || result.candidates.any?
          end
          if Nabu::Hieroglyphs.load_default(config: config) && input.match?(Nabu::Query::HieroCard::CODE)
            hiero = run_hiero_card(config, input)
            return emit_hiero_card(hiero) if hiero.card
          end
        end
        return if (kana || reading_shaped) && reading_char_card(config, input)

        if options[:json]
          empty = Nabu::Query::SignCard::Result.new(input: input, card: nil, candidates: [])
          say JSON.pretty_generate(Nabu::Query::SignCard.json_payload(empty))
        else
          say "#{input}: resolved neither as an OSL sign name/value/list number, a Unikemet " \
              "Gardiner-style code, nor a held Han reading — said plainly (input shapes: " \
              "SAR · szesz · idx · MZL535 · 852 · G5 · wen · ひと)"
        end
      end

      # The reading→character lane (P65 gate feedback): pinyin against
      # unihan kMandarin, kana against kanjidic2 on/kun. Prints the match
      # list and answers true; false (silently) when no dictionary shelf or
      # no match, so the caller's honest miss line runs. --json emits the
      # frozen reading contract (P77-r15 — the last char lane to freeze).
      def reading_char_card(config, input)
        catalog = open_catalog(config)
        return false unless catalog&.table_exists?(:dictionary_entries)

        matches = Nabu::Query::Char.new(catalog: catalog).characters_for_reading(input)
        return false if matches.empty?

        if options[:json]
          say JSON.pretty_generate(Nabu::Query::Char.reading_json_payload(input, matches))
        else
          print_reading_matches(input, matches)
        end
        true
      ensure
        catalog&.disconnect
      end

      def print_reading_matches(input, matches)
        say "#{input}: #{matches.size} Han character(s) carry this reading — " \
            "nabu char <glyph> for a card:"
        labels = matches.map do |match|
          kind = match.kind == "pinyin" ? "" : " (#{match.kind})"
          "#{match.glyph} #{match.reading}#{kind}"
        end
        labels.each_slice(6) { |slice| say "  #{slice.join('   ')}" }
      end

      def run_sign_card(config, input)
        list = Nabu::SignList.load_default(config: config)
        unless list
          raise Thor::Error, "char: no cuneiform sign list held — run nabu sync osl (the sign " \
                             "card reads canonical/osl)"
        end

        fulltext = open_fulltext(config)
        catalog = open_catalog(config)
        begin
          Nabu::Query::SignCard.new(
            sign_list: list, readings: Nabu::CdliSignReadings.load_default(config: config),
            fulltext: fulltext, catalog: catalog,
            overlay: Nabu::EdubbaOverlay.load_default(config: config)
          ).run(input)
        ensure
          fulltext&.disconnect
          catalog&.disconnect
        end
      end

      def run_hiero_card(config, input)
        signs = Nabu::Hieroglyphs.load_default(config: config)
        raise Thor::Error, "char: no Egyptian sign spine held — run nabu sync unikemet" unless signs

        catalog = open_catalog(config)
        begin
          Nabu::Query::HieroCard.new(hieroglyphs: signs, catalog: catalog,
                                     overlay: Nabu::EdubbaOverlay.load_default(config: config)).run(input)
        ensure
          catalog&.disconnect
        end
      end

      def emit_sign_card(result)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::SignCard.json_payload(result))
        else
          print_sign_card(result)
        end
      end

      def emit_hiero_card(result)
        if options[:json]
          say JSON.pretty_generate(Nabu::Query::HieroCard.json_payload(result))
        else
          print_hiero_card(result)
        end
      end

      # The cuneiform sign card (P65-1): sections only where the held OSL /
      # CDLI readings / fulltext back them — the "absent, never —" rule.
      # Ambiguity lists ALL candidates, never one silently.
      def print_sign_card(result)
        return print_sign_card_miss(result) if result.card.nil?

        card = result.card
        header = [card.glyph, card.name].compact.join("  ")
        header += "  (deprecated)" if card.deprecated
        header += "  ·  #{(card.codepoints || ['unencoded']).join(' ')}"
        say header
        say card.uname if card.uname
        say "form of #{card.parent} — nabu char '#{card.parent}'" if card.parent
        say "aka: #{card.aka.join(' · ')}" if card.aka.any?
        print_sign_card_lists(card)
        print_sign_card_concordances(card)
        print_sign_card_values(card)
        print_sign_card_glosses(card)
        print_sign_card_senses(card)
        print_sign_card_forms(card)
        print_sign_card_corpus(card)
        print_sign_didactic(card.didactic)
        print_sign_card_search(card)
      end

      # The Edubba cuneiform overlay section (P77-8, the hiero mold): the
      # certainty grade is LOAD-BEARING — "unclear" prints IN FRONT of
      # the meaning, never as a footnote.
      def print_sign_didactic(overlay)
        return if overlay.nil?

        say ""
        head = ["keyword \"#{overlay['keyword']}\"", overlay["value"] && "value #{overlay['value']}"]
               .compact.join("  ·  ")
        say "didactic (#{[overlay['course'],
                          overlay['chapter'] && "ch. #{overlay['chapter']}"].compact.join(' ')}): #{head}"
        if overlay["meaning"]
          grade = overlay["certainty"] == "unclear" ? "UNCLEAR (origin debated — not fact): " : ""
          say "  meaning: #{grade}#{overlay['meaning']}"
        end
        say "  origin: #{overlay['iconicity']}" if overlay["iconicity"]
        unless Array(overlay["confusables"]).empty?
          follow = overlay["confusables"].map { |name| "#{name} (nabu char #{name})" }.join("  ·  ")
          say "  confusable with: #{follow}"
        end
        say "  #{overlay['description']}" if overlay["description"]
        say "  codex: #{overlay['link']}" if overlay["link"]
        say "  #{overlay['attribution']}"
      end

      # P75 C-4: the follow-up affordance — a sign with reading values can
      # be searched as an OR over them (the inverse of this card).
      def print_sign_card_search(card)
        return if card.values.empty?

        say "search: nabu search --sign '#{card.glyph || card.name}'  (any reading value)"
      end

      def print_sign_card_senses(card)
        return if card.senses.empty?

        say ""
        say "senses (Wiktionary, kaikki extract):"
        card.senses.each { |sense| say "  #{sense.gloss}#{" (#{sense.pos})" if sense.pos}" }
      end

      def print_sign_card_miss(result)
        if result.candidates.any?
          say "#{result.input}: ambiguous — #{result.candidates.size} candidate signs " \
              "(all listed, never one silently):"
          result.candidates.each do |candidate|
            tail = +""
            tail << "  (form of #{candidate.form_of})" if candidate.form_of
            tail << "  (via #{candidate.via})" if candidate.via
            say "  #{candidate.glyph || 'unencoded'}  #{candidate.name}#{tail}  " \
                "—  nabu char '#{candidate.name}'"
          end
        else
          say "#{result.input}: not in the held OSL — said plainly"
        end
      end

      def print_sign_card_lists(card)
        return if card.lists.empty?

        say ""
        say "sign lists: #{card.lists.map { |list, nums| "#{list} #{nums.join(',')}" }.join('  ·  ')}"
      end

      # The OSL 00etc concordance block (precompiled sign_concordances
      # rows): the headline lists (Labat/AKS/ATU1/PGSL) on the head line,
      # the other Wikidata lists, MZL↔KWU, eBL names, Wikidata ids, then
      # the value maps — each line only where a row backs it.
      def print_sign_card_concordances(card)
        block = card.concordances or return

        say ""
        headline = Nabu::Query::SignCard::HEADLINE_LISTS
        # Several numbers in one list join with "; " — upstream cells carry
        # their own commas ("DP 138,VI").
        head = block.lists.slice(*headline).map { |list, nums| "#{list} #{nums.join('; ')}" }
        say "concordances (OSL 00etc)#{": #{head.join('  ·  ')}" unless head.empty?}"
        rest = block.lists.except(*headline)
        say "  more lists (Wikidata): #{rest.map { |list, nums| "#{list} #{nums.join('; ')}" }.join('  ·  ')}" \
          unless rest.empty?
        unless block.mzl_kwu.empty?
          pairs = block.mzl_kwu.map { |mzl, kwu| "#{mzl || '(no MZL)'}↔#{kwu || '(KWU unnumbered)'}" }
          say "  MZL↔KWU: #{pairs.join('  ·  ')}"
        end
        say "  eBL name: #{block.ebl.join(' · ')}" unless block.ebl.empty?
        say "  Wikidata: #{block.wikidata.join(' · ')}" unless block.wikidata.empty?
        return if block.value_maps.empty?

        maps = block.value_maps.map do |scheme, pairs|
          label = Nabu::Query::SignCard::VALUE_MAP_LABELS.fetch(scheme, scheme)
          "#{label} #{pairs.map { |from, to| "#{from}→#{to}" }.join(', ')}"
        end
        say "  value maps: #{maps.join('  ·  ')}"
      end

      def print_sign_card_values(card)
        return if card.values.empty?

        say ""
        rendered = card.values.map do |value|
          tail = +""
          tail << " (%#{value.language})" if value.language
          tail << " (deprecated)" if value.deprecated
          "#{value.value}#{tail}"
        end
        say "values (OSL): #{rendered.join(' · ')}"
      end

      def print_sign_card_glosses(card)
        glossed = card.glosses.select(&:meaning)
        return if glossed.empty?

        say ""
        say "meanings (CDLI sign readings):"
        glossed.each { |gloss| say "  #{gloss.reading} → #{gloss.meaning}" }
      end

      def print_sign_card_forms(card)
        return if card.forms.empty?

        say ""
        say "variant forms:"
        card.forms.each do |form|
          say "  #{form.glyph || 'unencoded'}  #{form.name}  —  nabu char '#{form.name}'"
        end
      end

      def print_sign_card_corpus(card)
        return if card.corpus.empty?

        say ""
        top = card.corpus.sort_by { |_, count| -count }
                         .map { |value, count| "#{value} #{count}" }.join("  ·  ")
        say "in the corpus (fulltext document counts, by spelled value): #{top}"
      end

      # The Egyptian sign card (P65-2): the Unikemet identity + the aes
      # hiero_inventar panel — absent upstream fields are absent lines.
      def print_hiero_card(result)
        card = result.card
        return say("#{result.input}: not in the held Unikemet file — said plainly") if card.nil?

        header = [card.glyph, card.codepoint].compact.join("  ")
        header += "  ·  #{card.jsesh} (Gardiner/JSesh)" if card.jsesh
        core = { "C" => "core", "L" => "legacy" }[card.core]
        header += "  ·  #{core}" if core
        say header
        say card.desc if card.desc
        say ""
        say "catalog: #{card.cat} (Unicode kEH_Cat)  ·  UniK #{card.unik}"
        say "function: #{card.func}" if card.func
        say "value: #{card.fval}" if card.fval
        concordances = []
        concordances << "Hieroglyphica #{card.hg}" if card.hg
        concordances << "IFAO #{card.ifao}" if card.ifao
        say "concordances: #{concordances.join('  ·  ')}" if concordances.any?
        say "alternate sequence: #{card.alt_seq}" if card.alt_seq
        print_hiero_didactic(card.didactic)
        return if card.corpus.empty?

        say ""
        lines = []
        if card.corpus["passages"]
          lines << "#{card.corpus['signs']} sign(s) across #{card.corpus['passages']} " \
                   "passage(s) (#{Nabu::Query::HieroCard::HIERO_SOURCES.keys.join(' + ')} annotations)"
        end
        # The AED per-text postings (P103-2) — text grain, its own line,
        # with the word-token grain and the damaged (<unclear>) share.
        lines << format_aed_hiero_postings(card.corpus) if card.corpus["aed_texts"]
        say "in the wild: #{lines.join(' · ')}"
      end

      def format_aed_hiero_postings(corpus)
        damaged = corpus["aed_unclear"].to_i.positive? ? ", #{corpus['aed_unclear']} damaged" : ""
        "#{corpus['aed_signs']} sign(s) in #{corpus['aed_words']} word(s) across " \
          "#{corpus['aed_texts']} text(s)#{damaged} (aed hieroglyph transcriptions)"
      end

      # The Edubba overlay section (P72-6). The certainty grade is
      # LOAD-BEARING: "unclear" is Edubba's never-present-as-fact rule,
      # so it prints IN FRONT of the gloss, not as a footnote.
      def print_hiero_didactic(overlay)
        return if overlay.nil?

        say ""
        head = ["keyword \"#{overlay['keyword']}\"", overlay["label"]].compact.join("  ·  ")
        say "didactic (#{[overlay['course'],
                          overlay['chapter'] && "ch. #{overlay['chapter']}"].compact.join(' ')}): #{head}"
        if overlay["voice"]
          grade = overlay["certainty"] == "unclear" ? "UNCLEAR (origin debated — not fact): " : ""
          say "  #{overlay['voice_kind']}: #{grade}#{overlay['voice']}"
        end
        unless Array(overlay["confusables"]).empty?
          follow = overlay["confusables"].map { |code| "#{code} (nabu char #{code})" }.join("  ·  ")
          say "  confusable with: #{follow}"
        end
        say "  #{overlay['description']}" if overlay["description"]
        say "  codex: #{overlay['link']}" if overlay["link"]
        say "  #{overlay['attribution']}"
      end

      # The character card (P37-4): each section printed only when a held
      # shelf backs it for this glyph (the "absent, never —" rule). The
      # diachronic column is what nabu adds over Jisho; the synchronic
      # sections match it field-for-field where the shelves reach.
      def print_char_card(card, held_cjk: [])
        return say("no dictionary shelf in this catalog yet — run nabu sync unihan") if card.nil?

        say "#{card.glyph}  #{card.codepoint}#{char_header_tail(card)}"
        print_char_decomposition(card)
        print_char_components(card)
        print_char_variants(card)
        print_char_ja_readings(card)
        print_char_sinoxenic(card)
        print_char_pedagogy(card)
        print_char_desk_reference(card)
        print_char_diachronic(card)
        print_char_corpus(card)
        print_char_search_affordances(card)
        print_char_absence(card, held_cjk)
      end

      # glyph · N strokes · radical M NAME — only the parts Unihan backs.
      def char_header_tail(card)
        parts = []
        parts << "#{card.total_strokes} strokes" if card.total_strokes
        parts << "radical #{card.radical.number} #{card.radical.glyph} #{card.radical.name}" if card.radical
        parts.empty? ? "" : "  ·  #{parts.join('  ·  ')}"
      end

      def print_char_decomposition(card)
        return if card.ids.empty?

        say ""
        say "decomposition (BabelStone IDS):"
        card.ids.each do |ids|
          tag = ids.sources ? " (#{ids.sources})" : ""
          say "  #{ids.sequence}#{tag}"
          ids.components.each do |component|
            say "    #{component} — nabu char #{component} · nabu search --char-component #{component}"
          end
        end
      end

      def print_char_components(card)
        return if card.components.empty?

        say ""
        say "components (KRADFILE index): #{card.components.join(' ')}"
      end

      def print_char_variants(card)
        return if card.variants.empty?

        say ""
        say "variants:"
        card.variants.each do |variant|
          say "  #{variant.relation}: #{variant.glyph} (#{variant.codepoint}) — nabu char #{variant.glyph}"
        end
      end

      def print_char_ja_readings(card)
        readings = card.readings_ja or return
        say ""
        say "readings (ja, KANJIDIC2):"
        say "  on: #{readings[:on].join('、')}" if readings[:on].any?
        say "  kun: #{readings[:kun].join('、')}" if readings[:kun].any?
        say "  nanori: #{readings[:nanori].join('、')}" if readings[:nanori].any?
        say "  meanings: #{readings[:meanings].join('; ')}" if readings[:meanings].any?
      end

      def print_char_sinoxenic(card)
        return if card.readings_sinoxenic.empty?

        say ""
        say "readings (sinoxenic, Unihan):"
        card.readings_sinoxenic.each { |label, value| say "  #{label}: #{value}" }
      end

      def print_char_pedagogy(card)
        pedagogy = card.pedagogy or return
        say ""
        labels = { "grade" => "Jōyō grade", "jlpt" => "JLPT", "freq" => "newspaper freq" }
        say "pedagogy: #{pedagogy.map { |k, v| "#{labels[k]} #{v}" }.join('  ·  ')}"
      end

      def print_char_desk_reference(card)
        return if card.desk_reference.empty?

        say ""
        say "desk reference: #{card.desk_reference.map { |k, v| "#{k} #{v}" }.join('  ·  ')}"
      end

      # The diachronic column — the half no dictionary site carries.
      def print_char_diachronic(card)
        print_char_shelf_block("Old Chinese (Baxter-Sagart)", card.old_chinese)
        print_char_phonetic_series(card.phonetic_series)
        print_char_shelf_block("Shuowen Jiezi 說文解字 (Xu Shen, Han graphology)", card.shuowen)
        print_char_shelf_block("Middle Chinese (Qieyun / Baxter-Sagart)", card.middle_chinese)
        print_char_shelf_block("early-Japan lexicography (HDIC)", card.early_japan)
        print_char_tls(card.tls)
      end

      # The 諧聲 neighbours (P146): per GSR series, the other held members
      # with their OC readings — `nabu char <member>` walks into each.
      def print_char_phonetic_series(series)
        return if series.nil? || series.empty?

        say ""
        say "phonetic series 諧聲 (Karlgren GSR, via Baxter-Sagart):"
        series.each do |group|
          count = group.neighbours.size
          members = group.neighbours.map { |m| "#{m.glyph} #{m.old_chinese.join(' / ')}".strip }
          say "  GSR #{group.series} · #{count} neighbour#{'s' unless count == 1}: #{members.join(' · ')}"
        end
      end

      def print_char_shelf_block(label, entries)
        return if entries.empty?

        say ""
        say "#{label}:"
        entries.each do |entry|
          say "  [#{entry.slug}] #{entry.gloss || entry.lines.first}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_tls(entries)
        return if entries.empty?

        say ""
        say "TLS (Thesaurus Linguae Sericae):"
        entries.each do |entry|
          attest = entry.attestations.positive? ? " — #{entry.attestations} attestation(s)" : ""
          say "  [#{entry.slug}] #{entry.gloss}#{attest}"
          entry.lines.each { |line| say "    #{line}" }
        end
      end

      def print_char_corpus(card)
        if card.corpus.nil?
          say ""
          say "corpus attestation: not indexed yet — nabu rebuild (or the next sync) builds " \
              "the char-postings index"
          return
        end
        return if card.corpus.empty?

        say ""
        totals = card.corpus.sort_by { |_, count| -count }
                            .map { |lang, count| "#{lang} #{count}" }.join("  ·  ")
        say "corpus attestation: #{totals}"
        # P72-5: the per-source provenance split, when more than one source
        # attests (a single-source panel would just repeat the line above).
        split = card.corpus_by_source || []
        return unless split.map(&:first).uniq.size > 1

        say "  by source: #{split.map { |slug, lang, docs| "#{slug} #{lang} #{docs}" }.join('  ·  ')}"
      end

      def print_char_search_affordances(card)
        say ""
        say "search: nabu search #{card.glyph}  ·  nabu search --char-component #{card.glyph}" \
            "#{"  ·  nabu search --radical #{card.radical.number}" if card.radical}"
      end

      # When NOTHING backed the card, say so honestly (the glyph is unknown to
      # every held shelf) rather than printing a bare header. P84-5: the hint
      # tells shelves-absent apart from char-not-covered — held CJK shelves
      # that stay silent on this glyph are named as held, and the sync points
      # only at the shelves actually missing from the dictionaries table.
      def print_char_absence(card, held_cjk)
        return unless card.held_shelves.empty? && card.ids.empty? && card.components.empty? &&
                      card.radical.nil? && (card.corpus || {}).empty?

        missing = Nabu::Query::Char::CJK_SHELF_SOURCES.keys - held_cjk
        say ""
        if held_cjk.empty?
          say "no held shelf carries #{card.glyph} yet — sync the CJK shelves (#{missing.join(', ')})"
        elsif missing.empty?
          say "the held CJK shelves (#{held_cjk.join(', ')}) don't carry #{card.glyph}"
        else
          say "the held CJK shelves (#{held_cjk.join(', ')}) don't carry #{card.glyph} — " \
              "sync the missing CJK shelves (#{missing.join(', ')})"
        end
      end

      # P90-5 (lane 3): is +term+ a language the desks know — a lect id
      # the registry parses, or a code the names census can name? (The
      # membership test the front door needs; the language command itself
      # renders unknown codes as honest misses, which would swallow every
      # string.)
      def info_language?(config, term, lects)
        return true if lects&.lect(term)

        catalog = open_catalog(config)
        return false unless catalog

        !Nabu::Languages.new(catalog: catalog).name(term).nil?
      ensure
        catalog&.disconnect
      end

      # A script-dossier tag for +term+: the tag itself, or a case-blind
      # script NAME alias (glag / Glagolitic), else nil.
      def info_script_tag(term)
        tag = term.downcase
        return tag if Nabu::ScriptDossiers.lookup(tag)

        Nabu::ScriptDossiers.table.find { |_t, row| row["name"].to_s.casecmp?(term) }&.first
      end

      # P90-5 (lane 2): the script dossier card — the curated context
      # config/script_dossiers.yml holds (published as nabu-data
      # mul/script-dossiers) finally readable from the CLI.
      def print_script_card(tag, lects)
        dossier = Nabu::ScriptDossiers.lookup(tag)
        say "script #{dossier.name} (#{dossier.tag})"
        say_wrapped(dossier.context, indent: 2)
        if dossier.desk
          say "  desk:"
          say_wrapped(dossier.desk, indent: 4)
        end
        row = lects&.script_rows&.dig(dossier.tag)
        if row
          iso = row["iso15924"] ? ", ISO 15924 #{row['iso15924']}" : ""
          say "  registry: minted in the nabu-lects scripts table#{iso}"
        else
          say "  registry: nabu-lects not synced — the scripts-table row is unavailable"
        end
      end
    end
  end
end
