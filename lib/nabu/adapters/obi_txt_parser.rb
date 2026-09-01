# frozen_string_literal: true

require_relative "../normalize"

module Nabu
  module Adapters
    # Parser family "obi-txt" (P92-3): one file of "A Structured Corpus of
    # Old Burmese Stone Inscriptions" (Zenodo 4321314) — one FACE of one
    # Bagan-period inscription, in the corpus's own structured plain-text
    # format (fixture-censused, uniform across volumes):
    #
    #   KEY: value              header lines (OBI CORPUS REF, INFORMATION
    #   …                       SOURCE, VOLUME, INSCRIPTION NUMBER, FACE,
    #   FOOTNOTES:              TITLE, DATE, DONOR, …)
    #   <n> <text ¤ translit>   footnote entries (editorial — dropped)
    #    INSCRIPTION:
    #   ၁⇥<Myanmar-script line>
    #   ¤ 1⇥<transliteration>
    #
    # Files are PAGE-based, and a page sometimes carries the START of the
    # NEXT inscription (fixture No36 runs into No37): an intra-file
    # heading "၃၇။ <title>" (mirrored by a "¤ 37|| …" line) opens a
    # SECTION — its lines mint "<section>.<n>" keys ("37.1"), the file's
    # own inscription keeps bare "<n>", and the section numbers ride
    # Record#sections for the adapter's census. "<pg>…</pg>" page
    # markers are milestones and drop.
    #
    # == Passages
    #
    # One passage per inscription line: text = the Myanmar-script Unicode
    # line (NFC; the corpus is verified Unicode, not Zawgyi), the paired
    # "¤"-prefixed transliteration riding annotations["translit"] — two
    # lanes, one passage (the aozora ruby-annotation shape). The line
    # number is the Burmese numeral converted to its Arabic form (၁ → "1").
    # Inline <ftn n</ftn> footnote markers are editorial and stripped from
    # both lanes. A wrapped physical line (rare) continues the open lane.
    # A file whose INSCRIPTION section yields zero lines quarantines.
    #
    # Bilingual header values ("TITLE: <Myanmar> ¤ <translit>") split on
    # the ¤ separator: the Myanmar half is the value, the romanization
    # rides a _translit twin.
    module ObiTxtParser
      Record = Data.define(:ref, :title, :title_translit, :source, :date,
                           :donor, :face, :lines, :sections)
      Line = Data.define(:n, :text, :translit)

      BURMESE_DIGITS = "၀၁၂၃၄၅၆၇၈၉"
      FTN_RE = %r{<ftn>?\s*\d+\s*</ftn>}
      MYANMAR_LINE_RE = /\A([#{BURMESE_DIGITS}]+)\t(.*)\z/
      HEADING_RE = /\A([#{BURMESE_DIGITS}]+)။(.*)\z/
      PG_RE = %r{\A\s*<pg>}
      TRANSLIT_LINE_RE = /\A¤\s*(\d+)?\t?(.*)\z/

      module_function

      def parse(path)
        header, body = split_sections(File.read(path, encoding: "UTF-8"))
        lines, sections = inscription_lines(body, path)
        raise Nabu::ParseError, "#{File.basename(path)}: no inscription lines" if lines.empty?

        title_my, title_tr = split_bilingual(header["TITLE"])
        Record.new(
          ref: header["OBI CORPUS REF"], title: title_my, title_translit: title_tr,
          source: header["INFORMATION SOURCE"], date: header["DATE"],
          donor: split_bilingual(header["DONOR"]).first, face: header["FACE"],
          lines: lines, sections: sections
        )
      end

      # Header KEY: value lines up to the INSCRIPTION marker; the FOOTNOTES
      # section's numbered entries are editorial notes, dropped.
      def split_sections(content)
        head, _, body = content.partition(/^\s*INSCRIPTION:\s*$/)
        raise Nabu::ParseError, "no INSCRIPTION section" if body.empty? && !head.match?(/\S/)

        header = {}
        head.each_line do |line|
          key, _, value = line.partition(":")
          next unless key.match?(/\A[A-Z][A-Z ]+\z/)

          header[key.strip] = clean(value)
        end
        [header, body]
      end

      def inscription_lines(body, path)
        lines = []
        sections = []
        section = nil
        open_lane = nil
        body.each_line do |raw|
          raw = raw.gsub(FTN_RE, "").rstrip
          next if raw.strip.empty? || raw.match?(PG_RE)

          if (m = raw.match(MYANMAR_LINE_RE))
            n = m[1].tr(BURMESE_DIGITS, "0123456789")
            lines << { n: [section, n].compact.join("."), text: +m[2], translit: +"" }
            open_lane = :text
          elsif (m = raw.match(HEADING_RE))
            section = m[1].tr(BURMESE_DIGITS, "0123456789")
            sections << section
            open_lane = :heading
          elsif raw.start_with?("¤")
            if open_lane == :heading
              open_lane = nil
            else
              raise Nabu::ParseError, "#{File.basename(path)}: transliteration before any line" if lines.empty?

              lines.last[:translit] << TRANSLIT_LINE_RE.match(raw)[2]
              open_lane = :translit
            end
          elsif open_lane && %i[text translit].include?(open_lane) && lines.any?
            lines.last[open_lane] << " #{raw.strip}"
          end
        end
        [lines.filter_map do |line|
          text = clean(line[:text])
          next if text.empty?

          Line.new(n: line[:n], text: text, translit: presence(clean(line[:translit])))
        end, sections]
      end

      def split_bilingual(value)
        return [nil, nil] if value.nil?

        my, _, tr = value.partition("¤")
        [presence(clean(my)), presence(clean(tr))]
      end

      def clean(text)
        Normalize.nfc(text.to_s.gsub(/\s+/, " ").strip)
      end

      def presence(value)
        value.nil? || value.empty? ? nil : value
      end
      private_class_method :presence
    end
  end
end
