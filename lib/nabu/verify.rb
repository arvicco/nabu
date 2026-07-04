# frozen_string_literal: true

module Nabu
  # `nabu verify` — the integrity check of architecture §8: re-derive each
  # canonical document's content hash and compare it against the value the
  # catalog recorded at load time. A cronnable bitrot/tamper detector.
  #
  # == Why re-PARSE rather than re-read bytes
  #
  # The catalog's documents.content_sha256 is NOT a hash of the file's raw
  # bytes: it is Store::ContentHash.document over the *parsed* model
  # (urn/language/title/canonical_path + each passage's content hash). So the
  # only faithful way to reproduce it is to run the file back through the
  # source's adapter — discover→parse, exactly as the loader did — and re-hash
  # the resulting Document. That costs a full re-parse per source (Perseus is
  # ~20s), which is acceptable for a scheduled job and is the price of hashing
  # semantic content instead of bytes (a whitespace-only edit that the parser
  # ignores is correctly NOT flagged; a changed word IS).
  #
  # == Read-only
  #
  # Verify never writes: not to canonical/ (it only reads and parses) and not to
  # the catalog (it only SELECTs). It reuses the adapter's discover→parse but
  # shares no code path with the loader's persistence side.
  #
  # == What each document can be
  #
  # For every non-withdrawn catalog document of a registered source whose
  # canonical dir exists:
  #
  # - :ok         recomputed hash == stored hash.
  # - :mismatch   both present, hashes differ (bitrot/tamper). detail carries
  #               {stored:, recomputed:}.
  # - :missing    the canonical file at canonical_path is gone.
  # - :unparseable the file no longer parses (Nabu::ParseError), or is present
  #               but discover no longer yields it — itself a corruption signal.
  #               detail carries the reason string.
  #
  # Extra canonical files with no catalog row are NOT verify's concern (that is
  # sync drift, surfaced in sync reports); withdrawn documents are skipped.
  # A source with no canonical dir was never synced and is skipped with a note,
  # mirroring Rebuild.
  class Verify
    # One catalog document that failed verification.
    DocumentIssue = Data.define(:urn, :canonical_path, :kind, :detail)

    # One source's verification. +verified+ counts the non-withdrawn documents
    # checked; +issues+ is the (possibly empty) list of DocumentIssue.
    SourceOutcome = Data.define(:slug, :verified, :issues) do
      def ok? = issues.empty?
    end

    # A source left unchecked because it has no local canonical data.
    Skip = Data.define(:slug, :reason)

    # The whole run. Clean iff every checked source is ok.
    Result = Data.define(:outcomes, :skips) do
      def clean? = outcomes.all?(&:ok?)
      def issues = outcomes.flat_map(&:issues)
    end

    def initialize(config:, registry:, db:)
      @config = config
      @registry = registry
      @db = db
    end

    # Verify every registered source against the catalog. +progress+, when
    # given, is called with each SourceOutcome as it completes (live per-source
    # reporting; the runner stays print-free). Returns a Result.
    def run(progress: nil)
      outcomes = []
      skips = []
      @registry.each_source do |entry|
        workdir = workdir_for(entry.slug)
        if Dir.exist?(workdir) && !Dir.empty?(workdir)
          outcome = verify_source(entry, workdir)
          outcomes << outcome
          progress&.call(outcome)
        else
          skips << Skip.new(slug: entry.slug, reason: :no_canonical)
        end
      end
      Result.new(outcomes: outcomes, skips: skips)
    end

    private

    # Re-parse the whole canonical dir once, then reconcile every non-withdrawn
    # catalog document of this source against the fresh parse.
    def verify_source(entry, workdir)
      recomputed, unparseable = reparse(entry.adapter_class.new, workdir)
      documents = documents_for(entry.slug)
      issues = documents.filter_map { |doc| classify(doc, recomputed, unparseable) }
      SourceOutcome.new(slug: entry.slug, verified: documents.size, issues: issues)
    end

    # discover→parse the workdir. Returns [recomputed, unparseable]:
    # recomputed maps document urn => freshly recomputed content hash;
    # unparseable maps ref id (== document urn for every adapter) => error
    # message for files that raised Nabu::ParseError. A non-parse Nabu::Error
    # (fetch-level trouble) is left to propagate, exactly as the loader does.
    def reparse(adapter, workdir)
      recomputed = {}
      unparseable = {}
      adapter.discover(workdir).each do |ref|
        document =
          begin
            adapter.parse(ref)
          rescue Nabu::ParseError => e
            unparseable[ref.id] = e.message
            next
          end
        recomputed[document.urn] = document_hash(document)
      end
      [recomputed, unparseable]
    end

    # Decide one catalog document's fate against the fresh parse. Returns a
    # DocumentIssue or nil (verified clean).
    def classify(doc, recomputed, unparseable)
      urn = doc.fetch(:urn)
      path = doc.fetch(:canonical_path)
      if recomputed.key?(urn)
        return if recomputed[urn] == doc.fetch(:content_sha256)

        DocumentIssue.new(urn: urn, canonical_path: path, kind: :mismatch,
                          detail: { stored: doc.fetch(:content_sha256), recomputed: recomputed[urn] })
      elsif unparseable.key?(urn)
        DocumentIssue.new(urn: urn, canonical_path: path, kind: :unparseable, detail: unparseable[urn])
      elsif path.nil? || !File.exist?(path)
        DocumentIssue.new(urn: urn, canonical_path: path, kind: :missing, detail: nil)
      else
        # File is present but discover no longer yields it (e.g. a corrupted
        # header the adapter now skips): the document cannot be reconstructed.
        DocumentIssue.new(urn: urn, canonical_path: path, kind: :unparseable,
                          detail: "present but no longer discoverable in the workdir")
      end
    end

    # Reproduce the loader's document hash from a freshly parsed Document: hash
    # each passage in sequence order, then the document over those (see
    # Store::ContentHash and Store::Loader#upsert_document).
    def document_hash(document)
      passage_hashes = document.passages.map { |passage| Store::ContentHash.passage(passage) }
      Store::ContentHash.document(document, passage_hashes)
    end

    # Non-withdrawn catalog documents for this source, as plain rows. Withdrawn
    # documents are out of scope (they name no live canonical obligation).
    def documents_for(slug)
      source = @db[:sources].where(slug: slug).select(:id).first
      return [] if source.nil?

      @db[:documents]
        .where(source_id: source.fetch(:id), withdrawn: false)
        .select(:urn, :canonical_path, :content_sha256)
        .all
    end

    def workdir_for(slug) = File.join(@config.canonical_dir, slug)
  end
end
