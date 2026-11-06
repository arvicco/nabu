# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"
require_relative "source_read"
require_relative "leme_entities"

module Nabu
  module Adapters
    # The leme-xml parser family: LEME's OWN XML (Lexicons of Early Modern
    # English, ed. Ian Lancashire, University of Toronto) — NOT TEI. One file
    # is one lexical work: <root><leme no="…"> enclosing <section type="…">
    # blocks (Title-page, Glossary, Dictionary, Closing …), whose word-entries
    # sit in <wordgroup1|2|3 object="A">…</wordgroup> groupings (an
    # alphabetical letter or a topical heading). The word-entry is
    #
    #   <wordentry type="h"><form lang="en">Corody,</form>
    #     <xpln lang="en">A sum of money …</xpln></wordentry>
    #
    # with optional <subform>/<subxpln> pairs inside the <xpln> (Rider's and
    # Martinez's derivative sub-entries), and LEME's inline tagset inside
    # both: <term lang> (a change of language), <class type="pos|gender:…|
    # etymlang|register|dialect…">, <etym lang>, <expan> (an expanded
    # abbreviation), <emend err> (the editor's correction; the text is the
    # corrected reading, @err the printed one), <editoraddition>, <note
    # type="margin|m…"> (the print's marginalia), <cit>, <infl>, <xref>,
    # <damage>, <f/> font switches, <pb sig|no|fol/> page breaks, and
    # <lemenote> (the LEME editors' own note — mostly OED antedatings and
    # "not found in OED" findings). Element census 2026-11-05 over all 314
    # TSpace files: 943,525 <wordentry>, each with exactly one <form>.
    #
    # == Entities, safely
    #
    # Upstream declares its character entities in an internal DTD subset
    # (260 of them, LEME_ENTITIES), but four files carry that subset with
    # every value lost and one carries no DOCTYPE at all while using
    # &aelig; — so the parser never lets libxml expand entities: it drops
    # the DOCTYPE, resolves each &name; itself (the file's well-formed
    # declarations first, then the snapshot), and neutralizes a name known
    # to neither as literal text ("&syh;", an upstream typo for &shy;),
    # counted in the census. No DTD is ever loaded and nothing touches the
    # network (NONET); the XML parser itself runs strict.
    #
    # == Page markers
    #
    # LEME's tagset lists <page> as the "page-break marker"; one file
    # (Martinez 1593) writes it as a container that closes across open
    # word-entries (</page> inside a <subxpln>) — read as the milestone the
    # tagset defines (<page no="10"> → a page break, </page> → nothing),
    # which makes that file parse. Page breaks feed the "page" annotation.
    #
    # == What an entry carries
    #
    # - entry_id: "e<n>", the word-entry's ordinal in the file (LEME's XML
    #   carries no entry ids — 10 @anchor values in all); an upstream
    #   re-issue that inserts entries re-numbers the tail (revisions, never
    #   withdrawals).
    # - key_raw: the <form> text as printed ("AMerciament,"); headword: the
    #   same with trailing punctuation dropped; the display text joins
    #   LEME's soft-hyphen line splits ("Troy&#173;\nweight" → "Troyweight",
    #   LEME's own display rule: "soft hyphens are not shown") and collapses
    #   whitespace — the spelling is otherwise the print's.
    # - language: the <form>'s @lang (inherited from an enclosing section /
    #   word-group @lang when absent) through LANGUAGES; LEME's code list is
    #   its own, so only codes the census evidences map — the rest (dialect
    #   county codes, thieves' cant, "un", "tbd" …) read "und" with the code
    #   verbatim as "leme_lang". A form with NO @lang anywhere (18,956 at
    #   census — Cawdrey's Table Alphabeticall among them) reads English,
    #   LEME's default object language (its encoding guide's own example
    #   is the lang-less <form lexeme="ditty(n)">dittie</form>), with
    #   "leme_lang" "none" recording the default; declared coarse — a few
    #   herbals' lang-less Latin plant names (Banckes 1525) ride as en too.
    # - body: line 1 the head and the explanation as printed; one line per
    #   <subform>/<subxpln> pair; marginal notes and editor additions in
    #   [brackets]. gloss: the explanation's first clause (≤ GLOSS_MAX).
    # - annotations: "xpln_lang" (the explanation's LEME code), "pos",
    #   "gender", "register", "dialect" (the <class> claims verbatim),
    #   "etymon_languages" (the LEME codes of <etym>/<class type=etymlang>),
    #   "lexemes" (LEME's OED modern headwords, form and explanation
    #   @lexeme split on "|"), "editor_notes" (the <lemenote>s), "page",
    #   "section", "group" (the innermost word-group object), "entry_type"
    #   (@type verbatim: h 940,018 · g 2,515 · d 992 at census — LEME does
    #   not publish the code's meaning, so it is carried, not interpreted),
    #   plus whatever per-lexicon context the caller passes (+context+).
    class LemeXmlParser
      # LEME form-language code → the stored language tag. Evidence: the
      # 2026-11-05 census over all 314 files, three sampled headwords per
      # code (en "AChilles", la "Abrotonum", it "Alerta", fr "Hargubuzier",
      # sp "Abanderado", oe Nowell's Vocabularium Saxonicum, me "Algats",
      # we Salesbury's Welsh, he/het the Hebrew of Martinez and Baldwin's
      # "Hebrue wurdes", gk/gkt Greek, sc "ABlins", du "Skance", pt "Braga",
      # ar "Algebra"). Codes left out are LEME-internal (county dialect
      # codes in Ray 1674 — ss, yk, nk …; ct thieves' cant; un; tbd) or too
      # thinly attested to name; they read "und".
      LANGUAGES = {
        "en" => "en", "la" => "lat", "it" => "ita", "fr" => "fra", "sp" => "spa",
        "oe" => "ang", "me" => "enm", "we" => "cym", "sc" => "sco", "du" => "nld",
        "pt" => "por", "ar" => "ara", "gk" => "grc", "gkt" => "grc", "he" => "hbo", "het" => "hbo"
      }.freeze
      UNDETERMINED = "und"
      DEFAULT_CODE = "en"

      Result = Data.define(:leme_no, :language, :entries, :census)

      PREDEFINED = %w[amp lt gt quot apos].freeze
      DOCTYPE = /<!DOCTYPE\s+\w+\s*\[(.*?)\]\s*>/m
      DECLARATION = /<!ENTITY\s+([A-Za-z][\w.-]*)\s+"([^"<>&]*(?:&#x?\h+;[^"<>&]*)*)"\s*>/
      ENTITY_REF = /&([A-Za-z_][\w.-]*);/
      PAGE_OPEN = /<page(\s[^>]*)?>/
      PAGE_CLOSE = %r{</page\s*>}
      GROUPS = %w[wordgroup1 wordgroup2 wordgroup3].freeze
      CONTAINERS = (%w[section] + GROUPS).freeze
      SKIP_IN_TEXT = %w[subform subxpln lemenote].freeze
      BRACKETED = %w[note editoraddition].freeze
      GLOSS_MAX = 100
      READER_OPTIONS = Nokogiri::XML::ParseOptions::NONET
      private_constant :PREDEFINED, :DOCTYPE, :DECLARATION, :ENTITY_REF, :PAGE_OPEN, :PAGE_CLOSE, :GROUPS,
                       :CONTAINERS, :SKIP_IN_TEXT, :BRACKETED, :GLOSS_MAX, :READER_OPTIONS

      # Map one LEME code to the stored tag (absent → the English default).
      def self.language_for(code)
        code = code.to_s.strip
        LANGUAGES.fetch(code.empty? ? DEFAULT_CODE : code, UNDETERMINED)
      end

      # +context+: per-lexicon annotations every entry carries (the
      # adapter's lexicon year and author). Raises Nabu::ParseError on
      # invalid UTF-8 or malformed XML.
      def parse(path, context: {})
        census = Hash.new(0)
        @leme_no = nil
        xml = prepare(SourceRead.utf8_file(path, label: "leme-xml"), census)
        raw = collect(xml, path)
        language = shelf_language(raw)
        entries = raw.each_with_index.filter_map do |item, index|
          build(item, index + 1, language, context, census)
        end
        Result.new(leme_no: @leme_no, language: language, entries: entries, census: census)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "leme-xml: malformed XML in #{path}: #{e.message}"
      end

      private

      # The entity-safe, milestone-paged text the strict parser reads.
      def prepare(text, census)
        text = text.delete_prefix("﻿")
        table = LEME_ENTITIES.dup
        text = text.sub(DOCTYPE) do
          subset = Regexp.last_match(1)
          declared = subset.scan(DECLARATION)
          if declared.size == subset.scan("<!ENTITY").size
            table.merge!(declared.to_h)
          else
            census["broken_entity_subset"] += 1
          end
          ""
        end
        text = text.gsub(ENTITY_REF) do
          name = Regexp.last_match(1)
          next "&#{name};" if PREDEFINED.include?(name)
          next table[name] if table.key?(name)

          census["unknown_entity:#{name}"] += 1
          "&amp;#{name};"
        end
        text.gsub(PAGE_OPEN) { "<pb#{Regexp.last_match(1)}/>" }.gsub(PAGE_CLOSE, "")
      end

      # Stream the file: one raw item per <wordentry>, with its context.
      def collect(xml, path)
        items = []
        state = { containers: [], page: nil, skip_depth: nil }
        Nokogiri::XML::Reader(xml, path, "UTF-8", READER_OPTIONS).each do |node|
          if state[:skip_depth]
            next unless node.depth == state[:skip_depth] && node.node_type == Nokogiri::XML::Reader::TYPE_END_ELEMENT

            state[:skip_depth] = nil
            next
          end
          step(node, state, items)
        end
        items
      end

      def step(node, state, items)
        case node.node_type
        when Nokogiri::XML::Reader::TYPE_ELEMENT
          case node.name
          when "leme" then @leme_no ||= node.attribute("no")
          when "pb" then state[:page] = page_label(node) || state[:page]
          when *CONTAINERS
            frame = { name: node.name, type: node.attribute("type"), object: node.attribute("object"),
                      lang: node.attribute("lang") }
            state[:containers].push(frame) unless node.empty_element?
          when "wordentry" then items << entry_item(node, state)
          end
        when Nokogiri::XML::Reader::TYPE_END_ELEMENT
          state[:containers].pop if CONTAINERS.include?(node.name) && state[:containers].last&.dig(:name) == node.name
        end
      end

      def entry_item(node, state)
        doc = Nokogiri::XML(node.outer_xml, &:strict)
        elem = doc.root
        page = state[:page]
        last_pb = elem.xpath(".//pb").map { |pb| page_label(pb) }.compact.last
        state[:page] = last_pb if last_pb
        state[:skip_depth] = node.depth unless node.empty_element?
        frames = state[:containers]
        { elem: elem, page: page,
          section: frames.reverse.find { |f| f[:name] == "section" }&.dig(:type),
          group: frames.reverse.find { |f| GROUPS.include?(f[:name]) && f[:object] }&.dig(:object),
          inherited_lang: frames.reverse.find { |f| f[:lang] }&.dig(:lang) }
      end

      def page_label(node)
        %w[sig no fol pg].each do |attr|
          value = node.attribute(attr).to_s.strip
          return value unless value.empty?
        end
        nil
      end

      def form_code(item)
        form = item[:elem].at_xpath("form")
        code = form&.[]("lang").to_s.strip
        code.empty? ? item[:inherited_lang].to_s.strip : code
      end

      # The most frequent claimed language over the file's entries ("und"
      # only when nothing maps).
      def shelf_language(raw)
        tally = raw.map { |item| self.class.language_for(form_code(item)) }.reject { |l| l == UNDETERMINED }.tally
        tally.empty? ? UNDETERMINED : tally.max_by { |lang, count| [count, lang] }.first
      end

      def build(item, ordinal, shelf_language, context, census)
        elem = item[:elem]
        code = form_code(item)
        language = self.class.language_for(code)
        form = elem.at_xpath("form")
        key_raw = display(text_of(form), language)
        headword = key_raw.sub(/[\s,.;:]+\z/, "")
        if headword.empty?
          census["empty_headword"] += 1
          return nil
        end

        xpln = elem.at_xpath("xpln")
        explanation = display(text_of(xpln), language)
        Nabu::DictionaryEntry.new(
          entry_id: "e#{ordinal}", key_raw: key_raw, language: language, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: language),
          gloss: gloss(explanation), body: body(key_raw, explanation, xpln, language),
          annotations: annotations(item, code, language, shelf_language, context)
        )
      end

      def body(key_raw, explanation, xpln, language)
        lines = [[key_raw, explanation].reject(&:empty?).join(" ")]
        return lines.first if xpln.nil?

        xpln.xpath("subform | subxpln").slice_before { |n| n.name == "subform" }.each do |pair|
          line = pair.map { |n| display(text_of(n), language) }.reject(&:empty?).join(" ")
          lines << line unless line.empty?
        end
        lines.join("\n")
      end

      def gloss(explanation)
        cut = explanation.split(/[.;:]\s|[.;:]\z/, 2).first.to_s.sub(/[\s\p{P}]+\z/, "").sub(/\A[\s\p{P}]+/, "")
        cut = "#{cut[0, GLOSS_MAX].sub(/\s+\S*\z/, '')}…" if cut.length > GLOSS_MAX
        cut.match?(/\p{L}/) ? cut : nil
      end

      def annotations(item, code, language, shelf_language, context)
        elem = item[:elem]
        found = context.dup
        found["language"] = language if language != shelf_language
        found["leme_lang"] = code.empty? ? "none" : code unless LANGUAGES.key?(code)
        xpln_lang = elem.at_xpath("xpln")&.[]("lang").to_s.strip
        found["xpln_lang"] = xpln_lang unless xpln_lang.empty?
        classes(elem, found)
        etymons = (elem.xpath(".//etym/@lang") + elem.xpath(".//class[@type='etymlang']/@lang"))
                  .map { |a| a.value.strip }.reject(&:empty?).uniq
        found["etymon_languages"] = etymons unless etymons.empty?
        lexemes = elem.xpath("form/@lexeme | xpln/@lexeme").flat_map { |a| a.value.split("|") }
                                                           .map(&:strip).reject(&:empty?).uniq
        found["lexemes"] = lexemes unless lexemes.empty?
        notes = elem.xpath(".//lemenote").map { |n| display(n.text, "en") }.reject(&:empty?)
        found["editor_notes"] = notes unless notes.empty?
        { "page" => item[:page], "section" => item[:section], "group" => item[:group],
          "entry_type" => elem["type"] }.each { |key, value| found[key] = value unless value.to_s.strip.empty? }
        found
      end

      def classes(elem, found)
        elem.xpath(".//class[@type]").each do |klass|
          type = klass["type"].to_s.strip
          key, value = case type
                       when "pos", "register", "dialect" then [type, display(klass.text, "en")]
                       when /\Agender:(\w+)\z/ then ["gender", Regexp.last_match(1)]
                       end
          next if key.nil? || value.empty?

          (found[key] ||= []) << value unless found[key]&.include?(value)
        end
      end

      # The text of +node+ in document order: sub-entries and LEME's
      # editorial notes left out (they ride their own lines/annotations),
      # marginal notes and editor additions bracketed.
      def text_of(node, out = +"")
        return out if node.nil?

        node.children.each do |child|
          if child.text? || child.cdata?
            out << child.text
          elsif child.element?
            next if SKIP_IN_TEXT.include?(child.name)

            if BRACKETED.include?(child.name)
              inner = text_of(child).strip
              out << " [#{inner}] " unless inner.empty?
            else
              text_of(child, out)
            end
          end
        end
        out
      end

      def display(text, language)
        joined = text.gsub(/­\s*/, "").gsub(/\s+/, " ").strip
        SourceRead.nfc(joined, language: language)
      end
    end
  end
end
