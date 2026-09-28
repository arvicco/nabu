# frozen_string_literal: true

require "digest"
require "fileutils"
require "nokogiri"
require_relative "../url_download"

module Nabu
  module Adapters
    # Skjaervø, Khotanese Manuscripts from Chinese Turkestan in the
    # British Library (P107-3a, Q96.2): the revised 2014 online edition
    # as ONE TEI.2 XML (Zenodo doi 10.5281/zenodo.3372682, CC BY 4.0) —
    # 2,357 msDescription records, 20,596 khot-Latn transliteration
    # lines. THE text lane for the Khotanese documents IEDC catalogs.
    #
    # UPSTREAM'S OWN CAVEAT, declared everywhere: "The records in this
    # file are a draft version. They have not yet been proofed and
    # checked against physical holdings" — metadata edition_status
    # "draft-unproofed" on every document, the license line repeats it.
    #
    # == Identity / passages
    #
    # One document per msDescription, keyed by upstream's own record
    # number (@n): urn:nabu:skjaervo-khotanese:ms<n>; title = the
    # CURRENT shelfmark (idno[@type=current]). Passages = the <l> lines
    # of each msItem's khot-Latn <q>, cited :i<item>.l<line> (line
    # numbers from @n where clean, positional otherwise). The English
    # <note> per item is APPARATUS — metadata "items", never passages.
    # Language kho (the transliteration IS the served text form; script
    # note recorded).
    class SkjaervoKhotanese < Nabu::Adapter
      FILE_URL = "https://zenodo.org/api/records/3372682/files/" \
                 "Skjaervo_2013_Khotanese%20Manuscripts_DRAFT.xml/content"
      FILE_GLOB = "Skjaervo_*.xml"
      URN_PREFIX = "urn:nabu:skjaervo-khotanese:"
      # The collection is not purely Khotanese: 164 transliteration
      # blocks are Chinese (chi-Latn/chi-Hant q lang tags — Chinese
      # scrolls among the BL bundles). The document language follows
      # the FIRST transliteration q's own lang attribute.
      LANGUAGE = "kho"
      Q_LANGUAGES = { "khot-Latn" => "kho", "chi-Latn" => "zho", "chi-Hant" => "zho" }.freeze
      # The raw-byte record boundary (see the damage-boundary note in
      # the private section): flat spans, regex-exact on this file.
      FRAGMENT = %r{<msDescription\b.*?</msDescription>}m

      MANIFEST = Nabu::SourceManifest.new(
        id: "skjaervo-khotanese",
        name: "Skjaervø — Khotanese Manuscripts from Chinese Turkestan (BL records)",
        license: "CC BY 4.0 (the Zenodo record). Credit Prods Oktor Skjærvø and the ERC " \
                 "\"Beyond Boundaries\" project (doi 10.5281/zenodo.3372682). UPSTREAM CAVEAT " \
                 "carried verbatim: \"The records in this file are a draft version. They have " \
                 "not yet been proofed and checked against physical holdings.\"",
        license_class: "open",
        upstream_url: "https://doi.org/10.5281/zenodo.3372682",
        parser_family: "skjaervo-tei2"
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = corpus_path(workdir) or return
        refs_for(path).each(&block)
      end

      def parse(document_ref)
        index = document_ref.metadata.fetch("index")
        fragment = fragments(document_ref.path)[index] or
          raise Nabu::ParseError, "#{document_ref.id}: fragment #{index} vanished (stale ref?)"
        record = parse_fragment(fragment)

        language = language_for(record)
        passages = passages_for(document_ref.id, record, language)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language,
          canonical_path: document_ref.path,
          title: title_for(record), metadata: metadata_for(record, passages)
        )
        passages.each { |passage| document << passage }
        document
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        FileUtils.mkdir_p(workdir)
        downloaded = Nabu::UrlDownload.new.fetch(FILE_URL, dir: workdir)
        Nabu::FetchReport.new(sha: Digest::SHA256.file(downloaded).hexdigest, fetched_at: Time.now,
                              notes: ["#{File.basename(downloaded)} (#{File.size(downloaded)} bytes)"])
      end

      private

      def corpus_path(workdir)
        Dir.glob(File.join(workdir, FILE_GLOB)).max
      end

      # == The damage boundary (first-sync finding, 2026-09-28)
      #
      # The upstream DRAFT is genuinely malformed XML — ~100 unclosed
      # <p>/<msIdentifier>/<msItem> tags. A whole-file recover parse
      # BLEEDS records into each other (1,903 of 2,357 records
      # survived, and neighbours' lines were re-collected 8x over). So
      # the record boundary is cut on the RAW BYTES — the flat
      # <msDescription>…</msDescription> spans are regex-exact (2,357,
      # verified) — and each fragment recovers as its OWN mini-DOM:
      # damage stays inside its record, neighbours parse clean.
      # (Defect reported upstream — .docs/upstream-reports.md.)
      def fragments(path)
        key = [path, File.mtime(path)]
        return @fragments_cache if defined?(@fragments_key) && @fragments_key == key

        @fragments_key = key
        @fragments_cache = File.read(path, encoding: "UTF-8").scan(FRAGMENT)
      end

      def parse_fragment(fragment)
        Nokogiri::XML(fragment, &:recover).root or
          raise Nabu::ParseError, "unparseable msDescription fragment"
      end

      # One ref per fragment; upstream duplicates @n on 20 records, so
      # duplicate urns take the house b2 suffix in FILE ORDER (stable
      # across discover and parse — both read the same fragment list).
      def refs_for(path)
        seen = Hash.new(0)
        fragments(path).each_with_index.map do |fragment, index|
          n = fragment[/\A<msDescription\b[^>]*\bn="([^"]*)"/, 1].to_s.strip
          n = "x#{index + 1}" if n.empty?
          seen[n] += 1
          urn = seen[n] == 1 ? "#{URN_PREFIX}ms#{n}" : "#{URN_PREFIX}ms#{n}b#{seen[n]}"
          Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn, path: path,
                                metadata: { "index" => index, "n" => n })
        end
      end

      def title_for(record)
        current = record.at_xpath(".//idno[@type='current']")&.text.to_s.strip
        current.empty? ? nil : Normalize.nfc(current)
      end

      def metadata_for(record, passages)
        meta = { "n" => record["n"].to_s.strip,
                 "edition_status" => "draft-unproofed" }
        { "settlement" => "settlement", "repository" => "repository",
          "collection" => "collection" }.each do |key, tag|
          value = record.at_xpath(".//msIdentifier/#{tag}")&.text.to_s.strip
          meta[key] = Normalize.nfc(value) unless value.empty?
        end
        old = record.xpath(".//idno[@type='old']").map { |i| Normalize.nfc(i.text.strip) }
        meta["idno_old"] = old unless old.empty?
        items = record.xpath(".//msItem").map do |item|
          entry = { "n" => item["n"].to_s, "type" => item["type"].to_s }
          note = item.xpath("./note").map { |x| x.text.gsub(/\s+/, " ").strip }.join(" ").strip
          entry["note"] = Normalize.nfc(note) unless note.empty?
          entry
        end
        meta["items"] = items unless items.empty?
        meta["text_state"] = passages.empty? ? "catalog-record" : "text"
        meta
      end

      def language_for(record)
        lang = record.at_xpath(".//q[@type='transliteration']")&.[]("lang").to_s
        Q_LANGUAGES.fetch(lang, LANGUAGE)
      end

      def passages_for(urn, record, language)
        passages = []
        record.xpath(".//msItem").each_with_index do |item, item_index|
          item.xpath(".//q[@type='transliteration']//l").each_with_index do |line, line_index|
            text = Normalize.nfc(line.text.gsub(/\s+/, " ").strip)
            next if text.empty?

            label = clean_line_number(line["n"]) || (line_index + 1).to_s
            passages << Nabu::Passage.new(
              urn: unique_urn(passages, "#{urn}:i#{item_index + 1}.l#{label}"),
              language: language, text: text, sequence: passages.size + 1
            )
          end
        end
        passages
      end

      # @n is usually a clean integer; anything else (ranges, letters)
      # falls back to position.
      def clean_line_number(value)
        v = value.to_s.strip
        v.match?(/\A\d+\z/) ? v : nil
      end

      # Duplicate upstream line numbers take the house :b2 suffix.
      def unique_urn(passages, candidate)
        return candidate if passages.none? { |p| p.urn == candidate }

        suffix = 2
        suffix += 1 while passages.any? { |p| p.urn == "#{candidate}b#{suffix}" }
        "#{candidate}b#{suffix}"
      end
    end
  end
end
