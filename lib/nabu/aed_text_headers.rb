# frozen_string_literal: true

require "nokogiri"

require_relative "normalize"

module Nabu
  # The AED per-text header reader: canonical/aed/files/<TLA-text-id>_hiero.xml
  # (13,949 stand-off files, fetched into the aed sparse cone for the
  # hieroglyph postings) open with a full TEI header that the TLA export
  # writes for EVERY text — the same text ids the AES corpus mints its
  # documents from (13,025 of 13,026 AES texts have a file; censused
  # 2026-10-18). This module is the ONE parser of that header; the AES
  # title pass (AesAedTitles) and the AES timeline extractor
  # (Store::TimelineBuilder::AesDates) both read through it, so a
  # cross-source join is spelled exactly once.
  #
  # == What a header carries (censused whole, 2026-10-18)
  #
  # - titleStmt/title on 13,948 files (one file has no header at all).
  #   1,265 are the editorial placeholders "〈TEXT〉" / "〈Text〉" /
  #   "〈Texte〉" — no title information, dropped. Other bracketed titles
  #   ("〈Stele des Nebanch (aus Abydos)〉", an editor-supplied name) are
  #   real titles and stay verbatim (NFC folds the U+2329/U+232A brackets
  #   to U+3008/U+3009 — the AES boundary rule).
  # - origDate: an earliest/latest pair (13,722 files), each a thesaurus
  #   label (105 distinct: rulers "Djedkare Asosi", dynasties "6. Dyn.",
  #   periods "Altes Reich", quarter-centuries "1. Viertel 3. Jhdt.
  #   v.Chr.") with signed notBefore/notAfter years ("-2421", zero-padded:
  #   read base-10). Five files carry the 0001/0001 placeholder pair
  #   (datingPoint ths:10000/-10000, empty labels) — not a dating, dropped.
  #   The years are ingested verbatim as historical years (the HGV axis
  #   doctrine); the grain is labeled by PRECISIONS below.
  # - origPlace with a TLA thesaurus ref (13,835 files, 621 distinct
  #   names, one ref per name except the sub-site "westliches Ufer" whose
  #   three refs disambiguate three west banks). The text's FIRST line is
  #   the place; later lines are prose notes (provenance stories, a tomb
  #   number) and are not a place name. Thesaurus nodes that name no site
  #   are dropped (NON_SITES).
  #
  # Read-only on canonical; an absent tree or file is nil (a clone without
  # the aed cone degrades to the AES-only coarse grain, honestly).
  class AedTextHeaders
    FILES_DIR = "files"
    SUFFIX = "_hiero.xml"
    HEADER_END = "</teiHeader>"
    HEADER_CHUNK = 1 << 14

    # The editorial "[text]" placeholders (post-NFC spelling).
    PLACEHOLDER_TITLES = ["〈TEXT〉", "〈Text〉", "〈Texte〉"].freeze

    # Thesaurus nodes that are categories or unknowns, not sites: the
    # find-spot root ("3 = Fundstellen"), the two unknown markers, and the
    # bare "Nekropolen" / "Siedlung" category nodes (one ref each across
    # 2,154 / 46 files — the category itself, never a particular site).
    NON_SITES = ["3 = Fundstellen", "(unbestimmt)", "(unbekannt)", "Nekropolen", "Siedlung"].freeze

    # The placeholder year both bounds carry on the undated files.
    PLACEHOLDER_YEAR = "0001"

    # Label grain, finest first; differing earliest/latest labels take the
    # coarser of the two.
    PRECISIONS = %w[reign century dynasty period].freeze

    Header = Data.define(:text_id, :title, :not_before, :not_after, :date_raw, :precision,
                         :place_name, :place_ref)

    # The grain of one thesaurus date label (class note). Word-bounded so
    # "Reichseinigung" and "Gesamtzeitraum" inside a ruler label stay reign.
    def self.precision_of(label)
      case label
      when /Dyn/ then "dynasty"
      when /Jhdt/ then "century"
      when /\bReich\b|zeit\b|Zeit\b|Makedonen|Ptolemäer/ then "period"
      else "reign"
      end
    end

    # +aed_dir+: the aed workdir (canonical/aed).
    def initialize(aed_dir:)
      @files_dir = File.join(aed_dir, FILES_DIR)
    end

    def path_for(text_id)
      File.join(@files_dir, "#{text_id}#{SUFFIX}")
    end

    # The Header for +text_id+, or nil when no file (or no header) exists.
    def header(text_id)
      path = path_for(text_id)
      return nil unless File.file?(path)

      slice = header_slice(path) or return nil
      doc = Nokogiri::XML(slice, &:recover)
      doc.remove_namespaces!
      build(text_id, doc)
    end

    private

    def build(text_id, doc)
      not_before, not_after, date_raw, precision = dating(doc)
      place_name, place_ref = place(doc)
      Header.new(text_id: text_id, title: title(doc), not_before: not_before, not_after: not_after,
                 date_raw: date_raw, precision: precision, place_name: place_name, place_ref: place_ref)
    end

    def title(doc)
      value = clean(doc.at_xpath("//titleStmt/title")&.text)
      value && !PLACEHOLDER_TITLES.include?(value) ? value : nil
    end

    def dating(doc)
      earliest = doc.at_xpath("//origDate/date[@type='earliest']")
      latest = doc.at_xpath("//origDate/date[@type='latest']")
      not_before = year(earliest&.[]("notBefore"))
      not_after = year(latest&.[]("notAfter"))
      return [nil, nil, nil, nil] if not_before.nil? && not_after.nil?

      labels = [earliest, latest].filter_map { |node| clean(node&.text) }.uniq
      return [nil, nil, nil, nil] if labels.empty?

      precision = labels.map { |label| self.class.precision_of(label) }
                        .max_by { |grain| PRECISIONS.index(grain) }
      [not_before, not_after, labels.join(" – "), precision]
    end

    def year(value)
      text = value.to_s.strip
      return nil if text.empty? || text == PLACEHOLDER_YEAR

      Integer(text, 10)
    rescue ArgumentError
      nil
    end

    def place(doc)
      node = doc.at_xpath("//origPlace") or return [nil, nil]
      name = clean(node.text.to_s.strip.lines.first)
      return [nil, nil] if name.nil? || NON_SITES.include?(name)

      ref = node["ref"].to_s.strip
      [name, ref.empty? ? nil : ref]
    end

    def clean(value)
      text = value.to_s.gsub(/[[:space:]]+/, " ").strip
      text.empty? ? nil : Normalize.nfc(text)
    end

    # Read up to </teiHeader> (chunked: the glyph runs that follow are
    # the postings builder's business, never parsed here).
    def header_slice(path)
      buffer = +""
      File.open(path, "rb") do |io|
        while (chunk = io.read(HEADER_CHUNK))
          buffer << chunk
          if (index = buffer.index(HEADER_END))
            return buffer[0, index + HEADER_END.length].force_encoding(Encoding::UTF_8)
          end
        end
      end
      nil
    end
  end
end
