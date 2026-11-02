# frozen_string_literal: true

require "json"
require "digest"
require "fileutils"
require "uri"

module Nabu
  module Adapters
    # Paramāra epigraphy — the Zenodo community `paramara` of the Siddham
    # network (siddham.network): the inscriptions of the Paramāra kings of
    # Mālava and their neighbours (9th–14th c.), after H. V. Trivedi,
    # Inscriptions of the Paramāras, Chandellas, Kachchhapaghātas and two
    # minor dynasties (CII VII, 1978/1989), deposited one inscription per
    # record under the PennGlobal sigla PMR### (Pennsylvania's Global
    # epigraphy program). The sibling of `siddham` (the 2019 Gupta-age
    # EpiDoc deposit) in a different shape: plain text, not EpiDoc.
    #
    # == The delivery grains (community census 2026-11-02: 153 records)
    #
    #   text record     one PMR###.txt (114) — ACCEPTED, one document each
    #   EpiDoc hybrid   IN060027.txt (1): a Siddham EpiDoc file pasted under a
    #                   PMR14 header — the same inscription as PMR14.txt;
    #                   SKIPPED BY RULE (duplicate rendering)
    #   image / PDF     estampage photographs and scans (tif/tiff/jpg/pdf,
    #                   36 records incl. 3 cc-by-nc-nd) and 2 file-less
    #                   records — never fetched, SKIPPED BY RULE from the
    #                   saved listing (no text file)
    #
    # 114 + 1 + 38 = 153, the community's own total.
    #
    # == The text file
    #
    # A "Key: value" header (PennGlobal, Period, Location, Dynasty, King,
    # Language, Script, Text, Metres, Gist, Published reference; tab-
    # indented continuation lines), a "Text{1}" marker, the edition — line-
    # numbered "N. …" with indented continuations and plate/side headings
    # ("First Plate", "Second Plate: First Side") — then a dashed rule and
    # the "{n} …" footnotes. Passage = one numbered inscription line; its
    # text is the edition line verbatim (Trivedi's [restorations],
    # (corrections), "- -" lacunae) minus the {n} footnote markers, which
    # resolve into annotations["notes"]. One file (PMR21) has no header and
    # an uppercase "TEXT{1}" — the parser keys on the line grammar, never
    # on the header.
    #
    # == Identity
    #
    #   document urn  urn:nabu:paramara:<filename PMR id downcased> (pmr203,
    #                 pmr57 from "PMR 57.txt", pmr185a/pmr185b — one header)
    #   passage urn   <document-urn>:<line> (:b<n> on a repeated number —
    #                 the plates of a charter number continuously, censused)
    #
    # == Axes (mined)
    #
    # Title = the Zenodo record title. Dating: the Period field's leading
    # era-typed year (VS / Vikrama → vikrama, Śaka → saka) through the
    # shared config/eras.yml table; any other shape (a CE range "c.
    # 1000-1055 AC", "Undated", "Unclear") rides raw only. Place: the
    # Location field when it names a findspot (a value naming a museum or
    # "now …" is the present repository, kept as location only). Dynasty,
    # King, Metres, Gist and the published reference ride metadata.
    # Language: Sanskrit (san) on every record — the Language field reads
    # "Sanskrit" (+ "with local dialect"), and PMR84's "Gauḍī" names the
    # poetic style (rīti) of an 87-verse Sanskrit praśasti; the field rides
    # language_raw verbatim.
    #
    # == License
    #
    # Each record's own license field: cc-by-4.0 on all 114 text records
    # (the community's 3 cc-by-nc-nd records are image-only and not taken).
    # A text record with any other license maps to restricted. → attribution.
    class Paramara < Nabu::Adapter
      COMMUNITY = "paramara"
      API = "https://zenodo.org/api"
      LISTING = "records.json"
      PAGE_SIZE = 25
      DELAY = 1.0
      URN_PREFIX = "urn:nabu:paramara:"
      LANGUAGE = "san"

      HEADER = /\A(?<key>[A-Z][A-Za-z ]{1,30}):[ \t]*(?<value>.*)\z/
      TEXT_MARKER = /\Atext\s*(?:\{\d+\})?\s*\z/i
      # "1. text" — or "1 text" (PMR23 and nine more number without the dot).
      LINE = /\A\s*(?<n>\d+)\.?\s+(?<text>\S.*)\z/
      RULE = /\A\s*-{5,}\s*\z/
      FOOTNOTE = /\A\{(?<n>\d+)\}\s*(?<text>.*)\z/
      MARKER = /\{(\d+)\}/
      ERA_YEAR = /\A(?<era>VS|V\.\s?S\.|Vikrama(?:\s+(?:year|saṃvat|samvat))?|Śaka|Saka)\s+(?<year>\d{3,4})\b/i
      REPOSITORY = /museum|\bnow\b/i

      MANIFEST = Nabu::SourceManifest.new(
        id: "paramara",
        name: "Paramāra epigraphy — the Siddham network's Zenodo community (PennGlobal PMR texts)",
        license: "CC BY 4.0 — each Zenodo record's license field (cc-by-4.0 on all 114 text " \
                 "records, community `paramara`, censused 2026-11-02). Cite the record's creators, " \
                 "the Siddham network (siddham.network) and H. V. Trivedi, Inscriptions of the " \
                 "Paramāras, Chandellas, Kachchhapaghātas and two minor dynasties (CII VII)",
        license_class: "attribution",
        upstream_url: "https://zenodo.org/communities/paramara",
        parser_family: "paramara-text"
      )

      def self.manifest
        MANIFEST
      end

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "zenodo community paramara", zip_url: "#{API}/communities/#{COMMUNITY}/records?size=1",
          metadata_url: nil, state_subdir: "", state_file: LISTING, liveness_only: true
        )]
      end

      # Text record → its single .txt key, else nil.
      def self.text_file(record)
        Array(record["files"]).map { |file| file["key"] }.find { |key| key.downcase.end_with?(".txt") }
      end

      def initialize(delay: DELAY, http: Nabu::ZipFetch.default_http)
        super()
        @delay = delay
        @http = http
      end

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        text_records(workdir).each do |record, path|
          next if epidoc_hybrid?(path)

          yield Nabu::DocumentRef.new(source_id: manifest.id, id: urn_for(path), path: File.expand_path(path),
                                      metadata: record_metadata(record))
        end
      end

      def discovery_skips(workdir)
        notes = listing(workdir).reject { |record| self.class.text_file(record) }.map do |record|
          files = Array(record["files"]).map { |file| file["key"] }
          "record #{record['id']}: no text file (#{files.empty? ? 'no files' : files.join(', ')})"
        end
        text_records(workdir).each do |record, path|
          if epidoc_hybrid?(path)
            notes << "record #{record['id']}: #{File.basename(path)} is an EpiDoc rendering under a PMR header " \
                     "(the PMR text record covers the inscription)"
          end
        end
        DiscoverySkips.new(skipped_by_rule: notes.size, unrecognized: 0, notes: notes)
      end

      def parse(document_ref)
        parsed = parse_text(File.read(document_ref.path, encoding: Encoding::UTF_8), document_ref.path)
        build_document(parsed, document_ref)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Page the community listing (saved whole as records.json), then
      # download every text record's .txt into <record id>/ — once per
      # file (a present file whose md5 matches the listing is kept).
      # Never deletes: a record that vanishes upstream keeps its file.
      def fetch(workdir, progress: nil, force: false)
        _ = force
        records = fetch_listing
        FileUtils.mkdir_p(workdir)
        File.write(File.join(workdir, LISTING), JSON.pretty_generate(records))
        fetched = records.count { |record| downloaded_text?(workdir, record, progress) }
        FetchReport.new(sha: Digest::SHA256.hexdigest(JSON.generate(records)), fetched_at: Time.now,
                        notes: "#{records.size} records listed; #{fetched} text files downloaded")
      rescue Faraday::Error, JSON::ParserError, KeyError => e
        raise Nabu::FetchError, "paramara fetch failed into #{workdir}: #{e.message}"
      end

      private

      class FetchFailure < Nabu::Error
      end
      private_constant :FetchFailure

      def fetch_listing
        records = []
        page = 1
        loop do
          body = get("#{API}/communities/#{COMMUNITY}/records?size=#{PAGE_SIZE}&page=#{page}&sort=oldest")
          hits = JSON.parse(body).fetch("hits")
          records.concat(hits.fetch("hits"))
          break if hits.fetch("hits").empty? || records.size >= hits.fetch("total")

          page += 1
          pause
        end
        records.sort_by { |record| record["id"].to_i }
      end

      def downloaded_text?(workdir, record, progress)
        key = self.class.text_file(record) or return false
        file = record["files"].find { |entry| entry["key"] == key }
        dest = File.join(workdir, record["id"].to_s, key)
        return false if File.exist?(dest) && md5_matches?(dest, file["checksum"])

        progress&.call("paramara: #{record['id']}/#{key}")
        escaped = URI.encode_www_form_component(key).gsub("+", "%20")
        body = get("#{API}/records/#{record['id']}/files/#{escaped}/content")
        FileUtils.mkdir_p(File.dirname(dest))
        File.binwrite(dest, body)
        pause
        true
      end

      def md5_matches?(path, checksum)
        checksum.to_s.start_with?("md5:") && Digest::MD5.file(path).hexdigest == checksum.delete_prefix("md5:")
      end

      def get(url)
        response, = Nabu::RedirectFollow.get(url, http: @http, error: FetchFailure)
        response.body
      rescue FetchFailure => e
        raise Nabu::FetchError, "paramara fetch failed: #{e.message}"
      end

      def pause
        sleep(@delay) if @delay.positive?
      end

      def listing(workdir)
        path = File.join(workdir, LISTING)
        File.exist?(path) ? JSON.parse(File.read(path)) : []
      end

      # [record, path] for each listed text record whose file is present.
      def text_records(workdir)
        present = listing(workdir).filter_map do |record|
          key = self.class.text_file(record) or next
          path = File.join(workdir, record["id"].to_s, key)
          [record, path] if File.exist?(path)
        end
        present.sort_by { |_record, path| urn_for(path) }
      end

      def epidoc_hybrid?(path)
        head = File.read(path, 4096).to_s.force_encoding(Encoding::UTF_8).scrub
        head.start_with?("SIDDHAM:") || head.include?("<TEI ")
      end

      # The filename's PMR id (PMR203.txt, "PMR 57.txt", PMR185A.txt) — the
      # depositor's own per-file identity; the two halves of PMR185 share
      # one PennGlobal header but not a filename.
      def urn_for(path)
        "#{URN_PREFIX}#{File.basename(path, '.*').delete(' ').downcase}"
      end

      def record_metadata(record)
        metadata = record["metadata"] || {}
        {
          "record_id" => record["id"].to_s,
          "title" => metadata["title"],
          "doi" => metadata["doi"] || record["doi"],
          "license_id" => metadata.dig("license", "id"),
          "creators" => Array(metadata["creators"]).filter_map { |creator| creator["name"] },
          "publication_date" => metadata["publication_date"]
        }.compact
      end

      # -- the text grammar -------------------------------------------------

      Parsed = Data.define(:header, :lines, :notes)
      private_constant :Parsed

      def parse_text(text, path)
        header = {}
        lines = []
        body = []
        notes = {}
        phase = :header
        current_key = nil
        section = nil
        text.each_line(chomp: true) do |raw|
          line = raw.sub(/\s+\z/, "")
          case phase
          when :header
            if TEXT_MARKER.match?(line.strip)
              phase = :body
            elsif (match = HEADER.match(line)) && !LINE.match?(line)
              current_key = match[:key].strip
              header[current_key] = match[:value].strip
            elsif current_key && raw.start_with?("\t", " ") && !line.strip.empty?
              header[current_key] = "#{header[current_key]} #{line.strip}".strip
            elsif LINE.match?(line)
              phase = :body
              section = add_line(lines, line, section)
            end
          when :body
            if RULE.match?(line)
              phase = :notes
            else
              body << line.strip unless line.strip.empty?
              section = add_line(lines, line, section)
            end
          when :notes
            if (match = FOOTNOTE.match(line.strip))
              current_key = match[:n]
              notes[current_key] = match[:text].strip
            elsif current_key && !line.strip.empty?
              notes[current_key] = "#{notes[current_key]} #{line.strip}"
            end
          end
        end
        lines = unnumbered(body) if lines.empty?
        raise ParseError, "#{path}: no inscription lines" if lines.empty?

        Parsed.new(header: header, lines: lines, notes: notes)
      end

      # An edition laid out by verse without line numbers (PMR47–49): each
      # body line is a passage, cited positionally s<n> (the house segment
      # fallback) and flagged unnumbered.
      def unnumbered(body)
        body.each_with_index.map { |text, index| { n: "s#{index + 1}", text: text, section: nil, unnumbered: true } }
      end

      # Append/extend the line list; answer the current section heading.
      def add_line(lines, line, section)
        return section if line.strip.empty?

        if (match = LINE.match(line))
          lines << { n: match[:n], text: match[:text].strip, section: section }
        elsif line.start_with?(" ", "\t") && !lines.empty?
          lines.last[:text] = "#{lines.last[:text]} #{line.strip}"
        else
          section = line.strip
        end
        section
      end

      def build_document(parsed, document_ref)
        metadata = document_metadata(parsed.header, document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: metadata["title"],
          canonical_path: document_ref.path, metadata: metadata,
          license_override: (metadata["license_id"] == "cc-by-4.0" ? nil : "restricted")
        )
        seen = Hash.new(0)
        parsed.lines.each do |line|
          seen[line[:n]] += 1
          ref = seen[line[:n]] > 1 ? "#{line[:n]}:b#{seen[line[:n]]}" : line[:n]
          text = squeeze(line[:text].gsub(MARKER, ""))
          next if text.empty?

          document << Nabu::Passage.new(urn: "#{document_ref.id}:#{ref}", language: LANGUAGE,
                                        text: Normalize.nfc(text), sequence: document.size,
                                        annotations: line_annotations(line, parsed.notes))
        end
        raise ParseError, "#{document_ref.path}: no readable inscription lines" if document.empty?

        document
      end

      def line_annotations(line, notes)
        annotations = { "line" => line[:n] }
        annotations["section"] = line[:section] if line[:section]
        annotations["unnumbered"] = true if line[:unnumbered]
        refs = line[:text].scan(MARKER).flatten
        unless refs.empty?
          annotations["notes"] = refs.to_h { |n| [n, Normalize.nfc(notes[n].to_s.strip)] }.reject { |_n, v| v.empty? }
        end
        annotations
      end

      def document_metadata(header, document_ref)
        record = document_ref.metadata
        title = record["title"] && Normalize.nfc(squeeze(record["title"]))
        location = header["Location"]
        {
          "siglum" => header["PennGlobal"],
          "title" => title,
          "record_id" => record["record_id"],
          "doi" => record["doi"],
          "license_id" => record["license_id"],
          "creators" => (record["creators"] unless record["creators"].to_a.empty?),
          "period" => header["Period"],
          "date" => date_envelope(header["Period"]),
          "location" => location,
          "place" => (location if location && !REPOSITORY.match?(location)),
          "dynasty" => header["Dynasty"],
          "king" => header["King"],
          "language_raw" => header["Language"],
          "script_raw" => header["Script"],
          "text_form" => header["Text"],
          "metres" => header["Metres"] || header["Metre"] || header["Meters"],
          "gist" => header["Gist"],
          "published_reference" => header["Published reference"]
        }.compact.transform_values { |value| value.is_a?(String) ? Normalize.nfc(value) : value }
      end

      def date_envelope(period)
        match = ERA_YEAR.match(period.to_s.strip) or return nil
        era = Nabu::Eras.default.resolve(match[:era].sub(/\s+(?:year|saṃvat|samvat)\z/i, "")) or return nil
        Nabu::Eras.default.to_ce(era, Integer(match[:year], 10)).to_date_bounds.merge("raw" => period.strip)
      end

      def squeeze(text) = text.to_s.gsub(/\s+/, " ").strip
    end
  end
end
