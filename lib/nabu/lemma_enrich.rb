# frozen_string_literal: true

require "json"
require "time"
require_relative "errors"
require_relative "shell"
require_relative "lemma_shelf"

module Nabu
  # P84-1 — the silver-lemma enricher runner (Q38, №R-35): runs a local
  # CPU lemmatizer (venv-managed Stanza, la:ittb for the Latin wave) over
  # the lemma-UNCOVERED slice of one language and lands the raw model
  # output on the local-lemmas shelf through Nabu::LemmaShelf — the model
  # output is NON-DERIVABLE (hours of compute), so it never touches db/;
  # the SilverLemmaIndexer projects the shelf into passage_lemmas at
  # rebuild/sync/--index time instead.
  #
  # == Shape
  #
  # - ONE worker subprocess per campaign (Shell.duplex; model load ~10s),
  #   fed batches of passages; the Ruby side owns selection, skipping,
  #   provenance and shelf writes — the worker owns nothing but the model.
  # - RESUMABLE at two grains (the corpus-corporum mold): the shelf's own
  #   urns are the fine grain (never re-sent), and the campaign checkpoint
  #   (last considered passage id, written at every shard flush) is the
  #   coarse grain — a crash at hour 3 loses at most one unflushed shard.
  # - Announced + ticked (no-silent-passes): census and scan stages speak
  #   before the long pass; the lemmatize loop ticks per worker batch.
  # - Bounded memory: the covered/shelved urn sets plus one shard of
  #   pending records; passages stream in keyset pages, never as one
  #   materialized result.
  #
  # The suite never runs the model: tests speak the identical protocol to
  # test/fixtures/lemma/fake_worker.rb.
  class LemmaEnrich
    # Wave-1 lanes (P79-4 verdict): Latin only. grc is measured and
    # planned but deliberately NOT wired yet — one gold-measurable wave at
    # a time.
    LANGUAGES = {
      "lat" => { stanza_lang: "la", aliases: %w[la latin] }
    }.freeze

    # The P79-4 measured single-process rate (passages/s, Apple Silicon
    # CPU) — the census ETA's basis until this box records its own.
    TRIAL_RATE = 72.0

    DEFAULT_BATCH = 100    # passages per worker request
    DEFAULT_SHARD = 2_000  # records per shelf shard (≈28s of compute)
    PAGE = 1_000           # keyset page size over passages
    STATE_SCHEMA = 1

    WORKER_SCRIPT = File.expand_path("../../script/stanza_lemma_worker.py", __dir__)
    DEFAULT_VENV = File.join(Dir.home, ".nabu", "venvs", "stanza")

    # The worker answered wrongly, died, or refused a batch. Campaign
    # aborts (flushing what it holds); the checkpoint makes re-fire cheap.
    class WorkerError < Nabu::Error; end

    Census = Data.define(:language, :total, :covered, :shelved, :uncovered, :eta_seconds)

    Result = Data.define(:language, :processed, :skipped_covered, :skipped_shelved,
                         :skipped_empty, :shards_written, :elapsed_seconds,
                         :model, :model_version, :package) do
      def rate
        elapsed_seconds.positive? ? processed / elapsed_seconds : 0.0
      end
    end

    # "la"/"latin" → "lat" (the catalog code IS the lane name); an unknown
    # language names what wave-1 supports.
    def self.resolve_language(name)
      code = name.to_s.strip.downcase
      return code if LANGUAGES.key?(code)

      match = LANGUAGES.find { |_code, lane| lane[:aliases].include?(code) }
      return match.first if match

      supported = LANGUAGES.map { |c, lane| "#{c} (aliases: #{lane[:aliases].join(', ')})" }
      raise Nabu::Error, "no silver-lemma lane for #{name.inspect} — wave-1 supports #{supported.join('; ')}"
    end

    # The real worker's argv for the CLI: the owner-bootstrapped venv
    # (docs/manual/silver-lemma-venv.md — a ONE-time human step; models
    # pre-fetched, so the worker itself never touches the network).
    def self.worker_argv(language:, venv: nil)
      venv ||= ENV.fetch("NABU_STANZA_VENV", DEFAULT_VENV)
      python = File.join(venv, "bin", "python")
      unless File.executable?(python)
        raise Nabu::Error, "no venv python at #{python} — bootstrap it once " \
                           "(docs/manual/silver-lemma-venv.md) or point --venv at an existing one"
      end
      [python, WORKER_SCRIPT,
       "--lang", LANGUAGES.fetch(language)[:stanza_lang],
       "--model-dir", File.join(venv, "models")]
    end

    def initialize(catalog:, fulltext:, shelf:, language:, worker_argv:,
                   batch_size: DEFAULT_BATCH, shard_size: DEFAULT_SHARD,
                   limit: nil, progress: nil)
      @catalog = catalog
      @fulltext = fulltext
      @shelf = shelf
      @language = language
      @worker_argv = worker_argv
      @batch_size = batch_size
      @shard_size = shard_size
      @limit = limit
      @progress = progress
    end

    # The honest pre-flight numbers: live passages of the lane, how many
    # are lemma-covered (any tier) or already shelved, and the uncovered
    # remainder with its ETA at the trial rate. Also the run's own skip
    # sets, so run! computes this exactly once.
    def census
      @progress&.stage("silver lemmas: census (#{@language})")
      total = live_passages.count
      covered = covered_urns
      shelved = shelved_urns
      uncovered = [total - covered.size - shelved.size, 0].max
      Census.new(language: @language, total: total, covered: covered.size,
                 shelved: shelved.size, uncovered: uncovered,
                 eta_seconds: uncovered / TRIAL_RATE)
    end

    # The campaign: worker up, stream the uncovered slice, shelve in
    # shards, checkpoint at every flush. Returns a Result; raises
    # WorkerError (resumably) if the worker fails.
    def run!
      covered_urns # warm both skip sets before the worker spawns
      shelved_urns
      @counts = Hash.new(0)
      @pending = []
      @considered = checkpoint_id
      @shards_written = 0
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      Shell.duplex(*@worker_argv) do |worker|
        handshake!(worker)
        @progress&.stage("silver lemmas: lemmatizing #{@language} " \
                         "(#{@model} #{@model_version}, #{@package})")
        begin
          stream_passages(worker)
        ensure
          flush! # a partial shard survives any abort; checkpoint rides along
        end
      end

      Result.new(language: @language, processed: @counts[:processed],
                 skipped_covered: @counts[:skipped_covered],
                 skipped_shelved: @counts[:skipped_shelved],
                 skipped_empty: @counts[:skipped_empty],
                 shards_written: @shards_written,
                 elapsed_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
                 model: @model, model_version: @model_version, package: @package)
    end

    # -- the gold spot-check (P79-4 protocol, wired) -------------------------
    #
    # Samples gold-annotated passages (token-level "lemma"+"form"), runs
    # the SAME worker over their pristine text, token-aligns on FOLDED
    # surface forms (LCS — the trial's difflib equivalent) and scores
    # folded-lemma agreement per source. Writes nothing anywhere.
    def spot_check(sample: 250)
      @progress&.stage("silver lemmas: gold spot-check (#{@language}, sample #{sample})")
      rows = gold_sample(sample)
      raise Nabu::Error, "no gold-annotated #{@language} passages to spot-check against" if rows.empty?

      report = {}
      Shell.duplex(*@worker_argv) do |worker|
        handshake!(worker)
        rows.each_slice(@batch_size) do |batch|
          answers = request!(worker, batch.map { |row| row[:text] })
          batch.zip(answers).each { |row, tokens| score(report, row, tokens) }
        end
      end
      report.each_value do |entry|
        entry[:accuracy] = entry[:aligned].positive? ? 100.0 * entry[:folded_hits] / entry[:aligned] : 0.0
      end
      report
    end

    private

    # -- selection -----------------------------------------------------------

    def live_passages
      @catalog[:passages]
        .join(:documents, id: :document_id)
        .join(:sources, id: Sequel[:documents][:source_id])
        .where(Sequel[:passages][:language] => @language,
               Sequel[:passages][:withdrawn] => false,
               Sequel[:documents][:withdrawn] => false)
    end

    def covered_urns
      @covered_urns ||=
        if @fulltext.table_exists?(:passage_lemmas)
          @fulltext[:passage_lemmas].where(language: @language).distinct.select_map(:urn).to_set
        else
          Set.new
        end
    end

    def shelved_urns
      @shelved_urns ||= begin
        @progress&.stage("silver lemmas: scanning the shelf (#{@language})")
        @shelf.urns(language: @language)
      end
    end

    def checkpoint_id
      state = @shelf.state(language: @language)
      state ? state.fetch("checkpoint_passage_id", 0) : 0
    end

    # Keyset pagination in passage-id order — the checkpoint's axis. Never
    # materializes more than one page.
    def stream_passages(worker)
      cursor = @considered
      loop do
        rows = live_passages
               .where { Sequel[:passages][:id] > cursor }
               .order(Sequel[:passages][:id])
               .limit(PAGE)
               .select(Sequel[:passages][:id].as(:passage_id), Sequel[:passages][:urn],
                       Sequel[:passages][:text], Sequel[:sources][:slug].as(:slug))
               .all
        break if rows.empty?

        cursor = rows.last[:passage_id]
        rows.each_slice(@batch_size) do |slice|
          send_batch(worker, filter(slice))
          break if limit_reached?
        end
        break if limit_reached?
      end
    end

    def limit_reached?
      @limit && @counts[:processed] >= @limit
    end

    # The skip gates, each counted honestly. Skipped passages advance the
    # considered pointer immediately — their causes are stable, so resume
    # never needs to revisit them.
    def filter(slice)
      slice.filter_map do |row|
        cause = skip_cause(row)
        if cause
          @counts[cause] += 1
          @considered = row[:passage_id]
          nil
        else
          row
        end
      end
    end

    def skip_cause(row)
      return :skipped_covered if covered_urns.include?(row[:urn])
      return :skipped_shelved if shelved_urns.include?(row[:urn])
      return :skipped_empty if row[:text].to_s.strip.empty?

      nil
    end

    # -- the worker protocol -------------------------------------------------

    def handshake!(worker)
      ready = parse(worker.read_line)
      raise WorkerError, "worker did not announce ready: #{ready.inspect}" unless ready["ready"]

      @model = ready.fetch("worker", "unknown")
      @model_version = ready.fetch("version", "unknown")
      lemma_model = ready["lemma_model"].to_s
      @package = "#{ready.fetch('lang', @language)}:#{lemma_model.empty? ? 'default' : lemma_model}"
    end

    def request!(worker, texts)
      @request_id = (@request_id || 0) + 1
      worker.write_line(JSON.generate({ "id" => @request_id, "texts" => texts }))
      answer = parse(worker.read_line)
      raise WorkerError, "worker error: #{answer['error']}" if answer["error"]
      raise WorkerError, "worker answered id #{answer['id']} to request #{@request_id}" \
        unless answer["id"] == @request_id

      results = answer["results"]
      raise WorkerError, "worker answered #{results&.size || 0} results for #{texts.size} texts" \
        unless results.is_a?(Array) && results.size == texts.size

      results
    end

    def parse(line)
      JSON.parse(line)
    rescue JSON::ParserError => e
      raise WorkerError, "unparseable worker answer (#{e.message}): #{line[0, 120]}"
    end

    def send_batch(worker, rows)
      if @limit
        remaining = @limit - @counts[:processed]
        rows = rows.take(remaining) # unsent rows never advance @considered
      end
      return if rows.empty?

      answers = request!(worker, rows.map { |row| row[:text] })
      now = Time.now.utc.iso8601
      rows.zip(answers).each do |row, tokens|
        @considered = row[:passage_id]
        if tokens.empty?
          @counts[:skipped_empty] += 1
          next
        end
        @pending << LemmaShelf::Record.new(
          urn: row[:urn], language: @language, source: row[:slug],
          model: @model, model_version: @model_version, package: @package,
          tokens: tokens, generated_at: now
        )
        @counts[:processed] += 1
      end
      @progress&.load_tick(@counts[:processed], 0)
      flush! if @pending.size >= @shard_size
    end

    # One shard per flush, checkpoint after — order matters: the shard is
    # durable before the checkpoint claims its passages are done.
    def flush!
      return if @pending.empty?

      @shelf.append_batch!(language: @language, records: @pending)
      @shards_written += 1
      @pending = []
      @shelf.write_state!(language: @language, payload: {
                            "state_schema" => STATE_SCHEMA, "language" => @language,
                            "checkpoint_passage_id" => @considered,
                            "updated_at" => Time.now.utc.iso8601,
                            "model" => @model, "model_version" => @model_version,
                            "package" => @package
                          })
    end

    # -- spot-check internals ------------------------------------------------

    # Up to +sample+ gold passages, stratified across the lane's
    # gold-annotated sources (deterministic id order — a spot-check should
    # reproduce).
    def gold_sample(sample)
      gold = live_passages.where(Sequel.like(Sequel[:passages][:annotations_json], '%"lemma"%'))
      slugs = gold.distinct.select_map(Sequel[:sources][:slug])
      return [] if slugs.empty?

      per_slug = [(sample.to_f / slugs.size).ceil, 1].max
      slugs.sort.flat_map do |slug|
        gold.where(Sequel[:sources][:slug] => slug)
            .order(Sequel[:passages][:id])
            .limit(per_slug)
            .select(Sequel[:passages][:urn], Sequel[:passages][:text],
                    Sequel[:passages][:annotations_json], Sequel[:sources][:slug].as(:slug))
            .all
      end
    end

    def score(report, row, predicted)
      gold = JSON.parse(row[:annotations_json]).fetch("tokens", []).filter_map do |token|
        next unless token.is_a?(Hash) && token["form"] && token["lemma"] && !token["lemma"].empty?

        [token["form"], token["lemma"]]
      end
      return if gold.empty?

      entry = report[row[:slug]] ||= { gold_tokens: 0, aligned: 0, folded_hits: 0 }
      entry[:gold_tokens] += gold.size
      pairs = align(gold.map { |form, _| fold(form) }, predicted.map { |form, _, _| fold(form) })
      pairs.each do |gi, pi|
        entry[:aligned] += 1
        entry[:folded_hits] += 1 if fold(gold[gi][1]) == fold(predicted[pi][1])
      end
    end

    def fold(text)
      Normalize.search_form(text.to_s, language: @language)
    end

    # Longest-common-subsequence alignment over folded surface forms —
    # index pairs of matched tokens (the difflib matching-blocks
    # equivalent, passage-sized inputs, O(n*m)).
    def align(gold, predicted)
      table = Array.new(gold.size + 1) { Array.new(predicted.size + 1, 0) }
      gold.size.times do |i|
        predicted.size.times do |j|
          table[i + 1][j + 1] =
            gold[i] == predicted[j] ? table[i][j] + 1 : [table[i][j + 1], table[i + 1][j]].max
        end
      end
      pairs = []
      i = gold.size
      j = predicted.size
      while i.positive? && j.positive?
        if gold[i - 1] == predicted[j - 1] && table[i][j] == table[i - 1][j - 1] + 1
          pairs.unshift([i - 1, j - 1])
          i -= 1
          j -= 1
        elsif table[i - 1][j] >= table[i][j - 1]
          i -= 1
        else
          j -= 1
        end
      end
      pairs
    end
  end
end
