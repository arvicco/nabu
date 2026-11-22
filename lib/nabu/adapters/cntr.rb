# frozen_string_literal: true

require_relative "cntr_mes_parser"
require_relative "../fetch/zip_fetch"

module Nabu
  module Adapters
    # CNTR — the Center for New Testament Restoration's electronic
    # transcriptions (Alan Bunning; github.com/Center-for-New-Testament-
    # Restoration/transcriptions): the EARLY WITNESSES of the Greek New
    # Testament themselves — papyri and majuscules to the fourth century
    # (P52, P66, P75, P46 … Sinaiticus 01, Alexandrinus 02, Vaticanus 03,
    # Ephraemi 04, Bezae 05), the extant manuscripts that quote the NT
    # (amulets, letters, lectionary and commentary fragments), and the
    # second- to fourth-century church fathers' quotations, each a verse-
    # keyed transcription in CNTR's Manuscript Encoding Specification (MES)
    # — the witness layer beside the held annotation editions (sblgnt,
    # macula-greek, opengnt, stepbible-tagnt), never a dedupe.
    #
    # == Delivery grains (enumerated at fixture time, commit 4e743a41)
    #
    # The repo holds 200 files: four top-level documentation files
    # (LICENSE.md, MES.g4 — the ANTLR grammar —, README.md, README.txt) and
    # 196 files in four folders, upstream's own data classes:
    #
    #   class 1/        130  continuous-text witnesses, by Gregory-Aland
    #                        number (P1…P141, 01…059, 0160…0326, O23) —
    #                        ACCEPTED
    #   class 2/         48  47 extant manuscripts quoting the NT, by
    #                        Trismegistos number (61709 = the amulet once
    #                        GA P50 …) — ACCEPTED; + README.txt (the
    #                        export's license notice) — SKIPPED by rule
    #   class 3/         13  12 church fathers' quotations, by CNTR's
    #                        four-letter author abbreviation (Orig, Iren,
    #                        ClmA …), each the reconstructed exemplar the
    #                        father quoted from — ACCEPTED; + README.txt —
    #                        SKIPPED by rule
    #   critical texts/   5  KJTR, RP, SR, ST, WH — SKIPPED by rule
    #
    # Reconciliation: 130 + 47 + 12 = 189 accepted + 2 READMEs + 5 critical
    # texts = 196; the 4 top-level files are provenance, skipped by rule
    # too (200 in all, every one counted in discovery_skips).
    #
    # The five critical texts, censused first-hand at the pin: KJTR (CNTR's
    # 2020 King James Textus Receptus), RP (Robinson-Pierpont 2025), SR
    # (CNTR's own 2022 Statistical Restoration), ST (Stephanus 1550), WH
    # (Westcott-Hort 1885) — accented, capitalized, punctuated modern
    # editions with the editorial marks only, 7,957 verse lines each. They are
    # EDITIONS, not witnesses: out of this source's scope by rule. None
    # duplicates a held text verbatim (the library holds SBLGNT, OpenGNT
    # and TAGNT's word amalgam, which marks WH/Byz/TR membership per word
    # but carries no standalone WH, RP, ST or TR verse text), and SR is
    # CNTR's own reconstruction, better taken from its own repo
    # (Center-for-New-Testament-Restoration/SR, word-tagged) — a recorded
    # widen, not v1.
    #
    # == Identity (FROZEN once used)
    #
    # Document urn = urn:nabu:cntr:<upstream identifier, downcased> —
    # urn:nabu:cntr:p52, …:01, …:o23, …:61709, …:orig (upstream's ids are
    # unique across its classes; the class rides metadata). Passage urn =
    # <doc>:<sblgnt's book stem>.<chapter>.<verse> (…:p52:john.18.31), in
    # the manuscript's own order (book order varies by manuscript).
    # Passages carry per-word tokens with the nt hub's citation_part, so
    # every witness aligns under `nabu align` (proiel-citation extractor,
    # single-document form).
    #
    # == Text policy
    #
    # CntrMesParser's header: the original scribe's reading, damaged and
    # supplied letters read through, every lacuna one "[…]"; the verbatim
    # MES, the extant-only reading, the later hands, the Leiden counts and
    # the word marks ride annotations. Text NFC at the boundary (grc is not
    # NFC-exempt; the witnesses' unaccented lowercase is already NFC).
    #
    # == Census at the pin (dry parse of all 189 witness files, 2026-11-21)
    #
    # 189 documents (130 / 47 / 12 by class) / 42,228 verse passages
    # (41,692 / 400 / 136) / 717,544 word tokens / 3,012 corrections; 0
    # parse errors. Of 42,492 verse lines: 42,228 passages + 260 letterless
    # verses (absent / absent-by-vid / present-by-vid — document metadata)
    # + 4 lines merged into the verse they repeat (01 1 Thess 2:13-14, 03
    # Rom 4:4-5 — deleted dittographies). One off-grammar mark is tolerated
    # and recorded (Orig 1 John 3:2, a stray ^ before a word's first
    # letter — mes_anomalies).
    #
    # == License
    #
    # CC BY-SA 4.0 → license_class "attribution". LICENSE.md is the full
    # legal code ("Creative Commons Attribution-ShareAlike 4.0
    # International"); README.md: "Copyright © 2020-2026 by Alan Bunning.
    # All rights reserved. Released under the Creative Commons
    # Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0)."
    # with the attribution term "You must give credit to Alan Bunning and
    # the Center for New Testament Restoration, and any derivative work
    # must likewise require that this attribution be included." Upstream's
    # own slip, recorded: README.md's license heading and README.txt read
    # "Creative Commons Attribution 4.0 International (CC BY-SA 4.0)" — the
    # BY name with the BY-SA code; LICENSE.md and the README's first line
    # govern (BY-SA). The greekcntr.org site (its witness metadata pages:
    # dates, provenance, material) is NOT under that license — its pages
    # say "Copying or distribution without the author's prior written
    # consent is expressly prohibited" — so v1 mines only the repo.
    #
    # == fetch / pin
    #
    # The repo has no tags or releases and is "generated directly from the
    # CNTR database" — every export re-uploads whole files (the 2026-10-01
    # export touched all of them), so a pin bump is expected to show full-
    # file churn, not line diffs. The fetch is ONE ZipFetch of GitHub's
    # commit-addressed archive (codeload …/zip/<COMMIT>, 4.3 MB), sha256-
    # verified BEFORE the tree mutates (the josephus-latin choreography):
    # the content is fixed by the commit in the URL, so a later upstream
    # push never moves this source. GitHub has served byte-identical
    # archives for a commit (two downloads compared at pin time); if it
    # ever regenerates one, the pin fails loudly with the tree untouched —
    # re-verify the commit and re-pin. The zip's single top directory maps
    # onto the workdir (ZipFetch), so canonical/cntr/ is upstream's tree.
    class Cntr < Nabu::Adapter
      REPO_URL = "https://github.com/Center-for-New-Testament-Restoration/transcriptions"
      COMMIT = "4e743a41a4b2ca010ece53229cd272aa59b1efe6" # main @ 2026-10-01 (the "10/1/2026" export)
      ZIP_URL = "https://codeload.github.com/Center-for-New-Testament-Restoration/transcriptions/" \
                "zip/#{COMMIT}".freeze
      ZIP_SHA256 = "fe4eb90c5e6eec8c04f76dbe013248a54e83d6d51bb73919b7d9c85472dbeca4"

      LANGUAGE = "grc"
      URN_PREFIX = "urn:nabu:cntr:"

      # Upstream folder => [class number, identifier system, title prefix].
      CLASSES = {
        "class 1" => [1, "Gregory-Aland", "GA"],
        "class 2" => [2, "Trismegistos", "TM"],
        "class 3" => [3, "CNTR author abbreviation", nil]
      }.freeze

      CLASS_NOTES = {
        1 => "continuous-text manuscript of the Greek New Testament",
        2 => "extant manuscript quoting the Greek New Testament",
        3 => "church father's quotations (the reconstructed exemplar)"
      }.freeze

      # Aliases from the CNTR Technical Reference §1.1.2 (identifiers only):
      # GA numbers CNTR merged into one manuscript, and class-2 items that
      # once carried GA numbers.
      ALIASES = {
        "P15" => "GA P15 + P16", "P49" => "GA P49 + P65", "P64" => "GA P64 + P67",
        "P77" => "GA P77 + P103", "029" => "GA 029 + 0113 + 0125 + 0139", "059" => "GA 059 + 0215",
        "61715" => "GA P7", "61868" => "GA P10", "62312" => "GA P12", "61709" => "GA P50",
        "61839" => "GA P62", "61695" => "GA P78", "61873" => "GA P99", "61645" => "GA P80",
        "61795" => "GA 0192 / GA l1604", "61914" => "GA 0212", "61871" => "GA O24"
      }.freeze

      CRITICAL_TEXTS_DIR = "critical texts"
      PROVENANCE_FILES = %w[LICENSE.md MES.g4 README.md README.txt].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "cntr",
        name: "CNTR — Center for New Testament Restoration electronic transcriptions " \
              "(early Greek NT witnesses, MES)",
        license: "CC BY-SA 4.0 (LICENSE.md; README.md: \"Copyright © 2020-2026 by Alan Bunning. " \
                 "All rights reserved. Released under the Creative Commons Attribution-ShareAlike " \
                 "4.0 International License (CC BY-SA 4.0).\") — credit: Alan Bunning and the " \
                 "Center for New Testament Restoration",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "cntr-mes"
      )

      def self.manifest
        MANIFEST
      end

      # #parse re-reads only the one file its ref names — safe for
      # rebuild's forked workers.
      def self.parallel_parse? = true

      # One HEAD against the commit-addressed archive (reachability; the
      # pinned body never drifts — drift means the PIN changed locally).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: "transcriptions@#{COMMIT[0, 8]}.zip", zip_url: ZIP_URL, metadata_url: nil,
          state_subdir: ""
        )]
      end

      # +pin+ exists for the WebMock'd fetch tests — real syncs keep the
      # frozen ZIP_SHA256.
      def initialize(pin: ZIP_SHA256)
        super()
        @pin = pin
      end

      # One DocumentRef per witness file, sorted by urn. A workdir without
      # the tree yields nothing; the same walk works under the attic.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        refs = census(workdir).fetch(:accepted).map { |rel| witness_ref(workdir, rel) }
        refs.sort_by(&:id).each(&block)
      end

      def discovery_skips(workdir)
        result = census(workdir)
        notes = result.fetch(:skipped).map { |rel, why| "#{rel}: skipped by rule — #{why}" } +
                result.fetch(:unrecognized).map { |rel| "#{rel}: unrecognized file in the CNTR tree" }
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: result.fetch(:skipped).size,
                                          unrecognized: result.fetch(:unrecognized).size, notes: notes)
      end

      def parse(document_ref)
        CntrMesParser.new.parse(document_ref.path, urn: document_ref.id,
                                                   title: document_ref.metadata.fetch("title"),
                                                   language: LANGUAGE,
                                                   metadata: document_ref.metadata.except("title", "language"))
      end

      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::ZipFetch.new(url: ZIP_URL, dir: workdir,
                                   attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        begin
          fetch.prepare!
          verify_pin!(fetch)
          guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
          fetch.complete!
        ensure
          fetch.cleanup!
        end
        Nabu::FetchReport.new(sha: COMMIT, fetched_at: Time.now, notes: fetch_notes(fetch))
      rescue ZipFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "cntr fetch failed into #{workdir}: #{e.message}"
      end

      private

      # Every file under the workdir (the attic and the fetcher's state file
      # aside), sorted into accepted witness files, skipped-by-rule files
      # (relpath => why) and unrecognized ones.
      def census(workdir)
        result = { accepted: [], skipped: {}, unrecognized: [] }
        Dir.glob("**/*", File::FNM_DOTMATCH, base: workdir).sort.each do |rel|
          next if rel.start_with?("#{ATTIC_DIRNAME}/") || rel == ATTIC_DIRNAME
          next if File.basename(rel) == Nabu::ZipFetch::STATE_FILE
          next unless File.file?(File.join(workdir, rel))

          classify(rel, result)
        end
        result
      end

      def classify(rel, result)
        folder = File.dirname(rel)
        name = File.basename(rel)
        if CLASSES.key?(folder) && name == "README.txt"
          result[:skipped][rel] = "the export's license notice (provenance, not a witness)"
        elsif CLASSES.key?(folder) && name.match?(/\A[0-9A-Za-z]+\.txt\z/)
          result[:accepted] << rel
        elsif folder == CRITICAL_TEXTS_DIR && name.end_with?(".txt")
          result[:skipped][rel] = "a modern critical edition, not a witness (out of the witness-layer scope)"
        elsif folder == "." && PROVENANCE_FILES.include?(name)
          result[:skipped][rel] = "repository documentation (license, MES grammar, readme)"
        elsif folder == "." && !name.end_with?(".txt")
          nil # other root furniture (a checkout's own files, the fixture manifest) — never upstream data
        else
          result[:unrecognized] << rel
        end
      end

      def witness_ref(workdir, rel)
        number, system, prefix = CLASSES.fetch(File.dirname(rel))
        id = File.basename(rel, ".txt")
        title = prefix ? "#{prefix} #{id}" : "#{id} (patristic citations)"
        title += " (#{ALIASES[id]})" if number == 2 && ALIASES.key?(id)
        metadata = { "title" => title, "language" => LANGUAGE, "cntr_id" => id, "cntr_class" => number,
                     "class_note" => CLASS_NOTES.fetch(number), "identifier_system" => system }
        metadata["aliases"] = ALIASES[id] if ALIASES.key?(id)
        Nabu::DocumentRef.new(source_id: MANIFEST.id, id: "#{URN_PREFIX}#{id.downcase}",
                              path: File.expand_path(File.join(workdir, rel)), metadata: metadata)
      end

      def verify_pin!(fetch)
        return if fetch.not_modified? || fetch.sha == @pin

        raise Nabu::FetchError,
              "cntr: the commit archive misses its sha256 pin (expected #{@pin}, got #{fetch.sha}) — " \
              "the archive is commit-addressed (#{COMMIT[0, 12]}), so GitHub regenerated it or the body " \
              "is corrupt; re-verify #{ZIP_URL} and re-pin ZIP_SHA256 deliberately"
      end

      def fetch_notes(fetch)
        base = fetch.not_modified? ? "not modified (304)" : "commit #{COMMIT[0, 8]} archive sha256 pin verified"
        [base, attic_notes(fetch.atticked)].compact.join("; ")
      end
    end
  end
end
