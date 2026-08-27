# frozen_string_literal: true

require_relative "../manual_drop"
require_relative "../zip_reader"
require_relative "gysseling_fromdb_parser"

module Nabu
  module Adapters
    # Corpus Gysseling (P84-7, work-queue Q48): the 13th-century originals that
    # sourced the Vroegmiddelnederlands Woordenboek — the Early Middle Dutch
    # (dum) reference corpus, ~2,228 .fromdb documents, GOLD lemma + POS. Parser
    # family gysseling-fromdb.
    #
    # == License / acquisition — identical posture to Corpus Oudnederlands
    #
    # INT non-commercial, no redistribution grant → research_private (strictest
    # reading): local research ingest only, never redistributed, default-excluded
    # from MCP, and NO corpus bytes in the public repo. Behind the taalmaterialen
    # registration wall → the Manual Adapter pattern (ruling Dp-a): the owner
    # drops corpus-gysseling.zip into incoming/corpus-gysseling/, fetch validates
    # + attics + moves it into canonical/ with .manual-fetch.json provenance, and
    # the ZIP is the canonical asset (discover/parse read members in-process via
    # Nabu::ZipReader — rebuild stays pure). The archive carries the .fromdb
    # documents plus plaats.txt / regio.txt, the place/region code tables this
    # adapter resolves at parse time. See docs/manual/corpus-gysseling.md.
    class CorpusGysseling < Nabu::Adapter
      SLUG = "corpus-gysseling"
      ZIP_NAME = "corpus-gysseling.zip"
      FROMDB_MEMBER = /\.fromdb\z/
      PLAATS_MEMBER = %r{(?:\A|/)plaats\.txt\z}
      REGIO_MEMBER = %r{(?:\A|/)regio\.txt\z}
      private_constant :FROMDB_MEMBER, :PLAATS_MEMBER, :REGIO_MEMBER

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Corpus Gysseling — 13th-c. Early Middle Dutch, lemma+POS (INT/IvdNT)",
        license: "INT non-commercial (\"Niet-commercieel\"); no redistribution grant → " \
                 "strictest reading: local research ingest only, never redistributed",
        license_class: "research_private",
        upstream_url: "https://taalmaterialen.ivdnt.org/download/tstc-corpus-gysseling/",
        parser_family: "gysseling-fromdb"
      )

      def self.manifest = MANIFEST

      def self.upstream_repo_urls = []

      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: SLUG,
          upstream_url: MANIFEST.upstream_url,
          steps: [
            "Register once at https://taalmaterialen.ivdnt.org/registreren/ and log in " \
            "(a personal identity act — never an automated agent)",
            "Open the Corpus Gysseling download page and CAPTURE THE LICENSE TEXT " \
            "verbatim (screenshot/copy) at the checkbox BEFORE agreeing",
            "Download the corpus archive (the .fromdb documents plus plaats.txt/regio.txt)",
            "Save it as #{ZIP_NAME} and drop it as listed below"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: ZIP_NAME,
              description: "the Corpus Gysseling archive (research_private — never redistributed)",
              required: true, sniff: ->(path) { zip_complaint(path) }
            )
          ],
          refresh_hint: "INT deposits are versioned — re-acquire on a new version; re-acceptance " \
                        "of terms may be required."
        )
      end

      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", SLUG), workdir)
      end

      def self.zip_complaint(path)
        reader = Nabu::ZipReader.new(File.binread(path))
        return nil if reader.entries.any? { |e| e.name.b.match?(FROMDB_MEMBER) }

        "no .fromdb members — is this the Corpus Gysseling download?"
      rescue Nabu::ZipReader::Error, SystemCallError
        "not a readable ZIP archive (a saved login/registration page?)"
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::ManualDrop.sync!(
          spec: self.class.manual_acquisition, drop_dir: self.class.drop_dir(workdir),
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "already up to date (held manual ingest)" : nil)
      end

      # One ref per .fromdb member; id = the filename stem = docId (0002B.fromdb
      # → 0002B). Sorted stably. No dropped archive → nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        zip = zip_path(workdir) or return
        reader = reader_for(zip)
        reader.entries.select { |e| e.name.b.match?(FROMDB_MEMBER) }
                      .sort_by { |e| e.name.b }
                      .each do |entry|
          id = member_id(entry.name)
          block.call(Nabu::DocumentRef.new(
                       source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}",
                       path: File.expand_path(zip), metadata: { "member" => entry.name.b.dup }
                     ))
        end
      end

      def parse(document_ref)
        reader = reader_for(document_ref.path)
        member = document_ref.metadata.fetch("member")
        entry = reader.entries.find { |e| e.name.b == member.b } or
          raise ParseError, "#{member}: member vanished between discover and parse"

        doc = parser_for(reader).document(reader.extract(entry), name: member)
        build_document(document_ref, doc)
      rescue Nabu::ZipReader::Error => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def build_document(document_ref, doc)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "dum", canonical_path: document_ref.path,
          title: title_for(doc), metadata: document_metadata(document_ref, doc)
        )
        doc.lines.each_with_index do |line, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{line.suffix}", language: "dum",
            text: line.text, sequence: index,
            annotations: { "tokens" => line.tokens, "page" => line.page, "line" => line.line }
          )
        end
        raise ParseError, "#{document_ref.id}: no non-empty lines" if document.empty?

        document
      end

      def title_for(doc)
        parts = [doc.bron_oms, doc.doc_id].compact
        parts.empty? ? nil : parts.join(" — ")
      end

      def document_metadata(document_ref, doc)
        {
          "doc_id" => doc.doc_id, "genre" => doc.genre,
          "bron_afk" => doc.bron_afk, "bron_oms" => doc.bron_oms,
          "member" => document_ref.metadata.fetch("member"),
          "not_before" => doc.not_before, "not_after" => doc.not_after, "date_raw" => doc.date_raw,
          "plaats_code" => doc.plaats_code, "regio_code" => doc.regio_code,
          "place" => doc.place, "region" => doc.region
        }.reject { |_, v| v.nil? || v == "" }
      end

      def member_id(name)
        File.basename(name.b, ".fromdb").force_encoding(Encoding::UTF_8)
      end

      def zip_path(workdir)
        direct = File.join(workdir, ZIP_NAME)
        return direct if File.file?(direct)

        Dir.glob(File.join(workdir, "*.zip")).min
      end

      def reader_for(zip)
        (@readers ||= {})[zip] ||= Nabu::ZipReader.new(File.binread(zip))
      end

      # One parser per archive, its place/region tables read from the zip once.
      def parser_for(reader)
        @parser_for ||= GysselingFromdbParser.new(
          plaats: code_table(reader, PLAATS_MEMBER), regio: code_table(reader, REGIO_MEMBER)
        )
      end

      # A TSV code table (plaats.txt / regio.txt): first column = code, second
      # = name; the header row and NULL cells are skipped. Absent member → {}
      # (place resolution then yields nil — the honest raw code still rides).
      def code_table(reader, pattern)
        entry = reader.entries.find { |e| e.name.b.match?(pattern) } or return {}

        table = {}
        GysselingFromdbParser.decode(reader.extract(entry)).each_line.with_index do |row, index|
          next if index.zero?

          code, name, = row.chomp.split("\t")
          next if code.nil? || name.nil? || name == "NULL" || name.strip.empty?

          table[code.strip] = Nabu::Normalize.nfc(name.strip)
        end
        table
      rescue Nabu::ZipReader::Error
        {}
      end
    end
  end
end
