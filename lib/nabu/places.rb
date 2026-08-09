# frozen_string_literal: true

require "yaml"

require_relative "pleiades"

module Nabu
  # The nabu-places read seam (P63-7): the sibling registry's matching
  # DECISIONS (source → verbatim place-name string → row), consumed
  # read-only off canonical/nabu-places (the nabu-lects consumer pattern).
  # Identity-default: an unlisted name resolves to nil — honestly unmatched,
  # never guessed. Aliases resolve one hop within their own section.
  class Places
    DIRNAME = "nabu-places"

    # One recorded decision. refs are "namespace:id" strings; status ∈
    # matched/unlocatable/region/ghost/rejected; certainty "high" unless the
    # row says otherwise; alias rows carry alias_of instead of status.
    Decision = Data.define(:refs, :status, :certainty, :note) do
      def matched? = status == "matched"
    end

    def self.load(dir)
      path = File.join(dir, "names.yml")
      return nil unless File.file?(path)

      new(YAML.safe_load_file(path) || {})
    end

    # The live registry under canonical/, or nil — the lane-off posture.
    def self.load_default(canonical_dir:)
      load(File.join(canonical_dir, DIRNAME))
    end

    def initialize(sections)
      @sections = sections
    end

    # Source slugs carrying a section.
    def sources
      @sections.keys
    end

    # The decision for (+source+, verbatim +name+), following one alias hop;
    # nil for an unlisted name (unmatched, the honest default) or an alias
    # whose target is itself absent.
    def decision(source, name)
      rows = @sections[source] or return nil
      row = rows[name] or return nil
      row = rows[row["alias_of"]] or return nil if row.key?("alias_of")
      return nil unless row.is_a?(Hash) && row["status"]

      certainty = rows[name]["certainty"] || row["certainty"] || "high"
      Decision.new(refs: Array(row["refs"]), status: row.fetch("status"),
                   certainty: certainty, note: row["note"])
    end

    # Every (verbatim name → Decision) pair of one source's section, aliases
    # resolved — the apply join's working set.
    def decisions_for(source)
      (@sections[source] || {}).keys.filter_map do |name|
        d = decision(source, name)
        [name, d] if d
      end.to_h
    end

    # The registry's OWN minted place records (places.yml, namespace np: —
    # the native lane: not only glue between gazetteers; owner ruling
    # 2026-08-09). Rows duck-type the place-index derive shape. An absent
    # or empty file is an empty lane, honestly.
    MintedPlace = Data.define(:id, :title, :lat, :lon, :place_types, :time_periods, :name_keys)

    def self.minted(dir)
      path = File.join(dir, "places.yml")
      return [] unless File.file?(path)

      (YAML.safe_load_file(path) || {}).map do |id, rec|
        MintedPlace.new(
          id: id, title: rec.fetch("name"),
          lat: rec["lat"], lon: rec["lon"],
          place_types: ["minted"], time_periods: [],
          name_keys: [Nabu::Pleiades.name_key(rec.fetch("name"))]
        )
      end
    end
  end
end
