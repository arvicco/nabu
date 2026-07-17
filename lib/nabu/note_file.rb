# frozen_string_literal: true

require "date"
require "yaml"
require_relative "normalize"

module Nabu
  # One local-notes topic file, canonical/local-notes/<topic>.yml (P24-1,
  # architecture §16) — the owner's annotation lane over ANY urn the corpus
  # knows: scholia-of-one's-own, keyed by document, passage, range or
  # dictionary-entry urn. The on-disk shape is a YAML LIST of note records
  # (`urn` / `note` / `added` / optional `tags`) so the NoteShelf gateway can
  # append one mechanically without rewriting the file — the LibraryManifest
  # precedent, and the same honesty contract: the owner may hand-edit, so
  # parse validates every record and names defects file+entry.
  class NoteFile
    # A malformed notes file (unparseable YAML, wrong shape, bad record).
    # The adapter quarantines the FILE; the gateway refuses to append into
    # one (an append into a broken record would only deepen the damage).
    class FormatError < Nabu::Error; end

    # One note. +urn+ is any urn shape ("urn:…" — resolution against the
    # catalog is the GATEWAY's job, not the parser's; a --force note on a
    # not-yet-held urn is legitimate and reads dangling at render); +note+
    # is NFC prose; +added+ an ISO date string; +tags+ an Array of Strings
    # (possibly empty).
    Record = Data.define(:urn, :note, :added, :tags)

    ADDED_SHAPE = /\A\d{4}-\d{2}-\d{2}\z/

    # A note's stable id: 8 hex chars of the digest over its identity
    # (topic + urn + added + text). COMPUTED, never stored — so hand-added
    # records have ids automatically, file edits never renumber neighbors,
    # and every surface (--list, the bare-urn read-back, --rm) derives the
    # same id from the same content.
    def self.record_id(topic:, urn:, added:, note:)
      require "digest"
      Digest::SHA256.hexdigest("#{topic}\n#{urn}\n#{added}\n#{note}")[0, 8]
    end

    # Parse the notes file at +path+; the topic is the file stem. Raises
    # FormatError on any structural or per-record defect, naming the file
    # and the offending entry.
    def self.load(path, topic: File.basename(path, ".yml"))
      data = YAML.safe_load_file(path, permitted_classes: [Date])
      raise FormatError, "#{path}: notes file must be a YAML list of note records, got #{data.class}" \
        unless data.is_a?(Array)
      raise FormatError, "#{path}: lists no notes" if data.empty?

      new(topic: topic, records: data.each_with_index.map { |item, index| build_record(path, item, index) })
    rescue Psych::Exception => e
      raise FormatError, "#{path}: unparseable YAML (#{e.message})"
    end

    def self.build_record(path, item, index)
      raise FormatError, "#{path}: entry #{index + 1} must be a mapping, got #{item.class}" unless item.is_a?(Hash)

      Record.new(
        urn: urn!(path, item, index),
        note: note!(path, item, index),
        added: added!(path, item, index),
        tags: tags!(path, item, index)
      )
    end
    private_class_method :build_record

    # Any urn shape is welcome — the corpus mints urn:cts:… and urn:nabu:…
    # alike — but a value that is not even urn-shaped is a hand-edit defect,
    # named here rather than sitting forever unresolvable.
    def self.urn!(path, item, index)
      urn = item["urn"]
      return Normalize.nfc(urn.strip) if urn.is_a?(String) && urn.strip.start_with?("urn:")

      raise FormatError, "#{path}: entry #{index + 1} needs a `urn:` the corpus can know (urn:…), " \
                         "got #{urn.inspect}"
    end
    private_class_method :urn!

    def self.note!(path, item, index)
      note = item["note"]
      unless note.is_a?(String) && !note.strip.empty?
        raise FormatError, "#{path}: entry #{index + 1} (#{item['urn']}): note must be non-empty prose, " \
                           "got #{note.inspect}"
      end

      Normalize.nfc(note.strip)
    end
    private_class_method :note!

    # The gateway stamps ISO dates; hand-edited bare YAML dates arrive as
    # Date objects — both normalize to the ISO string. Anything else is a
    # named defect.
    def self.added!(path, item, index)
      added = item["added"]
      return added.iso8601 if added.is_a?(Date)
      return added if added.is_a?(String) && added.match?(ADDED_SHAPE)

      raise FormatError, "#{path}: entry #{index + 1} (#{item['urn']}): added must be a date (YYYY-MM-DD), " \
                         "got #{added.inspect}"
    end
    private_class_method :added!

    def self.tags!(path, item, index)
      tags = item.fetch("tags", [])
      unless tags.is_a?(Array) && tags.all? { |tag| tag.is_a?(String) && !tag.strip.empty? }
        raise FormatError, "#{path}: entry #{index + 1} (#{item['urn']}): tags must be a list of Strings, " \
                           "got #{tags.inspect}"
      end

      tags.map { |tag| Normalize.nfc(tag.strip) }
    end
    private_class_method :tags!

    attr_reader :topic, :records

    def initialize(topic:, records:)
      @topic = topic
      @records = records
    end
  end
end
