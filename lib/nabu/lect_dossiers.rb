# frozen_string_literal: true

require_relative "language_shelf"
require_relative "timeline"

module Nabu
  # The dossier stage section (P60 rider — the P58-6/P59-3 deferral): the
  # lect registry's stage ladder accreted into language dossiers as one
  # structured "stages" section per anchor, through the sanctioned
  # LanguageShelf gateway (writer-owned kind, body-diff idempotency — the
  # P18-4 contract verbatim).
  #
  # Registry facts ONLY ride into canonical memory: stage tags, names,
  # bands, modes (the etym/define shelves' leading asterisk for
  # reconstructed), registered varieties. Never live counts — those stay on
  # the live card (`nabu language`), where they are computed fresh; a count
  # snapshot in permanent canonical memory would only go stale.
  #
  # Scope rule: EXISTING dossiers only. An anchor without a dossier file is
  # reported skipped, never skeletonized — the registry holds 80+ anchors
  # including pure family codes (ine, gmw) that are not language dossiers;
  # a code earns its stage section when its dossier first exists (the next
  # run is idempotent and absence-filling).
  class LectDossiers
    KIND = "stages"
    SOURCE = "nabu-lects"

    Report = Data.define(:written, :unchanged, :skipped)

    def initialize(lects:, shelf:)
      @lects = lects
      @shelf = shelf
    end

    def run!(now: Time.now, dry_run: false)
      written = []
      unchanged = []
      skipped = []
      each_ladder do |code, body|
        dossier = @shelf.load(code)
        next skipped << code if dossier.nil?
        next unchanged << code if dossier.section(KIND)&.body == body

        written << code
        @shelf.accrete!(notes: [[code, KIND, body]], source: SOURCE, now: now) unless dry_run
      end
      Report.new(written: written, unchanged: unchanged, skipped: skipped)
    end

    private

    def each_ladder
      @lects.anchor_codes.each do |code|
        stages = @lects.stages_of(code)
        varieties = @lects.varieties_of(code)
        next if stages.empty? && varieties.empty?

        yield code, ladder_body(stages, varieties)
      end
    end

    def ladder_body(stages, varieties)
      lines = stages.map { |stage| stage_line(stage) }
      unless varieties.empty?
        lines << "" unless lines.empty?
        lines << "registers:"
        lines.concat(varieties.map { |variety| variety_line(variety) })
      end
      lines.join("\n")
    end

    def stage_line(stage)
      star = stage.mode == :reconstructed ? "*" : ""
      band = stage.band ? " (#{Nabu::Timeline.format_span(stage.band[0], stage.band[1])})" : ""
      "- #{star}#{stage.stage} — #{stage.name}#{band}"
    end

    # The Record name composes "<Anchor> — <Variety>" (Lects#compose_name);
    # inside the anchor's own dossier the prefix is redundant — keep the
    # variety's own title.
    def variety_line(variety)
      "- /#{variety.variety} — #{variety.name.split(' — ', 2).last}"
    end
  end
end
