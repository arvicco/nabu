# frozen_string_literal: true

require "nokogiri"
require_relative "../fetch/makhzan_fetch"
require_relative "alto_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # makhzan — OpenITI MAKHZAN, the Open Islamicate Texts Initiative's
    # Arabic-script HTR/OCR ground truth (Zenodo 10.5281/zenodo.19861912,
    # version 2026.1.2, 2026-04-28; Parkes Allen, Mullan, Nigst, Barber,
    # Shahid Khan, Seydi, Chen, Weng, Vogler, Murel, Eshera, Berg-Kirkpatrick,
    # Smith, Bowen Savant, Thomas Miller, Verkinderen): pages of Arabic,
    # Persian, Ottoman Turkish and Urdu prints and manuscripts, segmented and
    # transcribed line by line in eScriptorium and exported as ALTO v4. This
    # source takes the OTTOMAN TURKISH manuscripts: 30 manuscripts copied
    # 1438–1869 (the Volume Date of each — the copy, not the composition) in
    # European, American and Turkish libraries — the Dāsitān-i Kesik Baş in
    # six copies, menāqib of Emīr Sulṭān and Yaḥyā al-Mawṣulī, Manāfiʿ
    # al-nās on medicine, the Revnaḳ-ı Būstān on gardening, the Şemsiyye,
    # Gülşenī's Baleybelen grammar, Nabi's history, the Behcet el-fetāvā …
    #
    # == License (the record, read 2026-11-27)
    #
    # The Zenodo record's license field is cc-by-nc-sa-4.0 (Creative Commons
    # Attribution Non Commercial Share Alike 4.0 International); the release
    # notes and the deposited files state no other terms. NonCommercial →
    # class `nc` (the openiti precedent: the same initiative, the same grant).
    #
    # == Delivery grains (the whole record, censused 2026-11-27)
    #
    # The record serves three files: the 6.1 GB data zip, a metadata TSV (one
    # row per page: language, title, author, call number, repository, volume
    # date, type/form/genre, hand, transcriber, line counts) and a two-page
    # release-notes PDF. The zip holds 208 stored per-document zips
    # (Doc<id>.zip), each the page images (jpg/png) + one ALTO XML per page
    # + a METS.xml giving the page order.
    #
    # - TAKEN: one document per Ottoman manuscript (a TSV Language naming
    #   Ottoman Turkish — 30 documents, four of them mixed with Arabic,
    #   Persian or Baleybelen, LANG="mul" on those pages); one passage per
    #   transcribed TextLine, in METS page order and ALTO line order, cited
    #   <page part id>.<line ordinal on the page>. 248 pages / 3,762 lines —
    #   exactly the TSV's Transcribed Lines Count, page by page.
    # - REJECTED by rule (counted in discovery_skips): the 178 documents of
    #   the other languages (Arabic, Persian, Urdu, Malay, Javanese) — out of
    #   this source's scope, never fetched (their TSV rows are the specimen).
    # - REJECTED at the fetch: the page images (the zip's bulk), the release
    #   notes PDF (no text, no terms).
    # - Empty lines (segmented, untranscribed: 106 of 3,868 TextLines) mint
    #   nothing but keep their ordinal, so a citation never shifts.
    #
    # Reconciliation: 30 taken + 178 skipped by rule = the 208 documents the
    # zip and the TSV both list (and the release notes' "208 documents").
    #
    # == Overlap
    #
    # None with the held `openiti` corpus: that is the OpenITI mARkdown text
    # release (Arabic + Persian works, edition-based), this is diplomatic
    # line transcription of individual Ottoman manuscripts; nor with the UD
    # Ottoman treebanks (BOUN, DUDU — modern-edited sentences). Distinct
    # witnesses, never deduped.
    #
    # == Mined
    #
    # Per document (the TSV, constant across a manuscript's pages): title of
    # text/volume, author and compiler, call number and repository (the
    # HOLDING library — never the place claim), upstream language label and
    # the ALTO language codes, the hand (naskh, taliq, divani …), type/form/
    # genre (genre → kind, config/kind_map.yml), vetting status, transcriber
    # and vetter, the transcription layer, the paleographic note, the
    # dataset source; the Volume Date as the date (a year, "c. 1500" circa,
    # "17th c." a century); the Place of Origin as the place when upstream
    # names one ("Ottoman Empire" — polity grain, 4 of 30). Per passage: the
    # page part, the page image, the eScriptorium line id, block and line
    # types, and the page language when it is "mul".
    #
    # The fetch materializes nothing beside upstream's files: the workdir is
    # a plain tree (the TSV + Doc<id>/<member> as upstream names them, and
    # the fetch state), hashed whole — no materialized_paths declaration
    # applies (that rule is for untracked artifacts beside a git checkout).
    # Zenodo versions are immutable; a new version is a new record → manual.
    class Makhzan < Nabu::Adapter
      SLUG = "makhzan"
      LANGUAGE = "ota"
      SCOPE_LANGUAGE = "Ottoman Turkish"
      DOI = "10.5281/zenodo.19861912"
      METADATA_FILE = Nabu::MakhzanFetch::METADATA_FILE
      METS_NS = { "m" => "http://www.loc.gov/METS/", "x" => "http://www.w3.org/1999/xlink" }.freeze

      LICENSE = "CC BY-NC-SA 4.0 (the Zenodo record's license field cc-by-nc-sa-4.0, Creative Commons " \
                "Attribution Non Commercial Share Alike 4.0 International; verified 2026-11-27) — the ALTO text " \
                "only, the page images never taken"

      CREDIT = "OpenITI MAKHZAN, version 2026.1.2 (Open Islamicate Texts Initiative; Parkes Allen, Mullan, Nigst, " \
               "Barber, Shahid Khan, Seydi, Chen, Weng, Vogler, Murel, Eshera, Berg-Kirkpatrick, Smith, Bowen " \
               "Savant, Thomas Miller, Verkinderen), Zenodo 2026, doi:10.5281/zenodo.19861912."

      # The TSV's columns (its own header row, 30 columns).
      COLUMNS = {
        language: "Language", doc: "Doc ID", part: "Doc Part ID", layer: "Transcription Layer Name",
        hand: "Script", uri: "URI", volume_title: "Title of Volume", text_title: "Title of Text",
        origin: "Place of Origin", call_no: "Call No", repository: "Repository",
        repository_place: "Place of Repository", public_link: "Public Link", compiler: "Author/Compiler of Volume",
        compiler_dates: "Author/Compiler Dates", author: "Author of Text", date: "Volume Date", type: "Type",
        form: "Form", genre: "Genre", category: "Category", transcriber: "Transcription", vetter: "Vetting",
        notes: "Notes", dataset_source: "Dataset Source", transcribed: "Transcribed Lines Count"
      }.freeze

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "OpenITI MAKHZAN — Ottoman Turkish manuscript transcriptions",
          license: LICENSE, license_class: "nc",
          upstream_url: "https://doi.org/#{DOI}",
          parser_family: "alto-escriptorium", credit: CREDIT
        )
      end

      def self.parallel_parse? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "zenodo #{Nabu::MakhzanFetch::RECORD_ID}",
          zip_url: Nabu::MakhzanFetch.file_url(Nabu::MakhzanFetch::ZIP_FILE), metadata_url: nil,
          state_subdir: ".", state_file: Nabu::MakhzanFetch::STATE_FILE, liveness_only: true
        )]
      end

      # The TSV text → its rows as {column => value} hashes (tab-separated,
      # CRLF lines, no quoting — the census of the whole file).
      def self.rows(tsv)
        lines = tsv.split(/\r?\n/).reject(&:empty?)
        header = lines.shift.to_s.split("\t", -1)
        raise Nabu::ParseError, "#{METADATA_FILE}: no Doc ID column" unless header.include?(COLUMNS[:doc])

        lines.map { |line| header.zip(line.split("\t", -1)).to_h }
      end

      def self.in_scope?(row) = row[COLUMNS[:language]].to_s.split(",").map(&:strip).include?(SCOPE_LANGUAGE)

      # The document ids to take, in numeric order (the fetch's selection).
      def self.ottoman_ids(tsv)
        rows(tsv).select { |row| in_scope?(row) }.map { |row| row[COLUMNS[:doc]] }.uniq.sort_by(&:to_i)
      end

      # The Volume Date → {"not_before","not_after","raw"} (+ "circa"): a
      # year ("1569"), "c. <year>" (the year, flagged circa) or "<n>th c."
      # (the century); {"raw"} alone for anything else; nil when blank.
      def self.date_of(raw)
        return nil if raw.nil?

        text = raw.strip
        case text
        when /\A(\d{3,4})\z/ then { "not_before" => ::Regexp.last_match(1).to_i,
                                    "not_after" => ::Regexp.last_match(1).to_i, "raw" => text }
        when /\Ac\.\s*(\d{3,4})\z/ then { "not_before" => ::Regexp.last_match(1).to_i,
                                          "not_after" => ::Regexp.last_match(1).to_i, "raw" => text,
                                          "circa" => true }
        when /\A(\d{1,2})(?:st|nd|rd|th) c\.\z/
          century = ::Regexp.last_match(1).to_i
          { "not_before" => ((century - 1) * 100) + 1, "not_after" => century * 100, "raw" => text }
        else { "raw" => text }
        end
      end

      def initialize(fetcher: Nabu::MakhzanFetch.method(:sync!))
        super()
        @fetcher = fetcher
      end

      def fetch(workdir, progress: nil, force: false)
        result = @fetcher.call(
          dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME), select: self.class.method(:ottoman_ids),
          progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        )
        notes = if result.not_modified
                  "record #{Nabu::MakhzanFetch::RECORD_ID} v#{Nabu::MakhzanFetch::RECORD_VERSION} unchanged"
                else
                  "#{result.documents} documents: #{result.kept} files kept by Range " \
                    "(#{result.bytes} bytes in #{result.requests} requests), #{result.skipped} members never read"
                end
        Nabu::FetchReport.new(sha: result.sha, fetched_at: Time.now,
                              notes: [notes, attic_notes(result.atticked)].compact.join("; "))
      rescue Nabu::MakhzanFetch::Error, Nabu::RemoteZip::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        documents(workdir).sort_by { |doc_id, _rows| doc_id.to_i }.each do |doc_id, rows|
          next unless rows.any? { |row| self.class.in_scope?(row) }

          mets = File.join(workdir, "Doc#{doc_id}", "METS.xml")
          next unless File.file?(mets)

          yield Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{doc_id}", path: mets,
                                      metadata: { "doc_id" => doc_id })
        end
      end

      def discovery_skips(workdir)
        docs = documents(workdir)
        out_of_scope = docs.reject { |_id, rows| rows.any? { |row| self.class.in_scope?(row) } }
        missing = (docs.keys - out_of_scope.keys).reject { |id| File.file?(File.join(workdir, "Doc#{id}", "METS.xml")) }
        stray = Dir.glob("Doc*", base: workdir).map { |dir| dir.delete_prefix("Doc") } - docs.keys
        notes = []
        if out_of_scope.any?
          labels = out_of_scope.values.map { |rows| rows.first[COLUMNS[:language]] }.tally
          notes << "documents in other languages (out of scope, never fetched): " \
                   "#{labels.sort.map { |label, n| "#{label} #{n}" }.join(', ')}"
        end
        notes << "Ottoman documents the TSV lists with no METS on disk: #{missing.join(', ')}" if missing.any?
        notes << "document directories the TSV does not list: #{stray.map { |id| "Doc#{id}" }.join(', ')}" if stray.any?
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: out_of_scope.size,
                                          unrecognized: missing.size + stray.size, notes: notes)
      end

      def parse(document_ref)
        doc_id = document_ref.metadata.fetch("doc_id")
        workdir = File.dirname(document_ref.path, 2)
        rows = documents(workdir).fetch(doc_id) { raise Nabu::ParseError, "#{document_ref.id}: not in the TSV" }
        pages = page_files(document_ref.path, rows)
        parsed = pages.map do |part, path|
          [part, AltoParser.parse(SourceRead.utf8_file(path, label: SLUG), label: path)]
        end
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: title(rows.first, doc_id),
                                      metadata: metadata_for(doc_id, rows, parsed))
        parsed.each { |part, page| add_passages(document, part, page) }
        raise Nabu::ParseError, "#{document_ref.id}: no transcribed lines" if document.empty?

        document
      end

      private

      # {doc id => [rows]} in TSV order, memoized per workdir (one read per
      # adapter instance, never per document).
      def documents(workdir)
        @documents ||= {}
        @documents[workdir] ||= begin
          path = File.join(workdir, METADATA_FILE)
          if File.file?(path)
            self.class.rows(SourceRead.utf8_file(path, label: SLUG)).group_by do |row|
              row[COLUMNS[:doc]]
            end
          else
            {}
          end
        end
      end

      # [[part id, page xml path]] in METS structMap page order; the METS
      # pages and the TSV parts must be the same set.
      def page_files(mets_path, rows)
        mets = Nokogiri::XML(SourceRead.utf8_file(mets_path, label: SLUG)) { |config| config.strict.nonet }
        hrefs = mets.xpath("//m:fileGrp[@USE='export']/m:file", METS_NS).to_h do |file|
          [file["ID"], file.at_xpath("m:FLocat", METS_NS)&.attribute_with_ns("href", METS_NS["x"])&.value]
        end
        order = mets.xpath("//m:structMap//m:div[@TYPE='page']/m:fptr/@FILEID", METS_NS).map(&:value)
        files = order.filter_map { |id| hrefs[id] }
        pages = files.map { |file| [file[/_(\d+)\.xml\z/, 1], File.join(File.dirname(mets_path), file)] }
        check_pages!(mets_path, pages, rows)
        pages
      rescue Nokogiri::XML::SyntaxError => e
        raise Nabu::ParseError, "#{mets_path}: not well-formed METS (#{e.message})"
      end

      def check_pages!(mets_path, pages, rows)
        parts = rows.map { |row| row[COLUMNS[:part]] }
        unless pages.map(&:first).sort == parts.sort && pages.none? { |part, _| part.nil? }
          raise Nabu::ParseError, "#{mets_path}: METS pages #{pages.map(&:first).inspect} are not the TSV's " \
                                  "parts #{parts.inspect}"
        end
        absent = pages.reject { |_part, path| File.file?(path) }
        raise Nabu::ParseError, "#{mets_path}: page XML missing: #{absent.map(&:last).join(', ')}" if absent.any?
      end

      def title(row, doc_id)
        text = value(row, :text_title) || value(row, :volume_title) || "MAKHZAN document #{doc_id}"
        Nabu::Normalize.nfc(text)
      end

      def value(row, key)
        text = row[COLUMNS.fetch(key)].to_s.strip
        text.empty? ? nil : text
      end

      def values(rows, key) = rows.filter_map { |row| value(row, key) }.uniq

      def metadata_for(doc_id, rows, parsed)
        row = rows.first
        codes = parsed.filter_map { |_part, page| page.tags["Language"] }.uniq
        meta = {
          "doc_id" => doc_id, "doi" => DOI, "record_version" => Nabu::MakhzanFetch::RECORD_VERSION,
          "title_of_text" => value(row, :text_title), "title_of_volume" => value(row, :volume_title),
          "author" => value(row, :author), "compiler" => value(row, :compiler),
          "compiler_dates" => value(row, :compiler_dates), "call_no" => value(row, :call_no),
          "repository" => value(row, :repository), "repository_place" => value(row, :repository_place),
          "languages" => value(row, :language), "language_codes" => codes.empty? ? nil : codes.join(","),
          "hand" => value(row, :hand), "type" => value(row, :type), "form" => value(row, :form),
          "genre" => value(row, :genre), "category" => value(row, :category), "uri" => value(row, :uri),
          "public_link" => value(row, :public_link), "transcribers" => values(rows, :transcriber),
          "vetters" => values(rows, :vetter), "transcription_layers" => values(rows, :layer),
          "notes" => values(rows, :notes), "dataset_source" => value(row, :dataset_source),
          "date" => self.class.date_of(value(row, :date)), "place" => value(row, :origin),
          "pages" => parsed.size
        }
        meta.reject { |_key, val| val.nil? || (val.respond_to?(:empty?) && val.empty?) }
            .transform_values { |val| val.is_a?(String) ? Nabu::Normalize.nfc(val) : val }
      end

      def add_passages(document, part, page)
        page.lines.each do |line|
          next if line.text.empty?

          annotations = { "part" => part, "image" => page.file_name, "line_id" => line.id,
                          "block_type" => line.block_type, "line_type" => line.line_type,
                          "page_language" => (page.language if page.language != LANGUAGE) }.compact
          document << Nabu::Passage.new(urn: "#{document.urn}:#{part}.#{line.ordinal}", language: LANGUAGE,
                                        text: Nabu::Normalize.nfc(line.text), sequence: document.size,
                                        annotations: annotations)
        end
      end
    end
  end
end
