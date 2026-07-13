# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"
require_relative "../slp1"
require_relative "mw_sigla"

module Nabu
  module Adapters
    # The mw-xml parser family (P17-4): Cologne CDSL's mw.xml — one record
    # per LINE inside <mw>…</mw>, streamed line by line (the file is 64 MB;
    # no DOM over the whole, CLAUDE.md's >5 MB rule). Each line is one
    # <H1|H2|H3|H4[A|B|C|E]> record; a MAIN record (H1–H4, MW's own four
    # headword lines) opens an entry and its immediately following lettered
    # records continue it (A sense-continuation, B gender block, C inflected
    # form, E etymology — file order guarantees adjacency, mw-meta2.txt), so
    # 286,525 records group into 193,890 entries (mw-survey §2/§6).
    #
    # == What one grouped entry yields (Nabu::DictionaryEntry)
    #
    # - entry_id: the main record's <L> — Cologne's stable per-record id
    #   (survives upstream revisions; fractions mark supplement inserts).
    # - key_raw: the main record's key2 VERBATIM — SLP1 with accents and
    #   compound seams (a/MSa, aMSa—karaRa); canonical means canonical.
    # - headword: IAST of key1 (Nabu::Slp1 — the adapter-boundary transcode,
    #   survey §2; no Devanagari exists upstream).
    # - headword_folded: the generic conventions-§9 fold of the IAST form —
    #   the SAME folded shape GRETIL's san-Latn text produces, which is what
    #   joins the two shelves (fold("aṃśa") = "amsa").
    # - gloss: best-effort first sense of the MAIN record: for verb records
    #   the text after the first <div n="to"/> sense break, otherwise the
    #   body text with the leading headword echo/apparatus and any leading
    #   parenthetical etymology stripped; cut before the first citation.
    #   nil is honest (cross-reference stubs).
    # - body: one line per record in the group (MW's sense-per-record maps
    #   onto B-T's sense-per-line), <s> SLP1 transcoded to IAST for display,
    #   <div> sense breaks as further lines, technical elements skipped —
    #   plus a final machine-readable "grammar:" line decoded from the
    #   <info> apparatus (lex= gender, verb=/cp= root class-pada,
    #   westergaard=/whitneyroots= references) when the entry carries any.
    # - citations: one DictionaryCitation per <ls> across the group, in
    #   document order. label/urn_raw is the RESTORED display text (the @n
    #   attribute rejoins elliptical continuations upstream pre-resolved:
    #   <ls n="RV.">x, 109, 1</ls> → "RV. x, 109, 1"); cts_work/citation
    #   come from the curated MwSigla map — GRETIL document urn + normalized
    #   dot citation at passage grain, urn only at document grain, nil+label
    #   for authority labels and works not held (the honest-miss shape).
    # - reflexes: MW's own cognate notes (survey §4) — each <lang> tag whose
    #   label is a genuine cognate language (COGNATE_LANGS; register markers
    #   like Ved./ep. mint NOTHING) paired with its adjacent tagged
    #   comparanda (<etym> Latin-script, <gk> polytonic Greek), one
    #   DictionaryReflex per (language, word). Coordination shares forms
    #   ("Goth. and Germ. un" mints both); language is the catalog-side tag
    #   for the unambiguous labels, nil (display-only) for Slav./Hib. —
    #   MW's "Slav." is usually but not reliably Church Slavonic.
    class MwXmlParser
      LANGUAGE = "san"

      MAIN_RECORD = /\AH[1-4]\z/
      CONTINUATION = /\AH[1-4][ABCE]\z/

      # Body elements that never contribute display text: page/column
      # apparatus, machine-readable info (decoded separately), print marks.
      SKIPPED_ELEMENTS = %w[info pb pc pcol lbinfo note mark edit pic C H P vlex sic hwtype].freeze

      # MW cognate-language labels → catalog language tags (mw-survey §4).
      # Tags align with the kaikki crosswalk's so the two shelves' reflex
      # rows meet on (language, word_folded). nil = display-only row, never
      # a join candidate: "Slav." (usually OCS, not reliably) and "Hib."
      # (Irish of no fixed period). Labels NOT in this map — the Ved./ep./
      # Class. register markers among them — mint no reflex at all.
      COGNATE_LANGS = {
        "Gk." => "grc", "Lat." => "lat", "Goth." => "got", "Lith." => "lit",
        "Angl.Sax." => "ang", "Zd." => "ae", "Eng." => "en", "Germ." => "de",
        "Russ." => "ru", "Armen." => "hy", "Slav." => nil, "Hib." => nil
      }.freeze

      # Parse +lines+ (any Enumerable of record lines — a File enumerator or
      # an unzipped string's each_line) and return DictionaryEntry values in
      # file order.
      def entries(lines)
        out = []
        group = nil
        lines.each do |line|
          record = parse_record(line) or next
          if record[:main]
            out << build_entry(group) if group
            group = [record]
          elsif group
            group << record
          else
            raise Nabu::ParseError, "mw-xml: continuation record L=#{record[:l]} before any main record"
          end
        end
        out << build_entry(group) if group
        out
      end

      private

      # One line → { tag:, main:, key1:, key2:, l:, body: } or nil for the
      # frame lines (<?xml…, DOCTYPE, comments, <mw>, </mw>).
      def parse_record(line)
        return nil unless line.lstrip.start_with?("<H")

        element = Nokogiri::XML.fragment(line).children.find(&:element?)
        return nil if element.nil? || !element.name.match?(/\AH[1-4][ABCE]?\z/)

        {
          tag: element.name, main: element.name.match?(MAIN_RECORD),
          key1: element.at_xpath("h/key1")&.text.to_s,
          key2: element.at_xpath("h/key2")&.text.to_s,
          l: element.at_xpath("tail/L")&.text.to_s,
          body: element.at_xpath("body")
        }
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "mw-xml: unparseable record line: #{e.message}"
      end

      def build_entry(group)
        main = group.first
        headword = Nabu::Normalize.nfc(Nabu::Slp1.to_iast(main[:key1]))
        Nabu::DictionaryEntry.new(
          entry_id: main[:l], key_raw: main[:key2].empty? ? main[:key1] : main[:key2],
          language: LANGUAGE, headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: LANGUAGE),
          gloss: gloss(main[:body]),
          body: body_text(group),
          citations: citations(group),
          reflexes: reflexes(group)
        )
      rescue Nabu::ValidationError, Nabu::Normalize::EncodingError => e
        raise Nabu::ParseError, "mw-xml: record L=#{main[:l].inspect}: #{e.message}"
      end

      # -- body ----------------------------------------------------------------

      # One line per record, <div> breaks as further lines, then the decoded
      # grammar apparatus.
      def body_text(group)
        lines = group.flat_map { |record| render(record[:body]).split("\n") }
                     .map(&:strip).reject(&:empty?)
        grammar = grammar_line(group)
        lines << grammar if grammar
        Nabu::Normalize.nfc(lines.join("\n"))
      end

      def render(node)
        buffer = +""
        walk(node, buffer)
        buffer.gsub(/[ \t]+/, " ").gsub(/ *\n+ */, "\n").strip
      end

      def walk(node, buffer)
        node.children.each do |child|
          if child.text?
            buffer << child.text.gsub(/\s+/, " ")
          elsif child.element?
            walk_element(child, buffer)
          end
        end
      end

      def walk_element(child, buffer)
        case child.name
        when "s" then buffer << sanskrit(child)
        when "div", "br", "lb" then buffer << "\n"
        when *SKIPPED_ELEMENTS then nil
        else walk(child, buffer)
        end
      end

      # <s> SLP1 → IAST. <srs/> marks a sandhi long vowel printed with a
      # circumflex (mw-meta2) — rendered as the combining circumflex on the
      # preceding vowel; <shortlong/> (may-be-long) adds nothing.
      def sanskrit(node)
        out = +""
        node.children.each do |child|
          if child.text?
            out << Nabu::Slp1.to_iast(child.text)
          elsif child.element? && child.name == "srs"
            out << "̂"
          end
        end
        out.unicode_normalize(:nfc)
      end

      # -- gloss ---------------------------------------------------------------

      def gloss(body)
        text = body.xpath("div[@n='to']").any? ? verb_gloss(body) : nominal_gloss(body)
        return nil if text.nil?

        cleaned = text.gsub(/\s+/, " ").strip.sub(/[\s,;:.(]+\z/, "")
        cleaned.empty? ? nil : Nabu::Normalize.nfc(cleaned)
      end

      # Verb records: the first <div n="to"/> sense break opens the first
      # English sense; collect up to the next citation or break.
      def verb_gloss(body)
        seen_break = false
        collect_gloss(body) do |child|
          if child.element? && child.name == "div"
            break_now = seen_break
            seen_break = true
            break_now ? :stop : :skip
          elsif seen_break
            child.element? && child.name == "ls" ? :stop : :take
          else
            :skip
          end
        end
      end

      # Nominal records: skip the leading headword echo / homonym digit /
      # gender label, collect until the first citation, then strip a leading
      # parenthetical etymology.
      def nominal_gloss(body)
        at_start = true
        text = collect_gloss(body) do |child|
          if child.element? && %w[s hom lex].include?(child.name) && at_start
            :skip
          elsif child.element? && child.name == "ls"
            :stop
          else
            at_start = false if child.element? || (child.text? && !child.text.strip.empty?)
            :take
          end
        end
        text && strip_leading_parenthetical(text)
      end

      # Walk the body's direct children; the block classifies each as
      # :take / :skip / :stop. Taken elements render like the display body.
      def collect_gloss(body)
        buffer = +""
        body.children.each do |child|
          case yield(child)
          when :stop then break
          when :take
            child.text? ? buffer << child.text.gsub(/\s+/, " ") : walk_element(child, buffer)
          end
        end
        text = buffer.tr("\n", " ").strip
        text.empty? ? nil : text
      end

      # Balanced-paren strip of ONE leading "(…)," group — MW opens many
      # entries with a parenthetical etymology before the actual gloss.
      def strip_leading_parenthetical(text)
        return text unless text.start_with?("(")

        depth = 0
        text.each_char.with_index do |char, index|
          depth += 1 if char == "("
          depth -= 1 if char == ")"
          return text[(index + 1)..].sub(/\A[\s,]+/, "") if depth.zero?
        end
        text
      end

      # -- citations -------------------------------------------------------------

      def citations(group)
        group.flat_map { |record| record[:body].xpath(".//ls") }.filter_map do |ls|
          label = restored_label(ls)
          next nil if label.empty?

          cts_work, citation = MwSigla.resolve(label)
          Nabu::DictionaryCitation.new(
            urn_raw: Nabu::Normalize.nfc(label), cts_work: cts_work,
            citation: citation, label: Nabu::Normalize.nfc(label)
          )
        end
      end

      # The @n attribute restores the elided context of continuation
      # citations upstream pre-resolved (survey §3): print "15" carries
      # n="RV. viii, 96," → "RV. viii, 96, 15".
      def restored_label(element)
        restored = [element["n"], element.text].compact.join(" ")
        restored.gsub(/\s+/, " ").strip
      end

      # -- cognate reflexes (survey §4) -------------------------------------------

      # Tag-stream walk over each record's <lang>/<etym>/<gk> elements:
      # <lang> labels accumulate while coordinated ("Goth. and Germ."),
      # reset once comparanda have been assigned; each <etym>/<gk> mints one
      # reflex per pending language. A <lang> that is NOT a cognate language
      # (a register marker) clears the state so nothing mis-attaches across
      # it.
      def reflexes(group)
        out = []
        pending = []
        assigned = false
        group.flat_map { |record| record[:body].xpath(".//lang | .//etym | .//gk") }.each do |element|
          if element.name == "lang"
            pending, assigned = next_pending(element, pending, assigned)
          elsif pending.any?
            word = element.text.gsub(/\s+/, " ").strip
            pending.each { |label| out << build_reflex(label, word) } unless word.empty?
            assigned = true
          end
        end
        out
      end

      def next_pending(element, pending, assigned)
        label = element.text.gsub(/\s+/, " ").strip
        return [[], false] unless COGNATE_LANGS.key?(label)

        assigned ? [[label], false] : [pending + [label], false]
      end

      def build_reflex(label, word)
        language = COGNATE_LANGS.fetch(label)
        folded = Nabu::Normalize.search_form(word, language: language)
        Nabu::DictionaryReflex.new(
          lang_code: label, language: language,
          word: Nabu::Normalize.nfc(word), roman: nil,
          word_folded: folded.strip.empty? ? nil : folded, roman_folded: nil
        )
      end

      # -- grammar (the machine-readable <info> apparatus) -------------------------

      def grammar_line(group)
        infos = group.flat_map { |record| record[:body].xpath(".//info") }
        parts = [gender_part(infos.find { |info| usable_lex?(info) }),
                 verb_part(infos.find { |info| info["verb"] }),
                 westergaard_part(infos.find { |info| info["westergaard"] }),
                 whitney_part(infos.find { |info| info["whitneyroots"] })].compact
        parts.empty? ? nil : "grammar: #{parts.join(' · ')}"
      end

      def usable_lex?(info)
        lex = info["lex"]
        lex && !lex.empty? && lex != "inh"
      end

      # lex="f#A:n" → "f(-ā), n" — colon-separated genders, # marking the
      # feminine stem suffix (SLP1, transcoded).
      def gender_part(info)
        return nil if info.nil?

        genders = info["lex"].split(":").map do |gender|
          base, suffix = gender.split("#", 2)
          suffix ? "#{base}(-#{Nabu::Slp1.to_iast(suffix)})" : base
        end
        genders.join(", ")
      end

      def verb_part(info)
        return nil if info.nil?

        cp = info["cp"]
        cp && !cp.empty? ? "verb #{info['verb']}, class-pada #{cp}" : "verb #{info['verb']}"
      end

      # westergaard="BAza,16.11,01.0396" → root (SLP1) + Dhātupāṭha ref.
      def westergaard_part(info)
        return nil if info.nil?

        root, ref, = info["westergaard"].split(",")
        "Westergaard Dhātup. #{Nabu::Slp1.to_iast(root.to_s)} #{ref}".strip
      end

      def whitney_part(info)
        return nil if info.nil?

        root, page = info["whitneyroots"].split(",")
        "Whitney roots #{Nabu::Slp1.to_iast(root.to_s)} #{page}".strip
      end
    end
  end
end
