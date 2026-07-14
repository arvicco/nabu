# frozen_string_literal: true

require "json"
require_relative "content_hash"
require_relative "../languages"

module Nabu
  module Store
    # Persists dictionary adapter output (P11-4) — the DICTIONARY-shaped
    # sibling of Store::Loader, sharing its idempotency / revision /
    # withdrawal semantics and its LoadReport shape, with entries where the
    # passage loader has documents+passages:
    #
    # - Dictionaries upsert on slug (metadata refresh only — a dictionary row
    #   is identity, not content). Entries upsert on (dictionary, entry_id):
    #   new → insert at revision 1 + provenance "loaded"; same content sha →
    #   skipped (no writes); different sha → fields updated, revision += 1,
    #   citations replaced wholesale (they are content, part of the sha),
    #   provenance "revised" + durable ledger revision.
    # - Full loads assert batch completeness: entries of this source's
    #   dictionaries absent from the batch are withdrawn, never deleted;
    #   withdrawn entries that reappear are restored.
    # - One transaction per dictionary FILE (a quarantined file never rolls
    #   back its siblings); Nabu::ParseError quarantines the file and the
    #   batch continues.
    # - LoadReport counts are ENTRY-grained (added/updated/skipped/withdrawn)
    #   except errored, which counts quarantined FILES — a dictionary "run"
    #   honestly reports how many entries moved.
    #
    # Retention granularity is the FILE: an upstream-deleted letter file is
    # atticked by GitFetch and rediscovered by discover_with_attic, so its
    # entries simply keep loading — there is no entry-level retired flag
    # (nothing upstream can delete a single entry without revising a file we
    # keep either way).
    class DictionaryLoader
      TOOL = "nabu-dictionary-loader"

      def initialize(db:, source:, ledger: nil)
        @db = db
        @source = source
        @ledger = ledger
      end

      # Load an enumerable of Nabu::DictionaryDocument values.
      def load(documents, full: true, on_document: nil)
        run(full: full, on_document: on_document) do |process, _quarantine|
          documents.each { |document| process.call(document) }
        end
      end

      # discover → parse → load straight off a dictionary adapter, attic
      # included (retained letter files rediscover; live wins on duplicates).
      def load_from(adapter, workdir:, full: true, on_document: nil)
        report = run(full: full, on_document: on_document) do |process, quarantine|
          adapter.discover_with_attic(workdir, on_superseded: method(:journal_superseded)).each do |ref|
            document =
              begin
                adapter.parse(ref)
              rescue Nabu::ParseError => e
                quarantine.call(ref, e)
                next
              end
            process.call(document)
          end
        end
        accrete_language_notes(adapter)
        report
      end

      private

      def run(full:, on_document: nil)
        counts = Hash.new(0)
        seen = Set.new
        processed = 0
        tick = lambda do
          processed += 1
          on_document&.call(processed, counts[:errored])
        end
        process = lambda do |document|
          load_document(document, counts, seen)
          tick.call
        end
        quarantine = lambda do |ref, error|
          counts[:errored] += 1
          journal(event: "quarantined", params: { "ref_id" => ref.id, "error" => error.message })
          tick.call
        end
        yield(process, quarantine)
        sweep_withdrawn(seen, counts) if full
        LoadReport.new(
          added: counts[:added], updated: counts[:updated], skipped: counts[:skipped],
          withdrawn: counts[:withdrawn], errored: counts[:errored]
        )
      end

      # One transaction per dictionary file; every entry present upstream
      # shields its row from the withdrawal sweep even if persisting fails
      # mid-file (the transaction rolls the file back as one unit).
      def load_document(document, counts, seen)
        @db.transaction do
          dictionary = upsert_dictionary(document)
          census = Hash.new(0)
          document.each do |entry|
            seen.add([document.slug, entry.entry_id])
            counts[upsert_entry(dictionary, document, entry)] += 1
            entry.reflexes.each { |reflex| census[[reflex.lang_code, reflex.lang_name]] += 1 if reflex.lang_name }
          end
          replace_name_census(dictionary, census)
        end
      rescue Sequel::DatabaseError => e
        counts[:errored] += 1
        journal(event: "quarantined", params: { "path" => document.canonical_path, "error" => e.message })
      end

      # P18-6: the language-notes rider — an adapter that declares
      # .language_notes ([lang_code, kind, body] rows; LIV/EDL stage
      # witnesses) accretes them into the ledger with its own id as the
      # per-record provenance, idempotently (Languages.accrete!'s
      # latest-body rule — a re-sync appends nothing). Ledger-optional and
      # table-guarded like every accumulated-layer touch; catalog loads
      # without a ledger simply skip the rider.
      def accrete_language_notes(adapter)
        return unless @ledger && adapter.class.respond_to?(:language_notes)

        Nabu::Languages.accrete!(ledger: @ledger, notes: adapter.class.language_notes,
                                 source: adapter.manifest.id)
      end

      # P18-4: the derived language-name census (migration 011) — what the
      # batch's descendants nodes CALL each lang_code, counted raw ("Cyrillic
      # script" wrapper noise included; Nabu::Languages filters at read).
      # Replaced wholesale per dictionary like reflexes, inside the file
      # transaction — but ONLY when this batch carries names at all: a
      # reflex-less shelf (the TEI lexica) or a pre-P18-4 parse writes
      # nothing and leaves any existing census alone. Every reflex-bearing
      # dictionary today is a single-file kaikki extract, so file == full
      # census; a future multi-file reflex dictionary would need per-file
      # keying (noted, not built).
      def replace_name_census(dictionary, census)
        return if census.empty?

        LanguageName.where(dictionary_id: dictionary.id).delete
        census.each do |(lang_code, name), occurrences|
          LanguageName.create(dictionary_id: dictionary.id, lang_code: lang_code,
                              name: name, occurrences: occurrences)
        end
      end

      # Identity + metadata refresh, no revision bookkeeping: the dictionary
      # row is a namespace, its content lives in the entries.
      def upsert_dictionary(document)
        row = Dictionary.first(slug: document.slug)
        attrs = { source_id: @source.id, title: document.title, language: document.language }
        return Dictionary.create(slug: document.slug, **attrs) if row.nil?

        row.update(attrs)
        row
      end

      def upsert_entry(dictionary, document, entry)
        sha = ContentHash.dictionary_entry(entry)
        row = DictionaryEntry.first(dictionary_id: dictionary.id, entry_id: entry.entry_id)
        return insert_entry(dictionary, document, entry, sha) if row.nil?

        if row.content_sha256 == sha
          return :skipped unless row.withdrawn

          restore(row)
        else
          revise_entry(row, entry, sha)
        end
        :updated
      end

      def insert_entry(dictionary, document, entry, sha)
        row = DictionaryEntry.create(
          dictionary_id: dictionary.id, urn: entry_urn(document.slug, entry),
          entry_id: entry.entry_id, key_raw: entry.key_raw,
          headword: entry.headword, headword_folded: entry.headword_folded,
          gloss: entry.gloss, body: entry.body,
          content_sha256: sha, revision: 1, withdrawn: false
        )
        insert_citations(row, entry)
        insert_reflexes(row, entry)
        journal(event: "loaded", dictionary_entry_id: row.id)
        :added
      end

      def revise_entry(row, entry, sha)
        old_sha = row.content_sha256
        was_withdrawn = row.withdrawn
        row.update(
          key_raw: entry.key_raw, headword: entry.headword,
          headword_folded: entry.headword_folded, gloss: entry.gloss, body: entry.body,
          content_sha256: sha, revision: row.revision + 1, withdrawn: false
        )
        DictionaryCitation.where(dictionary_entry_id: row.id).delete
        insert_citations(row, entry)
        DictionaryReflex.where(dictionary_entry_id: row.id).delete
        insert_reflexes(row, entry)
        journal(event: "revised", dictionary_entry_id: row.id,
                params: { "old_sha" => old_sha, "new_sha" => sha })
        durable(event: "revised", urn: row.urn, old_sha: old_sha, new_sha: sha)
        return unless was_withdrawn

        journal(event: "restored", dictionary_entry_id: row.id)
        durable(event: "restored", urn: row.urn, new_sha: sha)
      end

      def insert_citations(row, entry)
        entry.citations.each_with_index do |citation, seq|
          DictionaryCitation.create(
            dictionary_entry_id: row.id, seq: seq,
            urn_raw: citation.urn_raw, cts_work: citation.cts_work,
            citation: citation.citation, label: citation.label
          )
        end
      end

      # P14-1: reflexes persist like citations — content of the entry,
      # replaced wholesale on revision, resolved only at query time.
      def insert_reflexes(row, entry)
        entry.reflexes.each_with_index do |reflex, seq|
          DictionaryReflex.create(
            dictionary_entry_id: row.id, seq: seq,
            lang_code: reflex.lang_code, language: reflex.language,
            word: reflex.word, roman: reflex.roman,
            word_folded: reflex.word_folded, roman_folded: reflex.roman_folded,
            borrowed: reflex.borrowed
          )
        end
      end

      def restore(row)
        row.update(withdrawn: false)
        journal(event: "restored", dictionary_entry_id: row.id)
        durable(event: "restored", urn: row.urn, new_sha: row.content_sha256)
      end

      # Full loads assert completeness across this SOURCE's dictionaries.
      def sweep_withdrawn(seen, counts)
        @db.transaction do
          dictionaries = Dictionary.where(source_id: @source.id).to_h { |row| [row.id, row.slug] }
          DictionaryEntry.where(dictionary_id: dictionaries.keys, withdrawn: false).each do |row|
            next if seen.include?([dictionaries.fetch(row.dictionary_id), row.entry_id])

            row.update(withdrawn: true)
            journal(event: "withdrawn", dictionary_entry_id: row.id)
            durable(event: "withdrawn", urn: row.urn, old_sha: row.content_sha256)
            counts[:withdrawn] += 1
          end
        end
      end

      # An attic duplicate of a live letter file: journal once, stay silent
      # in steady state (the passage loader's stance).
      def journal_superseded(ref)
        params = { "ref_id" => ref.id, "attic_path" => ref.path }
        return unless Provenance.where(event: "superseded", tool: TOOL,
                                       params_json: JSON.generate(params)).empty?

        journal(event: "superseded", params: params)
      end

      def entry_urn(slug, entry)
        "urn:nabu:dict:#{slug}:#{entry.entry_id}"
      end

      def journal(event:, dictionary_entry_id: nil, params: nil)
        Provenance.create(
          event: event, dictionary_entry_id: dictionary_entry_id,
          tool: TOOL, tool_version: Nabu::VERSION,
          params_json: params && JSON.generate(params),
          at: Time.now
        )
      end

      def durable(event:, urn:, old_sha: nil, new_sha: nil)
        return unless @ledger

        Revision.create(urn: urn, event: event, old_sha: old_sha, new_sha: new_sha, at: Time.now)
      end
    end
  end
end
