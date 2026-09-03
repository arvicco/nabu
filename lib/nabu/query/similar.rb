# frozen_string_literal: true

require_relative "stored_snippet"

module Nabu
  module Query
    # P93-5 (№R-36): `search --similar <urn>` — same-language semantic /
    # cross-edition retrieval over the vector store `nabu embed` built
    # ("find this passage's other witnesses / passages like this"; the
    # P79-5 trial measured R@1 0.80 across editions within a language).
    #
    # Desk doctrine: the URN-anchored query needs NO model at query time
    # — the anchor's vector is already stored, so the whole answer is one
    # sqlite-vec brute-force scan of the same-language subpool
    # (vec_distance_cosine over the int8 rows, C speed), quasi-instant.
    # Absent store / absent extension / out-of-scope anchor each get an
    # honest hint, never a slow fallback scan and never an error page.
    #
    # Honesty rules from the trial (its central findings, not options):
    # - SAME-LANGUAGE ONLY. Cross-lingual retrieval measured dead-to-weak
    #   (grc→lat R@1 0.34, hbo→grc 0.14 unpointed), so the subpool is
    #   pinned to the anchor's language and no flag widens it.
    # - BANDS, never raw cosine: close/near/loose per thresholds below.
    #   The render names model + scope so a hit is never mistaken for a
    #   curated alignment (nabu_parallels stays hub-only).
    class Similar
      # The sqlite-vec loadable extension (the scan engine): an
      # owner-installed TOOL like the embed venv (docs/manual/
      # embed-venv.md carries the one-time step), never a gem — the
      # rubygems build for arm64-darwin predates int8 support
      # (verified 2026-09-02).
      DEFAULT_EXTENSION = File.join(Dir.home, ".nabu", "tools", "sqlite-vec", "vec0.dylib")

      # const: band thresholds are a RENDER choice over cosine distance
      # (unit-normalized e5 vectors, int8-quantized), not a corpus
      # measurement — close/near hits are what the trial's cross-edition
      # R@1 0.80 lives in; loose is the rest of the requested page.
      CLOSE = 0.10
      NEAR = 0.25

      Result = Data.define(:urn, :language, :band, :snippet, :document_title,
                           :license_class, :credit)

      Page = Data.define(:anchor_urn, :language, :model, :results)

      def self.extension_path
        ENV.fetch("NABU_SQLITE_VEC", DEFAULT_EXTENSION)
      end

      def initialize(catalog:, vectors:, extension: self.class.extension_path)
        @catalog = catalog
        @vectors = vectors
        @extension = extension
      end

      # The similarity page for +urn+: up to +limit+ same-language
      # neighbors in ascending cosine distance, banded. Raises Nabu::Error
      # with the honest next step on every absent-machinery case.
      def run(urn, limit: 10)
        model = store_model!
        anchor = @vectors[Nabu::Embed::VECTORS_TABLE].where(model: model, urn: urn).first
        raise Nabu::Error, missing_anchor_message(urn) if anchor.nil?

        load_extension!
        rows = neighbor_rows(model, anchor, limit)
        Page.new(anchor_urn: urn, language: anchor[:language], model: model,
                 results: decorate(rows))
      end

      private

      # The store's single model (the newest, should a future migration
      # hold two side by side) — or the honest "never built" refusal.
      def store_model!
        unless @vectors.table_exists?(Nabu::Embed::META_TABLE)
          raise Nabu::Error, "no vector store — `nabu embed` builds it (the literary-core " \
                             "scope; first run is the priced long build, later runs are deltas; " \
                             "setup: docs/manual/embed-venv.md)"
        end
        model = @vectors[Nabu::Embed::META_TABLE].order(Sequel.desc(:updated_at)).get(:model)
        raise Nabu::Error, "the vector store is empty — run `nabu embed`" if model.nil?

        model
      end

      def missing_anchor_message(urn)
        if @catalog[:passages].where(urn: urn).empty?
          "no passage #{urn} in the catalog"
        else
          "#{urn} has no vector — outside the embed scope (`embed_index: true` sources in " \
            "config/sources.yml) or not yet embedded (`nabu embed` catches the store up)"
        end
      end

      def load_extension!
        return if @loaded

        unless File.exist?(@extension)
          raise Nabu::Error, "sqlite-vec extension not found at #{@extension} — install it once " \
                             "(docs/manual/embed-venv.md, the vec0 step) or point $NABU_SQLITE_VEC " \
                             "at an existing copy"
        end
        @vectors.synchronize do |conn|
          conn.enable_load_extension(true)
          conn.load_extension(@extension)
          conn.enable_load_extension(false)
        end
        @loaded = true
      end

      # The brute-force scan: ascending vec_distance_cosine over the
      # anchor's same-language subpool (the [model, language] index bounds
      # the scan), anchor excluded.
      def neighbor_rows(model, anchor, limit)
        blob = Sequel.blob(anchor[:vec])
        @vectors[Nabu::Embed::VECTORS_TABLE]
          .where(model: model, language: anchor[:language])
          .exclude(urn: anchor[:urn])
          .select(:urn, Sequel.lit("vec_distance_cosine(vec_int8(vec), vec_int8(?))", blob)
                          .as(:distance))
          .order(:distance)
          .limit(limit)
          .all
      end

      def decorate(rows)
        catalog_rows = passages_by_urn(rows.map { |row| row[:urn] })
        rows.filter_map do |row|
          passage = catalog_rows[row[:urn]]
          next nil if passage.nil? # a vector whose passage left the catalog — skip honestly

          Result.new(
            urn: row[:urn], language: passage[:language], band: band(row[:distance]),
            snippet: StoredSnippet.build(text: passage[:text], language: passage[:language],
                                         terms: []),
            document_title: passage[:title], license_class: passage[:license_class],
            credit: passage[:credit]
          )
        end
      end

      def band(distance)
        return "close" if distance <= CLOSE
        return "near" if distance <= NEAR

        "loose"
      end

      def passages_by_urn(urns)
        @catalog[:passages]
          .join(:documents, id: Sequel[:passages][:document_id])
          .join(:sources, id: Sequel[:documents][:source_id])
          .where(Sequel[:passages][:urn] => urns)
          .select(Sequel[:passages][:urn], Sequel[:passages][:language],
                  Sequel[:passages][:text], Sequel[:documents][:title],
                  Sequel.function(:coalesce, Sequel[:documents][:license_override],
                                  Sequel[:sources][:license_class]).as(:license_class),
                  Sequel[:sources][:credit])
          .to_h { |row| [row[:urn], row] }
      end
    end
  end
end
