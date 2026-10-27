# frozen_string_literal: true

require "json"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The `tipitaka-lk-json` parser family: one tipitaka.lk text file
    # (public/static/text/<file>.json — the proofreaders' ground truth, from
    # which upstream's own build derives everything else).
    #
    # == The shape (upstream's own, read from the files and from its build:
    #    build/validate.ts, shared/markup.ts, shared/footnote.ts)
    #
    #   { "filename": "kn-khp", "bookId": 28, "pageOffset": 0,
    #     "collection": "mula" | "atta",            (absent on a few files)
    #     "pages": [ { "pageNum": 2,
    #                  "pali": { "entries": [...], "footnotes": [...] },
    #                  "sinh": { "entries": [...], "footnotes": [...] } } ] }
    #
    # pageNum is the printed Buddha Jayanthi page (Pāli on the even page,
    # the Sinhala facing it; strictly increasing within a file — an upstream
    # validation error otherwise). An entry is {type, text, level?,
    # keyOffset?}; type ∈ centered/heading/paragraph/gatha/unindented.
    # Upstream's build REQUIRES equal pali/sinh entry counts per page, so
    # entry n of one column renders entry n of the other — the alignment
    # this family's citation rides on. The Paṭṭhāna files (ap-pat*) are
    # served Pāli-only: their sinh columns are empty.
    #
    # == One layer per parse; the citation
    #
    # #parse yields ONE layer (layer: "pali" → language pli, "sinh" → si).
    # Passage citation = <pageNum>.<entry n> (n 1-based within the page's
    # column), identical on both layers — so a Sinhala sibling document
    # aligns to its Pāli root by suffix equality (Query::Parallel), with no
    # stored links. Entries whose plain text is empty (upstream keeps
    # placeholders to hold the pairing) are skipped by rule and counted in
    # metadata["empty_entries_skipped"]; the citation of the following
    # entries never shifts.
    #
    # == Text: upstream's own plain rendering
    #
    # Inline markup (shared/markup.ts): **bold** __underline__ ~~strike~~
    # $$editorial$$ {fn} pointers, "\n"/"↴" line breaks, <hr/>, the three
    # entities; unbalanced markers are literal. Passage text is upstream's
    # tokensToPlain of it — markers dropped, container content kept,
    # footnote pointers dropped, breaks as "\n" — ported verbatim as
    # Markup below; nothing is corrected or re-spelled (the license forbids
    # local correction: errors go upstream). What the plain form drops
    # rides annotations: the footnotes the entry points at (resolved on the
    # page's own column by upstream's parseFootnote rule — "<n>. <content>"),
    # the bold spans (in the commentaries these are the quoted lemmata),
    # type/level/keyOffset verbatim, the printed page, and the per-passage
    # attribution the license asks for.
    class TipitakaLkJsonParser
      LAYERS = { "pali" => "pli", "sinh" => "si" }.freeze
      ATTRIBUTION = "tipitaka.lk"

      # upstream's parseFootnote: /^([^\s\.\{\}]+)[\.\s]([\s\S]+)$/
      FOOTNOTE = /\A([^\s.{}]+)[.\s](.+)\z/m

      # Port of shared/markup.ts parseMarkup + tokensToPlain. Token trees
      # are never kept: one walk yields the plain text, the bold spans and
      # the footnote pointers.
      module Markup
        Rendered = Data.define(:text, :bold, :footnote_refs)

        PAIRS = { "**" => :bold, "__" => :underline, "~~" => :strike, "##" => :highlight,
                  "$$" => :editorial }.freeze
        ENTITIES = { "&gt;" => ">", "&lt;" => "<", "&amp;" => "&" }.freeze
        PAIR_LEADS = %w[* _ ~ # $].freeze
        TAG = %r{\A<(/?)(hr|b)\s*/?>}i
        ENTITY = /\A&(gt|lt|amp);/
        # Any character that can open a construct; text without one is
        # already its own plain form (the common case — a fast path only).
        SPECIAL = Regexp.union(%w[* _ ~ # $ { ↴ < &] + ["\n"])

        def self.render(text)
          text = text.to_s
          return Rendered.new(text: text, bold: [], footnote_refs: []) unless SPECIAL.match?(text)

          chars = text.chars
          bold = []
          refs = []
          plain = walk(chars, 0, chars.size, bold, refs)
          Rendered.new(text: plain, bold: bold, footnote_refs: refs)
        end

        def self.walk(chars, start, stop, bold, refs)
          out = +""
          i = start
          while i < stop
            two = PAIR_LEADS.include?(chars[i]) ? chars[i, 2].join : nil
            if (kind = PAIRS[two])
              close = find(chars, two, i + 2)
              if close && close + 2 <= stop
                inner = walk(chars, i + 2, close, bold, refs)
                bold << inner if kind == :bold
                out << inner
                i = close + 2
              else
                out << two
                i += 2
              end
              next
            end

            step = special(chars, i, stop, out, refs)
            if step
              i += step
            else
              out << chars[i]
              i += 1
            end
          end
          out
        end

        # The single-character constructs; returns the chars consumed, or
        # nil when chars[pos] is plain text.
        def self.special(chars, pos, stop, out, refs)
          case chars[pos]
          when "{"
            close = find(chars, "}", pos + 1)
            return nil unless close && close > pos + 1 && close < stop

            pointer = chars[(pos + 1)...close].join
            return nil if pointer.include?("\n")

            refs << pointer
            close + 1 - pos
          when "\n", "↴"
            out << "\n"
            1
          when "<"
            match = TAG.match(chars[pos, [stop, pos + 8].min - pos].join) or return nil
            out << "\n" if match[2].casecmp?("hr")
            match[0].length
          when "&"
            match = ENTITY.match(chars[pos, 5].join) or return nil
            out << ENTITIES.fetch(match[0])
            match[0].length
          end
        end

        # JS String#indexOf over the whole string (not bounded by +stop+ —
        # the caller checks the bound, exactly as upstream does).
        def self.find(chars, needle, from)
          width = needle.length
          (from..(chars.size - width)).find { |j| chars[j, width].join == needle }
        end
      end

      # +block+, when given, receives the parsed document metadata and
      # returns extra keys to merge (the adapter's layer-dependent facets
      # and provenance) — so the Document is built once, complete.
      def parse(path, urn:, layer:)
        language = LAYERS.fetch(layer)
        data = read(path)
        pages = data.fetch("pages")
        stats = { empty: 0, unattached: 0 }
        passages = pages.flat_map { |page| page_passages(page, layer, urn, language, stats) }
        metadata = document_metadata(data, pages, stats)
        metadata = metadata.merge(yield(metadata)) if block_given?
        document = Nabu::Document.new(
          urn: urn, language: language, canonical_path: path.to_s,
          title: title(pages, layer) || data["filename"], metadata: metadata
        )
        passages.each_with_index do |(urn_, text, notes), sequence|
          document << passage(urn_, text, notes, language, sequence)
        end
        document
      rescue JSON::ParserError, KeyError, TypeError => e
        raise Nabu::ParseError, "#{path}: not a tipitaka.lk text file (#{e.class}: #{e.message})"
      end

      private

      def read(path)
        data = JSON.parse(SourceRead.utf8_file(path, label: "tipitaka-lk"))
        raise Nabu::ParseError, "#{path}: top level is not an object" unless data.is_a?(Hash)

        data
      end

      # [urn, text, annotations] per non-empty entry of the page's column;
      # empty entries and footnotes no entry points at are counted.
      def page_passages(page, layer, urn, _language, stats)
        number = page.fetch("pageNum")
        column = page[layer] || {}
        footnotes = footnote_table(column["footnotes"])
        referenced = []
        rows = Array(column["entries"]).each_with_index.filter_map do |entry, index|
          rendered = Markup.render(entry.fetch("text"))
          text = Normalize.nfc(rendered.text.strip)
          if text.empty?
            stats[:empty] += 1
            next
          end

          notes = annotations(entry, number, rendered, footnotes)
          referenced.concat(notes.fetch("footnotes", {}).keys)
          ["#{urn}:#{number}.#{index + 1}", text, notes]
        end
        stats[:unattached] += (footnotes.keys - referenced).size
        rows
      end

      def passage(urn, text, notes, language, sequence)
        Nabu::Passage.new(urn: urn, language: language, text: text, sequence: sequence, annotations: notes)
      end

      def annotations(entry, page, rendered, footnotes)
        notes = { "type" => entry.fetch("type") }
        notes["level"] = entry["level"] if entry.key?("level")
        notes["key_offset"] = entry["keyOffset"] if entry.key?("keyOffset")
        notes["page"] = page
        bold = rendered.bold.map { |span| Normalize.nfc(span.strip) }.reject(&:empty?)
        notes["bold"] = bold unless bold.empty?
        resolved = rendered.footnote_refs.uniq.to_h { |ref| [ref, footnotes[ref]] }.compact
        notes["footnotes"] = resolved unless resolved.empty?
        notes["attribution"] = ATTRIBUTION
        notes
      end

      # number => plain content, first occurrence wins (upstream renders
      # footnotes in order; a repeated number is a proofreading slip it
      # warns about, never a second note to merge).
      def footnote_table(footnotes)
        Array(footnotes).each_with_object({}) do |footnote, table|
          match = FOOTNOTE.match(footnote.fetch("text").to_s) or next
          content = Normalize.nfc(Markup.render(match[2]).text.strip)
          table[match[1]] ||= content unless content.empty?
        end
      end

      # upstream's getName over the layer's first heading (build/tree.ts:
      # pointers, brackets, markers and a trailing full stop dropped).
      def title(pages, layer)
        heading = pages.lazy.flat_map { |page| Array(page.dig(layer, "entries")) }
                            .find { |entry| entry["type"] == "heading" }
        return nil unless heading

        name = heading["text"].to_s.strip.gsub(/\{.*?\}/, "").gsub(/[\[\]()]/, "").gsub(/\$\$|\*\*|__/, "")
        name = Normalize.nfc(name.sub(/\.\z/, "").strip)
        name.empty? ? nil : name
      end

      def document_metadata(data, pages, stats)
        {
          "file" => data["filename"],
          "book_id" => data["bookId"],
          "page_offset" => data["pageOffset"],
          "collection" => data["collection"],
          "pages" => [pages.first&.fetch("pageNum"), pages.last&.fetch("pageNum")],
          "empty_entries_skipped" => stats[:empty],
          "footnotes_unattached" => stats[:unattached],
          "attribution" => ATTRIBUTION
        }.compact
      end
    end
  end
end
