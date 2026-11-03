# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "tmpdir"

require_relative "../file_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # vHMML Reading Room — the manuscript catalogue of the Hill Museum &
    # Manuscript Library (Collegeville, MN): the cataloguing of the
    # libraries HMML has photographed, from Austrian abbeys to the Syriac
    # churches of Iraq, Turkey and Lebanon, the Ethiopian monasteries and
    # the Arabic collections of Timbuktu. This source takes the SYRIAC +
    # ETHIOPIC slice — the manuscript metadata layer the Ge'ez and Syriac
    # shelves lack — with each record's incipits as passages.
    #
    # == The channel and its identity
    #
    # HMML regenerates the whole dataset every Sunday 01:00 CT (stated by
    # HMML by email, 2026-11-02; the data portal says "updated weekly") at
    # one URL, DATASET_URL: a 50 MB zip holding one 757 MB JSON member.
    # The fetch is a FileFetch of that zip into dataset/ (conditional GET
    # on Last-Modified, the zip's sha256 as the pin, the previous
    # generation's state replaced, never silently overwritten — a 304
    # leaves everything as it was), then the slice is cut from the held
    # zip into scope/ (materialized_paths): records.jsonl (the taken
    # records, each line upstream's record bytes with the array comma
    # dropped) and census.json (the generation's Last-Modified and sha256
    # beside the slice counts). The slice is re-cut only when the zip's
    # sha256 differs from the one census.json names.
    #
    # == Grains (census of the 2026-11-01 generation)
    #
    # 263,989 records + one trailing empty `{}` (skipped by rule). The
    # slice rule: any part with a Syriac or Ethiopic writing system, or
    # any content item in Syriac, Ge'ez or Amharic — 18,892 records;
    # 245,097 are outside it (counted on every discovery as skipped by
    # rule — a later slice, never dropped silently). Document = one
    # record (urn:nabu:hmml-reading-room:<vHMML id>); the record's parts,
    # content items, repository, genres, dates and origin ride metadata
    # whole. Passage = a content item WITH an incipit (11,392 in the
    # slice, 5,338 documents): text = the incipit verbatim, urn
    # …:<part>.<item>. The 13,554 records without an incipit are
    # metadata-only documents (text_layer none).
    #
    # == Languages
    #
    # An incipit's language is its item's first catalogued language that
    # maps (LANGUAGES) AND fits the incipit's script: Syriac → syc, Ge'ez
    # → gez, Amharic → amh, Arabic Garshuni → ara-Syrc (Arabic in Syriac
    # script), Arabic → ara. Anything else — Neo-Aramaic (no registry
    # anchor yet), Turkish Garshuni, Latin-script incipits — skips by
    # rule, named in the document's skipped_incipits. The cataloguer's
    # language is the claim: an item catalogued Syriac whose incipit
    # reads as Garshuni stays syc (declared coarse).
    #
    # == License
    #
    # The data portal and vhmml.org/terms (read 2026-11-02): "The
    # manuscript metadata in vHMML Reading Room is available for reuse
    # under a Creative Commons 4.0 License: Creative Commons Attribution
    # 4.0 International License (CC BY 4.0)" → attribution. Images are
    # the holding institutions' and never taken.
    class HmmlReadingRoom < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "hmml-reading-room",
        name: "vHMML Reading Room — the Syriac and Ethiopic manuscript catalogue",
        license: "CC BY 4.0 — \"The manuscript metadata in vHMML Reading Room is available for reuse " \
                 "under a Creative Commons 4.0 License: Creative Commons Attribution 4.0 International " \
                 "License (CC BY 4.0).\" (vhmml.org/terms; the data portal). Images not taken",
        license_class: "attribution",
        upstream_url: "https://www.vhmml.org/dataPortal/dataset",
        parser_family: "vhmml-json"
      )

      SLUG = "hmml-reading-room"
      DATASET_URL = "https://www.vhmml.org/datasets/vhmml_rr_fulldata.zip"
      DATASET_DIR = "dataset"
      ZIP_NAME = "vhmml_rr_fulldata.zip"
      MEMBER = "vhmml_rr_fulldata.json"
      SCOPE_DIR = "scope"
      RECORDS = "records.jsonl"
      CENSUS = "census.json"

      SLICE_SCRIPTS = %w[Syriac Ethiopic].freeze
      SLICE_LANGUAGES = ["Syriac", "Ge'ez", "Amharic"].freeze

      # Catalogued language → tag, with the script its incipit must show.
      LANGUAGES = {
        "Syriac" => ["syc", :syriac], "Ge'ez" => ["gez", :ethiopic], "Amharic" => ["amh", :ethiopic],
        "Arabic Garshuni" => ["ara-Syrc", :syriac], "Arabic" => ["ara", :arabic]
      }.freeze
      WRITING_SYSTEM_FALLBACK = { "Syriac" => "syc", "Ethiopic" => "gez" }.freeze
      SCRIPTS = { syriac: /\p{Syriac}/, ethiopic: /\p{Ethiopic}/, arabic: /\p{Arabic}/ }.freeze

      def self.manifest = MANIFEST

      def self.materialized_paths = [SCOPE_DIR]

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "vhmml_rr_fulldata.zip", zip_url: DATASET_URL, metadata_url: nil,
          state_subdir: DATASET_DIR, state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      def fetch(workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
        result = Nabu::FileFetch.sync!(
          url: DATASET_URL, dir: File.join(workdir, DATASET_DIR), filename: ZIP_NAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        materialize!(workdir, progress: progress)
        FetchReport.new(sha: result.sha, fetched_at: Time.now,
                        notes: result.not_modified ? "generation unchanged (304)" : nil)
      rescue Nabu::FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "hmml-reading-room: #{e.message}"
      end

      # Cut the slice from the held zip (unless census.json already names
      # this zip's sha256). Unzips into a private temp dir, streams the
      # member line by line, writes scope/ atomically.
      def materialize!(workdir, progress: nil)
        zip = File.join(workdir, DATASET_DIR, ZIP_NAME)
        raise Nabu::FetchError, "hmml-reading-room: no held dataset at #{zip}" unless File.file?(zip)

        sha = Digest::SHA256.file(zip).hexdigest
        return if census(workdir)["dataset_sha256"] == sha && File.file?(records_path(workdir))

        progress&.call("Cutting the Syriac + Ethiopic slice from #{ZIP_NAME}…\n")
        Dir.mktmpdir("hmml-rr") do |tmp|
          Nabu::Shell.run("unzip", "-o", "-q", zip, MEMBER, "-d", tmp)
          staged = File.join(tmp, SCOPE_DIR)
          FileUtils.mkdir_p(staged)
          counts = cut_slice(File.join(tmp, MEMBER), File.join(staged, RECORDS))
          pin = { "dataset_sha256" => sha, "dataset_last_modified" => fetch_state(workdir)["last_modified"],
                  "dataset_url" => DATASET_URL }
          File.write(File.join(staged, CENSUS), JSON.pretty_generate(counts.merge(pin)))
          FileUtils.rm_rf(File.join(workdir, SCOPE_DIR))
          FileUtils.mv(staged, File.join(workdir, SCOPE_DIR))
        end
      end

      # One ref per slice record, carrying its byte span in records.jsonl.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        path = records_path(workdir)
        return unless File.file?(path)

        offset = 0
        slice_bytes(path).each_line do |line|
          id = line[/\A\{"id":(\d+),/, 1] or raise Nabu::ParseError, "#{path}: a slice line without an id"
          block.call(Nabu::DocumentRef.new(
                       source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}", path: File.expand_path(path),
                       metadata: { "offset" => offset, "length" => line.bytesize }
                     ))
          offset += line.bytesize
        end
      end

      def discovery_skips(workdir)
        counts = census(workdir)
        return Nabu::Adapter::DiscoverySkips.new if counts.empty?

        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: counts.fetch("out_of_slice", 0) + counts.fetch("empty_records", 0),
          notes: ["#{counts['out_of_slice']} records outside the Syriac + Ethiopic slice; " \
                  "#{counts['empty_records']} empty record(s)"]
        )
      end

      def parse(document_ref)
        bytes = SourceRead.slice(slice_bytes(document_ref.path), offset: document_ref.metadata.fetch("offset"),
                                                                 length: document_ref.metadata.fetch("length"),
                                                                 what: "#{document_ref.path}: record")
        record = JSON.parse(SourceRead.utf8(bytes, label: document_ref.id))
        build(document_ref, record)
      rescue JSON::ParserError, KeyError, Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.id}: #{e.message}"
      end

      # The slice rule over one parsed record.
      def self.in_slice?(record)
        parts = Array(record["parts"])
        systems = parts.flat_map { |p| p["writingSystem"].to_s.split(/,\s*/) } +
                  record["writingSystem"].to_s.split(/,\s*/)
        return true if systems.intersect?(SLICE_SCRIPTS)

        languages = parts.flat_map { |p| Array(p["contents"]) }.flat_map { |c| language_names(c) }
        languages.intersect?(SLICE_LANGUAGES)
      end

      def self.language_names(item) = Array(item["languages"]).filter_map { |l| l["name"] }

      private

      def records_path(workdir) = File.join(workdir, SCOPE_DIR, RECORDS)

      def census(workdir)
        path = File.join(workdir, SCOPE_DIR, CENSUS)
        File.file?(path) ? JSON.parse(SourceRead.utf8_file(path, label: SLUG)) : {}
      end

      # The FileFetch state of the held generation (its Last-Modified).
      def fetch_state(workdir)
        path = File.join(workdir, DATASET_DIR, Nabu::FileFetch::STATE_FILE)
        File.file?(path) ? JSON.parse(SourceRead.utf8_file(path, label: SLUG)) : {}
      end

      def slice_bytes(path)
        @slice_bytes ||= {}
        @slice_bytes[path] ||= SourceRead.utf8_file(path, label: SLUG)
      end

      # Stream the member (a JSON array, one record per line) into the
      # slice file; returns the counts census.json records.
      def cut_slice(member, out_path)
        counts = { "records" => 0, "taken" => 0, "out_of_slice" => 0, "empty_records" => 0 }
        taken = []
        File.foreach(member) do |line|
          body = line.chomp.delete_prefix("[").delete_suffix("]").delete_suffix(",")
          next if body.strip.empty?

          record = JSON.parse(body)
          next counts["empty_records"] += 1 if record.empty?

          counts["records"] += 1
          self.class.in_slice?(record) ? taken << body : counts["out_of_slice"] += 1
        end
        counts["taken"] = taken.size
        File.write(out_path, taken.map { |body| "#{body}\n" }.join)
        counts
      rescue JSON::ParserError => e
        raise Nabu::FetchError, "hmml-reading-room: the dataset member is not one record per line (#{e.message})"
      end

      def build(document_ref, record)
        parts = Array(record["parts"])
        skipped = []
        passages = incipit_passages(document_ref.id, parts, skipped)
        document = Nabu::Document.new(
          urn: document_ref.id, language: document_language(record, parts, passages),
          title: title(record, parts), canonical_path: document_ref.path,
          metadata: document_metadata(record, parts, skipped, passages.empty?)
        )
        passages.each { |p| document << p }
        document
      end

      def incipit_passages(doc_urn, parts, skipped)
        cites = item_cites(parts)
        sequence = 0
        parts.each_with_index.flat_map do |part, pi|
          Array(part["contents"]).each_with_index.filter_map do |item, ii|
            incipit = item["incipit"].to_s.strip
            next if incipit.empty?

            cite = cites.fetch([pi, ii])
            language = incipit_language(item, incipit)
            if language.nil?
              skipped << { "item" => cite, "languages" => self.class.language_names(item),
                           "reason" => "no lect mapping for the item's language" }
              next
            end
            sequence += 1
            Nabu::Passage.new(urn: "#{doc_urn}:#{cite}", language: language,
                              text: SourceRead.nfc(incipit, language: language), sequence: sequence,
                              annotations: item_annotations(item, part))
          end
        end
      end

      # "<partNumber>.<itemNumber>" where both exist and are unique in the
      # record; otherwise "i<content id>" (upstream's own item id).
      def item_cites(parts)
        raw = {}
        parts.each_with_index do |part, pi|
          Array(part["contents"]).each_with_index do |item, ii|
            raw[[pi, ii]] = [part["partNumber"], item["itemNumber"], item["id"]]
          end
        end
        plain = raw.transform_values { |pn, inum, _| pn && inum ? "#{pn}.#{inum}" : nil }
        counts = plain.values.compact.tally
        raw.to_h do |key, (_, _, id)|
          cite = plain[key]
          [key, cite && counts[cite] == 1 ? cite : "i#{id}"]
        end
      end

      def incipit_language(item, incipit)
        self.class.language_names(item).each do |name|
          tag, script = LANGUAGES[name]
          return tag if tag && incipit.match?(SCRIPTS.fetch(script))
        end
        nil
      end

      def document_language(record, parts, passages)
        return passages.first.language unless passages.empty?

        items = parts.flat_map { |p| Array(p["contents"]) }
        mapped = items.flat_map { |i| self.class.language_names(i) }.filter_map { |n| LANGUAGES.dig(n, 0) }.first
        return mapped if mapped

        systems = parts.flat_map { |p| p["writingSystem"].to_s.split(/,\s*/) } +
                  record["writingSystem"].to_s.split(/,\s*/)
        systems.filter_map { |s| WRITING_SYSTEM_FALLBACK[s] }.first || "und"
      end

      def title(record, parts)
        label = clean(record["shelfMark"]) || clean(record["hmmlProjectNumber"]) || "vHMML #{record['id']}"
        first = parts.flat_map { |p| Array(p["contents"]) }.filter_map { |i| clean(i["provisionalTitle"]) }.first
        first ||= clean(record["title"])
        Normalize.nfc(first ? "#{first} (#{label})" : label)
      end

      def document_metadata(record, parts, skipped, metadata_only)
        genres = Array(record["genres"]).filter_map { |g| clean(g["name"]) }
        {
          "vhmml_id" => record["id"], "purl" => record["PURL"],
          "hmml_project_number" => clean(record["hmmlProjectNumber"]),
          "shelf_mark" => clean(record["shelfMark"]), "object_type" => record["objectType"],
          "repository" => repository(record), "collection" => clean(record["collection"]),
          "current_status" => clean(record["currentStatus"]), "processed_by" => clean(record["processedBy"]),
          "acknowledgments" => clean(record["acknowledgments"]), "rights" => record["rights"],
          "last_update" => clean(record["lastUpdateDisplay"]),
          "viewable_online" => record["viewableOnline"], "access_restriction" => clean(record["accessRestriction"]),
          "surrogate_format" => clean(record.dig("surrogateFormat", "name")),
          "extents" => Array(record["extents"]).filter_map { |e| clean(e["folioImported"] || e["displayName"]) },
          "genres" => genres, "genre_uris" => Array(record["genres"]).filter_map { |g| g["uri"] },
          "subjects" => Array(record["subjects"]).filter_map { |s| clean(s["name"]) },
          "notes" => html_text(record["notes"]), "bibliography" => html_text(record["bibliography"]),
          "collation" => html_text(record["collation"]), "provenance" => html_text(record["provenance"]),
          "parts" => parts.map { |p| part_metadata(p) },
          "date" => date_envelope(parts), "place" => origin(parts),
          "skipped_incipits" => (skipped unless skipped.empty?),
          "text_layer" => ("none" if metadata_only),
          "facets" => facets(record, genres)
        }.reject { |_, v| v.nil? || v == [] || v == {} }
      end

      def repository(record)
        {
          "name" => clean(record.dig("repository", "name")), "city" => clean(record.dig("city", "name")),
          "country" => clean(record.dig("country", "name")),
          "viaf" => record.dig("repository", "authorityUriVIAF"), "lc" => record.dig("repository", "authorityUriLC")
        }.compact
      end

      def part_metadata(part)
        {
          "part_number" => part["partNumber"], "type" => part["type"], "centuries" => part["centuries"],
          "century" => clean(part["centuryImported"]), "begin_date" => part["beginDate"],
          "end_date" => part["endDate"], "date_precise_year" => part["datePreciseYear"],
          "date_precise_month" => part["datePreciseMonth"], "date_precise_day" => part["datePreciseDay"],
          "native_date" => clean(part["nativeDatePrecise"]), "writing_system" => clean(part["writingSystem"]),
          "script" => clean(part["script"]), "support" => clean(part["support"]),
          "country_of_origin" => name_of(part["countryOfOrigin"]), "city_of_origin" => name_of(part["cityOfOrigin"]),
          "region_of_origin" => name_of(part["regionOfOrigin"]), "scribe" => clean(part["scribe"]),
          "decoration" => html_text(part["decoration"]), "layout" => html_text(part["layout"]),
          "contents" => Array(part["contents"]).map { |item| item_metadata(item) }
        }.reject { |_, v| v.nil? || v == [] }
      end

      def item_metadata(item)
        {
          "item_number" => item["itemNumber"], "location" => clean(item["itemLocation"]),
          "title" => clean(item["provisionalTitle"]), "title_native" => clean(item["titleNs"]),
          "alternate_titles" => Array(item["alternateTitles"]).filter_map { |t| clean(t) },
          "uniform_title" => clean(item.dig("uniformTitle", "name")),
          "languages" => self.class.language_names(item), "contributors" => contributors(item),
          "incipit" => clean(item["incipit"]), "explicit" => clean(item["explicit"]),
          "rubric" => clean(item["rubric"]), "notes" => html_text(item["itemNotes"])
        }.reject { |_, v| v.nil? || v == [] }
      end

      def item_annotations(item, part)
        {
          "title" => clean(item["provisionalTitle"]), "title_native" => clean(item["titleNs"]),
          "uniform_title" => clean(item.dig("uniformTitle", "name")),
          "location" => clean(item["itemLocation"]), "languages" => self.class.language_names(item),
          "contributors" => contributors(item), "explicit" => clean(item["explicit"]),
          "rubric" => clean(item["rubric"]), "script" => clean(part["script"])
        }.reject { |_, v| v.nil? || v == [] }
      end

      def contributors(item)
        Array(item["contentContributors"]).filter_map do |c|
          name = clean(c.dig("contributor", "displayName") || c.dig("contributor", "name")) or next
          { "role" => c["type"], "name" => name, "viaf" => c.dig("contributor", "authorityUriVIAF") }.compact
        end
      end

      # The record's date envelope across its parts (upstream's own
      # begin/end years; the century label rides raw).
      def date_envelope(parts)
        begins = parts.filter_map { |p| p["beginDate"] }
        ends = parts.filter_map { |p| p["endDate"] }
        return nil if begins.empty? && ends.empty?

        raw = parts.filter_map { |p| clean(p["centuryImported"]) }.uniq.join("; ")
        { "not_before" => begins.min, "not_after" => ends.max, "raw" => (raw unless raw.empty?) }.compact
      end

      # The writing place a part's cataloguer recorded — its city, else
      # its country. The holding repository is NOT an origin.
      def origin(parts)
        parts.each do |p|
          place = name_of(p["cityOfOrigin"]) || name_of(p["countryOfOrigin"])
          return place if place
        end
        nil
      end

      def facets(record, genres)
        systems = Array(record["parts"]).flat_map { |p| p["writingSystem"].to_s.split(/,\s*/) }.uniq
        {
          "object_type" => record["objectType"] && { "value" => record["objectType"] },
          "genre" => (genres.empty? ? nil : { "values" => genres }),
          "writing_system" => (systems.empty? ? nil : { "values" => systems }),
          "holding_country" => clean(record.dig("country", "name"))&.then { |c| { "value" => c } }
        }.compact
      end

      def name_of(value) = clean(value.is_a?(Hash) ? value["name"] : value)

      def html_text(value)
        text = value.to_s.gsub(%r{<br\s*/?>|</p>}i, "\n").gsub(/<[^>]+>/, "")
        text = text.gsub("&nbsp;", " ").gsub("&amp;", "&").gsub("&lt;", "<").gsub("&gt;", ">")
        lines = text.split("\n").map { |l| l.gsub(/[[:space:]]+/, " ").strip }.reject(&:empty?)
        lines.empty? ? nil : Normalize.nfc(lines.join("\n"))
      end

      def clean(value)
        return nil if value.nil?

        text = value.to_s.gsub(/[[:space:]]+/, " ").strip
        text.empty? ? nil : Normalize.nfc(text)
      end
    end
  end
end
