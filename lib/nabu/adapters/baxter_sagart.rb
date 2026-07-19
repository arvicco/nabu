# frozen_string_literal: true

require_relative "flat_csv_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # The Baxter-Sagart Old Chinese reconstruction adapter (P32-3): the
    # yawnoc TSV dump of the Baxter & Sagart 2014 reconstruction — 4,959
    # rows (zi / pinyin / Middle Chinese + structural analysis / Old
    # Chinese / gloss / GSR / HYDZD / radical / strokes / codepoint), ONE
    # sha-pinned file minting TWO dictionaries (the EDL one-file-two-shelves
    # precedent): `baxter-sagart-oc` (och — the OC lane) and
    # `baxter-sagart-mc` (ltc — the MC lane), so both reconstruction stages
    # of the Sino axis hold a shelf. Stands BESIDE the kaikki wiktionary-zh
    # extract's per-entry B-S readings as a provenance-distinct witness
    # (the MW-beside-kaikki precedent) — never deduped.
    #
    # == THE PROVENANCE CHAIN (the license verdict, recorded whole)
    #
    # The TSV repo (github.com/yawnoc/baxter-sagart-old-chinese, pinned
    # commit below) carries NO license file — it is a faithful dump ("minor
    # (whitespace) cleanup") of the xlsx published by the authors'
    # University of Michigan site, so the CONTENT license governs. That
    # site is dead (ocbaxtersagart.lsait.lsa.umich.edu → 403,
    # sites.lsa.umich.edu/ocbaxtersagart → 403, both verified 2026-07-19);
    # its grant survives in the Wayback capture of 2025-03-12
    # (http://web.archive.org/web/20250312164901/http://ocbaxtersagart.lsait.lsa.umich.edu/),
    # verbatim: "The files on this page (related to Baxter & Sagart 2014:
    # Old Chinese: a new reconstruction, New York, Oxford University Press)
    # by William H. Baxter and Laurent Sagart are licensed under CC BY 4.0"
    # → license_class attribution, credited to Baxter & Sagart 2014. The
    # capture's own BaxterSagartOC2015-10-13.xlsx link is the named second
    # witness of the content (not fetched — the TSV is the machine shape).
    #
    # == What one row yields (per lane)
    #
    # - entry_id: the character; polyphones (722 characters, up to 5
    #   readings) get a positional ":<n>" suffix in file order (the
    #   wiktionary-jsonl homograph convention) — stable while the pinned
    #   file is stable.
    # - headword: the character (NFC); gloss: the English gloss verbatim
    #   (3 upstream rows are non-NFC — 阿/會/亘 glosses — composed at the
    #   boundary per house rule).
    # - body: OC-first in the och lane, MC-first in the ltc lane; the
    #   unnamed 4th TSV column (the MC structural analysis, "('- + -oj A)")
    #   rides the MC line; the one py-less row (瀾) omits its pinyin line;
    #   trailing upstream spaces in OC values (4,708 rows) are stripped.
    # - citations/reflexes: always empty — the TSV names no descendants.
    #
    # == fetch / sync policy
    #
    # One FileFetch from the pinned commit's raw URL, sha256-verified BEFORE
    # the tree mutates (the larth-etp choreography); the repo still moves
    # occasionally → sync_policy: manual, owner re-pins.
    class BaxterSagart < Nabu::Adapter
      REPO_URL = "https://github.com/yawnoc/baxter-sagart-old-chinese"
      COMMIT = "a448f53a311dc11fe903a98323a4cfd3ba5322c1" # master @ 2026-07-11 "Fix duplicated rows"
      TSV_URL = "https://raw.githubusercontent.com/yawnoc/baxter-sagart-old-chinese/" \
                "#{COMMIT}/BaxterSagartOC2015-10-13.tsv".freeze
      TSV_SHA256 = "0151fafbb65277c9a522e22ec08f18dd442839cc44f6fd026f15eb2ae9b3d8c3"

      FILENAME = "BaxterSagartOC2015-10-13.tsv"

      # The 4th column is unnamed upstream (the MC structural analysis);
      # FlatCsvParser keys it "".
      REQUIRED_HEADERS = ["zi", "py", "MC", "", "OC", "gloss", "GSR", "HYDZD",
                          "rad", "str", "Unicode"].freeze

      WAYBACK_CAPTURE = "http://web.archive.org/web/20250312164901/" \
                        "http://ocbaxtersagart.lsait.lsa.umich.edu/"

      # The two lanes this one TSV mints (the EDL precedent). Body lead
      # order is the lane's own reconstruction stage.
      DICTIONARIES = {
        "baxter-sagart-oc" => {
          language: "och", lead: :oc,
          title: "Baxter-Sagart 2014 — Old Chinese reconstruction (OC lane)"
        }.freeze,
        "baxter-sagart-mc" => {
          language: "ltc", lead: :mc,
          title: "Baxter-Sagart 2014 — Middle Chinese transcription (MC lane)"
        }.freeze
      }.freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "baxter-sagart",
        name: "Baxter-Sagart Old Chinese reconstruction (2015-10-13 TSV, yawnoc dump)",
        license: "CC BY 4.0 — the authors' grant on the dead Michigan host, verbatim from the Wayback " \
                 "capture #{WAYBACK_CAPTURE} (2025-03-12): \"The files on this page (related to Baxter " \
                 "& Sagart 2014: Old Chinese: a new reconstruction, New York, Oxford University Press) " \
                 "by William H. Baxter and Laurent Sagart are licensed under CC BY 4.0\". The TSV repo " \
                 "itself is license-less; the content license governs. Credit: Baxter & Sagart 2014.",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "flat-csv"
      )

      def self.manifest
        MANIFEST
      end

      # Entries, not passages (architecture §11) — SyncRunner/Rebuild route
      # through Store::DictionaryLoader.
      def self.content_kind = :dictionary

      # One HEAD against the pinned raw URL (reachability; the commit-pinned
      # body never drifts — drift means the PIN changed locally).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: TSV_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +tsv_sha256+ exists for the WebMock'd fetch tests — real syncs keep
      # the frozen pin.
      def initialize(tsv_sha256: TSV_SHA256)
        super()
        @tsv_sha256 = tsv_sha256
      end

      # One DocumentRef per lane against the one TSV (the EDL shape). A
      # workdir without the file yields nothing; the same walk works under
      # the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "**", FILENAME)).first(1).each do |path|
          DICTIONARIES.each_key do |slug|
            yield Nabu::DocumentRef.new(
              source_id: manifest.id, id: "#{slug}:#{FILENAME}",
              path: File.expand_path(path), metadata: { "dictionary" => slug }
            )
          end
        end
      end

      def parse(document_ref)
        slug = document_ref.metadata.fetch("dictionary")
        lane = DICTIONARIES.fetch(slug)
        document = Nabu::DictionaryDocument.new(
          slug: slug, language: lane.fetch(:language),
          title: lane.fetch(:title), canonical_path: document_ref.path
        )
        occurrences = Hash.new(0)
        parser.each_row(document_ref.path) do |row|
          document << build_entry(row, lane, occurrences, document_ref.path)
        end
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "baxter-sagart: #{document_ref.id}: #{e.message}"
      end

      # FileFetch phases run separately so the sha pin verifies BEFORE the
      # tree mutates (the larth-etp choreography).
      def fetch(workdir, progress: nil, force: false)
        fetch = FileFetch.new(
          url: TSV_URL, dir: workdir, filename: FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress
        )
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "baxter-sagart fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        FlatCsvParser.new(required_headers: REQUIRED_HEADERS, col_sep: "\t")
      end

      def verify_pin!(fetch)
        return if fetch.sha == @tsv_sha256

        raise Nabu::FetchError,
              "baxter-sagart: #{FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned " \
              "#{@tsv_sha256} (commit #{COMMIT[0, 12]}); review upstream and re-pin (owner decision)"
      end

      # -- entry building ------------------------------------------------------

      def build_entry(row, lane, occurrences, path)
        zi = row.fetch("zi").to_s.strip
        occurrences[zi] += 1
        entry_id = occurrences[zi] > 1 ? "#{zi}:#{occurrences[zi]}" : zi
        Nabu::DictionaryEntry.new(
          entry_id: entry_id, key_raw: zi, language: lane.fetch(:language),
          headword: Normalize.nfc(zi),
          headword_folded: Normalize.search_form(zi, language: lane.fetch(:language)),
          gloss: gloss(row),
          body: body_text(row, lane.fetch(:lead)),
          citations: []
        )
      rescue Nabu::ValidationError, Normalize::EncodingError => e
        raise Nabu::ParseError, "baxter-sagart: row zi=#{zi.inspect} in #{path}: #{e.message}"
      end

      def gloss(row)
        text = row["gloss"].to_s.strip
        text.empty? ? nil : Normalize.nfc(text)
      end

      def body_text(row, lead)
        recon = [oc_line(row), mc_line(row)]
        recon.reverse! if lead == :mc
        Normalize.nfc([*recon, pinyin_line(row), refs_line(row)].compact.join("\n"))
      end

      def oc_line(row)
        oc = row["OC"].to_s.strip
        oc.empty? ? nil : "OC: #{oc}"
      end

      def mc_line(row)
        mc = row["MC"].to_s.strip
        return nil if mc.empty?

        analysis = row[""].to_s.strip
        analysis.empty? ? "MC: #{mc}" : "MC: #{mc} #{analysis}"
      end

      def pinyin_line(row)
        py = row["py"].to_s.strip
        py.empty? ? nil : "pinyin: #{py}"
      end

      def refs_line(row)
        "refs: GSR #{row['GSR']} · HYDZD #{row['HYDZD']} · radical #{row['rad']} · " \
          "strokes #{row['str']} · #{row['Unicode']}"
      end
    end
  end
end
