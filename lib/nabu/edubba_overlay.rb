# frozen_string_literal: true

require "yaml"

module Nabu
  # The Edubba didactic overlay (P72-6): the school's curated hiero sign
  # pedagogy — keyword, iconic label, sound/sense gloss, certainty grade,
  # confusables, chapter, and the codex deep link — read from the synced
  # canonical/edubba-overlay snapshot and surfaced on the P65-2 hiero
  # card with Edubba's attribution line. The field set is Edubba's
  # extraction CONTRACT (their inbox note 2026-08-11): the named fields
  # are stable/additive-only; hiero-102 diverges honestly (`sense` for
  # `sound`, `chapter` for `taught_in`) and this seam folds the
  # divergence, never papers over the files.
  #
  # `certainty: unclear` is LOAD-BEARING: Edubba's rule is "NEVER present
  # as fact — carry the grade visibly", and the card renderer obeys.
  # The frequency TSVs in the same repo derive FROM Nabu and are never
  # re-imported (the circularity guard, standing since the P68 ask).
  class EdubbaOverlay
    SLUG = "edubba-overlay"
    ATTRIBUTION = "Didactic overlay: Edubba (edubba.ac) · CC BY-SA 4.0"
    SITE = "https://edubba.ac"

    POOLS = [
      { file: File.join("assets-src", "data", "hiero-101.yml"), course: "H101",
        voice: "sound", chapter: "taught_in" },
      { file: File.join("assets-src", "data", "hiero-102.yml"), course: "H102",
        voice: "sense", chapter: "chapter" }
    ].freeze
    SIGNS_DIR = File.join("site", "hieroglyphs", "addenda", "signs").freeze

    # One sign's overlay. +voice+ carries sound (H101) or sense (H102) —
    # the contract's honest divergence, labeled by +voice_kind+.
    Entry = Data.define(:code, :keyword, :label, :voice, :voice_kind, :certainty,
                        :confusables, :course, :chapter, :title, :description, :link)

    # nil when the module is not synced (feature-detect, never an error).
    def self.load_default(config: Nabu::Config.load)
      dir = config.source_workdir(SLUG)
      return nil unless POOLS.any? { |pool| File.file?(File.join(dir, pool[:file])) }

      new(dir)
    end

    def initialize(dir)
      @dir = dir
      @entries = load_pools
      merge_codex_pages
    end

    def [](code) = @entries[code.to_s.upcase]

    def size = @entries.size

    private

    def load_pools
      POOLS.each_with_object({}) do |pool, entries|
        path = File.join(@dir, pool[:file])
        next unless File.file?(path)

        ((YAML.safe_load_file(path) || {})["signs"] || []).each do |sign|
          code = sign.fetch("gardiner").to_s.upcase
          entries[code] = Entry.new(
            code: code, keyword: sign["keyword"], label: sign["label"],
            voice: sign[pool[:voice]], voice_kind: pool[:voice],
            certainty: sign["certainty"], confusables: Array(sign["confusable_with"]),
            course: pool[:course], chapter: sign[pool[:chapter]],
            title: nil, description: nil, link: nil
          )
        end
      end
    end

    # Codex sign pages: FRONT MATTER only (the contract); the body prose
    # is course material — the deep link points at it, never reprints.
    def merge_codex_pages
      Dir.glob(File.join(@dir, SIGNS_DIR, "*.md")).each do |path|
        front = front_matter(path)
        next unless front

        code = front["sign"].to_s.upcase
        next if code.empty?

        base = @entries[code] || Entry.new(
          code: code, keyword: nil, label: nil, voice: nil, voice_kind: nil,
          certainty: nil, confusables: [], course: nil, chapter: nil,
          title: nil, description: nil, link: nil
        )
        @entries[code] = base.with(
          title: front["title"], description: front["description"],
          link: front["permalink"] && "#{SITE}#{front['permalink']}"
        )
      end
    end

    def front_matter(path)
      raw = File.read(path, encoding: "UTF-8")
      match = raw.match(/\A---\n(.*?)\n---\n/m)
      match && YAML.safe_load(match[1])
    end
  end
end
