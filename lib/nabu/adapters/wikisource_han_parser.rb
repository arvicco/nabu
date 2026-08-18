# frozen_string_literal: true

module Nabu
  module Adapters
    # The wikisource-han parser family (P78-5): MediaWiki wikitext as the
    # Wikisource projects write classical-Chinese TEXT pages — censused
    # 2026-08-18 over the 大越史記全書 tree and the two chữ-Hán showpieces
    # on zh/vi.wikisource. This class knows the SHAPES; the adapter decides
    # what they mean. Two censused page layouts:
    #
    # :prose — the common shape (every DVSKTT quyển, the hịch): a leading
    # {{header}}/{{header2}}/{{đầu đề}} template block, then paragraphs of
    # classical Chinese separated by blank lines, structured by == / ===
    # headings (the 紀 / ruler tree). Passage = one paragraph; the heading
    # path rides beside it. Inline interlinear notes — {{annotate|…}} (the
    # DVSKTT edition's 原注) and <sub>…</sub> reading glosses (the hịch's
    # 多改切-style fanqie) — render as 【…】 inline, the sillok 원주
    # precedent: original apparatus stays in the text, visibly marked.
    #
    # :parallel_poem — the vi.wikisource showpiece shape (平吳大誥): a
    # two-column layout table whose first <poem> block is the chữ Hán and
    # whose second is the Hán-Việt phiên âm, stanza-parallel. Passage = one
    # original-script stanza; the matching phiên âm stanza rides beside it
    # WHEN the stanza counts agree (they do once the editorial <ref>
    # footnotes — which contain blank lines — are stripped); on a count
    # mismatch the pairing would be a guess, so the whole phiên âm is
    # returned unpaired instead.
    #
    # Editorial wiki apparatus is dropped, never text: HTML comments,
    # <ref> footnotes, license/category/interwiki lines, layout-table
    # markup, the {{檢索}}/{{PD-old}} service templates. Text is NOT
    # normalized here — NFC happens at the adapter boundary (house rule).
    class WikisourceHanParser
      # The page-top template's machine-usable slots: +author+ (author /
      # override_author / tác giả, wiki links stripped), +year+ (the bare
      # year param — the hịch carries 1284; most pages none), +textquality+
      # (the wiki's own {{Textquality|N%}} proofreading status).
      Header = Data.define(:author, :year, :textquality)

      # One extracted passage: +section+ = the heading path ("紀 · ruler",
      # prose mode), +phien_am+ = the paired transliteration stanza
      # (parallel-poem mode); both nil when absent.
      Passage = Data.define(:text, :section, :phien_am)

      # +unpaired_phien_am+ is non-nil only in the mismatched-stanza case
      # (parallel-poem mode) — the whole phiên âm as one string.
      Result = Data.define(:header, :passages, :unpaired_phien_am)

      # Interlinear-note templates rendered inline as 【…】 (never dropped):
      # {{annotate|…}} and the index pages' {{*|…}} sibling.
      INLINE_NOTE_TEMPLATES = /\{\{(?:annotate|\*)\|([^{}]*)\}\}/

      def parse(wikitext, mode: :prose)
        text = strip_apparatus(wikitext.to_s)
        header_block, body = split_leading_template(text)
        header = parse_header(header_block)
        if mode == :parallel_poem
          passages, unpaired = poem_passages(body)
          Result.new(header: header, passages: passages, unpaired_phien_am: unpaired)
        else
          Result.new(header: header, passages: prose_passages(body), unpaired_phien_am: nil)
        end
      end

      private

      # -- page-level apparatus ---------------------------------------------------

      # Comments and <ref> footnotes go first: refs carry prose (and even
      # blank lines) that must never leak into text or stanza structure.
      def strip_apparatus(text)
        text.gsub(/<!--.*?-->/m, "")
            .gsub(%r{<ref[^<>]*/>}, "")
            .gsub(%r{<ref[^<>]*>.*?</ref>}m, "")
      end

      # The leading "{{…}}" block (header/header2/đầu đề/bản dịch — every
      # censused page opens with one) split off by brace balance, so nested
      # templates and piped links inside it never truncate the scan.
      def split_leading_template(text)
        stripped = text.lstrip
        return [nil, text] unless stripped.start_with?("{{")

        depth = 0
        stripped.scan(/\{\{|\}\}/) do |braces|
          depth += braces == "{{" ? 1 : -1
          next unless depth.zero?

          cut = Regexp.last_match.end(0)
          return [stripped[0...cut], stripped[cut..]]
        end
        [nil, text] # unbalanced header — treat the whole page as body
      end

      # -- the header template ------------------------------------------------------

      def parse_header(block)
        return Header.new(author: nil, year: nil, textquality: nil) if block.nil?

        params = template_params(block)
        Header.new(
          author: header_author(params),
          year: header_year(params),
          textquality: block[/\{\{Textquality\|(\d+%)\}\}/, 1]
        )
      end

      # Top-level "|" split with {{…}}/[[…]] depth tracked, so piped links
      # ([[作者:吳士連|吳士連]]) and nested templates stay inside their
      # param — including the censused one-line double param
      # ("| author = |override_author=…").
      def template_params(block)
        params = {}
        split_top_level(block.sub(/\A\{\{/, "").sub(/\}\}\z/, "")).drop(1).each do |fragment|
          key, eq, value = fragment.partition("=")
          next if eq.empty? || key.strip.empty?

          params[key.strip] = value.strip
        end
        params
      end

      def split_top_level(content)
        parts = [+""]
        depth = 0
        index = 0
        while index < content.length
          pair = content[index, 2]
          case pair
          when "{{", "[["  then depth += 1
          when "}}", "]]"  then depth -= 1
          end
          if %w[{{ [[ }} ]]].include?(pair)
            parts.last << pair
            index += 2
          elsif content[index] == "|" && depth.zero?
            parts << +""
            index += 1
          else
            parts.last << content[index]
            index += 1
          end
        end
        parts
      end

      def header_author(params)
        raw = ["override_author", "author", "tác giả"].map { |key| params[key].to_s.strip }.find { |v| !v.empty? }
        return nil if raw.nil?

        author = plain_inline(raw)
        author.empty? ? nil : author
      end

      def header_year(params)
        raw = params["year"].to_s.strip
        raw.match?(/\A\d{3,4}\z/) ? Integer(raw, 10) : nil
      end

      # -- prose mode ---------------------------------------------------------------

      # Paragraphs under their heading path. A heading or blank line closes
      # the open paragraph; markup-only lines (tables, category/interwiki
      # links, dropped service templates) contribute nothing.
      def prose_passages(body)
        state = { passages: [], levels: {}, buffer: [] }
        body.each_line do |raw|
          line = raw.chomp
          if (heading = line.match(/\A(={1,6})\s*(.*?)\s*\1\s*\z/))
            flush!(state)
            note_heading!(state, heading[1].length, plain_inline(heading[2]))
          elsif line.strip.empty?
            flush!(state)
          else
            text = prose_line(line)
            state[:buffer] << text unless text.empty?
          end
        end
        flush!(state)
        state[:passages]
      end

      def flush!(state)
        return if state[:buffer].empty?

        section = state[:levels].sort.map(&:last).join(" · ")
        state[:passages] << Passage.new(text: state[:buffer].join("\n"),
                                        section: section.empty? ? nil : section, phien_am: nil)
        state[:buffer].clear
      end

      def note_heading!(state, level, text)
        state[:levels] = state[:levels].select { |depth, _| depth < level }
        state[:levels][level] = text unless text.empty?
      end

      def prose_line(line)
        return "" if table_markup?(line) || service_line?(line)

        plain_inline(line.sub(/\A[:;*#]+\s*/, ""))
      end

      def table_markup?(line)
        line.match?(/\A\s*(\{\||\|\}|\|-|[|!])/)
      end

      # Category/Thể loại/interwiki lines and lines that are nothing but
      # service templates ({{PD-old}}, {{檢索|…}}) — apparatus, not text.
      def service_line?(line)
        stripped = line.strip
        stripped.match?(/\A\[\[[^\]|]*:[^\]]*\]\]\z/) ||
          (stripped.match?(/\A(\{\{[^{}]*\}\})+\z/) && !stripped.match?(INLINE_NOTE_TEMPLATES))
      end

      # -- parallel-poem mode ---------------------------------------------------------

      def poem_passages(body)
        poems = body.scan(%r{<poem>(.*?)</poem>}m).map { |(inner)| stanzas(inner) }
        raise Nabu::ParseError, "parallel-poem page has no <poem> block" if poems.empty? || poems[0].empty?

        originals = poems[0]
        phien_am = poems[1] || []
        if phien_am.size == originals.size
          passages = originals.zip(phien_am).map do |text, paired|
            Passage.new(text: text, section: nil, phien_am: paired)
          end
          [passages, nil]
        else
          passages = originals.map { |text| Passage.new(text: text, section: nil, phien_am: nil) }
          [passages, phien_am.empty? ? nil : phien_am.join("\n\n")]
        end
      end

      # Blank-line-separated stanzas; line edges trimmed, INTERNAL spacing
      # kept verbatim (the cáo's per-character spacing is canonical).
      def stanzas(poem)
        poem.split(/\n\s*\n/).filter_map do |stanza|
          lines = stanza.each_line.map { |line| plain_inline(line.chomp) }.reject(&:empty?)
          lines.empty? ? nil : lines.join("\n")
        end
      end

      # -- inline wikitext ----------------------------------------------------------

      # One line's wikitext flattened: interlinear notes to 【…】, other
      # templates dropped (two passes for one nesting level), piped links
      # to their label, quote markup unwrapped, leftover HTML tags dropped.
      def plain_inline(text)
        flat = text.dup
        2.times do
          flat.gsub!(INLINE_NOTE_TEMPLATES) { "【#{Regexp.last_match(1)}】" }
          flat.gsub!(/\{\{[^{}]*\}\}/, "")
        end
        flat.gsub!(%r{<sub>(.*?)</sub>}m) { "【#{Regexp.last_match(1)}】" }
        flat.gsub!(/\[\[[^\]|]*\|([^\]]*)\]\]/, '\1')
        flat.gsub!(/\[\[([^\]]*)\]\]/, '\1')
        flat.gsub!("''", "")
        flat.gsub!(%r{</?[a-zA-Z][^>]*>}, "")
        flat.strip
      end
    end
  end
end
