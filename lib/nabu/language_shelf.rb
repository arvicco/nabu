# frozen_string_literal: true

require "fileutils"
require_relative "language_dossier"

module Nabu
  # The SANCTIONED write gateway to the canonical/local-language shelf
  # (P19-1, architecture §16) — and the doctrine that makes it legitimate:
  #
  # Canonical/ is the permanent asset and application code NEVER writes it,
  # except through Adapter#fetch and the ad-hoc pipeline (CLAUDE.md ground
  # rule). A LOCAL shelf's "fetch", though, is by definition the act of
  # placing files — there is no upstream to download from — so for local
  # shelves the fetch analogue is exactly this class: the one door through
  # which programmatic accretion reaches the dossier files. Everything else
  # (loaders, enrichers, queries) stays read-only on the shelf, and the
  # local-language adapter's own #fetch (LocalFetch) only ever SCANS.
  #
  # What rides through the door today: the two P18-5/6 accretion writers,
  # redirected here from the retiring ledger language_notes —
  # Store::DictionaryLoader's document-grain notes (IE-CoR's languages.csv
  # metadata, source "iecor") and adapter-grain riders (LIV/EDL stage
  # witnesses, kind "witness:<slug>"). The P18-4 contract maps verbatim:
  #
  # - append-only, latest-per-(code, kind) → one SECTION per kind, its body
  #   the latest, its header the provenance ("## witness:liv (liv, DATE)");
  # - supersession = a writer replacing its OWN section (kinds are
  #   writer-owned), never someone else's section and never the owner's
  #   curated front-matter/prose lanes;
  # - idempotency = write only when the body differs, so re-syncs and
  #   rebuild replays are byte-level no-ops (a rebuild replaying IE-CoR
  #   re-derives the same section and touches nothing);
  # - a code with no dossier yet gets a skeleton (front matter with the code
  #   only, plus the section) — the migration exporter and the owner both
  #   merge into it later, absence-filling only.
  #
  # Returns the changed dossiers so the caller can refresh the derived
  # catalog rows incrementally (db = f(canonical), maintained at the moment
  # canonical changed instead of waiting for the next shelf re-scan).
  class LanguageShelf
    # The shelf's directory name under canonical/ — also its registry slug.
    SLUG = "local-language"

    def self.dir(canonical_dir)
      File.join(canonical_dir, SLUG)
    end

    def initialize(dir:)
      @dir = dir
    end

    # Accrete +notes+ ([lang_code, kind, body] rows, or anything responding
    # to lang_code/kind/body like Nabu::DictionaryLanguageNote) with
    # per-record provenance +source+. Writes only sections whose body
    # differs; returns { code => LanguageDossier } for the dossiers actually
    # written.
    def accrete!(notes:, source:, now: Time.now)
      date = now.strftime("%Y-%m-%d")
      changed = {}
      normalize_notes(notes).group_by(&:first).each do |code, rows|
        dossier = load(code) || LanguageDossier.new(code: code)
        rows.each do |(_code, kind, body)|
          next if dossier.section(kind)&.body == body

          dossier = dossier.with_section(
            LanguageDossier::Section.new(kind: kind, source: source, date: date, body: body)
          )
          changed[code] = dossier
        end
        write!(dossier) if changed.key?(code)
      end
      changed
    end

    # The dossier for +code+, or nil when none exists yet. Malformed files
    # raise LanguageDossier::FormatError — an accretion must never silently
    # overwrite a file it cannot faithfully re-render.
    def load(code)
      path = path_for(code)
      return nil unless File.file?(path)

      LanguageDossier.parse(File.read(path, encoding: "UTF-8"), code: code)
    end

    def write!(dossier)
      FileUtils.mkdir_p(@dir)
      File.write(path_for(dossier.code), dossier.render)
    end

    def path_for(code)
      File.join(@dir, "#{code}.md")
    end

    private

    def normalize_notes(notes)
      notes.map do |note|
        next note if note.is_a?(Array)

        [note.lang_code, note.kind, note.body]
      end
    end
  end
end
