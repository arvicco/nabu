# frozen_string_literal: true

module Nabu
  # A pointer to one ingestible document in canonical/: what Adapter#discover
  # yields and Adapter#parse consumes. Carries no parsed content.
  #
  # - +source_id+: the owning source's manifest id (slug).
  # - +id+: identifier for the document, unique within the source and *stable
  #   across syncs* (typically the path relative to canonical/<source>/, or an
  #   upstream work id). Stability is what lets the loader detect upstream
  #   deletions (refs no longer yielded → rows marked withdrawn).
  # - +path+: canonical filesystem path parse should read.
  # - +metadata+: optional adapter-private hints carried from discover to
  #   parse (e.g. a language detected from directory layout). JSON data only,
  #   so a ref can be logged/journaled verbatim.
  DocumentRef = Data.define(:source_id, :id, :path, :metadata) do
    def initialize(source_id:, id:, path:, metadata: {})
      super(
        source_id: Model::Validation.slug!(source_id, field: "source_id"),
        id: Model::Validation.present_string!(id, field: "id"),
        path: Model::Validation.present_string!(path, field: "path"),
        metadata: Model::Validation.json_hash!(metadata, field: "metadata")
      )
    end
  end
end
