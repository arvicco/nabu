# frozen_string_literal: true

require "nokogiri"
require_relative "errors"
require_relative "zip_reader"

module Nabu
  # Minimal in-house xlsx SHEET reader (P77-r6, №R-30): an .xlsx is a ZIP
  # of XML parts, so this is Nabu::ZipReader (P39-3 — the ruling's "no gem
  # in the budget reads zip" premise was stale) + Nokogiri, nothing new in
  # the dependency budget.
  #
  # Deliberately dumb: every cell comes back as a STRING (or nil for a
  # skipped column), shared strings resolved, rows padded by the cell
  # reference so each value sits at its header's index. No types, no
  # styles, no formula evaluation, no date-serial decoding — the OSTA
  # works tables carry their dates as text ("1252 a quo"), and a works
  # TABLE is all this reader exists for. Anything fancier belongs to an
  # office suite, not an ingester.
  module Xlsx
    class Error < Nabu::Error; end

    WORKBOOK = "xl/workbook.xml"
    RELS = "xl/_rels/workbook.xml.rels"
    SHARED_STRINGS = "xl/sharedStrings.xml"

    module_function

    # The sheet's rows as arrays of strings/nils, in file order. +sheet+
    # names a worksheet (workbook names, e.g. "tabla obras"); nil takes
    # the workbook's first sheet.
    def rows(path, sheet: nil)
      archive = open_archive(path)
      strings = shared_strings(archive)
      parse_rows(sheet_xml(archive, path, sheet), strings)
    end

    def open_archive(path)
      Nabu::ZipReader.new(File.binread(path))
    rescue Nabu::ZipReader::Error, SystemCallError => e
      raise Error, "#{path}: not a readable xlsx (#{e.message})"
    end

    def member(archive, name)
      entry = archive.entries.find { |candidate| candidate.name == name }
      entry && archive.extract(entry)
    end

    def shared_strings(archive)
      xml = member(archive, SHARED_STRINGS) or return []
      Nokogiri::XML(xml).remove_namespaces!.xpath("//si").map do |si|
        si.xpath(".//t").map(&:text).join
      end
    end

    # Resolve the requested sheet name through workbook.xml + its rels —
    # sheet order in workbook.xml is the authoritative first-sheet rule.
    def sheet_xml(archive, path, sheet)
      workbook = member(archive, WORKBOOK) or raise Error, "#{path}: no workbook part — not an xlsx"
      sheets = Nokogiri::XML(workbook).remove_namespaces!.xpath("//sheets/sheet")
      raise Error, "#{path}: workbook lists no sheets" if sheets.empty?

      chosen = sheet.nil? ? sheets.first : sheets.find { |node| node["name"] == sheet }
      unless chosen
        raise Error, "#{path}: no sheet named #{sheet.inspect} " \
                     "(workbook holds: #{sheets.map { |node| node['name'] }.join(', ')})"
      end
      target = relationship_target(archive, path, chosen["id"])
      member(archive, target) or raise Error, "#{path}: missing worksheet part #{target}"
    end

    def relationship_target(archive, path, rel_id)
      rels = member(archive, RELS) or raise Error, "#{path}: no workbook relationships part"
      node = Nokogiri::XML(rels).remove_namespaces!
                     .xpath("//Relationship").find { |rel| rel["Id"] == rel_id }
      raise Error, "#{path}: workbook relationship #{rel_id.inspect} missing" unless node

      "xl/#{node['Target'].delete_prefix('/xl/').delete_prefix('./')}"
    end

    def parse_rows(xml, strings)
      Nokogiri::XML(xml).remove_namespaces!.xpath("//sheetData/row").map do |row|
        cells = []
        row.xpath("c").each_with_index do |cell, position|
          index = column_index(cell["r"]) || position
          cells[index] = cell_value(cell, strings)
        end
        cells
      end
    end

    # "A" → 0, "W" → 22, "AA" → 26. A cell without a reference falls back
    # to its position (handled by the caller).
    def column_index(ref)
      letters = ref.to_s[/\A[A-Z]+/] or return nil
      letters.each_char.reduce(0) { |acc, char| (acc * 26) + (char.ord - 64) } - 1
    end

    def cell_value(cell, strings)
      case cell["t"]
      when "s" then strings[cell.at_xpath("v").text.to_i]
      when "inlineStr" then cell.xpath(".//t").map(&:text).join
      else cell.at_xpath("v")&.text
      end
    end
  end
end
