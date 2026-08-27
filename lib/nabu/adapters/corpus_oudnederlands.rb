# frozen_string_literal: true

require_relative "../manual_drop"
require_relative "../zip_reader"
require_relative "onw_tei_parser"

module Nabu
  module Adapters
    # Corpus Oudnederlands (P84-7, work-queue Q48): the Old-Dutch (odt) corpus
    # — all surviving Dutch word material 475–1200, INT/IvdNT v1.0 (2026),
    # 90 TEI works. Parser family onw-tei.
    #
    # == License — the strictest reading (owner standing rule)
    #
    # INT catalogues the corpus "Niet-commercieel (non-commercial)"; the
    # download's checkbox terms carry NO explicit redistribution grant. With
    # no such grant the owner's rule is the strictest reading: local research
    # ingest only, NEVER served to third parties, NEVER redistributed. Hence
    # license_class research_private (the freising ND posture): default-excluded
    # from the MCP surface, per-call include_restricted opt-in. And — the repo
    # being public — NO corpus bytes ever enter git: test fixtures live under
    # the gitignored local/fixtures/, and the tests skip when they are absent.
    #
    # == Acquisition — the Manual Adapter pattern (P63-1, ruling Dp-a)
    #
    # The corpus sits behind the taalmaterialen registration wall (a one-time
    # personal license acceptance), so it fails the automation bar: a human
    # acquires it in a browser and drops the archive as corpus-oudnederlands.zip
    # into incoming/corpus-oudnederlands/. `nabu sync` prints the instruction
    # card until then; on the drop it validates (a TEI member is present),
    # attics any prior holding, moves the zip into canonical/ and stamps
    # .manual-fetch.json. The ZIP itself is the canonical asset — discover/parse
    # read its members in-process (Nabu::ZipReader), so nothing is unpacked and
    # rebuild stays a pure function of canonical/. See docs/manual/
    # corpus-oudnederlands.md (the card's human companion; the suite pins it).
    class CorpusOudnederlands < Nabu::Adapter
      SLUG = "corpus-oudnederlands"
      ZIP_NAME = "corpus-oudnederlands.zip"
      XML_MEMBER = /\.xml\z/
      private_constant :XML_MEMBER

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "Corpus Oudnederlands — Old Dutch word material 475–1200 (INT/IvdNT)",
        license: "INT non-commercial (\"Niet-commercieel\"); no redistribution grant → " \
                 "strictest reading: local research ingest only, never redistributed",
        license_class: "research_private",
        upstream_url: "https://taalmaterialen.ivdnt.org/download/corpus-oudnederlands-download/",
        parser_family: "onw-tei"
      )

      def self.manifest = MANIFEST

      # No unattended upstream to probe — the download is account-gated and
      # dropped by hand (the trismegistos-geo / sabellic-loans mold): an empty
      # repo list routes the remote-health probe to the vendored/local posture.
      def self.upstream_repo_urls = []

      # The acquisition contract the instruction card renders (and the
      # docs/manual companion must echo verbatim — the guard test pins it).
      def self.manual_acquisition
        @manual_acquisition ||= ManualDrop::Spec.new(
          slug: SLUG,
          upstream_url: MANIFEST.upstream_url,
          steps: [
            "Register once at https://taalmaterialen.ivdnt.org/registreren/ and log in " \
            "(a personal identity act — never an automated agent)",
            "Open the Corpus Oudnederlands download page and CAPTURE THE LICENSE TEXT " \
            "verbatim (screenshot/copy) at the checkbox BEFORE agreeing",
            "Download the corpus archive",
            "Save it as #{ZIP_NAME} and drop it as listed below"
          ],
          files: [
            ManualDrop::FileSpec.new(
              name: ZIP_NAME,
              description: "the Corpus Oudnederlands TEI archive (research_private — never redistributed)",
              required: true, sniff: ->(path) { zip_complaint(path) }
            )
          ],
          refresh_hint: "INT deposits are versioned (hdl 10032/tm-a3-f3, v1.0) — re-acquire on a " \
                        "new version; re-acceptance of terms may be required."
        )
      end

      # incoming/<slug>/ sits beside canonical/ (ruling Dp-a); workdir is
      # canonical/<slug>, so the drop is two levels up.
      def self.drop_dir(workdir)
        File.expand_path(File.join("..", "..", "incoming", SLUG), workdir)
      end

      # The archive must be a readable ZIP carrying at least one TEI member;
      # a saved login page or a truncated download is not. One sentence.
      def self.zip_complaint(path)
        reader = Nabu::ZipReader.new(File.binread(path))
        return nil if reader.entries.any? { |e| e.name.b.match?(XML_MEMBER) }

        "no TEI .xml members — is this the Corpus Oudnederlands download?"
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

      # One ref per TEI member, id minted from the filename (act.fl..xml →
      # onw_act.fl. → urn suffix act.fl.), sorted stably. A workdir with no
      # dropped archive yields nothing (the pre-acquisition state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        zip = zip_path(workdir) or return
        reader = reader_for(zip)
        reader.entries.select { |e| e.name.b.match?(XML_MEMBER) }
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

        work = OnwTeiParser.new.work(reader.extract(entry), name: member)
        build_document(document_ref, work)
      rescue Nabu::ZipReader::Error => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def build_document(document_ref, work)
        document = Nabu::Document.new(
          urn: document_ref.id, language: "odt", canonical_path: document_ref.path,
          title: work.title, metadata: document_metadata(document_ref, work)
        )
        work.citations.each do |citation|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{citation.seq}", language: "odt",
            text: citation.text, sequence: citation.seq - 1,
            annotations: passage_annotations(citation)
          )
        end
        raise ParseError, "#{document_ref.id}: no non-empty citations" if document.empty?

        document
      end

      def document_metadata(document_ref, work)
        {
          "source_id" => work.source_id, "pid" => work.pid,
          "member" => document_ref.metadata.fetch("member"),
          "not_before" => work.not_before, "not_after" => work.not_after,
          "date_raw" => work.date_raw, "place" => work.place,
          "region" => work.region, "country" => work.country
        }.reject { |_, v| v.nil? || v == "" }
      end

      def passage_annotations(citation)
        {
          "tokens" => citation.tokens, "translation" => citation.translation,
          "context" => citation.context, "citaat_id" => citation.citaat_id
        }.reject { |k, v| v.nil? || (v.respond_to?(:empty?) && v.empty? && k != "tokens") }
      end

      # onw_<id> = the filename stem; the urn suffix is that stem verbatim.
      def member_id(name)
        File.basename(name.b, ".xml").force_encoding(Encoding::UTF_8)
      end

      def zip_path(workdir)
        direct = File.join(workdir, ZIP_NAME)
        return direct if File.file?(direct)

        Dir.glob(File.join(workdir, "*.zip")).min
      end

      # One ZipReader per archive path, shared across discover + every parse in
      # a load pass (the loader reuses one adapter instance).
      def reader_for(zip)
        (@readers ||= {})[zip] ||= Nabu::ZipReader.new(File.binread(zip))
      end
    end
  end
end
