# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # KDSP — Korpus daljše slovenske proze (Corpus of longer narrative
    # Slovenian prose) 1.0 (Mandić & Erjavec, ZRC SAZU; CLARIN.SI hdl
    # 11356/1823; 02-sources row 242): 262 texts of at least 20,000 words,
    # published 1836–1918, each classified by period, length, text type,
    # subtype, theme and canonicity, with an author personography (sex,
    # birth, death, occupation). License (deposit page verbatim):
    # "Creative Commons - Attribution 4.0 International (CC BY 4.0)" →
    # attribution; every file's own availability names the same licence.
    #
    # == Shape
    #
    # ZipFetch of the plain-TEI edition (KDSP.TEI.zip, 29 MB; single top
    # dir KDSP.TEI → tree root). The deposit's .ana edition (CLASSLA
    # automatic lemma/MSD/UD — silver), txt and vert zips are deliberately
    # not ingested: the plain TEI carries the text, the silver layer would
    # be ~110 MB of error-bearing JSON (the imp silver decision).
    # discover: every KDSP<nnn>.xml at the tree root whose root element is
    # <TEI>; the corpus file KDSP.xml (<teiCorpus>: taxonomies + the
    # listPerson personography, the works XIncluded) is read for the
    # author records, never discovered; 00README.txt, KDSP-meta.tsv and
    # schema/ sit outside the pattern by layout.
    #
    # Document urn = urn:nabu:kdsp:<KDSPnnn> (the file stem IS upstream's
    # xml:id). Passages: every <head>, <p> and <lg> in body order, cited by
    # upstream's own xml:id suffix (…:d2.d1.p3, …:d1.lg1 — every block
    # carries one, censused 285,164 p / 4,571 head / 659 lg); verse lines
    # join with "\n". <milestone> (289 section-break asterisks) is layout,
    # not text — it mints nothing.
    #
    # == The held-Slovene OVERLAP — the declared policy (the sl-wikisource
    # precedent)
    #
    # KDSP is itself an AGGREGATE of digital sources, each text marked:
    # Wikivir 145, ELTeC-slv 96, dLib 21 (bibl@source). Census
    # 2026-10-11 (title-key match against the held trees): prilit holds 2
    # of the 7 texts in the 1836–66 window (Cigler's Sreča v nesreči 1836
    # — prilit's seven witness rows — and Deteljica 1863), sl-wikisource
    # 30 title-key hits (23 of KDSP's Wikivir texts by page title), imp
    # 141 title-key hits (IMP's WIKI-sigil texts are the same Wikivir
    # layer). POLICY: ingest WITH provenance, never drop — the copies are
    # different editions/renderings (KDSP's normalized TEI of a named
    # digital source vs the held corpora's own editions), and dedupe or
    # witness alignment is a catalog-side concern: the digital source,
    # its URL, author and year all ride in metadata for it.
    #
    # == Axes (aggressive mining)
    #
    # date — the sourceDesc bibl's publication year (@when on all 262),
    # a one-year envelope {not_before, not_after, raw} (MetadataDates
    # :structured). author — the bibl author, with the personography's
    # sex / birth / death / occupation joined by @corresp. facets — the
    # textClass catRefs: genre (textType: povest, roman, novela, črtica,
    # drugo), subgenre (textSubType, 28 texts), subject (textTheme);
    # canonicity, size class and the period slot (D1–D9) ride as plain
    # metadata. Places: none — the deposit carries no place field
    # (declared). Orthography: the texts are served as their digital
    # sources transcribe them (gajica throughout; no bohoričica
    # censused) — recorded, never normalized.
    class Kdsp < Nabu::Adapter
      ZIP_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/1823/KDSP.TEI.zip"

      LANGUAGE = "sl"
      URN_PREFIX = "urn:nabu:kdsp:"
      FILE_PATTERN = /\AKDSP\d{3}\.xml\z/
      CORPUS_FILE = "KDSP.xml"
      BLOCKS = %w[head p lg].freeze

      # textClass scheme → facet name (genre/subgenre/subject) or plain
      # metadata key.
      FACET_SCHEMES = { "textType" => "genre", "textSubType" => "subgenre", "textTheme" => "subject" }.freeze
      PLAIN_SCHEMES = { "textCanonicity" => "canonicity", "textSize" => "size",
                        "textTimeSlot" => "period_slot" }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "kdsp",
        name: "KDSP — Corpus of longer narrative Slovenian prose 1836–1918 (ZRC SAZU, CLARIN.SI)",
        license: "CC BY 4.0 (deposit page hdl 11356/1823 verbatim: \"Creative Commons - Attribution " \
                 "4.0 International (CC BY 4.0)\"; cite Mandić & Erjavec, KDSP 1.0)",
        license_class: "attribution",
        upstream_url: "http://hdl.handle.net/11356/1823",
        parser_family: "kdsp-tei"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "KDSP.TEI.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "*.xml")).each do |path|
          next unless FILE_PATTERN.match?(File.basename(path)) && tei_work?(path)

          block.call(Nabu::DocumentRef.new(
                       source_id: MANIFEST.id, id: "#{URN_PREFIX}#{File.basename(path, '.xml')}",
                       path: File.expand_path(path), metadata: {}
                     ))
        end
      end

      def parse(document_ref)
        doc = Nokogiri::XML(File.read(document_ref.path), &:strict)
        doc.remove_namespaces!
        build_document(doc, document_ref)
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
        raise Nabu::FetchError, "kdsp fetch failed into #{workdir}: #{e.message}"
      end

      private

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

      def build_document(doc, document_ref)
        stem = File.basename(document_ref.path, ".xml")
        bibl = doc.at_xpath("//sourceDesc/bibl")
        document = Document.new(
          urn: document_ref.id, language: LANGUAGE, title: title(doc, bibl),
          canonical_path: document_ref.path,
          metadata: header_metadata(doc, bibl, File.dirname(document_ref.path))
        )
        append_blocks(document, doc, document_ref, stem)
        raise ParseError, "#{document_ref.path}: no text blocks found" if document.empty?

        document
      end

      def append_blocks(document, doc, document_ref, stem)
        doc.xpath("//body//*[self::head or self::p or self::lg]").each do |block|
          text = block_text(block)
          next if text.empty?

          document << Passage.new(
            urn: "#{document_ref.id}:#{citation(block, stem, document.size)}",
            language: LANGUAGE, text: text,
            annotations: { "unit" => block.name }, sequence: document.size
          )
        end
      end

      def block_text(block)
        raw = if block.name == "lg"
                block.xpath("l").map { |line| squash(line.text) }.reject(&:empty?).join("\n")
              else
                squash(block.text)
              end
        Normalize.nfc(raw)
      end

      def squash(text) = text.gsub(/[[:space:]]+/, " ").strip

      # Upstream ids are "<docid>.<path>" — the suffix is the citation; a
      # block without an id (none censused) falls back positionally.
      def citation(block, stem, sequence)
        id = block["id"].to_s
        return id.delete_prefix("#{stem}.") if id.start_with?("#{stem}.")

        "b#{sequence + 1}"
      end

      def title(doc, bibl)
        node = bibl&.at_xpath("title[@type='main']")
        node = doc.at_xpath("//titleStmt/title") if node.nil? || node.text.strip.empty?
        node && Normalize.nfc(node.text.strip)
      end

      def header_metadata(doc, bibl, workdir)
        meta = bibl_metadata(bibl)
        meta.merge!(person_metadata(bibl, workdir))
        meta.merge!(class_metadata(doc))
        meta["words"] = doc.at_xpath("//extent/measure[@unit='words']")&.text
        meta.compact.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end

      def bibl_metadata(bibl)
        return {} if bibl.nil?

        year = bibl.at_xpath("date")&.[]("when").to_s[/\A\d{4}/]
        idno = bibl.at_xpath("idno")
        {
          "author" => bibl.at_xpath("author")&.text&.strip,
          "date" => year && { "not_before" => year.to_i, "not_after" => year.to_i,
                              "raw" => bibl.at_xpath("date").text.strip },
          "digital_source" => bibl["source"].to_s.delete_prefix("#").then { |s| s.empty? ? nil : s },
          "digital_source_url" => idno&.text&.strip
        }
      end

      def person_metadata(bibl, workdir)
        ref = bibl&.at_xpath("author")&.[]("corresp").to_s.delete_prefix("#")
        return {} if ref.empty?

        person = personography(workdir)[ref]
        return { "author_ref" => ref } if person.nil?

        { "author_ref" => ref }.merge(person.transform_keys { |key| "author_#{key}" })
      end

      # The corpus file's listPerson, memoized per tree: {xml:id => {sex,
      # birth, death, occupation}}. An absent corpus file (a trimmed tree)
      # joins nothing.
      def personography(workdir)
        @personography ||= {}
        @personography[workdir] ||= begin
          path = File.join(workdir, CORPUS_FILE)
          if File.file?(path)
            corpus = Nokogiri::XML(File.read(path))
            corpus.remove_namespaces!
            corpus.xpath("//listPerson/person").to_h { |person| [person["id"], person_record(person)] }
          else
            {}
          end
        end
      end

      def person_record(person)
        {
          "sex" => person.at_xpath("sex")&.[]("value"),
          "birth" => person.at_xpath("birth")&.[]("when"),
          "death" => person.at_xpath("death")&.[]("when"),
          "occupation" => person.at_xpath("occupation")&.text&.strip
        }.compact
      end

      def class_metadata(doc)
        meta = {}
        facets = {}
        doc.xpath("//textClass/catRef").each do |ref|
          scheme = ref["scheme"].to_s.delete_prefix("#")
          value = ref["target"].to_s.delete_prefix("#")
          next if value.empty?

          if (facet = FACET_SCHEMES[scheme])
            facets[facet] = { "value" => Normalize.nfc(value), "raw" => Normalize.nfc(value) }
          elsif (key = PLAIN_SCHEMES[scheme])
            meta[key] = value
          end
        end
        meta["facets"] = facets unless facets.empty?
        meta
      end
    end
  end
end
