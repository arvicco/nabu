# frozen_string_literal: true

require "fileutils"

require_relative "../errors"
require_relative "../shell"
require_relative "../version"
require_relative "../derivation_fingerprint"
require_relative "builder"
require_relative "languages_table"
require_relative "sources_bib"
require_relative "manifest"

module Nabu
  module DataBuild
    # One dataset build, end to end: resolve the canonical input shas
    # honestly, run the feature's builder, wrap its output in the uniform
    # dataset furniture (languages.csv, sources.bib, datapackage.json,
    # README.md), and return a Summary the CLI prints. The Runner writes
    # FILES into the owner's nabu-data working clone and NEVER runs git
    # operations there — reviewing, committing, and pushing the public data
    # repo is the owner's explicit act, not the rail's.
    class Runner
      # What the CLI summarizes: +files+ is [[relative path, row count or
      # nil], ...] in written order; +rows+ the data-row total; +fingerprint+
      # the manifest's derivation fingerprint.
      Summary = Data.define(:slug, :out_dir, :files, :rows, :fingerprint)

      def initialize(config:, registry:, catalog: nil)
        @config = config
        @registry = registry
        @catalog = catalog
      end

      # Build +feature+ into "<into>/<lang>/<feature>/". Inputs are resolved
      # BEFORE the builder runs, so a build that cannot be honestly described
      # writes nothing.
      def run(feature:, into:)
        raise Error, "#{feature.slug} is #{feature.status} — its builder has not landed yet" unless feature.available?

        input_shas = feature.canonical_cones.to_h { |cone| [cone, cone_sha(cone)] }
        guard_ingested_inputs!(feature)
        sources = source_refs(feature, input_shas)
        out_dir = File.join(File.expand_path(into.to_s), feature.slug)
        FileUtils.mkdir_p(out_dir)

        result = feature.builder.new.build(catalog: @catalog, out_dir: out_dir)
        language_count = LanguagesTable.write(dir: out_dir, languages: [feature.language])
        SourcesBib.write(dir: out_dir, citations: result.citations, slug: feature.slug)
        resources = result.resources + [LanguagesTable.resource(count: language_count), SourcesBib.resource]
        File.write(File.join(out_dir, "datapackage.json"),
                   Manifest.generate(feature: feature, resources: resources, input_shas: input_shas,
                                     recipe: result.recipe, sources: sources))
        fingerprint = Manifest.fingerprint(input_shas: input_shas, recipe: result.recipe)
        File.write(File.join(out_dir, "README.md"),
                   readme(feature: feature, result: result, input_shas: input_shas, fingerprint: fingerprint))

        files = result.resources.map { |resource| [resource.path, resource.rows] } +
                [[LanguagesTable::FILENAME, language_count], [SourcesBib::FILENAME, nil],
                 ["datapackage.json", nil], ["README.md", nil]]
        Summary.new(slug: feature.slug, out_dir: out_dir, files: files,
                    rows: resources.sum { |resource| resource.rows.to_i }, fingerprint: fingerprint)
      end

      private

      # The honest identity of one canonical cone. Git-backed cones publish
      # their HEAD sha — but only when the working tree is clean (a dirty
      # tree's HEAD does not name the bytes; refusing beats misdescribing —
      # the DerivationFingerprint weak-identity doctrine, hardened from
      # "never skip" to "never publish"). Non-git cones get the content
      # identity DerivationFingerprint computes.
      def cone_sha(cone)
        dir = File.join(@config.canonical_dir, cone)
        unless Dir.exist?(dir)
          raise Error, "canonical input #{cone.inspect} is missing (#{dir}) — sync it before building"
        end
        return tree_identity(dir, cone) unless File.directory?(File.join(dir, ".git"))

        unless Shell.run("git", "-C", dir, "status", "--porcelain").strip.empty?
          raise Error, "canonical/#{cone} has local modifications — HEAD cannot honestly name " \
                       "the bytes this dataset derives from; clean the tree before publishing"
        end
        Shell.run("git", "-C", dir, "rev-parse", "HEAD").strip
      rescue Shell::Error => e
        raise Error, "canonical/#{cone}: git failed (#{e.message}) — cannot name the input honestly"
      end

      def tree_identity(dir, cone)
        DerivationFingerprint.canonical_identity(dir) ||
          raise(Error, "canonical/#{cone} has no honest content identity (unreadable or dirty tree)")
      end

      # The stale-ingest guard (P50-r1, owner ruling D50-a). Catalog-reading
      # builders derive rows from the last INGEST of an input source, while
      # the manifest records the cone's CURRENT identity — if canonical
      # advanced without a re-ingest, the dataset would cite bytes its rows
      # were not derived from (silent provenance drift). So: with a catalog
      # open, every declared input's recorded last-ingest identity
      # (sources.last_ingest_identity, written by sync and rebuild alike;
      # migration 022) must equal the cone's current identity. Uniform across
      # read paths on purpose: even for a builder that reads canonical
      # directly, a catalog disagreeing with canonical means the box is
      # mid-ingest or torn, and the owner's normal flow (sync = fetch + load
      # + record, in one command) never trips it — so uniform-and-simple
      # costs nothing and refuses exactly the torn states. No catalog on the
      # box = no catalog rows to drift = nothing to guard (a builder that
      # NEEDS the catalog still refuses on its own). No --force: drifted
      # provenance is never publishable.
      def guard_ingested_inputs!(feature)
        return if @catalog.nil?

        feature.inputs.each do |slug|
          recorded = ingest_identity(slug)
          current = DerivationFingerprint.canonical_identity(File.join(@config.canonical_dir, slug))
          next if !recorded.nil? && recorded == current

          raise Error, stale_ingest_message(slug, recorded, current)
        end
      end

      def ingest_identity(slug)
        row = @catalog[:sources].where(slug: slug).first
        if row.nil?
          raise Error, "input source #{slug} has never been ingested into this catalog — " \
                       "run `nabu sync #{slug}` before building"
        end

        row[:last_ingest_identity]
      end

      def stale_ingest_message(slug, recorded, current)
        if recorded.nil?
          "the catalog does not record which canonical bytes its #{slug} rows were ingested from " \
            "(an ingest predating the record, or a tree with no honest identity) — " \
            "re-ingest with `nabu sync #{slug}` before building"
        else
          "canonical/#{slug} changed since the catalog last ingested it " \
            "(ingested #{short_identity(recorded)}, canonical now #{short_identity(current)}) — " \
            "the rows this build reads do not derive from the bytes the manifest would cite; " \
            "re-ingest with `nabu sync #{slug}` (no-network re-load: `nabu sync #{slug} --parse-only`), " \
            "then build again"
        end
      end

      def short_identity(identity)
        identity.nil? ? "(no honest identity)" : identity[0, 12]
      end

      # The manifest sources[] entries: title/path/license from each input
      # source's adapter manifest, version = the matching cone's sha (when a
      # cone of the same name was resolved).
      def source_refs(feature, input_shas)
        feature.inputs.map do |slug|
          entry = @registry[slug]
          raise Error, "input source #{slug.inspect} is not registered in sources.yml" if entry.nil?

          manifest = entry.manifest
          Manifest::SourceRef.new(title: manifest.name, path: manifest.upstream_url,
                                  version: input_shas[slug], licenses: [{ "name" => manifest.license }])
        end
      end

      def readme(feature:, result:, input_shas:, fingerprint:)
        lines = ["# #{feature.title}", "",
                 "`#{feature.slug}` — #{feature.tier} tier, anchoring: #{feature.anchoring}. " \
                 "Produced by `nabu data build #{feature.slug}` (Nabu #{Nabu::VERSION}); the " \
                 "producer-side contract is docs/nabu-data.md in the Nabu repository.", "",
                 feature.rationale, "",
                 "## Maintenance", "", feature.maintenance, "",
                 "## Provenance", ""]
        lines.concat(provenance_lines(input_shas))
        lines << ""
        lines << "Recipe: #{result.recipe}"
        lines << ""
        lines << "Derivation fingerprint: `#{fingerprint}`."
        lines.push("", result.notes) if result.notes
        "#{lines.join("\n")}\n"
      end

      def provenance_lines(input_shas)
        if input_shas.empty?
          ["Own authorship — no canonical corpus inputs."]
        else
          ["Canonical inputs at derivation:", ""] +
            input_shas.sort.map { |cone, sha| "- `#{cone}` @ `#{sha}`" }
        end
      end
    end
  end
end
