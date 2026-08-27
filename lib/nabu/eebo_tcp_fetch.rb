# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "faraday"

require_relative "redirect_follow"
require_relative "zip_fetch"
require_relative "git_fetch"
require_relative "version"

module Nabu
  # Box shared-folder acquisition for EEBO-TCP (P83-1; architecture §8) —
  # the TCP's own institutional Box folder ("eebo_all", shared link
  # /s/jjzmnrx98dkvanipopz3nxkvymnjccht) serving both phases of the corpus
  # as P4 XML zips, uniformly CC0 (channel verified 2026-08-26):
  #
  #   eebo_all/
  #     eebo_phase1/P4_XML_TCP/{A0..A9,B0,B2,B3}.zip        13 zips ≈1.73 GB
  #     eebo_phase1/{IDnos_in_phase1,eebo_phase1_IDs_and_dates}.txt
  #     eebo_phase2/P4_XML_TCP_Ph2/{A0..A9,B0..B4}.zip      15 zips ≈1.57 GB
  #     eebo_phase2/{IDnos_in_phase2,EEBO_Phase2_IDs_and_dates}.txt
  #     eebo2prf.xml.dtd                                    the schema
  #
  # Each zip carries one top-level directory named for its stem (A9.zip →
  # A9/<TCPID>.P4.xml), so units unpack to texts/<phase>/<stem>/ — the
  # phase prefix is load-bearing: BOTH phases ship an A2.zip whose inner
  # dir is A2/, and a flat merge would lose the zip↔file ledger mapping.
  #
  # == The listing: server-side Box.postStreamData JSON
  #
  # A shared-folder page embeds its full item listing in a server-side
  # `Box.postStreamData` JSON blob (no API token needed); folders resolve
  # BY NAME from that JSON — never by pinned folder ids, which are Box
  # infrastructure, not upstream identity. `pageCount` is honored (a
  # listing page names it; today every folder is one page) and per-zip
  # downloads ride the box_v2_download_shared_file endpoint (verified live
  # 2026-08-26: byte counts exactly match the listing's itemSize claims).
  #
  # == Wave scoping (№R-43, ruled 2026-08-26: wave 1 = Phase I whole)
  #
  # +phases+ scopes the acquisition (the kanripo `classes:` mold): the
  # ruled wave — and the stated both-phases follow-on — land as
  # sources.yml edits, never a code change. Out-of-scope phases are
  # INVISIBLE — never listed, never doomed, never deleted: scoping down
  # is not an upstream deletion.
  #
  # == Two-grain resumability (the corpus-corporum mold, zip-grain)
  #
  # - zip grain: a zip whose ledger row still matches the listing's own
  #   claims (itemSize + contentUpdated) with its unit dir on disk is
  #   skipped with ZERO requests — the steady-state re-sync costs ~5
  #   listing GETs total (TCP releases move in rare waves);
  # - member grain: a changed zip re-downloads through Nabu::ZipFetch
  #   (streamed body, staged unpack, tmp-discipline), whose staging diff
  #   attics upstream-vanished members (GitFetch manifest shape) behind
  #   the caller's mass-deletion guard — the house retention contract.
  #
  # A zip vanishing from the listing entirely dooms its whole unit dir:
  # guarded, atticked, then removed (the cme/derom posture).
  #
  # == Retention choreography (the house contract)
  #
  #   prepare!   the listing walk only (~5 GETs) — live tree untouched;
  #              doomed = unit dirs of zips the listing no longer names.
  #   [guard]    the caller's mass-deletion breaker; raising aborts with
  #              the tree byte-unchanged.
  #   complete!  attic+delete the doomed units, then per changed zip run
  #              the ZipFetch phases (each unit's member-grain doomed set
  #              guarded too), land the ID/date lists + DTD beside texts/
  #              (tmp+rename, previous differing copy atticked), pin the
  #              ledger (.eebo-tcp-fetch.json).
  class EeboTcpFetch
    # HTTP failure, a reshaped listing (no postStreamData / no zips), or a
    # broken zip. Adapters wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    STATE_FILE = ".eebo-tcp-fetch.json"

    # Where corpus texts land: texts/<phase>/<zip-stem>/<TCPID>.P4.xml.
    TEXTS_DIR = "texts"

    # The TCP Box folder's shared-link token (the channel; scout-verified
    # 2026-08-26). Not a secret — the folder is the TCP's public
    # distribution point.
    SHARED_NAME = "jjzmnrx98dkvanipopz3nxkvymnjccht"

    BASE_URL = "https://app.box.com"

    # The folder names each phase resolves through, and the per-phase ID
    # list sidecars that land beside texts/ (identity + TCP's own per-text
    # imprint years; kept verbatim under their upstream names).
    PHASES = {
      "phase1" => { "folder" => "eebo_phase1", "zips_folder" => "P4_XML_TCP",
                    "sidecars" => ["IDnos_in_phase1.txt", "eebo_phase1_IDs_and_dates.txt"].freeze }.freeze,
      "phase2" => { "folder" => "eebo_phase2", "zips_folder" => "P4_XML_TCP_Ph2",
                    "sidecars" => ["IDnos_in_phase2.txt", "EEBO_Phase2_IDs_and_dates.txt"].freeze }.freeze
    }.freeze

    # Root-level sidecars: the P4 schema itself.
    ROOT_SIDECARS = ["eebo2prf.xml.dtd"].freeze

    # Seconds between HTTP requests (sequential, polite — a full sync is
    # ~33 requests total: ~5 listings + 28 zips + 5 sidecars; pacing is
    # trivial at this request count, transfer time dominates).
    # const: crawl politeness pause, not a corpus claim
    DELAY = 1.0

    # const: retry ceiling, not a corpus claim
    MAX_ATTEMPTS = 3

    # const: HTTP semantics, not a corpus claim
    RETRIABLE_STATUSES = [500, 502, 503, 504].freeze

    USER_AGENT = "nabu/#{Nabu::VERSION} (personal research corpus; EEBO-TCP — CC0 public-domain " \
                 "corpus from the TCP Box folder; +https://github.com/arvicco/nabu; " \
                 "contact: arvicco@nabu.ac)".freeze

    Result = Data.define(:sha, :atticked, :zips_listed, :zips_fetched, :zips_cached,
                         :texts, :phases)

    def self.shared_url(base_url = BASE_URL)
      "#{base_url}/s/#{SHARED_NAME}"
    end

    def self.folder_url(base_url, folder_id, page: 1)
      url = "#{shared_url(base_url)}/folder/#{folder_id}"
      page > 1 ? "#{url}?page=#{page}" : url
    end

    def self.download_url(base_url, file_id)
      "#{base_url}/index.php?rm=box_v2_download_shared_file&shared_name=#{SHARED_NAME}&file_id=f_#{file_id}"
    end

    # Is +relpath+ a corpus text ("texts/<phase>/<stem>/<name>.xml")? The
    # ledger, the sidecars, the per-unit zip state files and the attic
    # never match.
    def self.record?(relpath)
      parts = relpath.split("/")
      parts.size == 4 && parts.first == TEXTS_DIR && PHASES.key?(parts[1]) &&
        parts.last.end_with?(".xml") && !parts.last.start_with?(".")
    end

    # One-shot choreography. +guard+ receives absolute doomed paths between
    # prepare! and complete! (whole-unit removals) AND before each changed
    # zip's tree swap (member-grain, via ZipFetch).
    def self.sync!(dir:, attic_dir:, phases:, base_url: BASE_URL, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir, phases: phases,
                  http: http, delay: delay, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!(guard: guard)
      Result.new(sha: fetch.sha, atticked: fetch.atticked, zips_listed: fetch.zips_listed,
                 zips_fetched: fetch.zips_fetched, zips_cached: fetch.zips_cached,
                 texts: fetch.texts, phases: fetch.phases)
    end

    def initialize(base_url:, dir:, attic_dir:, phases:, http: ZipFetch.default_http,
                   delay: DELAY, progress: nil)
      unknown = phases - PHASES.keys
      unless unknown.empty?
        raise ArgumentError, "unknown EEBO-TCP phases #{unknown.inspect} (known: #{PHASES.keys.join(', ')})"
      end

      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @phases = PHASES.keys & phases # canonical order
      @http = http
      @delay = delay
      @progress = progress
      @plan = [] # {"phase" =>, "name" =>, "file_id" =>, "listed_size" =>, "content_updated" =>}
      @sidecar_plan = [] # {"name" =>, "file_id" =>}
      @doomed = []
      @atticked = []
      @zips = {} # ledger rows, "phase/name" => row
      @sidecars = {}
      @zips_fetched = 0
      @zips_cached = 0
      @requests = 0
    end

    attr_reader :atticked, :sha, :zips_fetched, :zips_cached, :phases

    def zips_listed = @plan.size

    def texts = @zips.values.sum { |row| row["texts"].to_i }

    # Phase 1 — the listing walk only; live tree untouched. Resolves the
    # phase folders by name, plans every zip and sidecar, computes the
    # whole-unit doomed set (zips the listing no longer names).
    def prepare!
      root = folder_listing(nil, label: "eebo_all root")
      plan_root_sidecars!(root)
      @phases.each { |phase| plan_phase!(root, phase) }
      @doomed = doomed_relpaths
    end

    # Absolute live-tree text files whose zip vanished from the listing.
    def doomed_paths
      @doomed.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic+delete the vanished units, sync each zip (skip-if-
    # unchanged), land the sidecars, pin the ledger.
    def complete!(guard: nil)
      attic_doomed!
      @doomed.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      prune_empty_unit_dirs!
      previous = previous_state
      @plan.each { |zip| sync_zip!(zip, previous: previous, guard: guard) }
      @sidecar_plan.each { |sidecar| sync_sidecar!(sidecar) }
      @sha = aggregate_sha
      write_state!
    end

    private

    # -- the listing walk -------------------------------------------------------

    def plan_root_sidecars!(root)
      ROOT_SIDECARS.each do |name|
        item = find_item(root, "file", name) or
          raise Error, "the Box root listing no longer names #{name} — the folder shape moved upstream"
        @sidecar_plan << { "name" => name, "file_id" => item["id"].to_s }
      end
    end

    def plan_phase!(root, phase)
      spec = PHASES.fetch(phase)
      phase_folder = find_item(root, "folder", spec["folder"]) or
        raise Error, "the Box root listing has no #{spec['folder']} folder — the folder shape moved upstream"
      listing = folder_listing(phase_folder["id"], label: spec["folder"])
      spec["sidecars"].each do |name|
        item = find_item(listing, "file", name) or
          raise Error, "#{spec['folder']} no longer names #{name} — the folder shape moved upstream"
        @sidecar_plan << { "name" => name, "file_id" => item["id"].to_s }
      end
      plan_zips!(listing, phase, spec)
    end

    def plan_zips!(phase_listing, phase, spec)
      zips_folder = find_item(phase_listing, "folder", spec["zips_folder"]) or
        raise Error, "#{spec['folder']} has no #{spec['zips_folder']} folder — the folder shape moved upstream"
      listing = folder_listing(zips_folder["id"], label: spec["zips_folder"])
      zips = listing.select { |item| item["type"] == "file" && item["name"].end_with?(".zip") }
      if zips.empty?
        raise Error, "#{spec['zips_folder']} lists no zips — an outage page or a folder reshape; " \
                     "abort before any write"
      end

      zips.sort_by { |item| item["name"] }.each do |item|
        @plan << { "phase" => phase, "name" => item["name"], "file_id" => item["id"].to_s,
                   "listed_size" => item["itemSize"], "content_updated" => item["contentUpdated"] }
      end
    end

    def find_item(items, type, name)
      items.find { |item| item["type"] == type && item["name"] == name }
    end

    # All items of one folder, every page (`pageCount` is the listing's own
    # claim; today each folder is one page).
    def folder_listing(folder_id, label:)
      page = 1
      items = []
      loop do
        url = if folder_id
                self.class.folder_url(@base_url, folder_id, page: page)
              elsif page > 1
                "#{self.class.shared_url(@base_url)}?page=#{page}"
              else
                self.class.shared_url(@base_url)
              end
        @progress&.call("eebo-tcp listing #{label}#{" p#{page}" if page > 1}…\n")
        data = post_stream_data(get_with_retry(url, label: label), url: url)
        folder = data["/app-api/enduserapp/shared-folder"]
        raise Error, "#{url} carries no shared-folder listing — the page shape moved upstream" unless folder

        items.concat(Array(folder["items"]))
        break if page >= folder.fetch("pageCount", 1).to_i

        page += 1
      end
      items
    end

    # The server-side listing blob a Box shared-folder page embeds.
    def post_stream_data(body, url:)
      match = body.match(%r{Box\.postStreamData\s*=\s*(\{.*?\});?\s*</script>}m) or
        raise Error, "#{url} embeds no Box.postStreamData listing — an outage page or a Box reshape"
      JSON.parse(match[1])
    rescue JSON::ParserError => e
      raise Error, "#{url}: unparseable Box.postStreamData listing (#{e.message})"
    end

    # -- the zip units ----------------------------------------------------------

    def unit_reldir(zip)
      File.join(TEXTS_DIR, zip["phase"], File.basename(zip["name"], ".zip"))
    end

    def sync_zip!(zip, previous:, guard:)
      key = "#{zip['phase']}/#{zip['name']}"
      unit_dir = File.join(@dir, unit_reldir(zip))
      if (row = reusable_row(previous, key, zip, unit_dir))
        @zips[key] = row
        @zips_cached += 1
        return
      end

      @progress&.call("eebo-tcp zip #{key} (#{@zips_fetched + @zips_cached + 1}/#{@plan.size}, " \
                      "#{(zip['listed_size'].to_i / 1_048_576.0).round(1)} MB)…\n")
      result = zip_fetch!(zip, unit_dir, guard)
      texts = Dir.glob("*.xml", base: unit_dir).size
      @zips[key] = zip.merge("sha256" => result.sha, "texts" => texts)
      @zips_fetched += 1
      @atticked.concat(result.atticked.map { |rel| File.join(unit_reldir(zip), rel) })
    end

    # The zip-grain skip: the ledger row still matches the listing's own
    # size + contentUpdated claims and the unit is on disk — zero requests.
    def reusable_row(previous, key, zip, unit_dir)
      row = previous.dig("zips", key)
      return nil unless row && Dir.exist?(unit_dir)
      return nil unless row["listed_size"] == zip["listed_size"] &&
                        row["content_updated"] == zip["content_updated"]

      row.merge("file_id" => zip["file_id"])
    end

    # One changed zip through the ZipFetch phases (streamed download,
    # staged unpack, member-grain doomed guarded, attic, tree swap).
    def zip_fetch!(zip, unit_dir, guard)
      pause
      fetch = ZipFetch.new(url: self.class.download_url(@base_url, zip["file_id"]),
                           dir: unit_dir, attic_dir: File.join(@attic_dir, unit_reldir(zip)),
                           http: @http, progress: @progress, stream: true)
      begin
        fetch.prepare!
        guard&.call(fetch.doomed_paths)
        fetch.complete!
      ensure
        fetch.cleanup!
      end
      fetch
    rescue ZipFetch::Error, Shell::Error, ZipReader::Error => e
      raise Error, "#{zip['phase']}/#{zip['name']}: #{e.message}"
    end

    # -- sidecars ---------------------------------------------------------------

    # ID/date lists + the DTD land verbatim-named beside texts/ (tmp+rename);
    # a differing previous copy is atticked first (first copy wins).
    def sync_sidecar!(sidecar)
      name = sidecar["name"]
      target = File.join(@dir, name)
      pause
      @progress&.call("eebo-tcp sidecar #{name}…\n")
      body = get_with_retry(self.class.download_url(@base_url, sidecar["file_id"]), label: name)
      attic_replaced!(name, body) if File.file?(target)
      File.binwrite("#{target}.tmp", body.b)
      File.rename("#{target}.tmp", target)
      @sidecars[name] = sidecar.merge("sha256" => Digest::SHA256.hexdigest(body.b))
    end

    def attic_replaced!(name, body)
      source = File.join(@dir, name)
      return if Digest::SHA256.file(source).hexdigest == Digest::SHA256.hexdigest(body.b)

      destination = File.join(@attic_dir, name)
      return if File.exist?(destination)

      FileUtils.mkdir_p(File.dirname(destination))
      FileUtils.cp(source, destination)
      @atticked << name
      record_attic_manifest!([name])
    end

    # -- HTTP -------------------------------------------------------------------

    def get_with_retry(url, label:)
      attempt = 0
      begin
        attempt += 1
        pause
        response = begin
          RedirectFollow.get(url, http: @http, error: TransportFailure,
                                  headers: { "User-Agent" => USER_AGENT },
                                  accept: [200, *RETRIABLE_STATUSES]).first
        rescue TransportFailure => e
          raise RetriableFailure, e.message
        end
        raise RetriableFailure, "HTTP #{response.status} for #{url}" unless response.status == 200

        response.body.to_s
      rescue RetriableFailure => e
        raise Error, "#{e.message} (#{label}; after #{MAX_ATTEMPTS} attempts)" if attempt >= MAX_ATTEMPTS

        sleep(@delay * (2**attempt)) if @delay.positive?
        retry
      end
    end

    # Internal markers; never escape get_with_retry.
    class RetriableFailure < StandardError; end
    class TransportFailure < StandardError; end
    private_constant :RetriableFailure, :TransportFailure

    def pause
      sleep(@delay) if @delay.positive? && @requests.positive?
      @requests += 1
    end

    # -- ledger -----------------------------------------------------------------

    # Content pin: sorted (key, sha) lines over the per-zip body shas and
    # sidecar shas — what this sync holds, reproducible without hashing
    # 10 GB of unpacked members (each zip sha covers its members).
    def aggregate_sha
      lines = @zips.sort.map { |key, row| "#{key}\0#{row['sha256']}" } +
              @sidecars.sort.map { |name, row| "#{name}\0#{row['sha256']}" }
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_state!
      census = @phases.to_h do |phase|
        rows = @zips.select { |key, _row| key.start_with?("#{phase}/") }.values
        [phase, { "zips" => rows.size, "texts" => rows.sum { |row| row["texts"].to_i } }]
      end
      state = { "url" => self.class.shared_url(@base_url), "fetched_at" => Time.now.utc.iso8601,
                "phases" => @phases, "sha256" => @sha,
                "zips" => @zips, "sidecars" => @sidecars, "census" => census,
                "zips_fetched" => @zips_fetched, "zips_cached" => @zips_cached }
      File.write(File.join(@dir, STATE_FILE), JSON.pretty_generate(state))
    end

    def previous_state
      path = File.join(@dir, STATE_FILE)
      return {} unless File.file?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    # -- retention --------------------------------------------------------------

    # On-disk text files under a SCOPED phase whose zip the listing no
    # longer names. Out-of-scope phases are invisible (class note); the
    # per-unit ZipFetch state file rides with its unit.
    def doomed_relpaths
      listed = @plan.to_set { |zip| unit_reldir(zip) }
      @phases.flat_map do |phase|
        phase_dir = File.join(@dir, TEXTS_DIR, phase)
        next [] unless Dir.exist?(phase_dir)

        Dir.children(phase_dir).sort.flat_map do |stem|
          rel = File.join(TEXTS_DIR, phase, stem)
          next [] if listed.include?(rel) || !File.directory?(File.join(@dir, rel))

          Dir.glob("**/*", base: File.join(@dir, rel))
             .select { |inner| File.file?(File.join(@dir, rel, inner)) }
             .map { |inner| File.join(rel, inner) }
        end
      end
    end

    # Vanished-unit files copy into the attic before deletion (first copy
    # wins; GitFetch manifest shape so the adapter base rediscovers them).
    def attic_doomed!
      fresh = []
      @doomed.each do |rel|
        source = File.join(@dir, rel)
        destination = File.join(@attic_dir, rel)
        next unless File.file?(source)
        next if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        fresh << rel
      end
      @atticked.concat(fresh)
      record_attic_manifest!(fresh) unless fresh.empty?
    end

    def prune_empty_unit_dirs!
      @doomed.map { |rel| File.dirname(File.join(@dir, rel)) }.uniq.each do |dir|
        FileUtils.rmdir(dir) if Dir.exist?(dir) && Dir.empty?(dir)
      end
    end

    def record_attic_manifest!(rels)
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      pin = previous_state["sha256"] || "pre-#{Time.now.utc.iso8601}"
      rels.each { |rel| manifest[rel] ||= pin } # first record wins
      File.write(path, JSON.pretty_generate(manifest))
    end
  end
end
