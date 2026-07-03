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
end
