# frozen_string_literal: true

require "json"
require "digest"
require_relative "../zip_range_fetch"
require_relative "source_read"

module Nabu
  module Adapters
    # baley-manuscripts — Julien Baley's (SOAS) excavated-manuscript
    # alignment series on Zenodo (nine deposits, 2026-09-26 → 11-01, with
    # Yīng Jīnqí, Qiū Ruìfēng and Michele Pulini): graph-level transcriptions
    # of Warring States and Han bamboo-slip manuscripts — the Anhui
    # University (安大簡), Shanghai Museum (上博簡), Tsinghua (清華簡), Peking
    # University (北大簡), Guodian, Fuyang, Dingxian and Jeongbaekdong
    # witnesses of the Odes, the Laozi, the Analects, the Jinteng and Jigong
    # chapters, Cao Mo zhi zhen and the Anda poems — each aligned graph by
    # graph to its received text or to a scholar's edited reading. The
    # library's first Warring States / Han manuscript text: only the Shang
    # oracle bones (obimd) stand before it.
    #
    # == License (the nine records + in-deposit files, read 2026-11-02)
    #
    # Records verbatim: "Project-authored material is CC BY 4.0; manuscript
    # images are distributed under separate permissions documented in
    # witness-images/RIGHTS.md" (Zenodo field other-open on seven, cc-by-4.0
    # on Shan'er and Shentu Di); each LICENSE.md: "project-authored code,
    # structured data, documentation, schemas, and media mappings … are
    # licensed under the Creative Commons Attribution 4.0 International
    # License … This licence grants no rights in third-party source PDFs,
    # manuscript plates, or source-derived image assets." Only text is
    # taken — the image crops and plates are never fetched. Class
    # `attribution`.
    #
    # == Delivery grains (census of all nine deposits by Range, 2026-11-02)
    #
    # Each deposit is one zip: dataset/manifest.json (witness list),
    # dataset/<witness>/transcription.json (units → paragraphs → lines),
    # dataset/alignment.json (groups of graph positions across witnesses),
    # per manuscript witness source_mapping.json (graph → slip) plus image
    # geometry (strip/character mappings, expected_media), the crops under
    # witness-images/, fonts, a static viewer and tools. 40,031 members in
    # all, 39,764 of them images; the kept text members are ~20 MB of 2 GB.
    #
    # - TAKEN: one document per MANUSCRIPT witness (the excavated
    #   transcription, IDS-braced graphs verbatim) and per EDITION witness
    #   (a scholar's reading of the same manuscript: Chen Qi, Qiū Ruìfēng);
    #   one passage per transcribed line, cited unit.paragraph.line. 19
    #   documents / 4,626 lines across the nine deposits.
    # - REJECTED by rule (counted in discovery_skips): the RECEIVED-text
    #   witnesses (Shangshu, Yizhoushu, Wang Bi Laozi, the Analects, Mao
    #   Shi, and the Liji/Xunzi/Hanfeizi… parallels — 13 in all): received
    #   classics already held through kanripo, transcribed by the deposits
    #   from ctext.org editions and the 2000 毛詩正義 (their
    #   reference_transcription says so) — not project-authored text. They stay NAMED in every line's
    #   alignment annotation.
    # - REJECTED at the fetch: images, image geometry, fonts, viewer, tools,
    #   schemas and the Fuyang transcription_previous.json (superseded).
    #
    # A witness the WITNESSES table does not know is unrecognized (counted
    # loudly, never taken) — a new deposit version adding a witness asks
    # for a deliberate role decision.
    #
    # == Mined per line / per document
    #
    # graphs + graph_start (the deposits' own rule — a braced IDS expression
    # is one graph, whitespace and punctuation none; validated against the
    # data dictionaries' totals on 31 of 32 witnesses, the 32nd — Shangbo
    # 1,794 vs its dictionary's 1,795 — matching upstream's validator
    # itself); strips (the physical slip numbers from source_mapping);
    # aligned (per other witness, the unit.paragraph:graph-range each line's
    # graphs align to). Per document: role, collection, the curated
    # manuscript era and findspot (COLLECTIONS below — conventional dates,
    # approximate; an edition inherits its manuscript's), the deposit's DOI
    # and title, partners.
    class BaleyManuscripts < Nabu::Adapter
      SLUG = "baley-manuscripts"
      LANGUAGE = "och"

      # dataset_id (the manifest's own, also the canonical subdir) =>
      # [Zenodo record, zip file, deposit title].
      DEPOSITS = {
        "aisong" => [22_983_015, "aisong-alignment-dataset-1.0.0.zip", "Digital Āisòng 哀誦"],
        "caomozhizhen" => [23_675_832, "caomozhizhen-alignment-dataset-1.0.0.zip", "Cáo Mò Zhī Zhèn 曹沫之陳"],
        "jigong" => [23_864_380, "jigong-alignment-dataset-1.0.0.zip", "Jigong 祭公"],
        "jinteng" => [23_870_159, "jinteng-alignment-dataset-1.0.0.zip", "Jinteng 金縢"],
        "laozi" => [23_296_353, "laozi-alignment-dataset-1.0.0.zip", "Laozi 老子"],
        "lunyu" => [23_516_909, "lunyu-alignment-dataset-1.0.0.zip", "Lunyu 論語"],
        "shaner" => [23_323_410, "shaner-alignment-dataset-1.0.0.zip", "Shan'er 善而"],
        "shentudi" => [23_395_550, "shentudi-alignment-dataset-1.0.1.zip", "Shentu Di Meets the Duke of Zhou 申徒狄見周公"],
        "shijing" => [23_270_426, "odes-alignment-dataset-1.0.4.zip", "Aligning the Odes 詩"]
      }.freeze

      # The manuscript finds: conventional scholarly dating of each witness
      # (radiocarbon or burial terminus; approximate) and the findspot when
      # the slips were excavated (nil = acquired, unprovenanced).
      COLLECTIONS = {
        "anda" => { era: [-400, -278], raw: "Warring States (Chu), c. 4th c. BCE — Anhui University slips, " \
                                            "acquired 2015", place: nil },
        "shangbo" => { era: [-350, -278], raw: "Warring States (Chu), late 4th c. BCE — Shanghai Museum " \
                                               "slips, acquired 1994", place: nil },
        "tsinghua" => { era: [-335, -275], raw: "Warring States (Chu), radiocarbon c. 305 BCE — Tsinghua " \
                                                "University slips, acquired 2008", place: nil },
        "guodian" => { era: [-350, -278], raw: "Warring States (Chu), tomb sealed before 278 BCE",
                       place: "Guodian tomb 1, Jingmen (Hubei)" },
        "beida" => { era: [-180, -87], raw: "Western Han, mid-2nd to early 1st c. BCE — Peking University " \
                                            "slips, donated 2009", place: nil },
        "fuyang" => { era: [-206, -165], raw: "Western Han, before 165 BCE (Xiahou Zao's tomb)",
                      place: "Shuanggudui tomb 1, Fuyang (Anhui)" },
        "dingxian" => { era: [-206, -55], raw: "Western Han, before 55 BCE (Liu Xiu's tomb)",
                        place: "Bajiaolang tomb 40, Dingxian (Hebei)" },
        "jeongbaekdong" => { era: [-108, -45], raw: "Western Han (Lelang commandery), c. 45 BCE",
                             place: "Jeongbaekdong tomb 364, Pyongyang" }
      }.freeze

      # Per deposit: witness id => [role, collection]. Roles: excavated
      # (taken), edition (taken; a reading of the named collection's
      # manuscript), received (rejected by rule).
      WITNESSES = {
        "aisong" => { "chenqi" => %w[edition anda], "anda" => %w[excavated anda] },
        "caomozhizhen" => { "anda" => %w[excavated anda], "shangbo" => %w[excavated shangbo] },
        "jigong" => { "yizhoushu" => ["received", nil], "tsinghua" => %w[excavated tsinghua] },
        "jinteng" => { "shangshu" => ["received", nil], "tsinghua" => %w[excavated tsinghua] },
        "laozi" => { "wangbi" => ["received", nil], "beida" => %w[excavated beida],
                     "guodian_a" => %w[excavated guodian], "guodian_b" => %w[excavated guodian],
                     "guodian_c" => %w[excavated guodian] },
        "lunyu" => { "anda" => %w[excavated anda], "lunyu" => ["received", nil],
                     "jeongbaekdong" => %w[excavated jeongbaekdong], "dingxian" => %w[excavated dingxian],
                     "liji" => ["received", nil], "dadai-liji" => ["received", nil],
                     "kongcongzi" => ["received", nil], "xunzi" => ["received", nil], "mozi" => ["received", nil],
                     "yantie-lun" => ["received", nil], "zhonglun" => ["received", nil],
                     "hanfeizi" => ["received", nil] },
        "shaner" => { "qiuruifeng" => %w[edition anda], "anda" => %w[excavated anda] },
        "shentudi" => { "qiuruifeng" => %w[edition anda], "anda" => %w[excavated anda] },
        "shijing" => { "maoshi" => ["received", nil], "anda" => %w[excavated anda],
                       "fuyang" => %w[excavated fuyang] }
      }.freeze

      # The text members ZipRangeFetch keeps (names below the deposit's
      # top directory); everything else — images, image geometry, fonts,
      # viewer, tools, schemas, superseded transcriptions — is never read.
      KEEP = %r{\A(?:dataset/(?:manifest|alignment)\.json|dataset/[^/]+/(?:transcription|source_mapping)\.json|
                 LICENSE\.md|README\.md|CITATION\.cff|CHANGELOG\.md|CONTRIBUTORS\.md|VERSION|
                 docs/[^/]+\.(?:md|bib)|witness-images/RIGHTS\.md)\z}x

      # One graph per braced IDS expression or per character that is not
      # whitespace or punctuation — the deposits' tools/validate.py rule.
      GRAPH = /\{[^}]*\}|[^[:space:]\p{P}]/

      LICENSE = "CC BY 4.0 for the project-authored data (each record: \"Project-authored material is " \
                "CC BY 4.0; manuscript images are distributed under separate permissions documented in " \
                "witness-images/RIGHTS.md\"; each LICENSE.md the same grant, verified 2026-11-02) — text only, " \
                "no images taken"

      CREDIT = "Julien Baley (SOAS) with Yīng Jīnqí, Qiū Ruìfēng and Michele Pulini — the excavated-manuscript " \
               "alignment datasets, Zenodo 2026 (cite each deposit's DOI)."

      def self.manifest
        Nabu::SourceManifest.new(
          id: SLUG,
          name: "Baley excavated-manuscript alignments (Warring States and Han bamboo slips)",
          license: LICENSE, license_class: "attribution",
          upstream_url: "https://zenodo.org/search?q=creators.name%3ABaley",
          parser_family: "baley-alignment-json", credit: CREDIT
        )
      end

      def self.parallel_parse? = true

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        DEPOSITS.map do |id, (record, file, _title)|
          Nabu::Adapter::HttpProbeTarget.new(label: "zenodo #{record}", zip_url: zip_url(record, file),
                                             metadata_url: nil, state_subdir: id,
                                             state_file: Nabu::ZipRangeFetch::STATE_FILE, liveness_only: true)
        end
      end

      def self.zip_url(record, file) = "https://zenodo.org/api/records/#{record}/files/#{file}/content"

      def initialize(range_fetch: Nabu::ZipRangeFetch.method(:sync!))
        super()
        @range_fetch = range_fetch
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        each_witness(workdir) do |dataset_id, witness, role, path|
          next unless %w[excavated edition].include?(role) && File.file?(path)

          yield Nabu::DocumentRef.new(source_id: SLUG, id: "urn:nabu:#{SLUG}:#{dataset_id}:#{witness}", path: path,
                                      metadata: { "dataset_id" => dataset_id, "witness" => witness })
        end
      end

      def discovery_skips(workdir)
        skipped = []
        unknown = []
        each_witness(workdir) do |dataset_id, witness, role, _path|
          skipped << "#{dataset_id}:#{witness}" if role == "received"
          unknown << "#{dataset_id}:#{witness}" if role.nil?
        end
        notes = []
        if skipped.any?
          notes << "received-text witnesses (received classics held via kanripo, transcribed by the deposits " \
                   "from ctext.org / the 毛詩正義 — not project-authored): #{skipped.join(', ')}"
        end
        notes << "witnesses with no role in WITNESSES: #{unknown.join(', ')} — decide before taking" if unknown.any?
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, unrecognized: unknown.size, notes: notes)
      end

      def parse(document_ref)
        dataset_id = document_ref.metadata.fetch("dataset_id")
        witness = document_ref.metadata.fetch("witness")
        deposit = File.join(File.dirname(document_ref.path), "..", "..")
        transcription = read_json(document_ref.path)
        manifest = read_json(File.join(deposit, "dataset", "manifest.json"))
        aligned = alignment_index(File.join(deposit, "dataset", manifest.fetch("alignment", "alignment.json")), witness)
        strips = strip_index(File.join(File.dirname(document_ref.path), "source_mapping.json"))
        document = build_document(document_ref, dataset_id, witness, transcription, manifest)
        add_passages(document, transcription, aligned, strips)
        raise Nabu::ParseError, "#{document_ref.id}: no transcribed lines" if document.empty?

        document
      end

      def fetch(workdir, progress: nil, force: false)
        results = DEPOSITS.map do |id, (record, file, _title)|
          @range_fetch.call(
            url: self.class.zip_url(record, file), dir: File.join(workdir, id),
            attic_dir: File.join(workdir, ATTIC_DIRNAME, id), select: ->(name) { KEEP.match?(name) },
            progress: progress, guard: ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
          )
        end
        kept = results.sum(&:kept)
        skipped = results.sum(&:skipped)
        Nabu::FetchReport.new(
          sha: Digest::SHA256.hexdigest(results.map(&:sha).join("\n")), fetched_at: Time.now,
          notes: ["#{DEPOSITS.size} deposits: #{kept} text members kept by Range, #{skipped} never read",
                  attic_notes(results.flat_map(&:atticked))].compact.join("; ")
        )
      rescue Nabu::ZipRangeFetch::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      private

      def each_witness(workdir)
        DEPOSITS.each_key do |dataset_id|
          manifest_path = File.join(workdir, dataset_id, "dataset", "manifest.json")
          next unless File.file?(manifest_path)

          read_json(manifest_path).fetch("witnesses").each do |entry|
            witness = entry.fetch("id")
            role, = WITNESSES.fetch(dataset_id).fetch(witness, [nil])
            yield dataset_id, witness, role, File.join(workdir, dataset_id, "dataset", witness, "transcription.json")
          end
        end
      end

      def read_json(path)
        JSON.parse(SourceRead.utf8_file(path, label: SLUG))
      rescue JSON::ParserError => e
        raise Nabu::ParseError, "#{path}: not JSON (#{e.message})"
      end

      def build_document(document_ref, dataset_id, witness, transcription, manifest)
        record, _file, title = DEPOSITS.fetch(dataset_id)
        role, collection = WITNESSES.fetch(dataset_id).fetch(witness)
        found = COLLECTIONS.fetch(collection)
        unless manifest["dataset_id"] == dataset_id
          raise Nabu::ParseError, "#{document_ref.path}: manifest says #{manifest['dataset_id'].inspect}"
        end

        Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: Nabu::Normalize.nfc(transcription.fetch("title")),
          metadata: {
            "dataset_id" => dataset_id, "work" => dataset_id, "deposit_title" => title,
            "doi" => "10.5281/zenodo.#{record}", "witness" => witness, "witness_role" => role,
            "collection" => collection, "reference_transcription" => transcription["reference_transcription"],
            "date" => { "not_before" => found[:era][0], "not_after" => found[:era][1], "raw" => found[:raw] },
            "place" => found[:place],
            "partners" => manifest.fetch("witnesses").map { |w| w["id"] } - [witness],
            "units" => transcription.fetch("units").size
          }.compact
        )
      end

      def add_passages(document, transcription, aligned, strips)
        transcription.fetch("units").each_with_index do |unit, u|
          unit.fetch("paragraphs").each_with_index do |lines, p|
            graph = 1
            lines.each_with_index do |raw, l|
              text = Nabu::Normalize.nfc(raw.to_s).strip
              count = text.scan(GRAPH).size
              coords = [u + 1, p + 1]
              range = graph..(graph + count - 1)
              graph += count
              next if text.empty?

              document << Nabu::Passage.new(
                urn: "#{document.urn}:#{u + 1}.#{p + 1}.#{l + 1}", language: LANGUAGE, text: text,
                sequence: document.size,
                annotations: line_annotations(unit, count, range, aligned[coords], strips[coords])
              )
            end
          end
        end
      end

      def line_annotations(unit, count, range, aligned, strips)
        {
          "unit_title" => unit["title"], "unit_type" => unit["type"], "section" => unit["section"],
          "subsection" => unit["subsection"], "graphs" => count, "graph_start" => range.first,
          "strips" => (strips && range.filter_map { |g| strips[g] }.uniq).then { |s| s.nil? || s.empty? ? nil : s },
          "aligned" => aligned_ranges(aligned, range)
        }.compact
      end

      # {[unit, paragraph] => {graph => [[witness, unit, paragraph, graph], …]}} for +witness+.
      def alignment_index(path, witness)
        index = Hash.new { |hash, key| hash[key] = {} }
        return index unless File.file?(path)

        read_json(path).fetch("alignments").each do |group|
          mine, others = group.partition { |loc| loc["witness"] == witness }
          mine.each do |loc|
            index[[loc["unit"], loc["paragraph"]]][loc["graph"]] =
              others.map { |o| [o["witness"], o["unit"], o["paragraph"], o["graph"]] }
          end
        end
        index
      end

      # Per other witness: "unit.paragraph:first-last" spans the line's
      # graphs align to (nil when none align).
      def aligned_ranges(by_graph, range)
        return nil if by_graph.nil?

        spans = Hash.new { |hash, key| hash[key] = [] }
        range.each do |g|
          Array(by_graph[g]).each { |w, u, p, og| spans[[w, u, p]] << og }
        end
        return nil if spans.empty?

        spans.each_with_object({}) do |((w, u, p), graphs), out|
          (out[w] ||= []) << "#{u}.#{p}:#{graphs.min}-#{graphs.max}"
        end
      end

      # {[unit, paragraph] => {graph => strip}} from source_mapping.json.
      def strip_index(path)
        index = Hash.new { |hash, key| hash[key] = {} }
        return index unless File.file?(path)

        read_json(path).fetch("mappings").each do |m|
          pos = m.fetch("transcription_position")
          strip = m.dig("source_location", "strip")
          index[[pos["unit"], pos["paragraph"]]][pos["graph"]] = strip.to_s if strip
        end
        index
      end
    end
  end
end
