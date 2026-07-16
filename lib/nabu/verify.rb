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
    # catalog document of this source against the fresh parse. Routes by the
    # adapter's declared content_kind (P11-7 fix 2): dictionary sources verify
    # their ENTRIES (they carry no documents.urn — the old code called
    # document.urn on a DictionaryDocument and the crash aborted the WHOLE verify
    # run, leaving every later source unchecked).
    def verify_source(entry, workdir)
      adapter = entry.build_adapter
      return verify_dictionary_source(entry, adapter, workdir) if adapter.class.content_kind == :dictionary
      return verify_language_source(entry, adapter, workdir) if adapter.class.content_kind == :language
      return verify_notes_source(entry, adapter, workdir) if adapter.class.content_kind == :notes
      return verify_source_shelf(entry, adapter, workdir) if adapter.class.content_kind == :source

      recomputed, unparseable = reparse(adapter, workdir)
      documents = documents_for(entry.slug)
      issues = documents.filter_map { |doc| classify(doc, recomputed, unparseable) }
      SourceOutcome.new(slug: entry.slug, verified: documents.size, issues: issues)
    end

    # A dictionary source verifies by re-deriving each entry's content hash
    # (Store::ContentHash.dictionary_entry, the same value DictionaryLoader
    # stored) and reconciling it against the catalog's dictionary_entries rows
    # by their urn (urn:nabu:dict:<slug>:<entry_id>). Same fate vocabulary as
    # documents (ok/mismatch/unparseable); entries carry no per-entry file so
    # :missing never applies (the source-level workdir check already covers a
    # vanished clone).
    def verify_dictionary_source(entry, adapter, workdir)
      recomputed = reparse_dictionary(adapter, workdir)
      entries = dictionary_entries_for(entry.slug)
      issues = entries.filter_map { |row| classify_entry(row, recomputed) }
      SourceOutcome.new(slug: entry.slug, verified: entries.size, issues: issues)
    end

    # A language dossier shelf (P19-1) verifies by re-parsing the dossiers
    # and diffing the derived rows they yield against the catalog's
    # language_records, per code. Records carry no stored sha (they ARE the
    # content), so the comparison is the row set itself: a code whose rows
    # differ is :mismatch, a code with rows but no parseable dossier (file
    # gone or malformed) is :missing/:unparseable — the same fate vocabulary.
    def verify_language_source(entry, adapter, workdir)
      return SourceOutcome.new(slug: entry.slug, verified: 0, issues: []) \
        unless @db.table_exists?(:language_records)

      reparsed = reparse_dossiers(adapter, workdir)
      codes = @db[:language_records].distinct.select_map(:lang_code).sort
      issues = codes.filter_map { |code| classify_code(entry, code, reparsed) }
      SourceOutcome.new(slug: entry.slug, verified: codes.size, issues: issues)
    end

    # The owner-notes shelf (P24-1) verifies the dossier way: re-parse the
    # topic files and diff the derived rows they yield against the catalog's
    # urn_notes, per topic. Rows carry no stored sha (they ARE the content),
    # so the comparison is the row set itself — the same fate vocabulary
    # (:mismatch / :missing / :unparseable).
    def verify_notes_source(entry, adapter, workdir)
      return SourceOutcome.new(slug: entry.slug, verified: 0, issues: []) \
        unless @db.table_exists?(:urn_notes)

      reparsed = reparse_notes(adapter, workdir)
      topics = @db[:urn_notes].distinct.select_map(:topic).sort
      issues = topics.filter_map { |topic| classify_topic(entry, topic, reparsed) }
      SourceOutcome.new(slug: entry.slug, verified: topics.size, issues: issues)
    end

    # { topic => derived row set } from a fresh discover→parse (attic
    # included; Store::NoteLoader.rows_for, so load and check never drift);
    # a malformed topic file contributes its error instead.
    def reparse_notes(adapter, workdir)
      reparsed = {}
      adapter.discover_with_attic(workdir).each do |ref|
        note_file = adapter.parse(ref)
        reparsed[note_file.topic] = Store::NoteLoader.rows_for(note_file)
      rescue Nabu::ParseError => e
        reparsed[ref.metadata.fetch("topic", ref.id)] = e.message
      end
      reparsed
    end

    def classify_topic(entry, topic, reparsed)
      stored = @db[:urn_notes].where(topic: topic).order(:id)
                              .select(:urn, :note, :topic, :tags, :added, :provenance).all
      urn = "#{entry.slug}:#{topic}"
      fresh = reparsed[topic]
      return DocumentIssue.new(urn: urn, canonical_path: nil, kind: :missing, detail: nil) if fresh.nil?
      return DocumentIssue.new(urn: urn, canonical_path: nil, kind: :unparseable, detail: fresh) if fresh.is_a?(String)
      return nil if fresh == stored

      DocumentIssue.new(urn: urn, canonical_path: nil, kind: :mismatch,
                        detail: "derived notes differ from the reparsed topic file")
    end

    # { code => [[kind, body, source], …] } from a fresh discover→parse
    # (attic included); a malformed dossier contributes its error instead.
    def reparse_dossiers(adapter, workdir)
      reparsed = {}
      adapter.discover_with_attic(workdir).each do |ref|
        dossier = adapter.parse(ref)
        reparsed[dossier.code] = dossier.records.map { |r| [r.kind, r.body, r.source] }.sort
      rescue Nabu::ParseError => e
        reparsed[ref.metadata.fetch("code", ref.id)] = e.message
      end
      reparsed
    end

    def classify_code(entry, code, reparsed)
      stored = @db[:language_records].where(lang_code: code)
                                     .map { |row| [row[:kind], row[:body], row[:source]] }.sort
      urn = "#{entry.slug}:#{code}"
      fresh = reparsed[code]
      return DocumentIssue.new(urn: urn, canonical_path: nil, kind: :missing, detail: nil) if fresh.nil?
      return DocumentIssue.new(urn: urn, canonical_path: nil, kind: :unparseable, detail: fresh) if fresh.is_a?(String)
      return nil if fresh == stored

      DocumentIssue.new(urn: urn, canonical_path: nil, kind: :mismatch,
                        detail: "derived records differ from the reparsed dossier")
    end

    # The source-dossier shelf (P24-0) verifies exactly as the language
    # shelf does, at the slug grain: re-parse the dossiers, diff the derived
    # rows against source_records — the same fate vocabulary.
    def verify_source_shelf(entry, adapter, workdir)
      return SourceOutcome.new(slug: entry.slug, verified: 0, issues: []) \
        unless @db.table_exists?(:source_records)

      reparsed = reparse_source_dossiers(adapter, workdir)
      slugs = @db[:source_records].distinct.select_map(:slug).sort
      issues = slugs.filter_map { |slug| classify_source_slug(entry, slug, reparsed) }
      SourceOutcome.new(slug: entry.slug, verified: slugs.size, issues: issues)
    end

    # { slug => [[kind, body, provenance], …] } from a fresh discover→parse
    # (attic included); a malformed dossier contributes its error instead.
    def reparse_source_dossiers(adapter, workdir)
      reparsed = {}
      adapter.discover_with_attic(workdir).each do |ref|
        dossier = adapter.parse(ref)
        reparsed[dossier.slug] = dossier.records.map { |r| [r.kind, r.body, r.provenance] }.sort
      rescue Nabu::ParseError => e
        reparsed[ref.metadata.fetch("slug", ref.id)] = e.message
      end
      reparsed
    end

    def classify_source_slug(entry, slug, reparsed)
      stored = @db[:source_records].where(slug: slug)
                                   .map { |row| [row[:kind], row[:body], row[:provenance]] }.sort
      urn = "#{entry.slug}:#{slug}"
      fresh = reparsed[slug]
      return DocumentIssue.new(urn: urn, canonical_path: nil, kind: :missing, detail: nil) if fresh.nil?
      return DocumentIssue.new(urn: urn, canonical_path: nil, kind: :unparseable, detail: fresh) if fresh.is_a?(String)
      return nil if fresh == stored

      DocumentIssue.new(urn: urn, canonical_path: nil, kind: :mismatch,
                        detail: "derived records differ from the reparsed dossier")
    end

    # discover→parse the workdir — attic included (P5-2): retired documents
    # are live catalog rows whose canonical_path points under .attic, so they
    # carry the same integrity obligation as any other. Returns [recomputed,
    # unparseable]: recomputed maps document urn => freshly recomputed content
    # hash; unparseable maps ref id (== document urn for every adapter) =>
    # error message for files that raised Nabu::ParseError. A non-parse
    # Nabu::Error (fetch-level trouble) is left to propagate, exactly as the
    # loader does.
    def reparse(adapter, workdir)
      recomputed = {}
      unparseable = {}
      adapter.discover_with_attic(workdir).each do |ref|
        document =
          begin
            adapter.parse(ref)
          rescue Nabu::DocumentSkipped
            # Declined by rule (P11-7): a catalog-only skeleton was never loaded,
            # so it names no catalog row to verify. Skip it — NOT unparseable,
            # and above all not a crash that aborts the whole verify run.
            next
          rescue Nabu::ParseError => e
            unparseable[ref.id] = e.message
            next
          end
        recomputed[document.urn] = document_hash(document)
      end
      [recomputed, unparseable]
    end

    # discover→parse a dictionary adapter, mapping each freshly parsed entry's
    # urn to its recomputed content hash. A file that no longer parses
    # (Nabu::ParseError) or is declined by rule (Nabu::DocumentSkipped) simply
    # contributes no entries — its catalog rows then fall to :unparseable below,
    # the same corruption signal a vanished document raises.
    def reparse_dictionary(adapter, workdir)
      recomputed = {}
      adapter.discover_with_attic(workdir).each do |ref|
        document =
          begin
            adapter.parse(ref)
          rescue Nabu::ParseError, Nabu::DocumentSkipped
            next
          end
        document.each do |entry|
          recomputed["urn:nabu:dict:#{document.slug}:#{entry.entry_id}"] =
            Store::ContentHash.dictionary_entry(entry)
        end
      end
      recomputed
    end

    # One dictionary entry row's fate against the fresh parse.
    def classify_entry(row, recomputed)
      urn = row.fetch(:urn)
      stored = row.fetch(:content_sha256)
      if recomputed.key?(urn)
        return if recomputed[urn] == stored

        DocumentIssue.new(urn: urn, canonical_path: nil, kind: :mismatch,
                          detail: { stored: stored, recomputed: recomputed[urn] })
      else
        DocumentIssue.new(urn: urn, canonical_path: nil, kind: :unparseable,
                          detail: "entry no longer present in the reparsed dictionary")
      end
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

    # Non-withdrawn dictionary_entries rows for this source's dictionaries, as
    # plain {urn:, content_sha256:} rows.
    def dictionary_entries_for(slug)
      source = @db[:sources].where(slug: slug).select(:id).first
      return [] if source.nil?

      dictionary_ids = @db[:dictionaries].where(source_id: source.fetch(:id)).select_map(:id)
      return [] if dictionary_ids.empty?

      @db[:dictionary_entries]
        .where(dictionary_id: dictionary_ids, withdrawn: false)
        .select(:urn, :content_sha256)
        .all
    end

    def workdir_for(slug) = File.join(@config.canonical_dir, slug)
  end
end
