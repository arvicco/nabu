# frozen_string_literal: true

require_relative "usfm_parser"

module Nabu
  module Adapters
    # vuk-danicic — the Serbian Bible of Vuk Stefanović Karadžić (New
    # Testament, Vienna 1847) and Đura Daničić (Old Testament, completed
    # 1865, printed in the 1868 whole Bible) — P117-2. The founding
    # text of Vuk's Neo-Štokavian ijekavian literary standard, in the
    # language of the reform itself.
    #
    # == The asset, and why this one
    #
    # github.com/spthmpsn/Rs1Bible (one commit series, 2016-03-08/09): the
    # 66 books as one USFM file each (01-GEN … 67-REV), converted from THE
    # UNBOUND BIBLE's "Serbian: Danicic Karadzic Latin" (Biola University)
    # — 31,102 verses (censused 2026-10-11 @a51bd9fc, every verse
    # non-empty and NFC). It is the IJEKAVIAN text ("U početku bješe
    # riječ") in Latin transliteration of the Cyrillic original.
    #
    # The obvious alternative was weighed and refused: eBible.org's
    # srp1868 (Cyrillic) and srp1865 (Latin) are stated public domain but
    # their own title page says "ћирилични, екавизиран, модернизован и
    # параграфиран текст издања из 1868. године" — an EKAVIZED, MODERNIZED
    # rendering ("У почетку беше Реч"), a modern editorial layer over the
    # translation, not Vuk's and Daničić's language. The eBible USFX would
    # have composed UsfxParser for free; fidelity to the 1847/1868 text
    # outweighs the parser.
    #
    # The conversion's \p and \s5 markers were imported from an English
    # edition (the repo's own commit message: "Added chunk and paragraph
    # markers per ulb-en source") and its \h/\toc headings are English
    # ("John") — structure and titles of the converter, not of the Serbian
    # Bible; the usfm family reads verses only, and titles stay the
    # converter's English book names (declared, not translated).
    #
    # == Identity
    #
    # Document = one book: urn:nabu:vuk-danicic:<USFM code downcased>
    # (JHN → urn:nabu:vuk-danicic:jhn, the eng-web book-urn shape);
    # passages <doc-urn>:<chapter>.<verse>.
    #
    # == Axes
    #
    # Kind: scripture (kind_map source_kind — the whole-source Bible
    # precedent). Date: the translation's own era per testament — NT 1847
    # (Vuk's Vienna New Testament), OT 1865–1868 (Daničić's translation,
    # finished 1865, first printed in the 1868 Bible) — an attributed
    # composition-class envelope (MetadataDates :structured), not an
    # artifact date: the asset names no printing. Translator per
    # testament as metadata. Place: none — the asset carries no imprint.
    #
    # == License
    #
    # The text is public domain by age (Karadžić d. 1864, Daničić d. 1882;
    # 1847/1868 prints). The repository carries no LICENSE file; its only
    # statement is the README's provenance line ("USFM Bible source files
    # converted from … THE UNBOUND BIBLE (www.unboundbible.org) / Language
    # = Serbian: Danicic Karadzic Latin"). The USFM layer is a mechanical
    # conversion (verse markers over the PD text) with no authored layer
    # read here → open.
    class VukDanicic < Nabu::Adapter
      REPO_URL = "https://github.com/spthmpsn/Rs1Bible.git"
      LANGUAGE = "srp"
      URN_PREFIX = "urn:nabu:vuk-danicic:"
      FILE_PATTERN = /\A\d{2}-[1-3A-Z]{3}\.usfm\z/

      NT_BOOKS = %w[MAT MRK LUK JHN ACT ROM 1CO 2CO GAL EPH PHP COL 1TH 2TH 1TI 2TI TIT PHM HEB
                    JAS 1PE 2PE 1JN 2JN 3JN JUD REV].freeze

      TESTAMENTS = {
        "nt" => { "translator" => "Vuk Stefanović Karadžić",
                  "date" => { "not_before" => 1847, "not_after" => 1847,
                              "raw" => "1847 — Vuk's New Testament (Vienna); translation era, attributed" } },
        "ot" => { "translator" => "Đura Daničić",
                  "date" => { "not_before" => 1865, "not_after" => 1868,
                              "raw" => "1865–1868 — Daničić's Old Testament, finished 1865, first " \
                                       "printed in the 1868 Bible; translation era, attributed" } }
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "vuk-danicic",
        name: "The Vuk–Daničić Serbian Bible (NT 1847, OT 1865) — ijekavian text, via Rs1Bible USFM",
        license: "Public domain (Karadžić d. 1864, Daničić d. 1882; the 1847 New Testament and the 1868 " \
                 "Bible). The repository carries no LICENSE; its README states the provenance only: " \
                 "\"USFM Bible source files converted from … THE UNBOUND BIBLE (www.unboundbible.org)\" — " \
                 "\"Language = Serbian: Danicic Karadzic Latin\". The USFM layer is a mechanical conversion.",
        license_class: "open",
        upstream_url: "https://github.com/spthmpsn/Rs1Bible",
        parser_family: "usfm"
      )

      def self.manifest = MANIFEST

      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        book_paths(workdir).each do |path|
          code = File.basename(path, ".usfm").split("-", 2).last
          yield Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{code.downcase}",
                                      path: File.expand_path(path), metadata: { "book" => code })
        end
      end

      def discovery_skips(workdir)
        strays = Dir.glob(File.join(workdir, "*.usfm")).reject { |p| FILE_PATTERN.match?(File.basename(p)) }
        Nabu::Adapter::DiscoverySkips.new(unrecognized: strays.size,
                                          notes: strays.map { |p| "unrecognized .usfm name: #{File.basename(p)}" })
      end

      def parse(document_ref)
        book = UsfmParser.new.parse(document_ref.path)
        expected = document_ref.metadata.fetch("book")
        unless book.id == expected
          raise Nabu::ParseError, "#{document_ref.path}: \\id #{book.id} does not match the file's #{expected}"
        end

        testament = NT_BOOKS.include?(book.id) ? "nt" : "ot"
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: book.heading || book.id,
                                      metadata: metadata_for(book, testament))
        book.verses.each_with_index do |verse, index|
          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{verse.chapter}.#{verse.verse}",
                                        language: LANGUAGE, text: verse.text, sequence: index + 1)
        end
        raise Nabu::ParseError, "#{document_ref.id}: no verses" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      private

      def repo_url = REPO_URL

      def book_paths(workdir)
        Dir.glob(File.join(workdir, "*.usfm")).select { |p| FILE_PATTERN.match?(File.basename(p)) }.sort
      end

      def metadata_for(book, testament)
        era = TESTAMENTS.fetch(testament)
        { "book" => book.id, "testament" => testament, "translator" => era["translator"],
          "date" => era["date"], "script" => "Latn", "orthography" => "ijekavian",
          "toc" => book.toc }.reject { |_k, v| v.respond_to?(:empty?) && v.empty? }
      end
    end
  end
end
