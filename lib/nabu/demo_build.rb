# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "time"

module Nabu
  # The demo slice (`rake demo:build`): a SELF-CONTAINED demo library
  # directory the OCI image bakes in, so a fresh container's MCP server
  # answers real questions with no host mounts. The build runs REAL syncs
  # (network) — in CI per release, never in the suite; the tests inject the
  # command runner.
  #
  # == Layout (the image copies OUT to /demo)
  #
  #   OUT/config/            a copy of the project config/ (never profile.yml),
  #                          with a self-relative nabu.yml
  #   OUT/db/                the derived stores the server reads
  #                          (catalog.sqlite3, fulltext.sqlite3, …), sealed
  #                          into rollback-journal mode (no -wal/-shm needed)
  #   OUT/local/             the instance folder the syncs wrote (enablement
  #                          profile, the history ledger nabu_status reads)
  #   OUT/canonical/<slug>/  ONLY the KEEP_CANONICAL modules — the small
  #                          registry instruments tools feature-detect at call
  #                          time (the lect filter reads canonical/nabu-lects);
  #                          every other fetched tree stays in WORK
  #   OUT/demo-census.json   what was baked: sources + license classes +
  #                          document/passage/dictionary counts + bytes per file
  #
  # The server points at it with two variables and nothing else:
  #
  #   NABU_ROOT=OUT NABU_CONFIG=OUT/config/nabu.yml bin/nabu mcp [--http]
  #
  # WORK (default OUT-work, beside it) holds the full canonical fetch between
  # runs, so a re-run is an ordinary incremental re-sync — the task is
  # idempotent and re-runnable into its own output (the census marks the
  # directory as a demo; a foreign non-empty OUT is refused).
  #
  # == The license guard (two layers, both refusing loudly)
  #
  # 1. BEFORE any network: every slug in the plan — the demo set plus the
  #    core group and the whole `requires:` closure the sync would pull in —
  #    must declare a SERVABLE_LICENSE_CLASSES manifest class and be
  #    ungated (no blocked availability, no grant, no credentials).
  # 2. AFTER the syncs: the built catalog itself is re-read — every source
  #    row's class AND every document-level license_override must be
  #    servable, so a per-document class an adapter assigns at parse time
  #    cannot slip a non-commercial or private text into the image.
  #
  # The size ceiling (max_bytes, DEMO_MAX_MB) fails the build rather than
  # shipping an image larger than the slice was sized for.
  #
  # Deliberately NOT built here: the batch layers (links, vectors, mined
  # layers) — they are separate owner-fired commands, and the tools answer
  # their absence with the honest "not built" notes. The slice is a
  # read-only SERVING snapshot, not a rebuildable library: canonical/ is
  # pruned, so `nabu rebuild` inside the image is meaningless by design.
  class DemoBuild
    # A non-servable class (or access gate) in the plan or the built catalog.
    class LicenseRefused < Nabu::Error; end

    DemoSource = Data.define(:slug, :blurb)

    # The curated starter set, open/attribution only: the quickstart shelf
    # minus its two nc treebanks (proiel, iswoc), plus the open Bible
    # witnesses that keep `nabu_align "MARK 2.3"` multi-lingual.
    # census: ~105k passages + ~168k dictionary entries, 2026-10-29, the
    # live catalog's source_stats/dictionary_entries for these slugs —
    # an estimated 250-400 MB of derived stores (the library-wide ratio is
    # ~1.4 KB of catalog+index per passage); the census file measures the
    # real figure at every build.
    DEMO_SOURCES = [
      DemoSource.new(slug: "sblgnt", blurb: "SBL Greek New Testament (CC BY)"),
      DemoSource.new(slug: "vulgate", blurb: "Clementine Vulgate — the Latin witness (open)"),
      DemoSource.new(slug: "eng-web", blurb: "World English Bible — the English witness (open)"),
      DemoSource.new(slug: "oshb", blurb: "Open Scriptures Hebrew Bible — WLC text, morphology-tagged (open)"),
      DemoSource.new(slug: "lexica", blurb: "LSJ + Lewis & Short — the dictionary shelf (CC BY-SA)")
    ].freeze

    # const: the license model's redistributable classes (Model::Validation;
    # the nabu-data publishable set) — code, not corpus.
    SERVABLE_LICENSE_CLASSES = %w[open attribution].freeze

    # The canonical trees the image keeps: core registry instruments the
    # tools read lazily at call time. All attribution-class, together a few
    # MB. Everything else the tools need is derived into db/ at sync time
    # (the Pleiades place index included).
    KEEP_CANONICAL = %w[nabu-lects nabu-places cigs].freeze

    # Upstream bookkeeping never shipped inside kept trees.
    PRUNED_ENTRIES = %w[.git .attic].freeze

    CENSUS_FILE = "demo-census.json"
    CENSUS_SCHEMA = "nabu.demo-census/1"
    MIB = 1024 * 1024
    # census: 600 MiB, 2026-10-29, the demo slice's sized ceiling ("a few
    # hundred MB at most") — headroom over the DEMO_SOURCES estimate above.
    DEFAULT_MAX_BYTES = 600 * MIB

    attr_reader :out_dir, :work_dir, :max_bytes

    # The rake task's knobs: DEMO_OUT (default tmp/demo), DEMO_WORK
    # (default <out>-work), DEMO_MAX_MB. Relative paths resolve against
    # +project_root+.
    def self.from_env(env, registry:, project_root: Config::PROJECT_ROOT, **)
      out = File.expand_path(env.fetch("DEMO_OUT", "").to_s.strip.then { |v| v.empty? ? "tmp/demo" : v }, project_root)
      work = env.fetch("DEMO_WORK", "").to_s.strip
      work = work.empty? ? "#{out}-work" : File.expand_path(work, project_root)
      max_mb = env.fetch("DEMO_MAX_MB", "").to_s.strip
      max_bytes = max_mb.empty? ? DEFAULT_MAX_BYTES : Integer(max_mb, 10) * MIB
      new(registry: registry, out_dir: out, work_dir: work, project_root: project_root, max_bytes: max_bytes, **)
    end

    def initialize(registry:, out_dir:, work_dir:, project_root: Config::PROJECT_ROOT,
                   slugs: DEMO_SOURCES.map(&:slug), keep_canonical: KEEP_CANONICAL,
                   max_bytes: DEFAULT_MAX_BYTES, runner: nil, log: $stderr)
      @registry = registry
      @out_dir = File.expand_path(out_dir)
      @work_dir = File.expand_path(work_dir)
      @project_root = project_root
      @slugs = slugs
      @keep_canonical = keep_canonical
      @max_bytes = max_bytes
      @log = log
      @runner = runner || method(:shell_runner)
    end

    # Every slug the build will sync: the core group + the demo set, closed
    # over `requires:` (what `nabu sync` would pull in on a fresh box).
    def plan
      @registry.requires_closure(@registry.core_members + @slugs)
    end

    # Layer 1 — refuse before touching the network. Returns the plan.
    def guard!
      offenders = plan.filter_map { |slug| refusal(slug) }
      if offenders.any?
        raise LicenseRefused,
              "demo build refused — not servable in a public image: #{offenders.join(', ')}"
      end

      plan
    end

    # The whole build: guard → layout → enable + sync → catalog guard →
    # prune canonical → seal → census (written last: its presence marks a
    # finished demo). Returns the census hash.
    def build!
      guard!
      prepare_layout!
      write_nabu_yml(canonical: File.join(@work_dir, "canonical"))
      run_cli("enable", *@slugs)
      run_cli("sync", *@slugs)
      verify_catalog!
      write_nabu_yml(canonical: "canonical")
      prune_canonical!
      seal_stores!
      census = take_census
      if census[:total_bytes] > @max_bytes
        raise Nabu::Error, "demo slice is #{census[:total_bytes] / MIB} MiB — over the #{@max_bytes / MIB} MiB " \
                           "ceiling (trim DEMO_SOURCES or raise DEMO_MAX_MB deliberately)"
      end
      File.write(File.join(@out_dir, CENSUS_FILE), "#{JSON.pretty_generate(census)}\n")
      say("demo slice ready: #{@out_dir} (#{census[:total_bytes] / MIB} MiB)")
      census
    end

    # The environment the server (and the build's own CLI calls) run under.
    def runtime_env
      { "NABU_ROOT" => @out_dir, "NABU_CONFIG" => File.join(@out_dir, "config", "nabu.yml") }
    end

    private

    def refusal(slug)
      entry = @registry[slug]
      return "#{slug} (not in the registry)" unless entry
      return "#{slug} (blocked)" if entry.blocked?
      return "#{slug} (grant-gated)" if entry.grant_required?
      return "#{slug} (credentials: #{entry.credentials})" if entry.credentials

      license_class = entry.manifest.license_class
      SERVABLE_LICENSE_CLASSES.include?(license_class) ? nil : "#{slug} (#{license_class})"
    end

    def prepare_layout!
      if Dir.exist?(@out_dir) && !Dir.empty?(@out_dir) && !demo_dir?
        raise Nabu::Error, "demo build: #{@out_dir} is not empty and holds no #{CENSUS_FILE} — " \
                           "refusing to write into a directory that is not a demo slice"
      end
      FileUtils.rm_f(File.join(@out_dir, CENSUS_FILE)) # unfinished until the census lands again
      FileUtils.mkdir_p([@out_dir, @work_dir])
      config_out = File.join(@out_dir, "config")
      FileUtils.rm_rf(config_out)
      FileUtils.mkdir_p(config_out)
      source = File.join(@project_root, "config")
      Dir.children(source).sort.each do |name|
        next if %w[profile.yml nabu.yml].include?(name) # personal focus; the demo writes its own

        FileUtils.cp_r(File.join(source, name), config_out)
      end
    end

    def demo_dir?
      File.exist?(File.join(@out_dir, CENSUS_FILE)) || File.exist?(File.join(@out_dir, "config", "nabu.yml"))
    end

    def write_nabu_yml(canonical:)
      File.write(File.join(@out_dir, "config", "nabu.yml"), <<~YAML)
        # The demo slice's config (Nabu::DemoBuild) — relative paths resolve
        # against NABU_ROOT, the slice directory itself:
        #   NABU_ROOT=<slice> NABU_CONFIG=<slice>/config/nabu.yml bin/nabu mcp
        paths:
          canonical: #{canonical}
          db: db
          local: local
      YAML
    end

    def run_cli(*args)
      say("demo build: nabu #{args.join(' ')}")
      @runner.call(runtime_env, [RbConfig.ruby, File.join(@project_root, "bin", "nabu"), *args])
    end

    def shell_runner(env, argv)
      assignments = env.map { |key, value| "#{key}=#{value}" }
      Shell.stream("env", *assignments, *argv) { |line| @log.puts(line) }
    end

    def runtime_config
      Config.load(path: runtime_env.fetch("NABU_CONFIG"), root: @out_dir)
    end

    # Layer 2 — the built catalog, re-read: source rows and per-document
    # overrides alike.
    def verify_catalog!
      db = Store.connect(runtime_config.catalog_path, readonly: true)
      sources = db[:sources].exclude(license_class: SERVABLE_LICENSE_CLASSES)
                            .select_map(%i[slug license_class]).map { |slug, klass| "#{slug} (#{klass})" }
      documents = db[:documents].exclude(license_override: nil).exclude(license_override: SERVABLE_LICENSE_CLASSES)
                                .limit(10).select_map(%i[urn license_override])
                                .map { |urn, klass| "#{urn} (#{klass})" }
      offenders = sources + documents
      return if offenders.empty?

      raise LicenseRefused, "demo build refused — the built catalog carries non-servable material: " \
                            "#{offenders.join(', ')}"
    ensure
      db&.disconnect
    end

    def prune_canonical!
      work_canonical = File.join(@work_dir, "canonical")
      out_canonical = File.join(@out_dir, "canonical")
      FileUtils.rm_rf(out_canonical)
      FileUtils.mkdir_p(out_canonical)
      (@keep_canonical & plan).each do |slug|
        tree = File.join(work_canonical, slug)
        next unless Dir.exist?(tree)

        FileUtils.cp_r(tree, out_canonical)
        PRUNED_ENTRIES.each { |entry| FileUtils.rm_rf(File.join(out_canonical, slug, entry)) }
      end
    end

    def seal_stores!
      Dir.glob(File.join(@out_dir, "{db,local}", "**", "*.sqlite3")).each do |path|
        Store.seal_rollback_journal!(path)
      end
    end

    def take_census
      config = runtime_config
      db = Store.connect(config.catalog_path, readonly: true)
      stats = db[:source_stats].as_hash(:source_id, %i[live_documents live_passages])
      sources = db[:sources].order(:slug).select_map(%i[id slug license_class]).map do |id, slug, klass|
        documents, passages = stats.fetch(id, [0, 0])
        { slug: slug, license_class: klass, documents: documents.to_i, passages: passages.to_i }
      end
      entries = db.table_exists?(:dictionary_entries) ? db[:dictionary_entries].where(withdrawn: false).count : 0
      paths = Dir.glob(File.join(@out_dir, "**", "*"), File::FNM_DOTMATCH)
      files = paths.select { |path| File.file?(path) && File.basename(path) != CENSUS_FILE }.sort
                   .to_h { |path| [path.delete_prefix("#{@out_dir}/"), File.size(path)] }
      {
        schema: CENSUS_SCHEMA, nabu_version: Nabu::VERSION, built_at: Time.now.utc.iso8601,
        sources: sources,
        totals: { documents: sources.sum { |row| row[:documents] }, passages: sources.sum { |row| row[:passages] },
                  dictionary_entries: entries },
        files: files, total_bytes: files.values.sum
      }
    ensure
      db&.disconnect
    end

    def say(text)
      @log&.puts(text)
    end
  end
end
