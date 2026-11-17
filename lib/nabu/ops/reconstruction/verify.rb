# frozen_string_literal: true

require "date"
require "yaml"
require_relative "../../errors"
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
      #
      # `against:` (a reference box's parsed manifest, schema 1) turns the
      # battery into a box-to-box check: the census diffs the manifest's
      # census; every manifest source's live counts are compared with the
      # reference's (a CARRIED tree plus the deterministic rebuild must
      # match exactly — any delta is failure-class; a RESYNCED tree drifts
      # honestly when upstream moved since the stamp); and the canaries
      # come from the manifest — each urn resolved to THIS box's own
      # passage id (rowids differ across boxes) and probed as above. Under
      # --strict only failure-class findings fail: a count mismatch on a
      # carried source, a missing source, a carried canary miss (or an
      # index that is absent / errors on any source), a capability gap —
      # never resynced drift, or a strict run could not go green once
      # upstream moves.
      class Verify
        class ManifestError < Nabu::Error; end

        MANIFEST_SCHEMA = 1
        LIVE_COUNTS = %i[live_documents live_passages].freeze
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

        # transport: the manifest source's ("carried" / "resynced"), nil for
        # a live-sampled canary. Anything but "resynced" is held to carried's
        # exactness — the strict reading of an unknown transport.
        Canary = Data.define(:slug, :status, :urn, :phrase, :deferred, :transport) do
          def initialize(slug:, status:, urn: nil, phrase: nil, deferred: false, transport: nil)
            super
          end

          def failed? = %i[miss absent no_index error].include?(status)

          # A failed manifest canary that no upstream move explains: on a
          # carried source, or a box-side index fault on any source.
          def failure_class? = failed? && (transport != "resynced" || %i[no_index error].include?(status))
        end

        # One manifest source against this box. present: the slug has a
        # sources row here; documents/passages nil when source_stats is
        # absent (the derived census a rebuild always produces).
        SourceRow = Data.define(:slug, :transport, :expected_documents, :expected_passages, :documents,
                                :passages, :present) do
          def resynced? = transport == "resynced"

          def status
            return :missing unless present
            return :unknown if documents.nil?
            return :exact if documents == expected_documents && passages == expected_passages

            resynced? ? :drift : :mismatch
          end

          def failure? = %i[missing unknown mismatch].include?(status)
        end

        Result = Data.define(:census_path, :as_of, :census, :live_sources, :missing_sources, :canaries,
                             :capability_gaps, :tools_checked, :reference, :source_rows, :new_sources) do
          def initialize(census_path:, as_of:, census:, live_sources:, missing_sources:, canaries:,
                         capability_gaps:, tools_checked:, reference: nil, source_rows: [], new_sources: [])
            super
          end

          def misses = canaries.select(&:failed?)

          # Against a manifest (reference is its Hash): failure-class only.
          def against? = !reference.nil?

          def failure_canaries = misses.select(&:failure_class?)

          def drift_canaries = misses.reject(&:failure_class?)

          def failed?(strict:)
            if against?
              return strict && (source_rows.any?(&:failure?) || !failure_canaries.empty? ||
                                !capability_gaps.empty?)
            end

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
                       tools: MCP::Tools::TOOLS, against: nil)
          @registry = registry
          @catalog = catalog
          @fulltext = fulltext
          @census_path = census_path
          @capabilities = capabilities
          @homes = homes
          @tools = tools
          @against = against
        end

        def run
          return run_against if @against

          committed = File.exist?(@census_path.to_s) ? (YAML.safe_load_file(@census_path) || {}) : {}
          Result.new(census_path: @census_path, as_of: committed["as_of"], census: census(committed),
                     live_sources: live_slugs.size, missing_sources: missing_sources, canaries: canaries,
                     capability_gaps: capability_gaps, tools_checked: @homes ? @tools.size : 0)
        end

        def self.render(result)
          Render.new(result).to_s
        end

        # The parsed manifest at path, or a ManifestError naming why not
        # (absent, unparseable, a schema this verifier does not read).
        def self.load_manifest(path)
          raise ManifestError, "no manifest at #{path}" unless File.file?(path.to_s)

          manifest = YAML.safe_load_file(path, permitted_classes: [Date])
          schema = manifest.is_a?(Hash) ? manifest["schema"] : nil
          unless schema == MANIFEST_SCHEMA
            raise ManifestError, "#{path}: manifest schema #{schema.inspect} — reconstruct verify expects " \
                                 "schema #{MANIFEST_SCHEMA}"
          end

          manifest
        rescue Psych::Exception => e
          raise ManifestError, "#{path}: unreadable manifest (#{e.message})"
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

        def run_against
          sources = @against["sources"] || {}
          Result.new(census_path: nil, as_of: @against.dig("reference", "as_of")&.to_s,
                     census: census(@against["census"] || {}), live_sources: live_slugs.size,
                     missing_sources: missing_sources, canaries: manifest_canaries(sources),
                     capability_gaps: capability_gaps, tools_checked: @homes ? @tools.size : 0,
                     reference: @against["reference"] || {}, source_rows: source_rows(sources),
                     new_sources: live_slugs - sources.keys)
        end

        def source_rows(sources)
          counts = stats? ? @catalog[Store::SourceStats::TABLE].select_hash(:source_id, LIVE_COUNTS) : nil
          sources.map do |slug, row|
            id = source_ids[slug]
            documents, passages = counts && (counts[id] || [0, 0])
            SourceRow.new(slug: slug, transport: row["transport"], expected_documents: row["documents"],
                          expected_passages: row["passages"], documents: documents, passages: passages,
                          present: !id.nil?)
          end
        end

        # The manifest's canaries, each urn resolved to this box's own live
        # passage id — never a rowid carried from the reference. A missing
        # source probes nothing (its row already says so); a source the
        # reference sampled no canary for is skipped.
        def manifest_canaries(sources)
          index = @fulltext&.table_exists?(Store::Indexer::TABLE)
          contentless = index && Store::Indexer.fts_contentless?(@fulltext)
          sources.filter_map do |slug, row|
            canary = row["canary"]
            next if canary.nil? || source_ids[slug].nil?

            urn = canary["urn"]
            phrase = canary["phrase"]
            id = live_passage_id(urn)
            status = if id.nil? then :absent
                     elsif !index then :no_index
                     else probe(id, phrase, contentless)
                     end
            Canary.new(slug: slug, status: status, urn: urn, phrase: phrase, transport: row["transport"],
                       deferred: @registry[slug]&.index_deferred? || false)
          end
        end

        def live_passage_id(urn)
          @catalog[:passages].join(:documents, id: :document_id)
                             .where(Sequel[:passages][:urn] => urn.to_s, Sequel[:passages][:withdrawn] => false,
                                    Sequel[:documents][:withdrawn] => false)
                             .get(Sequel[:passages][:id])
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
            lines = if @result.against?
                      [header, *census, "", *sources, "", presence, *canaries, "", *capabilities, "",
                       against_summary]
                    else
                      [header, *census, "", presence, *canaries, "", *capabilities, "", summary]
                    end
            "#{lines.join("\n")}\n"
          end

          private

          def header
            if @result.against?
              return "reconstruct verify — the probe battery against reference " \
                     "#{@result.reference['commit'] || '?'}#{" (as of #{@result.as_of})" if @result.as_of}"
            end

            "reconstruct verify — the probe battery against #{@result.census_path}" \
              "#{" (stamped #{@result.as_of})" if @result.as_of}"
          end

          def num(value) = value.nil? ? "?" : Eta.commas(value)

          def signed(value) = "#{'+' if value.positive?}#{num(value)}"

          def census
            if @result.census.all? { |row| row.committed.nil? }
              return ["census: the reference manifest carries no census — nothing to diff against"] if @result.against?

              return ["census: no committed census at #{@result.census_path} — nothing to diff against"]
            end

            if @result.against?
              return ["census (reference → live; drift is expected where sources re-synced since the stamp):"] +
                     census_rows
            end

            ["census (committed → live; drift is expected when the library moved since the stamp):"] + census_rows
          end

          def census_rows
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

          # Per-source rows against the reference: a tally, then every row
          # that is not exact (exact rows are the silent majority).
          def sources
            rows = @result.source_rows
            tally = rows.group_by(&:status).transform_values(&:size)
            head = "sources (reference → live; carried must match exactly, resynced may drift): " \
                   "#{rows.size} in the reference — #{tally[:exact].to_i} exact, #{tally[:drift].to_i} drift, " \
                   "#{tally[:mismatch].to_i} MISMATCH, #{tally[:missing].to_i} missing" \
                   "#{", #{tally[:unknown]} unknown (no source_stats)" if tally[:unknown]}; " \
                   "#{@result.new_sources.size} new since the reference"
            lines = rows.reject { |row| row.status == :exact }.map do |row|
              format("  %-20<s>s %-9<t>s %<b>s", s: row.slug, t: row.transport, b: source_body(row))
            end
            lines << "  new since the reference: #{@result.new_sources.join(', ')}" unless @result.new_sources.empty?
            [head, *lines]
          end

          def source_body(row)
            case row.status
            when :missing then "missing (no live counterpart)"
            when :unknown then "unknown (no source_stats)"
            else
              documents = count_pair(row, row.expected_documents, row.documents)
              "documents #{documents}, passages #{count_pair(row, row.expected_passages, row.passages)}"
            end
          end

          def count_pair(row, expected, live)
            delta = live.to_i - expected.to_i
            mark = if delta.zero? then "="
                   elsif row.resynced? then "drift #{signed(delta)}"
                   else "MISMATCH #{signed(delta)}"
                   end
            "#{num(expected)} → #{num(live)} #{mark}"
          end

          def canaries
            return against_canaries if @result.against?

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

          def against_canaries
            tally = @result.canaries.group_by(&:status).transform_values(&:size)
            line = "fts canaries (from the reference, resolved by urn): #{@result.canaries.size} probed — " +
                   tally.sort.map { |status, count| "#{count} #{status}" }.join(", ")
            [line] + @result.misses.map do |canary|
              klass = canary.failure_class? ? "#{canary.transport || 'carried'} — failure" : "resynced — drift"
              deferred = canary.deferred ? " [index_policy: deferred — `nabu index refresh #{canary.slug}`]" : ""
              "  canary #{canary.status.to_s.upcase.tr('_', ' ')} (#{klass}): #{canary.slug} #{canary.urn} " \
                "#{canary.phrase}#{deferred}"
            end
          end

          def against_summary
            rows = @result.source_rows
            mismatches = rows.count { |row| %i[mismatch unknown].include?(row.status) }
            missing = rows.count { |row| row.status == :missing }
            failing = @result.failure_canaries.size
            gaps = @result.capability_gaps.size
            drifts = rows.count { |row| row.status == :drift }
            canary_drift = @result.drift_canaries.size
            "summary: #{mismatches + missing + failing + gaps} failure-class finding(s) " \
              "(#{mismatches} carried count MISMATCH(es), #{missing} missing source(s), " \
              "#{failing} failing canar#{failing == 1 ? 'y' : 'ies'}, #{gaps} tool(s) with home gaps); " \
              "#{drifts + canary_drift} expected drift(s) (#{drifts} resynced count drift(s), " \
              "#{canary_drift} resynced canary miss(es)); #{@result.census.count(&:drift?)} census drift(s); " \
              "#{@result.new_sources.size} new source(s)"
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
