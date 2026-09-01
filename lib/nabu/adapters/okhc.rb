# frozen_string_literal: true

require_relative "okhc_jsonl_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # OKHC — the Open Korean Historical Corpus (P91-1; Song et al., KAIST;
    # huggingface.co/datasets/seyoungsong/Open-Korean-Historical-Corpus):
    # 1,300 years of Korean historical text compiled from 19 institutional
    # archives. THIS adapter holds the corpus's curated HISTORICAL slice —
    # the FILES map below — not the whole 28.6 GB deposit.
    #
    # == License (resolved by the author, by email 2026-08-31)
    #
    # CC BY-NC 4.0 governs the dataset (deliberate — the release stays
    # within South Korean database-rights research exceptions); the MIT
    # license covers the processing code only; 15 National Hangeul Museum
    # docs are item-level KOGL Type 1. Personal-research ingestion was
    # explicitly welcomed; the authors ask that the paper be cited — the
    # manifest credit line carries it onto every serving surface. Class
    # `nc`; a record whose own copyright field says "Public Domain"
    # relabels `open` per document (the ud split-licensing precedent).
    #
    # == The scope map (the oracc PROJECTS discipline)
    #
    # INCLUDED (≈4.2 GB, the historical core new to the library):
    # sagi (Samguk sagi, 1145) · ilseongnok (Kyujanggak, the Records of
    # Daily Reflections) · klc (the ITKC munjip mass — the held itkc
    # source's zips carry only the tiny gojeon/gukjobogam slices, censused
    # 2026-09-01) · gaksa (Gaksadeungnok) · gongu (the Copyright
    # Commission's PD collection) · aks_kyu_nhm (AKS + Kyujanggak + NHM
    # old-literature dbs) · jpn_records (the Hanmun legation records).
    # HELD OUT, recorded:
    # - sillok · sjw · bibyeonsa · goryeosa — already first-class sources
    #   in this library from their primary channels; ingesting the OKHC
    #   copies would duplicate held documents;
    # - newslibrary (17.6 GB) · news_archive · magazine · gaksa_modern —
    #   the modern-newspaper/colonial-print mass, outside the library's
    #   historical scope (an early-modern widening is one FILES line away,
    #   an owner call);
    # - kcna_jp · kisu_journal · kisu_literary — contemporary North Korean
    #   material whose records carry "All Rights Reserved" — below the
    #   library's license floor regardless of scope.
    class Okhc < Nabu::Adapter
      SLUG = "okhc"
      PARSER_FAMILY = "okhc_jsonl"

      DATASET_URL = "https://huggingface.co/datasets/seyoungsong/Open-Korean-Historical-Corpus"

      LICENSE = "CC BY-NC 4.0 (dataset; confirmed by the author, by email 2026-08-31 — " \
                "personal-research use welcomed; per-record Public Domain rows relabel open)"

      CREDIT = "Open Korean Historical Corpus (Song, Kim, Chae, Park, Jin, Yoo, Cho & Oh; " \
               "KAIST) — cite the OKHC paper (arXiv:2510.24541 / LREC 2026) wherever used."

      # The curated historical slice: every part of each included source
      # file, fetched from the deposit's public resolve URLs.
      FILES = %w[
        sagi.jsonl
        ilseongnok_part_001_of_003.jsonl
        ilseongnok_part_002_of_003.jsonl
        ilseongnok_part_003_of_003.jsonl
        klc_part_001_of_008.jsonl
        klc_part_002_of_008.jsonl
        klc_part_003_of_008.jsonl
        klc_part_004_of_008.jsonl
        klc_part_005_of_008.jsonl
        klc_part_006_of_008.jsonl
        klc_part_007_of_008.jsonl
        klc_part_008_of_008.jsonl
        gaksa.jsonl
        gongu.jsonl
        aks_kyu_nhm.jsonl
        jpn_records.jsonl
      ].freeze

      # A cheap id probe so discovery never JSON-parses 4 GB twice: the
      # deposit writes ids first and plainly. A line it misses is counted
      # unrecognized (discovery_skips), and parse-time JSON is authoritative.
      ID_RE = /"id":\s*"([^"]+)"/

      # Each file lives in its OWN subdir (the ccl multi-artifact shape):
      # FileFetch keeps one state file and one doomed-scope per directory,
      # so siblings sharing a dir would clobber each other's conditional-GET
      # state and read each other as deletable.
      def self.file_dir(name)
        File.basename(name, ".jsonl")
      end

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "Open Korean Historical Corpus (historical slice)",
          license: LICENSE,
          license_class: "nc",
          upstream_url: DATASET_URL,
          parser_family: PARSER_FAMILY,
          credit: CREDIT
        )
      end

      # HTTP artifacts, not git: HEAD each included file's resolve URL for
      # liveness; each subdir's FileFetch state feeds the URL-identity lane.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |name|
          Nabu::Adapter::HttpProbeTarget.new(
            label: name, zip_url: "#{DATASET_URL}/resolve/main/#{name}", metadata_url: nil,
            state_subdir: file_dir(name), state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # One DocumentRef per RECORD (jsonl line): one streaming pass per
      # file collecting byte offsets, so parse reads exactly its line.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        each_record_line(workdir) do |path, name, line, offset|
          id = line[ID_RE, 1] or next
          yield Nabu::DocumentRef.new(
            source_id: SLUG, id: "urn:nabu:#{SLUG}:#{id}", path: path,
            metadata: { "file" => name, "offset" => offset, "length" => line.bytesize }
          )
        end
      end

      # Lines the id probe could not read, censused per file.
      def discovery_skips(workdir)
        unrecognized = Hash.new(0)
        each_record_line(workdir) do |_path, name, line, _offset|
          unrecognized[name] += 1 unless line.match?(ID_RE)
        end
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: 0, unrecognized: unrecognized.values.sum,
          notes: unrecognized.map { |name, count| "#{name}: #{count} id-less lines — identity unreadable" }
        )
      end

      # Parse one record into a Document of line Passages.
      def parse(document_ref)
        line = record_line(document_ref)
        record = OkhcJsonlParser.parse_record(line)
        raise Nabu::ParseError, "okhc: record #{record.id} has no body text" if record.lines.empty?

        document = Nabu::Document.new(
          urn: document_ref.id, language: record.language,
          canonical_path: document_ref.path, title: record.title,
          license_override: record.copyright == "Public Domain" ? "open" : nil,
          metadata: record_metadata(record)
        )
        record.lines.each_with_index do |text, index|
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{index + 1}", language: record.language,
            text: text, sequence: index
          )
        end
        document
      end

      # Sequential per-file FileFetch (conditional GETs make re-syncs
      # cheap; one file in memory at a time — the deposit's largest
      # included part is ~300 MB). Owner-fired: ≈4.2 GB on first sync.
      def fetch(workdir, progress: nil, force: false)
        shas = []
        atticked = []
        FILES.each do |name|
          dir = File.join(workdir, self.class.file_dir(name))
          result = Nabu::FileFetch.sync!(
            url: "#{DATASET_URL}/resolve/main/#{name}", dir: dir, filename: name,
            attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress,
            guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          )
          shas << result.sha
          atticked.concat(result.atticked)
        end
        Nabu::FetchReport.new(
          sha: Digest::SHA256.hexdigest(shas.join("\n")), fetched_at: Time.now,
          notes: ["#{FILES.size} files", attic_notes(atticked)].compact.join("; ")
        )
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "okhc fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Stream every included file's lines with byte offsets. Only FILES
      # members (each in its own subdir) are read — a stray jsonl is not
      # this source's data.
      def each_record_line(workdir)
        FILES.each do |name|
          path = File.join(workdir, self.class.file_dir(name), name)
          next unless File.file?(path)

          offset = 0
          File.open(path, "r:UTF-8") do |io|
            io.each_line do |line|
              yield(path, name, line.chomp, offset) unless line.strip.empty?
              offset += line.bytesize
            end
          end
        end
      end

      def record_line(document_ref)
        offset = document_ref.metadata.fetch("offset")
        length = document_ref.metadata.fetch("length")
        File.open(document_ref.path, "r:UTF-8") do |io|
          io.seek(offset)
          io.read(length).to_s.force_encoding(Encoding::UTF_8)
        end
      end

      def record_metadata(record)
        {
          "year" => record.year, "script" => record.script,
          "archive" => record.source, "corpus" => record.corpus,
          "copyright" => record.copyright, "permanent_url" => record.url,
          "page_path" => record.page_path
        }.compact
      end
    end
  end
end
