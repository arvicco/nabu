# frozen_string_literal: true

module Nabu
  # What Adapter#parse returns: one work/edition plus its ordered passages.
  # Unlike the Data values it has identity and a mutable (append-only)
  # collection, so it is a plain class — but it stays pure domain: no Sequel,
  # no persistence knowledge. The loader reads urn/language/title/
  # canonical_path/metadata and the passages; everything else about storage
  # (ids, hashing, revisions) happens on the loader's side.
  #
  # Ordering: passages enumerate in +sequence+ order, not append order, since
  # sequence is the domain's explicit ordering. Appending a passage whose urn
  # or sequence duplicates an existing one raises — both are parse bugs the
  # conformance suite would otherwise catch much later.
  class Document
    include Enumerable

    attr_reader :urn, :language, :title, :canonical_path, :metadata

    def initialize(urn:, language:, canonical_path:, title: nil, metadata: {})
      @urn = Model::Validation.urn!(urn)
      @language = Model::Validation.language!(language)
      @title = title.nil? ? nil : Model::Validation.present_string!(title, field: "title")
      @canonical_path = Model::Validation.present_string!(canonical_path, field: "canonical_path")
      @metadata = Model::Validation.json_hash!(metadata, field: "metadata")
      @passages_by_urn = {}
      @passages_by_sequence = {}
    end

    # Append a passage; returns self so appends chain. Rejects non-Passage
    # values and duplicate passage urns/sequences within this document.
    def <<(passage)
      unless passage.is_a?(Passage)
        raise ValidationError, "expected a Nabu::Passage, got #{passage.inspect} (#{passage.class})"
      end
      if @passages_by_urn.key?(passage.urn)
        raise ValidationError, "duplicate passage urn #{passage.urn.inspect} in document #{urn.inspect}"
      end
      if @passages_by_sequence.key?(passage.sequence)
        raise ValidationError, "duplicate passage sequence #{passage.sequence} in document #{urn.inspect}"
      end

      @passages_by_urn[passage.urn] = passage
      @passages_by_sequence[passage.sequence] = passage
      self
    end
    alias append <<

    # Passages in sequence order, as a defensive copy.
    def passages
      @passages_by_sequence.keys.sort.map { |sequence| @passages_by_sequence[sequence] }
    end

    def each(&)
      return enum_for(:each) { size } unless block_given?

      passages.each(&)
      self
    end

    def size
      @passages_by_sequence.size
    end
    alias length size

    def empty?
      @passages_by_sequence.empty?
    end
  end
end
