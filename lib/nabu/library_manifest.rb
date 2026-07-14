# frozen_string_literal: true

require "yaml"

module Nabu
  # One local-library collection's manifest.yml (P19-4, architecture §16;
  # design: canonical-memory §2) — THE SOURCE OF RECORD for the shelf. A
  # file present but unmanifested is unrecognized (discovery census);
  # manifested but missing is the LocalFetch vanished/attic story. The
  # on-disk shape is a YAML LIST of entry maps so `nabu ingest` (the next
  # packet) can append one entry mechanically without rewriting the file.
  #
  # == The license default, enforced here
  #
  # Acquired scholarly PDFs are mostly copyrighted, so the shelf DEFAULTS
  # every entry to license_class "research_private" (MCP-excluded, never
  # served externally, never redistributed). An entry may claim another
  # class explicitly — an owner decision, honored — but silence always
  # means the conservative class, and the default is applied HERE, in one
  # place, not scattered through adapters.
  class LibraryManifest
    FILENAME = "manifest.yml"
    DEFAULT_LICENSE_CLASS = "research_private"

    # A malformed manifest (unparseable YAML, wrong shape, bad field). The
    # adapter reports the COLLECTION as unrecognized in the discovery
    # census rather than quarantining per-file — the manifest is the
    # record, and a broken record means nothing in the collection can be
    # trusted as catalogued.
    class FormatError < Nabu::Error; end

    # One catalogued item. +file+ is the path relative to the collection
    # dir; +license_class+ is always a valid class (the default applied);
    # +languages+/+tags+/+related+ are Arrays of Strings (possibly empty);
    # +year+ is an Integer or nil; +title+ defaults to the file stem.
    Entry = Data.define(:file, :title, :creator, :year, :languages,
                        :provenance, :license_class, :tags, :related)

    # Parse the manifest at +path+. Raises FormatError on any structural or
    # per-entry defect, naming the file and the offending entry.
    def self.load(path)
      data = YAML.safe_load_file(path)
      raise FormatError, "#{path}: manifest must be a YAML list of entries, got #{data.class}" unless data.is_a?(Array)
      raise FormatError, "#{path}: manifest lists no entries" if data.empty?

      entries = data.each_with_index.map { |item, index| build_entry(path, item, index) }
      duplicate = entries.map(&:file).tally.find { |_file, count| count > 1 }
      raise FormatError, "#{path}: duplicate entry for file #{duplicate.first.inspect}" if duplicate

      new(entries)
    rescue Psych::Exception => e
      raise FormatError, "#{path}: unparseable YAML (#{e.message})"
    end

    def self.build_entry(path, item, index)
      raise FormatError, "#{path}: entry #{index + 1} must be a mapping, got #{item.class}" unless item.is_a?(Hash)

      Entry.new(
        file: file!(path, item, index),
        title: string_or_nil!(path, item, index, "title") || File.basename(item["file"], ".*"),
        creator: string_or_nil!(path, item, index, "creator"),
        year: year!(path, item, index),
        languages: string_list!(path, item, index, "languages"),
        provenance: string_or_nil!(path, item, index, "provenance"),
        license_class: license_class!(path, item, index),
        tags: string_list!(path, item, index, "tags"),
        related: string_list!(path, item, index, "related")
      )
    end
    private_class_method :build_entry

    def self.file!(path, item, index)
      file = item["file"]
      unless file.is_a?(String) && !file.strip.empty?
        raise FormatError, "#{path}: entry #{index + 1} needs a `file:` (relative path), got #{file.inspect}"
      end
      if file.start_with?("/") || file.split("/").include?("..")
        raise FormatError, "#{path}: entry #{index + 1}: file must stay inside the collection, got #{file.inspect}"
      end

      file
    end
    private_class_method :file!

    # The default lives here: absent → research_private; present → must be
    # a known class (a typo'd class must fail loudly, never default-down
    # silently to a more permissive reading).
    def self.license_class!(path, item, index)
      value = item.fetch("license_class", DEFAULT_LICENSE_CLASS)
      return value if Model::Validation::LICENSE_CLASSES.include?(value)

      raise FormatError, "#{path}: entry #{index + 1} (#{item['file']}): license_class must be one of " \
                         "#{Model::Validation::LICENSE_CLASSES.join(', ')}, got #{value.inspect}"
    end
    private_class_method :license_class!

    def self.year!(path, item, index)
      year = item.fetch("year", nil)
      return year if year.nil? || year.is_a?(Integer)

      raise FormatError, "#{path}: entry #{index + 1} (#{item['file']}): year must be an Integer, got #{year.inspect}"
    end
    private_class_method :year!

    def self.string_or_nil!(path, item, index, key)
      value = item.fetch(key, nil)
      return value if value.nil? || (value.is_a?(String) && !value.strip.empty?)

      raise FormatError, "#{path}: entry #{index + 1} (#{item['file']}): #{key} must be a String, got #{value.inspect}"
    end
    private_class_method :string_or_nil!

    def self.string_list!(path, item, index, key)
      value = item.fetch(key, [])
      unless value.is_a?(Array) && value.all? { |element| element.is_a?(String) && !element.strip.empty? }
        raise FormatError, "#{path}: entry #{index + 1} (#{item['file']}): #{key} must be a list of Strings, " \
                           "got #{value.inspect}"
      end

      value
    end
    private_class_method :string_list!

    attr_reader :entries

    def initialize(entries)
      @entries = entries
    end
  end
end
