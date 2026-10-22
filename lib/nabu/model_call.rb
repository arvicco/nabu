# frozen_string_literal: true

require_relative "errors"
require_relative "model_output"
require_relative "model_shelf"
require_relative "model_budget"

module Nabu
  # One paid-model call under the model-output convention (architecture §16 "the
  # model-output convention") — the ONE place the fixed check order
  # lives, so no producer re-implements (or reorders) it:
  #
  #   1. key    = ModelOutput.key(urn, tool, prompt_version, model)
  #   2. cache  — a shelf hit answers at once: no call, no cost row, no
  #               budget touch (a hit answers even over the cap)
  #   3. budget — ModelBudget#check! BEFORE the call (fail-closed)
  #   4. call   — backend.complete(prompt:, model:)
  #   5. costs  — one costs.tsv row, flushed (spend survives a kill)
  #   6. spend  — ModelBudget#record! with the call's REAL usd
  #   7. output — one outputs.jsonl row (the cache entry)
  #
  # Costs are booked BEFORE the output so money spent is never unrecorded:
  # a kill between 5 and 7 re-pays one call on resume, never hides one.
  #
  # == The backend contract
  #
  # Any object with #name (the costs.tsv backend label) and
  # #complete(prompt:, model:) returning a Response whose usd is computed
  # from the provider's reported usage. Tests pass a stub; a real backend
  # is the first producer's business (and its own gem/HTTP decision).
  class ModelCall
    Response = Data.define(:text, :usd)

    # +cached+ true when the shelf answered; +usd+ 0.0 then.
    Result = Data.define(:key, :output, :cached, :usd)

    class Error < Nabu::Error; end

    def initialize(shelf:, run:, budget:, backend:, producer:, model:, clock: -> { Time.now })
      @shelf = shelf
      @run = run
      @budget = budget
      @backend = backend
      @producer = producer
      @model = model
      @clock = clock
    end

    # Answer +prompt+ (a ModelOutput::Prompt the run recorded) rendered
    # with +vars+ for the unit +urn+. +unit+ is the costs.tsv unit label
    # (default the urn). +estimate_usd+ lets a producer refuse a call it
    # knows would cross the cap.
    def call(urn:, prompt:, vars:, unit: urn, estimate_usd: 0.0)
      unless @run.stage?(prompt)
        raise Error, "prompt #{prompt.tool}/#{prompt.version} is not a stage of run #{@run.dir} — " \
                     "every paid prompt must be recorded verbatim in the run's config.json"
      end

      key = ModelOutput.key(urn: urn, tool: prompt.tool, prompt_version: prompt.version, model: @model)
      hit = @shelf.lookup(producer: @producer, key: key)
      return Result.new(key: key, output: hit.output, cached: true, usd: 0.0) if hit

      now = @clock.call
      month = ModelBudget.month(now)
      @budget.check!(month: month, estimate_usd: estimate_usd)
      response = @backend.complete(prompt: prompt.render(vars), model: @model)
      usd = response.usd
      unless usd.is_a?(Numeric) && usd >= 0
        raise Error,
              "backend #{@backend.name} reported no usable cost (#{usd.inspect})"
      end

      @run.append_cost!(stage: prompt.tool, unit: unit, usd: usd, backend: @backend.name)
      @budget.record!(month: month, usd: usd)
      @run.append_output!(ModelShelf::Output.new(key: key, urn: urn, tool: prompt.tool,
                                                 prompt_version: prompt.version, model: @model,
                                                 output: response.text, generated_at: now.utc.iso8601))
      Result.new(key: key, output: response.text, cached: false, usd: usd)
    end
  end
end
