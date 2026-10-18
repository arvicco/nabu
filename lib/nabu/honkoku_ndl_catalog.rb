# frozen_string_literal: true

require "json"

require_relative "adapters/ndl_kotenseki"

module Nabu
  # The honkoku ← ndl-kotenseki catalog join. A honkoku v3 material whose
  # IIIF manifest is an NDL Digital Collections item
  # (https://dl.ndl.go.jp/api/iiif/<pid>/manifest.json — 918 transcribed
  # materials, census 2026-10-18) IS that NDL item transcribed; the held
  # ndl-kotenseki census.tsv carries the item's NDL catalog record (867
  # of those pids). This pass writes the record onto the loaded honkoku
  # row under metadata "ndl_catalog" — the label: every field there is
  # the NDL catalog's claim, never honkoku's — pid + permalink, the raw
  # 著者 string with its role-split parts and names (NdlKotenseki
  # .author_part), the 出版日 date envelope, the 件名 subjects.
  #
  # The join is EXACT-KEY only (the pid in the manifest url); a pid the
  # census lacks is counted, never guessed.
  #
  # Derived by construction: f(canonical/ndl-kotenseki + loaded honkoku
  # rows). The honkoku loader emits metadata without the key; the pass
  # re-merges idempotently (an absent census strips a stale record), and
  # it runs BEFORE the corpus builders — the facet map projects
  # ndl_catalog.author_names / .subjects and MetadataDates dates the row
  # from ndl_catalog.date — at rebuild, in the builder refresh, and after
  # honkoku/ndl-kotenseki syncs (the AesAedTitles mold: a cross-source
  # read lives in a post-load pass, never in an adapter's parse, so
  # neither source's identity stamp has to cover the other's tree).
  class HonkokuNdlCatalog
    HONKOKU_SLUG = "honkoku"
    NDL_SLUG = "ndl-kotenseki"
    KEY = "ndl_catalog"
    NDL_MANIFEST = %r{\Ahttps?://(?:www\.)?dl\.ndl\.go\.jp/api/iiif/(\d+)/manifest(?:\.json)?\z}

    Result = Data.define(:joined, :unmatched)

    def initialize(catalog:, canonical_dir:)
      @catalog = catalog
      @census_path = File.join(canonical_dir, NDL_SLUG, Adapters::NdlKotenseki::CENSUS_TSV)
    end

    def run
      source_id = @catalog[:sources].where(slug: HONKOKU_SLUG).get(:id)
      return Result.new(joined: 0, unmatched: 0) if source_id.nil?

      census = Adapters::NdlKotenseki.census_table(@census_path)
      joined = 0
      unmatched = 0
      @catalog.transaction do
        @catalog[:documents].where(source_id: source_id).select_map(%i[id metadata_json]).each do |id, json|
          metadata = JSON.parse(json.to_s.empty? ? "{}" : json)
          pid = metadata["manifest"].to_s.strip[NDL_MANIFEST, 1]
          record = pid && census[pid] && catalog_record(pid, census[pid])
          joined += 1 if record
          unmatched += 1 if pid && record.nil?

          updated = metadata.except(KEY)
          updated[KEY] = record if record
          next if updated == metadata

          @catalog[:documents].where(id: id).update(metadata_json: Store::ContentHash.canonical_json(updated))
        end
      end
      Result.new(joined: joined, unmatched: unmatched)
    end

    private

    def catalog_record(pid, bib)
      parts = bib["author"].to_s.split("||").reject { |part| part.strip.empty? }
                                            .map { |part| Adapters::NdlKotenseki.author_part(part) }
      author = bib["author"].to_s.strip
      subjects = bib["subject"].to_s.split("||").map { |value| Normalize.nfc(value.strip) }.reject(&:empty?)
      {
        "pid" => pid, "record" => "https://dl.ndl.go.jp/pid/#{pid}",
        "author" => (Normalize.nfc(author) unless author.empty?),
        "authors" => (parts unless parts.empty?),
        "author_names" => (parts.map { |part| part["name"] }.uniq unless parts.empty?),
        "date" => Adapters::NdlKotenseki.date_envelope(bib),
        "subjects" => (subjects unless subjects.empty?)
      }.compact
    end
  end
end
