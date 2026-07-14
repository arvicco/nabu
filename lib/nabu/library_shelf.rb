# frozen_string_literal: true

require "digest"
require "fileutils"
require "yaml"
require_relative "library_manifest"
require_relative "local_fetch"

module Nabu
  # The SANCTIONED write gateway to the canonical/local-library shelf
  # (P19-5, architecture §16) — LanguageShelf's sibling, and the same
  # doctrine: canonical/ is the permanent asset and application code never
  # writes it except through Adapter#fetch, the ad-hoc pipeline, and a local
  # shelf's one write gateway. For the library shelf that gateway is this
  # class, driven by `nabu ingest` (the intake front door): it COPIES a file
  # into <dir>/<collection>/ (never moves — the source stays where it was)
  # and APPENDS one manifest entry mechanically, without rewriting the rest
  # of the file (the manifest is a YAML LIST precisely so an append never
  # touches the owner's existing entries or comments). Everything else —
  # loaders, enrichers, queries, the adapter's own LocalFetch scan — stays
  # read-only on the shelf.
  class LibraryShelf
    # The shelf's directory name under canonical/ — also its registry slug.
    SLUG = "local-library"

    # A gateway refusal (bad target name, malformed manifest, duplicate
    # entry). Callers report it per file; it never aborts a whole ingest.
    class Error < Nabu::Error; end

    # Collection names become path segments AND urn segments: keep them to
    # one honest directory name (no separators, no dot-prefix).
    COLLECTION_NAME = /\A[a-zA-Z0-9][a-zA-Z0-9._-]*\z/

    def self.dir(canonical_dir)
      File.join(canonical_dir, SLUG)
    end

    def self.sha256(path)
      Digest::SHA256.file(path).hexdigest
    end

    def initialize(dir:)
      @dir = dir
    end

    attr_reader :dir

    # { sha256 => "collection/relative/path" } over every live file in the
    # tree (attic and scan-state excluded) — the duplicate-detection index.
    # Built once per ingest run; #copy_in! keeps it current.
    def sha_index
      @sha_index ||= scan_shas
    end

    # Copy +source+ into <dir>/<collection>/<basename> (never move; an
    # existing target is overwritten — the revision story). Returns the
    # file name relative to the collection dir.
    def copy_in!(source, collection:)
      file = File.basename(source)
      validate_collection!(collection)
      validate_file_name!(file)
      target_dir = File.join(@dir, collection)
      FileUtils.mkdir_p(target_dir)
      FileUtils.cp(source, File.join(target_dir, file))
      sha_index[self.class.sha256(source)] ||= "#{collection}/#{file}"
      file
    end

    # Whether the collection's manifest already carries an entry for +file+.
    # A malformed manifest raises (an append into a broken record would only
    # deepen the damage — fix the manifest first).
    def manifested?(collection, file)
      manifest = load_manifest(collection)
      return false if manifest.nil?

      manifest.entries.any? { |entry| entry.file == file }
    end

    # Append one entry (a String-keyed Hash, "file" required) to the
    # collection's manifest, creating collection dir + manifest if new.
    # Append-only: existing bytes (entries, owner comments) are never
    # rewritten. The result is re-validated through LibraryManifest so a bad
    # append can never land silently.
    def append_entry!(collection:, entry:)
      validate_collection!(collection)
      file = entry.fetch("file")
      raise Error, "#{collection}/#{file}: already manifested — edit the manifest to change it" \
        if manifested?(collection, file)

      path = manifest_path(collection)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render_entry(entry, exists: File.file?(path)), mode: "a")
      LibraryManifest.load(path)
      path
    rescue LibraryManifest::FormatError => e
      raise Error, "manifest append failed validation: #{e.message}"
    end

    def manifest_path(collection)
      File.join(@dir, collection, LibraryManifest::FILENAME)
    end

    private

    # One YAML list item, keys in the manifest's canonical order, separated
    # from any existing content by a blank line (readable, diff-friendly).
    def render_entry(entry, exists:)
      item = YAML.dump([entry]).delete_prefix("---\n")
      exists ? "\n#{item}" : item
    end

    def validate_collection!(collection)
      return if collection.match?(COLLECTION_NAME)

      raise Error, "collection #{collection.inspect} must be one plain directory name " \
                   "(letters, digits, . _ -; no leading dot)"
    end

    def validate_file_name!(file)
      raise Error, "refusing to ingest a file named #{LibraryManifest::FILENAME} (the manifest is the record)" \
        if file == LibraryManifest::FILENAME
      raise Error, "refusing dot-file #{file.inspect} (shelf furniture lives there)" if file.start_with?(".")
    end

    def load_manifest(collection)
      path = manifest_path(collection)
      return nil unless File.file?(path)

      LibraryManifest.load(path)
    rescue LibraryManifest::FormatError => e
      raise Error, "cannot append to a malformed manifest — #{e.message}"
    end

    def scan_shas
      return {} unless Dir.exist?(@dir)

      attic = "#{Adapter::ATTIC_DIRNAME}#{File::SEPARATOR}"
      Dir.glob("**/*", base: @dir)
         .select { |rel| File.file?(File.join(@dir, rel)) }
         .reject { |rel| rel == LocalFetch::STATE_FILE || rel.start_with?(attic) }
         .sort
         .each_with_object({}) { |rel, map| map[self.class.sha256(File.join(@dir, rel))] ||= rel }
    end
  end
end
