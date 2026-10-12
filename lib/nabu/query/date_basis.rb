# frozen_string_literal: true

require_relative "../errors"

module Nabu
  module Query
    # The date-basis vocabulary (P122-1): what a timeline row's envelope is
    # a date OF, as document_axes.date_class stores it (migration 034).
    # NULL — every row an extractor mints without a class — is the source's
    # own artifact/typed date (a findspot dating, a manuscript origDate) and
    # reads as "artifact"; "composition" is attributed author-era dating
    # (the aggressive-mining law's own labeled class); "edition" is a
    # print/edition year that must never masquerade as the text's dating
    # (P109-4). The set is CLOSED: a class reaches the timeline only through
    # an extractor that mints it, so a new class is a deliberate addition
    # here, never a string that silently matches nothing.
    #
    # `search --date-basis` filters on the class of a document's PRIMARY
    # dated row — the one `nabu show` renders and `export documents
    # --with-axes` ships: document grain, at least one bound, the earliest
    # by coalesce(not_before, not_after), then row id. The holdout
    # discipline for dating research as a flag, not a join.
    module DateBasis
      ARTIFACT = "artifact"
      COMPOSITION = "composition"
      EDITION = "edition"

      KNOWN = [ARTIFACT, COMPOSITION, EDITION].freeze

      module_function

      # A --date-basis value (a comma list String, or an Array of names) →
      # the sorted, de-duplicated class list; nil when absent. An unknown
      # name is refused naming the known set (never a silent empty page);
      # an empty list is refused too — "no basis" is the absence of the
      # flag.
      def parse(value)
        return nil if value.nil?

        names = Array(value).flat_map { |item| item.to_s.split(",") }
                            .map { |name| name.strip.downcase }
                            .reject(&:empty?).uniq
        raise Nabu::Error, "date basis: give at least one class (#{KNOWN.join(', ')})" if names.empty?

        unknown = names - KNOWN
        unless unknown.empty?
          raise Nabu::Error, "unknown date basis #{unknown.map(&:inspect).join(', ')} " \
                             "(choose from #{KNOWN.join(', ')})"
        end
        names.sort
      end
    end
  end
end
