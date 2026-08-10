# frozen_string_literal: true

require "yaml"
require "fileutils"

module Nabu
  # config/lect_rulings.yml — the DURABLE home of per-document owner lect
  # rulings (P70, the derivability contract). The config file is the source
  # of truth; the journal row (db/lects.sqlite3) is its DERIVED
  # representation: `nabu lect assign` writes HERE first and mirrors into
  # the journal, and `nabu rebuild` re-derives the whole journal from this
  # file + the compiled rules + infer-dates — so db/ holds no ruling the
  # two-folder backup (canonical/ + config/) cannot restore.
  #
  # Only OWNER-basis rulings live here: rule:<id> rows are compiled
  # derivations and never enter config.
  module LectRulings
    HEADER = <<~YAML
      # config/lect_rulings.yml — per-document lect rulings (the owner
      # overlay tier; P70 derivability contract).
      #
      # THE source of truth for hand rulings: `nabu lect assign` appends
      # here and mirrors into the derived journal (db/lects.sqlite3);
      # `nabu rebuild` re-derives the journal from this file + the
      # compiled rules + infer-dates. Every entry is an owner decision:
      #   - urn:  urn:nabu:…          # the document
      #     code: sux                 # the stored bare code refined
      #     lect: sux:post            # the ruling
      #     note: "why"               # optional
      #     at:   2026-08-10          # ruling date
      rulings: []
    YAML

    module_function

    def load(path)
      return [] unless File.file?(path)

      (YAML.safe_load_file(path) || {}).fetch("rulings", nil) || []
    end

    # Append (or replace the same (urn, code)) ruling — the write-through
    # front half of `lect assign`. Creates the file with its doctrinal
    # header on first use.
    def append!(path, urn:, code:, lect_id:, note: nil, at: Time.now)
      rulings = load(path).reject { |r| r["urn"] == urn && r["code"] == code }
      entry = { "urn" => urn, "code" => code, "lect" => lect_id }
      entry["note"] = note if note && !note.to_s.strip.empty?
      entry["at"] = at.strftime("%Y-%m-%d")
      write!(path, rulings + [entry])
      entry
    end

    # Remove rulings for +urn+ (all codes, or one) — the withdraw mirror.
    # Returns the count removed.
    def remove!(path, urn:, code: nil)
      rulings = load(path)
      kept = rulings.reject { |r| r["urn"] == urn && (code.nil? || r["code"] == code) }
      write!(path, kept) if kept.size != rulings.size
      rulings.size - kept.size
    end

    # Replay every config ruling into +journal+ (basis "owner") — the
    # rebuild re-derivation's first stage. Returns the count applied.
    def apply!(path, journal:)
      load(path).each do |r|
        Store::LectJournal.assign!(journal, urn: r.fetch("urn"), code: r.fetch("code"),
                                            lect_id: r.fetch("lect"), basis: "owner",
                                            note: r["note"])
      end.size
    end

    def write!(path, rulings)
      FileUtils.mkdir_p(File.dirname(path))
      body = rulings.empty? ? HEADER : HEADER.sub("rulings: []", YAML.dump("rulings" => rulings).sub(/\A---\n/, ""))
      File.write(path, body)
    end
  end
end
