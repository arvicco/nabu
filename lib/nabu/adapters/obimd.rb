# frozen_string_literal: true

require "json"
require "strscan"
require_relative "../file_fetch"
require_relative "../normalize"
require_relative "source_read"

module Nabu
  module Adapters
    # OBIMD — the Oracle Bone Inscriptions Multi-modal Dataset (Li Bang et
    # al.; Key Laboratory of Oracle Bone Inscriptions Information Processing,
    # Anyang Normal University, with Xiamen University and Tencent; paper
    # arXiv:2407.03900, Scientific Data 13:681, 2026; Hugging Face
    # KLOBIP/OBIMD, DOI 10.57967/hf/7821) — the library's EARLIEST Chinese
    # stratum: Late Shang royal divination inscriptions on bone and shell
    # (c. 1250–1046 BCE), as character-annotated, reading-ordered
    # inscription groups.
    #
    # == Upstream (census 2026-10-21, dataset revision 4820d2f1)
    #
    # data.json — ONE JSON array, 10,077 records, one per rubbing:
    # RubbingName (H<n> = 甲骨文合集 Heji no. n, 9,913; HD<n> = 殷墟花園莊東地
    # 甲骨 Huadong no. n, 164 — unique), Rubbing/Facsimile image paths, and
    # RecordUtilSentenceGroupVoList: 21,941 inscription groups, each with a
    # GroupCategory (InscriptionSentence 17,150 · OracleSequence 3,785 ·
    # Uncertain 599 · OracleOutcome 407 — usually suffixed with a per-type
    # number, 962 unsuffixed, 3 records repeat a label) and its glyph boxes:
    # Position (pixel box on the images), OrderNumber (reading order from
    # 0), SeatFont (1 = a placeholder for a missing glyph, 21,667 of
    # 115,319 boxes), Mark (upstream legend, paper §2.2: -1 normal; 0
    # damaged, unidentifiable; 1 disputed category; 2 on the rubbing only —
    # doubtful glyph; 3 on the facsimile only — not derived from the
    # rubbing), Label/SubLabel (the Oracular Digital Platform's main/sub
    # character UIDs).
    #
    # Hierarchical Character Metadata Supplement/Main-character.json — the
    # 3,936 main-character UIDs → {codepoint, transcription[]}: the
    # platform's "reference modern character" (README: "for reference
    # only and is not intended as a final philological interpretation").
    # 2,374 codepoints are private-use or unassigned (platform-font slots
    # for undeciphered glyphs and ligatures); 388 of those carry an encoded
    # transcription (a 合文 ligature reads "十一月", "二告").
    #
    # Delivery grains: data.json (ACCEPTED — split into one document per
    # rubbing) + Main-character.json (ACCEPTED as the text layer's lookup
    # table); the dataset card README.md (REJECTED — the license stamp's
    # home, fetched for provenance, counted in discovery_skips). NEVER
    # FETCHED: rubbing.zip (558 MB) and facsimile.zip (211 MB) — the image
    # modality; Sub-character Images.zip (40 MB); the two XLSX tables
    # (sub-character → platform-font code point, sub → main UID — the
    # SubLabel rides annotations, its font slot carries no text); OBIMD.py
    # (the datasets loader); figures/. Reconciliation (the full data.json
    # parsed 2026-10-21): 10,077 records = 10,077 documents = the README's
    # "Total OBI images: 10,077"; 21,941 groups = 21,941 passages = the
    # README's "Sentences: 21,941"; 93,652 glyphs + 21,667 placeholders =
    # the paper's 115,319 boxes.
    #
    # == Document / passage shape
    #
    # urn:nabu:obimd:<RubbingName>; title "合集 <n>" / "花東 <n>"; language
    # och (the zho:old anchor — the oracle bones are its earliest stratum;
    # a finer Shang stage is not minted). Metadata: collection, number,
    # the image paths (reference only — the images are not held), the
    # collection facet. One passage per inscription group, urn suffix =
    # the group's 1-based position in upstream's array (labels repeat);
    # text = the glyphs in reading order (OrderNumber, upstream array
    # position breaking the 258 shared numbers; gaps and non-zero starts
    # kept as-is): the reference character; else, for a private-use/
    # unassigned codepoint, its first encoded transcription; else ⬚ (the
    # house gaiji placeholder); a SeatFont placeholder is □ (the epigraphic
    # lacuna). Annotations: group (verbatim label), group_type, labels
    # (main UIDs, nil at placeholders — the glyph identity survives the
    # surrogate text), sublabels (only when any differs), marks ({position
    # => code}, non-default only). DROPPED, declared: Position boxes (pixel
    # alignment with images the library does not hold).
    #
    # Dating/places: no per-record period or findspot is carried. The
    # paper samples "five historical periods of the Shang Dynasty" (Dong
    # Zuobin's) but ships no per-record period; the Heji's own volume
    # ranges ARE period-ordered — the candidate table for a dating rule
    # (postures: pending). Heji/Huadong are Yinxu (Anyang) material; the
    # collection rides metadata, no place claim is minted per record.
    #
    # == License (re-verified verbatim 2026-10-21)
    #
    # The HF dataset — the data — is CC BY 4.0: card front matter
    # "license: cc-by-4.0", LICENSE "Creative Commons Attribution 4.0
    # International / You must give appropriate credit to the author(s).",
    # card "## License: This model is licensed under CC-BY 4.0." The
    # Zenodo record 18675664 (v1.1) is MIT but covers the CODE release (the
    # card's mirror note); a commented-out older card paragraph ("academic
    # research purposes only") is an HTML comment, not the stamp. →
    # attribution.
    #
    # == fetch / sync policy
    #
    # Three FileFetch single-file syncs over the revision-pinned resolve
    # URLs, each in its own subdir, sha256-verified BEFORE the tree mutates
    # (the baxter-sagart choreography; data.json's pin is its LFS oid).
    # ~42 MB. A new upstream revision = an owner re-pin → sync_policy manual.
    class Obimd < Nabu::Adapter
      HF_BASE = "https://huggingface.co/datasets/KLOBIP/OBIMD"
      REVISION = "4820d2f11a8f45f3347591fdcd5f6466706b0dce" # main @ 2026-03-11
      RESOLVE = "#{HF_BASE}/resolve/#{REVISION}".freeze

      # subdir → filename, resolve URL, sha256 pin.
      FILES = {
        "data" => { filename: "data.json", url: "#{RESOLVE}/data.json",
                    sha256: "b504b0d4e7a0126d494c161f5445c5ee4225659ff5e94182685fce35d261aa19" }.freeze,
        "chars" => { filename: "Main-character.json",
                     url: "#{RESOLVE}/Hierarchical%20Character%20Metadata%20Supplement/Main-character.json",
                     sha256: "17db8ffebf246571dd004c5ef7c42316e6c6dde74210fbdab466a4067c45de6e" }.freeze,
        "card" => { filename: "README.md", url: "#{RESOLVE}/README.md",
                    sha256: "2ad91fb999e3ea176a2f7dd39cf67b5e8cfb327d9f22f6713aa1d196a61932de" }.freeze
      }.freeze

      URN_PREFIX = "urn:nabu:obimd:"
      LANGUAGE = "och"

      # RubbingName prefix → [collection, short title prefix].
      COLLECTIONS = {
        "H" => %w[甲骨文合集 合集],
        "HD" => %w[殷墟花園莊東地甲骨 花東]
      }.freeze
      NAME_SHAPE = /\A([A-Z]+)(\d+)\z/

      GROUP_TYPES = {
        "InscriptionSentence" => "inscription", "OracleSequence" => "oracle-sequence",
        "OracleOutcome" => "oracle-outcome", "Uncertain" => "uncertain"
      }.freeze

      MISSING = "□"
      UNRENDERABLE = "⬚"
      # A codepoint with no faithful public glyph: private use or unassigned.
      NO_GLYPH = /[\p{Co}\p{Cn}]/

      MANIFEST = Nabu::SourceManifest.new(
        id: "obimd",
        name: "OBIMD — Oracle Bone Inscriptions Multi-modal Dataset (KLOBIP)",
        license: "CC BY 4.0 — the Hugging Face dataset card front matter \"license: cc-by-4.0\", " \
                 "LICENSE \"Creative Commons Attribution 4.0 International / You must give " \
                 "appropriate credit to the author(s).\" (revision 4820d2f1, verified 2026-10-21). " \
                 "The Zenodo record 18675664 (v1.1) is MIT and covers the code release only",
        license_class: "attribution",
        upstream_url: HF_BASE,
        parser_family: "obimd-json",
        credit: "Li, Bang; Luo, Donghao; Liang, Yujie et al., Oracle Bone Inscriptions Multi-modal " \
                "Dataset (OBIMD), Key Laboratory of Oracle Bone Inscriptions Information Processing, " \
                "Anyang Normal University — DOI 10.57967/hf/7821; Scientific Data 13:681 (2026)"
      )

      def self.manifest = MANIFEST

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        FILES.map do |subdir, file|
          Nabu::Adapter::HttpProbeTarget.new(
            label: file.fetch(:filename), zip_url: file.fetch(:url), metadata_url: nil,
            state_subdir: subdir, state_file: Nabu::FileFetch::STATE_FILE
          )
        end
      end

      # +pins+ exists for the WebMock'd fetch tests — real syncs keep the
      # frozen revision pins.
      def initialize(pins: FILES.transform_values { |file| file.fetch(:sha256) })
        super()
        @pins = pins
        @index = {}
        @bytes = nil
        @bytes_key = nil
        @chars = {}
      end

      # One ref per rubbing record, in file order. Each ref carries the
      # record's byte span inside data.json, so parse reads its slice only.
      # Needs both the data and the character map on disk.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        data = path(workdir, "data")
        return unless File.file?(data) && File.file?(path(workdir, "chars"))

        records(data).each do |name, offset, length|
          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{URN_PREFIX}#{name}", path: File.expand_path(data),
            metadata: { "name" => name, "offset" => offset, "length" => length }
          )
        end
      end

      # The dataset card (README.md) is the rejected card grain — counted.
      def discovery_skips(workdir)
        card = path(workdir, "card")
        return DiscoverySkips.new unless File.file?(card)

        DiscoverySkips.new(skipped_by_rule: 1,
                           notes: ["1 dataset card skipped — the license/description grain, not a record " \
                                   "(card/README.md)"])
      end

      def parse(document_ref)
        record = read_record(document_ref)
        name = document_ref.metadata.fetch("name")
        unless record["RubbingName"] == name && document_ref.id == "#{URN_PREFIX}#{name}"
          raise Nabu::ParseError, "obimd: #{document_ref.id}: the record slice names #{record['RubbingName'].inspect}"
        end

        chars = character_map(File.join(File.dirname(document_ref.path), "..", "chars", FILES["chars"][:filename]))
        build_document(document_ref, record, chars)
      rescue JSON::ParserError, KeyError, TypeError, Nabu::ValidationError => e
        raise Nabu::ParseError, "obimd: #{document_ref.id}: #{e.message}"
      end

      # Three single-file syncs, two-phase: every prepare (live tree
      # untouched) and every pin check before any complete.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        fetches.each { |subdir, fetch| verify_pin!(subdir, fetch) }
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.fetch("data").sha, fetched_at: Time.now,
                              notes: attic_notes(fetches.values.flat_map(&:atticked)))
      rescue Nabu::FileFetch::Error => e
        raise Nabu::FetchError, "obimd fetch failed into #{workdir}: #{e.message}"
      end

      private

      def path(workdir, subdir) = File.join(workdir, subdir, FILES.fetch(subdir).fetch(:filename))

      def file_fetches(workdir, progress)
        FILES.to_h do |subdir, file|
          [subdir, Nabu::FileFetch.new(url: file.fetch(:url), dir: File.join(workdir, subdir),
                                       filename: file.fetch(:filename),
                                       attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress)]
        end
      end

      def verify_pin!(subdir, fetch)
        return if fetch.sha == @pins.fetch(subdir)

        raise Nabu::FetchError,
              "obimd: #{FILES[subdir][:filename]} drifted — fetched sha256 #{fetch.sha} != pinned " \
              "#{@pins.fetch(subdir)} (revision #{REVISION[0, 8]}); review upstream and re-pin (owner decision)"
      end

      # -- the record index (byte spans of the top-level array's objects) ---------

      # [name, offset, length] per record, memoized per file state. A
      # string-aware brace scan (formatting-independent); the name comes
      # from the slice's RubbingName key and parse re-verifies it.
      def records(data)
        @index[file_key(data)] ||= scan_records(bytes_of(data))
      end

      # The whole data.json through the encoding belt, memoized per file
      # state — discover indexes it once, every parse slices it in memory.
      def bytes_of(data)
        key = file_key(data)
        @bytes = nil unless @bytes_key == key
        @bytes_key = key
        @bytes ||= SourceRead.utf8_file(data, label: "obimd")
      end

      def file_key(data) = [File.expand_path(data), File.size(data), File.mtime(data).to_r]

      def scan_records(bytes)
        scanner = StringScanner.new(bytes)
        depth = 0
        start = nil
        found = []
        while scanner.scan_until(/[\[\]{}"]/)
          case scanner.matched
          when '"' then skip_string(scanner)
          when "[", "{"
            depth += 1
            start = scanner.pos - 1 if depth == 2 && scanner.matched == "{"
          else
            found << span(bytes, start, scanner.pos) if depth == 2 && scanner.matched == "}"
            depth -= 1
          end
        end
        found
      end

      def skip_string(scanner)
        loop do
          scanner.scan_until(/["\\]/) or raise Nabu::ParseError, "obimd: unterminated string in data.json"
          break if scanner.matched == '"'

          scanner.pos += 1 # the escaped byte
        end
      end

      def span(bytes, start, finish)
        slice = SourceRead.slice(bytes, offset: start, length: finish - start, what: "obimd: data.json record")
        name = slice[/"RubbingName"\s*:\s*"([^"]+)"/, 1]
        raise Nabu::ParseError, "obimd: a data.json record at byte #{start} has no RubbingName" if name.nil?

        [name, start, finish - start]
      end

      def read_record(document_ref)
        slice = SourceRead.slice(bytes_of(document_ref.path), offset: document_ref.metadata.fetch("offset"),
                                                              length: document_ref.metadata.fetch("length"),
                                                              what: "obimd: #{document_ref.id} record slice")
        JSON.parse(SourceRead.utf8(slice, label: "obimd: #{document_ref.id} record slice"))
      end

      def character_map(path)
        path = File.expand_path(path)
        @chars[path] ||= JSON.parse(SourceRead.utf8_file(path, label: "obimd"))
      end

      # -- building ----------------------------------------------------------------

      def build_document(document_ref, record, chars)
        name = record.fetch("RubbingName")
        collection, short, number = collection_of(name)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: "#{short} #{number}",
          canonical_path: document_ref.path,
          metadata: { "collection" => collection, "number" => number,
                      "rubbing_image" => record["Rubbing"], "facsimile_image" => record["Facsimile"],
                      "facets" => { "collection" => { "value" => collection } } }.compact
        )
        record.fetch("RecordUtilSentenceGroupVoList").each_with_index do |group, index|
          document << passage(document_ref.id, group, index, chars)
        end
        raise Nabu::ParseError, "obimd: #{document_ref.id}: no inscription groups" if document.empty?

        document
      end

      def collection_of(name)
        match = NAME_SHAPE.match(name) or raise Nabu::ParseError, "obimd: unexpected RubbingName #{name.inspect}"
        collection, short = COLLECTIONS.fetch(match[1]) do
          raise Nabu::ParseError, "obimd: unknown collection prefix #{match[1].inspect} in #{name}"
        end
        [collection, short, match[2]]
      end

      def passage(urn, group, index, chars)
        label = group.fetch("GroupCategory")
        type = GROUP_TYPES.fetch(label.sub(/\d+\z/, "")) do
          raise Nabu::ParseError, "obimd: #{urn}: unknown GroupCategory #{label.inspect}"
        end
        glyphs = group.fetch("RecordUtilOracleCharVoList").each_with_index
                      .sort_by { |glyph, position| [glyph.fetch("OrderNumber"), position] }.map(&:first)
        raise Nabu::ParseError, "obimd: #{urn}: group #{index + 1} has no glyphs" if glyphs.empty?

        Nabu::Passage.new(
          urn: "#{urn}:#{index + 1}", language: LANGUAGE, sequence: index,
          text: Normalize.nfc(glyphs.map { |glyph| render(glyph, chars) }.join),
          annotations: annotations(label, type, glyphs)
        )
      end

      def render(glyph, chars)
        return MISSING if glyph.fetch("SeatFont") == 1

        entry = glyph["Label"] && chars[glyph["Label"]] or return UNRENDERABLE
        codepoint = entry.fetch("codepoint").to_s
        return codepoint unless codepoint.empty? || codepoint.match?(NO_GLYPH)

        Array(entry["transcription"]).find { |reading| !reading.to_s.empty? && !reading.match?(NO_GLYPH) } ||
          UNRENDERABLE
      end

      def annotations(label, type, glyphs)
        labels = glyphs.map { |glyph| glyph.fetch("SeatFont") == 1 ? nil : glyph["Label"] }
        sublabels = glyphs.map { |glyph| glyph.fetch("SeatFont") == 1 ? nil : glyph["SubLabel"] }
        marks = glyphs.each_with_index.filter_map do |glyph, position|
          [position.to_s, glyph.fetch("Mark")] unless glyph.fetch("Mark") == -1
        end.to_h
        result = { "group" => label, "group_type" => type, "labels" => labels }
        result["sublabels"] = sublabels unless sublabels == labels
        result["marks"] = marks unless marks.empty?
        result
      end
    end
  end
end
