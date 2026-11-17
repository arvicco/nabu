# frozen_string_literal: true

require "yaml"
require_relative "../site_data"
require_relative "../../eta"
require_relative "../../store/source_stats"

module Nabu
  module Ops
    module Reconstruction
      # `nabu reconstruct verify`: the probe battery a reconstructed (or
      # simply living) box answers against the published census. Read-only;
      # seconds-class. Four probes:
      #
      #   1. census diff — live documents / passages / language codes / live
      #      sources vs site/_data/census.yml's committed figures. The live
      #      side reads the precompiled per-source census (source_stats: the
      #      SUM over its rows IS the global census, and its language rows
      #      are documents.language-grained — the very definitions
      #      SiteData#census counts by scanning) plus SiteData's own
      #      live-public-slugs rule. Drift is EXPECTED when the library moved
      #      since the stamp: reported, failing only under --strict.
      #   2. presence — every live public source holds >0 live documents, or
      #      (a dictionary shelf) a dictionaries row.
      #   3. FTS canaries — one deterministic sample passage per live source
      #      (the first live passage with > MIN_SAMPLE characters of its
      #      indexed search text, among the source's first SAMPLE_DOCUMENTS
      #      live documents by id) probed in passages_fts as a phrase of its
      #      first tokens, pinned to its own rowid. Loaded-but-unsearchable
      #      is the failure this catches.
      #   4. capability homes — each MCP tool's data layers (config/
      #      capabilities.yml) have their homes on disk: file or directory
      #      present, and every named table present in a .sqlite3 home.
      class Verify
        CENSUS_FIELDS = %w[documents passages language_codes live_sources].freeze
        MIN_SAMPLE = 40
        SAMPLE_DOCUMENTS = 25
        PHRASE_TOKENS = 4
        # A token longer than this is a spaceless run (Han, kana, scriptio
        # continua): unicode61 keeps the whole run as ONE token, so the
        # probe takes its first PREFIX_CHARS characters as a prefix term.
        LONG_TOKEN = 24
        PREFIX_CHARS = 8
        # unicode61's token characters (letters, numbers, private use) plus
        # marks: a mark the tokenizer treats as a separator only splits a
        # token inside the quoted phrase, never reorders it.
        TOKEN = /[\p{L}\p{N}\p{M}\p{Co}]+/

        CensusRow = Data.define(:name, :committed, :live) do
          def drift? = !committed.nil? && !live.nil? && committed != live
          def delta = live.to_i - committed.to_i
        end

        Canary = Data.define(:slug, :status, :urn, :phrase, :deferred) do
          def initialize(slug:, status:, urn: nil, phrase: nil, deferred: false)
            super
          end

          def failed? = %i[miss no_index error].include?(status)
        end

        Result = Data.define(:census_path, :as_of, :census, :live_sources, :missing_sources, :canaries,
                             :capability_gaps, :tools_checked) do
          def misses = canaries.select(&:failed?)

          def failed?(strict:)
            strict && (census.any?(&:drift?) || !missing_sources.empty? || !misses.empty? ||
                       !capability_gaps.empty?)
          end
        end

        # The roots a capabilities.yml home resolves against (db/, local/,
        # canonical/ from the config; everything else the project root).
        Homes = Data.define(:project_root, :db_dir, :local_dir, :canonical_dir) do
          def self.from_config(config)
            new(project_root: Config::PROJECT_ROOT, db_dir: config.db_dir, local_dir: config.local_dir,
                canonical_dir: config.canonical_dir)
          end

          # "db/catalog.sqlite3 (a, b)" → ["db/catalog.sqlite3", ["a", "b"]];
          # a "<slug>/" placeholder segment collapses to its parent, and the
          # registry's slash shorthand expands on the first name's stem
          # ("dictionary_entries/citations" → dictionary_entries,
          # dictionary_citations).
          def self.parse(home)
            path, tables = home.to_s.strip.match(/\A(\S+)(?:\s+\((.*)\))?\z/)&.captures
            names = tables.to_s.split(",").map(&:strip).reject(&:empty?).flat_map do |name|
              first, *rest = name.split("/")
              stem = first[/\A.*_/].to_s
              [first, *rest.map { |tail| "#{stem}#{tail}" }]
            end
            [path.to_s.gsub(%r{<[^>]+>/?}, ""), names]
          end

          def resolve(path)
            head, rest = path.split("/", 2)
            root = { "db" => db_dir, "local" => local_dir, "canonical" => canonical_dir }[head]
            root ? File.join(root, rest.to_s) : File.join(project_root, path)
          end
        end

        def initialize(registry:, catalog:, fulltext:, census_path:, capabilities:, homes:,
                       tools: MCP::Tools::TOOLS)
          @registry = registry
          @catalog = catalog
          @fulltext = fulltext
          @census_path = census_path
          @capabilities = capabilities
          @homes = homes
          @tools = tools
        end

        def run
          committed = File.exist?(@census_path.to_s) ? (YAML.safe_load_file(@census_path) || {}) : {}
          Result.new(census_path: @census_path, as_of: committed["as_of"], census: census(committed),
                     live_sources: live_slugs.size, missing_sources: missing_sources, canaries: canaries,
                     capability_gaps: capability_gaps, tools_checked: @homes ? @tools.size : 0)
        end

        def self.render(result)
          Render.new(result).to_s
        end

        # The probe phrase for a passage's indexed search text, as an FTS5
        # column-filtered phrase query; nil when the text carries no token.
        def self.phrase(text)
          parts = []
          prefix = false
          text.to_s.scan(TOKEN).first(PHRASE_TOKENS).each do |token|
            if token.length > LONG_TOKEN
              parts << token[0, PREFIX_CHARS]
              prefix = true
              break
            end
            parts << token
          end
          return nil if parts.empty?

          %("#{parts.join(' ')}"#{' *' if prefix})
        end

        private

        def live_slugs = @live_slugs ||= SiteData.live_public_slugs(@registry)

        def source_ids = @source_ids ||= @catalog[:sources].select_hash(:slug, :id)

        def stats? = Store::SourceStats.available?(@catalog)

        def census(committed)
          rollup = stats? ? Store::SourceStats.rollup(@catalog) : nil
          live = {
            "documents" => rollup&.fetch(:live_documents),
            "passages" => rollup&.fetch(:live_passages),
            "language_codes" => stats? ? Store::SourceStats.language_codes(@catalog) : nil,
            "live_sources" => live_slugs.size
          }
          CENSUS_FIELDS.map { |name| CensusRow.new(name: name, committed: committed[name], live: live[name]) }
        end

        def missing_sources
          documents = stats? ? @catalog[Store::SourceStats::TABLE].select_hash(:source_id, :live_documents) : {}
          shelves = @catalog[:dictionaries].distinct.select_map(:source_id)
          live_slugs.reject do |slug|
            id = source_ids[slug]
            id && (documents[id].to_i.positive? || shelves.include?(id))
          end
        end

        def canaries
          index = @fulltext&.table_exists?(Store::Indexer::TABLE)
          contentless = index && Store::Indexer.fts_contentless?(@fulltext)
          live_slugs.map do |slug|
            deferred = @registry[slug]&.index_deferred? || false
            sample = source_ids[slug] && sample_passage(source_ids[slug])
            next Canary.new(slug: slug, status: unsampled(source_ids[slug]), deferred: deferred) if sample.nil?

            phrase = self.class.phrase(sample[:text_search])
            status = if phrase.nil? then :no_phrase
                     elsif !index then :no_index
                     else probe(sample[:id], phrase, contentless)
                     end
            Canary.new(slug: slug, status: status, urn: sample[:urn], phrase: phrase, deferred: deferred)
          end
        end

        # Why a source yields no sample: no live documents at all (a
        # dictionary shelf, or an empty source) or documents carrying no
        # passages (metadata-only records) — nothing the index could hold.
        def unsampled(source_id)
          return :no_documents if source_id.nil?

          @catalog[:documents].where(source_id: source_id, withdrawn: false).empty? ? :no_documents : :no_passages
        end

        def sample_passage(source_id)
          documents = @catalog[:documents].where(source_id: source_id, withdrawn: false)
                                          .order(:id).limit(SAMPLE_DOCUMENTS).select_map(:id)
          return nil if documents.empty?

          live = @catalog[:passages].where(document_id: documents, withdrawn: false)
                                    .order(:document_id, :sequence).select(:id, :urn, :text_search)
          live.where { length(text_search) > MIN_SAMPLE }.first || live.first
        end

        def probe(passage_id, phrase, contentless)
          match = Sequel.lit("passages_fts MATCH ?", "text_normalized : #{phrase}")
          hits = @fulltext[Store::Indexer::TABLE].where(match)
          hits = contentless ? hits.where(Sequel.lit("rowid") => passage_id) : hits.where(passage_id: passage_id)
          hits.empty? ? :miss : :hit
        rescue Sequel::DatabaseError
          :error
        end

        # { tool => ["layer: why", ...] } for every MCP tool with a gap.
        def capability_gaps
          return {} if @homes.nil?

          by_tool = @capabilities.fetch("capabilities", {}).each_with_object({}) do |(_, cap), map|
            Array(cap.dig("surfaces", "mcp")).each { |tool| map[tool] = Array(cap["layers"]) }
          end
          gaps = @tools.keys.to_h do |tool|
            layers = by_tool[tool]
            [tool, layers ? layers.filter_map { |layer| home_gap(layer) } : ["no capability row"]]
          end
          gaps.reject { |_, list| list.empty? }
        ensure
          @dbs&.each_value { |db| db&.disconnect }
          @dbs = nil
        end

        def home_gap(layer)
          home = @capabilities.dig("layers", layer, "home")
          return "#{layer}: undeclared layer" if home.nil?

          path, tables = Homes.parse(home)
          absolute = @homes.resolve(path)
          return "#{layer}: #{path} absent#{never_run_note(layer)}" unless File.exist?(absolute)
          return nil if tables.empty?

          db = open_db(absolute)
          absent = tables.reject { |table| db.table_exists?(table.to_sym) }
          absent.empty? ? nil : "#{layer}: #{path} lacks table#{'s' if absent.size > 1} #{absent.join(', ')}"
        end

        def never_run_note(layer)
          @capabilities.dig("layers", layer, "producer") == "enrichment" ? " (enrichment never run here)" : ""
        end

        def open_db(path)
          @dbs ||= {}
          @dbs[path] ||= Store.connect(path, readonly: true)
        end

        # The card's text (Verify.render).
        class Render
          def initialize(result)
            @result = result
          end

          def to_s
            lines = [header, *census, "", presence, *canaries, "", *capabilities, "", summary]
            "#{lines.join("\n")}\n"
          end

          private

          def header
            "reconstruct verify — the probe battery against #{@result.census_path}" \
              "#{" (stamped #{@result.as_of})" if @result.as_of}"
          end

          def num(value) = value.nil? ? "?" : Eta.commas(value)

          def census
            if @result.census.all? { |row| row.committed.nil? }
              return ["census: no committed census at #{@result.census_path} — nothing to diff against"]
            end

            ["census (committed → live; drift is expected when the library moved since the stamp):"] +
              @result.census.map do |row|
                mark = if row.drift? then "DRIFT #{'+' if row.delta.positive?}#{num(row.delta)}"
                       elsif row.live.nil? then "unknown (no source_stats)"
                       else "="
                       end
                format("  %-16<n>s %15<c>s %15<l>s  %<m>s", n: row.name, c: num(row.committed), l: num(row.live),
                                                            m: mark)
              end
          end

          def presence
            missing = @result.missing_sources
            line = "presence: #{@result.live_sources} live sources; #{missing.size} hold nothing"
            missing.empty? ? line : "#{line}: #{missing.join(', ')}"
          end

          def canaries
            tally = @result.canaries.group_by(&:status).transform_values(&:size)
            line = "fts canaries: #{@result.canaries.size} sources probed — " +
                   tally.sort.map { |status, count| "#{count} #{status}" }.join(", ")
            passageless = @result.canaries.select { |canary| canary.status == :no_passages }.map(&:slug)
            line += " (no_documents = dictionary shelves / empty sources; nothing to index)" if tally[:no_documents]
            line += "\n  documents without passages: #{passageless.join(', ')}" unless passageless.empty?
            [line] + @result.misses.map do |canary|
              deferred = canary.deferred ? " [index_policy: deferred — `nabu index refresh #{canary.slug}`]" : ""
              "  canary #{canary.status.to_s.upcase.tr('_', ' ')}: #{canary.slug} #{canary.urn} " \
                "#{canary.phrase}#{deferred}"
            end
          end

          def capabilities
            gaps = @result.capability_gaps
            ["capability homes: #{@result.tools_checked} MCP tools checked; #{gaps.size} with missing homes"] +
              gaps.flat_map { |tool, list| list.map { |gap| "  #{tool}: #{gap}" } }
          end

          def summary
            drift = @result.census.count(&:drift?)
            "summary: #{drift} census drift(s), #{@result.missing_sources.size} empty source(s), " \
              "#{@result.misses.size} canary miss(es), #{@result.capability_gaps.size} tool(s) with home gaps"
          end
        end
      end
    end
  end
end
