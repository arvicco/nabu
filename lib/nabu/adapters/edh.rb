# frozen_string_literal: true

require "csv"

module Nabu
  module Adapters
    # The EDH adapter (P17-2; docs/edh-survey.md) — the Epigraphic Database
    # Heidelberg, 82,450 Latin inscriptions, the third documentary shelf
    # beside the papyri and the tablets. A thin composition of the
    # EdhEpidocParser family with EDH's Open Data dump layout: nine EpiDoc
    # zips (Nabu::ZipFetch, the ORACC multi-artifact choreography) plus the
    # two corpus-wide CSVs (Nabu::FileFetch) that carry what the EpiDoc
    # LACKS — the per-record language, the raw facet codes, the Trismegistos
    # numbers, and the 93,646-row structured prosopography.
    #
    # == Layout
    #
    #   <workdir>/epidoc/<HD range>/HDnnnnnn.xml   (nine flat zip trees)
    #   <workdir>/text/edh_data_text.csv           (75 cols; nl_text/atext/…)
    #   <workdir>/pers/edh_data_pers.csv           (23 cols; one row/person)
    #
    # Each CSV gets its OWN subdir because FileFetch is single-file-per-dir
    # (anything else in its dir reads as an upstream deletion).
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:edh:hd<number> — HD numbers are the stable id every
    # aggregator (EAGLE, Trismegistos, EDCS) keys on. The 2021 dumps' own
    # <idno type="URI"> points at a STAGING host (survey §1), so nothing but
    # the localID is trusted; the parser mints from it and cross-checks, so
    # ref.id == parse(ref).urn (the sync-breaker conformance identity).
    #
    # == Language: from the CSV, never the EpiDoc header (the verified trap)
    #
    # Every EDH record's <langUsage> lists en/de/lat — Greek editions
    # included (survey: zero of 12,747 inspected files declare grc). The
    # per-record truth is the CSV nl_text column: any code containing L →
    # lat, else G → grc, else "und" (the 5-record exotic residue — Punic/
    # Celtic singletons; honest undetermined beats a guessed Latin).
    # Bilinguals (GL) get per-passage language by script inside the parser.
    #
    # == Metadata-only stubs: skipped by rule at discover
    #
    # ~475 records carry no transcription (CSV atext empty) — catalogued
    # monuments, never edited text (the ORACC no-content precedent). They are
    # not documents and not quarantines: discover never yields them, and
    # #discovery_skips counts them honestly. An XML file with NO CSV row at
    # all is the opposite — unrecognized, rendered loud.
    #
    # == fetch (frozen upstream — the preservation argument)
    #
    # EDH's funding closed in 2021; the dumps are archived (all zips
    # Last-Modified 2021-12-16, HEAD-verified 2026-07-13). sync_policy:
    # frozen — one owner-fired snapshot, ~220 MB canonical (154 MB zips +
    # 66 MB CSVs). The fetch still runs the full two-phase retention
    # choreography (all eleven artifacts prepared and guarded before any
    # tree changes), because correctness machinery is not policy.
    #
    # == License
    #
    # CC BY-SA 4.0, verified in two independent places: the /data page's
    # blanket grant AND the per-file <licence> element in every record →
    # license_class "attribution". Photo files (HeidIcon) carry separate
    # rights and are never fetched (facsimile URLs dropped at parse).
    class Edh < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "edh",
        name: "EDH — Epigraphic Database Heidelberg",
        license: "CC BY-SA 4.0 (per-file <licence> + /data page)",
        license_class: "attribution",
        upstream_url: "https://edh.ub.uni-heidelberg.de/data",
        parser_family: "edh-epidoc"
      )

      DUMP_BASE_URL = "https://edh.ub.uni-heidelberg.de/data/download"

      # The nine EpiDoc dump zips (survey §1 inventory; every URL
      # HEAD-verified 200 + Last-Modified 2021-12-16 on 2026-07-13). The
      # range strings double as the unpack dir names under epidoc/.
      ZIP_RANGES = %w[
        HD000001-HD010000 HD010001-HD020000 HD020001-HD030000
        HD030001-HD040000 HD040001-HD050000 HD050001-HD060000
        HD060001-HD070000 HD070001-HD080000 HD080001-HD082828
      ].freeze

      # The two CSV sidecars: subdir + filename (FileFetch is
      # single-file-per-dir — class note).
      CSVS = { "text" => "edh_data_text.csv", "pers" => "edh_data_pers.csv" }.freeze

      # The text-CSV columns the parser embeds (facet raws + annotation
      # riders, survey §4.3/§4.6). Everything else stays canonical-only.
      CSV_FIELDS = %w[
        i_gattung provinz material denkmaltyp tm_nr metrik fundjahr
        aufbewahrung fundstelle people_uris godot_uris literatur
      ].freeze

      # pers-CSV column → persons-annotation key (survey §4.5; the German
      # column names translated once, values verbatim).
      PERSON_FIELDS = {
        "name" => "name", "praenomen" => "praenomen", "nomen" => "nomen",
        "cognomen" => "cognomen", "supernomen" => "supernomen",
        "filiation" => "filiation", "tribus" => "tribus", "origo" => "origo",
        "geschlecht" => "sex", "verwandt" => "kinship", "status" => "status",
        "funktion" => "function", "beruf" => "occupation",
        "l_jahre" => "age_years", "l_monate" => "age_months",
        "l_tage" => "age_days", "l_stunden" => "age_hours",
        "uri" => "uri", "pir" => "pir"
      }.freeze

      def self.manifest
        MANIFEST
      end

      # nl_text → ISO 639-3 (class note): L anywhere → lat (the bilingual
      # codes GL/LG/PL/… all carry a Latin text), else G → grc, else und.
      def self.language_for(nl_text)
        code = nl_text.to_s.strip
        return "lat" if code.include?("L")
        return "grc" if code.include?("G")

        "und"
      end

      # P11-2: the HTTP fetch path — the remote probe HEADs each artifact
      # (zips via .zip-fetch.json pins, CSVs via .file-fetch.json). No
      # metadata endpoint serves the license (it lives per-file inside the
      # zips), so license rows read honestly unchecked.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        zips = ZIP_RANGES.map do |range|
          Nabu::Adapter::HttpProbeTarget.new(
            label: range, zip_url: zip_url(range), metadata_url: nil,
            state_subdir: File.join("epidoc", range)
          )
        end
        csvs = CSVS.map do |subdir, filename|
          Nabu::Adapter::HttpProbeTarget.new(
            label: filename, zip_url: "#{DUMP_BASE_URL}/#{filename}", metadata_url: nil,
            state_subdir: subdir, state_file: FileFetch::STATE_FILE
          )
        end
        zips + csvs
      end

      def self.zip_url(range) = "#{DUMP_BASE_URL}/edhEpidocDump_#{range}.zip"

      # One DocumentRef per EpiDoc record that has a CSV row WITH text
      # (metadata-only stubs skip by rule — class note), sorted by urn. The
      # CSVs are read once per call; a workdir without them (the attic
      # overlay, a never-fetched tree) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The discovery census (P11-7): text-less CSV stubs whose XML is
      # present are the honest skip-by-rule; an XML file with no CSV row is
      # unrecognized (loud) — the CSV and the zips drifting apart is a fetch
      # defect, never a norm.
      def discovery_skips(workdir)
        index = text_index(workdir)
        return Nabu::Adapter::DiscoverySkips.new if index.empty?

        skipped = 0
        notes = []
        record_paths(workdir).each do |path|
          row = index[hd_number(path)]
          if row.nil?
            notes << "#{File.basename(path)}: no edh_data_text.csv row (zip/CSV drift)"
          elsif row[:stub]
            skipped += 1
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      def parse(document_ref)
        EdhEpidocParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          csv: document_ref.metadata["csv"] || {},
          persons: document_ref.metadata["persons"] || []
        )
      end

      # Download/unpack the nine zips + two CSVs via the shared two-phase
      # retention choreography: ALL artifacts prepared (staged, live trees
      # untouched), the mass-deletion breaker sees the whole set's deletions,
      # then everything completes. No network in tests (WebMock-stubbed).
      def fetch(workdir, progress: nil, force: false)
        zips = zip_fetches(workdir, progress)
        files = file_fetches(workdir, progress)
        fetches = zips.merge(files)
        begin
          fetches.each_value(&:prepare!)
          guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
          fetches.each_value(&:complete!)
        ensure
          zips.each_value(&:cleanup!)
        end
        report(workdir, fetches)
      rescue ZipFetch::Error, FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "edh fetch failed into #{workdir}: #{e.message}"
      end

      private

      def zip_fetches(workdir, progress)
        ZIP_RANGES.to_h do |range|
          [self.class.zip_url(range), Nabu::ZipFetch.new(
            url: self.class.zip_url(range), dir: File.join(workdir, "epidoc", range),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, "epidoc", range), progress: progress
          )]
        end
      end

      def file_fetches(workdir, progress)
        CSVS.to_h do |subdir, filename|
          url = "#{DUMP_BASE_URL}/#{filename}"
          [url, Nabu::FileFetch.new(
            url: url, dir: File.join(workdir, subdir), filename: filename,
            attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
          )]
        end
      end

      def report(workdir, fetches)
        shas = fetches.transform_values(&:sha)
        Nabu::FetchReport.new(
          sha: shas.values.last, fetched_at: Time.now,
          notes: fetch_notes(workdir, fetches, shas), repos: shas
        )
      end

      # "HD000001-HD010000=<sha12> (9928 records) … text=<sha12> (82450 rows,
      # 475 text-less stubs)" — the honest per-artifact record; attic
      # activity rides along.
      def fetch_notes(workdir, fetches, shas)
        notes = shas.map do |url, sha|
          "#{artifact_label(url)}=#{sha.to_s[0, 12]} (#{artifact_counts(workdir, url)})"
        end.join(" ")
        atticked = fetches.values.sum { |fetch| fetch.atticked.size }
        atticked.positive? ? "#{notes} · atticked #{atticked} upstream-deleted file(s)" : notes
      end

      def artifact_label(url)
        name = File.basename(url)
        name.sub(/\AedhEpidocDump_/, "").sub(/\.zip\z/, "").sub(/\Aedh_data_(\w+)\.csv\z/, '\1')
      end

      def artifact_counts(workdir, url)
        if url.end_with?(".zip")
          range = artifact_label(url)
          "#{Dir.glob(File.join(workdir, 'epidoc', range, 'HD*.xml')).size} records"
        else
          rows = csv_rows(workdir, url)
          stubs = rows.count { |row| blank?(row["atext"]) } if url.include?("edh_data_text")
          count = "#{rows.size} rows"
          stubs.to_i.positive? ? "#{count}, #{stubs} text-less stubs" : count
        end
      end

      def csv_rows(workdir, url)
        subdir, filename = CSVS.find { |_dir, name| url.end_with?(name) }
        path = File.join(workdir, subdir, filename)
        return [] unless File.file?(path)

        CSV.read(path, headers: true)
      end

      # -- discovery ------------------------------------------------------------

      def document_refs(workdir)
        index = text_index(workdir)
        return [] if index.empty?

        persons = persons_index(workdir)
        record_paths(workdir).filter_map do |path|
          hd = hd_number(path)
          row = index[hd]
          next if row.nil? || row[:stub] # no CSV row (loud in the census) / text-less stub

          Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{EdhEpidocParser::URN_PREFIX}#{hd.downcase}",
            path: File.expand_path(path),
            metadata: ref_metadata(row, persons[hd])
          )
        end.sort_by(&:id)
      end

      def record_paths(workdir)
        Dir.glob(File.join(workdir, "epidoc", "*", "HD*.xml"))
      end

      def hd_number(path) = File.basename(path, ".xml")

      def ref_metadata(row, persons)
        metadata = { "language" => self.class.language_for(row[:nl_text]), "csv" => row[:csv] }
        metadata["persons"] = persons if persons && !persons.empty?
        metadata
      end

      # hd_nr → { nl_text:, stub:, csv: {the CSV_FIELDS subset, non-empty
      # values only} } from edh_data_text.csv. Streamed row by row — the real
      # file is 57 MB / 82,450 rows and must never materialize whole.
      def text_index(workdir)
        path = File.join(workdir, "text", CSVS.fetch("text"))
        return {} unless File.file?(path)

        index = {}
        CSV.foreach(path, headers: true) do |row|
          hd = row["hd_nr"].to_s.strip
          next if hd.empty?

          csv = CSV_FIELDS.each_with_object({}) do |field, subset|
            subset[field] = row[field] unless blank?(row[field])
          end
          index[hd] = { nl_text: row["nl_text"].to_s, stub: blank?(row["atext"]), csv: csv }
        end
        index
      end

      # hd_nr → ordered person hashes (PERSON_FIELDS, non-empty values only)
      # from edh_data_pers.csv — the §3.5 prosopography seed, riding into
      # Document#metadata via the parser.
      def persons_index(workdir)
        path = File.join(workdir, "pers", CSVS.fetch("pers"))
        return {} unless File.file?(path)

        index = Hash.new { |hash, key| hash[key] = [] }
        CSV.foreach(path, headers: true) do |row|
          hd = row["hd_nr"].to_s.strip
          next if hd.empty?

          index[hd] << person_record(row)
        end
        index
      end

      def person_record(row)
        PERSON_FIELDS.each_with_object({}) do |(column, key), person|
          person[key] = row[column] unless blank?(row[column])
        end
      end

      def blank?(value) = value.nil? || value.to_s.strip.empty?
    end
  end
end
