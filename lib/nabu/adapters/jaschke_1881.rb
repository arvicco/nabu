# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"

require_relative "../redirect_follow"
require_relative "../zip_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # jaschke-1881 — H. A. Jäschke, A Tibetan-English Dictionary, with
    # special reference to the prevailing dialects; to which is added an
    # English-Tibetan vocabulary (London: Secretary of State for India in
    # Council, 1881), as the public-domain archive.org scan of the Robarts
    # Library (University of Toronto) copy, item tibetanenglishdi00jsuoft.
    # The dictionary's only complete digital home: DSAL serves 2 of its 671
    # pages (comparison survey, 2026-10-29).
    #
    # == A scan asset, not a text (text_layer none)
    #
    # The archive's machine OCR strips the romanisation's diacritics and
    # reads the Tibetan script as garbage, so NO text layer is taken: every
    # document is a metadata-only scan page ("text_layer" => "none", the
    # local-library/ogham marker) — catalogued, citable by printed page,
    # and queued for transcription as an enrichment (the print gives every
    # headword twice, script and romanisation — the transcription's own
    # cross-check).
    #
    # == Documents: one per printed leaf
    #
    # The PDF's 702 pages are the page map's 702 leafNum entries (leaf k =
    # PDF page k). The curated LEAF MAP below — read off the scan,
    # 2026-10-29 — classes them: print page N sits on leaf N + 26 from
    # p. 1 (leaf 27) to the colophon [p. 672] (leaf 698); the page map's own
    # pageNumber agrees wherever it numbers a leaf (pp. 1–9 and 671–672 it
    # leaves blank), and a contradiction quarantines the page. Numbered
    # leaves mint urn:nabu:jaschke-1881:p<N>; the unnumbered front matter
    # mints …:leaf<k>.
    #
    # == Discovery reconciliation (archive.org's own counts, 2026-10-29)
    #
    # The item advertises imagecount 706: 702 access leaves (the PDF and the
    # page map) + 4 calibration cards (scandata pageType Color Card ×2,
    # White Card ×2) that no access derivative carries. Of the 702, 696 are
    # documents (front matter 24 · dictionary 608 · vocabulary 60 ·
    # corrections 3 · colophon 1) and 6 are binding leaves (covers,
    # endpapers, the library card pocket) skipped by rule, counted in
    # discovery_skips with their notes. 696 + 6 + 4 = 706.
    #
    # == Fetch: pinned to upstream's own checksums
    #
    # Two files under upstream's names in canonical/jaschke-1881/<item>/:
    # the PDF (the page images) and the page map. Each is pinned to the
    # sha1 the item's files.xml publishes (verified against the downloaded
    # bytes 2026-10-29). A held file whose sha1 verifies is never
    # re-requested; downloaded bytes that miss the pin are refused whole
    # (nothing written) — an archive.org re-derivation is an owner re-pin,
    # never a silent swap. Nothing beside upstream's files is materialized.
    class Jaschke1881 < Nabu::Adapter
      SLUG = "jaschke-1881"
      URN_PREFIX = "urn:nabu:#{SLUG}".freeze
      IDENTIFIER = "tibetanenglishdi00jsuoft"
      PDF = "#{IDENTIFIER}.pdf".freeze
      PAGE_MAP = "#{IDENTIFIER}_page_numbers.json".freeze
      FILES = [PDF, PAGE_MAP].freeze
      # files.xml sha1 per file (the archive's own published checksums).
      PINS = {
        PDF => "146fad4ff870fcf8efc3affb278d6928db8019f4",
        PAGE_MAP => "d4cea0cdec1ef012e36a5479a3c651bb71bd41fa"
      }.freeze
      DOWNLOAD_BASE = "https://archive.org/download/#{IDENTIFIER}/".freeze
      DETAILS_URL = "https://archive.org/details/#{IDENTIFIER}".freeze
      ATTEMPTS = 6
      DELAY = 1.0

      # Printed page N = leaf N + LEAF_OFFSET (1-based leafNum).
      LEAF_OFFSET = 26

      # The curated leaf map: [leaves, section, accepted?, note].
      LEAF_MAP = [
        [1..2, "binding", false, "front cover and endpaper of the library binding"],
        [3..26, "front_matter", true, "title, preface, introduction (the transliteration key), " \
                                      "dialect tables, abbreviations, half-title"],
        [27..634, "dictionary", true, "the Tibetan-English dictionary, pp. 1–608"],
        [635..694, "vocabulary", true, "the English-Tibetan vocabulary, pp. 609–668 (half-title, blank, 611–668)"],
        [695..697, "corrections", true, "Corrections, pp. 669–671"],
        [698..698, "colophon", true, "printer's colophon (Unger Brothers, Berlin), [p. 672]"],
        [699..702, "binding", false, "endpapers, library card pocket and back cover of the binding"]
      ].freeze

      TITLE = "A Tibetan-English Dictionary"
      AUTHOR = "H. A. Jäschke"
      DATE = { "not_before" => 1881, "not_after" => 1881, "raw" => "1881" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Jäschke, A Tibetan-English Dictionary (London 1881; archive.org scan)",
        license: "Public domain: H. A. Jäschke (1817–1883), printed London 1881. archive.org item " \
                 "#{IDENTIFIER} (Robarts Library, University of Toronto copy) marked " \
                 "NOT_IN_COPYRIGHT — \"no visible notice of copyright; stated date is 1881\"",
        license_class: "open",
        upstream_url: DETAILS_URL,
        parser_family: "ia-scan-pages"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      # Liveness only: the pins, not a Last-Modified, are the identity.
      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "#{IDENTIFIER} page map", state_subdir: "", liveness_only: true,
          zip_url: "#{DOWNLOAD_BASE}#{PAGE_MAP}", metadata_url: nil
        )]
      end

      # The leaf-map row for leaf +leaf+ (nil outside 1..702).
      def self.leaf_row(leaf) = LEAF_MAP.find { |range, *| range.cover?(leaf) }

      # The printed page on leaf +leaf+, or nil for the unnumbered front
      # matter and the binding.
      def self.print_page(leaf)
        row = leaf_row(leaf)
        return nil if row.nil? || !row[2] || row[1] == "front_matter"

        leaf - LEAF_OFFSET
      end

      def self.urn_for(leaf)
        page = print_page(leaf)
        page ? "#{URN_PREFIX}:p#{page}" : "#{URN_PREFIX}:leaf#{leaf}"
      end

      def initialize(delay: DELAY, pins: PINS, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @pins = pins
        @http = http
      end

      # One ref per accepted leaf in the held page map, in leaf order.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        each_leaf(workdir) do |entry, row|
          next unless row && row[2]

          leaf = entry.fetch("leafNum")
          metadata = { "leaf" => leaf, "section" => row[1] }
          page_number = entry["pageNumber"].to_s
          metadata["ia_page_number"] = page_number unless page_number.empty?
          yield Nabu::DocumentRef.new(source_id: SLUG, id: self.class.urn_for(leaf),
                                      path: File.expand_path(path(workdir, PDF)), metadata: metadata)
        end
      end

      # Binding leaves skip by rule; a leaf outside the curated map is
      # unrecognized (the scan grew or was re-derived — loud).
      def discovery_skips(workdir)
        skipped = []
        unknown = []
        each_leaf(workdir) do |entry, row|
          leaf = entry["leafNum"]
          if row.nil?
            unknown << "leaf #{leaf}: outside the curated leaf map (1–702) — re-derived scan?"
          elsif !row[2]
            skipped << "leaf #{leaf}: #{row[1]} (#{row[3]}) — not part of the 1881 print"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, unrecognized: unknown.size,
                                          notes: skipped + unknown)
      end

      def parse(document_ref)
        meta = document_ref.metadata
        leaf = meta.fetch("leaf")
        page = self.class.print_page(leaf)
        check_page_number!(document_ref, page, meta["ia_page_number"])
        Nabu::Document.new(urn: document_ref.id, language: "eng", canonical_path: document_ref.path,
                           title: title_for(leaf, page), metadata: metadata_for(meta, leaf, page))
      end

      # +force+ is part of the fetch interface; the walk never deletes.
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(File.join(workdir, IDENTIFIER))
        bodies = FILES.reject { |name| held?(workdir, name) }.to_h do |name|
          [name, verified_download(name, progress)]
        end
        bodies.each do |name, body|
          target = path(workdir, name)
          File.binwrite("#{target}.part", body)
          File.rename("#{target}.part", target)
        end
        notes = "#{FILES.size}/#{FILES.size} pinned file(s) held (+#{bodies.size} this sync)"
        progress&.call("#{notes}\n")
        Nabu::FetchReport.new(sha: held_sha(workdir), fetched_at: Time.now, notes: notes)
      end

      private

      def path(workdir, name) = File.join(workdir, IDENTIFIER, name)

      def held?(workdir, name)
        file = path(workdir, name)
        File.file?(file) && Digest::SHA1.file(file).hexdigest == @pins.fetch(name)
      end

      # Yields [page-map entry, leaf-map row] for every leaf, once both
      # pinned files are on disk (the PDF is every document's path).
      def each_leaf(workdir)
        return unless FILES.all? { |name| File.file?(path(workdir, name)) }

        JSON.parse(SourceRead.utf8_file(path(workdir, PAGE_MAP), label: "page map")).fetch("pages").each do |entry|
          yield entry, self.class.leaf_row(entry["leafNum"].to_i)
        end
      end

      def check_page_number!(document_ref, page, ia_number)
        return if ia_number.nil? || ia_number == page.to_s

        raise Nabu::ParseError, "#{document_ref.id}: the page map numbers leaf #{document_ref.metadata['leaf']} " \
                                "p. #{ia_number}, the leaf rule p. #{page.inspect} — re-derived scan?"
      end

      def title_for(leaf, page)
        where = page ? "p. #{page}" : "front matter, leaf #{leaf}"
        "#{AUTHOR}, #{TITLE} (1881), #{where}"
      end

      def metadata_for(meta, leaf, page)
        {
          "author" => AUTHOR, "title" => TITLE, "date" => DATE,
          "imprint" => "London: Secretary of State for India in Council",
          "object_language" => "xct", "section" => meta.fetch("section"), "leaf" => leaf,
          "print_page" => page, "ia_page_number" => meta["ia_page_number"],
          "ia_identifier" => IDENTIFIER, "ia_url" => "#{DETAILS_URL}/page/n#{leaf - 1}",
          "scan" => "Robarts Library, University of Toronto copy; Internet Archive scan 2007, 400 ppi",
          "text_layer" => "none"
        }.compact
      end

      def verified_download(name, progress)
        body = download("#{DOWNLOAD_BASE}#{name}", progress)
        actual = Digest::SHA1.hexdigest(body)
        return body if actual == @pins.fetch(name)

        raise Nabu::FetchError, "#{SLUG}: #{name} sha1 #{actual} differs from the pinned " \
                                "#{@pins.fetch(name)} (files.xml) — upstream re-derived it; review and re-pin"
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

      # The tree's identity: sha256 over each held file's name + sha1 pin.
      def held_sha(workdir)
        rows = FILES.select { |name| held?(workdir, name) }.map { |name| "#{name}\t#{@pins.fetch(name)}" }
        Digest::SHA256.hexdigest(rows.join("\n"))
      end
    end
  end
end
