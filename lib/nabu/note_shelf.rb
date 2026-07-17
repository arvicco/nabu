# frozen_string_literal: true

require "fileutils"
require "yaml"
require_relative "note_file"
require_relative "query/show"

module Nabu
  # The SANCTIONED write gateway to the canonical/local-notes shelf (P24-1,
  # architecture §16) — the FOURTH local-shelf gateway, beside LanguageShelf
  # (dossiers), LibraryShelf (the library) and the ad-hoc pipeline, and the
  # same doctrine: canonical/ is the permanent asset, application code never
  # writes it except through Adapter#fetch and a local shelf's one write
  # gateway. For the notes shelf that gateway is this class, driven by
  # `nabu note`: it APPENDS one note record to <dir>/<topic>.yml
  # mechanically, without rewriting the rest of the file (the file is a YAML
  # LIST precisely so an append never touches the owner's existing records
  # or comments — the LibraryShelf pattern, reparse-validate + rollback
  # included). Everything else — the loader, the query surfaces, the
  # adapter's own LocalFetch scan — stays read-only on the shelf.
  #
  # == URN resolution, before any write
  #
  # A note keys on a urn the corpus KNOWS: the +resolver+ (a callable
  # urn → boolean; .catalog_resolver wires Query::Show, so documents,
  # passages, ranges and dictionary-entry urns all resolve) is consulted
  # BEFORE the append, and a miss is an error naming the urn — a note on a
  # typo'd urn would sit unreachable forever. +force+ skips resolution
  # deliberately (honest use: notes on planned, not-yet-held material) and
  # such notes read "dangling" at render until the urn arrives.
  class NoteShelf
    # The shelf's directory name under canonical/ — also its registry slug.
    SLUG = "local-notes"
    DEFAULT_TOPIC = "notes"

    # A gateway refusal (unresolvable urn, empty note, bad topic, malformed
    # topic file). The CLI reports it; nothing was written.
    class Error < Nabu::Error; end

    # Topic names become file stems (and render labels): one honest
    # lowercase name, no separators, no dot-prefix. "manifest" is reserved
    # shelf furniture (the other shelves' record file claims the name), so
    # gateway and discovery agree it is never a topic.
    TOPIC_NAME = /\A[a-z0-9][a-z0-9_-]*\z/
    RESERVED_TOPICS = %w[manifest].freeze

    def self.dir(canonical_dir)
      File.join(canonical_dir, SLUG)
    end

    # The standard resolver: Query::Show's urn resolution over +catalog+ —
    # passage, document, range, and (P22-2) dictionary-entry urns alike. A
    # range whose endpoint is missing raises inside Show; here that is
    # simply a miss, never a crash.
    def self.catalog_resolver(catalog)
      show = Query::Show.new(catalog: catalog)
      lambda do |urn|
        !show.run(urn).nil?
      rescue Query::Range::Error
        false
      end
    end

    def initialize(dir:, resolver: nil)
      @dir = dir
      @resolver = resolver
    end

    attr_reader :dir

    def path_for(topic)
      File.join(@dir, "#{topic}.yml")
    end

    # The topic's NoteFile, or nil when none exists yet. A malformed file
    # raises NoteFile::FormatError — an append must never build on a record
    # it cannot faithfully re-render.
    def load(topic)
      path = path_for(topic)
      return nil unless File.file?(path)

      NoteFile.load(path)
    end

    # Append one note record to <dir>/<topic>.yml, creating dir + file if
    # new. Append-only: existing bytes (records, owner comments) are never
    # rewritten. The result is re-validated through NoteFile and a rejected
    # append is ROLLED BACK (truncated to the prior bytes) — a record the
    # loader would refuse can never land. Returns the topic file's path.
    def append_note!(urn:, note:, topic: DEFAULT_TOPIC, tags: [], force: false, now: Time.now)
      validate_topic!(topic)
      urn = urn.to_s.strip
      body = Normalize.nfc(note.to_s).strip
      raise Error, "a note needs a urn" if urn.empty?
      raise Error, "refusing an empty note — say something about #{urn}" if body.empty?

      resolve!(urn, force: force)
      guard_existing!(topic)
      write_record!(topic, build_record(urn, body, tags, now))
    end

    # What one removal did: the record, its topic, the file path, and
    # whether the file itself was deleted (last record removed).
    Removal = Data.define(:record, :topic, :path, :file_deleted)

    # Remove ONE note by its computed id (NoteFile.record_id — shown by
    # --list and the bare-urn read-back). +topic+ scopes the search; without
    # it every topic file is searched. Zero matches and ambiguity are named
    # errors; the rewrite goes through the same reparse-validate the append
    # uses, and removing the last record deletes the file (an empty notes
    # file is furniture, not content).
    def remove_note!(id:, topic: nil)
      id = id.to_s.strip.downcase
      raise Error, "note --rm needs an id (nabu note --list shows them)" if id.empty?

      matches = find_by_id(id, topic)
      raise Error, "no note with id #{id}#{" in topic #{topic}" if topic} — nabu note --list shows ids" \
        if matches.empty?

      if matches.size > 1
        listing = matches.map { |t, r, _| "#{id} (#{t}) #{r.urn}" }.join("; ")
        raise Error, "id #{id} is ambiguous across topics (#{listing}) — scope with --topic"
      end

      found_topic, record, path = matches.first
      note_file = NoteFile.load(path)
      remaining = note_file.records.reject { |r| r == record }
      if remaining.empty?
        File.delete(path)
        return Removal.new(record: record, topic: found_topic, path: path, file_deleted: true)
      end

      rewrite!(path, remaining)
      Removal.new(record: record, topic: found_topic, path: path, file_deleted: false)
    end

    private

    # [topic, record, path] triples matching +id+ across the shelf (or one
    # topic). Ids are computed per record — no index to consult or corrupt.
    def find_by_id(id, topic)
      paths = topic ? [path_for(topic)].select { |p| File.file?(p) } : Dir[File.join(@dir, "*.yml")]
      paths.flat_map do |path|
        file = NoteFile.load(path)
        hits = file.records.select do |r|
          NoteFile.record_id(topic: file.topic, urn: r.urn, added: r.added, note: r.note) == id
        end
        hits.map { |r| [file.topic, r, path] }
      end
    end

    # Whole-file rewrite for a removal: temp + validate + atomic rename —
    # the owner's surviving records land byte-equivalent (YAML re-dump; the
    # append path's record shape), never half-written.
    def rewrite!(path, records)
      body = records.map do |r|
        YAML.dump([r.to_h.transform_keys(&:to_s).reject do |k, v|
          k == "tags" && v.empty?
        end]).delete_prefix("---\n")
      end.join("\n")
      tmp = "#{path}.tmp"
      File.write(tmp, body)
      NoteFile.load(tmp, topic: File.basename(path, ".yml"))
      File.rename(tmp, path)
    rescue NoteFile::FormatError => e
      FileUtils.rm_f(tmp)
      raise Error, "note removal failed validation: #{e.message}"
    end

    def build_record(urn, body, tags, now)
      record = { "urn" => urn, "note" => body, "added" => now.strftime("%Y-%m-%d") }
      tag_list = Array(tags).map { |tag| Normalize.nfc(tag.to_s).strip }.reject(&:empty?)
      record["tags"] = tag_list unless tag_list.empty?
      record
    end

    # The miss must be an error naming the urn — a note keyed to a typo is
    # unreachable forever — while --force records a note on a not-yet-held
    # urn deliberately (flagged dangling at render). No resolver means no
    # catalog to ask: only a deliberate --force can proceed.
    def resolve!(urn, force:)
      return if force

      if @resolver.nil?
        raise Error, "no catalog to resolve #{urn} against — run nabu sync or nabu rebuild " \
                     "(or --force to note a not-yet-held urn)"
      end
      return if @resolver.call(urn)

      raise Error, "#{urn} does not resolve in the catalog — check for a typo " \
                   "(--force records a note on a not-yet-held urn, flagged dangling at render)"
    end

    def guard_existing!(topic)
      load(topic)
    rescue NoteFile::FormatError => e
      raise Error, "cannot append to a malformed notes file — fix it first: #{e.message}"
    end

    # One YAML list item appended after the owner's untouched bytes,
    # separated by a blank line (readable, diff-friendly); then the
    # reparse-validate + rollback backstop (the LibraryShelf P20-1 rule).
    def write_record!(topic, record)
      path = path_for(topic)
      FileUtils.mkdir_p(@dir)
      prior_size = File.file?(path) ? File.size(path) : nil
      item = YAML.dump([record]).delete_prefix("---\n")
      File.write(path, prior_size.nil? ? item : "\n#{item}", mode: "a")
      revalidate!(path, prior_size)
      path
    end

    # +prior_size+ nil means the append created the file (delete it whole);
    # otherwise truncate back to the owner's untouched prior bytes.
    def revalidate!(path, prior_size)
      NoteFile.load(path)
    rescue NoteFile::FormatError => e
      prior_size.nil? ? File.delete(path) : File.truncate(path, prior_size)
      raise Error, "note append failed validation: #{e.message}"
    end

    def validate_topic!(topic)
      unless topic.to_s.match?(TOPIC_NAME)
        raise Error, "topic #{topic.inspect} must be one plain lowercase name (letters, digits, _ -)"
      end
      return unless RESERVED_TOPICS.include?(topic.to_s)

      raise Error, "topic #{topic.inspect} is reserved shelf furniture — pick another name"
    end
  end
end
