# frozen_string_literal: true

require_relative "sentence_lines_parser"

module Nabu
  module Adapters
    # NiuTrans/Classical-Modern (P88-A2): the largest Classical↔Modern
    # Chinese parallel corpus there is — ~967k sentence pairs across 97
    # classical works at CHAPTER grain (censused 2026-08-29 via blobless
    # clone: 7,304 chapter units, each a
    # 双语数据/<book>[/<section>]/<chapter>/ directory holding source.txt
    # (classical, one sentence per line) + target.txt (modern, LINE-
    # ALIGNED) + bitext.txt (the same pairs interleaved — a rendition) +
    # 数据来源.txt (the chapter's crawl sources — a metadata rider)).
    #
    # == The repo choice (recorded so nobody re-scouts)
    #
    # nk2028/Classical-Modern is a FORK frozen 2022-02-08 that concatenated
    # everything into 27 per-book blobs — per-chapter identity destroyed.
    # The canonical upstream is NiuTrans/Classical-Modern (MIT, active),
    # and this adapter registers THAT.
    #
    # == Identity + languages
    #
    #   document urn  urn:nabu:classical-modern:<book>[:<section>]:<chapter>
    #   sibling       <document-urn>-cmn        (the modern translation)
    #   passage urn   <document-urn>:<line-number>
    #
    # lzh for the classical side (the kanripo precedent — BUT both sides
    # are SIMPLIFIED script, censused: 岂/国/宪 on the 古文 side too; the
    # script posture records it). cmn for the modern side, riding as a
    # translation sibling (the aranese -es mold, suffix -cmn). Line counts
    # of a pair MUST match — a mismatch is a ParseError (the aranese
    # equal-line-counts rule), and blank lines still count in numbering so
    # an upstream blank never re-flows following urns.
    #
    # == Provenance honesty (the aranese "mainly synthetic" precedent)
    #
    # The modern translations are web-crawled ("原始爬取的数据…人工校对" —
    # the README's own words) from sites the per-chapter 数据来源.txt
    # names (易文言, 百度百科…). That file rides every document's
    # `provenance` metadata verbatim; the caveat also rides the manifest
    # license field. Never presented as a scholarly translation.
    #
    # == fetch / sync policy
    #
    # Sparse GitFetch scoped to 双语数据/ + the repo docs — the ~500-book
    # monolingual 古文原文/ tree (22,612 files) and 复现/ stay censused,
    # not ingested (kanripo/CBETA already cover monolingual classical
    # Chinese with better provenance). Upstream still moves occasionally →
    # sync_policy manual.
    class ClassicalModern < Nabu::Adapter
      REPO_URL = "https://github.com/NiuTrans/Classical-Modern"

      SPARSE_PATHS = ["双语数据/**", "LICENSE", "README.md", "statistic.md"].freeze

      DATA_DIR = "双语数据"
      SOURCE_FILE = "source.txt"
      TARGET_FILE = "target.txt"
      RENDITION_FILES = ["bitext.txt", "数据来源.txt"].freeze
      PROVENANCE_FILE = "数据来源.txt"

      LANGUAGE = "lzh"
      SIBLING_LANGUAGE = "cmn"
      SIBLING_SUFFIX = "-cmn"
      URN_PREFIX = "urn:nabu:classical-modern:"

      MANIFEST = Nabu::SourceManifest.new(
        id: "classical-modern",
        name: "Classical-Modern — Classical↔Modern Chinese parallel corpus (NiuTrans)",
        license: "MIT (in-repo LICENSE, © 2022 NiuTrans Open Source, verified 2026-08-29; the " \
                 "README requests citation of github.com/NiuTrans/Classical-Modern). PROVENANCE " \
                 "HONESTY: the modern translations are web-crawled (\"原始爬取的数据…人工校对\" — " \
                 "the README's own words); each chapter's 数据来源.txt names its crawl sources " \
                 "and rides document metadata verbatim",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "sentence-lines"
      )

      def self.manifest
        MANIFEST
      end

      # +translations+: the registry row's posture — the modern side is
      # the point of a parallel corpus.
      def initialize(translations: false)
        super()
        @translations = translations
        @parser = SentenceLinesParser.new
      end

      # One lzh DocumentRef per chapter source.txt (+ the -cmn sibling
      # over target.txt when opted in AND present), sorted by urn. The
      # glob is anchored under 双语数据/ so repo docs and the attic never
      # match; a pre-fetch workdir yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        refs = chapter_dirs(workdir).flat_map { |dir| chapter_refs(workdir, dir) }
        refs.sort_by(&:id).each(&block)
      end

      # bitext.txt (a rendition of source+target) and 数据来源.txt (a
      # metadata rider) — visible skips, never silent, never documents.
      def discovery_skips(workdir)
        skipped = RENDITION_FILES.sum do |name|
          Dir.glob(File.join(workdir, DATA_DIR, "**", name)).size
        end
        DiscoverySkips.new(skipped_by_rule: skipped)
      end

      def parse(document_ref)
        translation = document_ref.metadata["kind"] == "translation"
        chapter_dir = File.dirname(document_ref.path)
        check_alignment!(chapter_dir, document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id,
          language: translation ? SIBLING_LANGUAGE : LANGUAGE,
          title: title_for(document_ref, translation),
          metadata: document_metadata(chapter_dir, document_ref, translation),
          canonical_path: document_ref.path
        )
        each_passage(document_ref, translation ? SIBLING_LANGUAGE : LANGUAGE) do |passage|
          document << passage
        end
        raise Nabu::ParseError, "classical-modern: #{document_ref.id}: no sentences" if document.empty?

        document
      rescue Nabu::ValidationError => e
        raise Nabu::ParseError, "classical-modern: #{document_ref.id}: #{e.message}"
      end

      # Clone or non-destructively pull the repo via the shared git path
      # (GitFetch: attic + pre-merge mass-deletion breaker), sparse cone.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force,
                   sparse: SPARSE_PATHS)
      end

      private

      # Seam for tests (the house local-git pattern).
      def repo_url
        manifest.upstream_url
      end

      def chapter_dirs(workdir)
        Dir.glob(File.join(workdir, DATA_DIR, "**", SOURCE_FILE)).map { |path| File.dirname(path) }
      end

      def chapter_refs(workdir, dir)
        components = dir.delete_prefix(File.join(workdir, DATA_DIR, "")).split(File::SEPARATOR)
        urn = "#{URN_PREFIX}#{components.join(':')}"
        refs = [document_ref(urn, File.join(dir, SOURCE_FILE), components, translation: false)]
        target = File.join(dir, TARGET_FILE)
        if @translations && File.file?(target)
          refs << document_ref("#{urn}#{SIBLING_SUFFIX}", target, components, translation: true)
        end
        refs
      end

      def document_ref(id, path, components, translation:)
        metadata = { "book" => components.first, "chapter" => components.last }
        metadata["section"] = components[1..-2].join("/") if components.size > 2
        metadata["kind"] = "translation" if translation
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: id, path: File.expand_path(path), metadata: metadata
        )
      end

      # Equal line counts ARE the format (the aranese rule): the pair is
      # line-aligned, so a raw physical-line-count mismatch means the
      # chapter's files diverged upstream — quarantine, never mis-pair.
      def check_alignment!(chapter_dir, document_ref)
        source = File.join(chapter_dir, SOURCE_FILE)
        target = File.join(chapter_dir, TARGET_FILE)
        return unless File.file?(source) && File.file?(target)

        source_lines = count_lines(source)
        target_lines = count_lines(target)
        return if source_lines == target_lines

        raise Nabu::ParseError,
              "classical-modern: #{document_ref.id}: source/target line counts diverge " \
              "(#{source_lines} vs #{target_lines}) — the pair is line-aligned by contract"
      end

      def count_lines(path)
        File.foreach(path).count
      end

      def each_passage(document_ref, language)
        sequence = 0
        @parser.each_sentence(document_ref.path) do |number, text|
          yield Nabu::Passage.new(
            urn: "#{document_ref.id}:#{number}",
            language: language,
            text: Nabu::Normalize.nfc(text.strip),
            annotations: {},
            sequence: sequence
          )
          sequence += 1
        end
      end

      def title_for(document_ref, translation)
        base = [document_ref.metadata["book"], document_ref.metadata["section"],
                document_ref.metadata["chapter"]].compact.join(" · ")
        translation ? "#{base}（现代文）" : base
      end

      def document_metadata(chapter_dir, document_ref, translation)
        metadata = document_ref.metadata.dup
        provenance = File.join(chapter_dir, PROVENANCE_FILE)
        if File.file?(provenance)
          text = File.read(provenance, encoding: Encoding::UTF_8).strip
          metadata["provenance"] = Nabu::Normalize.nfc(text) unless text.empty?
        end
        metadata["kind"] = "translation" if translation
        metadata
      end
    end
  end
end
