# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # DiCCAS — the Disaster Corpus in Classical Arabic Sources (P95-4,
    # the long-tail sweep; CLARIN.SI hdl 11356/2097, Cicola, University
    # of Bologna 2025). One 3.6 MB TEI file of disaster accounts
    # excerpted from ten classical sources — the Qurʾān, Ṣaḥīḥ Muslim,
    # Ṣaḥīḥ al-Bukhārī, al-Ṭabarī's history and tafsīr, Ibn Taghrībirdī,
    # al-Maqrīzī, al-Dhahabī, Ibn al-Jawzī, al-Jāḥiẓ — with catastrophe
    # terminology tagged. License: deposit page AND in-file <licence>
    # agree, CC BY-NC-SA 4.0 → nc. The arabic desk's third member.
    #
    # == Shape
    #
    # Document = one <div1 type="book"> (10 upstream; title = the
    # header's msDesc msName by matching @n; genre = the div1's @ana —
    # religious/history/tafsir, "#" stripped). Passage = one <p>, text
    # at paragraph grain; citation = the div @n ladder + p ordinal
    # within its division ("2.155.p1" — positional at the leaf, stable
    # because the deposit is frozen and sync_policy is manual).
    #
    # == The gloss policy (the censused quirk)
    #
    # Most paragraphs embed an English translation as
    # <gloss ana="translation" xml:lang="en"> INSIDE the Arabic <p>.
    # The gloss never enters the passage text (the text is the Arabic
    # source, not a bilingual soup); it rides the passage annotations
    # as "gloss_en" — searchable context, honestly labelled machine-side
    # metadata of the corpus's own making. <term>/<hi>/<placeName> are
    # transparent reading text.
    class Diccas < Nabu::Adapter
      FILE_URL = "https://www.clarin.si/repository/xmlui/bitstream/handle/11356/2097/" \
                 "DiCCAS.tei.xml?sequence=21&isAllowed=y"
      FILENAME = "DiCCAS.tei.xml"

      LANGUAGE = "ara"

      URN_PREFIX = "urn:nabu:diccas:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "diccas",
        name: "DiCCAS — Disaster Corpus in Classical Arabic Sources (Cicola, Bologna)",
        license: "CC BY-NC-SA 4.0 (deposit page: \"Creative Commons - " \
                 "Attribution-NonCommercial-ShareAlike 4.0 International\"; in-file <licence> " \
                 "agrees; cite Cicola, hdl 11356/2097)",
        license_class: "nc",
        upstream_url: "http://hdl.handle.net/11356/2097",
        parser_family: "diccas-tei"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, FILENAME)
        return unless File.file?(path)

        corpus(path).books.each do |book|
          block.call(Nabu::DocumentRef.new(
                       source_id: manifest.id, id: "#{URN_PREFIX}#{book[:n]}",
                       path: File.expand_path(path), metadata: { "n" => book[:n] }
                     ))
        end
      end

      def parse(document_ref)
        book = corpus(document_ref.path).books.find { |b| b[:n] == document_ref.metadata["n"] } or
          raise ParseError, "#{document_ref.path}: book #{document_ref.metadata['n']} vanished"

        document = Document.new(
          urn: document_ref.id, language: LANGUAGE, title: book[:title],
          canonical_path: document_ref.path,
          metadata: { "genre" => book[:genre], "book" => book[:n] }.compact
        )
        book[:passages].each_with_index do |unit, sequence|
          document << Passage.new(
            urn: "#{document_ref.id}:#{unit[:citation]}", language: LANGUAGE,
            text: unit[:text],
            annotations: { "unit" => "p", "gloss_en" => unit[:gloss] }.compact,
            sequence: sequence
          )
        end
        raise ParseError, "#{document_ref.path}: book #{book[:n]} has no paragraphs" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::FileFetch.new(url: FILE_URL, dir: workdir, filename: FILENAME,
                                    attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: nil)
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "diccas fetch failed into #{workdir}: #{e.message}"
      end

      private

      # One DOM parse per file, memoized per path+mtime (the whole corpus
      # is one 3.6 MB document — the <5 MB house DOM ceiling).
      def corpus(path)
        key = [path, File.mtime(path)]
        return @corpus[1] if @corpus && @corpus[0] == key

        doc = Nokogiri::XML(File.read(path)) { |cfg| cfg.strict }
        doc.remove_namespaces!
        @corpus = [key, Extraction.new(doc).call]
        @corpus[1]
      rescue Nokogiri::XML::SyntaxError => e
        raise ParseError, "#{path}: malformed XML: #{e.message}"
      end

      # The one-pass extraction: header msNames by @n, then each div1's
      # paragraph units with ladder citations and the gloss split.
      class Extraction
        Result = Data.define(:books)

        def initialize(doc)
          @doc = doc
        end

        def call
          titles = @doc.xpath("//sourceDesc/msDesc").to_h do |ms|
            [ms["n"], ms.at_xpath(".//msName")&.text&.strip]
          end
          books = @doc.xpath("//body/div1").map do |div1|
            n = div1["n"]
            {
              n: n, title: titles[n] || "Book #{n}",
              genre: div1["ana"]&.delete_prefix("#"),
              passages: passages(div1)
            }
          end
          Result.new(books: books)
        end

        private

        def passages(div1)
          counters = Hash.new(0)
          div1.xpath(".//p").filter_map do |p|
            ladder = p.ancestors.reverse.filter_map { |a| a["n"] if a.name.start_with?("div") && a.name != "div1" }
            key = ladder.join(".")
            counters[key] += 1
            gloss = p.xpath(".//gloss").map { |g| squash(g.text) }.reject(&:empty?).join(" ")
            text = arabic_text(p)
            next nil if text.empty?

            citation = [key, "p#{counters[key]}"].reject(&:empty?).join(".")
            { citation: citation, text: text, gloss: gloss.empty? ? nil : gloss }
          end
        end

        # The passage text: the paragraph minus its gloss subtrees (the
        # embedded English translations — annotation, never text).
        def arabic_text(paragraph)
          clone = paragraph.dup
          clone.xpath(".//gloss").each(&:remove)
          Normalize.nfc(squash(clone.text))
        end

        def squash(text)
          text.gsub(/[[:space:]]+/, " ").strip
        end
      end
      private_constant :Extraction
    end
  end
end
