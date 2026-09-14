# frozen_string_literal: true

require "json"

module Nabu
  module Store
    # The kind-axis projection (P99-2 — №R-63): a derived pass beside
    # FacetBuilder that reads each ruled source's mapped facet rows (or
    # applies its whole-source source_kind declaration), normalizes them
    # through Nabu::Kinds (§4b: strip, split, exact → prefix → range),
    # and writes facet="kind" rows into document_facets — value = the
    # class path, raw = the upstream value verbatim (the honesty
    # invariant: the upstream claim is never altered; the source facet
    # rows stay untouched beside these).
    #
    # Derivable by construction: kind rows are f(document_facets +
    # config), themselves f(canonical) — drop-and-reproject lifecycle,
    # rebuilt after FacetBuilder (which re-mints the input rows) and
    # refreshed per source after every sync (the P47-r3 lesson: no lane
    # may lag a sync). +kinds+ nil = the lane-off posture (a clone
    # without the config files) — zero rows, never an error.
    module KindBuilder
      FACET = "kind"
      INSERT_SLICE = 2_000

      Summary = Data.define(:documents, :rows)

      module_function

      def rebuild!(catalog:, kinds:, progress: nil, canonical_dir: nil)
        catalog[:document_facets].where(facet: FACET).delete
        catalog[:kind_stats].delete if catalog.table_exists?(:kind_stats)
        return Summary.new(documents: 0, rows: 0) if kinds.nil?

        documents = 0
        rows = 0
        kinds.sources.each do |slug|
          slug_docs, slug_rows = project_source(catalog, kinds, slug, canonical_dir)
          documents += slug_docs
          rows += slug_rows
          progress&.load_tick("kind: #{slug} — #{slug_rows} rows")
        end
        Summary.new(documents: documents, rows: rows)
      end

      # Drop and re-project ONE source's kind rows (SyncRunner's
      # post-load seam). Returns the row count; an unruled slug just
      # clears any stale rows and reports zero.
      def refresh_source!(catalog:, kinds:, slug:, canonical_dir: nil)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        doc_ids = catalog[:documents].where(source_id: source_id).select(:id)
        catalog[:document_facets].where(facet: FACET, document_id: doc_ids).delete
        catalog[:kind_stats].where(source_id: source_id).delete if source_id && catalog.table_exists?(:kind_stats)
        return 0 if kinds.nil? || !kinds.sources.include?(slug)

        project_source(catalog, kinds, slug, canonical_dir).last
      end

      def project_source(catalog, kinds, slug, canonical_dir = nil)
        source_id = catalog[:sources].where(slug: slug).get(:id)
        return [0, 0] if source_id.nil?

        rows = if kinds.source_kind(slug)
                 declaration_rows(catalog, kinds, slug, source_id)
               elsif kinds.metadata_for(slug)
                 metadata_rows(catalog, kinds, slug, source_id)
               elsif kinds.walk_for(slug)
                 walk_rows(catalog, kinds, slug, source_id, canonical_dir)
               else
                 mapped_rows(catalog, kinds, slug, source_id)
               end
        rows.each_slice(INSERT_SLICE) { |slice| catalog[:document_facets].multi_insert(slice) }
        write_stats(catalog, source_id, rows)
        [rows.map { |row| row[:document_id] }.uniq.size, rows.size]
      end

      # The precompiled census (migration 032): per (source, head)
      # distinct docs + one NULL-head total row per source, aggregated
      # from the rows just projected — so `nabu kind census` never
      # groups the millions (the desk-commands law).
      def write_stats(catalog, source_id, rows)
        return unless catalog.table_exists?(:kind_stats)

        heads = Hash.new { |hash, key| hash[key] = {} }
        total = {}
        rows.each do |row|
          heads[row[:value].split("/", 2).first][row[:document_id]] = true
          total[row[:document_id]] = true
        end
        stats = heads.map { |head, docs| { source_id: source_id, head: head, documents: docs.size } }
        stats << { source_id: source_id, head: nil, documents: total.size } unless total.empty?
        catalog[:kind_stats].multi_insert(stats)
      end

      # source_kind: one row per live document — the whole-source claim
      # (okhc's dynastic histories). raw stays nil: a declaration, not
      # an upstream value.
      def declaration_rows(catalog, kinds, slug, source_id)
        path = kinds.source_kind(slug)
        catalog[:documents]
          .where(source_id: source_id, withdrawn: false)
          .select_map(:id)
          .map { |id| { document_id: id, facet: FACET, value: path, raw: nil } }
      end

      # Metadata-mapped (P100-1): the declared metadata_json fields read
      # per live document — an ARRAY value takes its FIRST element (a
      # category path is a hierarchy, not a multi-label), each declared
      # field maps independently, a document without the field
      # contributes nothing (absence, never "unmapped"). metadata_json
      # is our own canonical_json output, so a parse failure is real
      # corruption and honestly raises (the FacetBuilder stance).
      def metadata_rows(catalog, kinds, slug, source_id)
        fields = kinds.metadata_for(slug)
        rows = []
        seen = Hash.new { |hash, key| hash[key] = {} }
        catalog[:documents]
          .where(source_id: source_id, withdrawn: false)
          .exclude(metadata_json: nil)
          .select_map(%i[id metadata_json]).each do |document_id, json|
            parsed = JSON.parse(json)
            fields.each do |field|
              value = parsed[field]
              value = value.first if value.is_a?(Array)
              next if value.nil? || value.to_s.empty?

              kinds.normalize(slug, value.to_s).each do |path|
                next if seen[document_id].key?(path)

                seen[document_id][path] = true
                rows << { document_id: document_id, facet: FACET, value: path, raw: value.to_s }
              end
            end
          end
        rows
      end

      # Canonical-tree walkers (P100-3): sidecar files no facet or
      # metadata field carries. Without canonical_dir the walk skips to
      # zero rows honestly (a caller that cannot name the corpus root).
      def walk_rows(catalog, kinds, slug, _source_id, canonical_dir)
        return [] if canonical_dir.nil?

        case kinds.walk_for(slug)
        when "hgv-keywords" then hgv_keyword_rows(catalog, kinds, slug, canonical_dir)
        else []
        end
      end

      # The papyri HGV text types (the TimelineBuilder walk precedent):
      # each HGV_meta_EpiDoc record's LEADING `<keywords scheme="hgv">`
      # term is the text type (later terms are subjects — never read),
      # joined ddb-hybrid → urn → document like the timeline lane.
      def hgv_keyword_rows(catalog, kinds, slug, canonical_dir)
        hgv_dir = File.join(canonical_dir, TimelineBuilder::HGV_SLUG, TimelineBuilder::HGV_SUBDIR)
        return [] unless Dir.exist?(hgv_dir)

        ddbdp = catalog[:documents]
                .where(Sequel.like(:urn, "#{TimelineBuilder::DDBDP_PREFIX}%"))
                .where(withdrawn: false)
                .select_hash(:urn, :id)
        rows = []
        seen = Hash.new { |hash, key| hash[key] = {} }
        Dir.glob(File.join(hgv_dir, "**", "*.xml")).each do |path|
          hybrid, term = hgv_leading_term(File.read(path))
          next if hybrid.nil? || term.nil?

          document_id = ddbdp["#{TimelineBuilder::DDBDP_PREFIX}#{hybrid.tr(';', ':')}"] or next
          kinds.normalize(slug, term).each do |kind_path|
            next if seen[document_id].key?(kind_path)

            seen[document_id][kind_path] = true
            rows << { document_id: document_id, facet: FACET, value: kind_path, raw: term }
          end
        end
        rows
      end

      def hgv_leading_term(xml)
        doc = Nokogiri::XML(xml)
        doc.remove_namespaces!
        hybrid = doc.at_xpath("//idno[@type='ddb-hybrid']")&.text&.strip
        term = doc.at_xpath("//keywords[@scheme='hgv']/term")&.text&.strip
        [hybrid, (term unless term.to_s.empty?)]
      end

      # Facet-mapped: each (document, value) of the source's declared
      # facet normalizes to 0..n class paths, deduped per document.
      def mapped_rows(catalog, kinds, slug, source_id)
        facet = kinds.facet_for(slug)
        seen = Hash.new { |hash, key| hash[key] = {} }
        rows = []
        catalog[:document_facets]
          .where(facet: facet)
          .where(document_id: catalog[:documents].where(source_id: source_id).select(:id))
          .select_map(%i[document_id value]).each do |document_id, value|
            kinds.normalize(slug, value).each do |path|
              next if seen[document_id].key?(path)

              seen[document_id][path] = true
              rows << { document_id: document_id, facet: FACET, value: path, raw: value }
            end
          end
        rows
      end
    end
  end
end
