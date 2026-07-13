# frozen_string_literal: true

module Nabu
  module Query
    # The slice scope grammar shared by the corpus-slice surfaces (Formulas —
    # P15-5, BatchParallels — P16-1): SCOPE is a source slug (exact — "aspr")
    # when one exists, else a DOCUMENT-urn prefix. A document urn is a prefix
    # of its passages' urns, so a whole work
    # ("urn:cts:greekLit:tlg0012.tlg001.perseus-grc2") OR a super-prefix
    # spanning several works ("urn:cts:greekLit:tlg0012" = Iliad + Odyssey)
    # scopes its passages through the join. One module so the two surfaces can
    # never drift: a slice mined by formulas is the same slice batch-parallels
    # walks.
    #
    # Expects the including class to hold the catalog handle in @catalog
    # (the CatalogJoin convention).
    module Scope
      private

      def source_slug?(scope)
        @catalog[:sources].where(slug: scope).any?
      end

      # A byte-range prefix match (BINARY collation) over the DOCUMENT urn:
      # urn >= prefix AND urn < prefix + max-codepoint — no LIKE, so nothing
      # to escape, and it rides the documents.urn unique index (then joins to
      # passages by document_id, the fast path — measured 0.16 s on Homer; the
      # passages.urn variant defeated the index at 2 s). Document-grain by
      # design: a source slug, a whole work, or a super-prefix over several
      # works. A prefix finer than a document urn is not a v1 slice.
      def prefix_match(prefix)
        doc = Sequel[:documents][:urn]
        Sequel.expr(doc >= prefix) & (doc < "#{prefix}\u{10FFFF}")
      end

      # The scoped visible passages: slug (exact) else document-urn prefix,
      # over the shared visibility+filter join (CatalogJoin).
      def scoped_passages(scope, lang:)
        base = visible_passages(lang: lang, license: nil)
        if source_slug?(scope)
          base.where(Sequel[:sources][:slug] => scope)
        else
          base.where(prefix_match(scope))
        end
      end
    end
  end
end
