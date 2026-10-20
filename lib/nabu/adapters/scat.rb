# frozen_string_literal: true

require "csv"
require_relative "scat_tei_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # The SCAT adapter: the St. Petersburg Corpus of Hagiographic Texts
    # (Saint Petersburg State University) — 24 Russian saints' lives
    # (žitija, with their miracle cycles and praises) of the Vologda /
    # Russian North monastic tradition, in manuscripts of the 16th–18th c.,
    # transcribed diplomatically (titla, superscript letters, ѿ ѡ ѣ ѧ
    # kept) in Unicode Cyrillic TEI with a normalized spelling per word and
    # lemma/POS/morphology on five texts.
    #
    # == Upstream and grains
    #
    # github.com/vintagentleman/scat-content. The git tree serves the
    # texts as Windows-866 ASCII-coded transliterations (raw/) and TSV
    # annotation layers (annotation/); the RELEASES serve the same 24
    # texts converted to Unicode TEI plus a .txm binary for the TXM
    # concordancer. The adapter takes the release TEI zip
    # (scat-content-120.zip, tag 1.2.0, 2021-10-24): the git tree's
    # transliteration is a legacy encoding the TEI supersedes, and the
    # .txm binary is a TXM import, never text. Inside the zip:
    #   <ID>.xml        one TEI per text — THE DOCUMENT (urn:nabu:scat:<id>)
    #   metadata.csv    the release catalog (id, title, century,
    #                   morphology, text_structure) — consumed as metadata
    #   Documentation.jsp, css/, xsl/ — the TXM portal's page, stylesheet
    #                   and XSLT furniture — skipped by rule, counted
    #
    # == Reconciliation (first real sync, 2026-10-20)
    #
    # Upstream advertises 24 texts (metadata.csv rows; the repo README's
    # text table lists the same 24). Accepted 24 documents + 0 catalog
    # rows without TEI = 24; the 5 furniture files skip by rule. Residue 0.
    #
    # == License
    #
    # CC BY-SA 4.0. The repo LICENSE is the Attribution-ShareAlike 4.0
    # International text; the README's Copyright section: "This corpus is
    # licensed under CC-BY-SA-4.0." The release zip is an asset of the
    # same repository under the same grant. Share-alike → class
    # attribution (the glaux precedent). The zip's Documentation.jsp
    # carries a "Corpus binaire TXM sous licence CC BY-NC-SA 3.0" line
    # INSIDE an HTML comment — the TXM demo-portal template's leftover,
    # commented out, not a SCAT statement; the repository grant governs.
    #
    # == Axes
    #
    # date — the catalog's century ("16"/"17"/"18" — the century column
    # beside the manuscript shelfmark in the README's table, i.e. the
    # witness's century) → a century envelope {1501, 1600}. Coarse by
    # upstream's own grain, declared. lect — chu (Russian-recension
    # Church Slavonic) via the scat-century facet rule (century → stage).
    # kind — hagiography (config/kind_map.yml source_kind). Place — the
    # release carries no origin place; the saints' Vologda/Northern
    # monasteries are the texts' SUBJECT, never claimed as the writing
    # place — unplaced, declared.
    #
    # == fetch / sync policy
    #
    # One release-asset zip over HTTPS (Nabu::ZipFetch; GitHub's 302 to
    # its object store is followed). A tagged release is frozen →
    # sync_policy manual; a new upstream release means a new pinned URL.
    class Scat < Nabu::Adapter
      ZIP_URL = "https://github.com/vintagentleman/scat-content/releases/download/1.2.0/scat-content-120.zip"
      CATALOG = "metadata.csv"
      LANGUAGE = "chu"
      FURNITURE = [/\ADocumentation\.jsp\z/, %r{\Acss/}, %r{\Axsl/}].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "scat",
        name: "SCAT — St. Petersburg Corpus of Hagiographic Texts (Saint Petersburg State University)",
        license: "CC BY-SA 4.0 (vintagentleman/scat-content LICENSE: Attribution-ShareAlike 4.0 " \
                 "International; README: \"This corpus is licensed under CC-BY-SA-4.0.\"); credit the " \
                 "St. Petersburg Corpus of Hagiographic Texts (SCAT), Saint Petersburg State University, " \
                 "release 1.2.0",
        license_class: "attribution",
        upstream_url: "https://github.com/vintagentleman/scat-content",
        parser_family: "scat-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: File.basename(ZIP_URL), zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One ref per <ID>.xml at the tree root, sorted by urn.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        catalog = catalog(workdir)
        tei_paths(workdir).map { |path| ref(path, catalog) }.sort_by(&:id).each(&block)
      end

      # Furniture files skip by rule; a catalog row whose TEI is absent is
      # unrecognized (upstream advertised a text the tree does not hold).
      def discovery_skips(workdir)
        files = Dir.glob(File.join(workdir, "**", "*"))
                   .select { |path| File.file?(path) }
                   .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
                   .map { |path| path.delete_prefix("#{workdir}/") }
        furniture = files.select { |rel| FURNITURE.any? { |rule| rule.match?(rel) } }.sort
        held = tei_paths(workdir).map { |path| File.basename(path, ".xml") }
        missing = catalog(workdir).keys.reject { |id| held.include?(id) }.sort
        notes = furniture.map { |rel| "TXM portal furniture (not text): #{rel}" } +
                missing.map { |id| "catalog row without TEI: #{id}" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: furniture.size, unrecognized: missing.size,
                                          notes: notes)
      end

      def parse(document_ref)
        xml = SourceRead.utf8_file(document_ref.path, label: "scat")
        metadata = document_ref.metadata
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: metadata["title"] || parser.title(xml, label: document_ref.path),
          metadata: metadata.except("title")
        )
        parser.pages(xml, label: document_ref.path).each do |page|
          document << passage(document_ref, page, document.size)
        end
        raise ParseError, "#{document_ref.path}: no folio side carries text" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: attic_notes(result.atticked))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "scat fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        @parser ||= ScatTeiParser.new
      end

      def tei_paths(workdir)
        Dir.glob(File.join(workdir, "*.xml"))
      end

      # {id => row} from metadata.csv ({} when absent).
      def catalog(workdir)
        path = File.join(workdir, CATALOG)
        return {} unless File.file?(path)

        text = SourceRead.utf8_file(path, label: "scat")
        CSV.parse(text, headers: true).to_h { |row| [row["id"].to_s.strip, row.to_h] }
      rescue CSV::MalformedCSVError => e
        raise Nabu::ParseError, "#{path}: malformed catalog: #{e.message}"
      end

      def ref(path, catalog)
        id = File.basename(path, ".xml")
        Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "urn:nabu:scat:#{id.downcase}",
                              path: File.expand_path(path), metadata: ref_metadata(id, catalog[id]))
      end

      def ref_metadata(id, row)
        meta = { "language" => LANGUAGE, "scat_id" => id }
        return meta if row.nil?

        century = row["century"].to_s.strip
        meta["title"] = Normalize.nfc(row["title"].to_s.strip) unless row["title"].to_s.strip.empty?
        meta["morphology"] = row["morphology"] == "true"
        meta["text_structure"] = row["text_structure"] == "true"
        if century.match?(/\A\d{1,2}\z/)
          n = Integer(century, 10)
          meta["century"] = century
          meta["date"] = { "not_before" => ((n - 1) * 100) + 1, "not_after" => n * 100,
                           "raw" => "#{n}th century (SCAT catalog)" }
        end
        meta
      end

      def passage(document_ref, page, sequence)
        annotations = { "folio" => page.folio, "tokens" => page.tokens }
        annotations["corrections"] = page.corrections unless page.corrections.empty?
        annotations["quotations"] = page.quotations unless page.quotations.empty?
        Nabu::Passage.new(urn: "#{document_ref.id}:#{page.citation}", language: LANGUAGE,
                          text: page.text, annotations: annotations, sequence: sequence)
      end
    end
  end
end
