# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "dharma-epidoc" (P92-1): one DHARMA edition file — the
    # EFEO/ERC project's EpiDoc-flavored TEI (files validate against
    # DHARMA_Schema.rng and declare the stock tei-epidoc model). Composed by
    # the five DHARMA adapters (khmer, campa, nusantara, pyu, and the
    # philology repo's inscriptional siblings). DOM-based like
    # RiigEpidocParser and for the same reason: the corpus is thousands of
    # files ≤ ~400 KB (the >5 MB streaming rule never engages) and the
    # keep/drop policy needs name-based subtree decisions.
    #
    # == Content shape (fixture-censused across four repos, 2026-09-01)
    #
    #   div[@type="edition"] @xml:lang @rendition="… maturity:NNNNN"
    #     prose:  <p> … <lb n="1"/>text <lb n="2" break="no"/>text …
    #     verse:  <lg n="1" met="…"> <l n="a"><lb n="1"/>text</l> …
    #
    # Prose lines run ACROSS <p> boundaries (a new <p> without a leading
    # <lb> continues the current physical line — INSIDENK00007) and across
    # face milestones (one line wraps around the stone's faces a→B→c).
    # In verse, <lb> is a physical milestone inside the metrical unit.
    #
    # == Passage grain
    #
    # - Verse (<lg>): one passage per <l>; citation "<lg n>.<l n>",
    #   PREFIXED by the @n of any ancestor divs inside the edition — the
    #   kakawin editions nest chapter > canto (met=…) > lg, so
    #   Deśavarṇana 1.1.1.a cites chapter.canto.stanza.pāda while K.2's
    #   flat verse keeps "1.d". A canto/lg @met rides each verse
    #   passage's annotations["met"] (the meter axis's feed).
    # - Prose WITH <lb> (inscriptions; the diplomatic transcriptions'
    #   folio-lines "1r1"): one passage per PHYSICAL LINE; lb break="no"
    #   still ends the line — the straddling word stays split as upstream
    #   prints it (the titus/menota line-grain precedent). Text before
    #   the first <lb> (rare) mints suffix "pre".
    # - Prose WITHOUT any <lb> outside verse (the prose critical
    #   editions — BhimaSvarga's <p> stream of app/lem/rdg): one passage
    #   per PARAGRAPH, keys "p1", "p2", … in document order. The mode is
    #   decided per document by a pre-scan, never mixed.
    # - A unit whose extraction is only gap markers / punctuation mints no
    #   passage (K.2's all-lost pādas); a document with ZERO passages
    #   raises ParseError — metadata-only stubs quarantine loudly.
    # - Duplicate citation keys raise ParseError (never silent overwrite).
    #
    # == Text policy (the RIIG/DDbDP doctrine, DHARMA dialect)
    #
    # - READ THROUGH (text counts): supplied, unclear, add, seg, num, g
    #   (symbol glyphs carry their display text), hi, foreign, w, name,
    #   persName, placeName, choice→(corr|reg|expan preferred over
    #   sic|orig|abbr), app→lem (rdg is apparatus).
    # - MARKERS: gap → "[…]"; del → "⟦…⟧"; surplus → "{…}"; space → " ".
    # - DROP: note (and its XML comments), bibl, figure, desc, certainty,
    #   ref, rdg, sic, orig, abbr.
    # - milestone/pb contribute nothing (break="no" wraps mid-word around
    #   faces); whitespace collapses; NFC at this boundary.
    #
    # == Languages
    #
    # Per-passage language is the nearest ancestor-or-self @xml:lang inside
    # the edition (bilingual editions: INSIDENK00007 opens in Sanskrit
    # verse inside an omy edition); the document language is the edition
    # div's own code, both verbatim (okz-Latn — the gretil san-Latn shape).
    # Every code must be in the adapter's allowed set: the deposit carries
    # at least one template-placeholder bug ("languageb-Latn",
    # INSIDENK00050) and the unknown-code net quarantines it loudly.
    module DharmaEpidocParser
      XML_NS = "http://www.w3.org/XML/1998/namespace"

      Result = Data.define(:title, :language, :license, :maturity, :passages)
      Unit = Data.define(:key, :text, :language, :met)

      DROP = %w[note bibl figure desc certainty ref rdg sic orig abbr head].freeze
      GAP_MARKER = "[…]"

      module_function

      # Parse one DHARMA edition file. +allowed_languages+ is the adapter's
      # measured code set; any other code raises Nabu::ParseError.
      def parse(path, allowed_languages:)
        doc = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:noblanks)
        doc.remove_namespaces!

        edition = doc.at_xpath('//body//div[@type="edition"]') or
          raise Nabu::ParseError, "#{File.basename(path)}: no edition div"

        language = check_language!(lang_of(edition), allowed_languages, path)
        units = []
        prose = ProseLines.new(paragraph_mode: !edition.at_xpath(".//lb[not(ancestor::lg)]"))
        walk_edition(edition, units, prose, Walkctx.new(language, [], nil), allowed_languages, path)
        prose.flush!(units)

        units = units.reject { |u| marker_only?(u.text) }
        raise Nabu::ParseError, "#{File.basename(path)}: edition has no citable text" if units.empty?

        keys = units.map(&:key)
        if (dup = keys.tally.find { |_, n| n > 1 })
          raise Nabu::ParseError, "#{File.basename(path)}: duplicate citation #{dup.first.inspect}"
        end

        Result.new(
          title: text_of(doc.at_xpath("//teiHeader//titleStmt/title")),
          language: language,
          license: doc.at_xpath("//availability/licence/@target")&.value,
          maturity: edition["rendition"]&.[](/maturity:(\d+)/, 1),
          passages: units
        )
      end

      # The walk's inherited state: language, the @n path of ancestor divs
      # inside the edition, and the nearest @met (canto meter).
      Walkctx = Data.define(:language, :div_path, :met)

      # Accumulates the current prose unit. Line mode: a unit runs from one
      # <lb> to the next, across <p> and face boundaries. Paragraph mode
      # (no <lb> in the document's prose): a unit is one <p>/<ab>, keyed
      # "p<ordinal>".
      class ProseLines
        def initialize(paragraph_mode: false)
          @paragraph_mode = paragraph_mode
          @paragraphs = 0
          @key = nil
          @buffer = +""
          @language = nil
        end

        def open_line!(units, number, language)
          flush!(units)
          @key = number
          @language = language
        end

        def paragraph_boundary!(units, language)
          if @paragraph_mode
            flush!(units)
            @paragraphs += 1
            @key = "p#{@paragraphs}"
            @language = language
          else
            append(" ", language)
          end
        end

        def append(text, language)
          @language ||= language
          @buffer << text
        end

        def flush!(units)
          text = DharmaEpidocParser.clean(@buffer)
          units << Unit.new(key: @key || "pre", text: text, language: @language, met: nil) unless text.empty?
          @buffer = +""
          @key = nil
          @language = nil
        end
      end

      def walk_edition(node, units, prose, ctx, allowed, path)
        node.children.each do |child|
          case child
          when Nokogiri::XML::Text
            prose.append(child.text, ctx.language)
          when Nokogiri::XML::Element
            lang = lang_of(child) ? check_language!(lang_of(child), allowed, path) : ctx.language
            child_ctx = ctx.with(language: lang, met: child["met"] || ctx.met)
            case child.name
            when "lg" then verse_units(child, units, child_ctx, allowed, path)
            when "lb" then prose.open_line!(units, child["n"] || "?", lang)
            when "p", "ab"
              prose.paragraph_boundary!(units, lang)
              walk_edition(child, units, prose, child_ctx, allowed, path)
            when "div"
              prose.append(" ", lang)
              div_ctx = child["n"] ? child_ctx.with(div_path: ctx.div_path + [child["n"]]) : child_ctx
              walk_edition(child, units, prose, div_ctx, allowed, path)
            when *DROP then nil
            else prose.append(extract(child), lang)
            end
          end
        end
      end

      def verse_units(lg_node, units, ctx, allowed, path)
        lg_n = lg_node["n"]
        met = lg_node["met"] || ctx.met
        lg_node.xpath("./l").each_with_index do |l, index|
          lang = lang_of(l) ? check_language!(lang_of(l), allowed, path) : ctx.language
          key = (ctx.div_path + [lg_n, l["n"] || (index + 1).to_s].compact).join(".")
          units << Unit.new(key: key, text: clean(extract(l)), language: lang, met: met)
        end
      end

      # The keep/drop extraction for one subtree (verse lines, inline
      # elements inside prose). <lb> here is a physical milestone → space.
      def extract(node)
        return node.text if node.text?
        return "" unless node.element?

        case node.name
        when *DROP then ""
        when "gap" then GAP_MARKER
        when "space" then " "
        when "lb", "pb", "milestone"
          # break="no" wraps mid-word (a line around the stone's faces:
          # ti|thi) — contribute nothing; otherwise the break separates words.
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

      def clean(text)
        Normalize.nfc(text.gsub(/\s+/, " ").strip)
      end

      def marker_only?(text)
        text.gsub(GAP_MARKER, "").gsub(/[\s.·|⟦⟧{}\-—–,;:!?()]/, "").empty?
      end

      def check_language!(code, allowed, path)
        return code if allowed.include?(code)

        raise Nabu::ParseError,
              "#{File.basename(path)}: unknown language code #{code.inspect} — classify it before ingesting"
      end

      def lang_of(node)
        node.attribute_with_ns("lang", XML_NS)&.value || node["lang"]
      end

      def text_of(node)
        node ? clean(node.children.map { |c| extract(c) }.join) : nil
      end
    end
  end
end
