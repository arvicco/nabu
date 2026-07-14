# frozen_string_literal: true

module Nabu
  # One per-language note a dictionary batch accretes into the history
  # ledger's language_notes (P18-5 — the P18-4 accumulated layer's first
  # programmatic writer). The parser mints it from upstream language
  # metadata (IE-CoR's languages.csv); Store::DictionaryLoader appends it
  # under the layer's append-only latest-per-(lang_code, kind) contract —
  # only when the latest stored body differs — with +source+ as the
  # per-record provenance ("iecor"; the seed keeps its own
  # "seed:config/languages.yml" provenance, never touched by this path).
  DictionaryLanguageNote = Data.define(:lang_code, :kind, :body, :source) do
    def initialize(lang_code:, kind:, body:, source:)
      super(
        lang_code: Model::Validation.present_string!(lang_code, field: "lang_code"),
        kind: Model::Validation.present_string!(kind, field: "kind"),
        body: Model::Validation.nfc_text!(body, field: "body"),
        source: Model::Validation.present_string!(source, field: "source")
      )
    end
  end

  # What a dictionary adapter's #parse returns (P11-4): one dictionary FILE's
  # worth of entries, tagged with the dictionary it belongs to. The
  # DictionaryDocument is to Store::DictionaryLoader what Nabu::Document is
  # to Store::Loader — same pure-domain stance (no Sequel, no persistence),
  # different content shape (entries, not passages).
  #
  # +slug+ names the DICTIONARY (lsj, lewis-short), not the file: a dictionary
  # split across many upstream files (LSJ ships 27) yields many
  # DictionaryDocuments sharing a slug, and the loader upserts entries by
  # (dictionary, entry_id) across all of them.
  class DictionaryDocument
    include Enumerable

    attr_reader :slug, :language, :title, :canonical_path

    def initialize(slug:, language:, title:, canonical_path:)
      @slug = Model::Validation.slug!(slug, field: "slug")
      @language = Model::Validation.language!(language)
      @title = Model::Validation.present_string!(title, field: "title")
      @canonical_path = Model::Validation.present_string!(canonical_path, field: "canonical_path")
      @entries_by_id = {}
      @language_notes = []
    end

    # Language notes riding this batch (P18-5): NOT entry content — they
    # never touch ContentHash or the catalog — the loader accretes them
    # into the ledger's language_notes idempotently after the file loads.
    attr_reader :language_notes

    def add_language_note(note)
      unless note.is_a?(DictionaryLanguageNote)
        raise ValidationError, "expected a Nabu::DictionaryLanguageNote, got #{note.inspect} (#{note.class})"
      end

      @language_notes << note
      self
    end

    # Append an entry; duplicate entry ids within one file are a parse bug.
    def <<(entry)
      unless entry.is_a?(DictionaryEntry)
        raise ValidationError, "expected a Nabu::DictionaryEntry, got #{entry.inspect} (#{entry.class})"
      end
      if @entries_by_id.key?(entry.entry_id)
        raise ValidationError, "duplicate entry id #{entry.entry_id.inspect} in dictionary file #{canonical_path}"
      end

      @entries_by_id[entry.entry_id] = entry
      self
    end
    alias append <<

    def entries = @entries_by_id.values

    def each(&)
      return enum_for(:each) { size } unless block_given?

      entries.each(&)
      self
    end

    def size = @entries_by_id.size
    alias length size

    def empty? = @entries_by_id.empty?
  end
end
