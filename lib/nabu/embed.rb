# frozen_string_literal: true

require "json"
require "time"
require "digest"
require_relative "errors"
require_relative "shell"

module Nabu
  # P93-4 — the semantic-vector build lane (№R-36, ruled "build"
  # 2026-09-02 with the incremental-first constraint). Embeds the
  # embed-flagged sources' live passages (registry `embed_index: true` —
  # the literary core; the P79-5 trial's full-library extrapolation was a
  # measured NO) with the trial's model via a venv worker, into
  # db/vectors.sqlite3.
  #
  # == The incremental contract (the owner's design constraint)
  #
  # Vectors key on (model, urn) and carry the sha of the EXACT text that
  # was embedded — NEVER passage ids, which a rebuild re-mints. So:
  # - `nabu rebuild` never touches vectors.sqlite3 (rebuild deletes the
  #   catalog/fulltext files by name; this file survives untouched and
  #   its rows stay VALID — they are a pure function of canonical text).
  # - every `nabu embed` run is a delta: a passage is skipped when its
  #   (model, urn) row already carries the sha of its current embed
  #   input; revised text re-embeds, everything else is never redone.
  #   The first run is the priced ~22h build; later runs are seconds to
  #   minutes. Resumability is row-grain: each batch commits, so a crash
  #   loses at most one batch.
  # - a MODEL change is the only full re-embed, and it is deliberate:
  #   rows are per-model, so a new model builds beside the old (the
  #   architecture §"vectors" contract), never silently over it.
  #
  # == Worker
  #
  # One subprocess per campaign (Shell.duplex — the P84-1 stanza mold):
  # script/embed_worker.py inside the owner-bootstrapped venv
  # (docs/manual/embed-venv.md; models pre-fetched, the worker never
  # touches the network). The worker owns nothing but the model; it
  # answers base64 int8 vectors (E5 "passage: " prefixing applied
  # worker-side). The suite never runs the model — tests speak the same
  # protocol to test/fixtures/embed/fake_worker.rb.
  #
  # == The NFC-exempt variant (the trial's hard finding)
  #
  # Pointed Hebrew/Aramaic is unembeddable by this model class (P79-5:
  # gold cosine 0.891 vs random 0.882 — zero signal); stripping the
  # combining marks rescues it to usable. The embed INPUT for the
  # NFC-exempt languages is therefore the marks-stripped text, and the
  # stored sha is the sha of that input — the stored passage text is
  # untouched (canonical means canonical).
  class Embed
    MODEL = "multilingual-e5-base"
    # The P79-5 measured throughput (passages/s, MPS batch 128) — the
    # census ETA's basis until this box records its own.
    TRIAL_RATE = 69.8
    DEFAULT_BATCH = 128
    PAGE = 1_000

    VECTORS_TABLE = :vectors
    META_TABLE = :embed_meta

    # Bytes per component for the worker's declared encoding — int8 (the
    # production worker: the trial's smallest tier, and the one
    # sqlite-vec's distance functions scan natively — float16 is NOT
    # supported there, verified 2026-09-02) or float16/float32 should a
    # future worker declare them.
    ENCODING_BYTES = { "i8" => 1, "f16" => 2, "f32" => 4 }.freeze

    WORKER_SCRIPT = File.expand_path("../../script/embed_worker.py", __dir__)
    DEFAULT_VENV = File.join(Dir.home, ".nabu", "venvs", "embed")

    # The worker answered wrongly, died, or refused a batch. The campaign
    # aborts; row-grain resumability makes re-fire cheap.
    class WorkerError < Nabu::Error; end

    Census = Data.define(:slugs, :total, :fresh, :stale, :missing, :eta_seconds)

    Result = Data.define(:embedded, :skipped_fresh, :skipped_empty, :elapsed_seconds,
                         :model, :dim, :worker_version) do
      def rate
        elapsed_seconds.positive? ? embedded / elapsed_seconds : 0.0
      end
    end

    # The real worker's argv for the CLI: the owner-bootstrapped venv
    # (docs/manual/embed-venv.md — a ONE-time human step; the model is
    # pre-fetched, so the worker itself never touches the network).
    def self.worker_argv(venv: nil)
      venv ||= ENV.fetch("NABU_EMBED_VENV", DEFAULT_VENV)
      python = File.join(venv, "bin", "python")
      unless File.executable?(python)
        raise Nabu::Error, "no venv python at #{python} — bootstrap it once " \
                           "(docs/manual/embed-venv.md) or point --venv at an existing one"
      end
      [python, WORKER_SCRIPT, "--model-dir", File.join(venv, "models")]
    end

    # Create the vectors schema when absent (imperative, the fulltext
    # precedent — but the FILE is expensive-derived: nothing ever drops
    # it wholesale; `nabu embed` maintains it row-wise).
    def self.ensure_schema!(vectors)
      vectors.create_table?(VECTORS_TABLE) do
        String :model, null: false
        String :urn, null: false
        String :language
        String :text_sha, null: false
        File :vec, null: false # SQLite BLOB — the worker's int8 bytes (ENCODING_BYTES)
        primary_key %i[model urn]
        index %i[model language]
      end
      vectors.create_table?(META_TABLE) do
        String :model, primary_key: true
        Integer :dim, null: false
        String :encoding, null: false
        String :worker_version, null: false
        String :updated_at, null: false
      end
    end

    # The embed INPUT for a passage: the pristine text, except the
    # NFC-exempt languages, which embed marks-stripped (class note).
    def self.embed_input(text, language)
      return text.to_s unless Nabu::Normalize.nfc_exempt?(language)

      text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}+/, "")
    end

    def self.input_sha(input) = Digest::SHA256.hexdigest(input)

    def initialize(catalog:, vectors:, slugs:, worker_argv: nil, model: MODEL,
                   batch_size: DEFAULT_BATCH, limit: nil, progress: nil)
      @catalog = catalog
      @vectors = vectors
      @slugs = slugs
      @worker_argv = worker_argv
      @model = model
      @batch_size = batch_size
      @limit = limit
      @progress = progress
      self.class.ensure_schema!(vectors)
    end

    # The honest pre-flight numbers: scope passages, how many carry a
    # FRESH vector (sha matches the current embed input), how many are
    # stale (text changed since embedding) or missing, and the remainder's
    # ETA at the trial rate. Streams the scope page-wise (announced +
    # ticked — minutes at core scale, never silent).
    def census
      @progress&.stage("embed: census (#{@slugs.size} sources, model #{@model})")
      counts = { total: 0, fresh: 0, stale: 0, missing: 0 }
      each_scope_page do |rows|
        held = held_shas(rows.map { |row| row[:urn] })
        rows.each do |row|
          counts[:total] += 1
          counts[classify(row, held)] += 1
        end
        @progress&.load_tick(counts[:total], 0)
      end
      Census.new(slugs: @slugs, total: counts[:total], fresh: counts[:fresh],
                 stale: counts[:stale], missing: counts[:missing],
                 eta_seconds: (counts[:stale] + counts[:missing]) / TRIAL_RATE)
    end

    # The campaign: worker up, stream the scope, embed exactly the
    # stale-or-missing remainder, commit per batch. Returns a Result;
    # raises WorkerError (resumably) if the worker fails.
    def run!
      raise Nabu::Error, "no sources flagged embed_index: true — nothing to embed" if @slugs.empty?

      @counts = Hash.new(0)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Shell.duplex(*@worker_argv) do |worker|
        handshake!(worker)
        @progress&.stage("embed: encoding (#{@model}, dim #{@dim}, #{@encoding}) — " \
                         "delta only, batches of #{@batch_size} commit as they land")
        stream_scope(worker)
      end
      Result.new(embedded: @counts[:embedded], skipped_fresh: @counts[:skipped_fresh],
                 skipped_empty: @counts[:skipped_empty],
                 elapsed_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                 model: @model, dim: @dim, worker_version: @worker_version)
    end

    private

    # -- selection -----------------------------------------------------------

    def scope
      @catalog[:passages]
        .join(:documents, id: Sequel[:passages][:document_id])
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:passages][:withdrawn] => false, Sequel[:documents][:withdrawn] => false)
        .where(Sequel[:sources][:slug] => @slugs)
    end

    # Keyset pages in passage-id order; never materializes more than one.
    def each_scope_page
      cursor = 0
      loop do
        rows = scope
               .where { Sequel[:passages][:id] > cursor }
               .order(Sequel[:passages][:id])
               .limit(PAGE)
               .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:urn],
                       Sequel[:passages][:text], Sequel[:passages][:language])
               .all
        break if rows.empty?

        cursor = rows.last[:passage_id]
        yield rows
      end
    end

    # { urn => stored text_sha } for this page's urns — one indexed IN
    # query per page, bounded memory (the incremental-first crux: presence
    # + sha equality IS the skip decision, no checkpoint state anywhere).
    def held_shas(urns)
      @vectors[VECTORS_TABLE].where(model: @model, urn: urns).select_hash(:urn, :text_sha)
    end

    def classify(row, held)
      input = self.class.embed_input(row[:text], row[:language])
      # An empty embed input can never embed — nothing owed, counts as
      # fresh so the ETA prices only real work.
      return :fresh if input.strip.empty?

      sha = held[row[:urn]]
      return :missing if sha.nil?

      sha == self.class.input_sha(input) ? :fresh : :stale
    end

    # -- the campaign --------------------------------------------------------

    def stream_scope(worker)
      each_scope_page do |rows|
        held = held_shas(rows.map { |row| row[:urn] })
        todo = rows.filter_map { |row| prepare(row, held) }
        todo.each_slice(@batch_size) do |batch|
          embed_batch(worker, batch)
          return nil if limit_reached?
        end
      end
    end

    def prepare(row, held)
      input = self.class.embed_input(row[:text], row[:language])
      if input.strip.empty?
        @counts[:skipped_empty] += 1
        return nil
      end
      sha = self.class.input_sha(input)
      if held[row[:urn]] == sha
        @counts[:skipped_fresh] += 1
        return nil
      end
      { urn: row[:urn], language: row[:language], input: input, sha: sha }
    end

    def limit_reached?
      @limit && @counts[:embedded] >= @limit
    end

    def embed_batch(worker, batch)
      batch = batch.take(@limit - @counts[:embedded]) if @limit
      return if batch.empty?

      vectors = request!(worker, batch.map { |row| row[:input] })
      now = Time.now.utc.iso8601
      @vectors.transaction do
        batch.zip(vectors).each do |row, b64|
          @vectors[VECTORS_TABLE]
            .insert_conflict(target: %i[model urn],
                             update: { text_sha: row[:sha], language: row[:language],
                                       vec: Sequel[:excluded][:vec] })
            .insert(model: @model, urn: row[:urn], language: row[:language],
                    text_sha: row[:sha], vec: Sequel.blob(decode64(b64)))
        end
        touch_meta(now)
      end
      @counts[:embedded] += batch.size
      @progress&.load_tick(@counts[:embedded], 0)
    end

    def decode64(b64)
      bytes = b64.to_s.unpack1("m0")
      expected = @dim * ENCODING_BYTES.fetch(@encoding, 1)
      raise WorkerError, "worker vector has #{bytes.bytesize} bytes, expected #{expected} (#{@encoding})" \
        unless bytes.bytesize == expected

      bytes
    end

    def touch_meta(now)
      @vectors[META_TABLE]
        .insert_conflict(target: :model, update: { updated_at: now })
        .insert(model: @model, dim: @dim, encoding: @encoding,
                worker_version: @worker_version, updated_at: now)
    end

    # -- the worker protocol -------------------------------------------------

    def handshake!(worker)
      ready = parse(worker.read_line)
      raise WorkerError, "worker did not announce ready: #{ready.inspect}" unless ready["ready"]
      raise WorkerError, "worker model #{ready['model'].inspect} != campaign model #{@model}" \
        unless ready["model"] == @model

      @dim = Integer(ready.fetch("dim"))
      @encoding = ready.fetch("encoding", "i8")
      @worker_version = ready.fetch("version", "unknown")
    end

    def request!(worker, texts)
      @request_id = (@request_id || 0) + 1
      worker.write_line(JSON.generate({ "id" => @request_id, "texts" => texts }))
      answer = parse(worker.read_line)
      raise WorkerError, "worker error: #{answer['error']}" if answer["error"]
      raise WorkerError, "worker answered id #{answer['id']} to request #{@request_id}" \
        unless answer["id"] == @request_id

      vectors = answer["vectors"]
      raise WorkerError, "worker answered #{vectors&.size || 0} vectors for #{texts.size} texts" \
        unless vectors.is_a?(Array) && vectors.size == texts.size

      vectors
    end

    def parse(line)
      JSON.parse(line)
    rescue JSON::ParserError => e
      raise WorkerError, "unparseable worker answer (#{e.message}): #{line.to_s[0, 120]}"
    end
  end
end
