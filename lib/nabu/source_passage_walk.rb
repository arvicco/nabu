# frozen_string_literal: true

module Nabu
  # One source's live passages in id order, read in rowid windows — the
  # PlaceMine walk (a rowid RANGE per window, no join, no ORDER BY over
  # the whole slice: the keyset page with a join sorted every remaining
  # passage on each page), filtered to the source's live documents in
  # Ruby. Same rows, same order, as passages ⋈ documents ⋈ sources WHERE
  # live AND slug ORDER BY id. Shared by the person lanes (PersonMine,
  # PersonCandidates); yields { id:, document_id:, text: } rows.
  module SourcePassageWalk
    WINDOW = 5_000

    module_function

    def each(catalog, source, window: WINDOW)
      documents = catalog[:documents]
                  .where(withdrawn: false, source_id: catalog[:sources].where(slug: source).select(:id))
                  .select_map(:id)
      return if documents.empty?

      first, last = catalog[:passages].where(document_id: documents).get { [min(id).as(:first), max(id).as(:last)] }
      return if first.nil?

      live = documents.to_set
      low = first
      while low <= last
        high = [low + window - 1, last].min
        catalog[:passages].where(id: low..high, withdrawn: false).order(:id)
                          .select(:id, :document_id, :text).all.each do |row|
          yield row if live.include?(row[:document_id])
        end
        low = high + 1
      end
    end
  end
end
