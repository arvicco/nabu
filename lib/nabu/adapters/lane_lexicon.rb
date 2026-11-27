# frozen_string_literal: true

require_relative "lane_tei_parser"
require_relative "source_read"

module Nabu
  module Adapters
    # Lane's Arabic-English Lexicon (Edward William Lane, London: Williams
    # and Norgate, 1863–1893) from the Alpheios repository
    # github.com/alpheios-project/lan — the Perseus digitization with the
    # Alpheios corrections. One dictionary shelf, slug "lane", language
    # ara (Classical Arabic: config/lect_overrides.yml maps it to ara:cla).
    # Parsing lives on LaneTeiParser (the lane-tei family).
    #
    # == Delivery grains (census at the pinned HEAD 7dd04e1, 2026-11-26)
    #
    # - db/lexica/ara/lan/u*.xml — 38 letter-bucket files, the ACCEPTED
    #   grain (one DocumentRef each; the entry is the entryFree inside).
    #   All 28 letters are present, each as one "…0.xml" main file named
    #   by its Buckwalter letter (u_A0 = ا … u_Y0 = ي, filed under div1
    #   n="Y" with an alif-maqsura head); eight "…1.xml" files carry the
    #   Supplement Lane-Poole printed after part VIII (pp. 2984–3064:
    #   uq1 uk1 ul1 um1 un1 uh1 uw1 u_Y1); uq2.xml is a variant copy and
    #   ua0.xml a duplicate (below). The dictionary is UNFINISHED upstream
    #   because Lane's was: ي (u_Y0, pp. 2974–2983) is thin, and many of
    #   its roots are one-line "See Supplement" stubs the Supplement never
    #   filled.
    # - db/indexes/ara-lan-index.xml — Alpheios's lemma → id lookup index
    #   (61,899 lemmas over all 44,829 distinct ids): REJECTED, a derived
    #   lookup aid, not lexicon text. It does not index the id-less
    #   paragraphs (3,010 of their 3,327 orths are absent), so it cannot
    #   key them either.
    # - dat/ara-lan-ids.dat — the same index as a flat form|id list
    #   (218,721 lines): REJECTED.
    # - **/__contents__.xml — five eXist-db collection descriptors: REJECTED.
    # Rejected grains count in discovery_skips with their note; anything
    # else under db/ or dat/ is unrecognized — loud.
    #
    # Upstream reconciliation (the whole-repo census): 49,473 entryFree
    # elements in the 38 files — 46,146 with @id/@key, 3,327 without.
    # Loaded: 48,795 = 49,473 − ua0.xml's 678 (640 id + 38 id-less)
    # collapsed; i.e. 45,506 id entries (44,829 distinct upstream ids +
    # uq2.xml's 677 re-used ones under its prefix) + 3,289 id-less
    # paragraphs. Nothing else is skipped.
    #
    # == The id design (decided on that census)
    #
    # (1) Entry identity = the upstream @id ("n14041"), kept bare: it is
    #     the identity Alpheios itself serves (the index and ids.dat key on
    #     it), it is stable across every upstream commit since the 2017
    #     transfer, and it makes the URN urn:nabu:dict:lane:n14041. Bucket
    #     file names are storage, not identity, so they enter an id only
    #     where upstream's own ids fail to be unique (2).
    # (2) Duplicates and collisions (the only id-uniqueness failures):
    #     - ua0.xml is a whole-file copy of u_0.xml (letter ذ, pp. 948–993,
    #       the same 678 entries; 639 byte-identical, one — n14061 —
    #       differing by a trailing space). Rule: a DUPLICATE_FILES member
    #       whose whitespace-collapsed text equals its original's collapses
    #       — not discovered, counted and named in discovery_skips. Should
    #       the copy ever diverge it loads as a variant (next rule), so no
    #       content is ever dropped by the rule.
    #     - uq2.xml re-uses ids n42477–n43153 for DIFFERENT words than the
    #       entries owning them in uq1.xml (436), uk1.xml (213) and
    #       u_Y0.xml (28). Evidence says it is an earlier copy of the ق–ك
    #       Supplement pages (2984–3006) that uq1 + uk1 re-split and
    #       renumbered: all 677 of its keys recur there (326 entries
    #       text-identical, the rest differing by the sense-milestone and
    #       dash corrections uq2 only partly received), and Alpheios's own
    #       index resolves all 677 ids to the uq1/uk1/u_Y0 words. Rule:
    #       the index-resolved owners keep the bare id; a VARIANT_FILES
    #       member's entries are qualified by its file stem
    #       ("uq2.n42477") and annotated copy: variant + variant_of. Both
    #       copies load — never silently dropped; the variant is visible
    #       as such.
    # (3) The id-less entries (3,327): Lane's numbered verb-form paragraphs
    #     (3,056 "2"…"10", 59 quadriliteral "R. Q."/"Q. Q."/"Q." ones), 199
    #     "See Supplement" stubs and 13 others (one text-less: uq2.xml's root
    #     قو, whose heading "قو: see قوى" is the whole article and becomes
    #     its body). They are NOT mere pointers:
    #     1,099 run past a one-line pointer (60+ characters) into real
    #     senses ("10 إِسْتَشْبَ3َ It is said in a trad., …"), and the
    #     pointer ones ("2 ذَمَّرَ see 1, in three
    #     places") are exactly what a reader meets when looking up a
    #     derived form. So they LOAD, with a derived stable id: the
    #     nearest preceding id entry of the same file + ordinal since it
    #     ("n14041.1"; before any id entry: file stem + ordinal, "uq2.1").
    #     Their "see N" pointers resolve, within the root, to the entry
    #     carrying paragraph N — the reader is taken to paragraph 1.
    # (4) Mined per entry (LaneTeiParser): headword (Arabic, NFC), root
    #     (the div2 heading — the root → entries grouping, also an entry
    #     facet), paragraph number, printed page from <pb n> (Lane's
    #     pagination runs continuously 1–3064 across all eight parts, so
    #     the page alone finds the printed Lane), English gloss, body, and
    #     the "see" cross-references.
    #
    # == License
    #
    # README verbatim: "This work is licensed under a Creative Commons
    # Attribution-ShareAlike 3.0 United States License." (credit: original
    # digitization by the Perseus Digital Library, Tufts University;
    # corrections by the Alpheios Project, Ltd.) → attribution.
    #
    # == Fetch
    #
    # GitFetch (attic + mass-deletion breaker), PINNED: upstream has been
    # dormant since 2019 (one README edit since), so a moved HEAD is an
    # event to review, never a cadence — the fetch aborts loudly on drift.
    class LaneLexicon < Nabu::Adapter
      REPO_URL = "https://github.com/alpheios-project/lan"

      # master HEAD at the 2026-11-26 census ("Update README.md",
      # 2026-04-19; the data last changed 2019-04-22).
      PINNED_SHA = "7dd04e1182c13a4b0883978867d2a3b04616542a"

      MANIFEST = Nabu::SourceManifest.new(
        id: "lane-lexicon",
        name: "Lane's Arabic-English Lexicon (Perseus digitization, Alpheios edition)",
        license: "CC BY-SA 3.0 US — README verbatim: \"This work is licensed under a Creative Commons " \
                 "Attribution-ShareAlike 3.0 United States License.\" Original digitization: Perseus " \
                 "Digital Library, Tufts University; corrections: The Alpheios Project, Ltd. " \
                 "(github.com/alpheios-project/lan)",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "lane-tei"
      )

      DICTIONARY_SLUG = "lane"
      DICTIONARY_TITLE = "An Arabic-English Lexicon (Lane)"
      LANGUAGE = LaneTeiParser::LANGUAGE
      LEXICON_DIR = File.join("db", "lexica", "ara", "lan")
      BUCKET_GLOB = "u*.xml"

      # Copy => original, collapsed while whitespace-equivalent (class note 2).
      DUPLICATE_FILES = { "ua0.xml" => "u_0.xml" }.freeze

      # Variant copy => the files owning its re-used ids (class note 2).
      VARIANT_FILES = { "uq2.xml" => "uq1.xml uk1.xml" }.freeze

      # The Supplement (pp. 2984–3064) and its variant copy.
      SUPPLEMENT_FILES = %w[uq1.xml uk1.xml ul1.xml um1.xml un1.xml uh1.xml uw1.xml u_Y1.xml uq2.xml].freeze

      # The rejected grains (class note), workdir-relative => why.
      REJECTED_GRAINS = {
        File.join("db", "indexes", "ara-lan-index.xml") =>
          "Alpheios's derived lemma index (lemma → entry id lookup aid), not lexicon text",
        File.join("dat", "ara-lan-ids.dat") => "the same lemma index as a flat form|id list"
      }.freeze
      CONTENTS_FILE = "__contents__.xml"

      # The tree discovery_skips censuses (upstream's README sits outside).
      CENSUS_DIRS = %w[db dat].freeze

      def self.manifest
        MANIFEST
      end

      def self.content_kind = :dictionary

      # +repo_url+/+pinned_sha+ exist for the tests (local upstream repos);
      # no-arg construction stays the registry contract.
      def initialize(repo_url: REPO_URL, pinned_sha: PINNED_SHA)
        super()
        @repo_url = repo_url
        @pinned_sha = pinned_sha
      end

      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: @repo_url, workdir: workdir, progress: progress, force: force)
        return report if report.sha == @pinned_sha

        raise Nabu::FetchError,
              "#{manifest.id}: upstream #{@repo_url} is at #{report.sha[0, 12]}, but the source is pinned " \
              "to #{@pinned_sha[0, 12]} — review the new commits (license + text) and re-pin (owner " \
              "decision; the upstream is dormant, so drift is an event, not a cadence)"
      end

      # One DocumentRef per bucket file, sorted by name; a collapsed
      # duplicate is not yielded (discovery_skips names it).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        bucket_paths(workdir).each do |path|
          name = File.basename(path)
          next if collapsed_duplicate?(path)

          yield Nabu::DocumentRef.new(
            source_id: manifest.id, id: "#{manifest.id}:#{name}", path: File.expand_path(path),
            metadata: ref_metadata(path)
          )
        end
      end

      def discovery_skips(workdir)
        accepted = bucket_paths(workdir).to_set { |path| File.expand_path(path) }
        skipped = []
        strays = []
        census_files(workdir).each do |path|
          rel = path.delete_prefix("#{workdir.chomp('/')}/")
          if accepted.include?(File.expand_path(path))
            skipped << duplicate_note(path) if collapsed_duplicate?(path)
          elsif (why = rejection(rel))
            skipped << "#{rel}: #{why}"
          else
            strays << "#{rel}: not a recognized Lane repository file"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped.size, unrecognized: strays.size,
                                          notes: skipped + strays)
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        document = Nabu::DictionaryDocument.new(slug: DICTIONARY_SLUG, language: LANGUAGE,
                                                title: DICTIONARY_TITLE, canonical_path: document_ref.path)
        LaneTeiParser.new.entries(document_ref.path, id_prefix: metadata["id_prefix"],
                                                     annotations: metadata.fetch("annotations", {}))
                     .each { |entry| document << entry }
        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "lane-lexicon: #{document_ref.id}: #{e.message}"
      end

      private

      def bucket_paths(workdir)
        Dir.glob(File.join(workdir, LEXICON_DIR, BUCKET_GLOB)).sort_by { |path| File.basename(path) }
      end

      def census_files(workdir)
        CENSUS_DIRS.flat_map { |dir| Dir.glob(File.join(workdir, dir, "**", "*")) }
                   .select { |path| File.file?(path) }.sort
      end

      def rejection(rel)
        return REJECTED_GRAINS[rel] if REJECTED_GRAINS.key?(rel)

        "eXist-db collection descriptor (database packaging)" if File.basename(rel) == CONTENTS_FILE
      end

      # The per-file parse options: a variant (declared, or a diverged
      # duplicate) gets its stem prefix; supplement/variant annotations.
      def ref_metadata(path)
        name = File.basename(path)
        variant_of = VARIANT_FILES[name] || DUPLICATE_FILES[name]
        annotations = {}
        annotations["section"] = "supplement" if SUPPLEMENT_FILES.include?(name)
        annotations.merge!("copy" => "variant", "variant_of" => variant_of) if variant_of
        { "id_prefix" => variant_of ? File.basename(name, ".xml") : nil, "annotations" => annotations }.compact
      end

      def collapsed_duplicate?(path)
        original = DUPLICATE_FILES[File.basename(path)]
        return false if original.nil?

        original_path = File.join(File.dirname(path), original)
        File.file?(original_path) && whitespace_collapsed(path) == whitespace_collapsed(original_path)
      end

      def duplicate_note(path)
        "#{File.basename(path)}: whitespace-equivalent duplicate of #{DUPLICATE_FILES.fetch(File.basename(path))} " \
          "(the same entries and ids) — collapsed to the original"
      end

      def whitespace_collapsed(path)
        SourceRead.utf8_file(path, label: "lane-lexicon").gsub(/\s+/, " ")
      end
    end
  end
end
