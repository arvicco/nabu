# frozen_string_literal: true

require "nokogiri"

require_relative "source_read"
require_relative "../normalize"

module Nabu
  module Adapters
    # The lane-tei parser family: the Perseus digitization of Lane's
    # Arabic-English Lexicon as the Alpheios project ships it — TEI P4
    # letter buckets (<TEI.2>, div1 = letter, div2 type="root" = one root
    # article headed by its radicals, entryFree = one paragraph of the
    # article, <pb n> = the printed page, <milestone unit="sense"> = Lane's
    # ―/＝ sense divisions). The Arabic is Unicode throughout (no
    # Buckwalter in the text — Buckwalter letters survive only in the
    # file names and div1/@n), so no transliteration layer exists here.
    #
    # Streams the bucket with Nokogiri::XML::Reader (the largest, u_E0.xml,
    # is 5.1 MB) and DOM-parses one entryFree at a time; the file's entries
    # are held only long enough to resolve its cross-references (the
    # resolution needs the whole file's headwords and each root's
    # paragraph numbers).
    #
    # == Identity (the entry_id)
    #
    # - an entry WITH @id keeps it verbatim ("n14041"), qualified by
    #   +id_prefix+ when the caller declares the file a variant copy
    #   ("uq2.n42477");
    # - an entry WITHOUT @id (Lane's derived-verb paragraphs and "See
    #   Supplement" stubs, which the digitization left id-less) is anchored
    #   on the nearest preceding id entry of the same file plus its ordinal
    #   since that anchor ("n14041.1"); before any id entry the anchor is
    #   the prefix, else the file stem ("uq2.1"). Deterministic per file
    #   byte state; the adapter class note carries the full design.
    #
    # == What one entry yields (Nabu::DictionaryEntry, language ara)
    #
    # - headword: the FIRST <form>'s <orth> (later <form n="infl"> orths
    #   are aorist vowels inside the body), else @key, else the root
    #   heading's Arabic (the id-less, orth-less stubs). Placeholder orths
    #   the digitization left with radical digits ("تَشَبَّ3َ") stay
    #   verbatim — canonical means canonical; they simply fold to no real
    #   word.
    # - key_raw: @key, else the headword; headword_folded: the key folded
    #   by the house Arabic rule (Normalize.search_form, ara).
    # - gloss: the first sense's first English italic run, joined across
    #   short parenthetical gaps ("He (a lion) roared.") — best-effort, nil
    #   for pure pointer paragraphs.
    # - body: the whole entry as text, whitespace collapsed, each sense
    #   milestone starting a new line (the digitizers' "-A2-"/"-b3-" sense
    #   tags are upstream text and stay).
    # - annotations: "root" (the div2 heading's radicals), "paragraph"
    #   (Lane's paragraph number from <itype>: "1", "10", "R. Q. 2"),
    #   "page" (the printed page the entry starts on — the last <pb n>
    #   before it; absent before a file's first <pb>, never guessed) and
    #   "page_end" (when the entry runs onto a later page), plus whatever
    #   +annotations+ the caller passes.
    # - crossrefs (kind "see"): "see <Arabic>" pointers — target_id when
    #   the vocalized target is exactly ONE headword or key of this file,
    #   else target_folded for the loader's dictionary-wide unique-fold
    #   resolution; and "see N" / "see R. Q. N" paragraph pointers —
    #   target_id when the same root holds exactly one paragraph N (a
    #   pointer into another article, "see 2 in art. X", mints nothing).
    #   Prose pointers ("see the next paragraph") stay body text.
    class LaneTeiParser
      LANGUAGE = "ara"

      # Lane's paragraph numbers: a derived-form number, optionally under a
      # quadriliteral class ("R. Q." reduplicated, "Q. Q.", "Q.").
      PARAGRAPH = /\A(?:(?:R\.|Q\.)\s*)?(?:Q\.\s*)?\d+\z/
      PARAGRAPH_POINTER = /\bsee\s+(?:also\s+)?(?<class>R\.\s*Q\.\s*|Q\.\s*Q\.\s*|Q\.\s*)?(?<number>\d+)\b/i
      # A paragraph pointer into ANOTHER article — not this root's paragraph.
      FOREIGN_ARTICLE = /\A[,;:]?\s*(?:in|of)\s+(?:art\b|that art|the art)/
      SEE_BEFORE = /\bsee(?:\s+also)?\s*\z/i

      # Gloss assembly: an abbreviation-only italic run ("i. e.", "q. v.")
      # is never a gloss; a gap of plain text this short (no Arabic, no
      # editorial brackets) joins two italic runs; at most this many runs.
      ABBREVIATION = /\A(?:\p{L}{1,4}\.\s*)+\z/
      GLOSS_GAP = 20
      GLOSS_RUNS = 4

      # Parse +path+ and return its Nabu::DictionaryEntry values in file
      # order. +id_prefix+ qualifies every id (the variant-copy rule);
      # +annotations+ merge into every entry's own.
      def entries(path, id_prefix: nil, annotations: {})
        records = scan(path, stem: id_prefix || File.basename(path, ".xml"), id_prefix: id_prefix)
        resolver = Resolver.new(records)
        records.map { |record| build(record, resolver, annotations) }
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "lane-tei: malformed XML in #{path}: #{e.message}"
      end

      # One scanned paragraph, before resolution.
      Record = Data.define(:entry_id, :element, :root, :root_seq, :page, :page_end, :headword, :key,
                           :paragraph)

      # Headword/paragraph lookups over one file's records.
      class Resolver
        def initialize(records)
          @by_form = Hash.new { |hash, key| hash[key] = [] }
          @by_paragraph = Hash.new { |hash, key| hash[key] = [] }
          records.each do |record|
            [record.headword, record.key].compact.uniq.each { |form| @by_form[form] << record.entry_id }
            @by_paragraph[[record.root_seq, record.paragraph]] << record.entry_id if record.paragraph
          end
        end

        def headword(form) = unique(@by_form.fetch(form, []))

        def paragraph(root_seq, label) = unique(@by_paragraph.fetch([root_seq, label], []))

        private

        def unique(ids)
          ids = ids.uniq
          ids.size == 1 ? ids.first : nil
        end
      end

      private

      def scan(path, stem:, id_prefix:)
        text = SourceRead.utf8_file(path, label: "lane-tei")
        state = { root: nil, root_seq: 0, pending_root: false, page: nil, anchor: stem, ordinal: 0 }
        records = []
        Nokogiri::XML::Reader(text, path).each do |node|
          next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

          case node.name
          when "div2" then open_division(node, state)
          when "head" then read_root(node, state) if state[:pending_root]
          when "pb" then state[:page] = node.attribute("n")
          when "entryFree" then records << record(node, state, id_prefix: id_prefix)
          end
        end
        records
      end

      def open_division(node, state)
        state[:root_seq] += 1
        state[:root] = nil
        state[:heading] = nil
        state[:pending_root] = node.attribute("type") == "root"
      end

      # The root heading's radicals: its <foreign lang="ar"> (the "&c." of
      # "يتم &c." is Lane's, not the root's), else the whole heading.
      def read_root(node, state)
        head = Nokogiri::XML.fragment(node.outer_xml).children.find(&:element?)
        foreign = head.at_xpath(".//foreign")
        root = collapse((foreign || head).text)
        state[:root] = root.empty? ? nil : Nabu::Normalize.nfc(root)
        state[:heading] = head
        state[:pending_root] = false
      end

      def record(node, state, id_prefix:)
        elem = Nokogiri::XML.fragment(node.outer_xml).children.find(&:element?)
        raise Nabu::ParseError, "lane-tei: unreadable entryFree after #{state[:anchor]}" if elem.nil?

        page = state[:page]
        inner = elem.xpath(".//pb").map { |pb| pb["n"] }.last
        Record.new(
          entry_id: entry_id(elem, state, id_prefix: id_prefix), element: content(elem, state),
          root: state[:root], root_seq: state[:root_seq], page: page,
          page_end: inner == page ? nil : inner,
          headword: headword(elem, state[:root]), key: elem["key"] && Nabu::Normalize.nfc(elem["key"]),
          paragraph: paragraph(elem)
        )
      end

      # What the entry's text is read from: the entryFree itself, or — for
      # the one text-less entryFree upstream (uq2.xml, root قو, whose
      # heading IS the article: "قو: see قوى") — its root heading.
      def content(elem, state)
        return elem unless collapse(elem.text).empty?

        heading = state[:heading]
        return heading if heading && !collapse(heading.text).empty?

        raise Nabu::ParseError, "lane-tei: text-less entryFree after #{state[:anchor]} outside any root"
      end

      def entry_id(elem, state, id_prefix:)
        if (upstream = elem["id"])
          state[:anchor] = id_prefix ? "#{id_prefix}.#{upstream}" : upstream
          state[:ordinal] = 0
          state[:anchor]
        else
          state[:ordinal] += 1
          "#{state[:anchor]}.#{state[:ordinal]}"
        end
      end

      def headword(elem, root)
        orth = collapse(elem.at_xpath("./form/orth")&.text.to_s)
        raw = [orth, elem["key"].to_s.strip, root.to_s].find { |candidate| !candidate.empty? }
        raise Nabu::ParseError, "lane-tei: entry without orth, key or root (id #{elem['id'].inspect})" if raw.nil?

        Nabu::Normalize.nfc(raw)
      end

      def paragraph(elem)
        label = collapse(elem.at_xpath("./form/itype")&.text.to_s)
        label.match?(PARAGRAPH) ? label : nil
      end

      def build(record, resolver, extra)
        key = record.key || record.headword
        Nabu::DictionaryEntry.new(
          entry_id: record.entry_id, key_raw: key, language: LANGUAGE,
          headword: record.headword,
          headword_folded: Nabu::Normalize.search_form(key, language: LANGUAGE),
          gloss: gloss(record.element),
          body: body(record.element),
          crossrefs: see_crossrefs(record, resolver) + paragraph_crossrefs(record, resolver),
          annotations: annotations(record).merge(extra)
        )
      end

      def annotations(record)
        {
          "root" => record.root, "paragraph" => record.paragraph,
          "page" => record.page, "page_end" => record.page_end
        }.compact
      end

      # -- gloss ----------------------------------------------------------------

      def gloss(elem)
        segments = first_sense_segments(elem)
        start = segments.index { |kind, text| kind == :ital && gloss_run?(text) }
        return nil if start.nil?

        assemble_gloss(segments[start..])
      end

      def gloss_run?(text)
        run = collapse(text)
        !run.empty? && !run.match?(ABBREVIATION)
      end

      def assemble_gloss(segments)
        gloss = +""
        gap = +""
        runs = 0
        segments.each do |kind, text|
          if kind == :ital
            gloss << gap << text
            gap = +""
            runs += 1
            break if runs >= GLOSS_RUNS || collapse(text).match?(/[.!?:;]\z/)
          else
            break if kind == :arabic

            gap << text
            break if collapse(gap).size > GLOSS_GAP || gap.match?(/[\[\]]/)
          end
        end
        result = collapse(gloss).sub(/[\s,;:]+\z/, "")
        result.empty? ? nil : Nabu::Normalize.nfc(result)
      end

      # The entry's text leaves up to the first sense milestone, tagged
      # :ital (English italic gloss text), :arabic, or :roman — the <form>
      # (headword block) and quoted verse excluded.
      def first_sense_segments(elem)
        segments = []
        catch(:milestone) { collect_segments(elem, segments, :roman) }
        segments
      end

      def collect_segments(node, segments, kind)
        node.children.each do |child|
          if child.text?
            segments << [kind, child.text]
          elsif child.element?
            throw :milestone if child.name == "milestone"
            next if %w[form quote].include?(child.name)

            collect_segments(child, segments, segment_kind(child, kind))
          end
        end
      end

      def segment_kind(child, inherited)
        return :arabic if child["lang"] == "ar"
        return :ital if child.name == "hi" && child["rend"] == "ital"

        inherited
      end

      # -- body ----------------------------------------------------------------

      def body(elem)
        buffer = +""
        walk(elem, buffer)
        Nabu::Normalize.nfc(buffer.gsub(/[ \t]+/, " ").gsub(/ *\n */, "\n").strip)
      end

      def walk(node, buffer)
        node.children.each do |child|
          if child.text?
            buffer << child.text.gsub(/\s+/, " ")
          elsif child.element?
            buffer << "\n" if child.name == "milestone"
            walk(child, buffer)
          end
        end
      end

      # -- cross-references ------------------------------------------------------

      def see_crossrefs(record, resolver)
        record.element.xpath(".//foreign[@lang='ar']").filter_map do |foreign|
          before = foreign.previous_sibling
          next unless before&.text? && before.text.match?(SEE_BEFORE)

          target = Nabu::Normalize.nfc(collapse(foreign.text))
          next if target.empty?

          see_crossref(target, resolver.headword(target), record.entry_id)
        end.uniq(&:target)
      end

      def see_crossref(target, target_id, own_id)
        return nil if target_id == own_id

        folded = target_id ? nil : Nabu::Normalize.search_form(target, language: LANGUAGE)
        Nabu::DictionaryCrossref.new(kind: "see", label: "see #{target}", target: target, target_id: target_id,
                                     target_folded: folded.nil? || folded.strip.empty? ? nil : folded)
      end

      def paragraph_crossrefs(record, resolver)
        text = collapse(record.element.text)
        text.to_enum(:scan, PARAGRAPH_POINTER).filter_map do
          match = Regexp.last_match
          next if text[match.end(0)..].match?(FOREIGN_ARTICLE)

          label = "#{collapse(match[:class].to_s)} #{match[:number]}".strip
          target_id = resolver.paragraph(record.root_seq, label)
          next if target_id.nil? || target_id == record.entry_id

          Nabu::DictionaryCrossref.new(kind: "see", label: "see #{label}", target: label, target_id: target_id)
        end.uniq(&:target_id)
      end

      def collapse(text)
        text.gsub(/\s+/, " ").strip
      end
    end
  end
end
