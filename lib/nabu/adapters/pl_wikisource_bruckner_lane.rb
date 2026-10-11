# frozen_string_literal: true

require "fileutils"
require "json"

require_relative "../normalize"

module Nabu
  module Adapters
    # Brückner's Słownik etymologiczny języka polskiego (Kraków: Krakowska
    # Spółka Wydawnicza, 1927; A. Brückner †1939 → PD) — pl-wikisource's
    # declared secondary dictionary lane (Adapter.dictionary_lane, the
    # P104-4 multi-shelf seam), shelf slug "bruckner", language pol.
    #
    # == The structure verdict (census 2026-10-10): DICTIONARY-SHAPED
    #
    # The wiki holds the 1927 print as 828 proofread scan pages
    # (Strona:PL Aleksander Brückner-Słownik etymologiczny języka polskiego
    # NNN.jpeg) in which EVERY entry is a labelled section
    # (<section begin="córa"/>…<section end="córa"/>), plus 5,715 ns-0
    # entry pages (Słownik etymologiczny języka polskiego/<headword>) that
    # are pure {{Bruckner}} stubs naming the entry's section and its
    # first/last scan page. So: one entry per stub; the body is the
    # section's text joined across the scan pages it spans (an entry
    # continued over a page break reuses its section label on the next
    # page; the {{pp|a|b}}/{{pk|a|b}} hyphenation pair joins the split
    # word). The headword is the stub's own subpage name, verbatim
    # ("*rągać" keeps Brückner's asterisk; "kapa, kapica" keeps the pair).
    #
    # Live census (2026-10-10): 5,711 of the 5,715 stubs resolve to a
    # section — the four left are the book's front/back matter (Przedmowa,
    # Dodatek, Indeks Ch, Objaśnienie znaków i skróceń), honestly absent.
    # Scan proofreading: 138 validated · 387 proofread · 292 NOT proofread
    # (raw OCR) · 11 without text — ingested at any transcription status
    # (the №R-74 posture), declared here rather than filtered.
    #
    # == Canonical shape (written by the pl-wikisource fetch)
    #
    # bruckner/entries.json — the stubs: [{title, pageid, revid, section,
    # first_page, last_page}] sorted by title; bruckner/scans/<pageid>.json
    # — each scan page's envelope (title/pageid/revid/timestamp/wikitext,
    # its pagequality level inside the wikitext's <noinclude> header).
    class PlWikisourceBrucknerLane < Nabu::Adapter
      SLUG = "bruckner"
      LANGUAGE = "pol"
      TITLE = "Słownik etymologiczny języka polskiego (A. Brückner, Kraków 1927)"
      DIRNAME = "bruckner"
      ENTRIES_FILE = "entries.json"
      SCANS_DIRNAME = "scans"
      STUB_PREFIX = "Słownik etymologiczny języka polskiego/"
      SCAN_PREFIX = "PL Aleksander Brückner-Słownik etymologiczny języka polskiego"
      SCAN_NAMESPACE = 100 # Strona:
      REF_ID = "pl-wikisource-bruckner:slownik"
      SECTION = %r{<section\s+begin="([^"]+)"\s*/>(.*?)<section\s+end="\1"\s*/>}m

      def self.manifest = PlWikisource::MANIFEST

      # The fetch stage (called from PlWikisource#fetch with the family's
      # batched api.php plumbing): stubs → entries.json, scans → envelopes.
      def self.fetch!(workdir, pins:, progress:, batches:, revisions:, prefix_titles:)
        dir = File.join(workdir, DIRNAME)
        stubs = []
        stub_titles = prefix_titles.call(STUB_PREFIX)
        progress&.call("Brückner: #{stub_titles.size} entry stub(s)\n")
        batches.call(stub_titles).each do |batch|
          revisions.call(batch).each do |page|
            revision = page.dig("revisions", 0) or next

            stubs << stub_record(page, revision)
            pins["bruckner:#{page.fetch('pageid')}"] = revision["revid"]
          end
        end
        scan_titles = prefix_titles.call(SCAN_PREFIX, namespace: SCAN_NAMESPACE)
        progress&.call("Brückner: #{scan_titles.size} scan page(s)\n")
        batches.call(scan_titles).each do |batch|
          revisions.call(batch).each do |page|
            revision = page.dig("revisions", 0) or next

            write_json!(File.join(dir, SCANS_DIRNAME, "#{page.fetch('pageid')}.json"),
                        "title" => page.fetch("title"), "pageid" => page.fetch("pageid"),
                        "revid" => revision["revid"], "timestamp" => revision["timestamp"],
                        "wikitext" => revision.dig("slots", "main", "*").to_s)
            pins["bruckner-scan:#{page.fetch('pageid')}"] = revision["revid"]
          end
        end
        write_json!(File.join(dir, ENTRIES_FILE), stubs.sort_by { |stub| stub.fetch("title") })
      end

      def self.stub_record(page, revision)
        wikitext = revision.dig("slots", "main", "*").to_s
        param = ->(name) { wikitext[/^\s*\|\s*#{Regexp.escape(name)}\s*=\s*(.*?)\s*$/, 1].to_s.strip }
        {
          "title" => page.fetch("title"), "pageid" => page.fetch("pageid"), "revid" => revision["revid"],
          "section" => param.call("sekcja"), "first_page" => param.call("pierwsza strona"),
          "last_page" => param.call("ostatnia strona")
        }
      end

      def self.write_json!(path, payload)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite("#{path}.tmp", "#{JSON.pretty_generate(payload)}\n")
        File.rename("#{path}.tmp", path)
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = File.join(workdir, DIRNAME, ENTRIES_FILE)
        return unless File.file?(path)

        yield Nabu::DocumentRef.new(source_id: "pl-wikisource", id: REF_ID, path: File.expand_path(path),
                                    metadata: { "dictionary" => SLUG })
      end

      def parse(document_ref)
        document = Nabu::DictionaryDocument.new(slug: SLUG, language: LANGUAGE, title: TITLE,
                                                canonical_path: document_ref.path)
        sections = section_texts(File.join(File.dirname(document_ref.path), SCANS_DIRNAME))
        stubs(document_ref.path).each do |stub|
          entry = self.class.build_entry(stub, sections)
          document << entry if entry
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "bruckner #{document_ref.id}: #{e.message}"
      end

      # One stub + the section map → an entry, or nil when the stub's
      # section is not on any held scan page (honest absence).
      def self.build_entry(stub, sections)
        headword = Normalize.nfc(stub.fetch("title").delete_prefix(STUB_PREFIX).strip)
        section = stub["section"].to_s.empty? ? headword : stub["section"]
        pieces = sections[section] or return nil

        body = Normalize.nfc(join_pieces(pieces))
        return nil if body.empty?

        folded = Normalize.search_form(headword.delete_prefix("*"), language: LANGUAGE)
        Nabu::DictionaryEntry.new(
          entry_id: headword, key_raw: headword, language: LANGUAGE, headword: headword,
          headword_folded: folded.nil? || folded.empty? ? headword : folded, body: body
        )
      end

      # Pieces in page order; a piece opening with the {{pk|…}} carry of a
      # hyphenated word joins with no space.
      def self.join_pieces(pieces)
        raw = +""
        pieces.each_with_index do |piece, index|
          raw << (index.zero? || piece.match?(/\A\s*\{\{\s*pk\s*\|/i) ? "" : " ") << piece
        end
        clean(raw)
      end

      # The scan-page wikitext → plain text: the hyphenation pair joins
      # ({{pp|a|b}} → ab, {{pk|…}} → ""), {{tab}} and furniture drop, a
      # correction template keeps its corrected reading, links keep their
      # label, bold/italic quotes drop.
      def self.clean(raw)
        text = raw.gsub(%r{<ref[^>]*/>}m, "").gsub(%r{<ref[^>]*>.*?</ref>}m, "").gsub(/<!--.*?-->/m, "")
        3.times do
          text = text.gsub(/\{\{([^{}]*)\}\}/) { render_template(::Regexp.last_match(1)) }
        end
        text.gsub(/\[\[(?:[^\[\]|]*\|)?([^\[\]]*)\]\]/) { ::Regexp.last_match(1) }
            .gsub(/'{2,}/, "").gsub("&#32;", " ").gsub("&nbsp;", " ")
            .gsub(%r{</?[a-z][^>]*>}i, "")
            # an unclosed section tag (upstream typo, censused on "kiermasz":
            # `<section end="kiermasz" .<section end="kiermasz" />`)
            .gsub(/<section\b[^<>]*/, "")
            .gsub(/[ \t\r\n]+/, " ").strip
      end

      def self.render_template(body)
        name, *args = body.split("|").map(&:strip)
        case name.to_s.downcase
        when "pp" then args.first(2).join
        when "pk", "tab", "tab2" then ""
        when "korekta" then args[1].to_s
        else args.last.to_s
        end
      end

      private

      def stubs(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}: unreadable Brückner stub index: #{e.message}"
      end

      # section name → its text pieces, in scan-page order.
      def section_texts(scans_dir)
        sections = Hash.new { |hash, key| hash[key] = [] }
        scan_envelopes(scans_dir).each do |envelope|
          body = envelope.fetch("wikitext").gsub(%r{<noinclude>.*?</noinclude>}m, "")
          body.scan(SECTION) { |name, text| sections[name] << text }
        end
        sections
      end

      def scan_envelopes(scans_dir)
        envelopes = Dir.glob(File.join(scans_dir, "*.json")).map { |path| read_scan(path) }
        envelopes.sort_by { |envelope| envelope.fetch("title")[/(\d+)\.\w+\z/, 1].to_i }
      end

      def read_scan(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}: unreadable Brückner scan envelope: #{e.message}"
      end
    end
  end
end
