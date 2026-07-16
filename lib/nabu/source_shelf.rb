# frozen_string_literal: true

require "fileutils"
require_relative "source_dossier"

module Nabu
  # The SANCTIONED write gateway to the canonical/local-source shelf
  # (P24-0, architecture §16) — the THIRD local-shelf gateway, beside
  # Nabu::LanguageShelf (dossiers) and Nabu::LibraryShelf (the library).
  #
  # Canonical/ is the permanent asset and application code NEVER writes it,
  # except through Adapter#fetch and the ad-hoc pipeline (CLAUDE.md ground
  # rule). A LOCAL shelf's "fetch", though, is by definition the act of
  # placing files — there is no upstream to download from — so for local
  # shelves the fetch analogue is exactly this class: the one door through
  # which programmatic accretion reaches the source-dossier files.
  # Everything else (loaders, enrichers, queries) stays read-only on the
  # shelf, and the local-source adapter's own #fetch (LocalFetch) only ever
  # SCANS.
  #
  # What rides through the door today: the `nabu ingest --shelf source`
  # scaffold and the owner-fired seed exporter
  # (`nabu list --export-source-dossiers`). The accretion contract is the
  # LanguageShelf's verbatim:
  #
  # - append-only, latest-per-(slug, kind) → one SECTION per kind, its body
  #   the latest, its header the provenance ("## witness:survey (edh-survey,
  #   DATE)");
  # - supersession = a writer replacing its OWN section (kinds are
  #   writer-owned), never someone else's section and never the owner's
  #   curated front-matter/prose lanes;
  # - idempotency = write only when the body differs, so re-syncs and
  #   rebuild replays are byte-level no-ops;
  # - a slug with no dossier yet gets a skeleton (front matter with the
  #   slug only, plus the section) — the seed exporter and the owner both
  #   merge into it later, absence-filling only.
  #
  # Returns the changed dossiers so a caller can refresh the derived
  # catalog rows incrementally (db = f(canonical), maintained at the moment
  # canonical changed instead of waiting for the next shelf re-scan).
  class SourceShelf
    # The shelf's directory name under canonical/ — also its registry slug.
    SLUG = "local-source"

    def self.dir(canonical_dir)
      File.join(canonical_dir, SLUG)
    end

    def initialize(dir:)
      @dir = dir
    end

    # Accrete +notes+ ([source_slug, kind, body] rows, or anything
    # responding to slug/kind/body) with per-record provenance +source+.
    # Writes only sections whose body differs; returns
    # { slug => SourceDossier } for the dossiers actually written.
    def accrete!(notes:, source:, now: Time.now)
      date = now.strftime("%Y-%m-%d")
      changed = {}
      normalize_notes(notes).group_by(&:first).each do |slug, rows|
        dossier = load(slug) || SourceDossier.new(slug: slug)
        rows.each do |(_slug, kind, body)|
          next if dossier.section(kind)&.body == body

          dossier = dossier.with_section(
            SourceDossier::Section.new(kind: kind, provenance: source, date: date, body: body)
          )
          changed[slug] = dossier
        end
        write!(dossier) if changed.key?(slug)
      end
      changed
    end

    # The dossier for +slug+, or nil when none exists yet. Malformed files
    # raise SourceDossier::FormatError — an accretion must never silently
    # overwrite a file it cannot faithfully re-render.
    def load(slug)
      path = path_for(slug)
      return nil unless File.file?(path)

      SourceDossier.parse(File.read(path, encoding: "UTF-8"), slug: slug)
    end

    def write!(dossier)
      FileUtils.mkdir_p(@dir)
      File.write(path_for(dossier.slug), dossier.render)
    end

    def path_for(slug)
      File.join(@dir, "#{slug}.md")
    end

    private

    def normalize_notes(notes)
      notes.map do |note|
        next note if note.is_a?(Array)

        [note.slug, note.kind, note.body]
      end
    end
  end
end
