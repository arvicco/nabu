# frozen_string_literal: true

require_relative "mw_xml_parser"
require_relative "mw_sigla"

module Nabu
  module Adapters
    # The Monier-Williams adapter (P17-4): *A Sanskrit-English Dictionary*
    # (Monier Monier-Williams, Oxford 1899) in the Cologne Digital Sanskrit
    # Lexicon (CDSL) digitization — the FOURTH dictionary-shelf occupant,
    # completing the per-language desk loop LSJ:grc :: L&S:lat :: B-T:ang ::
    # MW:san (docs/mw-survey.md is the survey of record). Same content_kind
    # :dictionary routing, same DictionaryDocument/Entry model, dictionary
    # slug mw, language san. Headwords/in-body Sanskrit are SLP1, transcoded
    # to IAST at this boundary (Nabu::Slp1 — the betacode precedent); the
    # generic §9 fold then joins MW headwords with GRETIL's IAST text, no
    # fold-rule change.
    #
    # == Upstream (verified in full, mw-survey §2)
    #
    # mwxml.zip (11.1 MB) at the CDSL 2020 download dir: xml/mw.xml (64 MB,
    # one record per line, 286,525 records / 193,890 grouped entries),
    # xml/mw.dtd, xml/mwheader.xml (the license), xml/mw-meta2.txt (coding
    # manual). Upstream is ACTIVELY CORRECTED (zip Last-Modified 2026-07,
    # DTD change comments through 06-2026) — manual re-sync, never described
    # as frozen.
    #
    # == License (mwheader.xml <availability>, quoted in full — survey §1)
    #
    # "Copyright © 2014 The Sanskrit Library and Thomas Malten" / "All
    # rights reserved other than those granted under the Creative Commons
    # Attribution Non-Commercial Share Alike license available in full at
    # //creativecommons.org/licenses/by-nc-sa/3.0/legalcode, and summarized
    # at //creativecommons.org/licenses/by-nc-sa/3.0/. Permission is granted
    # to build upon this work non-commercially, as long as credit is
    # explicitly acknowledged exactly as described herein, and derivative
    # work is distributed under the same license."
    #
    # → CC BY-NC-SA 3.0, license_class "nc" (the GRETIL class): local
    # research + index, default-excluded from the MCP surface, never
    # redistributed. Credit line: "The Sanskrit Library and Thomas Malten;
    # Cologne Digital Sanskrit Lexicon (CDSL), sanskrit-lexicon.uni-koeln.de".
    # CDSL licenses PER DICTIONARY — this verdict covers MW 1899 only. There
    # is no probe-shaped license endpoint; the grant travels inside the zip
    # (mwheader.xml), so every real refetch re-lands it in canonical and the
    # license row honestly reads unchecked between refetches (the B-T
    # stance).
    #
    # == fetch / parse
    #
    # Single-file HTTP via Nabu::FileFetch over mwxml.zip only (conditional
    # GET on Last-Modified, sha256 pin, attic + mass-deletion guard);
    # canonical keeps the 11 MB zip, and parse streams the 64 MB xml/mw.xml
    # member out of it (system unzip -p through Nabu::Shell — the ZipFetch
    # unzip dependency, no new gem). The fixture dir holds a plain trimmed
    # mw.xml, so discover accepts both shapes under ONE stable ref id.
    # mwweb1.zip (44 MB display bundle) is NOT fetched: the sigla→work
    # mapping lives as the curated MwSigla map and the full 871-row key
    # stays upstream-recoverable. sync_policy: manual, enabled: false until
    # the owner-fired first sync (~100–130 MB catalog).
    class Mw < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "mw",
        name: "Monier-Williams — A Sanskrit-English Dictionary (Cologne CDSL)",
        license: "CC BY-NC-SA 3.0 (mwheader.xml: Copyright © 2014 The Sanskrit Library and Thomas Malten; " \
                 "credit: The Sanskrit Library and Thomas Malten; Cologne Digital Sanskrit Lexicon (CDSL), " \
                 "sanskrit-lexicon.uni-koeln.de)",
        license_class: "nc",
        upstream_url: "https://www.sanskrit-lexicon.uni-koeln.de/scans/MWScan/2020/downloads/mwxml.zip",
        parser_family: "mw-xml"
      )

      ZIP_FILENAME = "mwxml.zip"
      XML_MEMBER = "xml/mw.xml"
      XML_FILENAME = "mw.xml"
      DICTIONARY_SLUG = "mw"
      LANGUAGE = "san"
      TITLE = "A Sanskrit-English Dictionary (Monier-Williams, 1899)"

      def self.manifest
        MANIFEST
      end

      # The routing declaration (architecture §11): entries, not passages —
      # SyncRunner/Rebuild load through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # The probe HEADs the zip itself: reachability + Last-Modified drift
      # vs the .file-fetch.json pin. metadata_url nil — see the license note.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: ZIP_FILENAME, zip_url: MANIFEST.upstream_url, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # One DocumentRef for the one dictionary file, under ONE stable id
      # regardless of shape: a plain mw.xml (fixtures; hand-unzipped trees)
      # wins over the zip (the real post-fetch canonical), whose ref carries
      # the member to stream. A workdir with neither yields nothing (the
      # day-one pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        ref = plain_ref(workdir) || zip_ref(workdir)
        yield ref if ref
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(
          slug: DICTIONARY_SLUG, language: LANGUAGE,
          title: TITLE, canonical_path: document_ref.path
        )
        MwXmlParser.new.entries(record_lines(document_ref)).each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "mw: #{document_ref.id}: #{e.message}"
      end

      # Download mwxml.zip via FileFetch (conditional GET, sha pin, attic +
      # guard contract). No network in tests: WebMock stubs.
      def fetch(workdir, progress: nil, force: false)
        result = Nabu::FileFetch.sync!(
          url: manifest.upstream_url, dir: workdir, filename: ZIP_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "mw fetch failed into #{workdir}: #{e.message}"
      end

      # == Per-siglum citation coverage (P17-4; mw-survey §3)
      #
      # The survey's projection as VERIFIABLE output, computed against the
      # live catalog after every sync (the CLI prints it): per-tier totals,
      # one line per held siglum with its live resolution fraction at
      # passage grain (same candidate probing Define uses — exact citation
      # then pada suffixes), authority and not-held sigla aggregated. Never
      # faked: a GRETIL document not yet synced reads "document not in
      # catalog", misses stay misses.
      def self.citation_coverage(catalog:)
        return [] unless catalog.table_exists?(:dictionary_citations)

        rows = citation_rows(catalog)
        return [] if rows.empty?

        tallies = rows.group_by { |row| MwSigla.siglum_of(row.fetch(:label)) }
        tiers = rows.group_by { |row| MwSigla.classify(row.fetch(:label)) }
        [coverage_header(rows, tiers)] + held_lines(catalog, tallies) +
          [authority_line(tiers), unheld_line(tiers)].compact
      end

      class << self
        private

        def citation_rows(catalog)
          catalog[:dictionary_citations]
            .join(:dictionary_entries, id: Sequel[:dictionary_citations][:dictionary_entry_id])
            .join(:dictionaries, id: Sequel[:dictionary_entries][:dictionary_id])
            .where(Sequel[:dictionaries][:slug] => DICTIONARY_SLUG)
            .select(Sequel[:dictionary_citations][:label], Sequel[:dictionary_citations][:cts_work],
                    Sequel[:dictionary_citations][:citation])
            .all
        end

        def coverage_header(rows, tiers)
          counts = %i[passage document authority unheld].map { |tier| (tiers[tier] || []).size }
          "mw citations: #{rows.size} — #{counts[0]} passage-grain · #{counts[1]} document-grain · " \
            "#{counts[2]} authority · #{counts[3]} not-held"
        end

        # One line per curated siglum that actually occurs, map order.
        def held_lines(catalog, tallies)
          MwSigla::WORKS.filter_map do |siglum, held|
            cited = tallies[siglum] or next
            "  #{siglum.ljust(8)} #{cited.size.to_s.rjust(6)}  #{held_detail(catalog, held, cited)}"
          end
        end

        def held_detail(catalog, held, cited)
          document_id = catalog[:documents].where(urn: held.urn, withdrawn: false).get(:id)
          return "held — document not in catalog (#{held.urn})" if document_id.nil?

          passage_grain = cited.select { |row| row.fetch(:citation) }
          return "document grain — #{held.urn}" if passage_grain.empty?

          live = resolved_count(catalog, document_id, held.urn, passage_grain)
          "#{live}/#{passage_grain.size} live at passage grain — #{held.urn}"
        end

        # The same candidate shapes Define probes: the exact citation, then
        # the pada suffixes.
        def resolved_count(catalog, document_id, urn, passage_grain)
          existing = catalog[:passages].where(document_id: document_id, withdrawn: false)
                                       .select_map(:urn).to_set
          passage_grain.count do |row|
            [row.fetch(:citation), *%w[a b c d].map { |pada| "#{row.fetch(:citation)}#{pada}" }]
              .any? { |form| existing.include?("#{urn}:#{form}") }
          end
        end

        def authority_line(tiers)
          rows = tiers[:authority] || []
          return nil if rows.empty?

          "  authority labels: #{siglum_tally(rows, limit: 6)}"
        end

        def unheld_line(tiers)
          rows = tiers[:unheld] || []
          return nil if rows.empty?

          "  not held: #{siglum_tally(rows, limit: 8)}"
        end

        def siglum_tally(rows, limit:)
          tally = rows.group_by { |row| MwSigla.siglum_of(row.fetch(:label)) }
                      .transform_values(&:size).sort_by { |siglum, count| [-count, siglum.to_s] }
          head = tally.first(limit).map { |siglum, count| "#{siglum} #{count}" }.join(" · ")
          tally.size > limit ? "#{head} … and #{tally.size - limit} more sigla" : head
        end
      end

      private

      def plain_ref(workdir)
        path = Dir.glob(File.join(workdir, "**", XML_FILENAME)).min or return nil

        document_ref(path, member: nil)
      end

      def zip_ref(workdir)
        path = Dir.glob(File.join(workdir, "**", ZIP_FILENAME)).min or return nil

        document_ref(path, member: XML_MEMBER)
      end

      def document_ref(path, member:)
        metadata = { "dictionary" => DICTIONARY_SLUG }
        metadata["member"] = member if member
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: "#{DICTIONARY_SLUG}:#{XML_FILENAME}",
          path: File.expand_path(path), metadata: metadata
        )
      end

      # The record lines: straight off the plain file, or streamed out of
      # the zip member (unzip -p via Nabu::Shell — no gem, the house rule).
      def record_lines(document_ref)
        member = document_ref.metadata["member"]
        return File.foreach(document_ref.path) if member.nil?

        Nabu::Shell.run("unzip", "-p", document_ref.path, member)
                   .force_encoding(Encoding::UTF_8).each_line
      rescue Nabu::Shell::Error => e
        raise Nabu::ParseError, "mw: cannot read #{member} from #{document_ref.path}: #{e.message}"
      end
    end
  end
end
