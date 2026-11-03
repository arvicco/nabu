# frozen_string_literal: true

require_relative "dpd_txt_parser"

module Nabu
  module Adapters
    # DPD: the Digital Pāḷi Dictionary (Bodhirasa Bhikkhu and
    # contributors) — a modern Pāḷi-English dictionary of the Theravāda
    # canon and commentaries: meaning, grammar, root, construction,
    # compound analysis and the Sanskrit parallel for every headword. For
    # the held Pāḷi text (suttacentral, tipitaka-lk — 676,753 passages),
    # which had no Pāḷi dictionary shelf.
    #
    # Stored language pli (the held Pāḷi tag).
    #
    # == Upstream / grains (verified 2026-11-02)
    #
    # github.com/digitalpalidictionary/dpd-db, release v0.4.20261026
    # (2026-10-26). The release serves the same dictionary in twelve
    # formats: dpd.db.tar.xz (the 170 MB SQLite build database), the
    # GoldenDict / MDict / slob / Kindle / Kobo / Apple / Anki / PDF /
    # mobile-db reader packages, and dpd-txt.zip (4,276,639 B; one
    # dpd.txt, 22,972,952 B) — the plain-text headword export, ACCEPTED:
    # every headword with every field, no reader markup. The reader
    # packages are renderings of the same headwords (plus the inflection
    # tables the SQLite carries) and are not fetched. Fetched from the
    # stable latest-release URL (ZipFetch; the zip's one file unpacks
    # into the workdir — upstream's own tree, nothing materialized).
    #
    # Reconciliation (upstream advertises no total in the release): 89,763
    # blocks = 89,763 unique DPD ids, every head line readable. The
    # dictionary-gap survey's 142,555 counted sc-data's flattened
    # simple/en/pli2en_dpd.json rows, a different (inflection-bearing)
    # derivative, not this export.
    #
    # == License
    #
    # LICENSE, verbatim: "Digital Pāḷi Dictionary / Copyright (c) Bodhirasa
    # Bhikkhu / SPDX-License-Identifier: CC-BY-NC-SA-4.0" → license_class
    # "nc" (non-commercial; ShareAlike).
    class Dpd < Nabu::Adapter
      ZIP_URL = "https://github.com/digitalpalidictionary/dpd-db/releases/latest/download/dpd-txt.zip"
      FILENAME = "dpd.txt"
      DICTIONARY_SLUG = "dpd"
      TITLE = "Digital Pāḷi Dictionary (Bodhirasa Bhikkhu)"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dpd",
        name: "Digital Pāḷi Dictionary — dpd-db release text export",
        license: "CC BY-NC-SA 4.0 (LICENSE verbatim: \"Digital Pāḷi Dictionary / Copyright (c) Bodhirasa " \
                 "Bhikkhu / SPDX-License-Identifier: CC-BY-NC-SA-4.0\")",
        license_class: "nc",
        upstream_url: "https://github.com/digitalpalidictionary/dpd-db",
        parser_family: "dpd-txt"
      )

      def self.manifest = MANIFEST

      # Entries, not passages — SyncRunner/Rebuild load through
      # Store::DictionaryLoader (architecture §11).
      def self.content_kind = :dictionary

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "dpd-txt.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{FILENAME}", path: File.expand_path(path),
          metadata: { "dictionary" => DICTIONARY_SLUG }
        )
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: DpdTxtParser::LANGUAGE, title: TITLE, canonical_path: document_ref.path
        )
        DpdTxtParser.new.entries(document_ref.path).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "dpd: #{document_ref.id}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error => e
        raise Nabu::FetchError, "dpd fetch failed into #{workdir}: #{e.message}"
      end
    end
  end
end
