# frozen_string_literal: true

require "nokogiri"

require_relative "dta_tei_parser"

module Nabu
  module Adapters
    # The Deutsches Textarchiv (P94-1): the BBAW's reference corpus of
    # German print, 5,481 TEI/P5 (DTA-Basisformat) texts spanning
    # 1473–1969 — the Kernkorpus (1,478 balanced works, 1600–1899,
    # Belletristik/Gebrauchsliteratur/Wissenschaft) plus the
    # Ergänzungstexte (newspapers, funeral sermons, the wider reach).
    # One stable public zip, CC BY-SA 4.0. A thin composition of the
    # DtaTeiParser family (page-grain, as-printed — the layer decisions
    # live on the parser's class note); the adapter owns identity, the
    # fetch, and the license doctrine.
    #
    # == Identity
    #
    # Every file's teiHeader carries <idno type="DTADirName"> — DTA's
    # own stable text id (kant_aufklaerung_1784) — peeked at discover
    # via a streamed header read (never a whole-file DOM: newspaper
    # volumes can be large). urn:nabu:dta:<dirname>. A file without the
    # idno is damage, not a rule.
    #
    # == fetch / update channel
    #
    # ZipFetch of the DATED komplett archive (606,937,636 bytes,
    # Last-Modified served — the conditional-GET change detection
    # applies). DTA cuts a new dated artifact on corpus growth; a
    # refresh is a deliberate ZIP_URL bump, reviewed like a version
    # bump. No upstream sha is published, so there is no pin — the
    # dated URL plus Last-Modified is the identity. sync_policy manual;
    # the first sync is the owner-fired gate round.
    class Dta < Nabu::Adapter
      ZIP_URL = "https://www.deutschestextarchiv.de/media/download/dta_komplett_2026-02-10.zip"

      LANGUAGE = "de"

      URN_PREFIX = "urn:nabu:dta:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "dta",
        name: "Deutsches Textarchiv (BBAW)",
        license: "CC BY-SA 4.0 (https://www.deutschestextarchiv.de/doku/nutzungsbedingungen; " \
                 "cite: Deutsches Textarchiv, Berlin-Brandenburgische Akademie der Wissenschaften)",
        license_class: "attribution",
        upstream_url: "https://www.deutschestextarchiv.de/",
        parser_family: "dta-tei"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "dta_komplett.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      # One DocumentRef per corpus XML file, id = the DTADirName idno,
      # sorted by urn. The header peek is streamed (a few KB into any
      # file) and rides no further — parse re-mines the full header in
      # its own single pass.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      def parse(document_ref)
        DtaTeiParser.new.parse(document_ref.path, urn: document_ref.id, language: LANGUAGE)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [result.not_modified ? "not modified (304)" : "komplett zip unpacked",
                 attic_notes(result.atticked)].compact.join("; ")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "dta fetch failed into #{workdir}: #{e.message}"
      end

      private

      def document_refs(workdir)
        corpus_files(workdir).map do |path|
          Nabu::DocumentRef.new(source_id: manifest.id, id: "#{URN_PREFIX}#{dirname_idno(path)}",
                                path: File.expand_path(path), metadata: {})
        end.sort_by(&:id)
      end

      # The zip layout is not assumed: any .xml under the workdir (the
      # attic excluded) is corpus shape; identity comes from the header.
      def corpus_files(workdir)
        Dir.glob(File.join(workdir, "**", "*.xml"))
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
      end

      # The streamed identity peek: walk only as far as the teiHeader's
      # end, then read the small fragment as its own document.
      def dirname_idno(path)
        fragment = header_fragment(path)
        raise ParseError, "#{path}: no <teiHeader> found" if fragment.nil?

        idno = Nokogiri::XML(fragment).remove_namespaces!
                       .at_xpath("//idno[@type='DTADirName']")&.text&.strip
        raise ParseError, "#{path}: teiHeader carries no DTADirName idno identity" if idno.nil? || idno.empty?

        idno
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML header: #{e.message}"
      end

      def header_fragment(path)
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            return node.outer_xml if node.name.split(":").last == "teiHeader" &&
                                     node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
          end
        end
        nil
      end
    end
  end
end
