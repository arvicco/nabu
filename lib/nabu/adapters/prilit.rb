# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # PriLit — the corpus of older Slovenian narrative prose (P95-1;
    # CLARIN.SI hdl 11356/1319; Žejn & Erjavec, ZRC SAZU/JSI): 43 texts /
    # 37 works / 12 authors, 1643–1866 excluding reprints — the earliest
    # Slovenian narrative prose, extending the sl axis's narrative
    # material a century and a half before goo300k. License (deposit
    # page, verbatim): "Creative Commons - Attribution 4.0 International
    # (CC BY 4.0)" → attribution.
    #
    # == The v1 scope (the P17-6 survey's fixture sketch, executed P95)
    #
    # The deposit ships four editions; v1 ingests the PLAIN TEI
    # (PriLit.TEI.zip): bodies are pure <ab xml:id="Doc.N"> text blocks —
    # the canonical historical surface, no annotation. The .ana edition's
    # SILVER lemma/msd/UD layer is deliberately not ingested (and its
    # schema is NOT imp-tei: bare <w> with @join spacing, no
    # <choice><orig>/<reg> — a future silver wave would need its own
    # family; recorded honestly, not smuggled).
    #
    # Sreča v nesreči (Cigler) ships in MULTIPLE editions with different
    # segmentations — provenance-distinct documents (the diorisis
    # second-editions stance), a ready collation case.
    #
    # == Shape
    #
    # ZipFetch of the TEI zip (single top dir PriLit.TEI → tree root).
    # discover: every *.xml in the workdir whose root is <TEI> — the
    # corpus-level PriLit.xml (<teiCorpus>, header only) is skipped by
    # ROOT ELEMENT, never by name. Document urn = urn:nabu:prilit:<stem>
    # (the file stem IS upstream's xml:id). Passage citation = the ab
    # xml:id's suffix after "<docid>." (upstream's own numbering).
    class Prilit < Nabu::Adapter
      ZIP_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1319/" \
                "PriLit.TEI.zip?sequence=6&isAllowed=y"

      LANGUAGE = "sl"

      URN_PREFIX = "urn:nabu:prilit:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "prilit",
        name: "PriLit — older Slovenian narrative prose (ZRC SAZU/JSI, CLARIN.SI)",
        license: "CC BY 4.0 (deposit page verbatim: \"Creative Commons - Attribution 4.0 " \
                 "International (CC BY 4.0)\"; cite Žejn & Erjavec, hdl 11356/1319)",
        license_class: "attribution",
        upstream_url: "http://hdl.handle.net/11356/1319",
        parser_family: "prilit-tei"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "PriLit.TEI.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", "*.xml")).sort
           .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
           .each do |path|
          stem = File.basename(path, ".xml")
          next unless tei_work?(path)

          block.call(Nabu::DocumentRef.new(
                       source_id: manifest.id, id: "#{URN_PREFIX}#{stem}",
                       path: File.expand_path(path), metadata: {}
                     ))
        end
      end

      def parse(document_ref)
        doc = Nokogiri::XML(File.read(document_ref.path)) { |cfg| cfg.strict }
        doc.remove_namespaces!
        stem = File.basename(document_ref.path, ".xml")
        build_document(doc, document_ref, stem)
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{document_ref.path}: malformed XML: #{e.message}"
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        result = Nabu::ZipFetch.sync!(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress,
          guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = [result.not_modified ? "not modified (304)" : "TEI zip unpacked",
                 attic_notes(result.atticked)].compact.join("; ")
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now, notes: notes)
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "prilit fetch failed into #{workdir}: #{e.message}"
      end

      private

      # A work file's root is <TEI>; the corpus header PriLit.xml is a
      # <teiCorpus> and is skipped by rule (root element, never filename).
      def tei_work?(path)
        root = nil
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            next unless node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT

            root = node.name.split(":").last
            break
          end
        end
        root == "TEI"
      rescue Nokogiri::XML::SyntaxError
        false
      end

      def build_document(doc, document_ref, stem)
        document = Document.new(
          urn: document_ref.id, language: LANGUAGE,
          title: doc.at_xpath("//titleStmt/title")&.text&.strip,
          canonical_path: document_ref.path,
          metadata: header_metadata(doc)
        )
        doc.xpath("//body/ab").each_with_index do |block, sequence|
          text = Normalize.nfc(block.text.gsub(/[[:space:]]+/, " ").strip)
          next if text.empty?

          document << Passage.new(
            urn: "#{document_ref.id}:#{citation(block, stem, sequence)}",
            language: LANGUAGE, text: text,
            annotations: { "unit" => "ab" }, sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path}: no <ab> blocks found" if document.empty?

        document
      end

      # Upstream ids are "<docid>.<n>" — the suffix is the citation; a
      # block without an id (none censused) falls back positionally.
      def citation(block, stem, sequence)
        id = block["id"].to_s
        return id.delete_prefix("#{stem}.") if id.start_with?("#{stem}.")

        "b#{sequence + 1}"
      end

      def header_metadata(doc)
        author = doc.at_xpath("//titleStmt/author")
        print_date = doc.at_xpath("//sourceDesc/bibl[@type='printSource']/date")
        {
          "author" => author&.text&.strip,
          "author_ref" => author&.[]("ref"),
          "date" => print_date&.[]("when"),
          "date_cert" => print_date&.[]("cert"),
          "digital_urn" => doc.at_xpath("//sourceDesc/bibl[@type='digitalSource']/idno[@type='urn']")&.text,
          "words" => doc.at_xpath("//extent/measure[@unit='words']")&.text
        }.compact
      end
    end
  end
end
