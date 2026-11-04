# frozen_string_literal: true

require "csv"
require_relative "../file_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # wenhai — The Digital Wenhai, Version 1.1 "Phonology" (Mathieu
    # Beaudouin, University of Cambridge; Zenodo record 22817676, published
    # 2026-09-17; concept DOI 10.5281/zenodo.22256047): the Wenhai 文海
    # ("Sea of Characters"), the native rhyme dictionary of the Tangut
    # (Xi Xia) state, as 3,085 Unicode-Tangut records with the fanqie
    # (反切) spelling evidence that ties each character's initial and rhyme
    # to others. The library's first Tangut (txg) holding.
    #
    # == License (verified first-hand 2026-11-04)
    #
    # Zenodo record license field `cc-by-4.0`; the deposit's LICENSE.txt
    # verbatim: "The original data and documentation in this release are
    # licensed under the Creative Commons Attribution 4.0 International
    # Licence (CC BY 4.0)" (the accompanying build_fanqie_chains.py is MIT,
    # and not fetched). Class `attribution` (the house CC BY mapping).
    #
    # == Delivery grains (census of the v1.1 record, 2026-11-04)
    #
    # The record serves 16 files. TAKEN:
    # - 01_wenhai.csv — one row per Wenhai source position: 3,085 rows =
    #   the record's own "3,085 records" exactly; WenhaiPos unique. ONE
    #   dictionary document, one entry per row.
    # - 02b_fanqie_groups.csv — the normalized fanqie statements (1,507),
    #   each with the positions it governs: the JOIN table. A statement is
    #   written once, at its first position, and governs the run after it
    #   (01's Fanqie cell is blank on the governed rows — README §5.1);
    #   joining 02b gives every governed entry its statement and spellers.
    #   3,077 of 3,085 records are governed by exactly one statement; the
    #   8 ungoverned are 45.2 ~ 47.1 and seven mixed-tone records (M09.111,
    #   M09.112, M09.151, M09.152, M17.212, M17.221, M22.172).
    # - README.md and LICENSE.txt are fetched as the licence of record and
    #   skipped by rule (counted in discovery_skips).
    # NOT fetched (named so nobody re-scouts): the two .xlsx (spreadsheet
    # twins of the CSVs — upstream names the CSVs the preservation format);
    # 02a (method notes); 02c–02h (chain-grain graph products computed from
    # 01 + 02b by upstream's own script — every record's chain IDs already
    # ride its 01 row); build_fanqie_chains.py; CITATION.cff/.bib.
    #
    # == Entry shape
    #
    # entry_id = WenhaiPos (upstream's "principal key for returning from
    # the database to the source"), with internal whitespace removed for
    # the one span position "45.2 ~ 47.1" (→ 45.2~47.1; the verbatim
    # position rides annotations). key_raw = the Tangut cell verbatim;
    # headword = its first character — the cell is a single Unicode Tangut
    # character except for two pronunciation-split nodes (𘅇a/𘅇b, 𗼍a/𗼍b,
    # README §6.2: the suffix names a READING, kept as the `node`
    # annotation) and the one bracketed head 𗾌(𗣀) (the bracketed form
    # rides `variant`). gloss nil: v1.1 is the phonology release, the
    # Wenhai's definitions and glyph analyses are not in the deposit (the
    # monlam headword-honesty precedent). Every 01 column is mined into
    # annotations + body (rhyme system, Li Fanwen number, TYYJ initial,
    # the fanqie-derived initial/rhyme chain IDs, the Gong Hwang-cherng
    # and Beaudouin reconstructions); the governing statement's upper and
    # lower spellers become `fanqie-upper` / `fanqie-lower` crossrefs into
    # this dictionary (unreadable □ spellers mint none). Suffixed variant
    # positions (17.151*, 17.152a …) are governed through their unsuffixed
    # position (README §6.1). One GHC value is non-NFC upstream (M11.222,
    # u + U+0323) — composed at this boundary, the house rule.
    #
    # Dating: the deposit carries no dates; README §1 (citing Hamada 2024)
    # places the work as "already in existence during the second half of
    # the eleventh century", compiler and date unknown. A dictionary shelf
    # has no document timeline — the era is declared in the posture row,
    # never faked onto entries.
    #
    # == Fetch
    #
    # One FileFetch per taken file, each into its own subdirectory
    # (FileFetch dooms any sibling it did not serve — the fsv-lexica
    # layout); every body is sha256-pinned BETWEEN download and any tree
    # mutation. Zenodo files are immutable: a pin miss is corruption or a
    # new version — an owner re-pin. Nothing is materialized beside the
    # fetched files, so materialized_paths stays empty.
    class Wenhai < Nabu::Adapter
      SLUG = "wenhai"
      LANGUAGE = "txg"
      RECORD_ID = "22817676"
      RECORD_URL = "https://zenodo.org/records/#{RECORD_ID}".freeze
      FILE_BASE = "https://zenodo.org/api/records/#{RECORD_ID}/files".freeze
      RECORD_COUNT = 3_085 # the record's own count = the full 01 file's rows (2026-11-04)

      # stem (= subdirectory) => the deposit file and its sha256 pin
      # (each full download's md5 matched the record's checksum).
      FILES = {
        "01_wenhai" => { filename: "01_wenhai.csv",
                         sha256: "1f6741339bc2a6c83368a99747d3ba9d553ec69f5462d2d073477282d4dd204e" },
        "02b_fanqie_groups" => { filename: "02b_fanqie_groups.csv",
                                 sha256: "8e0a3699b65dbb8fbab7561d0c64d5528064aaba085eaed504a7c71fa8487b01" },
        "README" => { filename: "README.md",
                      sha256: "8c9556279775a2296e759db8ef42725b0f49f6b532487ce20becbdcb9f483adb" },
        "LICENSE" => { filename: "LICENSE.txt",
                       sha256: "d839a7ba2069a397a7c0af9781ccfb20ef611215e4b50089b1907abcdfa3c5b9" }
      }.freeze
      RECORDS = "01_wenhai"
      GROUPS = "02b_fanqie_groups"
      DOCS = %w[README LICENSE].freeze

      COLUMNS = %w[Cycle She Subcycle Grade ToneRhyme RhymeName WenhaiPos Tangut LiFanwen Fanqie
                   InitialTYYJ InitialClassID RhymeClassID GHC MB].freeze
      GROUP_COLUMNS = ["FanqieBase", "Fanqie", "Upper", "Lower", "Announced", "Represented",
                       "Governed positions", "Members"].freeze

      # 01 column => annotation key (blank cells are omitted).
      ANNOTATION_COLUMNS = {
        "Cycle" => "cycle", "She" => "she", "Subcycle" => "subcycle", "Grade" => "grade",
        "ToneRhyme" => "tone_rhyme", "RhymeName" => "rhyme_name", "LiFanwen" => "li_fanwen",
        "InitialTYYJ" => "initial_tyyj", "InitialClassID" => "initial_chain",
        "RhymeClassID" => "rhyme_chain", "GHC" => "ghc", "MB" => "mb"
      }.freeze

      # A suffixed position names a graphical variant of its unsuffixed one.
      VARIANT_SUFFIX = /[*a-c]\z/
      # The one bracketed head: 𗾌(𗣀).
      BRACKETED = /\A(?<head>.)\((?<variant>.+)\)\z/
      # A split node: one glyph + a reading letter (𘅇a).
      SPLIT_NODE = /\A(?<head>.)[a-z]\z/
      UNREADABLE = "□"
      BOM = "﻿"

      TITLE = "文海 Wenhai — the Tangut rhyme dictionary (The Digital Wenhai v1.1, Beaudouin 2026)"

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "The Digital Wenhai v1.1: Phonology (Beaudouin 2026) — the Tangut rhyme dictionary 文海",
        license: "CC BY 4.0 — Zenodo record #{RECORD_ID} license field \"cc-by-4.0\" (verified 2026-11-04); " \
                 "LICENSE.txt verbatim: \"The original data and documentation in this release are licensed " \
                 "under the Creative Commons Attribution 4.0 International Licence (CC BY 4.0)\"; " \
                 "credit Mathieu Beaudouin",
        license_class: "attribution",
        upstream_url: "https://doi.org/10.5281/zenodo.#{RECORD_ID}",
        parser_family: "wenhai-csv",
        credit: "Beaudouin, Mathieu. 2026. The Digital Wenhai: A Unicode-Compliant Dataset of Tangut " \
                "Linguistics and Philology's Backbone. Version 1.1: Phonology. Zenodo. " \
                "doi:10.5281/zenodo.22256047 (v1.1: 10.5281/zenodo.#{RECORD_ID})."
      )

      def self.manifest = MANIFEST

      # Entries, not passages (architecture §11).
      def self.content_kind = :dictionary

      def self.url_for(stem) = "#{FILE_BASE}/#{FILES.fetch(stem).fetch(:filename)}/content"

      # One HEAD per fetched file against its subdirectory's FileFetch state.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |stem, spec|
          Nabu::Adapter::HttpProbeTarget.new(label: spec.fetch(:filename), zip_url: url_for(stem),
                                             metadata_url: nil, state_subdir: stem,
                                             state_file: Nabu::FileFetch::STATE_FILE)
        end
      end

      # +pins+ ({stem => sha256}) exists for the WebMock'd fetch tests —
      # real syncs keep the frozen pins.
      def initialize(pins: FILES.transform_values { |spec| spec.fetch(:sha256) })
        super()
        @pins = pins
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        path = file_path(workdir, RECORDS)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{SLUG}:#{FILES.fetch(RECORDS).fetch(:filename)}",
                                    path: File.expand_path(path), metadata: { "dictionary" => SLUG })
      end

      def discovery_skips(workdir)
        present = DOCS.map { |stem| FILES.fetch(stem).fetch(:filename) if File.file?(file_path(workdir, stem)) }
                      .compact
        return Nabu::Adapter::DiscoverySkips.new if present.empty?

        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: present.size,
          notes: ["deposit documentation, not entries (skipped by rule): #{present.join(', ')}"]
        )
      end

      def parse(document_ref)
        workdir = File.dirname(document_ref.path, 2)
        governing = governing_statements(file_path(workdir, GROUPS))
        document = Nabu::DictionaryDocument.new(slug: SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        read_table(document_ref.path, COLUMNS).each { |row| document << entry(row, governing) }
        raise Nabu::ParseError, "#{document_ref.path}: no entries" if document.empty?

        document
      rescue CSV::MalformedCSVError, Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "#{SLUG}: #{document_ref.path}: #{e.message}"
      end

      # All files prepare with the live tree untouched, every pin verifies,
      # the breaker sees the combined doomed set, then all complete.
      def fetch(workdir, progress: nil, force: false)
        fetches = FILES.to_h do |stem, spec|
          [stem, Nabu::FileFetch.new(url: self.class.url_for(stem), dir: File.join(workdir, stem),
                                     filename: spec.fetch(:filename),
                                     attic_dir: File.join(workdir, ATTIC_DIRNAME, stem), progress: progress)]
        end
        fetches.each_value(&:prepare!)
        fetches.each { |stem, fetch| verify_pin!(stem, fetch) }
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.fetch(RECORDS).sha, fetched_at: Time.now,
                              notes: ["zenodo #{RECORD_ID} v1.1 sha256 pins verified",
                                      attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; "))
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def file_path(workdir, stem) = File.join(workdir, stem, FILES.fetch(stem).fetch(:filename))

      # The CSVs carry a leading BOM (README §2: "with or without a
      # byte-order mark") — dropped before the header is read.
      def read_table(path, columns)
        text = SourceRead.utf8_file(path, label: SLUG).delete_prefix(BOM)
        table = CSV.parse(text, headers: true)
        return table if table.headers == columns

        raise Nabu::ParseError, "#{path}: columns #{table.headers.inspect} ≠ the v1.1 schema"
      end

      # {governed position => statement row}. A missing 02b file is a
      # broken fetch, never a silently fanqie-less shelf.
      def governing_statements(path)
        unless File.file?(path)
          raise Nabu::ParseError, "#{SLUG}: #{path} missing — the fanqie join table is part of the fetch"
        end

        read_table(path, GROUP_COLUMNS).each_with_object({}) do |group, map|
          group["Governed positions"].to_s.split.each { |position| map[position] = group }
        end
      end

      def entry(row, governing)
        position = text(row["WenhaiPos"]) || raise(Nabu::ParseError, "#{SLUG}: a row has no WenhaiPos")
        cell = text(row["Tangut"]) || raise(Nabu::ParseError, "#{SLUG}: #{position} has no Tangut head")
        headword, extra = head(cell)
        group = governing[position] || governing[position.sub(VARIANT_SUFFIX, "")]
        annotations = annotations(row, position, extra, group)
        Nabu::DictionaryEntry.new(
          entry_id: position.gsub(/\s+/, ""), key_raw: cell, language: LANGUAGE,
          headword: headword, headword_folded: fold(headword),
          body: body(position, annotations), crossrefs: spellers(group), annotations: annotations
        )
      end

      # The headword glyph, plus the cell's node/variant claim.
      def head(cell)
        if (m = cell.match(BRACKETED))
          [m[:head], { "variant" => m[:variant] }]
        elsif (m = cell.match(SPLIT_NODE))
          [m[:head], { "node" => cell }]
        else
          [cell, {}]
        end
      end

      def annotations(row, position, extra, group)
        stated = text(row["Fanqie"])
        fanqie = group && {
          "fanqie" => text(group["Fanqie"]), "fanqie_base" => text(group["FanqieBase"]),
          "fanqie_stated" => (true if stated),
          "upper_speller" => readable(group["Upper"]), "lower_speller" => readable(group["Lower"])
        }
        ANNOTATION_COLUMNS.to_h { |column, key| [key, text(row[column])] }
                          .merge("position" => position, **extra)
                          .merge("fanqie" => stated, **(fanqie || {}))
                          .compact
      end

      def body(position, ann)
        lines = ["Wenhai #{position} — #{rhyme_line(ann)}"]
        if ann["fanqie"]
          where = ann["fanqie_stated"] ? "" : " (stated at #{ann['fanqie_base']})"
          spellers = [("upper speller #{ann['upper_speller']}" if ann["upper_speller"]),
                      ("lower speller #{ann['lower_speller']}" if ann["lower_speller"])].compact
          lines << "fanqie #{ann['fanqie']}#{where}#{" — #{spellers.join(', ')}" unless spellers.empty?}"
        end
        lines << chain_line(ann)
        lines << "Gong Hwang-cherng #{ann['ghc']} · Beaudouin #{ann['mb']}"
        lines << "Li Fanwen #{ann['li_fanwen']}"
        Normalize.nfc(lines.compact.join("\n"))
      end

      def rhyme_line(ann)
        system = [("#{ann['cycle']} cycle" if ann["cycle"]), ("She #{ann['she']}" if ann["she"]),
                  ("subcycle #{ann['subcycle']}" if ann["subcycle"]), ("grade #{ann['grade']}" if ann["grade"])].compact
        tone = "ToneRhyme #{ann['tone_rhyme']}"
        rhyme = ann["rhyme_name"] ? "rhyme #{ann['rhyme_name']} (#{tone})" : tone
        system.empty? ? rhyme : "#{rhyme}; #{system.join(', ')}"
      end

      def chain_line(ann)
        initial = ann["initial_chain"] ? "initial chain #{ann['initial_chain']}" : "initial chain unresolved"
        rhyme = ann["rhyme_chain"] ? "rhyme chain #{ann['rhyme_chain']}" : "rhyme chain unresolved"
        "#{initial} (TYYJ #{ann['initial_tyyj']}) · #{rhyme}"
      end

      def spellers(group)
        return [] unless group

        { "fanqie-upper" => group["Upper"], "fanqie-lower" => group["Lower"] }.filter_map do |kind, value|
          node = readable(value)
          next unless node

          target = node.match(SPLIT_NODE)&.[](:head) || node
          Nabu::DictionaryCrossref.new(kind: kind, label: node, target: target, target_folded: fold(target))
        end
      end

      def readable(value)
        node = text(value)
        node && !node.include?(UNREADABLE) ? node : nil
      end

      def fold(value)
        folded = Normalize.search_form(value, language: LANGUAGE)
        folded.strip.empty? ? value : folded
      end

      def text(value)
        stripped = Normalize.nfc(value.to_s).strip
        stripped.empty? ? nil : stripped
      end

      def verify_pin!(stem, fetch)
        pin = @pins.fetch(stem)
        return if fetch.not_modified? || fetch.sha == pin

        raise Nabu::FetchError,
              "#{SLUG}: #{FILES.fetch(stem).fetch(:filename)} misses the v1.1 sha256 pin (expected #{pin}, " \
              "got #{fetch.sha}) — Zenodo files are immutable, so this is corruption or a new version; " \
              "read #{RECORD_URL} and re-pin FILES"
      end
    end
  end
end
