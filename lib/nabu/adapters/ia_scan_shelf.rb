# frozen_string_literal: true

require "digest"
require "fileutils"

require_relative "ia_hocr_text"
require_relative "../redirect_follow"
require_relative "../zip_fetch"

module Nabu
  module Adapters
    # The archive.org scan-shelf base: a CURATED table of archive.org
    # items — public-domain scholarship whose only machine text is the
    # archive's own uncorrected OCR — fetched as their hOCR derivative pair
    # (Nabu::Adapters::IaHocrText) and minted at PAGE grain. Subclasses
    # declare MANIFEST (the source identity) and ITEMS (the census: one
    # Item per work volume, each naming its archive.org identifier and file
    # stem); everything else is shared here.
    #
    # == Documents and passages
    #
    # One document per Item — urn:nabu:<slug>:<key>, the key a curated,
    # stable work slug (never the archive.org identifier, which rides as
    # metadata) — and one passage per NON-BLANK hOCR page,
    # urn:nabu:<slug>:<key>:<n>, n the 1-based hOCR page ordinal (the scan's
    # page sequence, front matter and plates included; printed page numbers
    # are not claimed — see IaHocrText).
    #
    # == The OCR honesty flag (rides every document)
    #
    # metadata "text_nature" = "uncorrected-ocr" plus the OCR_NOTE
    # statement and a measured "ocr_wordlike" share (IaHocrText.
    # wordlike_share over the document's pages) — the text is the archive's
    # machine OCR, never proofread: German prose reads approximately;
    # Cyrillic, Glagolitic-transliterated, Greek and diacritic-heavy Slavic
    # forms are frequently garbled. Cite the scan (metadata "ia_url").
    #
    # == Fetch: the polite, resumable item walk
    #
    # Each item's two derivatives land in canonical/<slug>/<identifier>/
    # under upstream's own file names. An item already on disk is never
    # re-requested (archive.org derivatives are treated as immutable; a
    # re-derive upstream is caught only by deleting the item dir —
    # declared). archive.org 302s every download to a rotating mirror node
    # and some nodes answer 500 for a while (censused 2026-10-11: the same
    # file 500 on two nodes, 200 on the third), so each GET retries up to
    # ATTEMPTS times; an item still unreachable is reported in the notes and
    # retried at the next sync — the sync proceeds with what landed. Only a
    # walk where NOTHING is held raises Nabu::FetchError. Nothing is ever
    # deleted, so there is no mass-deletion breaker to guard.
    class IaScanShelf < Nabu::Adapter
      # One curated work volume. +date+ is the structured MetadataDates
      # shape (not_before/not_after/raw) — the TEXT's own date (a facsimile
      # reprint keeps its first edition's date; the print rides +note+).
      Item = Data.define(:key, :identifier, :file, :language, :creator, :title, :date, :imprint,
                         :genre, :series, :scan, :note) do
        def initialize(key:, identifier:, language:, creator:, title:, date:, genre:, file: nil,
                       imprint: nil, series: nil, scan: nil, note: nil)
          super(key: key, identifier: identifier, file: file || identifier, language: language,
                creator: creator, title: title, date: date, imprint: imprint, genre: genre,
                series: series, scan: scan, note: note)
        end
      end

      DOWNLOAD_BASE = "https://archive.org/download/"
      DETAILS_BASE = "https://archive.org/details/"
      # GET attempts per file across rotating mirror nodes.
      ATTEMPTS = 6
      # Seconds between requests (and the retry backoff unit).
      DELAY = 1.0

      OCR_NOTE = "Uncorrected machine OCR (archive.org hOCR derivative), never proofread: German " \
                 "and Latin prose reads approximately; Cyrillic, Glagolitic-transliterated, Greek " \
                 "and diacritic-heavy Slavic forms are frequently garbled. Cite the scan (ia_url)."

      # The structured date hash for a year or a year span.
      def self.dated(first, last = first, raw: nil)
        { "not_before" => first, "not_after" => last,
          "raw" => raw || (first == last ? first.to_s : "#{first}–#{last}") }
      end

      # archive.org file names carry spaces, parentheses and diacritics —
      # percent-encode every byte outside the unreserved set.
      def self.download_url(identifier, filename)
        encoded = filename.b.gsub(/[^A-Za-z0-9._~-]/n) { |byte| format("%%%02X", byte.ord) }
        "#{DOWNLOAD_BASE}#{identifier}/#{encoded}"
      end

      def self.items = self::ITEMS

      def self.remote_probe_strategy = :http_zip

      # Liveness only: the walk keeps no Last-Modified pin (held items are
      # never re-requested), so drift honestly reads unknown.
      def self.http_probe_targets
        item = items.first
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "#{item.identifier} search text", state_subdir: "", liveness_only: true,
          zip_url: download_url(item.identifier, "#{item.file}#{IaHocrText::SEARCHTEXT_SUFFIX}"),
          metadata_url: nil
        )]
      end

      def initialize(delay: DELAY, items: nil, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @items = items || self.class.items
        @http = http
      end

      # One ref per census item whose derivative pair is on disk.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        @items.each do |item|
          paths = item_paths(workdir, item)
          next unless File.file?(paths[:searchtext]) && File.file?(paths[:pageindex])

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: "urn:nabu:#{manifest.id}:#{item.key}",
                                      path: File.expand_path(paths[:searchtext]),
                                      metadata: { "key" => item.key })
        end
      end

      def parse(document_ref)
        item = @items.find { |candidate| candidate.key == document_ref.metadata["key"] } ||
               raise(Nabu::ParseError, "#{document_ref.id}: not in the #{manifest.id} census")
        pages = IaHocrText.read_pages(
          searchtext_path: document_ref.path,
          pageindex_path: document_ref.path.delete_suffix(IaHocrText::SEARCHTEXT_SUFFIX) +
                          IaHocrText::PAGEINDEX_SUFFIX
        )
        text_pages = pages.reject { |page| page.text.empty? }
        raise Nabu::ParseError, "#{document_ref.id}: no OCR text on any of #{pages.size} pages" if text_pages.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: item.language, canonical_path: document_ref.path,
          title: title_for(item), metadata: metadata_for(item, pages, text_pages)
        )
        text_pages.each do |page|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{page.ordinal}", language: item.language,
                                        text: page.text, sequence: page.ordinal,
                                        annotations: { "hocr_page" => page.ordinal })
        end
        document
      end

      # +force+ is part of the fetch interface; the walk never deletes, so
      # there is no breaker to override.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        landed = []
        failed = []
        @items.each do |item|
          next if held?(workdir, item)

          fetch_item!(workdir, item, progress)
          landed << item.key
        rescue Nabu::FetchError => e
          failed << item.key
          progress&.call("#{item.key}: unreachable this sync (#{e.message})\n")
        end
        held = @items.count { |item| held?(workdir, item) }
        raise Nabu::FetchError, "#{manifest.id}: no item reachable (#{failed.join(', ')})" if held.zero?

        notes = "#{held}/#{@items.size} item(s) held (+#{landed.size} this sync)"
        notes += "; unreachable, retried next sync: #{failed.join(', ')}" unless failed.empty?
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: held_sha(workdir), fetched_at: Time.now, notes: notes)
      end

      private

      def item_paths(workdir, item) = IaHocrText.paths(File.join(workdir, item.identifier), item.file)

      def held?(workdir, item) = item_paths(workdir, item).values.all? { |path| File.file?(path) }

      # Both derivatives download BEFORE either is written — an item lands
      # whole or not at all.
      def fetch_item!(workdir, item, progress)
        bodies = item_paths(workdir, item).transform_values do |path|
          download(self.class.download_url(item.identifier, File.basename(path)), progress)
        end
        bodies.each do |kind, body|
          path = item_paths(workdir, item).fetch(kind)
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite("#{path}.part", body)
          File.rename("#{path}.part", path)
        end
      end

      def download(url, progress)
        attempt = 0
        begin
          attempt += 1
          sleep(@delay * attempt) if @delay.positive?
          progress&.call("GET #{url}\n") if attempt == 1
          response, = Nabu::RedirectFollow.get(url, http: @http, error: Nabu::FetchError)
          response.body.to_s.b
        rescue Nabu::FetchError
          raise if attempt >= ATTEMPTS

          retry
        end
      end

      # The tree's identity: sha256 over every held file's relative path +
      # body sha, in path order.
      def held_sha(workdir)
        rows = @items.select { |item| held?(workdir, item) }.flat_map do |item|
          item_paths(workdir, item).values.map do |path|
            "#{path.delete_prefix("#{workdir}/")}\t#{Digest::SHA256.file(path).hexdigest}"
          end
        end
        Digest::SHA256.hexdigest(rows.sort.join("\n"))
      end

      def title_for(item)
        "#{item.creator}, #{item.title} (#{item.date.fetch('raw')})"
      end

      def metadata_for(item, pages, text_pages)
        {
          "author" => item.creator, "title" => item.title, "date" => item.date, "imprint" => item.imprint,
          "series" => item.series, "genre" => item.genre, "facets" => { "genre" => { "value" => item.genre } },
          "note" => item.note, "scan" => item.scan,
          "ia_identifier" => item.identifier, "ia_file" => item.file, "ia_url" => "#{DETAILS_BASE}#{item.identifier}",
          "text_nature" => "uncorrected-ocr", "ocr_note" => OCR_NOTE,
          "ocr_wordlike" => IaHocrText.wordlike_share(text_pages.map(&:text)),
          "hocr_pages" => pages.size, "blank_pages" => pages.size - text_pages.size
        }.compact
      end
    end
  end
end
