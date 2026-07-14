# frozen_string_literal: true

require "yaml"
require_relative "language_dossier"
require_relative "language_shelf"
require_relative "languages"

module Nabu
  # THE MIGRATION (P19-1): the one-shot exporter that rehomes the P18-4
  # accumulated language layer — the ledger's language_notes (seed curation +
  # the iecor/liv/edl accretions) plus, when the file still exists, the
  # retired config/languages.yml seed — into canonical/local-language/
  # dossier files. Fired by the OWNER against the live db
  # (`nabu language --export-dossiers`); after it runs, `nabu sync
  # local-language` (or rebuild) derives the catalog records and the merged
  # read serves cards from them, ledger fallback no longer consulted for the
  # exported codes.
  #
  # == The ordering doctrine
  #
  # Code ships FIRST, the export runs LATER, the ledger table drops LAST:
  #
  # 1. This packet ships the shelf + this exporter, with reads falling back
  #    to the ledger notes wherever no catalog record exists — both states
  #    are honest, nothing user-visible changes before the export.
  # 2. The owner fires the export, then the first local-language sync. The
  #    exporter is IDEMPOTENT and ABSENCE-FILLING ONLY: it never overwrites
  #    an existing front-matter lane, context prose, or section (an
  #    accretion that already landed in a dossier — the redirected writers
  #    run from merge time — is newer than the ledger row it would clobber).
  # 3. Dropping ledger_migrate/004 CANNOT ride this packet: every write path
  #    auto-migrates the ledger on open, so a drop migration would destroy
  #    the notes on the first sync BEFORE the owner ever exported. The drop
  #    is a later packet, after parity is eyeballed. (The full supersession
  #    HISTORY stays in the ledger until then — the export carries only the
  #    latest body per (code, kind), which is all the read surface ever
  #    served.)
  #
  # Per-record provenance is preserved as section headers (kind, source,
  # note date) for the programmatic lanes; the curated name/family/context
  # lanes become front matter + prose with a `provenance:` block naming the
  # export.
  class LanguageDossierExport
    CURATED_KINDS = Nabu::Languages::NOTE_KINDS

    # One export's outcome: dossier files written (created or extended),
    # files already covering everything (unchanged), and the note lanes
    # skipped because the dossier already carried a fresher section.
    Report = Data.define(:written, :unchanged, :lanes_kept)

    def initialize(ledger:, dir:, seed_path: nil, now: Time.now)
      @ledger = ledger
      @shelf = LanguageShelf.new(dir: dir)
      @seed_path = seed_path
      @now = now
    end

    # +dry_run+ computes the full report without touching the tree.
    def run!(dry_run: false)
      written = 0
      unchanged = 0
      lanes_kept = 0
      latest_notes.each do |code, lanes|
        dossier = @shelf.load(code) || LanguageDossier.new(code: code)
        merged, kept = merge(dossier, lanes)
        lanes_kept += kept
        if merged.render == dossier.render && File.file?(@shelf.path_for(code))
          unchanged += 1
        else
          @shelf.write!(merged) unless dry_run
          written += 1
        end
      end
      Report.new(written: written, unchanged: unchanged, lanes_kept: lanes_kept)
    end

    private

    # { code => { kind => { body:, source:, date: } } } — the latest note per
    # (code, kind) from the ledger (guarded: a ledger predating 004
    # contributes nothing), then the seed yml filling only the gaps (the
    # ledger is the accumulated superset of a seed that was loaded; the yml
    # covers a checkout whose ledger never seeded).
    def latest_notes
      notes = Hash.new { |hash, key| hash[key] = {} }
      ledger_notes.each { |code, kind, lane| notes[code][kind] = lane }
      seed_notes.each { |code, kind, lane| notes[code][kind] ||= lane }
      notes
    end

    def ledger_notes
      return [] unless @ledger&.table_exists?(:language_notes)

      @ledger[:language_notes].order(:id).map do |row|
        [row[:lang_code], row[:kind],
         { body: row[:body], source: row[:source], date: stamp(row[:created_at]) }]
      end
    end

    def seed_notes
      return [] unless @seed_path && File.file?(@seed_path)

      data = YAML.safe_load_file(@seed_path) || {}
      %w[languages families].flat_map do |section|
        (data[section] || {}).flat_map do |code, fields|
          CURATED_KINDS.filter_map do |kind|
            body = fields[kind].to_s.strip
            [code.to_s, kind, { body: body, source: "seed:#{File.basename(@seed_path)}", date: stamp(@now) }] \
              unless body.empty?
          end
        end
      end
    end

    # Fill absences only. Curated kinds land as front matter/prose; every
    # other kind (iecor, witness:*) lands as a provenance-headed section.
    # Returns [merged dossier, lanes kept because already present].
    def merge(dossier, lanes)
      kept = 0
      name = dossier.name
      family = dossier.family
      context = dossier.context
      sections = []
      lanes.each do |kind, lane|
        case kind
        when "name" then dossier.name ? kept += 1 : name ||= lane[:body]
        when "family" then dossier.family ? kept += 1 : family ||= lane[:body]
        when "context" then dossier.context ? kept += 1 : context ||= lane[:body]
        else
          dossier.section(kind) ? kept += 1 : sections << section_for(kind, lane)
        end
      end
      merged = LanguageDossier.new(
        code: dossier.code, name: name, family: family, context: context,
        extras: dossier.extras, sections: dossier.sections + sections,
        provenance: dossier.provenance || { "exported" => "#{stamp(@now)} (ledger language_notes + seed yml)" }
      )
      [merged, kept]
    end

    def section_for(kind, lane)
      LanguageDossier::Section.new(kind: kind, source: lane[:source], date: lane[:date], body: lane[:body])
    end

    def stamp(time)
      return time.strftime("%Y-%m-%d") if time.respond_to?(:strftime)

      time.to_s.split.first.to_s.split("T").first
    end
  end
end
