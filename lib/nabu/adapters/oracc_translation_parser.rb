# frozen_string_literal: true

require "json"
require "nokogiri"

module Nabu
  module Adapters
    # Parser for one ORACC per-text rendered-HTML fragment (P13-4) — the
    # aligned English translation of a tablet, as an ordinary Document in the
    # P7-4 sibling shape. Composed by the Oracc adapter next to
    # OraccJsonParser; individually tested like every family.
    #
    # == Why HTML (the honest acquisition record, P13-4 Phase A)
    #
    # ORACC's running translations live in NO public bulk artifact: the JSON
    # zips carry none (P9-5a), the oracc/catf GitHub repo is C-ATF
    # transliteration-only (0 `#tr` lines), and the per-text .atf/.xtf
    # endpoints are soft-404s. The one public machine-readable carrier is the
    # official per-text fragment at `/<project>/<textid>/html` (served with
    # `access-control-allow-origin: *`), where each translation UNIT — the
    # rendered form of an ATF `@translation labeled` block — anchors at its
    # first transliteration row.
    #
    # == Alignment: shared node refs, then the tablet's own labels
    #
    # A prose unit renders as `<td class="t1 xtr" data-tlit-id="P224395.5">`;
    # that ref is the SAME id the sibling corpusjson's `line-start` d-node
    # carries in its `ref` field, whose `label` ("o 4") is what the tablet
    # adapter minted its passage suffix from ("o.4", spaces → dots, FROZEN).
    # So the unit's passage urn is `<tablet-urn>-en:<label suffix>` — a suffix
    # that exists in the tablet by construction, which is exactly what
    # Query::Parallel's span-grouping needs: the anchor owns tablet lines up
    # to the next anchor, a multi-line unit renders as a :block, a 1:1 unit
    # as a :pair (the card-cited-Homer model, P8-1b).
    #
    # == Extraction rules (all markup-based, no prose regexes)
    #
    # - Unit prose = the text of the cell's `span.cell` descendants,
    #   whitespace-collapsed, NFC. Editorial marks ([resto]rations, (glosses))
    #   survive verbatim — they are part of the translation as published.
    # - The leading print marker ("(1)", "(o 1)") renders in its own
    #   `span.xtr-label` element and is alignment metadata (the citation
    #   carries it now) — excluded by element, never by pattern.
    # - A cell with NO `span.cell` prose is a state notice ("(Break)",
    #   rulings — the rendered `$`-lines) and is skipped by rule.
    # - A PROSE cell anchored at a row that is not a line-start (seen only
    #   doctored so far; upstream anchors state notices there) reattaches to
    #   the next line-start row in row order — prose is never dropped
    #   silently; a unit with no line-start anywhere after it is counted out
    #   loud in the ParseError below.
    # - Two units resolving to one label JOIN in cell order (passage urns
    #   must stay unique; consecutive prose under one anchor is what a reader
    #   wants anyway).
    #
    # == Identity and license
    #
    # urn = urn:nabu:oracc:<project ("/"→"-")>:<textid>-en, minted from the
    # sibling corpusjson's own project/textid fields and cross-checked against
    # the caller (the OraccJsonParser contract). Every passage is language
    # "eng". The Document carries license_override "attribution": the prose
    # is the SAAo/ORACC project content layer ("Content released under a CC
    # BY-SA 3.0 license" — project footer), NOT the CC0 that attaches to the
    # JSON build files (P13-4 Phase A license evidence); the P10-4 override
    # labels it honestly while the oracc source stays "open".
    class OraccTranslationParser
      LANGUAGE = "eng"
      LICENSE_OVERRIDE = "attribution"

      # +source+ is the fragment's path; +corpusjson_path+ the sibling tablet
      # file (ref → label). Signature family of the sibling parsers.
      def parse(source, urn:, corpusjson_path:, title: nil, canonical_path: nil)
        path = canonical_path || source
        labels = line_labels(corpusjson_path, urn: urn)
        units = extract_units(File.read(source), path: path, labels: labels)
        build_document(units, urn: urn, title: title, path: path)
      end

      private

      # ref ("P224395.5") → label ("o 4") for every line-start d-node, plus
      # the identity cross-check: the corpusjson's own project/textid must
      # mint the caller's urn (minus nothing — the -en suffix is ours).
      def line_labels(corpusjson_path, urn:)
        data = read_json(corpusjson_path)
        check_identity!(data, path: corpusjson_path, urn: urn)
        labels = {}
        walk_line_starts(data["cdl"]) do |node|
          ref = node["ref"].to_s
          label = node["label"].to_s
          labels[ref] = label unless ref.empty? || label.empty?
        end
        labels
      end

      def read_json(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ParseError, "#{path}: malformed ORACC JSON: #{e.message}"
      end

      def check_identity!(data, path:, urn:)
        project = data["project"].to_s
        textid = data["textid"].to_s
        if project.empty? || textid.empty?
          raise ParseError, "#{path}: missing project/textid — not an ORACC corpus file"
        end

        minted = "urn:nabu:oracc:#{project.tr('/', '-')}:#{textid}-en"
        return if minted == urn

        raise ParseError, "#{path}: urn mismatch: caller says #{urn.inspect}, " \
                          "project/textid mint #{minted.inspect}"
      end

      def walk_line_starts(nodes, &block)
        Array(nodes).each do |node|
          next unless node.is_a?(Hash)

          yield node if node["node"] == "d" && node["type"] == "line-start"
          walk_line_starts(node["cdl"], &block)
        end
      end

      # One prose unit: the label suffix it anchors at + its extracted text.
      Unit = Data.define(:label, :text)
      private_constant :Unit

      def extract_units(html, path:, labels:)
        fragment = Nokogiri::HTML(html)
        cells = fragment.css("td.xtr")
        if cells.empty?
          raise DocumentSkipped.new("#{path}: no translation cells in fragment",
                                    reason: "no translation units")
        end

        row_ids = fragment.css("tr[id]").map { |row| row["id"] }
        cells.filter_map { |cell| unit_for(cell, labels: labels, row_ids: row_ids, path: path) }
      end

      # nil for state-notice cells (no span.cell prose) — skipped by rule.
      def unit_for(cell, labels:, row_ids:, path:)
        text = Normalize.nfc(cell.css("span.cell").map(&:text).join(" ").gsub(/\s+/, " ").strip)
        return nil if text.empty?

        label = anchor_label(cell["data-tlit-id"].to_s, labels: labels, row_ids: row_ids)
        if label.nil?
          raise ParseError, "#{path}: prose unit anchored at #{cell['data-tlit-id'].inspect} " \
                            "resolves to no line-start row — prose would be dropped"
        end

        Unit.new(label: label, text: text)
      end

      # The anchor row's label; a non-line-start anchor reattaches to the
      # next line-start row in row order (see class note). nil when none.
      def anchor_label(ref, labels:, row_ids:)
        return labels[ref] if labels.key?(ref)

        position = row_ids.index(ref)
        return nil if position.nil?

        row_ids[position..].filter_map { |row_id| labels[row_id] }.first
      end

      def build_document(units, urn:, title:, path:)
        document = Document.new(
          urn: urn, language: LANGUAGE, title: title, canonical_path: path,
          license_override: LICENSE_OVERRIDE
        )
        joined = units.each_with_object({}) do |unit, acc|
          acc[unit.label] = acc.key?(unit.label) ? "#{acc[unit.label]} #{unit.text}" : unit.text
        end
        joined.each_with_index do |(label, text), sequence|
          document << Passage.new(
            urn: "#{urn}:#{Normalize.nfc(label).tr(' ', '.')}",
            language: LANGUAGE, text: text, sequence: sequence
          )
        end
        document
      rescue ValidationError => e
        raise ParseError, "#{path}: #{e.message}"
      end
    end
  end
end
