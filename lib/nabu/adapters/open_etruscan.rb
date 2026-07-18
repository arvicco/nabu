# frozen_string_literal: true

require_relative "flat_csv_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The OpenEtruscan adapter (P29-0; the P17-5 Phase B scope): the
    # "Etruscan Machine Learning Corpus" — 6,567 quality-tagged Etruscan
    # inscriptions (Zenodo record 20075836, v1.0.0, 2026-05-07; OpenEtruscan
    # Project / Edoardo Panichi; ~71% from the Larth dataset of Vico &
    # Spanakis 2023, ~29% from CIE Vol. I extractions). The FIRST flat-csv
    # corpus source: one CSV row per inscription, one document per row.
    #
    # == Quality classes and the skip rule
    #
    # Upstream's own three-class data_quality tag governs discovery:
    # `clean` (6,094) and `needs_review` (154) rows mint documents —
    # needs_review carries its honest tag in document metadata — while
    # `ocr_failed` rows (319; upstream's own words: "digit-substitution OCR
    # junk, kept for diagnostic / error analysis only") are SKIPPED BY RULE
    # and counted in discovery_skips. The author's own data-quality caveat
    # ("many inscriptions are really noisy and not really reliable",
    # recorded at survey time, P17-5) rides the 02-sources row verbatim.
    #
    # == Text layers (the epigraphic-conventions decision)
    #
    # raw_text — the carved glyph stream, Old Italic where available, the
    # scholarly transliteration where the row came in transliterated — IS
    # the passage text (canonical means canonical). The regenerated layers
    # ride as annotations verbatim: `transliterated` (Bonfante/Wallace
    # conventions), `italic` (regenerated U+10300–1032F glyph stream, when
    # philologically defensible upstream), `words` (intact tokens only).
    # text_normalized is minted from the TRANSLITERATED layer when present
    # (else the pristine text) — the ccmh-txt documented-derivation seam:
    # the derivation source is stored verbatim in annotations, so the
    # search form stays recomputable from the stored passage alone, and
    # `search`/`search --fuzzy` speak the scholarly Latin transliteration
    # instead of raw Old Italic codepoints.
    #
    # == Dates and findspots
    #
    # year_from/year_to are BCE-POSITIVE upstream ("675.0" = 675 BCE) and
    # carried VERBATIM in document metadata; the sign flip to signed
    # historical years happens in ONE place, the axis extractor
    # (Store::AxisBuilder::OpenEtruscanDates), pinned by fixture. The
    # findspot side-join rides the second fetched artifact (the ccl
    # crosswalk precedent): Larth's Data/Etruscan.csv carries the 456
    # city-tagged rows OpenEtruscan dropped in cleaning; the extractor
    # joins them back on the shared inscription ids as place rows.
    #
    # == Translations (registry `translations: true`)
    #
    # 1,800 rows carry an English gloss; those mint -en sibling documents
    # (the riig -fr shape): same row, language eng, one passage. Same CC BY
    # grant — no license override.
    #
    # == License
    #
    # Zenodo record license field: cc-by-4.0 (CC BY 4.0) → attribution.
    # The findspots sidecar comes from the Larth repo, LICENSE CC BY 4.0
    # (verified 2026-07-18; the provenance caveat DISSOLVED 2026-07-14 when
    # upstream added the LICENSE on owner request) — same class.
    #
    # == fetch / sync policy
    #
    # Two FileFetch artifacts, two-phase (the wiktionary-recon
    # choreography): corpus/openetruscan_clean.csv from the immutable
    # Zenodo v1.0.0 record and findspots/Etruscan.csv from the Larth repo
    # at a PINNED commit — both sha256-pinned in this class; drift aborts
    # BEFORE the tree mutates (an owner re-pin decision, the corph
    # doctrine). sync_policy: frozen. Checked at build time (2026-07-18):
    # the record has NO v2 deposit — v1.0.0 (concept 20075835) is the only
    # version.
    class OpenEtruscan < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/20075836"
      CORPUS_URL = "https://zenodo.org/api/records/20075836/files/openetruscan_clean.csv/content"
      LARTH_COMMIT = "daf4972175f45b48188fe36671db3a0e081e5130" # main @ 2026-07-14, LICENSE CC BY 4.0
      FINDSPOTS_URL = "https://raw.githubusercontent.com/GianlucaVico/Larth-Etruscan-NLP/" \
                      "#{LARTH_COMMIT}/Data/Etruscan.csv".freeze

      # The frozen pins (sha256 of the full artifacts, computed 2026-07-18;
      # the corpus md5 f9cfce78… matches Zenodo's own checksum field). A
      # future version is a NEW pin the owner verifies before re-syncing.
      CORPUS_SHA256 = "4fc09af94005655bfe26affeeb48295c88606ae23c8dbc33ff5436f9083f69f8"
      FINDSPOTS_SHA256 = "e00bbff1858dbfd24579785784ca913a1dfc71f1722b8a6f907acba5b56a260a"

      CORPUS_DIRNAME = "corpus"
      CORPUS_FILENAME = "openetruscan_clean.csv"
      FINDSPOTS_DIRNAME = "findspots"
      FINDSPOTS_FILENAME = "Etruscan.csv"

      URN_PREFIX = "urn:nabu:open-etruscan:"
      LANGUAGE = "ett"
      SKIP_QUALITY = "ocr_failed"

      REQUIRED_HEADERS = %w[
        id raw_text canonical_transliterated canonical_italic canonical_words_only
        translation year_from year_to intact_token_ratio data_quality
      ].freeze

      # The annotation layers, CSV column → annotation key (verbatim carry;
      # empty upstream cells mint no key).
      LAYER_COLUMNS = {
        "canonical_transliterated" => "transliterated",
        "canonical_italic" => "italic",
        "canonical_words_only" => "words"
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "open-etruscan",
        name: "OpenEtruscan — Etruscan Machine Learning Corpus (Zenodo 20075836)",
        license: "CC BY 4.0 (Zenodo record 20075836 license field cc-by-4.0, v1.0.0 2026-05-07, " \
                 "OpenEtruscan Project / Edoardo Panichi; findspots sidecar from the Larth repo, " \
                 "LICENSE CC BY 4.0 — Vico & Spanakis 2023, ALP2023)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "flat-csv"
      )

      def self.manifest
        MANIFEST
      end

      # Two HEADs, one per artifact, each against its own subdir's
      # FileFetch state. No metadata endpoint serves the license as JSON
      # (the Zenodo API record body carries volatile stats — the diorisis
      # false-alarm lesson), so the probe's license row honestly reads
      # unchecked.
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: CORPUS_FILENAME, zip_url: CORPUS_URL, metadata_url: nil,
            state_subdir: CORPUS_DIRNAME, state_file: FileFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: FINDSPOTS_FILENAME, zip_url: FINDSPOTS_URL, metadata_url: nil,
            state_subdir: FINDSPOTS_DIRNAME, state_file: FileFetch::STATE_FILE
          )
        ]
      end

      # The stable urn for an upstream inscription id: downcased, runs of
      # anything outside [a-z0-9.] collapsed to "-" ("CIE 2609" →
      # …:cie-2609, "Cr 2.20" → …:cr-2.20, "CIE 52a, b" → …:cie-52a-b).
      # Censused unique across the full corpus (6,567 ids, 0 collisions).
      # The axis extractor mints join urns through this same method — one
      # rule, no drift.
      def self.urn_for(row_id)
        slug = row_id.strip.downcase.gsub(/[^a-z0-9.]+/, "-").gsub(/\A-+|-+\z/, "")
        "#{URN_PREFIX}#{slug}"
      end

      # The documented text_normalized derivation (class note): the stored
      # transliteration layer when present, else the pristine text. The
      # conformance suite pins every passage to the minted form of this.
      def self.search_source(text, annotations)
        annotations["transliterated"] || text
      end

      # +translations+ arrives via SourceRegistry::Entry#build_adapter; the
      # sha keywords exist for the WebMock'd fetch tests — real syncs keep
      # the frozen pins.
      def initialize(translations: false, corpus_sha256: CORPUS_SHA256,
                     findspots_sha256: FINDSPOTS_SHA256)
        super()
        @translations = translations
        @pins = { CORPUS_DIRNAME => corpus_sha256, FINDSPOTS_DIRNAME => findspots_sha256 }
        @corpus_cache = {}
      end

      # One ref per non-ocr_failed row, in file order (plus the -en sibling
      # for translated rows when opted in). A workdir without the corpus
      # CSV yields nothing (the day-one pre-fetch state); the same walk
      # works under the attic (same relative shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        each_minted_row(workdir) do |row, path|
          urn = self.class.urn_for(row.fetch("id"))
          yield document_ref(urn, path, row)
          if @translations && present(row["translation"])
            yield document_ref("#{urn}-en", path, row, kind: "translation")
          end
        end
      end

      # The ocr_failed census (P11-7): an explicit, benign skip — honest,
      # expected, quiet. Nothing is ever unrecognized in a headered CSV.
      def discovery_skips(workdir)
        skipped = 0
        each_corpus_row(workdir) { |row, _path| skipped += 1 if skip?(row) }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        row = corpus_rows(document_ref.path)[document_ref.metadata.fetch("row_id")]
        raise ParseError, "#{document_ref.path}: no corpus row for #{document_ref.id}" if row.nil?

        if document_ref.metadata["kind"] == "translation"
          translation_document(row, document_ref)
        else
          base_document(row, document_ref)
        end
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # Both artifacts two-phase (the wiktionary-recon choreography): all
      # prepare with the live tree untouched, the sha pins verify against
      # the held bodies, the breaker sees the combined doomed set, then all
      # complete. Drift aborts with the tree byte-unchanged.
      def fetch(workdir, progress: nil, force: false)
        fetches = file_fetches(workdir, progress)
        fetches.each_value(&:prepare!)
        verify_pins!(fetches)
        guard_mass_deletion!(workdir, fetches.values.flat_map(&:doomed_paths), force: force)
        fetches.each_value(&:complete!)
        Nabu::FetchReport.new(sha: fetches.fetch(CORPUS_DIRNAME).sha, fetched_at: Time.now,
                              notes: fetch_notes(fetches))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "open-etruscan fetch failed into #{workdir}: #{e.message}"
      end

      private

      def present(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end

      def skip?(row)
        row["data_quality"].to_s.strip == SKIP_QUALITY
      end

      def document_ref(id, path, row, kind: nil)
        metadata = { "row_id" => row.fetch("id") }
        metadata["kind"] = kind if kind
        Nabu::DocumentRef.new(source_id: manifest.id, id: id, path: path, metadata: metadata)
      end

      # -- corpus reading ------------------------------------------------------

      def each_corpus_row(workdir, &)
        Dir.glob(File.join(workdir, "**", CORPUS_FILENAME)).first(1).each do |path|
          expanded = File.expand_path(path)
          parser.each_row(expanded) { |row| yield row, expanded }
        end
      end

      def each_minted_row(workdir)
        each_corpus_row(workdir) do |row, path|
          yield row, path unless skip?(row)
        end
      end

      def parser
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS)
      end

      # id → row for one parsed corpus file, memoized per path (the corph
      # pattern — parse is called once per ref, the file holds every ref).
      def corpus_rows(path)
        @corpus_cache[path] ||= parser.each_row(path).to_h { |row| [row.fetch("id"), row] }
      end

      # -- document building ---------------------------------------------------

      def base_document(row, document_ref)
        text = present(row["raw_text"])
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: row has no raw_text" if text.nil?

        annotations = layer_annotations(row)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, title: row.fetch("id"),
          canonical_path: document_ref.path, metadata: row_metadata(row)
        )
        document << Nabu::Passage.new(
          urn: "#{document_ref.id}:1", language: LANGUAGE,
          text: Normalize.nfc(text),
          text_normalized: Normalize.search_form(
            self.class.search_source(text, annotations), language: LANGUAGE
          ),
          annotations: annotations, sequence: 0
        )
        document
      end

      def translation_document(row, document_ref)
        text = present(row["translation"])
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: row has no translation" if text.nil?

        document = Nabu::Document.new(
          urn: document_ref.id, language: "eng",
          title: "#{row.fetch('id')} — English translation",
          canonical_path: document_ref.path, metadata: { "kind" => "translation" }
        )
        document << Nabu::Passage.new(
          urn: "#{document_ref.id}:1", language: "eng", text: Normalize.nfc(text), sequence: 0
        )
        document
      end

      def layer_annotations(row)
        LAYER_COLUMNS.each_with_object({}) do |(column, key), annotations|
          value = present(row[column])
          annotations[key] = Normalize.nfc(value) if value
        end
      end

      # data_quality/intact_token_ratio always; the BCE-positive bounds
      # verbatim when dated (the sign flip is OpenEtruscanDates', class
      # note).
      def row_metadata(row)
        metadata = { "id" => row.fetch("id"), "data_quality" => row.fetch("data_quality") }
        %w[intact_token_ratio year_from year_to].each do |column|
          value = present(row[column])
          metadata[column] = value if value
        end
        metadata
      end

      # -- fetch ---------------------------------------------------------------

      def file_fetches(workdir, progress)
        {
          CORPUS_DIRNAME => file_fetch(workdir, progress, CORPUS_DIRNAME, CORPUS_FILENAME, CORPUS_URL),
          FINDSPOTS_DIRNAME => file_fetch(workdir, progress, FINDSPOTS_DIRNAME, FINDSPOTS_FILENAME,
                                          FINDSPOTS_URL)
        }
      end

      def file_fetch(workdir, progress, subdir, filename, url)
        FileFetch.new(
          url: url, dir: File.join(workdir, subdir), filename: filename,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, subdir), progress: progress
        )
      end

      def verify_pins!(fetches)
        fetches.each do |subdir, fetch|
          expected = @pins.fetch(subdir)
          next if fetch.sha == expected

          raise Nabu::FetchError,
                "open-etruscan: #{subdir} artifact drifted — fetched sha256 #{fetch.sha} != pinned " \
                "#{expected}; the deposit is frozen at v1.0.0 / Larth commit #{LARTH_COMMIT[0, 12]} — " \
                "review upstream and re-pin (owner decision)"
        end
      end

      def fetch_notes(fetches)
        shas = fetches.map { |subdir, fetch| "#{subdir} #{fetch.sha[0, 12]}" }
        [shas.join(" · "), attic_notes(fetches.values.flat_map(&:atticked))].compact.join("; ")
      end
    end
  end
end
