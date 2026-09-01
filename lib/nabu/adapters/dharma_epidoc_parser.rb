# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "dharma-epidoc" (P92-1, hardened at the P92 first-sync
    # census): one DHARMA edition file — the EFEO/ERC project's
    # EpiDoc-flavored TEI. Composed by the five DHARMA adapters. DOM-based
    # like RiigEpidocParser: thousands of files ≤ ~400 KB, and the
    # keep/drop policy needs name-based subtree decisions.
    #
    # == Passage grain
    #
    # - Verse (<lg>): one passage per <l>; citation "<lg n>.<l n>",
    #   prefixed by ancestor div @n's inside the edition (the kakawin
    #   chapter.canto.stanza.pāda) and by the current SECTION (below).
    #   An unnumbered lg takes "u<ordinal>" (Devaśāsana's invocation
    #   stanzas). A canto/lg @met rides annotations["met"].
    # - Prose WITH <lb>: one passage per physical line. lb break="no"
    #   still ends a line (the titus precedent) — EXCEPT a re-anchor: an
    #   lb repeating the CURRENT line's number continues it (MpuMano's
    #   "1v5" twice, the second break="no" — the editor resuming the same
    #   line after an interruption; pb re-anchors likewise).
    # - Prose WITHOUT any <lb> outside verse: one passage per paragraph —
    #   the <p>'s own @n when it carries one (Devaśāsana's p n="1"), else
    #   "p<ordinal>".
    # - SECTIONS (the first-sync census, 2026-09-01): multi-face
    #   inscriptions restart numbering per face, marked either by
    #   <milestone type="pagelike"> (K. 46's faces, K. 21's doorjambs) or
    #   by <pb> (the diplomatic CalonArang restarting lb per leaf). Both
    #   set the current section; a key not already beginning with the
    #   section token is prefixed "<section>.<key>". Inline face
    #   milestones WITHOUT type="pagelike" wrap text mid-line
    #   (INSIDENK00007) and set no section.
    # - Marker-only units mint nothing; zero passages raises ParseError.
    # - UPSTREAM NUMBERING DUPLICATES (census 2026-09-01: Deśavarṇana
    #   carries chapter n="3" twice; Sutasoma canto 137 numbers four
    #   stanzas lg n="1"; K. 267 repeats a stanza number): the second and
    #   later occurrences of a key mint with a deterministic "+2"/"+3"
    #   occurrence suffix (document order — the DDbDP implicit-block
    #   idiom) — never a silent overwrite, never a lost flagship edition;
    #   the dups ride .docs/upstream-reports.md.
    # - A <pb> carrying @edRef is a WITNESS's pagination (the critical
    #   editions cite their manuscripts' page turns) and never sets a
    #   section — only the edition's own pb / pagelike milestones do,
    #   including pagelike milestones INSIDE verse lines (K. 46's faces
    #   open inside <l>).
    #
    # == Text policy (the RIIG/DDbDP doctrine, DHARMA dialect)
    #
    # - READ THROUGH: supplied, unclear, add, seg, num, g, hi, foreign,
    #   w, name, persName, placeName, choice→(corr|reg|expan over
    #   sic|orig|abbr), app→lem (rdg is apparatus).
    # - MARKERS: gap → "[…]"; del → "⟦…⟧"; surplus → "{…}"; space → " ".
    # - DROP: note, bibl, figure, desc, certainty, ref, rdg, sic, orig,
    #   abbr, head, label (editorial face/doorjamb captions — the
    #   first-sync census's largest false-quarantine class), fw
    #   (foliation furniture).
    # - lb/pb/milestone with break="no" contribute nothing inline;
    #   whitespace collapses; NFC at the boundary.
    #
    # == Languages (validated AT MINT, not during the walk)
    #
    # Only text that actually mints validates its language — an eng
    # <label> inside the edition is dropped, never quarantined (the
    # first sync's 200+ false quarantines). Per-passage language is the
    # nearest ancestor @xml:lang; the document language is the edition
    # div's own code, falling back to the first lang-carrying inner div
    # (textpart editions), then the first minted unit's. Adapters pass a
    # measured allowed set plus an ALIASES map for censused upstream tag
    # dirt ("kaw-Latin" typo, "kaw-ban"); anything else — including the
    # real "languageb-Latn" template bug and "und" stubs — quarantines
    # loudly.
    module DharmaEpidocParser
      XML_NS = "http://www.w3.org/XML/1998/namespace"

      Result = Data.define(:title, :language, :license, :maturity, :passages)
      Unit = Data.define(:key, :text, :language, :met)

      DROP = %w[note bibl figure desc certainty ref rdg sic orig abbr head label fw].freeze
      GAP_MARKER = "[…]"

      module_function

      # Parse one DHARMA edition file. +allowed_languages+ is the adapter's
      # measured code set; +aliases+ maps censused upstream tag dirt onto
      # held codes. Any other code raises Nabu::ParseError at mint.
      def parse(path, allowed_languages:, aliases: {})
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:noblanks)
        doc.remove_namespaces!

        edition = doc.at_xpath('//body//div[@type="edition"]') or
          raise Nabu::ParseError, "#{File.basename(path)}: no edition div"

        checker = language_checker(allowed_languages, aliases, path)
        state = WalkState.new(checker: checker,
                              paragraph_mode: !edition.at_xpath(".//lb[not(ancestor::lg)]"))
        edition_lang = lang_of(edition) ||
                       edition.xpath(".//div").filter_map { |d| lang_of(d) }.first
        walk_edition(edition, state, Walkctx.new(edition_lang, [], nil))
        state.flush!

        units = state.units
        raise Nabu::ParseError, "#{File.basename(path)}: edition has no citable text" if units.empty?

        Result.new(
          title: presence(text_of(doc.at_xpath("//teiHeader//titleStmt/title"))),
          language: checker.call(edition_lang || units.first.language),
          license: doc.at_xpath("//availability/licence/@target")&.value,
          maturity: edition["rendition"]&.[](/maturity:(\d+)/, 1),
          passages: units
        )
      end

      # The walk's inherited (immutable) state: language, the @n path of
      # ancestor divs inside the edition, and the nearest @met (the
      # kakawin canto's meter, inherited down to every pāda).
      Walkctx = Data.define(:language, :div_path, :met)

      # The walk's mutable state: minted units, the open prose line, the
      # current section (pagelike milestone / pb), paragraph bookkeeping.
      # Languages validate here — at mint — through the checker.
      class WalkState
        attr_reader :units

        def initialize(checker:, paragraph_mode:)
          @checker = checker
          @paragraph_mode = paragraph_mode
          @units = []
          @used = Hash.new(0)
          @section = nil
          @key = nil
          @buffer = +""
          @language = nil
          @paragraphs = 0
        end

        def mint_verse(key, text, language, met)
          @units << Unit.new(key: disambiguated(sectioned(key)), text: text,
                             language: @checker.call(language), met: met)
        end

        # An lb opens a new line — unless it re-anchors the CURRENT line
        # (same number, the MpuMano resume shape). The ancestor div @n
        # path prefixes the number (campa textparts A/B each restart lb
        # at 1) unless the number already carries the component
        # (INSCIK00015 writes lb n="A1" under textpart A).
        def open_line!(number, language, div_path = [])
          key = div_path.reverse.reduce(number) do |acc, component|
            acc.start_with?(component) ? acc : "#{component}.#{acc}"
          end
          return if @key == key

          flush!
          @key = key
          @language = language
        end

        # A pagelike milestone or pb sets the section; repeating the
        # current section is a re-anchor and changes nothing.
        def open_section!(token)
          return if token.nil? || token == @section

          flush!
          @section = token
        end

        def paragraph_boundary!(language, para_n)
          if @paragraph_mode
            flush!
            @paragraphs += 1
            @key = para_n || "p#{@paragraphs}"
            @language = language
          else
            append(" ", language)
          end
        end

        def append(text, language)
          @language ||= language
          @buffer << text
        end

        def flush!
          text = DharmaEpidocParser.clean(@buffer)
          unless text.empty? || DharmaEpidocParser.marker_only?(text)
            @units << Unit.new(key: disambiguated(sectioned(@key || "pre")), text: text,
                               language: @checker.call(@language), met: nil)
          end
          @buffer = +""
          @key = nil
          @language = nil
        end

        private

        # The upstream-duplicate policy: a repeated key takes "+2", "+3"…
        # in document order — deterministic, stable across parses.
        def disambiguated(key)
          @used[key] += 1
          @used[key] == 1 ? key : "#{key}+#{@used[key]}"
        end

        # Prefix the section unless the key already carries its token
        # (diplomatic lb n="1v5" under pb n="1v" needs no prefix).
        def sectioned(key)
          return key if @section.nil? || key.start_with?(@section)

          "#{@section}.#{key}"
        end
      end

      def walk_edition(node, state, ctx)
        node.children.each do |child|
          case child
          when Nokogiri::XML::Text
            state.append(child.text, ctx.language)
          when Nokogiri::XML::Element
            lang = lang_of(child) || ctx.language
            child_ctx = ctx.with(language: lang, met: child["met"] || ctx.met)
            case child.name
            when *DROP then nil
            when "lg" then verse_units(child, state, child_ctx)
            when "lb" then state.open_line!(child["n"] || "?", lang, ctx.div_path)
            when "pb"
              state.open_section!(child["n"]) unless child["edRef"]
            when "milestone"
              state.open_section!(child["n"]) if child["type"] == "pagelike"
            when "p", "ab"
              state.paragraph_boundary!(lang, child["n"])
              walk_edition(child, state, child_ctx)
            when "div"
              state.append(" ", lang)
              div_ctx = child["n"] ? child_ctx.with(div_path: ctx.div_path + [child["n"]]) : child_ctx
              walk_edition(child, state, div_ctx)
            else state.append(extract(child), lang)
            end
          end
        end
      end

      def verse_units(lg_node, state, ctx)
        lg_n = lg_node["n"] || "u#{lg_ordinal(lg_node)}"
        met = lg_node["met"] || ctx.met
        lg_node.xpath("./l").each_with_index do |l, index|
          lang = lang_of(l) || ctx.language
          if (pagelike = l.at_xpath('.//milestone[@type="pagelike"]'))
            state.open_section!(pagelike["n"])
          end
          key = (ctx.div_path + [lg_n, l["n"] || (index + 1).to_s]).join(".")
          text = clean(extract(l))
          next if text.empty? || marker_only?(text)

          state.mint_verse(key, text, lang, met)
        end
      end

      # 1-based ordinal of an unnumbered lg among its parent's lg children.
      def lg_ordinal(lg_node)
        lg_node.parent.xpath("./lg").index(lg_node) + 1
      end

      # The keep/drop extraction for one subtree.
      def extract(node)
        return node.text if node.text?
        return "" unless node.element?

        case node.name
        when *DROP then ""
        when "gap" then GAP_MARKER
        when "space" then " "
        when "lb", "pb", "milestone"
          node["break"] == "no" ? "" : " "
        when "del" then "⟦#{node.children.map { |c| extract(c) }.join}⟧"
        when "surplus" then "{#{node.children.map { |c| extract(c) }.join}}"
        when "choice"
          preferred = node.at_xpath("./corr | ./reg | ./expan") || node.children.first
          preferred ? extract(preferred) : ""
        when "app"
          lem = node.at_xpath("./lem")
          lem ? extract(lem) : ""
        else
          node.children.map { |c| extract(c) }.join
        end
      end

      def language_checker(allowed, aliases, path)
        lambda do |code|
          resolved = aliases.fetch(code, code)
          next resolved if allowed.include?(resolved)

          raise Nabu::ParseError,
                "#{File.basename(path)}: unknown language code #{code.inspect} — classify it before ingesting"
        end
      end

      def clean(text)
        Normalize.nfc(text.gsub(/\s+/, " ").strip)
      end

      def marker_only?(text)
        text.gsub(GAP_MARKER, "").gsub(%r{[\s.·|⟦⟧{}\-—–,;:!?()*/]}, "").empty?
      end

      def presence(value)
        value.nil? || value.strip.empty? ? nil : value
      end

      def lang_of(node)
        return nil if node.nil?

        node.attribute_with_ns("lang", XML_NS)&.value || node["lang"]
      end

      def text_of(node)
        node ? clean(node.children.map { |c| extract(c) }.join) : nil
      end
    end
  end
end
