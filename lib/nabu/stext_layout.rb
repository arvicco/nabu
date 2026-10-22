# frozen_string_literal: true

require "nokogiri"
require_relative "errors"
require_relative "shell"

module Nabu
  # mutool's structured-text layer (`mutool draw -F stext`) read back as
  # POSITIONED, STYLED visual lines — the layout half of a PDF dictionary
  # segmentation (first consumer: Nabu::WilkensOui).
  #
  # Plain `-F txt` (Nabu::PdfText) loses exactly what dictionary segmentation
  # needs: which glyphs are bold or italic, where a line starts (margin vs
  # hanging indent), and which column it sits in. stext keeps a bbox, font
  # and flags per glyph. Two mutool habits are undone here:
  #
  # * justified lines arrive as several stext <line>s on one baseline (one
  #   per stretched word gap) — fragments of one column sharing a baseline
  #   band are merged back into the printed line, a space restored where a
  #   gap separated them;
  # * Word's synthetic bold is not a bold FONT: the glyphs are drawn filled
  #   AND stroked (char flags bit 32), so bold = stroked, bold-flagged, or a
  #   Bold-named font.
  #
  # Columns: a two-column page splits at half its width; lines come back
  # left column top-to-bottom, then right column (reading order). The
  # printed folio — a lone number in the bottom band — is lifted out of the
  # text flow onto Page#folio.
  module StextLayout
    # Extraction failure (mutool missing, nonzero exit).
    class Error < Nabu::Error; end

    Glyph = Data.define(:char, :x0, :x1, :bold, :italic, :small)

    Line = Data.define(:column, :x0, :x1, :y, :glyphs) do
      def text = glyphs.map(&:char).join
    end

    Page = Data.define(:width, :height, :folio, :lines)

    STROKED = 32
    BOLD = 8
    # Baseline band within which fragments are one printed line (the body
    # leading is ~10.5 pt; subscripts sit ~2 pt off the baseline).
    BASELINE_BAND = 3.5
    # A glyph this much smaller than the page's dominant size is a sub/superscript.
    SMALL_RATIO = 0.8
    # The folio sits in this bottom band (points from the page foot).
    FOLIO_BAND = 45.0

    module_function

    # The stext XML for +path+ (optionally a page range like "17-36"), via
    # mutool through the house shell boundary. +runner+ is the command seam.
    def extract(path, pages: nil, runner: Shell)
      argv = ["mutool", "draw", "-F", "stext", "-o", "-", path]
      argv << pages.to_s if pages
      runner.run(*argv)
    rescue Shell::Error => e
      raise Error, "mutool stext extraction failed for #{path} (#{e.message})"
    end

    # Every <page> of +xml+ as a Page.
    def pages(xml)
      Nokogiri::XML(xml).xpath("//page").map { |node| page(node) }
    end

    def page(node)
      width = node["width"].to_f
      height = node["height"].to_f
      frags = fragments(node)
      dominant = dominant_size(frags)
      folio = nil
      body = frags.reject do |f|
        next false unless f[:y0] > height - FOLIO_BAND

        text = f[:chars].map { _1[:c] }.join.strip
        folio = text.to_i if text.match?(/\A\d+\z/)
        true
      end
      Page.new(width: width, height: height, folio: folio, lines: visual_lines(body, width: width, dominant: dominant))
    end

    def fragments(node)
      node.xpath(".//line").filter_map do |line|
        chars = line.xpath("./font").flat_map do |font|
          name = font["name"].to_s
          size = font["size"].to_f
          font.xpath("./char").map do |c|
            quad = c["quad"].split.map(&:to_f)
            flags = c["flags"].to_i
            { c: c["c"], x0: quad[0], x1: quad[2], size: size,
              bold: flags.anybits?(STROKED | BOLD) || name.include?("Bold"),
              italic: name.match?(/Italic|Oblique/) }
          end
        end
        next if chars.all? { _1[:c].strip.empty? }

        x0, y0, x1, y1 = line["bbox"].split.map(&:to_f)
        { x0: x0, y0: y0, x1: x1, y1: y1, chars: chars }
      end
    end

    def dominant_size(frags)
      sizes = frags.flat_map { |f| f[:chars].map { _1[:size] } }
      sizes.tally.max_by { |_, n| n }&.first || 0.0
    end

    def visual_lines(frags, width:, dominant:)
      %i[left right].flat_map do |column|
        mine = frags.select { |f| (f[:x0] < width / 2) == (column == :left) }
        baseline_groups(mine).filter_map { |group| merge(group, column: column, dominant: dominant) }
      end
    end

    def baseline_groups(frags)
      frags.sort_by { _1[:y1] }.each_with_object([]) do |f, groups|
        if groups.any? && (f[:y1] - groups.last.first[:y1]).abs < BASELINE_BAND
          groups.last << f
        else
          groups << [f]
        end
      end
    end

    def merge(group, column:, dominant:)
      frags = group.sort_by { _1[:x0] }
      glyphs = []
      frags.each_with_index do |f, i|
        if i.positive? && glyphs.any? && !glyphs.last.char.match?(/\s/) && !f[:chars].first[:c].match?(/\s/) &&
           f[:x0] - frags[i - 1][:x1] > 1.0
          glyphs << Glyph.new(char: " ", x0: frags[i - 1][:x1], x1: f[:x0], bold: false, italic: false, small: false)
        end
        f[:chars].each do |c|
          glyphs << Glyph.new(char: c[:c], x0: c[:x0], x1: c[:x1], bold: c[:bold], italic: c[:italic],
                              small: c[:size] < dominant * SMALL_RATIO)
        end
      end
      glyphs.shift while glyphs.any? && glyphs.first.char.strip.empty?
      return nil if glyphs.empty?

      Line.new(column: column, x0: glyphs.first.x0, x1: glyphs.reverse.find { !_1.char.strip.empty? }.x1,
               y: frags.first[:y1], glyphs: glyphs)
    end
  end
end
