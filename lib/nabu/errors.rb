# frozen_string_literal: true

module Nabu
  # Base class for every error Nabu raises on purpose. Application code rescues
  # this (or a specific subclass) — never a bare StandardError.
  class Error < StandardError; end

  # A document could not be parsed. The offending document is quarantined; the
  # surrounding sync/batch continues.
  class ParseError < Error; end

  # An upstream fetch failed. This aborts the sync — we do not persist a
  # partial or stale corpus.
  class FetchError < Error; end

  # A domain value failed validation at construction time (empty URN,
  # implausible language tag, non-NFC text, unknown license class, ...).
  # Domain objects are valid by construction; this is how they refuse.
  class ValidationError < Error; end

  # The withdrawal circuit breaker tripped (architecture §8): a sync would
  # withdraw more than the allowed fraction of a source's documents, so it was
  # aborted BEFORE any loading — nothing was written. Carries the counts that
  # justified the refusal so callers can report them without recomputing. The
  # message names the counts and hints `--force`. RunRecorder records the run
  # as "aborted" (not "failed") on this error.
  class SyncAborted < Error
    attr_reader :existing_count, :would_withdraw_count, :threshold

    def initialize(existing_count:, would_withdraw_count:, threshold:)
      @existing_count = existing_count
      @would_withdraw_count = would_withdraw_count
      @threshold = threshold
      percent = (threshold * 100).round
      super(
        "circuit breaker: syncing would withdraw #{would_withdraw_count} of " \
        "#{existing_count} document(s) — more than #{percent}% of the source. " \
        "Refusing to gut the corpus; re-run with --force if this is intended."
      )
    end
  end
end
