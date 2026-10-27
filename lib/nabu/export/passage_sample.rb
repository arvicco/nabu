# frozen_string_literal: true

require "digest"

require_relative "types"
require_relative "axes"
require_relative "../languages"
require_relative "../script_check"
require_relative "../timeline"
require_relative "../query/catalog_join"

module Nabu
  module Export
    # `nabu export passages --stratum ...` (P145): a stratified,
    # reproducible passage sample — the corpus-linguistics design for a
    # thesis sample out of a library whose raw distribution is wildly
    # skewed (a handful of languages and centuries hold most passages).
    #
    # == Cells
    #
    # A cell is the tuple of the chosen strata, each NULL-honest (NULL is
    # its own cell, never dropped or guessed):
    #   language  the passage's stored language (the document's when unset)
    #   century   signed century index (Nabu::Timeline: -1 = 1st c. BCE) of
    #             the MIDPOINT of the document's exported envelope (the Axes
    #             primary row — the `documents --with-axes` envelope), on
    #             astronomical years so the missing year 0 cannot skew a
    #             BCE/CE-straddling midpoint (the lemma rollup's arithmetic);
    #             NULL = undated
    #   script    the dominant script of the passage's held bytes
    #             (ScriptCheck — the checker that polices ~script claims),
    #             a lowercased ISO 15924 tag; NULL when no script-bearing
    #             character appears
    #   source    the source slug
    #
    # == Allocation: equal per cell by default, argued
    #
    # Proportional allocation reproduces the library's skew — on this
    # corpus it is barely different from a simple random sample, and a
    # small cell (an under-attested language, an early century) gets zero
    # or one passage. A stratified sample is usually drawn to make cells
    # COMPARABLE, so the default is equal allocation: up to --per-cell N
    # (default 100) passages per cell, a cell smaller than N contributing
    # all of its passages. Every row carries its cell_population,
    # cell_sampled and weight = population / sampled (the inverse inclusion
    # probability), so population-level estimates stay one weighted sum
    # away. --proportional TOTAL is the other design: TOTAL passages split
    # across cells by population share (largest-remainder rounding, ties to
    # cell order).
    #
    # == Reproducible draw
    #
    # Selection is a bottom-k sample under a SEEDED hash order: each passage
    # ranks by sha256("<seed>:<urn>"), and a cell keeps its k lowest ranks.
    # Urns are stable across rebuilds, so the same seed over the same
    # library draws the same passages, independent of scan order — and a
    # proportional quota q ≤ k is the first q of the same order. Rows
    # stream cell by cell (cells in stratum order, NULL last), urn order
    # within a cell.
    #
    # == OCR exclusion: the flag the catalog actually carries
    #
    # --exclude-ocr drops documents whose metadata declares OCR text —
    # metadata_json text_nature in OCR_NATURES, the label the scan-shelf
    # adapters (IaScanShelf: slavistics-pd, africa-pd, archiv-slav-phil;
    # ndl-kotenseki; mdz-protestant) stamp on every document. It is the
    # ONLY machine-readable OCR marker in the catalog: other OCR-origin text
    # (corrected or not) says so only in free-text notes, if at all — so
    # --exclude-source SLUG,... is the explicit complement, and the
    # manifest echoes both.
    #
    # Memory is the reservoirs (k urns per cell, text fetched only for the
    # winners); the scan is one keyset pass over the scoped passages.
    class PassageSample
      include Nabu::Query::CatalogJoin

      NAME = "passage_sample"
      SUMMARY = "A stratified, seeded passage sample: cells by language / century / script / source, equal " \
                "per-cell allocation (or proportional), each row with its cell population and weight"

      STRATA = %w[language century script source].freeze
      # const: the documented default cell quota (class note), not a corpus claim
      DEFAULT_PER_CELL = 100
      # The text_nature labels that declare OCR (class note).
      OCR_NATURES = %w[machine-ocr uncorrected-ocr].freeze
      # const: keyset page — one batched axis read per page, well under SQLite's variable cap
      PAGE_SIZE = 1_000

      COLUMNS = [
        Column.new(name: "urn", description: "the passage urn (stable across rebuilds)"),
        Column.new(name: "document_urn", description: "its document's urn"),
        Column.new(name: "source", description: "source slug"),
        Column.new(name: "language", description: "the passage's stored language (the document's when unset)"),
        Column.new(name: "century", description: "signed century index of the document envelope's midpoint " \
                                                 "(-1 = 1st c. BCE); NULL = undated"),
        Column.new(name: "script", description: "dominant script of the held text (lowercased ISO 15924); " \
                                                "NULL when none"),
        Column.new(name: "stratum", description: "the cell: the chosen strata as key=value, ';'-joined " \
                                                 "(null for an absent value)"),
        Column.new(name: "cell_population", description: "passages in scope in this cell"),
        Column.new(name: "cell_sampled", description: "passages drawn from this cell"),
        Column.new(name: "weight", description: "cell_population / cell_sampled — the inverse inclusion " \
                                                "probability, for population-level estimates"),
        Column.new(name: "license_class", description: "effective license class (document override, else source)"),
        Column.new(name: "text", description: "the passage text as stored")
      ].freeze

      Pick = Data.define(:rank, :urn, :values)

      def initialize(catalog:, strata:, per_cell: nil, proportional: nil, seed: 0, sources: nil, langs: nil,
                     exclude_sources: nil, exclude_ocr: false, page_size: PAGE_SIZE)
        @catalog = catalog
        @strata = presence(strata) || []
        @per_cell = per_cell
        @proportional = proportional
        @seed = seed.to_i
        @sources = presence(sources)
        @langs = presence(langs)
        @exclude_sources = presence(exclude_sources)
        @exclude_ocr = exclude_ocr
        @page_size = page_size
        validate!
        @per_cell ||= DEFAULT_PER_CELL unless @proportional
        @notes = {}
      end

      def columns = COLUMNS

      def filters
        { "strata" => @strata, "allocation" => @proportional ? "proportional" : "per_cell",
          "per_cell" => @per_cell, "proportional" => @proportional, "seed" => @seed, "source" => @sources,
          "language" => @langs, "exclude_source" => @exclude_sources, "exclude_ocr" => @exclude_ocr,
          "withdrawn" => "excluded" }
      end

      attr_reader :notes

      def each_row(license_classes: nil)
        counts, reservoirs = scan(license_classes)
        quotas = @proportional ? proportional_quotas(counts) : counts.to_h { |cell, n| [cell, [n, @per_cell].min] }
        picks = quotas.sort_by { |cell, _| cell_order(cell) }.flat_map do |cell, quota|
          reservoirs.fetch(cell, []).first(quota).sort_by(&:urn).map { |pick| [cell, pick] }
        end
        record_notes(counts, license_classes, picks.size)
        details = fetch_details(picks.map { |_cell, pick| pick.urn })
        envelopes = drawn_envelopes(details)
        picks.each do |cell, pick|
          yield build(cell, pick, details.fetch(pick.urn), envelopes, counts.fetch(cell), quotas.fetch(cell))
        end
      end

      private

      def presence(list)
        list = Array(list).map(&:to_s).map(&:strip).reject(&:empty?).uniq
        list.empty? ? nil : list
      end

      def validate!
        raise Error, "give at least one stratum (#{STRATA.join(', ')})" if @strata.empty?

        unknown = @strata - STRATA
        raise Error, "unknown stratum #{unknown.first.inspect} (choose from #{STRATA.join(', ')})" unless unknown.empty?
        raise Error, "choose either --per-cell or --proportional, not both" if @per_cell && @proportional

        [[@per_cell, "--per-cell"], [@proportional, "--proportional"]].each do |value, flag|
          raise Error, "#{flag} must be a positive whole number" if value && (!value.is_a?(Integer) || value < 1)
        end
        validate_sources!
      end

      def validate_sources!
        wanted = (@sources || []) + (@exclude_sources || [])
        return if wanted.empty?

        known = @catalog[:sources].order(:slug).select_map(:slug)
        unknown = wanted - known
        raise Error, "unknown source #{unknown.first.inspect} — the catalog holds: #{known.join(', ')}" \
          unless unknown.empty?
      end

      # The one keyset pass: cell populations and a bottom-k reservoir per
      # cell (k = the per-cell quota, or TOTAL under --proportional — any
      # quota is a prefix of the same order).
      def scan(license_classes)
        counts = Hash.new(0)
        reservoirs = Hash.new { |hash, cell| hash[cell] = [] }
        capacity = @per_cell || @proportional
        dataset = scoped(license_classes)
        last = nil
        loop do
          page = (last ? dataset.where(Sequel[:passages][:urn] > last) : dataset).limit(@page_size).all
          break if page.empty?

          envelopes = century_needed? ? Axes.by_document(@catalog, page.map { |row| row[:document_id] }.uniq) : {}
          page.each do |row|
            values = stratum_values(row, envelopes)
            cell = @strata.map { |stratum| values[stratum] }
            counts[cell] += 1
            offer(reservoirs[cell], Pick.new(rank: rank(row[:urn]), urn: row[:urn], values: values), capacity)
          end
          last = page.last[:urn]
        end
        [counts, reservoirs]
      end

      def scoped(license_classes)
        passages = Sequel[:passages]
        documents = Sequel[:documents]
        dataset = @catalog[:passages].join(:documents, id: passages[:document_id])
                                     .join(:sources, id: documents[:source_id])
                                     .where(passages[:withdrawn] => false, documents[:withdrawn] => false)
        dataset = dataset.where(Sequel[:sources][:slug] => @sources) if @sources
        dataset = dataset.exclude(Sequel[:sources][:slug] => @exclude_sources) if @exclude_sources
        dataset = dataset.where(language_expr => @langs.flat_map { |code| Nabu::Languages.code_variants(code) }) \
          if @langs
        dataset = dataset.where(license_expr => license_classes) if license_classes
        dataset = dataset.where(not_ocr) if @exclude_ocr
        dataset.order(passages[:urn])
               .select(passages[:urn].as(:urn), passages[:document_id].as(:document_id),
                       language_expr.as(:language), Sequel[:sources][:slug].as(:source),
                       *(script_needed? ? [passages[:text].as(:text)] : []))
      end

      def language_expr = Sequel.function(:coalesce, Sequel[:passages][:language], Sequel[:documents][:language])

      def text_nature = Sequel.function(:json_extract, Sequel[:documents][:metadata_json], "$.text_nature")

      def not_ocr = Sequel.|({ text_nature => nil }, Sequel.~(text_nature => OCR_NATURES))

      def century_needed? = @strata.include?("century")

      def script_needed? = @strata.include?("script")

      def stratum_values(row, envelopes)
        values = { "language" => row[:language], "source" => row[:source] }
        values["century"] = century(envelopes[row[:document_id]]) if century_needed?
        values["script"] = ScriptCheck.dominant([row[:text]]).first if script_needed?
        values
      end

      # The envelope midpoint's signed century (class note).
      def century(axes)
        low = axes&.not_before || axes&.not_after
        high = axes&.not_after || axes&.not_before
        return nil unless low

        mid = (astronomical(low) + astronomical(high)) / 2 # Integer#/ floors, as the rollup's floor_half
        Nabu::Timeline.century_index(mid.positive? ? mid : mid - 1)
      end

      def astronomical(year) = year.negative? ? year + 1 : year

      def rank(urn) = Digest::SHA256.hexdigest("#{@seed}:#{urn}")[0, 16].to_i(16)

      # Keep +reservoir+ the +capacity+ lowest-ranked picks, sorted by rank.
      def offer(reservoir, pick, capacity)
        return if reservoir.size >= capacity && pick.rank >= reservoir.last.rank

        at = reservoir.bsearch_index { |held| held.rank > pick.rank } || reservoir.size
        reservoir.insert(at, pick)
        reservoir.pop if reservoir.size > capacity
      end

      # Largest remainder: floor of each exact share, the leftover seats to
      # the largest fractional parts (ties in cell order); never above a
      # cell's population.
      def proportional_quotas(counts)
        population = counts.values.sum
        return {} if population.zero?

        total = [@proportional, population].min
        exact = counts.to_h { |cell, n| [cell, Rational(total * n, population)] }
        quotas = exact.transform_values(&:floor)
        leftover = total - quotas.values.sum
        exact.sort_by { |cell, share| [-(share - share.floor), cell_order(cell)] }.first(leftover)
             .map(&:first).each { |cell| quotas[cell] += 1 }
        quotas
      end

      def cell_order(cell) = cell.map { |value| value.nil? ? [1, ""] : [0, value] }

      def record_notes(counts, license_classes, sampled)
        @notes = { "population" => counts.values.sum, "cells" => counts.size, "sampled" => sampled }
        @notes["ocr_documents_excluded"] = ocr_documents(license_classes) if @exclude_ocr
      end

      def ocr_documents(license_classes)
        documents = Sequel[:documents]
        dataset = @catalog[:documents].join(:sources, id: documents[:source_id])
                                      .where(documents[:withdrawn] => false, text_nature => OCR_NATURES)
        dataset = dataset.where(Sequel[:sources][:slug] => @sources) if @sources
        dataset = dataset.exclude(Sequel[:sources][:slug] => @exclude_sources) if @exclude_sources
        dataset = dataset.where(license_expr => license_classes) if license_classes
        dataset.count
      end

      # { urn => row } — document urn, effective license and text for the
      # drawn passages only, one batched read per page of urns.
      def fetch_details(urns)
        urns.each_slice(@page_size).with_object({}) do |slice, out|
          @catalog[:passages].join(:documents, id: Sequel[:passages][:document_id])
                             .join(:sources, id: Sequel[:documents][:source_id])
                             .where(Sequel[:passages][:urn] => slice)
                             .select(Sequel[:passages][:urn].as(:urn), Sequel[:passages][:text].as(:text),
                                     Sequel[:documents][:urn].as(:document_urn), license_expr.as(:license_class),
                                     Sequel[:passages][:document_id].as(:document_id))
                             .each { |row| out[row[:urn]] = row }
        end
      end

      # The drawn documents' envelopes, for the century column when century
      # is not a stratum (the scan read none).
      def drawn_envelopes(details)
        return {} if century_needed?

        ids = details.values.map { |row| row[:document_id] }.uniq
        ids.each_slice(@page_size).with_object({}) { |slice, out| out.merge!(Axes.by_document(@catalog, slice)) }
      end

      def build(cell, pick, detail, envelopes, population, sampled)
        values = pick.values
        script = values.fetch("script") { ScriptCheck.dominant([detail[:text]]).first }
        century = values.fetch("century") { century(envelopes[detail[:document_id]]) }
        stratum = @strata.zip(cell).map { |name, value| "#{name}=#{value.nil? ? 'null' : value}" }.join(";")
        Row.new(values: [pick.urn, detail[:document_urn], values["source"], values["language"], century, script,
                         stratum, population, sampled, (population.to_f / sampled).round(6),
                         detail[:license_class], detail[:text]],
                draws: [[values["source"], detail[:license_class]]])
      end
    end
  end
end
