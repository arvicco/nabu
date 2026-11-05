# frozen_string_literal: true

require "json"
require_relative "source_read"
require_relative "../normalize"

module Nabu
  module Adapters
    # The CGPG carve plan (Cgpg's work grain): open-greek-corpus's curated
    # per-volume plan for splitting the Migne volume dumps into works
    # (github.com/open-greek/open-greek-corpus, data/cgpg_carve_plan.json,
    # pinned at tag corpus-2026-10-28.2; CC BY 4.0 project aids). Read
    # here, consolidated per volume, never edited: the plan is upstream's
    # curation, Cgpg only applies it.
    #
    # == The shape (read off the pinned file, 2026-11-05)
    #
    # {"_meta": {…rules…}, "volumes": [entry, …]} — 34 entries over 23
    # volumes: a volume researched in several PASSES (PG 113 six, PG 151
    # four, PG 139 three, PG 112 two) has one entry per pass, each carving
    # works out of what the last left. An entry: volume ("PG087_1"), basis,
    # works [{slug, title, author_display, tlg, ranges [[a, b]…], rank?,
    # secondary_reason?, incipit_checks [{locus, text}], append?,
    # row_order?}], residual_ranges, and per volume at most once:
    # residual_loci, drop_duplicates [{loci, duplicates_of}], status
    # "defer" + defer_reason (PG 3 only).
    #
    # Ranges are LOCI — the served rows of the volume, which are the PDF
    # pages of the deposit's <w id="PDF Page P"> (measured: every one of the
    # plan's 227 incipit checks lands on the page of that number).
    #
    # == Consolidation (the rules, each from the plan's own words)
    #
    # - works accumulate across passes in plan order; a later pass only
    #   carves what earlier ones left (no locus is claimed twice — checked;
    #   a double claim is a plan error).
    # - the residual is the LAST pass's residual_ranges ("what pass N
    #   left"), plus residual_loci — explicit rows cut OUT of a work range
    #   (PG 101's locus 293, "resolved by the explicit locus-293 exclusion").
    # - drop_duplicates are rescans of a leaf already served: they leave the
    #   work and keep the locus of the leaf they repeat.
    # - rank absent = primary: the _meta rank_rule names only the demotion
    #   ("carved … with rank secondary"); a work it did not demote serves.
    # - append: a work continued in a later volume ("appended to the same
    #   corpus file — two-volume delivery of one work") joins the earlier
    #   volume's work of the same slug into ONE document. A slug repeated
    #   WITHOUT append is a second witness (PG 157's Patria primary, PG 122's
    #   copy secondary): each copy's key takes its volume (<slug>-pg<n>).
    # - row_order (PG 122's Patria): the reading order of a work whose
    #   rescans interleave; a range locus it does not list follows in page
    #   order.
    #
    # Every locus of a planned volume therefore has exactly one role
    # (#role_of): :duplicate (with its original), :apparatus (the plan's
    # residual), :work (with its work), or :uncarved (in no work and no
    # residual — a row the plan's served set never reached, or one a
    # later script moved without updating the ranges).
    class CgpgCarvePlan
      # Incipit soft verification: the share of the check's first
      # INCIPIT_WORDS folded words (>= INCIPIT_MIN_LENGTH letters — the
      # article/particle noise drops out) found on the page. Calibrated on
      # the whole plan against the box's deposit (2026-11-05): all 227
      # checks score >= 0.67 on their own page; on the page three later,
      # 200 of 215 score < 0.5.
      INCIPIT_WORDS = 6
      INCIPIT_MIN_LENGTH = 4
      INCIPIT_THRESHOLD = 0.5

      VOLUME = /\APG(\d{3})(?:_(\d+))?\z/

      Check = Data.define(:locus, :text)

      Work = Data.define(:slug, :volume, :title, :author, :tlg, :rank, :secondary_reason, :loci, :ranges,
                         :checks, :append, :evidence)

      # One planned volume, all passes folded.
      class Volume
        attr_reader :volume, :works, :passes, :residual_note, :defer_reason, :basis

        def initialize(volume:, works:, passes:, residual:, duplicates:, residual_note:, defer_reason:, basis:)
          @volume = volume
          @works = works
          @passes = passes
          @residual = residual
          @duplicates = duplicates
          @residual_note = residual_note
          @defer_reason = defer_reason
          @basis = basis
          @owner = works.each_with_object({}) { |work, owner| work.loci.each { |locus| owner[locus] = work } }
        end

        def deferred? = !@defer_reason.nil?

        # [:duplicate, original] / [:apparatus] / [:work, work] / [:uncarved]
        def role_of(locus)
          return [:duplicate, @duplicates[locus]] if @duplicates.key?(locus)
          return [:apparatus] if @residual.include?(locus)
          return [:work, @owner[locus]] if @owner.key?(locus)

          [:uncarved]
        end
      end

      # One document of the work grain: a work, or a work and its
      # continuation in a later volume (append).
      Document = Data.define(:key, :parts) do
        def volumes = parts.map(&:volume)
        def lead = parts.first
        def last = parts.last
      end

      # "PG087_1" → "87.1" (the Cgpg adapter's volume key).
      def self.volume_key(name)
        match = name.to_s.match(VOLUME) or raise ParseError, "carve plan: volume #{name.inspect} is not PG<nnn>[_<n>]"
        [Integer(match[1], 10).to_s, match[2]].compact.join(".")
      end

      def self.load(path)
        new(JSON.parse(SourceRead.utf8_file(path, label: "cgpg carve plan")), path: path)
      rescue JSON::ParserError => e
        raise ParseError, "carve plan #{path}: #{e.message}"
      end

      # A check's words: the plan's own bracketed annotations ("[OCR noise
      # from …]", "[= …]") dropped, then #folded_words.
      def self.incipit_words(check_text)
        folded_words(check_text.to_s.gsub(/\[[^\]]*\]/, " "))
      end

      # Folded, accentless, letters-only words (final sigma folded); words
      # shorter than INCIPIT_MIN_LENGTH left out. Page text is folded as is:
      # the OCR's own stray brackets are text, not annotations.
      def self.folded_words(text)
        text.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").downcase.tr("ς", "σ")
            .gsub(/[^\p{L}\s]/, " ").split.select { |word| word.length >= INCIPIT_MIN_LENGTH }
      end

      def self.incipit_score(check_text, page_text)
        wanted = incipit_words(check_text).first(INCIPIT_WORDS)
        return 1.0 if wanted.empty?

        present = folded_words(page_text).to_set
        wanted.count { |word| present.include?(word) }.fdiv(wanted.size)
      end

      attr_reader :volumes, :documents

      def initialize(raw, path: "carve plan")
        @path = path
        entries = raw.fetch("volumes") { raise ParseError, "#{path}: no volumes list" }
        @volumes = entries.group_by { |entry| self.class.volume_key(entry.fetch("volume")) }
                          .to_h { |key, passes| [key, fold(key, passes)] }
        @documents = mint_documents
      end

      private

      def fold(key, passes)
        duplicates = duplicate_map(passes)
        cut = passes.flat_map { |entry| Array(entry["residual_loci"]) }
        works = passes.flat_map { |entry| entry.fetch("works", []) }.map { |raw| work(key, raw, duplicates, cut) }
        check_claims!(key, works)
        Volume.new(volume: key, works: works, passes: passes.size,
                   residual: (expand(passes.last["residual_ranges"]) + cut).to_set, duplicates: duplicates,
                   residual_note: passes.reverse_each.map { |entry| entry["residual_note"] }.find { |n| present?(n) },
                   defer_reason: passes.find { |entry| entry["status"] == "defer" }&.fetch("defer_reason", "deferred"),
                   basis: passes.map { |entry| entry["basis"] }.compact)
      end

      def work(key, raw, duplicates, cut)
        ranges = raw.fetch("ranges")
        loci = ordered_loci(raw, ranges) - duplicates.keys - cut
        Work.new(slug: raw.fetch("slug"), volume: key, title: nfc(raw["title"]), author: nfc(raw["author_display"]),
                 tlg: raw["tlg"], rank: raw["rank"] || "primary", secondary_reason: raw["secondary_reason"],
                 loci: loci, ranges: ranges, append: raw["append"] == true, evidence: raw["evidence"],
                 checks: Array(raw["incipit_checks"]).map do |check|
                   Check.new(locus: check.fetch("locus"), text: check.fetch("text"))
                 end)
      end

      def ordered_loci(raw, ranges)
        in_range = expand(ranges)
        return in_range unless raw["row_order"]

        ordered = expand(raw["row_order"]) & in_range
        ordered + (in_range - ordered)
      end

      def duplicate_map(passes)
        passes.flat_map { |entry| Array(entry["drop_duplicates"]) }.each_with_object({}) do |drop, map|
          originals = expand(drop.fetch("duplicates_of"))
          expand(drop.fetch("loci")).each_with_index { |locus, index| map[locus] = originals[index] }
        end
      end

      def check_claims!(key, works)
        works.each_with_object({}) do |work, owner|
          work.loci.each do |locus|
            if owner.key?(locus)
              raise ParseError, "#{@path}: PG #{key} locus #{locus} is claimed by two works " \
                                "(#{owner[locus]} and #{work.slug})"
            end
            owner[locus] = work.slug
          end
        end
      end

      # Plan order; an append part joins the open document of its slug; a
      # slug left with several documents keys each by its lead volume.
      def mint_documents
        open = {}
        docs = []
        @volumes.each_value do |volume|
          volume.works.each do |work|
            if work.append && open[work.slug]
              open[work.slug] << work
            else
              docs << (open[work.slug] = [work])
            end
          end
        end
        shared = docs.map { |parts| parts.first.slug }.tally.select { |_slug, count| count > 1 }.keys
        docs.map do |parts|
          slug = parts.first.slug
          Document.new(key: shared.include?(slug) ? "#{slug}-pg#{parts.first.volume}" : slug, parts: parts)
        end
      end

      def expand(ranges)
        Array(ranges).flat_map { |first, last| (first..last).to_a }
      end

      def present?(value) = value.is_a?(String) && !value.strip.empty?

      def nfc(value) = value && Normalize.nfc(value)
    end
  end
end
