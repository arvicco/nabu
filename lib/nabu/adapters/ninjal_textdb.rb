# frozen_string_literal: true

require "digest"
require_relative "../file_fetch"
require_relative "../zip_fetch"
require_relative "../normalize"
require_relative "ninjal_txt_parser"
require_relative "ninjal_nippo_lane"

module Nabu
  module Adapters
    # ninjal-textdb — NINJAL's "Text Data Sets for Research on the History of
    # Japanese" (日本語史研究用テキストデータ集, www2.ninjal.ac.jp/
    # textdb_dataset/): static transcription files, one per work volume per
    # layer, under per-work dataset directories. THIS adapter holds the
    # KIRISHITAN slice — the Jesuit mission press's romanized Japanese —
    # with the full-site census (DATASETS) recorded for the future widen.
    #
    # == The slice (census 2026-11-04 over the index's 24 dataset dirs)
    #
    # TAKEN: amhk — Feiqe no monogatari, the Amakusa Heike (1592, British
    # Library Or.59.aa.1); amis — Esopo no fabulas (1593, the same volume);
    # cmhab — Contemptus Mundi jenbu (1596, the Herzog August Bibliothek copy
    # discovered 2017, transcribed by Osterkamp, Neutzler and Miyagawa); nipp —
    # the Nippo Jisho (Vocabulario da Lingoa de Iapam, 1603) entry-word data,
    # carried as the dictionary lane (NinjalNippoLane). Every other dataset
    # dir is skipped by rule at discovery (counted in discovery_skips, its
    # reason on its DATASETS row) and never fetched: the Edo share-bon /
    # ninjō-bon, the dictionaries Wamyō ruijushō / Butsurui shōko / Tetsugaku
    # jii / Genkai, the Saidaiji kunten text, the Hawaii Japanese-school
    # readers (and their PDF-only facsimile collection).
    #
    # == Grains and layers (each work page's own list)
    #
    # amhk and amis each serve three txt layers: -r- the original
    # romanization (Latin script), -k- a kanji-kana transliteration, and -rk-
    # the two juxtaposed per line. cmhab serves -r- (original romanization)
    # and -r-normalized- (a normalized version: word division, hyphenation
    # and ligatures regularized; the 目録 and 言葉の和らげ omitted). Every
    # layer is also rendered as an HTML view of the same txt.
    #
    # LAYER DESIGN: the ORIGINAL ROMANIZATION is the document text —
    # canonical means canonical: it is the print's own surface, and the
    # other layers are modern editorial products derived from it. The
    # companion layer rides each line as an annotation keyed on the shared
    # page.line citation — "kanji_kana" (amhk, amis: 9,681 / 2,251 lines,
    # keys identical to the -r- file, censused) and "normalized" (cmhab:
    # 8,943 of 10,173 lines; the 1,230 unmatched are the glossary and
    # contents pages the normalized version leaves out by its own rule 9).
    # Alignment counts ride metadata "layers". REJECTED, never fetched: the
    # -rk- files (byte-for-byte the -r- and -k- columns side by side — 0
    # mismatches over all 11,932 lines, censused; a pinned specimen skips by
    # rule) and the HTML views (renderings of the txt). The kanji-kana layer
    # is an annotation, so not full-text-searchable — indexing it is a
    # recorded future widen.
    #
    # Document = one work volume (urn:nabu:ninjal-textdb:amhk-001); passage =
    # one printed LINE, cited page.line — the transcription's own grain
    # (upstream numbers lines within pages). URN page segments: amhk/amis
    # page numbers verbatim, 扉 (title page) → "tobira", 序/序N (preface) →
    # "jo"/"joN"; cmhab "001" verbatim, "205[=206]" (misnumbered, corrected)
    # → "205=206", "[434]" (supplied) → "s434", "[*001]" (the unpaginated
    # title page) → "t001", a column suffix kept ("[445]a" → "s445a"). The
    # verbatim label rides annotation "page". Four Feiqe line numbers are
    # mis-keyed upstream as repeats of a neighbour (8.15, 119.13, 310.11,
    # 403.3, identically in both layers): the number stays verbatim and the
    # repeat is cited "-b" ("amhk-001:8.1-b", annotation line_repeat) —
    # never a guessed number (NinjalTxtParser::Line). First-sync expectation (full
    # files, censused): amhk-001 9,681 lines / 410 pages; amis-001 2,251 /
    # 96; cmhab-001 10,173 / 476 pages-or-columns; the lane 32,878 entries.
    #
    # Search: the romanization carries long ſ throughout, which the jpn fold
    # leaves alone (downcase does not reach U+017F), so text_normalized is
    # the jpn search form of the text with ſ → s — a documented derivation
    # recomputable from the stored text (the conformance hook pins it).
    #
    # == Axes
    #
    # Dates: each work page's own "Publication Date" (1592 / 1593 / 1596)
    # → a one-year envelope, class edition (the print year of the volume
    # transcribed). Place: amhk and amis name their imprint on the title
    # page — "Collegio Amacuſa ni voite" — → Amakusa (role imprint); the
    # cmhab title page names none (no place claimed). Language jpn → the
    # lect override jpn:lmj~latn (Late Middle Japanese, held in Latin
    # script — the registry's lmj note names these mission romanizations).
    # Kind: config/kind_map.yml folds metadata "dataset".
    #
    # == License (read 2026-11-04 on the amhk, amis, cmhab and nipp pages)
    #
    # amhk/amis: "The transcribed text (txt) on this site is licensed under a
    # Creative Commons Attribution 4.0 International License"; cmhab:
    # "Transcription (txt) on this site is licensed under a Creative Commons
    # 4.0 International license" (its link: creativecommons.org/licenses/
    # by/4.0/); nipp: "Entry Words Data of Nippojisho Ver.202510 on this site
    # is licensed under a Creative Commons Attribution 4.0 International
    # License" (and the readme: CC BY 4.0). → attribution.
    class NinjalTextdb < Nabu::Adapter
      SLUG = "ninjal-textdb"
      URN_PREFIX = "urn:nabu:ninjal-textdb:"
      LANGUAGE = "jpn"
      BASE_URL = "https://www2.ninjal.ac.jp/textdb_dataset/"
      SITE_URL = "#{BASE_URL}en/".freeze
      NIPPO_ZIP_URL = "#{BASE_URL}nipp/data/ew-nippo-202510.zip".freeze
      DELAY = 1.0

      MANIFEST = Nabu::SourceManifest.new(
        id: SLUG,
        name: "NINJAL Text Data Sets for Research on the History of Japanese — the Kirishitan materials",
        license: "CC BY 4.0 — each work page (read 2026-11-04): \"The transcribed text (txt) on this site is " \
                 "licensed under a Creative Commons Attribution 4.0 International License\" (Feiqe, Esopo); " \
                 "\"Transcription (txt) on this site is licensed under a Creative Commons 4.0 International " \
                 "license\" linking creativecommons.org/licenses/by/4.0/ (Contemptus Mundi); \"Entry Words " \
                 "Data of Nippojisho Ver.202510 on this site is licensed under a Creative Commons Attribution " \
                 "4.0 International License\" (Nippo Jisho). Facsimile images are not taken.",
        license_class: "attribution",
        upstream_url: SITE_URL,
        parser_family: "ninjal-txt",
        credit: "National Institute for Japanese Language and Linguistics (NINJAL), Text Data Sets for Research " \
                "on the History of Japanese (www2.ninjal.ac.jp/textdb_dataset). Contemptus Mundi [HAB copy]: " \
                "Sven Osterkamp, Sophie Neutzler (Ruhr University Bochum) and So Miyagawa (NINJAL). Nippo " \
                "Jisho entry words: OHSHIMA Hideyuki, with AIDA Taichi."
      )

      # The index's dataset directories (census 2026-11-04, in index order).
      Dataset = Data.define(:dir, :title, :section, :serves, :reason) do
        def taken? = reason.nil?
      end
      EDO = "Edo-period share-bon / ninjō-bon fiction (early-modern Japanese) — outside the adopted " \
            "Kirishitan slice; a future widen"
      HAWAII = "a 20th-century Hawaii Japanese-school reader (modern Japanese) — outside the Kirishitan slice"
      DATASETS = [
        Dataset.new(dir: "sksh", title: "Saidaiji-bon konkōmyō saishōō-kyō heian shoki-ten (vol. 1)",
                    section: "Kunten Shiryō", serves: "1 txt + 1 xml + the himawari zip",
                    reason: "an early-Heian kunten (glossed kanbun) text — a different layer model; a future widen"),
        Dataset.new(dir: "amhk", title: "Feiqe no monogatari [Amakusa edition] (1592)", section: "Kirishitan",
                    serves: "3 txt layers (r, k, rk)", reason: nil),
        Dataset.new(dir: "amis", title: "Esopo no fabulas [Amakusa edition] (1593)", section: "Kirishitan",
                    serves: "3 txt layers (r, k, rk)", reason: nil),
        Dataset.new(dir: "cmhab", title: "Contemptus Mundi [HAB copy] (1596)", section: "Kirishitan",
                    serves: "2 txt layers (r, r-normalized)", reason: nil),
        Dataset.new(dir: "kwrs", title: "Wamyō ruijushō [early movable type, 1617]", section: "Dictionary",
                    serves: "20 txt", reason: "a kanbun-glossed Heian dictionary in a 1617 print — a future widen"),
        Dataset.new(dir: "nipp", title: "Nippojisho (Vocabulario da Lingoa de Iapam, 1603)", section: "Dictionary",
                    serves: "1 zip (TSV + xlsx + readme)", reason: nil),
        Dataset.new(dir: "brsk", title: "Shokoku hōgen butsurui shōko (1775)", section: "Dictionary",
                    serves: "5 txt",
                    reason: "an Edo dialect dictionary — outside the Kirishitan slice; a future widen"),
        Dataset.new(dir: "tgzi", title: "Tetsugaku jii (1881)", section: "Dictionary", serves: "1 txt",
                    reason: "a Meiji philosophical glossary (modern Japanese) — outside the Kirishitan slice"),
        Dataset.new(dir: "genk", title: "Genkai (entry words, Ver.202510)", section: "Dictionary",
                    serves: "1 zip",
                    reason: "the Meiji dictionary Genkai's entry words — outside the Kirishitan slice"),
        Dataset.new(dir: "ywyj", title: "Yoshiwara yōji (1788)", section: "Share-bon/Ninjō-bon",
                    serves: "1 txt", reason: EDO),
        Dataset.new(dir: "agnm", title: "Urazato tokijirō akegarasu nochi no masayume (1821)",
                    section: "Share-bon/Ninjō-bon", serves: "15 txt", reason: EDO),
        Dataset.new(dir: "mssy", title: "Kosan kingorō kanamajiri musume setsuyō (1831)",
                    section: "Share-bon/Ninjō-bon", serves: "9 txt", reason: EDO),
        Dataset.new(dir: "umgy", title: "Shunshoku umegoyomi (1832)", section: "Share-bon/Ninjō-bon",
                    serves: "12 txt", reason: EDO),
        Dataset.new(dir: "tmsn", title: "Umegoyomi yokyō shunshoku tatsumi no sono (1833)",
                    section: "Share-bon/Ninjō-bon", serves: "12 txt", reason: EDO),
        Dataset.new(dir: "knhz", title: "Ukiyo shingata koi no hanazome (1833)", section: "Share-bon/Ninjō-bon",
                    serves: "9 txt", reason: EDO),
        Dataset.new(dir: "hnsd", title: "Hiyoku renri hana no shimadai (1836)", section: "Share-bon/Ninjō-bon",
                    serves: "12 txt", reason: EDO),
        Dataset.new(dir: "ssru", title: "Shunshoku renri no ume (1850)", section: "Share-bon/Ninjō-bon",
                    serves: "15 txt", reason: EDO),
        Dataset.new(dir: "edms", title: "Okumi sōjirō shunshoku edomurasaki (1864)", section: "Share-bon/Ninjō-bon",
                    serves: "9 txt", reason: EDO),
        Dataset.new(dir: "hn17", title: "Nihongo tokuhon, jinjōkayō [Hawai Kyōikukai, 1917 edition]",
                    section: "Japanese Language School Textbooks", serves: "6 txt", reason: HAWAII),
        Dataset.new(dir: "hn29", title: "Nihongo tokuhon [Hawai Kyōikukai, 1929 edition]",
                    section: "Japanese Language School Textbooks", serves: "6 txt", reason: HAWAII),
        Dataset.new(dir: "hn36", title: "Nihongo tokuhon [Hawai Kyōikukai, 1936 edition]",
                    section: "Japanese Language School Textbooks", serves: "12 txt", reason: HAWAII),
        Dataset.new(dir: "pi25", title: "Nihongo shoho [Department of Public Instruction, Territory of Hawaii]",
                    section: "Japanese Language School Textbooks", serves: "2 txt", reason: HAWAII),
        Dataset.new(dir: "mjeh", title: "Japanese-language textbooks compiled in Hawaii before WWII (Akutagawa " \
                                        "Collection)", section: "Japanese Language School Textbooks",
                    serves: "78 PDF facsimiles, no transcription",
                    reason: "facsimile images only — the library takes no images"),
        Dataset.new(dir: "newshistory", title: "News Archive", section: "site", serves: "release notes",
                    reason: "the site's news archive — no data")
      ].freeze

      # One taken work volume: its romanization file (the document) and the
      # companion layer that rides each line.
      Work = Data.define(:dir, :volume, :primary, :companion, :layer_key, :shape, :title, :year, :place)
      WORKS = [
        Work.new(dir: "amhk", volume: "001", primary: "amhk-r-001", companion: "amhk-k-001",
                 layer_key: "kanji_kana", shape: :paged, year: 1592, place: "Amakusa",
                 title: "Feiqe no monogatari (天草版平家物語) — Amakusa, 1592 — vol. 1, original romanization"),
        Work.new(dir: "amis", volume: "001", primary: "amis-r-001", companion: "amis-k-001",
                 layer_key: "kanji_kana", shape: :paged, year: 1593, place: "Amakusa",
                 title: "Esopo no fabulas (天草版伊曽保物語) — Amakusa, 1593 — original romanization"),
        Work.new(dir: "cmhab", volume: "001", primary: "cmhab-r-001", companion: "cmhab-r-normalized-001",
                 layer_key: "normalized", shape: :cited, year: 1596, place: nil,
                 title: "Contemptus Mundi jenbu (コンテムツス・ムンヂ), 1596 — HAB copy, original romanization")
      ].freeze

      FILES = WORKS.flat_map { |work| [work.primary, work.companion] }.freeze

      STATE_FILES = [Nabu::FileFetch::STATE_FILE, Nabu::ZipFetch::STATE_FILE].freeze
      RK_FILE = /\A[a-z]+-rk-\d{3}\.txt\z/
      NIPPO_EXTRAS = {
        "readme_ew-nippo-202510.txt" => "the data set's own documentation (column list, sources) — not entries",
        "ew-nippo-202510.xlsx" => "the Excel twin of the TSV (the readme: 内容は同じです — same content)"
      }.freeze

      def self.manifest = MANIFEST

      def self.dictionary_lane = NinjalNippoLane.new

      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        files = FILES.map do |stem|
          Nabu::Adapter::HttpProbeTarget.new(label: "#{stem}.txt", zip_url: txt_url(stem), metadata_url: nil,
                                             state_subdir: file_dir(stem), state_file: Nabu::FileFetch::STATE_FILE)
        end
        files + [Nabu::Adapter::HttpProbeTarget.new(label: "ew-nippo-202510.zip", zip_url: NIPPO_ZIP_URL,
                                                    metadata_url: nil, state_subdir: NinjalNippoLane::DIR)]
      end

      def self.dataset_of(stem) = stem[/\A[a-z]+/]

      def self.txt_url(stem) = "#{BASE_URL}#{dataset_of(stem)}/txt/#{stem}.txt"

      # One FileFetch dir per file (FileFetch treats every sibling as doomed).
      def self.file_dir(stem) = File.join(dataset_of(stem), stem)

      def self.file_path(workdir, stem) = File.join(workdir, file_dir(stem), "#{stem}.txt")

      # The page label → urn segment (class note); nil for an uncensused label.
      def self.page_segment(label, shape)
        case [shape, label]
        in [:paged, /\A\d+\z/] | [:cited, /\A\d{3}\z/] then label
        in [:paged, "扉"] then "tobira"
        in [:paged, /\A序(\d*)\z/] then "jo#{Regexp.last_match(1)}"
        in [:cited, /\A(\d{3})\[=(\d{3})\]\z/] then "#{Regexp.last_match(1)}=#{Regexp.last_match(2)}"
        in [:cited, /\A\[(\*?)(\d{3})\]([ab]?)\z/]
          "#{Regexp.last_match(1).empty? ? 's' : 't'}#{Regexp.last_match(2)}#{Regexp.last_match(3)}"
        else nil
        end
      end

      def discover(workdir)
        return enum_for(:discover, workdir) unless block_given?

        WORKS.each do |work|
          path = self.class.file_path(workdir, work.primary)
          next unless File.file?(path)

          yield Nabu::DocumentRef.new(source_id: SLUG, id: "#{URN_PREFIX}#{work.dir}-#{work.volume}",
                                      path: File.expand_path(path), metadata: { "dataset" => work.dir })
        end
      end

      # Out-of-slice datasets (never fetched) and the rejected grains that
      # do land skip by rule; anything else in the tree is unrecognized.
      def discovery_skips(workdir)
        notes = DATASETS.reject(&:taken?).map { |set| "#{set.dir}: #{set.title} — #{set.reason}" }
        unrecognized = []
        each_file(workdir) do |rel|
          next if accepted?(rel)

          name = File.basename(rel)
          note = skip_note(rel, name)
          note ? notes << "#{name}: #{note}" : unrecognized << rel
        end
        notes.concat(unrecognized.map { |rel| "#{rel}: unrecognized file in the ninjal-textdb tree" })
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: notes.size - unrecognized.size,
                                          unrecognized: unrecognized.size, notes: notes)
      end

      def parse(document_ref)
        work = WORKS.find { |candidate| document_ref.id == "#{URN_PREFIX}#{candidate.dir}-#{candidate.volume}" } or
          raise Nabu::ParseError, "#{SLUG}: unknown document #{document_ref.id}"
        primary = read(document_ref.path, work.shape)
        companion_path = self.class.file_path(File.expand_path("../..", File.dirname(document_ref.path)),
                                              work.companion)
        companion = File.file?(companion_path) ? read(companion_path, work.shape) : nil
        build(document_ref, work, primary, companion)
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Sequential FileFetch per layer file, then the Nippo zip — a polite
      # pause between requests (DELAY). Conditional GETs keep re-syncs cheap.
      def fetch(workdir, progress: nil, force: false)
        guard = ->(doomed) { guard_mass_deletion!(workdir, doomed, force: force) }
        attic = File.join(workdir, ATTIC_DIRNAME)
        results = FILES.map do |stem|
          dir = File.join(workdir, self.class.file_dir(stem))
          result = Nabu::FileFetch.sync!(url: self.class.txt_url(stem), dir: dir, filename: "#{stem}.txt",
                                         attic_dir: attic, progress: progress, guard: guard)
          sleep(fetch_delay)
          result
        end
        results << Nabu::ZipFetch.sync!(url: NIPPO_ZIP_URL, dir: File.join(workdir, NinjalNippoLane::DIR),
                                        attic_dir: attic, progress: progress, guard: guard)
        notes = ["#{FILES.size} txt + the Nippo zip", attic_notes(results.flat_map(&:atticked))].compact
        Nabu::FetchReport.new(sha: Digest::SHA256.hexdigest(results.map(&:sha).join("\n")), fetched_at: Time.now,
                              notes: notes.join("; "))
      rescue Nabu::FileFetch::Error, Nabu::ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "#{SLUG} fetch failed into #{workdir}: #{e.message}"
      end

      # Seam for tests (the politeness pause between GETs).
      def fetch_delay = DELAY

      private

      def read(path, shape)
        NinjalTxtParser.parse(SourceRead.utf8_file(path, label: SLUG), shape: shape, path: path)
      end

      def build(document_ref, work, primary, companion)
        layer = companion ? companion.lines.to_h { |line| [line.key, line.text] } : {}
        document = Nabu::Document.new(urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
                                      title: work.title, metadata: metadata(work, primary, companion, layer))
        primary.lines.each_with_index do |line, sequence|
          segment = self.class.page_segment(line.page, work.shape) or
            raise Nabu::ParseError, "#{document_ref.path}: uncensused page label #{line.page.inspect}"
          annotations = { "page" => line.page, "line" => line.line, "line_repeat" => (true unless line.repeat.zero?),
                          work.layer_key => layer[line.key] }.compact
          document << Nabu::Passage.new(
            urn: "#{document_ref.id}:#{segment}.#{line.key.delete_prefix("#{line.page}.")}", language: LANGUAGE,
            text: line.text,
            text_normalized: Normalize.search_form(line.text.tr("ſ", "s"), language: LANGUAGE),
            sequence: sequence, annotations: annotations
          )
        end
        document
      end

      def metadata(work, primary, companion, layer)
        keys = primary.lines.map(&:key)
        {
          "dataset" => work.dir, "volume" => work.volume, "layer" => "original romanization",
          "upstream_title" => primary.title, "base_text" => primary.base_text,
          "transcribers" => primary.transcribers, "release_history" => primary.history,
          "date" => { "not_before" => work.year, "not_after" => work.year,
                      "raw" => "Publication Date #{work.year}", "class" => "edition" },
          "place" => work.place, "place_role" => work.place && "imprint",
          "pages" => primary.lines.map(&:page).uniq.size,
          "layers" => { work.layer_key => layer_census(work, companion, keys, layer) }
        }.compact
      end

      def layer_census(work, companion, keys, layer)
        return { "file" => "#{work.companion}.txt", "present" => false } unless companion

        aligned = keys.count { |key| layer.key?(key) }
        { "file" => "#{work.companion}.txt", "present" => true, "aligned" => aligned,
          "unmatched" => keys.size - aligned, "orphaned" => (layer.keys - keys).size,
          "transcribers" => companion.transcribers }.compact
      end

      def each_file(workdir)
        return unless Dir.exist?(workdir)

        Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir).sort.each do |rel|
          next if rel.split(File::SEPARATOR).include?(ATTIC_DIRNAME) || !File.file?(File.join(workdir, rel))

          yield rel
        end
      end

      def accepted?(rel)
        FILES.any? { |stem| rel == File.join(self.class.file_dir(stem), "#{stem}.txt") } ||
          rel == File.join(NinjalNippoLane::DIR, NinjalNippoLane::TSV)
      end

      def skip_note(rel, name)
        return "the fetcher's own state pin — not upstream content" if STATE_FILES.include?(name)
        if name.match?(RK_FILE)
          return "upstream's -r-/-k- juxtaposition — both layers are taken line for line (0 mismatches, censused)"
        end
        return NIPPO_EXTRAS[name] if rel.start_with?("#{NinjalNippoLane::DIR}/") && NIPPO_EXTRAS.key?(name)

        nil
      end
    end
  end
end
