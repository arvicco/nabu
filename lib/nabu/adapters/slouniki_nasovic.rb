# frozen_string_literal: true

require "nokogiri"
require_relative "../normalize"

module Nabu
  module Adapters
    # Насовіч's dictionary (P117, 02-sources row 253): I. I. Nosovič
    # (Іван Насовіч, 1788–1877), «Словарь бѣлорусскаго нарѣчія» (СПб.:
    # Imperial Academy of Sciences, 1870) — the founding dictionary of
    # Belarusian, ~35k entries of the 19th-c. vernacular glossed in
    # Russian with proverb- and folk-speech examples. The library's FIRST
    # Belarusian shelf; dictionary-shaped (the gpc/dillmann molds).
    #
    # == Upstream (github.com/Belarus/Slouniki-Nasovic, census 2026-10-11)
    #
    # The Belarusian dictionary-digitization volunteers' repo behind the
    # slounik web edition: data/NNNNN.xml — ONE ARTICLE PER FILE, 35,159
    # files (ids 00007–35252, gaps upstream's), keyed in their SlounikPlus
    # editor against data/article.xsd:
    #
    #   <suc>       the headword in modern Belarusian spelling (editors')
    #   <synonyms>  modern-Belarusian equivalents/search keys (editors')
    #   <comment>   an editor's proofreading note (537 files, 481 non-empty)
    #   <rtf>       the editor's base64 rich-text source blob — formatting
    #               only, the same text as zah/tlum; NOT ingested
    #   <zah>       the 1870 article head, verbatim: headword with the
    #               print's stress mark as U+00B4 "´" after the vowel,
    #               grammar, cross-references in {braces} (the editor's
    #               markup for the print's italics/references)
    #   <tlum>      a sense: optional <gram>, <desc> (the Russian gloss),
    #               any number of <ex> (examples, proverbs)
    #               — 41,466 senses; 2,931 articles have none (pure
    #               "см. {…}" cross-references)
    #
    # == Entry shape
    #
    # entry_id = the file stem ("00873" — upstream's own article number);
    # headword = the zah head up to its first comma (or the whole head,
    # trailing period dropped — 164 comma-less heads like "АЙ."), the 1870
    # spelling verbatim, stress marks and all; headword_folded = the search
    # form of that head with the "´" stress marks removed (they are
    # spacing characters the generic fold would keep); gloss = the first
    # sense's Russian desc (nil for a cross-reference — honest); body =
    # the full head, the numbered senses with their examples, then the
    # editors' layer labeled as such (modern spelling, equivalents,
    # proofreading note) — every upstream field but the rtf blob.
    #
    # == License
    #
    # "Public domain." — the repo's own description (no LICENSE file);
    # the 1870 text (Nosovič †1877) is PD by age, and the editors declare
    # their keying PD. The README's ISBN 978-985-458-312-9 names the
    # print edition of the project. → open; credit the volunteers.
    #
    # == Lect
    #
    # be — the registry anchor (nabu-lects: be "Belarusian", parent orv).
    # 19th-c. Belarusian; no stage is minted for it and none is claimed.
    class SlounikiNasovic < Nabu::Adapter
      REPO_URL = "https://github.com/Belarus/Slouniki-Nasovic"
      SPARSE_PATHS = ["data/*.xml", "data/article.xsd", "README.md"].freeze

      DICTIONARY_SLUG = "nasovic"
      LANGUAGE = "be"
      TITLE = "Насовіч, Словарь бѣлорусскаго нарѣчія (СПб., 1870)"
      STRESS = "´"

      MANIFEST = Nabu::SourceManifest.new(
        id: "slouniki-nasovic",
        name: "Насовіч — Словарь бѣлорусскаго нарѣчія (1870), Slouniki digitization",
        license: "Public domain — the repo's own declaration (github.com/Belarus/Slouniki-Nasovic " \
                 "description: \"Public domain.\", verified 2026-10-11; no LICENSE file). The 1870 " \
                 "text is PD by age (I. I. Nosovič †1877); the keying is declared PD by its editors",
        license_class: "open",
        upstream_url: REPO_URL,
        parser_family: "slouniki-xml",
        credit: "I. I. Nosovič (Насовіч), Словарь бѣлорусскаго нарѣчія, СПб. 1870 — digitized by the " \
                "Belarus/Slouniki volunteers (github.com/Belarus/Slouniki-Nasovic)"
      )

      def self.manifest = MANIFEST

      def self.content_kind = :dictionary

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "data", "*.xml")).each do |path|
          stem = File.basename(path, ".xml")
          next unless stem.match?(/\A\d+\z/)

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{stem}",
                                      path: File.expand_path(path), metadata: { "dictionary" => DICTIONARY_SLUG })
        end
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(slug: DICTIONARY_SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        document << build_entry(File.basename(document_ref.path, ".xml"), read_root(document_ref.path))
        document
      rescue Nabu::ValidationError, Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "slouniki-nasovic: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force, sparse: SPARSE_PATHS)
      end

      private

      def repo_url = REPO_URL

      def read_root(path)
        root = Nokogiri::XML(File.read(path, encoding: "UTF-8"), &:strict).root
        raise Nabu::ParseError, "slouniki-nasovic: #{path}: root is not <root>" unless root&.name == "root"

        root
      end

      def build_entry(stem, root)
        head = field(root, "zah") or raise Nabu::ParseError, "slouniki-nasovic: #{stem}: no <zah> head"
        headword = headword_of(head)
        Nabu::DictionaryEntry.new(
          entry_id: stem, key_raw: head, language: LANGUAGE, headword: headword,
          headword_folded: Normalize.search_form(headword.delete(STRESS), language: LANGUAGE),
          gloss: root.at_xpath("tlum")&.then { |sense| field(sense, "desc") },
          body: body(root, head)
        )
      end

      def headword_of(head)
        word = head.split(",", 2).first.strip.sub(/\.\z/, "").strip
        raise Nabu::ParseError, "slouniki-nasovic: empty headword in #{head.inspect}" if word.empty?

        word
      end

      def body(root, head)
        lines = [head]
        root.xpath("tlum").each_with_index do |sense, index|
          gram = field(sense, "gram")
          desc = field(sense, "desc")
          lines << "#{index + 1}. #{[gram && "(#{gram})", desc].compact.join(' ')}"
          sense.xpath("ex").each { |example| lines << "   — #{squish(example.text)}" }
        end
        { "comment" => "Заўвага рэдактара", "suc" => "Сучасны правапіс", "synonyms" => "Адпаведнікі" }
          .each do |name, label|
            value = field(root, name)
            lines << "[#{label}: #{value}]" if value
          end
        Normalize.nfc(lines.join("\n"))
      end

      def field(node, name)
        value = node.at_xpath(name)&.text
        value = squish(value) if value
        value.nil? || value.empty? ? nil : Normalize.nfc(value)
      end

      def squish(text) = text.to_s.gsub(/[[:space:]]+/, " ").strip
    end
  end
end
