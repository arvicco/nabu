# frozen_string_literal: true

require "fileutils"

require_relative "../file_fetch"

module Nabu
  module Adapters
    # The CTILC adapter (P80-8): the public-domain works slice of the
    # Corpus Textual Informatitzat de la Llengua Catalana (Institut
    # d'Estudis Catalans) — 967 downloadable works (LITERARI 348 + NO
    # LITERARI 619, censused 2026-08-19), 19th–20th c. printed Catalan.
    #
    # == Identity (FROZEN minting)
    #
    # Document = one downloadable work; urn = urn:nabu:ctilc:<OBRA id>
    # (the filename's 6-digit zero-padded prefix IS the OBRA id — stable,
    # never the mojibake-prone title; parse cross-checks the in-file
    # <OBRA id> and quarantines a mismatch). Passage = one blank-line
    # paragraph of <TEXT>, cited :1..n in file order. Minting frozen once
    # used.
    #
    # == Format (verified on three real works)
    #
    # UTF-8 WITH BOM; a pseudo-XML header then plain text:
    #   <DOCUMENT> <OBRA id="41"> <AUTOR>…</AUTOR> <TÍTOL>…</TÍTOL>
    #   <ANY>1918</ANY> <CLASSIFICACIÓ_TEXTUAL llengua= gènere= tema=
    #   subtema= traducció= variant= /> </OBRA> <TEXT>…</TEXT> </DOCUMENT>
    # NON-ASCII tag names, no XML declaration, unescaped & likely in body
    # text → the header parses by line/regex rules, NEVER an XML parser.
    # The BOM strips at the boundary; verse keeps upstream's trailing
    # two-space soft line breaks verbatim (canonical means canonical).
    #
    # == Language and dating
    #
    # `cat` for every document (bare-anchor identity — no Catalan node in
    # nabu-lects yet; postures row identity). The CLASSIFICACIÓ_TEXTUAL
    # variant= dialect attr (baleàric, central, valencià…) rides metadata
    # verbatim AND as the "variant" facet — the FUTURE lect seam; no
    # rules are built here. The ANY publication year rides the
    # :structured MetadataDates envelope (the sillok mold).
    #
    # == License (verbatim on the listing page, 2026-08-19)
    #
    # The terms table: the works "han passat a ser de domini públic"
    # under Llei 21/2014 and are downloadable "per a ús privat o de
    # recerca amb llicència Creative Commons" — the CC variant is UNNAMED
    # on the page (dcc@iec.cat is the published contact for a named one).
    # Mandatory citation on the digitization (verbatim in the manifest).
    # Honest class: attribution (PD works + the IEC citation duty).
    #
    # == fetch: listing snapshot + polite resumable crawl (the riig mold)
    #
    # The listing page (the ONLY home of each work's bibliographic
    # citation — publisher/place metadata) fetches through Nabu::FileFetch
    # into <workdir>/listing/ (conditional GET, sha pin, attic retention,
    # the remote probe's drift target). Then each listed work GETs from
    # the STATELESS per-file endpoint (no cookies/session/referer —
    # verified 2026-08-19) into <workdir>/works/, sequential at
    # CRAWL_DELAY (≤1 rq/s), RESUMABLE: a file that exists, is nonzero
    # and ends with </DOCUMENT> is never refetched (upstream serves no
    # ETag/Last-Modified per file). A replacement (an incomplete local
    # file) attics the old bytes first — non-destructive by construction.
    # Change detection = listing re-diff: NEW WORKS ENTER THE PUBLIC
    # DOMAIN EACH JANUARY, so a yearly owner-fired re-sync picks up the
    # new entries (sync_policy manual).
    class Ctilc < Nabu::Adapter
      BASE_URL = "https://ctilc.iec.cat/scripts"
      LISTING_URL = "#{BASE_URL}/CTILCCorpus_Descarr.asp".freeze
      WORK_URL = "#{BASE_URL}/CTILCCorpus_DescarrF.asp".freeze

      LISTING_DIRNAME = "listing"
      LISTING_FILENAME = "CTILCCorpus_Descarr.html"
      WORKS_DIRNAME = "works"

      # Seconds between work GETs — the polite bar (≤1 rq/s) against the
      # IEC's ASP host; the crawl is resumable, so a re-run only pays for
      # what is missing.
      CRAWL_DELAY = 1.0

      LANGUAGE = "cat"

      URN_PREFIX = "urn:nabu:ctilc:"

      # A work filename as the listing spells it (000041_Poemes_biblics
      # .out.txt — all 967 censused 2026-08-19 match; 19 carry hyphens).
      FILENAME_SHAPE = /\A(\d{6})_[A-Za-z0-9_-]+\.out\.txt\z/

      # One listing entry: the obredoc('<filename>') onClick plus the
      # anchor's inner HTML (the bibliographic citation).
      ENTRY_SHAPE = %r{onClick="obredoc\('([^']+)'\); return false">(.*?)</a>}m

      MANIFEST = Nabu::SourceManifest.new(
        id: "ctilc",
        name: "CTILC public-domain works slice — Corpus Textual Informatitzat de la " \
              "Llengua Catalana (IEC)",
        license: "Public domain + IEC citation duty (listing-page terms verbatim, 2026-08-19: the works " \
                 "\"han passat a ser de domini públic\" under Llei 21/2014 and are downloadable \"per a " \
                 "ús privat o de recerca amb llicència Creative Commons\" — the CC variant is UNNAMED " \
                 "on the page; dcc@iec.cat is the published contact for a named one. Mandatory citation: " \
                 "\"Aquest text ha estat digitalitzat i processat per l'Institut d'Estudis Catalans, " \
                 "com a part del projecte Corpus Textual Informatitzat de la Llengua Catalana\")",
        license_class: "attribution",
        upstream_url: LISTING_URL,
        parser_family: "ctilc-txt"
      )

      def self.manifest
        MANIFEST
      end

      # P79-2: the listing rides FileFetch, so the probe HEADs it against
      # the listing/.file-fetch.json pin (reachability + Last-Modified
      # drift — the riig mold). Per-work state exists only as the bulk
      # skip-valid rule; the listing is the honest cheap target.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "download listing", zip_url: LISTING_URL, metadata_url: nil,
          state_subdir: LISTING_DIRNAME, state_file: FileFetch::STATE_FILE
        )]
      end

      # +crawl_delay+ exists for the WebMock'd tests (0) — real syncs
      # keep the polite default.
      def initialize(crawl_delay: CRAWL_DELAY)
        super()
        @crawl_delay = crawl_delay
        @listing_entries = {}
      end

      # One DocumentRef per crawled work, in OBRA-id order. A workdir
      # without works/ yields nothing (the day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        work_files(workdir).each do |id, path|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{URN_PREFIX}#{id}", path: path,
            metadata: { "file" => File.basename(path), "id" => id }
          )
        end
      end

      def discovery_skips(workdir)
        strays = Dir[File.join(workdir, WORKS_DIRNAME, "*")]
                 .select { |path| File.file?(path) }
                 .reject { |path| FILENAME_SHAPE.match?(File.basename(path)) }.sort
        DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |path| "#{File.basename(path)}: not the NNNNNN_Title.out.txt shape" }
        )
      end

      def parse(document_ref)
        content = Normalize.nfc(read_work(document_ref.path))
        id = document_ref.metadata.fetch("id")
        check_obra_id!(content, id, document_ref.path)
        classificacio = classificacio_attrs(content)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: presence(field(content, "TÍTOL")),
          canonical_path: document_ref.path,
          metadata: metadata(document_ref, content, classificacio)
        )
        paragraphs(content, document_ref.path).each_with_index do |paragraph, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE,
            text: paragraph, sequence: index
          )
        end
        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Listing via FileFetch (prepare → breaker → complete), then the
      # polite resumable work crawl (class note). No network in tests:
      # WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        listing = listing_fetch(workdir, progress)
        listing.prepare!
        guard_mass_deletion!(workdir, listing.doomed_paths, force: force)
        listing.complete!
        filenames = listed_filenames(workdir)
        counts = crawl_works!(workdir, filenames, progress: progress)
        report(listing, filenames, counts)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "ctilc fetch failed into #{workdir}: #{e.message}"
      end

      private

      # -- parse -----------------------------------------------------------------

      # The file's decoded UTF-8, BOM stripped at the boundary (every
      # work is UTF-8 WITH BOM upstream — the encoding regression).
      def read_work(path)
        File.read(path, encoding: Encoding::UTF_8).delete_prefix("﻿")
      end

      # The urn mints from the filename prefix; the in-file <OBRA id>
      # must agree, or the document quarantines — an identity is never
      # guessed past a disagreement.
      def check_obra_id!(content, id, path)
        obra = content[/<OBRA id="(\d+)">/, 1]
        raise ParseError, "#{path}: no <OBRA id> header found" if obra.nil?
        return if obra.to_i == id

        raise ParseError, "#{path}: filename id #{id} disagrees with OBRA id #{obra} — " \
                          "the identity is never guessed past a mismatch"
      end

      def field(content, tag)
        content[%r{<#{tag}>(.*?)</#{tag}>}m, 1].to_s.strip
      end

      def classificacio_attrs(content)
        tag = content[%r{<CLASSIFICACIÓ_TEXTUAL\b([^>]*)/>}, 1].to_s
        tag.scan(/([[:alpha:]]+)="([^"]*)"/).to_h
      end

      def metadata(document_ref, content, classificacio)
        meta = { "file" => document_ref.metadata.fetch("file") }
        autor = presence(field(content, "AUTOR"))
        meta["autor"] = autor if autor
        any = presence(field(content, "ANY"))
        meta["any"] = any if any
        meta["date"] = date_envelope(any) if any&.match?(/\A\d{4}\z/)
        meta["classificacio"] = classificacio unless classificacio.empty?
        variant = presence(classificacio["variant"])
        # The dialect variant is the FUTURE lect seam (class note): it
        # rides as a facet so a ruled rule can match it later — no rules
        # are built here.
        meta["facets"] = { "variant" => { "value" => variant } } if variant
        meta.merge!(listing_metadata(document_ref))
        meta
      end

      # The :structured MetadataDates shape (the sillok mold): the ANY
      # publication year, one-year envelope.
      def date_envelope(any)
        { "not_before" => any.to_i, "not_after" => any.to_i, "raw" => any }
      end

      def presence(value)
        value.nil? || value.empty? ? nil : value
      end

      def paragraphs(content, path)
        text = content[%r{<TEXT>(.*)</TEXT>}m, 1]
        raise ParseError, "#{path}: no <TEXT> body found" if text.nil?

        chunks = text.split(/\n\s*\n/).map(&:strip).reject(&:empty?)
        raise ParseError, "#{path}: <TEXT> holds no paragraphs" if chunks.empty?

        chunks
      end

      # -- the listing join ------------------------------------------------------

      # The work's listing entry ({"citation" => …, "section" => …}), by
      # filename. The listing is the ONLY home of the bibliographic
      # citation (publisher/place); a workdir without the snapshot (or a
      # work the snapshot does not list) honestly carries neither key.
      def listing_metadata(document_ref)
        workdir = File.dirname(document_ref.path, 2)
        listing_entries(File.join(workdir, LISTING_DIRNAME, LISTING_FILENAME))
          .fetch(document_ref.metadata.fetch("file"), {})
      end

      def listing_entries(path)
        @listing_entries[path] ||= begin
          entries = {}
          if File.file?(path)
            listing = Normalize.nfc(File.read(path, encoding: Encoding::UTF_8).scrub)
            nolit = listing.index("<b>NO LITERARI</b>")
            listing.scan(ENTRY_SHAPE) do
              match = Regexp.last_match
              entries[match[1]] = {
                "citation" => citation_text(match[2]),
                "section" => nolit && match.begin(0) > nolit ? "NO LITERARI" : "LITERARI"
              }
            end
          end
          entries
        end
      end

      # The anchor's inner HTML stripped to its text — the citation as a
      # reader sees it (small-caps/italic spans are presentation).
      def citation_text(html)
        html.gsub(/<[^>]+>/, "").gsub(/\s+/, " ").strip
      end

      # -- fetch -----------------------------------------------------------------

      def listing_fetch(workdir, progress)
        FileFetch.new(
          url: LISTING_URL, dir: File.join(workdir, LISTING_DIRNAME), filename: LISTING_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, LISTING_DIRNAME), progress: progress
        )
      end

      # The listed work filenames out of the fetched snapshot. Zero
      # entries = the page shape changed upstream — loud, never a silent
      # empty sync.
      def listed_filenames(workdir)
        path = File.join(workdir, LISTING_DIRNAME, LISTING_FILENAME)
        raise Nabu::FetchError, "ctilc fetch: listing #{path} is missing after fetch" unless File.file?(path)

        names = File.read(path, encoding: Encoding::UTF_8).scrub
                    .scan(ENTRY_SHAPE).map(&:first).grep(FILENAME_SHAPE).uniq
        if names.empty?
          raise Nabu::FetchError,
                "ctilc fetch: no work entries found in #{path} (upstream page shape changed?)"
        end

        names
      end

      # Sequential, polite, resumable (class note). tmp+rename writes; a
      # replacement attics the old bytes first; a non-200 or an
      # incomplete body aborts the sync loudly.
      def crawl_works!(workdir, filenames, progress: nil)
        dir = File.join(workdir, WORKS_DIRNAME)
        FileUtils.mkdir_p(dir)
        progress&.call("Crawling #{filenames.size} CTILC works…\n")
        counts = { fetched: 0, cached: 0 }
        filenames.each do |name|
          target = File.join(dir, name)
          next counts[:cached] += 1 if complete_document?(target)

          sleep(@crawl_delay) if @crawl_delay.positive? && counts[:fetched].positive?
          body = get_work(name)
          attic_replaced!(workdir, name, target) if File.file?(target)
          File.binwrite("#{target}.tmp", body)
          File.rename("#{target}.tmp", target)
          counts[:fetched] += 1
        end
        counts
      end

      # The resumability rule: present, nonzero, and ending with
      # </DOCUMENT> (upstream serves no per-file ETag/Last-Modified — the
      # closing tag is the honest completeness check).
      def complete_document?(path)
        return false unless File.file?(path) && File.size(path).positive?

        tail = File.open(path, "rb") do |file|
          file.seek(-[64, file.size].min, IO::SEEK_END)
          file.read
        end
        tail.rstrip.end_with?("</DOCUMENT>")
      end

      def get_work(name)
        url = "#{WORK_URL}?fitxer=#{name}"
        response = FileFetch.default_http.get(url)
        raise Nabu::FetchError, "ctilc work crawl: HTTP #{response.status} for #{url}" unless response.status == 200

        body = response.body.to_s
        unless body.rstrip.end_with?("</DOCUMENT>")
          raise Nabu::FetchError, "ctilc work crawl: body for #{url} does not end with </DOCUMENT> " \
                                  "(an error page is never persisted as a work)"
        end
        body
      rescue Faraday::Error => e
        raise Nabu::FetchError, "ctilc work crawl: transport error for #{url}: #{e.message}"
      end

      # Non-destructive replacement (the house retention contract): the
      # doomed local bytes copy into the attic before the rewrite; the
      # first copy wins, as in GitFetch.
      def attic_replaced!(workdir, name, target)
        attic = File.join(workdir, ATTIC_DIRNAME, WORKS_DIRNAME, name)
        return if File.exist?(attic)

        FileUtils.mkdir_p(File.dirname(attic))
        FileUtils.cp(target, attic)
      end

      def report(listing, filenames, counts)
        Nabu::FetchReport.new(
          sha: listing.sha, fetched_at: Time.now,
          notes: "listing=#{listing.sha.to_s[0, 12]} · works: #{counts[:fetched]} fetched, " \
                 "#{counts[:cached]} cached (#{filenames.size} listed)",
          repos: { LISTING_URL => listing.sha }
        )
      end

      # -- discovery -------------------------------------------------------------

      def work_files(workdir)
        Dir[File.join(workdir, WORKS_DIRNAME, "*.out.txt")]
          .filter_map do |path|
            match = FILENAME_SHAPE.match(File.basename(path))
            [match[1].to_i, File.expand_path(path)] if match
          end
          .sort
      end
    end
  end
end
