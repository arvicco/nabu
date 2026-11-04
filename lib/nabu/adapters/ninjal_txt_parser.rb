# frozen_string_literal: true

require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # The ninjal-txt family: NINJAL's "Text Data Sets for Research on the
    # History of Japanese" transcription files (www2.ninjal.ac.jp/
    # textdb_dataset/<set>/txt/<stem>.txt) — one plain-text file per work
    # volume per layer. Every file is a title line, a 凡例 (transcription
    # rules) block between dashed dividers, the body, and a colophon after
    # a final divider (底本 the copy transcribed, 翻字担当者 the
    # transcribers, 更新履歴 the release history). Two body shapes, chosen
    # by the caller per set (censused 2026-11-04):
    #
    #   :paged  a "（page）" header line, then "n<TAB>text" lines numbered
    #           within the page (the original's own line breaks). Page labels
    #           are the print's page numbers, plus 扉 (title page) and 序/序N
    #           (unnumbered preface pages). amhk, amis.
    #   :cited  every line "PPP.LL<TAB>text" — page (3 digits, corrected
    #           "205[=206]", supplied "[434]", the unpaginated title page
    #           "[*001]", a column suffix "[445]a") and 2-digit line; a bare
    #           "///" line marks each page/column break (redundant with the
    #           citations, so not carried). cmhab.
    #
    # Encoding: UTF-8, with or without a BOM; line terminators vary per
    # file (CRLF, and bare CR in amhk-r-001) — all three are split here.
    # Invalid UTF-8, and any non-blank body line outside the shape, raise
    # Nabu::ParseError (both censused at zero over the four Kirishitan
    # files). Text is returned NFC-normalized, otherwise verbatim — the
    # editorial marks ([f], {…}«…», ■, [=…], ( ), [-]) are the
    # transcription's own and stay in.
    module NinjalTxtParser
      # +repeat+ counts earlier lines on the same page carrying the same
      # number (0 normally). Upstream mis-keys a few numbers — the Feiqe
      # prints 8.15, 119.13, 310.11 and 403.3 as a repeat of their
      # neighbour's (identically in both layers, censused 2026-11-04) — so
      # the number stays verbatim and the repeat's key takes a letter
      # ("8.1-b", the oncoj duplicate-id precedent): never a guessed number.
      Line = Data.define(:page, :line, :text, :repeat) do
        def initialize(page:, line:, text:, repeat: 0) = super

        def key = repeat.zero? ? "#{page}.#{line}" : "#{page}.#{line}-#{('b'.ord + repeat - 1).chr}"
      end

      Result = Data.define(:title, :lines, :base_text, :transcribers, :history)

      SHAPES = %i[paged cited].freeze
      DIVIDER = /\A-{20,}\s*\z/
      PAGE_HEADER = /\A（([^）]+)）\z/
      PAGED_LINE = /\A(\d+)\t(.*)\z/
      CITED_LINE = /\A(\S+)\.(\d\d)\t(.*)\z/
      BREAK = "///"

      module_function

      def parse(bytes, shape:, path:)
        raise ArgumentError, "unknown shape #{shape.inspect}" unless SHAPES.include?(shape)

        lines = decode(bytes, path: path)
        dividers = lines.each_index.select { |index| lines[index].match?(DIVIDER) }
        raise Nabu::ParseError, "#{path}: no colophon divider" if dividers.size < 2

        body = number_repeats(shape == :paged ? paged(lines, dividers, path) : cited(lines, dividers, path))
        raise Nabu::ParseError, "#{path}: no transcribed lines" if body.empty?

        colophon(lines[(dividers.last + 1)..], title: lines.find { |line| !line.strip.empty? }, body: body)
      end

      def decode(bytes, path:)
        SourceRead.utf8(bytes, label: "ninjal-txt: #{path}").delete_prefix("﻿").split(/\r\n|\r|\n/)
      end

      # The body sits between the rules block's closing divider (the second)
      # and the colophon's (the last).
      def paged(lines, dividers, path)
        page = nil
        lines[(dividers[1] + 1)...dividers.last].each_with_object([]) do |line, out|
          next if line.strip.empty?

          if (match = line.match(PAGE_HEADER))
            page = match[1]
          elsif page && (match = line.match(PAGED_LINE))
            out << Line.new(page: page, line: match[1], text: Normalize.nfc(match[2]))
          else
            raise Nabu::ParseError, "#{path}: unexpected body line #{line[0, 40].inspect}"
          end
        end
      end

      # The cited body runs from the first citation line to the last (the
      # rules block itself carries no TAB-joined citation).
      def cited(lines, dividers, path)
        first = lines.index { |line| line.match?(CITED_LINE) }
        last = lines.rindex { |line| line.match?(CITED_LINE) }
        return [] unless first && last && last < dividers.last

        lines[first..last].each_with_object([]) do |line, out|
          next if line.strip.empty? || line == BREAK

          match = line.match(CITED_LINE) or
            raise Nabu::ParseError, "#{path}: unexpected body line #{line[0, 40].inspect}"
          out << Line.new(page: match[1], line: match[2], text: Normalize.nfc(match[3]))
        end
      end

      def number_repeats(lines)
        seen = Hash.new(0)
        lines.map do |line|
          repeat = seen[[line.page, line.line]]
          seen[[line.page, line.line]] += 1
          repeat.zero? ? line : line.with(repeat: repeat)
        end
      end

      # 底本：… / 翻字担当者：… (names joined by 、 or ・ — a 、 list keeps the
      # katakana middle dots inside foreign names) / 更新履歴： then one
      # dated line each; anything after (the English echo) rides history.
      def colophon(tail, title:, body:)
        fields = tail.map(&:strip).reject(&:empty?).map { |line| Normalize.nfc(line) }
        base = fields.find { |line| line.start_with?("底本：") }&.delete_prefix("底本：")
        names = fields.find { |line| line.start_with?("翻字担当者：") }&.delete_prefix("翻字担当者：")
        history_at = fields.index("更新履歴：")
        Result.new(
          title: title && Normalize.nfc(title.delete_prefix("﻿").strip),
          lines: body, base_text: base,
          transcribers: names&.split(names.include?("、") ? "、" : "・")&.map(&:strip),
          history: history_at ? fields[(history_at + 1)..] : []
        )
      end
    end
  end
end
