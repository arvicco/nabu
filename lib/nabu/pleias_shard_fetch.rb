# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "zlib"

require_relative "errors"
require_relative "redirect_follow"
require_relative "hf_rows_fetch"
require_relative "paced_crawl"
require_relative "parquet"

module Nabu
  # The fetch half of the pleias-french-books lane (Adapters::
  # PleiasFrenchBooks — its class comment carries the census and the
  # cone): one parquet SHARD of a pinned Hugging Face revision streamed to
  # a staging file, verified against the revision's LFS sha256, and CUT —
  # every row's catalogue columns kept (shards/<n>.jsonl), only the rows
  # +keep+ accepts kept with their text (books/<file_id>.json.gz), the
  # stamp (shards/<n>.json) written last as the held marker, the staged
  # shard deleted. The paced-crawl engine drives #fetch_shard! one shard
  # id (the shard's number) at a time.
  #
  # Workdir layout (every path fetch-made; the adapter declares them as
  # materialized):
  #   tree.json            the revision's shards {n => path, size, sha256}
  #   dataset-card.md      the dataset card (README.md) at the revision
  #   shards/<n>.jsonl     one catalogue line per row: index + the
  #                        catalogue columns, upstream values verbatim
  #   shards/<n>.json      the stamp: revision, pin, rows, cone id, kept
  #   books/<id>.json.gz   {"shard","index","row"} — the row with its text
  #                        (gzip mtime 0: the same row writes the same bytes)
  class PleiasShardFetch
    TREE_FILE = "tree.json"
    CARD_FILE = "README.md"
    CARD_TARGET = "dataset-card.md"
    SHARDS_DIR = "shards"
    BOOKS_DIR = "books"
    STAGING_DIR = ".staging"
    SHARD_NAME = /\Agallica_mono_(\d+)\.parquet\z/
    TEXT_COLUMN = "complete_text"
    # census: upstream's eight catalogue columns at revision 21abfb3f (every
    # shard's footer, 2026-11-13) — all but the text
    CATALOGUE_COLUMNS = %w[file_id ocr title date author page_count word_count character_count].freeze
    DENIED_STATUSES = [403, 404].freeze
    TIMEOUT_PATTERN = /transport error for .*(timeout|timed out|execution expired)/i

    # +keep+ answers whether a catalogue line (a Hash) is kept with its
    # text; +cone_id+ is stamped on every shard cut with it.
    def initialize(workdir:, repo:, revision:, cone_id:, keep:, http:, label:)
      @workdir = workdir
      @repo = repo
      @revision = revision
      @cone_id = cone_id
      @keep = keep
      @http = http
      @label = label
      @tree = nil
    end

    def api_url = "https://huggingface.co/api/datasets/#{@repo}"
    def tree_url = "#{api_url}/tree/#{@revision}"
    def resolve_url(name) = "https://huggingface.co/datasets/#{@repo}/resolve/#{@revision}/#{name}"

    def stamp_path(id) = File.join(@workdir, SHARDS_DIR, "#{id}.json")
    def catalogue_path(id) = File.join(@workdir, SHARDS_DIR, "#{id}.jsonl")
    def book_path(file_id) = File.join(@workdir, BOOKS_DIR, "#{file_id}.json.gz")

    # The held shards' listing as last written: { id => entry }.
    def tree
      @tree ||= begin
        path = File.join(@workdir, TREE_FILE)
        File.file?(path) ? JSON.parse(File.read(path, encoding: Encoding::UTF_8)).fetch("shards") : {}
      end
    end

    # Held = the stamp names this revision and this cone, and the
    # catalogue it vouches for is on disk.
    def held?(id)
      stamp = read_stamp(id)
      !stamp.nil? && stamp["revision"] == @revision && stamp["cone"] == @cone_id && File.file?(catalogue_path(id))
    end

    # A note when upstream's main moved past the pin (the era stays on
    # the pin; a re-pin is a re-census), else nil.
    def revision_drift
      body, = get(api_url)
      main = JSON.parse(body)["sha"]
      return nil if main == @revision

      "upstream main is now #{main}; this era stays pinned to #{@revision} (re-census before re-pinning)"
    rescue JSON::ParserError
      nil
    end

    # Fetch and land the revision's listing and the dataset card.
    def refresh_listing!
      atomic_write(File.join(@workdir, TREE_FILE),
                   "#{JSON.pretty_generate('revision' => @revision, 'shards' => fetch_tree)}\n")
      @tree = nil
      body, = get(resolve_url(CARD_FILE))
      atomic_write(File.join(@workdir, CARD_TARGET), body)
    end

    def clear_staging! = FileUtils.rm_rf(File.join(@workdir, STAGING_DIR))

    # The fetch pin: every held shard's stamp, in shard order.
    def crawl_sha
      stamps = tree.keys.filter_map { |id| File.file?(stamp_path(id)) && File.read(stamp_path(id)) }
      Digest::SHA256.hexdigest("#{@revision}\n#{@cone_id}\n#{stamps.join("\n")}")
    end

    # One shard → a PacedCrawl::Outcome: :ok (catalogue + kept books +
    # stamp landed), :denied (403/404), :empty (a readable parquet with
    # no rows — nothing to keep, so it is answered before the pin, which
    # guards what is KEPT), :timeout (a transport timeout). Any other
    # answer raises (the slice dies resumable); a sha256 miss on a shard
    # with rows raises loudly and keeps nothing.
    def fetch_shard!(id)
      entry = tree.fetch(id)
      staged = File.join(@workdir, STAGING_DIR, entry.fetch("path"))
      FileUtils.mkdir_p(File.dirname(staged))
      status, sha, head = download(resolve_url(entry.fetch("path")), staged)
      return PacedCrawl::Outcome.from_body(:denied, http_status: status, body: head) if
        DENIED_STATUSES.include?(status)
      return PacedCrawl::Outcome.from_body(:empty, http_status: status, body: "0 rows") if
        row_count(staged, entry, sha).zero?

      verify_pin!(entry, sha)
      rows = cut_shard!(id, staged, entry)
      PacedCrawl::Outcome.from_body(:ok, http_status: status, body: "#{rows} rows")
    rescue Nabu::Error => e
      raise unless e.message.match?(TIMEOUT_PATTERN)

      PacedCrawl::Outcome.new(status: :timeout, evidence: { body_head: PacedCrawl.body_head(e.message) })
    ensure
      FileUtils.rm_f(staged) if staged
    end

    private

    def read_stamp(id)
      path = stamp_path(id)
      File.file?(path) ? JSON.parse(File.read(path, encoding: Encoding::UTF_8)) : nil
    rescue JSON::ParserError
      nil
    end

    # The pinned revision's shards: { number => {"path","size","sha256"} }.
    def fetch_tree
      body, headers = get(tree_url)
      if headers["link"].to_s.include?('rel="next"')
        raise FetchError, "#{@label}: the tree listing is paginated — extend the fetch to follow it"
      end

      shards = JSON.parse(body).filter_map do |entry|
        number = SHARD_NAME.match(entry["path"].to_s)&.[](1) or next
        sha = entry.dig("lfs", "oid") or raise FetchError, "#{@label}: #{entry['path']} carries no LFS sha256"
        [number, { "path" => entry["path"], "size" => entry.dig("lfs", "size") || entry["size"], "sha256" => sha }]
      end
      raise FetchError, "#{@label}: the revision lists no parquet shards" if shards.empty?

      shards.sort_by { |number, _| Integer(number, 10) }.to_h
    rescue JSON::ParserError => e
      raise FetchError, "#{@label}: the tree listing is not JSON (#{e.message})"
    end

    # Stream +url+ into +path+ (redirect hops reset the sink): [status,
    # sha256, the body's first bytes].
    def download(url, path)
      digest = Digest::SHA256.new
      response = nil
      File.open(path, "wb") do |file|
        sink = lambda do
          file.truncate(0)
          file.rewind
          digest.reset
          proc do |chunk, _received|
            file.write(chunk)
            digest << chunk
          end
        end
        response, = RedirectFollow.get(url, http: @http, error: FetchError, headers: headers,
                                            accept: [200, *DENIED_STATUSES], stream: sink)
        if file.pos.zero? && !(fallback = response.body.to_s.b).empty?
          file.write(fallback)
          digest << fallback
        end
      end
      [response.status, digest.hexdigest, File.binread(path, 80).to_s]
    end

    def verify_pin!(entry, sha)
      return if sha == entry.fetch("sha256")

      raise FetchError, "#{@label}: #{entry['path']} misses its sha256 pin (the revision's LFS oid " \
                        "#{entry['sha256']}, got #{sha}) — corruption, or the resolve URL served another " \
                        "object; nothing of the shard was kept"
    end

    # An unreadable body that also misses its pin reports the pin miss
    # (the truer diagnosis: corruption in transit).
    def row_count(staged, entry, sha)
      File.open(staged, "rb") { |io| Parquet.new(io).num_rows }
    rescue Parquet::Error => e
      verify_pin!(entry, sha)
      raise FetchError, "#{@label}: #{entry['path']} is not a readable shard: #{e.message}"
    end

    # Read the catalogue, keep the accepted rows' books, then land the
    # catalogue and the stamp (the stamp last: it is the held marker).
    # Returns the shard's row count.
    def cut_shard!(id, staged, entry)
      File.open(staged, "rb") do |io|
        parquet = Parquet.new(io)
        catalogue = read_catalogue(parquet)
        kept = catalogue.each_with_index.filter_map { |line, i| i if @keep.call(line) }.to_set
        land_books!(id, parquet, catalogue, kept)
        atomic_write(catalogue_path(id), catalogue.map { |line| "#{JSON.generate(line)}\n" }.join)
        atomic_write(stamp_path(id), "#{JSON.pretty_generate(
          'revision' => @revision, 'path' => entry['path'], 'sha256' => entry['sha256'],
          'bytes' => entry['size'], 'rows' => parquet.num_rows, 'cone' => @cone_id, 'kept' => kept.size
        )}\n")
        parquet.num_rows
      end
    rescue Parquet::Error, Snappy::Error => e
      raise FetchError, "#{@label}: #{entry['path']} is not a readable shard: #{e.message}"
    end

    # [{"index" => i, column => value, …}] in upstream column order.
    def read_catalogue(parquet)
      columns = CATALOGUE_COLUMNS.to_h { |name| [name, parquet.column(name)] }
      Array.new(parquet.num_rows) do |i|
        { "index" => i }.merge(columns.transform_values { |values| utf8(values[i]) })
      end
    end

    def land_books!(id, parquet, catalogue, kept)
      FileUtils.mkdir_p(File.join(@workdir, BOOKS_DIR))
      parquet.each_value(TEXT_COLUMN, want: kept) do |i, value|
        line = catalogue.fetch(i)
        row = line.except("index").merge(TEXT_COLUMN => utf8(value))
        write_book!(book_path(line.fetch("file_id")), "shard" => id, "index" => i, "row" => row)
      end
    end

    def write_book!(path, book)
      tmp = "#{path}.tmp"
      Zlib::GzipWriter.open(tmp) do |gz|
        gz.mtime = 0
        gz.write(JSON.generate(book))
      end
      File.rename(tmp, path)
    end

    def utf8(value)
      return value unless value.is_a?(String)

      text = value.dup.force_encoding(Encoding::UTF_8)
      raise FetchError, "#{@label}: a cell is not valid UTF-8" unless text.valid_encoding?

      text
    end

    def atomic_write(path, body)
      FileUtils.mkdir_p(File.dirname(path))
      File.binwrite("#{path}.tmp", body)
      File.rename("#{path}.tmp", path)
    end

    def get(url)
      response, = RedirectFollow.get(url, http: @http, error: FetchError, headers: headers)
      [response.body.to_s.dup.force_encoding(Encoding::UTF_8), response.headers]
    end

    def headers = { "User-Agent" => HfRowsFetch::USER_AGENT }
  end
end
