# frozen_string_literal: true

require_relative "../eebo_tcp_fetch"

module Nabu
  module Adapters
    # Box shared-folder acquisition for the TCP's two smaller collections
    # (Evans-TCP, ECCO-TCP) — Nabu::EeboTcpFetch's machinery (the
    # postStreamData listing walk, zip-grain skip-if-unchanged, streamed
    # ZipFetch staging with the member-grain attic, the mass-deletion
    # guard, the sha-pinned ledger) re-pointed at a different share and
    # folder shape. A subclass in adapters/ (the MaduraiFetch < LitopysFetch
    # mold) rather than an edit to EeboTcpFetch: the parent is shared
    # derivation core, and a change there would dirty every source's stamp.
    #
    # == The folder shape (both collections, verified 2026-11-03)
    #
    #   <share root>/
    #     <P4 folder>/                 Evans P4_XML_TCP · ECCO p4
    #       N0.zip … N3.zip            Evans released (4,864 texts)
    #       unedited.zip               Evans unedited (148 texts)
    #       ecco_p4_released.zip       ECCO released (2,473 texts)
    #       ecco_p4_unedited.zip       ECCO unedited (628 texts)
    #     <P3 folder>/, <P5 folder>/   the same texts as SGML / Oxford P5 — never walked
    #     eebo2prf.xml.dtd             the P4 schema (landed beside texts/)
    #     *dat*.sgm, *.mtxt, *.mrc …   catalogue metadata — never fetched
    #
    # Unlike EEBO's zips (one top-level <stem>/ dir), these zips are FLAT
    # (<ID>.p4.xml members at the root); ZipFetch maps either shape onto
    # the unit dir, so units land at texts/<class>/<zip-stem>/<ID>.p4.xml.
    #
    # == The two classes
    #
    # A zip whose name carries "unedited" is the `unedited` class, every
    # other P4 zip is `released` (a future N4.zip joins released with no
    # code change). The TCP never formally released the unedited texts
    # (the share's TCP-readme: "never even minimally edited, much less
    # formally released, mostly because of quality issues") — the class
    # rides each document's metadata so a reader can tell them apart.
    # +classes+ scopes acquisition exactly as EEBO's phases do: an
    # out-of-scope class is never listed, never doomed.
    class TcpBoxFetch < Nabu::EeboTcpFetch
      # One collection's channel facts.
      Collection = Data.define(:slug, :label, :shared_name, :zips_folder, :root_sidecars)

      # The parent's constants, re-bound here: an unqualified name in this
      # body resolves LEXICALLY first (Nabu::Error would shadow the
      # parent's Error), so each one this class uses is named explicitly.
      Error = Nabu::EeboTcpFetch::Error
      Result = Nabu::EeboTcpFetch::Result
      BASE_URL = Nabu::EeboTcpFetch::BASE_URL
      DELAY = Nabu::EeboTcpFetch::DELAY
      TEXTS_DIR = Nabu::EeboTcpFetch::TEXTS_DIR
      MAX_ATTEMPTS = Nabu::EeboTcpFetch::MAX_ATTEMPTS
      RETRIABLE_STATUSES = Nabu::EeboTcpFetch::RETRIABLE_STATUSES

      CLASSES = %w[released unedited].freeze

      # The zip-name marker of the unedited class (upstream's own naming).
      UNEDITED_MARKER = "unedited"

      def self.collection
        raise NotImplementedError, "#{self} must name its Collection"
      end

      def self.shared_url(base_url = BASE_URL)
        "#{base_url}/s/#{collection.shared_name}"
      end

      def self.download_url(base_url, file_id)
        "#{base_url}/index.php?rm=box_v2_download_shared_file&shared_name=#{collection.shared_name}" \
          "&file_id=f_#{file_id}"
      end

      def self.state_file = ".#{collection.slug}-fetch.json"

      def self.user_agent
        "nabu/#{Nabu::VERSION} (personal research corpus; #{collection.label} — CC0 public-domain " \
          "corpus from the TCP Box folder; +https://github.com/arvicco/nabu; contact: arvicco@nabu.ac)"
      end

      def self.class_of(zip_name) = zip_name.include?(UNEDITED_MARKER) ? "unedited" : "released"

      # Is +relpath+ a corpus text ("texts/<class>/<stem>/<name>.xml")?
      def self.record?(relpath)
        parts = relpath.split("/")
        parts.size == 4 && parts.first == TEXTS_DIR && CLASSES.include?(parts[1]) &&
          parts.last.end_with?(".xml") && !parts.last.start_with?(".")
      end

      # The parent's choreography with +classes+ in place of +phases+.
      def self.sync!(dir:, attic_dir:, classes:, base_url: BASE_URL, http: ZipFetch.default_http,
                     delay: DELAY, progress: nil, guard: nil)
        fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir, classes: classes,
                    http: http, delay: delay, progress: progress)
        fetch.prepare!
        guard&.call(fetch.doomed_paths)
        fetch.complete!(guard: guard)
        Result.new(sha: fetch.sha, atticked: fetch.atticked, zips_listed: fetch.zips_listed,
                   zips_fetched: fetch.zips_fetched, zips_cached: fetch.zips_cached,
                   texts: fetch.texts, phases: fetch.phases)
      end

      def initialize(base_url:, dir:, attic_dir:, classes:, http: ZipFetch.default_http,
                     delay: DELAY, progress: nil)
        unknown = classes - CLASSES
        unless unknown.empty?
          raise ArgumentError, "unknown #{self.class.collection.label} classes #{unknown.inspect} " \
                               "(known: #{CLASSES.join(', ')})"
        end

        super(base_url: base_url, dir: dir, attic_dir: attic_dir, phases: [], http: http,
              delay: delay, progress: relabeled(progress))
        @phases = CLASSES & classes # canonical order; the parent's per-"phase" ledger keys
      end

      # The listing walk only: the root (sidecars + the P4 folder), then the
      # P4 folder's zips, each assigned its class by name; out-of-scope
      # classes are invisible.
      def prepare!
        collection = self.class.collection
        root = folder_listing(nil, label: "#{collection.slug} root")
        collection.root_sidecars.each do |name|
          item = find_item(root, "file", name) or
            raise Error, "the Box root listing no longer names #{name} — the folder shape moved upstream"
          @sidecar_plan << { "name" => name, "file_id" => item["id"].to_s }
        end
        plan_class_zips!(root, collection.zips_folder)
        @doomed = doomed_relpaths
      end

      private

      def plan_class_zips!(root, folder_name)
        folder = find_item(root, "folder", folder_name) or
          raise Error, "the Box root listing has no #{folder_name} folder — the folder shape moved upstream"
        zips = folder_listing(folder["id"], label: folder_name)
               .select { |item| item["type"] == "file" && item["name"].end_with?(".zip") }
        zips.sort_by { |item| item["name"] }.each do |item|
          klass = self.class.class_of(item["name"])
          next unless @phases.include?(klass)

          @plan << { "phase" => klass, "name" => item["name"], "file_id" => item["id"].to_s,
                     "listed_size" => item["itemSize"], "content_updated" => item["contentUpdated"] }
        end
        missing = @phases - @plan.map { |zip| zip["phase"] }
        return if missing.empty?

        raise Error, "#{folder_name} lists no #{missing.join('/')} zip — an outage page or a folder " \
                     "reshape; abort before any write"
      end

      # The parent's progress lines name eebo-tcp; this collection's own
      # slug reads instead (the lines are otherwise the parent's).
      def relabeled(progress)
        return nil unless progress

        slug = self.class.collection.slug
        ->(line) { progress.call(line.sub(/\Aeebo-tcp /, "#{slug} ")) }
      end

      # The parent's GET-with-retry, carrying this collection's own
      # User-Agent.
      def get_with_retry(url, label:)
        attempt = 0
        begin
          attempt += 1
          pause
          response = begin
            RedirectFollow.get(url, http: @http, error: TransportError,
                                    headers: { "User-Agent" => self.class.user_agent },
                                    accept: [200, *RETRIABLE_STATUSES]).first
          rescue TransportError => e
            raise RetryableError, e.message
          end
          raise RetryableError, "HTTP #{response.status} for #{url}" unless response.status == 200

          response.body.to_s
        rescue RetryableError => e
          raise Error, "#{e.message} (#{label}; after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

          sleep(@delay * (2**attempt)) if @delay.positive?
          retry
        end
      end

      # Internal markers; never escape get_with_retry.
      class RetryableError < StandardError; end
      class TransportError < StandardError; end
      private_constant :RetryableError, :TransportError

      def write_state!
        census = @phases.to_h do |klass|
          rows = @zips.select { |key, _row| key.start_with?("#{klass}/") }.values
          [klass, { "zips" => rows.size, "texts" => rows.sum { |row| row["texts"].to_i } }]
        end
        state = { "url" => self.class.shared_url(@base_url), "fetched_at" => Time.now.utc.iso8601,
                  "classes" => @phases, "sha256" => @sha,
                  "zips" => @zips, "sidecars" => @sidecars, "census" => census,
                  "zips_fetched" => @zips_fetched, "zips_cached" => @zips_cached }
        File.write(File.join(@dir, self.class.state_file), JSON.pretty_generate(state))
      end

      def previous_state
        path = File.join(@dir, self.class.state_file)
        return {} unless File.file?(path)

        JSON.load_file(path)
      rescue JSON::ParserError
        {}
      end
    end
  end
end
