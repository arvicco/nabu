# frozen_string_literal: true

module Nabu
  # Abstract base for source adapters — the extensibility point of the whole
  # system (architecture §3). Every source is one subclass implementing four
  # methods; adapters emit the neutral Document/Passage model and never touch
  # SQL. Every subclass must pass the shared conformance suite
  # (test/support/adapter_conformance.rb) plus its own source-specific tests.
  #
  # Text discipline: adapters normalize upstream text to UTF-8 NFC at this
  # boundary (Nabu::Normalize.nfc) — Passage rejects non-NFC input outright.
  #
  # Error discipline: parse raises Nabu::ParseError (quarantines the
  # document); fetch raises Nabu::FetchError (aborts the sync).
  class Adapter
    # Static metadata for the source: a Nabu::SourceManifest (id, name,
    # license + license_class, upstream URL, parser family).
    def self.manifest
      raise NotImplementedError, "#{self} must implement .manifest"
    end

    # Instances answer for their manifest too, so callers holding an adapter
    # never need to reach for .class.
    def manifest
      self.class.manifest
    end

    # Bring upstream to the local canonical dir at +workdir+ (git pull,
    # rsync, HTTP crawl with cache). Must be resumable and rate-limit polite.
    # Returns a Nabu::FetchReport (sha, fetched_at, notes); raises
    # Nabu::FetchError on failure, which aborts the sync.
    def fetch(workdir)
      raise NotImplementedError, "#{self.class} must implement #fetch"
    end

    # Enumerate the ingestible documents found in +workdir+ as
    # Nabu::DocumentRef values (stable ids — stability across syncs is what
    # lets the loader detect upstream deletions).
    def discover(workdir)
      raise NotImplementedError, "#{self.class} must implement #discover"
    end

    # Parse the document behind one +document_ref+ into a Nabu::Document
    # with its ordered Nabu::Passage list.
    def parse(document_ref)
      raise NotImplementedError, "#{self.class} must implement #parse"
    end
  end
end
