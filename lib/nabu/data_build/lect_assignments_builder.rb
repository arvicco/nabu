# frozen_string_literal: true

require "digest"

require_relative "../errors"
require_relative "../config"
require_relative "../source_registry"
require_relative "../store/lect_journal"
require_relative "builder"
require_relative "csv_writer"

module Nabu
  module DataBuild
    # The mul/lect-assignments builder (P73-3) — the per-document
    # historical-stage journal, published. One row per (URN, language-code)
    # assignment from db/lects.sqlite3: which lect (Old vs Neo-Babylonian,
    # Ur III vs OB Sumerian, Vedic vs Classical Sanskrit, ...) the document
    # is assigned to, with the basis (rule:akk-period, rule:date-band, ...)
    # and the human-readable note riding in-band — the per-row honesty the
    # repo practices, because rule-derived and date-inferred rows differ in
    # kind and the consumer must see which is which.
    #
    # == The license slice (owner ruling №R-24, 2026-08-11)
    #
    # The dataset publishes CC BY-SA 4.0 (one carve-out dataset — BY-SA
    # lanes like edh/aes ride inside it). Only documents from open- and
    # attribution-class sources are publishable at all: nc, odbl and
    # research_private slices are excluded ROW BY ROW, and rows whose URN
    # resolves to no cataloged document are excluded too (no document, no
    # license class — and the URN namespace is NOT the source slug:
    # papyri-ddbdp mints urn:nabu:ddbdp:..., so the join goes through
    # documents.urn, never a prefix parse) — everything excluded is
    # censused in nabu.eval, never silently dropped.
    #
    # == Provenance
    #
    # The journal itself is the source of truth (the aozora-gaiji posture:
    # no canonical cones declared — rows cite documents at URN grain, which
    # is stable across syncs by the conformance contract, so no cone sha
    # is load-bearing). The recipe embeds the sha256 of the published
    # slice: identical journal state → identical fingerprint, any change
    # in a published row moves it. The lect identifier grammar and the
    # registry of ids are public in nabu-lects (CC BY 4.0), cited from
    # sources.bib; contributing corpora are cited one bib key per source,
    # and every CSV row's Source column names its corpus's key.
    class LectAssignmentsBuilder
      FILENAME = "assignments.csv"
      COLUMNS = %w[ID URN Language_ID Lect_ID Basis Comment Source].freeze

      # License classes whose documents may be republished at URN grain.
      PUBLISHABLE_LICENSE_CLASSES = %w[open attribution].freeze

      NABU_LECTS_URL = "https://github.com/arvicco/nabu-lects"

      # URN → source resolution batch size (documents.urn lookups).
      BATCH = 2_000

      OVERVIEW =
        "Ancient-language corpora rarely say which historical stage of a language a text " \
        "belongs to — an Akkadian tablet may be Old Babylonian or Neo-Babylonian, a Sanskrit " \
        "hymn Vedic or Classical, and the difference matters to anyone studying how these " \
        "languages changed. This dataset publishes Nabu's per-document stage assignments " \
        "across its whole multilingual catalog: for each document (cited by its stable URN), " \
        "the specific historical variety it is assigned to, plus the basis of the assignment " \
        "— a period rule reading the corpus's own metadata, or an inference from the " \
        "document's date — so every row says how much to trust it. No other project " \
        "publishes stage assignments at corpus scale."

      def initialize(lects_db: nil, registry: nil)
        @lects_db = lects_db
        @registry = registry
      end

      def build(catalog:, out_dir:)
        raise Error, "mul/lect-assignments needs the catalog open — license classes live there" if catalog.nil?

        journal = @lects_db || open_journal
        rows, excluded, published_slugs, digest = published_rows(journal, catalog)
        count = CsvWriter.write(path: File.join(out_dir, FILENAME), columns: COLUMNS, rows: rows)
        BuildResult.new(
          resources: [resource(count)],
          recipe: recipe(digest),
          citations: citations(published_slugs),
          evaluation: evaluation(journal, rows, excluded),
          overview: OVERVIEW
        )
      end

      private

      def open_journal
        path = Nabu::Config.load.lects_journal_path
        journal = Nabu::Store::LectJournal.open_readonly(path)
        raise Error, "no lect journal at #{path} — run `nabu rebuild` (the lect-journal stage) first" if journal.nil?

        journal
      end

      # One pass over the journal in deterministic (urn, code) order:
      # publishable rows, the exclusion census, the contributing source
      # slugs, and the published-slice digest, together. URNs resolve to
      # sources through documents.urn in batches — never a prefix parse.
      def published_rows(journal, catalog)
        sources = catalog[:sources].select_hash(:id, %i[slug license_class])
        state = { rows: [], excluded: Hash.new(0), slugs: {}, sha: Digest::SHA256.new }
        batch = []
        journal[:lect_assignments].order(:urn, :code).paged_each do |row|
          batch << row
          next if batch.size < BATCH

          resolve_batch(batch, catalog, sources, state)
          batch = []
        end
        resolve_batch(batch, catalog, sources, state)
        [state[:rows], state[:excluded], state[:slugs].keys.sort, state[:sha].hexdigest]
      end

      def resolve_batch(batch, catalog, sources, state)
        return if batch.empty?

        source_ids = catalog[:documents].where(urn: batch.map { |row| row[:urn] }.uniq)
                                        .select_hash(:urn, :source_id)
        batch.each do |row|
          slug, license_class = sources[source_ids[row[:urn]]]
          reason = exclusion_reason(source_ids.key?(row[:urn]), license_class)
          if reason
            state[:excluded][reason] += 1
            next
          end

          state[:slugs][slug] = true
          state[:sha] << [row[:urn], row[:code], row[:lect_id], row[:basis], row[:note]].join("\x1f") << "\n"
          state[:rows] << csv_row(row, slug)
        end
      end

      def exclusion_reason(cataloged, license_class)
        return "uncataloged" unless cataloged
        return nil if PUBLISHABLE_LICENSE_CLASSES.include?(license_class)

        license_class
      end

      def csv_row(row, slug)
        { "ID" => CsvWriter.mint_id(row[:urn], row[:code]), "URN" => row[:urn],
          "Language_ID" => row[:code], "Lect_ID" => row[:lect_id],
          "Basis" => row[:basis], "Comment" => row[:note], "Source" => slug }
      end

      def resource(count)
        Resource.new(
          name: "assignments", path: FILENAME, rows: count,
          fields: COLUMNS.map { |name| { name: name, type: "string" } },
          primary_key: ["ID"]
        )
      end

      def recipe(digest)
        "lect-assignments v1: project the lect journal at URN grain, license classes " \
          "#{PUBLISHABLE_LICENSE_CLASSES.join('+')} only, ordered (urn, code); " \
          "published-slice sha256=#{digest}"
      end

      def citations(published_slugs)
        registry = @registry || Nabu::SourceRegistry.load(Nabu::Config.load.sources_path)
        corpus_citations = published_slugs.filter_map do |slug|
          entry = registry[slug]
          next nil if entry.nil?

          manifest = entry.manifest
          Citation.new(key: slug, type: "misc",
                       fields: { "title" => manifest.name, "howpublished" => manifest.upstream_url,
                                 "note" => "license: #{manifest.license}" })
        end
        corpus_citations + [nabu_lects_citation]
      end

      def nabu_lects_citation
        Citation.new(
          key: "nabu-lects", type: "misc",
          fields: {
            "title" => "nabu-lects — the lect identifier grammar and registry",
            "howpublished" => NABU_LECTS_URL,
            "note" => "CC BY 4.0; the Lect_ID column's grammar " \
                      "(anchor[:stage][/variety][@ortho]) and the registry of ids"
          }
        )
      end

      def evaluation(journal, rows, excluded)
        {
          "journal_rows" => journal[:lect_assignments].count,
          "published_rows" => rows.size,
          "excluded_rows" => excluded.sort.to_h
        }
      end
    end
  end
end
