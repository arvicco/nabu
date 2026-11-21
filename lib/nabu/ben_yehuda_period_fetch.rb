# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "nokogiri"
require "uri"

require_relative "redirect_follow"
require_relative "zip_fetch"

module Nabu
  # Upstream's own period taxonomy for the ben-yehuda dump (the ruled
  # pre-modern cut): which author directories of Project Ben-Yehuda's
  # public-domain dump belong to the site's "ancient + piyyut" and "middle
  # ages and renaissance" bands.
  #
  # == Why the site's author browse
  #
  # The dump itself carries no period: pseudocatalogue.csv is ID, path,
  # title, authors, translators, author_uris, translator_uris,
  # original_language, genre, source_edition — and the HTML variant's
  # head names only title + author (both read 2026-11-18). The site holds
  # the period on every authority record, but its API (/api/v1) answers
  # "key not found or disabled" without a registered key — the automation
  # bar for a fetch. The public author browse filters by the same period
  # enum (ancient / medieval / enlightenment / revival / modern) and needs
  # nothing: GET /authors?ckb_periods[]=<band>, 100 authors a page,
  # alphabetical, the next page named by the "לדף הבא" button's
  # data-search-after-* cursor (the site's own paging script submits
  # exactly those four values). The walk checks itself against the page's
  # own "דף N מתוך M" (page N of M) line.
  #
  # == The sidecar
  #
  # periods.json at the canonical root (Adapters::BenYehuda declares it in
  # materialized_paths): per band the site's label and its year bounds,
  # per author id (= the dump's p<id> directory) the band, the browse
  # name and the site's own work count. Rewritten only when the band
  # lists change, so an unchanged re-fetch leaves the canonical identity
  # (and its retrieved stamp) untouched.
  #
  # A walk that fails anywhere — HTTP error, a page without entries, a
  # page count that disagrees with the walk, an author listed in both
  # bands — raises Error and writes nothing.
  class BenYehudaPeriodFetch
    class Error < Nabu::Error; end

    BASE_URL = "https://benyehuda.org/authors"
    SIDECAR = "periods.json"

    # The two pre-modern bands, labels verbatim from the site's period
    # menu (read 2026-11-18); the bounds are the labels' own years. The
    # ancient band states no lower bound ("to 900 CE") — nil, never a
    # guessed floor.
    BANDS = {
      "ancient" => { "label" => "עת עתיקה ופיוט (עד 900 לספירה)", "not_before" => nil, "not_after" => 900 },
      "medieval" => { "label" => "ימי הביניים והרנסאנס (900 עד 1700)", "not_before" => 900, "not_after" => 1700 }
    }.freeze

    # A runaway guard on the cursor walk.
    # census: the medieval band is 3 browse pages (202 authors), the ancient
    # band 1 (13), 2026-11-18 — 25 leaves room for growth.
    MAX_PAGES = 25

    NEXT_LABEL = "לדף הבא"
    PAGE_COUNT = /דף\s+(\d+)\s+מתוך\s+(\d+)/
    ONE_WORK = "יצירה אחת"

    Entry = Data.define(:id, :name, :works)
    Page = Data.define(:entries, :next_cursor, :page, :pages)
    Result = Data.define(:payload, :written)

    def self.default_http
      ZipFetch.default_http
    end

    # Walk both bands and land the sidecar in +dir+ (unless unchanged).
    def self.sync!(dir:, http: default_http, retrieved: Date.today, progress: nil)
      payload = new(http: http, progress: progress).payload(retrieved: retrieved)
      Result.new(payload: payload, written: !write!(dir, payload).nil?)
    end

    # The held sidecar under +dir+, or nil when none was ever written.
    def self.read(dir)
      path = File.join(dir, SIDECAR)
      File.file?(path) ? JSON.parse(File.read(path, encoding: "UTF-8")) : nil
    end

    # Write +payload+ unless the held sidecar already says the same (the
    # retrieved stamp aside). Returns the written path, nil when unchanged.
    # tmp + rename.
    def self.write!(dir, payload)
      held = read(dir)
      return nil if held && held.except("retrieved") == payload.except("retrieved")

      FileUtils.mkdir_p(dir)
      path = File.join(dir, SIDECAR)
      File.write("#{path}.tmp", "#{JSON.pretty_generate(payload)}\n")
      File.rename("#{path}.tmp", path)
      path
    end

    # One browse page → its author entries, the next-page cursor (nil on
    # the last page) and its "page N of M" (1 of 1 when no paging row).
    def self.parse_page(html)
      doc = Nokogiri::HTML(html)
      entries = doc.css("#browse_mainlist li").filter_map { |li| entry(li) }
      page, pages = (doc.text[PAGE_COUNT] && [Integer(Regexp.last_match(1)), Integer(Regexp.last_match(2))]) || [1, 1]
      Page.new(entries: entries, next_cursor: next_cursor(doc), page: page, pages: pages)
    end

    def self.entry(item)
      link = item.at_css("a[href^='/author/']") or return nil
      id = link["href"][%r{\A/author/(\d+)\z}, 1] or return nil
      Entry.new(id: id, name: Normalize.nfc(link.text.strip), works: works(item.at_css("span")&.text.to_s))
    end

    # "(586 יצירות)" → 586; "(יצירה אחת)" → 1; anything else nil.
    def self.works(text)
      return 1 if text.include?(ONE_WORK)

      text[/(\d+)/, 1]&.then { |count| Integer(count, 10) }
    end

    def self.next_cursor(doc)
      button = doc.css("button.browse_paging").find { |b| b.text.strip == NEXT_LABEL } or return nil
      { "search_after_id" => button["data-search-after-id"].to_s,
        "page" => button["data-search-after-page"].to_s,
        "reverse" => button["data-search-after-reverse"].to_s,
        "search_after_value" => button["data-search-after-value"].to_s }
    end

    def self.page_url(band, cursor = nil)
      pairs = [["ckb_periods[]", band]]
      pairs.concat(cursor.to_a) if cursor
      "#{BASE_URL}?#{URI.encode_www_form(pairs)}"
    end

    def initialize(http:, progress: nil)
      @http = http
      @progress = progress
    end

    # The sidecar content: both bands walked, authors keyed by id.
    def payload(retrieved:)
      bands = {}
      authors = {}
      BANDS.each do |band, info|
        entries, pages = walk(band)
        entries.each do |entry|
          if authors.key?(entry.id)
            raise Error, "author #{entry.id} is listed in both #{authors[entry.id]['band']} and #{band}"
          end

          authors[entry.id] = { "band" => band, "name" => entry.name, "works" => entry.works }
        end
        bands[band] = info.merge("authors" => entries.size, "pages" => pages)
      end
      {
        "source" => "#{BASE_URL}?ckb_periods[]=<band> — Project Ben-Yehuda's author browse filtered by " \
                    "the site's own period taxonomy",
        "retrieved" => retrieved.iso8601,
        "bands" => bands,
        "authors" => authors.sort_by { |id, _| Integer(id, 10) }.to_h
      }
    end

    private

    # Every entry of one band, following the cursor; [entries, pages].
    def walk(band)
      entries = []
      cursor = nil
      1.upto(MAX_PAGES) do |step|
        page = fetch_page(band, cursor)
        check_page!(band, page, step)
        entries.concat(page.entries)
        return [entries, page.pages] if page.next_cursor.nil?

        cursor = page.next_cursor
      end
      raise Error, "#{band}: more than #{MAX_PAGES} browse pages — refusing a runaway walk"
    end

    def check_page!(band, page, step)
      raise Error, "#{band} page #{step}: no author entries (the browse layout changed?)" if page.entries.empty?
      unless page.page == step
        raise Error, "#{band}: the walk is at page #{step} but the site prints page #{page.page} of #{page.pages}"
      end
      return unless page.next_cursor.nil? && page.page != page.pages

      raise Error, "#{band}: page #{page.page} of #{page.pages} carries no next-page cursor"
    end

    def fetch_page(band, cursor)
      url = self.class.page_url(band, cursor)
      @progress&.call("Reading #{url}…\n")
      response, = RedirectFollow.get(url, http: @http, error: Error)
      self.class.parse_page(response.body.to_s.dup.force_encoding(Encoding::UTF_8))
    end
  end
end
