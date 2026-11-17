# frozen_string_literal: true

require "digest"
require "find"
require "fileutils"
require "json"
require "pathname"
require "yaml"
require_relative "verify"
require_relative "../site_data"
require_relative "../../store/source_stats"

module Nabu
  module Ops
    module Reconstruction
      # `nabu reconstruct manifest` / `reconstruct check`: the PORTABLE
      # REFERENCE MANIFEST — what a box held at one commit, written so a
      # second box can prove it arrived at the same library:
      #
      #   schema: 1
      #   reference: {commit: "<git HEAD sha>", as_of: "YYYY-MM-DD"}
      #   census: {documents: N, passages: N, language_codes: N, live_sources: N}
      #   sources:
      #     <slug>:
      #       transport: carried | resynced
      #       documents: N
      #       passages: N
      #       canary: {urn: "...", phrase: "\"w1 w2 w3 w4\""}
      #   trees:
      #     - {path: "local", bytes: N, files: N, sha256: "<hex>"}
      #
      # The format is frozen at schema 1. The parsed YAML hash IS the
      # interface: consumers read it with Manifest.load (a plain
      # YAML.safe_load_file) and index the string keys above — there is no
      # wrapper object to keep in step. Census and per-source counts read
      # the precompiled source_stats (as Verify does); sources are the live
      # public slugs; a source is "carried" when its whole canonical tree
      # is in the backup set, else "resynced"; the canary is Verify's own
      # deterministic sample and phrase, so the receiving box's `reconstruct
      # verify` probes exactly what the manifest names.
      #
      # trees[] digests the backup set's entries (repo-relative): a file is
      # the sha256 of its contents; a directory is the sha256 over the
      # bytewise-sorted lines "relpath\tsha256(file)\n" for every file under
      # it, a symlink hashing its target string (never followed); bytes and
      # files sum what was hashed. Digesting the full set reads every carried
      # byte — an owner-fired cost, so it is skippable (trees: []).
      #
      # The manifest is PRIVATE: it names access-gated holdings. Nothing
      # here writes it into the repo tree; the CLI prints to stdout unless
      # given --out.
      class Manifest
        SCHEMA = 1

        # One line of the arrival check: :ok, :mismatch or :absent.
        CheckRow = Data.define(:path, :status, :expected, :actual)

        def initialize(registry:, catalog:, entry_paths:, root:, canonical_dir:, commit:, as_of:, trees: true)
          @registry = registry
          @catalog = catalog
          @entry_paths = entry_paths.map { |path| File.expand_path(path) }
          @root = File.expand_path(root)
          @canonical_dir = File.expand_path(canonical_dir)
          @commit = commit
          @as_of = as_of
          @trees = trees
        end

        def build
          {
            "schema" => SCHEMA,
            "reference" => { "commit" => @commit, "as_of" => @as_of },
            "census" => census,
            "sources" => live_slugs.to_h { |slug| [slug, source_row(slug)] },
            "trees" => @trees ? trees : []
          }
        end

        # The frozen YAML text (flow-style leaves, as the format above).
        def self.render(manifest)
          lines = ["schema: #{manifest['schema']}",
                   "reference: #{flow(manifest['reference'])}",
                   "census: #{flow(manifest['census'])}"]
          sources = manifest["sources"] || {}
          lines << (sources.empty? ? "sources: {}" : "sources:")
          sources.each do |slug, row|
            lines << "  #{key(slug)}:"
            lines << "    transport: #{row['transport']}"
            lines << "    documents: #{scalar(row['documents'])}"
            lines << "    passages: #{scalar(row['passages'])}"
            lines << "    canary: #{row['canary'] ? flow(row['canary']) : 'null'}"
          end
          trees = manifest["trees"] || []
          lines << (trees.empty? ? "trees: []" : "trees:")
          trees.each { |tree| lines << "  - #{flow(tree.slice('path', 'bytes', 'files', 'sha256'))}" }
          "#{lines.join("\n")}\n"
        end

        def self.write(manifest, path)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, render(manifest))
        end

        def self.load(path) = YAML.safe_load_file(path)

        # { "bytes", "files", "sha256" } for a path, or nil when absent.
        def self.digest(path)
          stat = File.lstat(path)
          if stat.symlink?
            target = File.readlink(path)
            { "bytes" => target.bytesize, "files" => 1, "sha256" => Digest::SHA256.hexdigest(target) }
          elsif stat.directory?
            directory_digest(path)
          else
            { "bytes" => stat.size, "files" => 1, "sha256" => Digest::SHA256.file(path).hexdigest }
          end
        rescue Errno::ENOENT
          nil
        end

        # Re-digest every trees[] path under root and compare.
        def self.check(manifest, root:)
          Array(manifest["trees"]).map do |tree|
            actual = digest(File.expand_path(tree["path"], root))
            status = if actual.nil? then :absent
                     elsif actual["sha256"] == tree["sha256"] && actual["bytes"] == tree["bytes"] then :ok
                     else :mismatch
                     end
            CheckRow.new(path: tree["path"], status: status, expected: tree, actual: actual)
          end
        end

        def self.render_check(rows, reference: nil)
          ref = reference ? " (reference #{reference['commit']}, #{reference['as_of']})" : ""
          lines = ["reconstruct check — #{rows.size} carried tree(s) against the manifest#{ref}"]
          rows.each do |row|
            line = format("  %-8<status>s %<path>s", status: row.status == :ok ? "ok" : row.status.to_s.upcase,
                                                     path: row.path)
            if row.status == :mismatch
              line += "  — expected #{row.expected['bytes']} B / #{row.expected['files']} files / " \
                      "#{row.expected['sha256'].to_s[0, 12]}, found #{row.actual['bytes']} B / " \
                      "#{row.actual['files']} files / #{row.actual['sha256'][0, 12]}"
            end
            lines << line
          end
          bad = rows.count { |row| row.status != :ok }
          lines << "summary: #{rows.size - bad} ok, #{bad} mismatched or absent"
          "#{lines.join("\n")}\n"
        end

        def self.directory_digest(dir)
          lines = []
          bytes = 0
          prefix = "#{dir.chomp('/')}/"
          Find.find(dir) do |path|
            stat = File.lstat(path)
            next if stat.directory?

            relpath = path.delete_prefix(prefix)
            if stat.symlink?
              target = File.readlink(path)
              bytes += target.bytesize
              sha = Digest::SHA256.hexdigest(target)
            else
              bytes += stat.size
              sha = Digest::SHA256.file(path).hexdigest
            end
            lines << "#{relpath}\t#{sha}\n".b
          end
          { "bytes" => bytes, "files" => lines.size, "sha256" => Digest::SHA256.hexdigest(lines.sort.join) }
        end
        private_class_method :directory_digest

        def self.flow(hash)
          "{#{hash.map { |name, value| "#{name}: #{scalar(value)}" }.join(', ')}}"
        end
        private_class_method :flow

        def self.scalar(value)
          case value
          when nil then "null"
          when Integer then value.to_s
          else JSON.generate(value.to_s)
          end
        end
        private_class_method :scalar

        # A slug renders bare unless YAML would read it as something else
        # ("yes", "on", "1e3" …): then it is double-quoted.
        def self.key(slug)
          bare = slug.match?(/\A[a-z0-9][a-z0-9._-]*\z/) && YAML.safe_load("#{slug}: 0").keys == [slug]
          bare ? slug : JSON.generate(slug)
        end
        private_class_method :key

        private

        def live_slugs = @live_slugs ||= SiteData.live_public_slugs(@registry)

        def source_ids = @source_ids ||= @catalog[:sources].select_hash(:slug, :id)

        def stats? = @stats ||= Store::SourceStats.available?(@catalog)

        def census
          rollup = stats? ? Store::SourceStats.rollup(@catalog) : nil
          { "documents" => rollup&.fetch(:live_documents), "passages" => rollup&.fetch(:live_passages),
            "language_codes" => stats? ? Store::SourceStats.language_codes(@catalog) : nil,
            "live_sources" => live_slugs.size }
        end

        def source_row(slug)
          id = source_ids[slug]
          counts = if id.nil? then { live_documents: 0, live_passages: 0 }
                   elsif stats? then Store::SourceStats.fetch(@catalog, id)
                   else { live_documents: nil, live_passages: nil }
                   end
          { "transport" => carried?(slug) ? "carried" : "resynced",
            "documents" => counts[:live_documents], "passages" => counts[:live_passages],
            "canary" => canary(id) }
        end

        def carried?(slug) = @entry_paths.include?(File.join(@canonical_dir, slug))

        def canary(source_id)
          sample = source_id && Verify.sample_passage(@catalog, source_id)
          return nil if sample.nil?

          { "urn" => sample[:urn], "phrase" => Verify.phrase(sample[:text_search]) }
        end

        def trees
          @entry_paths.filter_map do |path|
            digest = self.class.digest(path)
            next if digest.nil?

            { "path" => Pathname(path).relative_path_from(Pathname(@root)).to_s }.merge(digest)
          end
        end
      end
    end
  end
end
