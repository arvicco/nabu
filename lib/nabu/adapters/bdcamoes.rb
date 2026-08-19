# frozen_string_literal: true

require "nokogiri"

require_relative "../zip_fetch"
require_relative "../license_agree_fetch"

module Nabu
  module Adapters
    # BDCamões Part I (P80-7): the Corpus of Portuguese Literary Documents
    # from the Digital Library of Camões I.P., PORTULAN CLARIN repository —
    # 127 complete works (~3.1 M words) by 37 authors in 10 genres, 15th to
    # 20th century, in a minimal one-work XML wrapper (header > title/
    # author/other, then text, then an optional footer with the edition
    # citation). PART I ONLY: Part II is a different grant (MS NC-NoReD-ND
    # 2.0) and is deliberately not ingested.
    #
    # The download is gated by a licence-agree click-through (a Django CSRF
    # form) — accepted on owner ruling №R-37 (2026-08-19) and implemented
    # by Nabu::LicenseAgreeFetch, which refuses to agree if the form's
    # licence field drifts from the recorded DECLARED_LICENCE. The zip
    # itself then rides the whole non-destructive ZipFetch choreography.
    #
    # Document = one work: urn:nabu:bdcamoes:<slug>, the slug a
    # transliteration of the upstream basename (NFD-decompose, strip marks,
    # hyphenate camel bounds, downcase — 127/127 unique, censused
    # 2026-08-19). Filenames are clean UTF-8 upstream (every member name
    # UTF-8-flagged in the zip's central directory; the mojibake `unzip -l`
    # prints is a display artifact) — the transliteration exists so the urn
    # is byte-stable across NFC/NFD filesystems and both unzip paths (the
    # system unzip and the P78-r4 salvage reader), where raw basenames are
    # not.
    #
    # Passage = one paragraph/stanza, following what the format gives: the
    # text splits on blank lines, and each block then splits at a newline
    # followed by a SINGLE tab — the corpus's second paragraph convention
    # (22 of 127 files carry no blank lines at all and mark paragraphs by
    # tab indent; censused 2026-08-19). Drama/verse continuation lines are
    # indented with MULTIPLE tabs and poetry stanza lines with none, so
    # stanzas and speeches stay whole. Section markers ("*", canto
    # numerals — 1.2% of passages) are upstream text, kept verbatim:
    # canonical means canonical.
    #
    # The header's YY: publication year feeds the timeline (MetadataDates
    # :structured): exact years and ranges ("1880-1881", "1876/77") mint
    # bounds; unresolved marks ("18??") stay raw-only — nothing invented.
    # GG: genre rides metadata and the genre facet.
    class BdCamoes < Nabu::Adapter
      LANGUAGE = "por"
      ATTIC_DIRNAME = ".attic"

      # The record's download endpoint: a GET answers the licence-agree
      # page, the agreed POST streams archive.zip (verified 2026-08-19).
      ARTIFACT_URL = "https://portulanclarin.net/repository/download/" \
                     "52f2b16412c411ea8a1302420a000005407eb504ccc045a4a0582ab53dfd43fd/"
      RECORD_URL = "https://portulanclarin.net/repository/browse/" \
                   "bdcamoes-corpus-collection-of-portuguese-literary-documents-from-the-" \
                   "digital-library-of-camoes-ip-part-i/" \
                   "52f2b16412c411ea8a1302420a000005407eb504ccc045a4a0582ab53dfd43fd/"

      # The agree form's hidden licence value at grant time (№R-37) — the
      # exact string LicenseAgreeFetch holds the live page against.
      DECLARED_LICENCE = "CC-BY"

      MANIFEST = Nabu::SourceManifest.new(
        id: "bdcamoes",
        name: "BDCamões — Corpus of Portuguese Literary Documents, Part I (PORTULAN CLARIN)",
        license: "CC - BY (the PORTULAN CLARIN record's licence field verbatim, read 2026-08-19; " \
                 "download click-through accepted on owner ruling №R-37, 2026-08-19). Part I only " \
                 "— Part II is a different grant (MS NC-NoReD-ND 2.0) and is NOT ingested",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "bdcamoes-xml",
        credit: "João Ricardo Silva (University of Lisbon, FCUL, Department of Informatics), " \
                "BDCamões Corpus — Collection of Portuguese Literary Documents from the Digital " \
                "Library of Camões I.P. (Part I), v20191128, PORTULAN CLARIN, " \
                "hdl:21.11129/0000-000D-F89B-D; texts from the Biblioteca Digital Camões (Camões, I.P.)"
      )

      def self.manifest
        MANIFEST
      end

      # P79-2: the artifact URL only answers a POST — nothing to HEAD
      # statelessly — so the probe HEADs the record page for liveness
      # only; content drift rides the zip sha in ZipFetch's state file.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "BDCamões Part I record", zip_url: RECORD_URL, metadata_url: nil,
          state_subdir: "", liveness_only: true
        )]
      end

      # The urn slug: NFD-decompose, strip combining marks, hyphenate at
      # lower/digit→upper camel bounds, downcase, collapse everything else
      # to hyphens. "QueirósUmPoetaLírico" → "queiros-um-poeta-lirico".
      def self.urn_slug(basename)
        basename.unicode_normalize(:nfd).gsub(/\p{Mn}/, "")
                .gsub(/(?<=[a-z0-9])(?=[A-Z])/, "-")
                .downcase.gsub(/[^a-z0-9]+/, "-")
                .gsub(/\A-+|-+\z/, "")
      end

      # The YY: envelope — every shape of the 2026-08-19 census: exact
      # years, "1880-1881" ranges, the "1876/77" split year (second bound
      # completed from the first's century), and unresolved "18??"/"189?"
      # marks that honestly claim no bounds at all.
      def self.year_envelope(raw)
        raw = raw.to_s.strip
        return nil if raw.empty?

        case raw
        when /\A(\d{3,4})\z/
          year = Regexp.last_match(1).to_i
          { "not_before" => year, "not_after" => year, "raw" => raw }
        when /\A(\d{3,4})\s*-\s*(\d{3,4})\z/
          { "not_before" => Regexp.last_match(1).to_i, "not_after" => Regexp.last_match(2).to_i,
            "raw" => raw }
        when %r{\A(\d{3,4})/(\d{1,4})\z}
          first = Regexp.last_match(1)
          second = Regexp.last_match(2)
          completed = second.length < first.length ? first[0, first.length - second.length] + second : second
          { "not_before" => first.to_i, "not_after" => completed.to_i, "raw" => raw }
        else
          { "raw" => raw }
        end
      end

      # +zip_fetch_factory+ exists for the tests (a rigged fetch — no
      # network in the suite, ever); no-arg construction stays the
      # registry contract.
      def initialize(zip_fetch_factory: Nabu::ZipFetch.method(:new))
        super()
        @zip_fetch_factory = zip_fetch_factory
      end

      # The achemenet ZipFetch choreography whole, with the licence-agree
      # arm as the connection: the artifact "GET" is the agree dance.
      def fetch(workdir, progress: nil, force: false)
        agree = Nabu::LicenseAgreeFetch.new(licence: DECLARED_LICENCE)
        fetch = @zip_fetch_factory.call(url: ARTIFACT_URL, dir: workdir, http: agree,
                                        attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: fetch.sha, fetched_at: Time.now,
                              notes: ["BDCamões Part I archive.zip (licence-agree click-through, №R-37)"])
      rescue ZipFetch::Error, LicenseAgreeFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "bdcamoes fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        corpus_files(workdir).each do |path|
          basename = File.basename(path)
          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "urn:nabu:bdcamoes:#{self.class.urn_slug(File.basename(basename, '.xml'))}",
            path: File.expand_path(path),
            metadata: { "member" => basename }
          )
        end
      end

      # The census: the zip's own license.pdf is a recognized non-corpus
      # member; anything else outside resource/*.xml is unrecognized —
      # loud.
      def discovery_skips(workdir)
        corpus = corpus_files(workdir).map { |path| File.expand_path(path) }
        strays = Dir.glob(File.join(workdir, "**", "*"))
                    .select { |path| File.file?(path) }
                    .reject { |path| path.include?("/#{ATTIC_DIRNAME}/") }
                    .reject { |path| File.basename(path).start_with?(".") }
                    .reject { |path| corpus.include?(File.expand_path(path)) }
                    .reject { |path| File.expand_path(path) == File.expand_path(File.join(workdir, "license.pdf")) }
                    .map { |path| path.delete_prefix("#{workdir}/") }
                    .sort
        Nabu::Adapter::DiscoverySkips.new(
          unrecognized: strays.size,
          notes: strays.map { |rel| "non-corpus file: #{rel}" }
        )
      end

      def parse(document_ref)
        xml = parse_xml(document_ref)
        text_node = xml.at_xpath("/document/text") or
          raise Nabu::ParseError, "#{document_ref.id}: no <text> element in #{document_ref.metadata['member']}"

        passages = passages_of(text_node.text)
        raise Nabu::ParseError, "#{document_ref.id}: <text> yields zero passages" if passages.empty?

        build_document(document_ref, xml, passages)
      end

      private

      def corpus_files(workdir)
        Dir.glob(File.join(workdir, "resource", "*.xml"))
      end

      def parse_xml(document_ref)
        Nokogiri::XML(File.read(document_ref.path, encoding: "UTF-8"), &:strict)
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{document_ref.id}: malformed XML — #{e.message}"
      end

      # Blank-line blocks, then the newline+single-tab paragraph split (the
      # class note). Multi-tab and unindented continuation lines never
      # split, so speeches and stanzas stay whole.
      def passages_of(text)
        text.split(/\n[ \t]*\n+/)
            .flat_map { |block| block.split(/\n(?=\t(?!\t))/) }
            .map(&:strip)
            .reject(&:empty?)
      end

      def build_document(document_ref, xml, passages)
        header = header_of(xml)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: header[:title] || document_ref.metadata["member"],
          metadata: document_metadata(document_ref, xml, header)
        )
        passages.each_with_index do |text, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: LANGUAGE,
            text: Nabu::Normalize.nfc(text), sequence: index
          )
        end
        document
      end

      def header_of(xml)
        other = xml.at_xpath("/document/header/other")&.text.to_s
        { title: presence(xml.at_xpath("/document/header/title")&.text),
          author: presence(xml.at_xpath("/document/header/author")&.text),
          year: presence(other[/^YY:[ \t]*(.*)$/, 1]),
          genre: presence(other[/^GG:[ \t]*(.*)$/, 1]) }
      end

      def document_metadata(document_ref, xml, header)
        { "member" => document_ref.metadata["member"],
          "author" => header[:author],
          "genre" => header[:genre],
          "date" => self.class.year_envelope(header[:year]),
          "edition" => presence(xml.at_xpath("/document/footer")&.text),
          "facets" => header[:genre] ? { "genre" => { "value" => header[:genre] } } : nil }.compact
      end

      def presence(value)
        normalized = Nabu::Normalize.nfc(value.to_s).strip
        normalized.empty? ? nil : normalized
      end
    end
  end
end
