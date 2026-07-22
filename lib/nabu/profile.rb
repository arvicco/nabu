# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  # The personal focus profile (config/profile.yml, P40-f) — a plain list of
  # AXIS NAMES and/or SOURCE SLUGS naming what the owner is working on right
  # now. `nabu status`, `nabu list`, and `nabu health` scope their row set to
  # the focused sources; an absent/empty file means no profile at all (current
  # behavior everywhere).
  #
  # This class is the FILE seam only: load, the stored entry list (sorted,
  # de-duplicated), empty?, and save with a commented header. It knows nothing
  # of the registry — resolving names to axes/sources (and flagging drift) is
  # Nabu::Focus's job, which needs the registry the profile is silent about.
  #
  # The file is gitignored (personal research interest, not a publication) and
  # rides `nabu backup` for free: backup snapshots the whole config/ tree, so
  # this owner-authored, non-derivable file is already covered.
  class Profile
    # The yaml key holding the focus list.
    KEY = "focus"

    # The commented header written above the list — what the file is, that it
    # is gitignored, and how to edit it (by hand or via the focus subcommands).
    HEADER = <<~YAML
      # nabu focus profile — your personal research interest (config/profile.yml).
      #
      # A plain list of AXIS NAMES and/or SOURCE SLUGS. `nabu status`, `nabu list`,
      # and `nabu health` then show only the focused sources — your own shelves
      # always show, and --all shows everything. `nabu search` and `nabu sync --all`
      # stay library-wide on purpose (focus is a display preference, never a data
      # or freshness decision).
      #
      # Gitignored: personal, not published. Rides `nabu backup` (the config/ tree).
      # Edit by hand or via `nabu focus only|add|drop <names…>` / `nabu focus clear`.
    YAML

    # The stored entries, sorted and de-duplicated (axis names and/or source
    # slugs as strings — validation against the registry is Focus's concern).
    attr_reader :entries

    def initialize(entries)
      @entries = self.class.normalize(entries)
    end

    # Load the profile from +path+; a missing file (the common case) is the
    # empty profile, never an error. A malformed file (not a mapping, or no
    # focus list) also reads as empty — a hand-edit typo must never crash the
    # everyday status view.
    def self.load(path)
      return new([]) unless File.exist?(path)

      raw = YAML.safe_load_file(path) || {}
      list = raw.is_a?(Hash) ? raw[KEY] : nil
      new(Array(list))
    end

    # A fresh profile with +entries+ (normalized on construction). The write
    # verbs (only/add/drop) build the next profile through this.
    def self.normalize(entries)
      Array(entries).map { |name| name.to_s.strip }.reject(&:empty?).uniq.sort
    end

    def empty?
      @entries.empty?
    end

    # Persist the header + the focus list to +path+ (creating the directory if
    # needed). An empty profile writes `focus: []`, so a cleared file is still a
    # legible, self-documenting artifact rather than a bare deletion.
    def save(path)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, render)
      self
    end

    # The yaml text (header + list). Slugs and axis names are plain
    # [a-z0-9_-] tokens, so an unquoted block list is safe and readable.
    def render
      body = if @entries.empty?
               "#{KEY}: []\n"
             else
               "#{KEY}:\n#{@entries.map { |name| "  - #{name}\n" }.join}"
             end
      "#{HEADER}#{body}"
    end
  end
end
