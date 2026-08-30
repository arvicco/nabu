# frozen_string_literal: true

require "nokogiri"

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "seal-html" (P89-3): one text page of SEAL — Sources of
    # Early Akkadian Literature (seal.huji.ac.il; Streck & Wasserman), a
    # Drupal 8/9 node page per text. DOM-based: pages are ~100–250 KB
    # (capture census 2026-08-30), far under the >5 MB Reader rule.
    #
    # == Identity (the grant's own key)
    #
    # urn = urn:nabu:seal:<SEAL no.> — the page's own "SEAL no." <h4>, the
    # fixed citation number the grant names for scholarly reference (node
    # ids are NOT SEAL numbers; they ride metadata as the permanent URL).
    # Three cross-checks quarantine drift loudly: the filename's node id
    # against the page's canonical self-link; the passed urn against the
    # page's SEAL no.; a page WITHOUT a SEAL no. never mints.
    #
    # == Page anatomy (capture ground truth 2026-08-30, three fixtures)
    #
    # Metadata rides Drupal field divs (field--name-field-*): Texts
    # Hierarchy (Projects › SEAL › <genre group> › <period> › <composition>
    # — the period source; there is no standalone Period field), Genre /
    # Classification, Provenance, Collection, Tablet Siglum, Edition
    # (bibliography + pages), and the English Translation
    # (field--name-field-translation — document-level metadata in v1, no
    # sibling documents). The Vocabulary and Statistics tabs (per-word
    # lm/ts/me lemma attributes, sign counts) are deliberately OUT of v1 —
    # the transliteration text is the passage payload.
    #
    # == The transliteration: TWO censused shapes in field--name-field-text
    #
    # TABLE shape (nodes 1526/1830): <table class="_ts_tb"> — line rows
    # (<td class="_ts_ln">N</td><td>text</td>, numbering continuous across
    # sections), section rows (<td colspan="2">obv. / rev. / col. i</td>),
    # gap-note rows (digit-leading colspan text, "123–127 Lost.") and empty
    # spacer rows.
    #
    # PARAGRAPH shape (node 31252): <p> lines with a leading label token
    # ("5ʹ …]-iš-tim?"), labels RESTARTING per column; label-less
    # paragraphs are section headings ("col. i"); range labels
    # ("1ʹ–4ʹ traces") are editorial gap notes, not lines.
    #
    # == Passage = the transliteration LINE
    #
    #   urn = <document-urn>:<ordinal>   (urn:nabu:seal:1526:1)
    #
    # The ordinal is the dense 1-based document order — the ONE key that is
    # unique in both shapes (paragraph-shape labels restart per column, so
    # the label itself cannot key). The upstream label and its section ride
    # annotations verbatim: citation "obv. 3" / "rev. 12" / "col. i 5ʹ"
    # (section + label, exactly what the HTML gives), plus "line" and
    # "section". Gap notes are censused in document metadata "gap_notes";
    # rows the walk cannot place are counted, never silently dropped.
    # Language akk; NFC at the boundary (Nabu::Normalize.nfc).
    class SealHtmlParser
      URN_PREFIX = "urn:nabu:seal:"

      LANGUAGE = "akk"

      BASE_URL = "https://seal.huji.ac.il"

      SITE_TITLE_SUFFIX = " | Sources of Early Akkadian Literature"

      # A paragraph-shape line label: "5", "5ʹ" (U+02B9/U+2032/'), or a
      # range "1ʹ–4ʹ" (range = an editorial gap note, not a line).
      LINE_LABEL = /\A(\d+[ʹ′']*(?:\s*[–-]\s*\d+[ʹ′']*)?)\s+(.*)\z/m

      # One transliteration line as the walk collects it.
      Line = Data.define(:label, :section, :text)

      def parse(path, urn:)
        seal_no = expected_seal_no(urn)
        page = Nokogiri::HTML(read(path))
        node_id = check_node_identity!(page, path)
        check_seal_no!(page, seal_no, path)
        lines, walk_metadata = transliteration_lines(page, path)
        document = build_document(urn, path, page, node_id, walk_metadata)
        append_lines!(document, urn, lines)
        document
      end

      private

      def expected_seal_no(urn)
        unless urn.start_with?(URN_PREFIX)
          raise Nabu::ValidationError, "urn #{urn.inspect} does not carry the #{URN_PREFIX} prefix"
        end

        urn.delete_prefix(URN_PREFIX)
      end

      # Drupal serves UTF-8; a page that is not valid UTF-8 is drift.
      def read(path)
        body = File.read(path, encoding: Encoding::UTF_8)
        return body if body.valid_encoding?

        raise Nabu::ValidationError, "#{path}: not valid UTF-8 — the upstream encoding drifted"
      end

      # The page's canonical self-link carries its node id; drift between
      # the filename the crawl landed and the served page quarantines.
      def check_node_identity!(page, path)
        filename_id = File.basename(path)[/\Anode-(\d+)\.html\z/, 1] or
          raise Nabu::ValidationError, "#{path}: not a node-<id>.html record file"
        served = page.at_css("link[rel=canonical]")&.[]("href").to_s[%r{/node/(\d+)}, 1]
        return filename_id if served == filename_id

        raise Nabu::ValidationError,
              "page canonical link says node/#{served || 'none'}, expected node/#{filename_id} " \
              "(#{path}) — the crawl landed a different page under this id"
      end

      # The page's own "SEAL no." heading — the identity the urn claims.
      # A page without one never mints (quarantine, honestly).
      def check_seal_no!(page, expected, path)
        served = page_seal_no(page)
        if served.nil?
          raise Nabu::ValidationError,
                "no \"SEAL no.\" heading on the page (#{path}) — the identity field the grant " \
                "names is missing; quarantined, never minted from the node id"
        end
        return if served == expected

        raise Nabu::ValidationError,
              "page says SEAL no. #{served}, urn claims #{expected} (#{path})"
      end

      def page_seal_no(page)
        page.css("h4").filter_map { |h4| fold(h4.text)[/\ASEAL no\.\s*(\S+)/, 1] }.first
      end

      def build_document(urn, path, page, node_id, walk_metadata)
        Nabu::Document.new(
          urn: urn, language: LANGUAGE, canonical_path: path,
          title: title(page, path),
          metadata: metadata(page, node_id).merge(walk_metadata)
        )
      end

      def title(page, path)
        raw = page.at_css("title")&.text.to_s
        folded = fold(raw.sub(SITE_TITLE_SUFFIX, ""))
        return folded unless folded.empty?

        raise Nabu::ValidationError, "no page title (#{path}) — the page shape drifted"
      end

      def append_lines!(document, urn, lines)
        lines.each_with_index do |line, index|
          annotations = { "citation" => citation(line), "line" => line.label }
          annotations["section"] = line.section if line.section
          document << Nabu::Passage.new(
            urn: "#{urn}:#{index + 1}", language: LANGUAGE, text: line.text,
            annotations: annotations, sequence: index
          )
        end
      end

      # Exactly what the HTML gives: the section context + the printed
      # label ("obv. 3", "col. i 5ʹ"); a label with no section yet keeps
      # the bare "l. <label>" form.
      def citation(line)
        line.section ? "#{line.section} #{line.label}" : "l. #{line.label}"
      end

      # -- the transliteration field ---------------------------------------------

      def transliteration_lines(page, path)
        item = page.at_css("div.field--name-field-text .field--item") or
          raise Nabu::ValidationError, "no Text field (field--name-field-text) — every SEAL text " \
                                       "page carries a transliteration, so the page shape drifted (#{path})"
        walk = Walk.new
        table = item.at_css("table._ts_tb")
        table ? walk_table(table, walk) : walk_paragraphs(item, walk)
        lines = walk.lines
        if lines.empty?
          raise Nabu::ValidationError,
                "zero transliteration lines in the Text field — the page shape drifted (#{path})"
        end

        [lines, walk.metadata]
      end

      # The table shape: 2-td rows with a _ts_ln cell are lines; single-td
      # (colspan) rows are section headings, gap notes (digit-leading,
      # "123–127 Lost.") or spacers; anything else is censused, never
      # silently dropped.
      def walk_table(table, walk)
        table.xpath(".//tr").each do |row|
          tds = row.xpath("./td")
          if tds.size == 2 && tds.first.classes.include?("_ts_ln")
            walk.line!(label: fold(tds.first.text), text: fold(tds.last.text))
          elsif tds.size == 1
            walk.heading!(fold(tds.first.text))
          else
            walk.unplaced!
          end
        end
      end

      # The paragraph shape: label-led paragraphs are lines (a RANGE label
      # is an editorial gap note); label-less paragraphs are section
      # headings; empty paragraphs are spacers.
      def walk_paragraphs(item, walk)
        item.css("p").each do |paragraph|
          text = fold(paragraph.text)
          next if text.empty?

          match = LINE_LABEL.match(text)
          if match.nil?
            walk.heading!(text)
          elsif match[1].match?(/[–-]/)
            walk.gap_note!(text)
          else
            walk.line!(label: match[1], text: fold(match[2]))
          end
        end
      end

      # Collects lines + the honesty census (gap notes verbatim, counted
      # empty lines and unplaced rows) that rides document metadata.
      class Walk
        attr_reader :lines

        def initialize
          @lines = []
          @section = nil
          @gap_notes = []
          @empty = 0
          @unplaced = 0
        end

        def line!(label:, text:)
          if text.empty?
            @empty += 1
          else
            @lines << Line.new(label: label, section: @section, text: text)
          end
        end

        # A single-td/label-less row: empty → spacer; digit-leading → an
        # editorial gap note ("123–127 Lost."); else a section heading.
        def heading!(text)
          return if text.empty?

          if text.match?(/\A\d/)
            gap_note!(text)
          else
            @section = text
          end
        end

        def gap_note!(text)
          @gap_notes << text
        end

        def unplaced!
          @unplaced += 1
        end

        def metadata
          census = {}
          census["gap_notes"] = @gap_notes unless @gap_notes.empty?
          census["empty_lines"] = @empty if @empty.positive?
          census["unplaced_rows"] = @unplaced if @unplaced.positive?
          census
        end
      end

      # -- metadata ---------------------------------------------------------------

      def metadata(page, node_id)
        metadata = {
          "seal_number" => page_seal_no(page),
          "permanent_url" => "#{BASE_URL}/node/#{node_id}",
          "citation" => Seal::CITATION
        }
        metadata.merge!(hierarchy_fields(page))
        metadata.merge!(summary_fields(page))
        siglum = field_item_text(page, "field-tablet-siglum")
        metadata["tablet_siglum"] = siglum if siglum
        edition = edition_text(page)
        metadata["edition"] = edition if edition
        translation = translation_text(page)
        metadata["translation_en"] = translation if translation
        metadata
      end

      # Texts Hierarchy: Projects › SEAL › <genre group> › <period> ›
      # <composition>. The tail after SEAL rides verbatim; the period is
      # its second element when present (there is no standalone Period
      # field — capture ground truth 2026-08-30), honestly absent otherwise.
      def hierarchy_fields(page)
        crumbs = page.css("div.field--name-field-texts-hierarchy li a").map { |a| fold(a.text) }
        seal_at = crumbs.index("SEAL")
        tail = seal_at ? crumbs[(seal_at + 1)..] : crumbs
        fields = {}
        fields["texts_hierarchy"] = tail unless tail.empty?
        fields["period"] = tail[1] if tail.size >= 2
        fields
      end

      # The paragraph-formatter fields (Genre / Provenance / Collection):
      # their summary-content spans, joined.
      def summary_fields(page)
        fields = {}
        genre = summary_texts(page, "field--name-field__genre-classification").join(", ")
        fields["genre"] = genre unless genre.empty?
        provenance = summary_texts(page, "field--name-field-provenance").join("; ")
        fields["provenance"] = provenance unless provenance.empty?
        collection = summary_texts(page, "field--name-field-collections").join("; ")
        fields["collection"] = collection unless collection.empty?
        fields
      end

      def summary_texts(page, field_class)
        page.css("div.#{field_class} span.summary-content")
            .map { |span| fold(span.text) }.reject(&:empty?)
      end

      def field_item_text(page, name)
        text = fold(page.at_css("div.field--name-#{name} .field--item")&.text.to_s)
        text.empty? ? nil : text
      end

      # "George 2003, 248–251" — bibliography reference + page range per
      # edition item, multiple editions joined with "; ".
      def edition_text(page)
        items = page.css("div.field--name-field-edition > .field--items > .field--item").map do |item|
          reference = fold(item.at_css(".field--name-field-bibliography")&.text.to_s)
          pages = fold(item.at_css(".field--name-field-pages")&.text.to_s)
          [reference, pages].reject(&:empty?).join(", ")
        end
        joined = items.reject(&:empty?).join("; ")
        joined.empty? ? nil : joined
      end

      # The upstream English translation, plain text one line per <p> —
      # document-level metadata in v1 (no sibling documents; the numbered
      # prose keeps its own line labels verbatim).
      def translation_text(page)
        item = page.at_css("div.field--name-field-translation .field--item") or return nil
        lines = item.css("p").map { |paragraph| fold(paragraph.text) }.reject(&:empty?)
        lines = [fold(item.text)].reject(&:empty?) if lines.empty?
        lines.empty? ? nil : lines.join("\n")
      end

      # nbsp → space, whitespace folded, NFC at the boundary.
      def fold(text)
        Nabu::Normalize.nfc(text.tr(" ", " ").gsub(/[[:space:]]+/, " ").strip)
      end
    end
  end
end
