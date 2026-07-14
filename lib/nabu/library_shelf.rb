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
    # rewritten. The result is re-validated through LibraryManifest and a
    # rejected append is ROLLED BACK (truncated to the prior bytes) — a bad
    # entry can never land at all, the loader-facing invariant `nabu
    # ingest` promises (P20-1).
    def append_entry!(collection:, entry:)
      validate_collection!(collection)
      file = entry.fetch("file")
      raise Error, "#{collection}/#{file}: already manifested — edit the manifest to change it" \
        if manifested?(collection, file)

      path = manifest_path(collection)
      FileUtils.mkdir_p(File.dirname(path))
      prior_size = File.file?(path) ? File.size(path) : nil
      File.write(path, render_entry(entry, exists: !prior_size.nil?), mode: "a")
      revalidate!(path, prior_size)
      path
    end

    def manifest_path(collection)
      File.join(@dir, collection, LibraryManifest::FILENAME)
    end

    # The collection's FUTURE manifest bytes with +entries+ appended — the
    # prepare-phase rehearsal material (P20-1): the ingest engine parses
    # these through LibraryManifest against a STAGING file to prove the
    # eventual append cannot be rejected. Reads only, renders identically
    # to append_entry! (same render_entry, byte for byte).
    def future_manifest(collection, entries)
      base = File.file?(manifest_path(collection)) ? File.read(manifest_path(collection)) : ""
      entries.reduce(base) { |content, entry| content + render_entry(entry, exists: !content.empty?) }
    end

    # Compensating delete for a failed commit (P20-1): remove the file just
    # copied in when its manifest append failed — canonical never keeps a
    # stray. Only the ingest engine's rollback path calls this; it refuses
    # anything already manifested (that would be a hard delete of record).
    def remove_copy!(collection:, file:)
      raise Error, "#{collection}/#{file} is manifested — not a stray, refusing to remove" \
        if manifested?(collection, file)

      target = File.join(@dir, collection, file)
      File.delete(target) if File.file?(target)
    end

    private

    # One YAML list item, keys in the manifest's canonical order, separated
    # from any existing content by a blank line (readable, diff-friendly).
    def render_entry(entry, exists:)
      item = YAML.dump([entry]).delete_prefix("---\n")
      exists ? "\n#{item}" : item
    end

    # +prior_size+ nil means the append created the file (delete it whole);
    # otherwise truncate back to the owner's untouched prior bytes.
    def revalidate!(path, prior_size)
      LibraryManifest.load(path)
    rescue LibraryManifest::FormatError => e
      prior_size.nil? ? File.delete(path) : File.truncate(path, prior_size)
      raise Error, "manifest append failed validation: #{e.message}"
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
