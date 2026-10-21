# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"
require "uri"
require "faraday"

require_relative "redirect_follow"

module Nabu
  # Paged harvest of whole corpora through an anonymous Korp JSON API (the
  # Språkbanken/FIN-CLARIN concordance backend; architecture §8) — the
  # fetch shape for an upstream that serves NO bulk file, only a
  # concordance endpoint. Kielipankki's Korp answers anonymous queries on
  # its public (PUB) corpora; this class reads each configured corpus
  # sentence by sentence and lands one JSONL file per upstream text.
  #
  #   1. corpus_info?corpus=A,B,… — every configured corpus must be
  #      present (a missing one is a loud Error: the scope the adapter
  #      declares no longer matches upstream); its info.Sentences is the
  #      paging total and its info block is carried into the ledger.
  #   2. per corpus, query?cqp=<sentence> [] with default_context
  #      "1 sentence": every hit is the first token of one sentence and its
  #      kwic row carries the WHOLE sentence plus the requested structural
  #      attributes — paged start/end, +page_size+ sentences per request,
  #      corpus order. The hit total must equal info.Sentences (a mismatch
  #      is an Error, never a silently short corpus).
  #   3. each row lands, in corpus order, as one JSON line in
  #      texts/<CORPUS>/<text-file-stem>.jsonl (grouped by the structural
  #      attribute +text_key+): {"structs": {…verbatim…}, "tokens":
  #      [[word, attr2, attr3 …], …]} — the row's token objects repacked as
  #      positional arrays in +attrs+ order, an attribute equal to the
  #      first one stored as null (a lossless repacking: the kwic row is
  #      recomputable from the line).
  #
  # == Pinning, deletion, attic (the InessFetch mold)
  #
  # No commit sha exists: the pin is an aggregate sha256 over the landed
  # (relpath, body-sha) set. Staged files are written under a staging dir
  # first (a mid-flight failure leaves the live tree untouched); the
  # caller's guard sees the would-be deletions (texts upstream stopped
  # serving) BEFORE the tree mutates; doomed files are preserved under the
  # attic with a GitFetch-format manifest; the ledger (.korp-fetch.json)
  # records the corpus_info blocks, the fetch time and every file's sha.
  #
  # == Progress
  #
  # One progress line per page ("VKS_BIBLIA 12000/57447 sentences, 1.4 s")
  # so a long harvest is readable while it runs.
  class KorpFetch
    # HTTP failure or a malformed/inconsistent API response. Adapters wrap
    # it in Nabu::FetchError.
    class Error < Nabu::Error; end

    LEDGER_FILE = ".korp-fetch.json"
    TEXTS_DIR = "texts"
    STAGING_DIR = ".korp-staging"
    DEFAULT_PAGE_SIZE = 1000

    Result = Data.define(:sha, :fetched_at, :corpora, :sentences, :texts, :atticked)

    def self.default_http
      ZipFetch.default_http
    end

    # One-shot sync; see the class comment. +pause+ seconds between page
    # requests (politeness; tests pass 0).
    def self.sync!(base_url:, dir:, attic_dir:, corpora:, attrs:, structs:, text_key:, http: default_http,
                   progress: nil, guard: nil, page_size: DEFAULT_PAGE_SIZE, pause: 0.5, sleeper: nil)
      fetch = new(base_url: base_url, dir: dir, attic_dir: attic_dir, corpora: corpora, attrs: attrs,
                  structs: structs, text_key: text_key, http: http, progress: progress,
                  page_size: page_size, pause: pause, sleeper: sleeper)
      fetch.prepare!
      guard&.call(fetch.doomed_paths)
      fetch.complete!
      Result.new(sha: fetch.sha, fetched_at: fetch.fetched_at, corpora: fetch.corpora,
                 sentences: fetch.sentences, texts: fetch.texts, atticked: fetch.atticked)
    end

    def initialize(base_url:, dir:, attic_dir:, corpora:, attrs:, structs:, text_key:,
                   http: self.class.default_http, progress: nil, page_size: DEFAULT_PAGE_SIZE,
                   pause: 0.5, sleeper: nil)
      @base_url = base_url.delete_suffix("/")
      @dir = dir
      @attic_dir = attic_dir
      @corpora = corpora.uniq.sort
      @attrs = attrs
      @structs = structs
      @text_key = text_key
      @http = http
      @progress = progress
      @page_size = page_size
      @pause = pause
      @sleeper = sleeper || ->(seconds) { Kernel.sleep(seconds) }
      @info = {}
      @sentences = 0
      @atticked = []
    end

    attr_reader :sha, :fetched_at, :corpora, :sentences, :atticked

    def texts = @staged_relpaths.size

    # Phase 1 — census, harvest every corpus into the staging dir, compute
    # the pin and the doomed set. The live texts/ tree is untouched.
    def prepare!
      @info = corpus_info!
      FileUtils.rm_rf(staging_root)
      begin
        @corpora.each { |corpus| harvest!(corpus) }
      rescue Error
        FileUtils.rm_rf(staging_root) # a failed harvest leaves no half-staged tree behind
        raise
      end
      @staged_relpaths = Dir.glob("**/*.jsonl", base: staging_root).sort
      @sha = aggregate_sha
      @doomed_relpaths = live_relpaths - @staged_relpaths
    end

    def doomed_paths
      @doomed_relpaths.map { |rel| File.join(texts_root, rel) }
    end

    # Phase 2 — attic the doomed, swap the staged tree in, pin the ledger.
    def complete!
      @fetched_at = Time.now.utc.iso8601
      attic_doomed!
      FileUtils.rm_rf(texts_root)
      FileUtils.mv(staging_root, texts_root)
      write_ledger!
    end

    private

    def texts_root = File.join(@dir, TEXTS_DIR)

    def staging_root = File.join(@dir, STAGING_DIR)

    # -- the census ------------------------------------------------------------

    def corpus_info!
      body = get("corpus_info", "corpus" => @corpora.join(","))
      blocks = body["corpora"]
      raise Error, "#{@base_url}: corpus_info carried no corpora object — #{shape_hint(body)}" unless
        blocks.is_a?(Hash)

      @corpora.to_h do |corpus|
        info = blocks.dig(corpus, "info")
        raise Error, "#{@base_url}: configured corpus #{corpus} is not served (corpus_info)" unless info.is_a?(Hash)

        [corpus, info]
      end
    end

    # -- the harvest -----------------------------------------------------------

    def harvest!(corpus)
      total = sentence_total(corpus)
      start = 0
      while start < total
        stop = [start + @page_size, total].min - 1
        began = Time.now
        rows = page(corpus, start, stop, total)
        land(corpus, rows)
        @sentences += rows.size
        @progress&.call("#{corpus} #{stop + 1}/#{total} sentences, #{(Time.now - began).round(1)} s\n")
        start = stop + 1
        @sleeper.call(@pause) if @pause.positive? && start < total
      end
    end

    def sentence_total(corpus)
      Integer(@info.dig(corpus, "Sentences").to_s, 10)
    rescue ArgumentError
      raise Error, "#{@base_url}: corpus_info for #{corpus} carries no integer Sentences count"
    end

    def page(corpus, start, stop, total)
      body = get("query", "corpus" => corpus, "cqp" => "<sentence> []", "start" => start.to_s,
                          "end" => stop.to_s, "default_context" => "1 sentence",
                          "show" => @attrs.join(","), "show_struct" => @structs.join(","))
      raise Error, "#{@base_url}: query(#{corpus}) error: #{body['ERROR']}" if body["ERROR"]

      rows = body["kwic"]
      raise Error, "#{@base_url}: query(#{corpus}) carried no kwic array — #{shape_hint(body)}" unless rows.is_a?(Array)
      unless body["hits"] == total
        raise Error, "#{@base_url}: query(#{corpus}) reports #{body['hits'].inspect} sentence hits, " \
                     "corpus_info says #{total}"
      end
      if rows.size != stop - start + 1
        raise Error, "#{@base_url}: query(#{corpus}) page #{start}–#{stop} returned #{rows.size} rows"
      end

      rows
    end

    # Append one page's rows to their texts' staged files (rows stay in
    # corpus order; a page spanning two texts appends to both).
    def land(corpus, rows)
      rows.chunk_while { |a, b| text_of(corpus, a) == text_of(corpus, b) }.each do |run|
        path = File.join(staging_root, corpus, "#{safe_stem(text_of(corpus, run.first))}.jsonl")
        FileUtils.mkdir_p(File.dirname(path))
        lines = run.map { |row| JSON.generate({ "structs" => row["structs"], "tokens" => repack(row["tokens"]) }) }
        File.open(path, "a") { |io| io.puts(lines) }
      end
    end

    def text_of(corpus, row)
      unless row.is_a?(Hash) && row["structs"].is_a?(Hash) && row["tokens"].is_a?(Array)
        raise Error, "#{@base_url}: a #{corpus} kwic row lacks structs/tokens — #{shape_hint(row)}"
      end

      key = row["structs"][@text_key].to_s
      raise Error, "#{@base_url}: a #{corpus} row has no #{@text_key}" if key.empty?

      key
    end

    def repack(tokens)
      tokens.map do |token|
        first = token[@attrs.first]
        @attrs.each_with_index.map { |attr, index| index.zero? || token[attr] != first ? token[attr] : nil }
      end
    end

    # The text file's stem, filesystem-safe ("agri1_abc1543.sen" →
    # "agri1_abc1543").
    def safe_stem(key)
      key.sub(/\.[A-Za-z]+\z/, "").gsub(%r{[/\\\s]+}, "-")
    end

    # -- HTTP --------------------------------------------------------------------

    def get(command, params)
      url = "#{@base_url}/#{command}?#{URI.encode_www_form(params)}"
      response, = RedirectFollow.get(url, http: @http, error: Error, accept: [200])
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError => e
      raise Error, "#{@base_url}/#{command}: malformed JSON response: #{e.message}"
    end

    def shape_hint(body)
      keys = body.is_a?(Hash) ? "keys #{body.keys.inspect}" : body.class.name
      "actual shape: #{keys}, sample #{JSON.generate(body)[0, 300]}"
    end

    # -- landing ---------------------------------------------------------------

    def aggregate_sha
      lines = @staged_relpaths.map do |rel|
        "#{rel}\0#{Digest::SHA256.file(File.join(staging_root, rel)).hexdigest}"
      end
      Digest::SHA256.hexdigest(lines.join("\n"))
    end

    def live_relpaths
      return [] unless Dir.exist?(texts_root)

      Dir.glob("**/*.jsonl", base: texts_root).sort
    end

    def attic_doomed!
      @doomed_relpaths.each do |rel|
        source = File.join(texts_root, rel)
        destination = File.join(@attic_dir, TEXTS_DIR, rel)
        next if !File.file?(source) || File.exist?(destination)

        FileUtils.mkdir_p(File.dirname(destination))
        FileUtils.cp(source, destination)
        @atticked << File.join(TEXTS_DIR, rel)
      end
      record_manifest! unless @atticked.empty?
    end

    def record_manifest!
      path = File.join(@attic_dir, GitFetch::ATTIC_MANIFEST)
      manifest = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      @atticked.each { |rel| manifest[rel] ||= @sha }
      File.write(path, JSON.pretty_generate(manifest))
    end

    def write_ledger!
      files = live_relpaths.to_h do |rel|
        [File.join(TEXTS_DIR, rel), { "sha256" => Digest::SHA256.file(File.join(texts_root, rel)).hexdigest }]
      end
      ledger = {
        "harvest" => { "base_url" => @base_url, "fetched_at" => @fetched_at, "pin" => @sha,
                       "sentences" => @sentences, "page_size" => @page_size },
        "corpora" => @info,
        "files" => files
      }
      File.write(File.join(@dir, LEDGER_FILE), JSON.pretty_generate(ledger))
    end
  end
end
