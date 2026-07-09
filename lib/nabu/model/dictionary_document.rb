# frozen_string_literal: true

module Nabu
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
