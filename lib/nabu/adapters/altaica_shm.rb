# frozen_string_literal: true

require "digest"
require "fileutils"
require_relative "../shell"
require_relative "../url_download"

module Nabu
  module Adapters
    # altaica-shm — Street's Text of the Secret History of the Mongols
    # (P107-7, Q99): the romanized Middle Mongol SHM, Version 24
    # (2013), hosted by Monumenta Altaica (altaica.ru). USE GRANTED by
    # the site's maintainer by email, 2026-09-27 — the grant notes the
    # late Prof. Street "always wanted free propagation of his works";
    # his copyright line rides every surface verbatim.
    #
    # == Shape (the PDF's text layer, census 2026-09-28)
    #
    # One line per Street line number (4 digits, 1010–9492; 3,419 clean
    # + 104 with the footnote pointer GLUED to the number — split_line
    # owns that rule). "(§N)" section markers move to annotations.
    # Street's OWN ASCII substitutions (front matter, verbatim: 6 = ŋ
    # (Alt+252), @ / + / ^ / " for special letters) are served AS-IS —
    # the substitution note rides metadata, never a silent re-decode.
    # The trailing apparatus section ("114. C Y435 …") is censused out
    # of passages. The Kozin transcription page is a JS shell today —
    # recorded residue, not fetched.
    class AltaicaShm < Nabu::Adapter
      PDF_URL = "http://altaica.ru/SECRET/SH-24UP.pdf"
      PDF_NAME = "SH-24UP.pdf"
      URN = "urn:nabu:altaica-shm:shm"
      LANGUAGE = "xng"
      # 4-digit Street line + optional glued footnote digits.
      LINE = /\A(\d{4})(\d{0,3})\s+(.*)\z/
      SECTION = /\A\(§(\d+)\)\s*/
      APPARATUS = /\A\d{1,3}\.\s/

      MANIFEST = Nabu::SourceManifest.new(
        id: "altaica-shm",
        name: "Street's Text of the Secret History of the Mongols (Monumenta Altaica)",
        license: "Use granted by the Monumenta Altaica maintainer (by email, 2026-09-27): " \
                 "\"Yes, you can use it. I'm pretty sure that the late prof. Street wouldn't " \
                 "mind. He always wanted free propagation of his works.\" Street's own notice " \
                 "carried verbatim: \"Copyright John C. Street 1985-2013\". Credit Monumenta " \
                 "Altaica (altaica.ru) as the source",
        license_class: "attribution",
        upstream_url: "http://altaica.ru/e_SecretH.php",
        parser_family: "altaica-shm-pdf"
      )

      def self.manifest = MANIFEST

      # +extract+ is the text-layer seam (a callable path → the raw
      # mutool text), injectable so the suite never depends on mutool
      # being installed (the local-library law): tests run against the
      # RECORDED extraction, and a guarded live test exercises real
      # mutool when present.
      def initialize(extract: nil)
        super()
        @extract = extract || method(:mutool_text)
      end

      # UrlDownload keeps no state file — the probe HEADs the stable
      # upstream URL for liveness only; drift honestly reads unknown.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "pdf", zip_url: PDF_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The glued-footnote rule, exposed for the unit pin: "10951 text"
      # → ["1095", "1", "text"].
      def self.split_line(raw)
        match = LINE.match(raw) or return nil
        [match[1], match[2].empty? ? nil : match[2], match[3].strip]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, PDF_NAME)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: URN, path: path, metadata: {})
      end

      def parse(document_ref)
        lines = text_lines(document_ref.path)
        document = Nabu::Document.new(
          urn: URN, language: LANGUAGE, canonical_path: document_ref.path,
          title: "Mongqol-un niuca tobcaan — Street's text, v24",
          metadata: metadata_for(lines)
        )
        section = nil
        lines.each do |raw|
          parts = self.class.split_line(raw) or next
          number, footnote, text = parts
          if (match = SECTION.match(text))
            section = match[1]
            text = text.sub(SECTION, "").strip
          end
          next if text.empty?

          annotations = {}
          annotations["section"] = section if section
          annotations["fn"] = footnote if footnote
          document << Nabu::Passage.new(
            urn: unique_urn(document, "#{URN}:l#{number}"), language: LANGUAGE,
            text: Normalize.nfc(text), sequence: document.passages.size + 1,
            annotations: annotations
          )
        end
        raise Nabu::ParseError, "#{document_ref.path}: no Street lines parsed — text layer gone?" if
          document.passages.empty?

        document
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        downloaded = Nabu::UrlDownload.new.fetch(PDF_URL, dir: workdir)
        target = File.join(workdir, PDF_NAME)
        FileUtils.mv(downloaded, target) unless downloaded == target
        Nabu::FetchReport.new(sha: Digest::SHA256.file(target).hexdigest, fetched_at: Time.now,
                              notes: ["#{PDF_NAME} (#{File.size(target)} bytes; Kozin page = " \
                                      "JS shell, recorded residue)"])
      end

      private

      # Street repeats a handful of line numbers (and a glued footnote
      # split can shadow a real line) — collisions take the house b2.
      def unique_urn(document, candidate)
        return candidate if document.passages.none? { |p| p.urn == candidate }

        suffix = 2
        suffix += 1 while document.passages.any? { |p| p.urn == "#{candidate}b#{suffix}" }
        "#{candidate}b#{suffix}"
      end

      def text_lines(path)
        @extract.call(path).split("\n").map(&:rstrip)
      end

      # The PDF's text layer via mutool (the house shell boundary).
      def mutool_text(path)
        Nabu::Shell.run("mutool", "draw", "-F", "txt", "-o", "-", path)
      rescue Nabu::Error => e
        raise Nabu::ParseError, "#{path}: mutool text extraction failed — #{e.message}"
      end

      def metadata_for(lines)
        front = lines.take_while { |l| !LINE.match?(l) }
        copyright = front.find { |l| l.include?("Copyright John C. Street") }.to_s.strip
        note = front.find { |l| l.include?("Alt+252") }.to_s.strip
        apparatus = lines.count { |l| APPARATUS.match?(l) }
        meta = { "edition" => "Street v24 (10 October 2013)" }
        meta["copyright"] = copyright unless copyright.empty?
        meta["encoding_note"] = note unless note.empty?
        meta["apparatus_lines_censused"] = apparatus if apparatus.positive?
        meta
      end
    end
  end
end
