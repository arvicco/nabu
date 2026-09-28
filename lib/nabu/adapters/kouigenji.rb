# frozen_string_literal: true

require "digest"
require "fileutils"
require "nokogiri"
require_relative "../url_download"

module Nabu
  module Adapters
    # kouigenji — the 校異源氏物語テキストDB (P108-3, Q89.2;
    # kouigenjimonogatari.github.io — the デジタル源氏物語 project,
    # Nakamura/Nagasaki et al., repo license CC BY 4.0): Ikeda Kikan's
    # 1942 critical edition of Genji Monogatari, all 54 maki as one TEI
    # file each.
    #
    # == Shape (fixture-verified 2026-09-29)
    #
    # body > p > `seg` per MANUSCRIPT LINE, each seg's `corresp` API id
    # (…/items/0005-01.json) carrying the page.line citation → passage
    # urn :p5.l1. `<pb n= facs=>` breaks carry NDL IIIF page images —
    # the facs rides the page's first line as an annotation. Waka are
    # `<lg type="waka" xml:id="waka-NNN">` with five `<l n>` lines
    # NESTED INSIDE their seg: the passage text keeps the manuscript
    # line verbatim (the poem is inline in the line), and the waka
    # surfaces as annotations (id + the l-lines joined with ／).
    #
    # Language jpn; the lect posture claims the Heian stage (jpn:emj)
    # pending its registry mint.
    class Kouigenji < Nabu::Adapter
      BASE_URL = "https://raw.githubusercontent.com/kouigenjimonogatari/" \
                 "kouigenjimonogatari.github.io/master/xml/master"
      # Genji's 54 maki — stable by the work itself; upstream serves
      # 01.xml … 54.xml.
      MAKI = (1..54).map { |n| format("%02d", n) }.freeze
      URN_PREFIX = "urn:nabu:kouigenji:"
      LANGUAGE = "jpn"
      TEI_NS = { "tei" => "http://www.tei-c.org/ns/1.0" }.freeze
      CORRESP_ID = %r{items/0*(\d+)-0*(\d+)\.json}

      MANIFEST = Nabu::SourceManifest.new(
        id: "kouigenji",
        name: "校異源氏物語テキストDB — Ikeda's critical Genji, TEI (デジタル源氏物語)",
        license: "CC BY 4.0 (the repository's LICENSE, github.com/kouigenjimonogatari/" \
                 "kouigenjimonogatari.github.io, read 2026-09-29). Credit the デジタル源氏物語 " \
                 "project (Nakamura, Nagasaki et al.) and Ikeda Kikan's 校異源氏物語 (1942)",
        license_class: "attribution",
        upstream_url: "https://kouigenjimonogatari.github.io/",
        parser_family: "kouigenji-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "maki 01 tei", zip_url: "#{BASE_URL}/01.xml", metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "[0-9][0-9].xml")).each do |path|
          maki = File.basename(path, ".xml")
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{maki}",
                                      path: path, metadata: { "maki" => maki })
        end
      end

      def parse(document_ref)
        xml = Nokogiri::XML(File.read(document_ref.path, encoding: "UTF-8"))
        raise Nabu::ParseError, "#{document_ref.path}: #{xml.errors.first}" if xml.errors.any?

        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: title_for(xml), metadata: { "maki" => document_ref.metadata["maki"] }
        )
        facs_pending = nil
        xml.xpath("//tei:body//tei:pb | //tei:body//tei:seg", TEI_NS).each do |node|
          if node.name == "pb"
            facs_pending = node["facs"].to_s.strip
            next
          end

          add_seg(document, node, facs: facs_pending)
          facs_pending = nil
        end
        document
      end

      # 54 raw GETs, wholesale idempotent overwrite (the atmo shape —
      # at this size a resume apparatus would outweigh the corpus).
      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        MAKI.each_with_index do |maki, i|
          progress&.call("kouigenji maki #{i + 1}/#{MAKI.size}…\n")
          downloaded = Nabu::UrlDownload.new.fetch("#{BASE_URL}/#{maki}.xml", dir: workdir)
          wanted = File.join(workdir, "#{maki}.xml")
          FileUtils.mv(downloaded, wanted) unless downloaded == wanted
        end
        sha = Digest::SHA256.hexdigest(
          MAKI.map { |m| Digest::SHA256.file(File.join(workdir, "#{m}.xml")).hexdigest }.join("\n")
        )
        Nabu::FetchReport.new(sha: sha, fetched_at: Time.now, notes: ["#{MAKI.size} maki TEI files"])
      end

      private

      def title_for(xml)
        raw = xml.at_xpath("//tei:titleStmt/tei:title[@type='alt']", TEI_NS)&.text.to_s
        raw = xml.at_xpath("//tei:titleStmt/tei:title", TEI_NS)&.text.to_s if raw.strip.empty?
        Normalize.nfc(raw.strip)
      end

      def add_seg(document, seg, facs:)
        text = seg.text.gsub(/\s+/, "").strip
        return if text.empty?

        annotations = {}
        annotations["facs"] = facs if facs && !facs.empty?
        if (lg = seg.at_xpath(".//tei:lg[@type='waka']", TEI_NS))
          annotations["waka"] = lg["xml:id"].to_s
          annotations["waka_text"] = lg.xpath("./tei:l", TEI_NS).map { |l| l.text.strip }.join("／")
        end
        document << Nabu::Passage.new(
          urn: "#{document.urn}:#{ref_for(seg, document)}", language: LANGUAGE,
          text: Normalize.nfc(text), sequence: document.passages.size + 1,
          annotations: annotations
        )
      end

      # The seg's own corresp id is the citation (0005-01 → p5.l1); a
      # corresp-less seg falls back to its running position.
      def ref_for(seg, document)
        match = CORRESP_ID.match(seg["corresp"].to_s)
        return "p#{match[1]}.l#{match[2]}" if match

        "s#{document.passages.size + 1}"
      end
    end
  end
end
