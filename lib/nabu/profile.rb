# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  # The local enablement config (config/profile.yml, promoted from the P40-f
  # focus profile at P44-r3b) — a plain list of AXIS NAMES and/or SOURCE SLUGS
  # naming the sources ENABLED on this box. The entries govern (a) what `nabu
  # sync`/`sync --all` will acquire and (b) the DEFAULT row set of every read
  # surface (list/status/health/language/axis cards and MCP nabu_status). The
  # meaning shifted from "display preference" to "the box's active set"; the
  # file KEY and vocabulary are unchanged (the existing `focus:` list, axis
  # names and slugs) so no hand-edited file breaks.
  #
  # THE DEFAULT INVERSION: an ABSENT file no longer means "everything" — it
  # means the QUICKSTART DEFAULT SET (Profile.default_entries). The CLI's
  # enablement resolution handles the one-time MIGRATION (an absent file on a
  # box that already built a library writes every synced source out, announced)
  # and the empty-state (a truly fresh box enables the quickstart-tagged rows,
  # zero for now → the honest "no sources enabled" prompt).
  #
  # This class is the FILE seam only: load, exist?, the stored entry list
  # (sorted, de-duplicated), empty?, default_entries, and save with a commented
  # header. It knows nothing of the registry beyond default_entries' read — name
  # resolution/drift is Nabu::Focus's job.
  #
  # The file is gitignored (personal research interest, not a publication) and
  # rides `nabu backup` for free: backup snapshots the whole config/ tree, so
  # this owner-authored, non-derivable file is already covered.
  class Profile
    # The yaml key holding the enablement list (kept as `focus:` from P40-f so a
    # hand-edited file survives the promotion — the vocabulary is unchanged).
    KEY = "focus"

    # The commented header written above the list — what the file is (the local
    # enablement config), that it is gitignored, and how to edit it.
    HEADER = <<~YAML
      # nabu enablement config (config/profile.yml) — the sources ENABLED on this box.
      #
      # A plain list of AXIS NAMES and/or SOURCE SLUGS. These entries govern BOTH
      # what `nabu sync` / `sync --all` acquires AND the default row set of
      # `nabu list` / `status` / `health` / the axis+language cards / MCP nabu_status
      # — your own shelves always show, and --all reveals the full registry.
      # `nabu search` / `show` / `links` / `export` stay library-wide on purpose
      # (enablement scopes acquisition + visibility, never the corpus you can read).
      #
      # An ABSENT file means the quickstart starter set, NOT everything (the P44-r3b
      # inversion). Gitignored: personal, not published. Rides `nabu backup`.
      # Edit by hand or via `nabu enable|disable <axis|source…>`.
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

    # Does the enablement config FILE exist (P44-r3b)? The migration seam needs
    # to tell an ABSENT file (→ quickstart default / one-time migration) apart
    # from a present-but-empty one (`focus: []` — the owner explicitly enabled
    # nothing), which #load alone collapses to the same empty entry list.
    def self.exist?(path)
      File.exist?(path)
    end

    # The enablement default for an ABSENT config on a fresh, library-less box
    # (P44-r3b): the registry rows tagged `quickstart: true`, recorded by slug.
    # Empty until r3c seeds the tags — so the default is the empty set today and
    # the honest "no sources enabled" empty-state shows. This is NOT a save; the
    # caller uses it only to resolve visibility/sync when no file exists yet.
    def self.default_entries(registry)
      registry.quickstart_slugs
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
