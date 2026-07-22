# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"
require "faraday"

require_relative "redirect_follow"

module Nabu
  # Session-based REST fetch for the CLARINO INESS portal (P40-2; architecture
  # §8) — the fetch shape for an upstream that is neither a git repo nor a
  # static file tree but an EPHEMERAL-SESSION API. Menotec (Old Norwegian
  # treebanks + the Poetic Edda / Codex Regius) is served ONLY through
  # clarino.uib.no/iness/rest, whose download URLs carry a short-lived
  # session-id, so no raw GET reproduces the bytes and neither GitFetch nor
  # FileFetch/SefariaFetch applies. This class composes the same retention
  # discipline into the documented anonymous flow:
  #
  #   1. get-session -> {"sessionId" => "<digits>"} (ephemeral; threaded into
  #      every later call).
  #   2. list-resources&details=true -> {"resources" => [...], "languages" =>
  #      [...], "collections" => [...]}; each resources entry keys on "name"
  #      (`{"name" => "non-edda-regius-dep", "type" => "dependency",
  #      "languages" => ["non"], "collections" => ["Menotec"], "size" => N,
  #      …}`). Every CONFIGURED treebank must be present BY NAME (a missing one
  #      is a loud Error — the scope the adapter declares no longer matches
  #      upstream); the matched entry's type/languages/collections/size are
  #      carried into the ledger truly shaped.
  #   3. per treebank, get-treebank-documents -> its document list (chapters /
  #      poems).
  #   4. per (treebank, document), get-sentences -> the native PROIEL-XML
  #      per-sentence stream at `sentences.data`, written VERBATIM to
  #      <dir>/<treebank>/<document>.xml (canonical is what upstream serves).
  #
  # == Pinning (the non-git ledger mold)
  #
  # INESS exposes no commit sha. The FetchReport pin is instead an AGGREGATE
  # sha256 over the fetched (relpath, body-sha) set — a reproducible content
  # pin (a byte-identical re-sync mints the identical sha). The ledger
  # (.iness-fetch.json) records the SESSION DATE, the per-treebank resource
  # metadata, and each file's sha256 — the reproducibility artifact, sibling to
  # SefariaFetch's index pin and the Kanripo ledger.
  #
  # == Deletion semantics (attic, per the house contract)
  #
  # Re-sync = re-fetch + diff. A document (or a whole treebank) that upstream
  # stops serving is DOOMED — a previously-written canonical .xml no longer in
  # the freshly-fetched set. Exactly as FileFetch/SefariaFetch: the version
  # files are staged in memory before any write (a mid-flight HTTP failure
  # leaves the tree byte-unchanged), the caller's guard runs on the would-be
  # deletions BEFORE the tree mutates (raising aborts with the tree
  # byte-unchanged), and the doomed files are preserved under the attic with a
  # GitFetch-format manifest (first copy wins; the manifest records the pin the
  # file vanished at).
  #
  # == Loud on surprises — and self-diagnosing (P40-i1)
  #
  # A missing sessionId, a malformed JSON envelope, a configured treebank
  # absent from list-resources, a document entry without an id, a missing
  # sentences.data payload, any non-200 status — all raise InessFetch::Error
  # (adapters wrap it in Nabu::FetchError), and every SHAPE error appends the
  # actual top-level keys + a truncated body sample (#shape_hint), so a live
  # divergence diagnoses itself from the error text alone. Evidence status:
  # get-sentences (`sentences.data`), get-session (`sessionId`) and the
  # list-resources envelope are EVIDENCED by captured real responses (the
  # list-resources capture landed at the P40-i1 incident, 2026-07-22, after
  # the original reconstruction guessed an "id" key where upstream sends
  # "name" — the real trim rides in test/fixtures/menotec/).
  # get-treebank-documents is evidenced too since P40-i2 (same day): its
  # reconstruction ALSO guessed "id"; the shape_hint diagnostics caught the
  # real key LIVE on the owner sync — keys ["documentId", "title"], title
  # often null. All four envelopes carry evidence now; the dumps stay,
  # because upstream can still drift.
  class InessFetch
    # HTTP-level failure or a malformed/inconsistent API response. Adapters
    # wrap it in Nabu::FetchError.
    class Error < Nabu::Error; end

    LEDGER_FILE = ".iness-fetch.json"

    # The resource-entry fields carried into the ledger, truly shaped (the
    # captured envelope: type a string, languages/collections arrays, size a
    # sentence count).
    # const: the ledger's metadata field selection (a design choice over the
    # captured envelope), not a corpus census
    RESOURCE_METADATA_KEYS = %w[type languages collections size].freeze
    private_constant :RESOURCE_METADATA_KEYS

    # What one completed sync did: the aggregate content pin, the session date
    # (the non-git pin analogue), the treebanks fetched (sorted), how many
    # documents were written, and the relpaths newly copied into the attic.
    Result = Data.define(:sha, :session_date, :treebanks, :documents, :atticked)

    # The shared cert-hardened Faraday connection (ZipFetch's, by reference).
    def self.default_http
      ZipFetch.default_http
    end

    # One-shot sync. +treebanks+ is the configured resource scope (the adapter's
    # treebank list). +guard+, when given, receives the absolute live-tree paths
    # this sync would delete — BEFORE any tree mutation — and may raise
    # (Nabu::SyncAborted) to abort.
    def self.sync!(base_url:, dir:, attic_dir:, treebanks:, http: default_http, progress: nil, guard: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir,
                  treebanks: treebanks, http: http, progress: progress)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, session_date: fetch.session_date,
                 treebanks: fetch.treebanks, documents: fetch.documents, atticked: fetch.atticked)
    end

    def initialize(base_url:, dir:, attic_dir:, treebanks:, http: self.class.default_http, progress: nil)
      @base_url = base_url
      @dir = dir
      @attic_dir = attic_dir
      @treebanks = treebanks.uniq.sort
      @http = http
      @progress = progress
      @staged = {}
      @resources = {}
      @doomed_relpaths = []
      @atticked = []
    end

    attr_reader :sha, :atticked, :session_date

    # The treebanks fetched (sorted) and the number of documents written.
    attr_reader :treebanks

    def documents = @staged.size

    # Phase 1 — walk the session flow, stage every document body in memory,
    # compute the pin and the doomed set. The live tree is untouched.
    def prepare!
      session_id = fetch_session!
      @resources = fetch_resources!(session_id)
      @treebanks.each do |treebank|
        used = {}
        fetch_documents!(session_id, treebank).each do |document|
          body = fetch_sentences!(session_id, treebank, document)
          @staged["#{treebank}/#{unique_filename(used, document)}"] = body
        end
      end
      @sha = aggregate_sha(@staged)
      @doomed_relpaths = live_relpaths - @staged.keys
    end

    # Absolute live-tree paths this sync would delete: previously fetched
    # documents no longer served upstream. Empty on a fresh sync and on every
    # ordinary unchanged re-sync.
    def doomed_paths
      @doomed_relpaths.map { |rel| File.join(@dir, rel) }
    end

    # Phase 2 — attic the doomed files, land the staged tree, delete the
    # doomed, pin the ledger.
    def complete!
      @session_date = Time.now.utc.iso8601
      attic_doomed!
      write_tree!
      @doomed_relpaths.each { |rel| FileUtils.rm_f(File.join(@dir, rel)) }
      write_ledger!
    end

    private

    # -- the session flow ------------------------------------------------------

    def fetch_session!
      body = get(command: "get-session")
      id = body["sessionId"]
      return id if id.is_a?(String) && !id.empty?

      raise Error, "#{@base_url}: get-session returned no sessionId — #{shape_hint(body)}"
    end

    # list-resources -> { treebank => resource metadata } for the configured
    # scope. The captured envelope (P40-i1) keys each resources entry on
    # "name" — NOT "id", the original reconstruction's wrong guess. A
    # configured treebank the portal does not offer BY NAME is a loud Error.
    def fetch_resources!(session_id)
      body = get(command: "list-resources", session_id: session_id,
                 extra: { "details" => "true", "project" => "iness" })
      list = body["resources"]
      raise Error, "#{@base_url}: list-resources carried no resources array — #{shape_hint(body)}" unless
        list.is_a?(Array)

      by_name = list.each_with_object({}) { |entry, map| map[entry["name"]] = entry if entry.is_a?(Hash) }
      @treebanks.to_h do |treebank|
        entry = by_name[treebank]
        if entry.nil?
          raise Error, "#{@base_url}: configured treebank #{treebank.inspect} is not offered by INESS " \
                       "(the resource scope no longer matches upstream; matching keys on \"name\" across " \
                       "#{list.size} resources — #{shape_hint(list.first)})"
        end

        [treebank, entry.slice(*RESOURCE_METADATA_KEYS)]
      end
    end

    def fetch_documents!(session_id, treebank)
      body = get(command: "get-treebank-documents", session_id: session_id,
                 extra: { "type" => "dependency", "treebank" => treebank })
      list = body["documents"]
      unless list.is_a?(Array)
        raise Error, "#{@base_url}: get-treebank-documents(#{treebank}) carried no documents array — " \
                     "#{shape_hint(body)}"
      end

      list.map do |entry|
        id = entry.is_a?(Hash) ? entry["documentId"] : nil
        unless id.is_a?(String) && !id.empty?
          raise Error, "#{@base_url}: get-treebank-documents(#{treebank}) has a document without a documentId — " \
                       "#{shape_hint(entry)}"
        end

        id
      end
    end

    def fetch_sentences!(session_id, treebank, document)
      body = get(command: "get-sentences", session_id: session_id,
                 extra: { "mode" => "text", "download-mode" => "tiger-xml",
                          "type" => "dependency", "treebank" => treebank, "document-id" => document })
      data = body.dig("sentences", "data")
      return data if data.is_a?(String) && !data.empty?

      raise Error, "#{@base_url}: get-sentences(#{treebank}/#{document}) carried no sentences.data " \
                   "payload — #{shape_hint(body)}"
    end

    # The P40-i1 self-diagnosis contract: every shape error appends what
    # upstream ACTUALLY sent — the top-level keys plus a truncated JSON sample
    # — so the next live envelope divergence (get-treebank-documents is still
    # reconstructed-from-flow) diagnoses itself from the error text alone.
    def shape_hint(body)
      keys = body.is_a?(Hash) ? "keys #{body.keys.inspect}" : body.class.name
      sample = JSON.generate(body)[0, 300]
      "actual shape: #{keys}, sample #{sample}"
    end

    # -- HTTP ------------------------------------------------------------------

    def get(command:, session_id: nil, extra: {})
      params = { "command" => command }
      params["session-id"] = session_id if session_id
      params.merge!(extra)
      url = "#{@base_url}?#{URI.encode_www_form(params)}"
      @progress&.call("INESS #{command}…\n")
      response, = RedirectFollow.get(url, http: @http, error: Error, accept: [200])
      parse_json(response.body.to_s)
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Error, "#{@base_url}: malformed JSON response: #{e.message}"
    end

    # -- filenames -------------------------------------------------------------

    # A filesystem-safe, deterministic filename for one upstream document id.
    # Path separators collapse to "-", whitespace runs to "-", NFC preserved
    # (Alvíssmál stays Alvíssmál); a within-treebank collision gets a numeric
    # suffix in document-list order (stable across re-syncs).
    def unique_filename(used, document)
      base = Normalize.nfc(document.to_s).gsub(%r{[/\\]+}, "-").strip.gsub(/\s+/, "-")
      base = "document" if base.empty?
      name = "#{base}.xml"
      if used.key?(name)
        used[name] += 1
        name = "#{base}-#{used[name]}.xml"
      end
      used[name] ||= 1
      name
    end

    # -- staging / landing -----------------------------------------------------

    def aggregate_sha(staged)
      lines = staged.keys.sort.map { |rel| "#{rel}\0#{Digest::SHA256.hexdigest(staged[rel])}" }
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def write_tree!
      @staged.each do |rel, body|
        path = File.join(@dir, rel)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, body)
      end
    end

    def write_ledger!
      files = @staged.keys.sort.to_h do |rel|
        [rel, { "sha256" => Digest::SHA256.hexdigest(@staged[rel]) }]
      end
      ledger = {
        "session" => { "base_url" => @base_url, "fetched_at" => @session_date, "pin" => @sha },
        "resources" => @resources,
        "files" => files
      }
      FileUtils.mkdir_p(@dir)
      File.write(File.join(@dir, LEDGER_FILE), JSON.pretty_generate(ledger))
    end

    # Live canonical documents this sync could delete: every *.xml under +dir+
    # except (when nested inside) the attic. The ledger is not an .xml file.
    def live_relpaths
      return [] unless Dir.exist?(@dir)

      attic_prefix = attic_relprefix
      Dir.glob("**/*.xml", base: @dir)
         .select { |rel| File.file?(File.join(@dir, rel)) }
         .reject { |rel| attic_prefix && rel.start_with?(attic_prefix) }
    end

    def attic_relprefix
      dir = File.expand_path(@dir)
      attic = File.expand_path(@attic_dir)
      return nil unless attic.start_with?("#{dir}#{File::SEPARATOR}")

      "#{attic.delete_prefix("#{dir}#{File::SEPARATOR}")}#{File::SEPARATOR}"
    end

    # First copy wins — the document as first scrapped is the retained asset —
    # and the manifest records the pin each file vanished at (first record wins
    # too), in GitFetch's exact format so the adapter base class's attic
    # rediscovery reads it generically.
    def attic_doomed!
      @doomed_relpaths.each do |rel|
        source = File.join(@dir, rel)
        destination = File.join(@attic_dir, rel)
        next unless File.file?(source)
        next if File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << rel
      end
      record_manifest! unless @atticked.empty?
    end

    def record_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      @atticked.each { |rel| manifest[rel] ||= @sha } # first record wins
      File.write(path, JSON.pretty_generate(manifest))
    end
  end
end
