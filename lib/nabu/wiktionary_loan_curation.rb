# frozen_string_literal: true

require_relative "normalize"

module Nabu
  # Reads English Wiktionary's "Latin terms borrowed/derived from X"
  # category membership and each member's own etymology into curated loan
  # rows — the recipe behind config/sabellic_loans.yml, made replayable for
  # config/etruscan_loans.yml. Pure: it takes the MediaWiki API's parsed
  # JSON (list=categorymembers for both categories; prop=revisions with
  # rvslots=main content for the members) and never touches the network —
  # the fetch is a deliberate curation act, the config the artifact.
  #
  # == Rules (each one censused on the 2026-10-22 Etruscan curation)
  #
  # - Members: main-namespace pages only. A Reconstruction: page or a
  #   subcategory in the member list is excluded and named (+excluded+).
  #   A split-page title ("a/languages A to L") rows under its lemma.
  # - Relation: "borrowed" when the page sits in the borrowed category,
  #   else "derived" (the superset). Borrowed wins every overlap; the
  #   overlap is counted (+overlap+).
  # - Etymon: read from the page's ==Latin== section, its Etymology
  #   subsections only, HTML comments removed. Candidates are the
  #   {{bor|der|bor+|der+|lbor|uder|bor-lite|der-lite|la|<code>|FORM}}
  #   templates (named parameters may sit anywhere; tr= is the
  #   transliteration) and the {{ety|la|…}} template's "<code>:FORM"
  #   tokens (a <tr:…> modifier is the transliteration). The FIRST
  #   candidate stating a form wins; mentions ({{m}}, {{cog}}, {{desc}})
  #   are cognates and never promoted.
  # - No etymon, declared: "unstated" when the templates name the source
  #   language but cite no form ("-", empty, or only a commented-out
  #   form); "no-template" when the Latin etymology carries no template
  #   for the source language at all (membership inherited through
  #   another word's etymology — titulo from titulus).
  class WiktionaryLoanCuration
    Row = Data.define(:latin, :relation, :etymon, :translit, :no_etymon, :page)
    Result = Data.define(:rows, :excluded, :overlap)

    TEMPLATES = %w[bor der bor+ der+ lbor uder bor-lite der-lite].freeze
    UNSTATED = ["", "-"].freeze

    def initialize(source_code:)
      @code = source_code
      @classic = /\{\{\s*(#{TEMPLATES.map { |t| Regexp.escape(t) }.join('|')})\s*((?:\|[^{}|]*)*)\}\}/
      @ety_token = /(?<![\w-])#{Regexp.escape(source_code)}:([^|<>}]*)((?:<[^<>]*(?:<[^<>]*>[^<>]*)*>)*)/
    end

    def curate(borrowed:, derived:, revisions:)
      borrowed_titles = lemma_titles(borrowed)
      derived_titles = lemma_titles(derived)
      texts = revisions.dig("query", "pages").to_h do |page|
        [page.fetch("title"), page.dig("revisions", 0, "slots", "main", "content").to_s]
      end
      titles = (derived_titles | borrowed_titles).sort_by { |title| [title.downcase, title] }
      rows = titles.map do |title|
        relation = borrowed_titles.include?(title) ? "borrowed" : "derived"
        row_for(title, relation, texts.fetch(title) { raise Nabu::Error, "no revision fetched for #{title}" })
      end
      Result.new(rows: rows, excluded: non_lemmas(borrowed) + non_lemmas(derived),
                 overlap: (borrowed_titles & derived_titles).size)
    end

    # [form, translit, status] for one page's wikitext — status "etymon",
    # "unstated" or "no-template".
    def etymon(wikitext)
      section = etymology_text(wikitext)
      candidates = classic_candidates(section) + ety_candidates(section)
      stated = candidates.find { |(form, _)| !UNSTATED.include?(form) }
      return [nil, nil, candidates.empty? ? "no-template" : "unstated"] unless stated

      form, translit = stated
      [Normalize.nfc(form), translit.to_s.empty? ? nil : Normalize.nfc(translit), "etymon"]
    end

    private

    def members(doc) = doc.dig("query", "categorymembers") || []

    def lemma_titles(doc) = members(doc).select { |m| m["ns"].zero? }.map { |m| m.fetch("title") }

    def non_lemmas(doc) = members(doc).reject { |m| m["ns"].zero? }.map { |m| m.fetch("title") }

    def row_for(title, relation, text)
      form, translit, status = etymon(text)
      lemma = title.split("/", 2).first
      Row.new(latin: lemma, relation: relation, etymon: form, translit: translit,
              no_etymon: status == "etymon" ? nil : status, page: lemma == title ? nil : title)
    end

    # The ==Latin== section's Etymology subsections, comments stripped.
    def etymology_text(wikitext)
      latin = wikitext.match(/^==\s*Latin\s*==\s*$/) or return ""
      rest = latin.post_match
      rest = rest[0...(rest =~ /^==[^=].*==\s*$/ || rest.size)]
      rest = rest.gsub(/<!--.*?-->/m, "")
      rest.to_enum(:scan, /^(===+)\s*Etymology[^=]*\1\s*$/).map do
        body = Regexp.last_match.post_match
        body[0...(body =~ /^===+[^=].*===+\s*$/ || body.size)]
      end.join("\n")
    end

    def classic_candidates(text)
      text.to_enum(:scan, @classic).filter_map do
        args = Regexp.last_match(2).split("|").drop(1)
        positional = args.reject { |a| a.include?("=") }.map(&:strip)
        next unless positional[0, 2] == ["la", @code]

        named = args.select { |a| a.include?("=") }.to_h { |a| a.split("=", 2).map(&:strip) }
        [positional[2].to_s, named["tr"]]
      end
    end

    def ety_candidates(text)
      ety_templates(text).flat_map do |template|
        template.to_enum(:scan, @ety_token).map do
          match = Regexp.last_match
          [match[1].strip, match[2][/<tr:([^<>]*)>/, 1]&.strip]
        end
      end
    end

    # The balanced {{ety|la|…}} template texts.
    def ety_templates(text)
      text.to_enum(:scan, /\{\{ety\|la\|/).map do
        start = Regexp.last_match.begin(0)
        depth = 0
        index = start
        while index < text.size
          if text[index, 2] == "{{"
            depth += 1
            index += 2
          elsif text[index, 2] == "}}"
            depth -= 1
            index += 2
            break if depth.zero?
          else
            index += 1
          end
        end
        text[start...index]
      end
    end
  end
end
