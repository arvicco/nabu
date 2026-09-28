# frozen_string_literal: true

require "csv"

module Nabu
  module Adapters
    # honkoku — みんなで翻刻 (P108-5, Q89.1; github.com/yuta1984/
    # honkoku-data, README license verbatim CC BY-SA 4.0): the
    # citizen-transcription platform's published text data. Served
    # HONESTLY as crowd transcription: the README's own quality
    # census (a PhD historian's 100k-char verification) measured
    # ~1.5 errors/100 chars — these are never "clean editions", and
    # the platform's aozora-like notation (振り仮名, 割書, 虫損
    # marks; wiki.honkoku.org/doku.php?id=howto_markup) is served
    # VERBATIM — the notation IS the transcription convention; a
    # parsed ruby/gaiji layer is a recorded future refinement.
    #
    # == The v3 tree (censused 2026-09-29)
    #
    # v3/<projectId>/info.tsv (id · label · manifestUrl · projectId ·
    # size · progress · attribution · thumbnail) + per material a
    # <materialId>/ dir of page txts (001.txt …) with its own
    # info.tsv (filename · status · IIIF image). Document per
    # material, passage per page (:p<n> from the filename number),
    # the page's IIIF image as an annotation. Index rows without a
    # transcription dir skip counted. The v1 tree (the 2017
    # platform's ~5M chars, entries.csv bibliography, different
    # layout) is DELIBERATELY deferred — recorded on the queue's
    # japonic remainder, never silent.
    class Honkoku < Nabu::Adapter
      REPO_URL = "https://github.com/yuta1984/honkoku-data"
      URN_PREFIX = "urn:nabu:honkoku:"
      LANGUAGE = "jpn"
      PAGE_TXT = /\A0*(\d+)\.txt\z/

      MANIFEST = Nabu::SourceManifest.new(
        id: "honkoku",
        name: "みんなで翻刻 honkoku-data — citizen transcriptions of premodern Japanese documents",
        license: "CC BY-SA 4.0 (the repository README's license section, read 2026-09-29). " \
                 "Credit みんなで翻刻 (honkoku.org) and each material's holding institution " \
                 "(the attribution column, carried per document)",
        license_class: "attribution",
        upstream_url: "https://github.com/yuta1984/honkoku-data",
        parser_family: "honkoku-pages"
      )

      def self.manifest = MANIFEST

      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        each_index_row(workdir) do |project, row, dir|
          next if dir.nil?

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id, id: "#{URN_PREFIX}#{project}:#{row['id']}", path: dir,
            metadata: { "label" => row["label"].to_s, "project" => project,
                        "attribution" => row["attribution"].to_s,
                        "manifest" => row["manifestUrl"].to_s }
          )
        end
      end

      def discovery_skips(workdir)
        skipped = 0
        each_index_row(workdir) { |_project, _row, dir| skipped += 1 if dir.nil? }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: skipped,
          notes: skipped.positive? ? ["#{skipped} index rows without transcribed pages (dir-less or all-empty)"] : []
        )
      end

      def parse(document_ref)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          title: presence(document_ref.metadata["label"]),
          metadata: document_ref.metadata.reject { |_k, v| v.to_s.empty? }
        )
        images = page_images(document_ref.path)
        page_files(document_ref.path).each do |number, path|
          text = File.read(path, encoding: "UTF-8").rstrip
          next if text.strip.empty?

          annotations = {}
          annotations["image"] = images[File.basename(path)] if images[File.basename(path)]
          document << Nabu::Passage.new(
            urn: "#{document.urn}:p#{number}", language: LANGUAGE,
            text: Normalize.nfc(text), sequence: document.passages.size + 1,
            annotations: annotations
          )
        end
        raise Nabu::ParseError, "#{document_ref.path}: no transcribed pages" if document.passages.empty?

        document
      end

      # The standard many-file git rail (architecture §8: fetch →
      # breaker → attic → ff-merge) — one repo, ~190 MB; upstream
      # grows as transcription proceeds.
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      # quote_char nil: a TSV is never quoted CSV, and attribution
      # cells carry raw HTML with bare quotes (href="…" — the 2026-09-29
      # first-sync poison, fixture-pinned).
      def each_index_row(workdir)
        Dir.glob(File.join(workdir, "v3", "*", "info.tsv")).each do |index|
          project = File.basename(File.dirname(index))
          CSV.foreach(index, col_sep: "\t", headers: true, quote_char: nil) do |row|
            id = row["id"].to_s.strip
            next if id.empty?

            dir = File.join(File.dirname(index), id)
            yield project, row, transcribed?(dir) ? dir : nil
          end
        end
      end

      # A material counts only when at least one page carries text —
      # thousands of materials exist as EMPTY placeholder pages awaiting
      # transcription (6,739 at the 2026-09-29 first sync); they are
      # by-design skips, never quarantine noise.
      def transcribed?(dir)
        return false unless File.directory?(dir)

        Dir.children(dir).any? do |name|
          path = File.join(dir, name)
          PAGE_TXT.match?(name) && File.size(path).positive? &&
            !File.read(path, encoding: "UTF-8").strip.empty?
        end
      end

      def page_files(dir)
        Dir.children(dir).filter_map do |name|
          match = PAGE_TXT.match(name)
          [Integer(match[1], 10), File.join(dir, name)] if match
        end.sort_by(&:first)
      end

      def page_images(dir)
        index = File.join(dir, "info.tsv")
        return {} unless File.file?(index)

        CSV.foreach(index, col_sep: "\t", headers: true, quote_char: nil)
           .to_h { |row| [row["filename"].to_s, row["image"].to_s] }
           .reject { |_k, v| v.empty? }
      rescue CSV::MalformedCSVError
        {}
      end

      def presence(value)
        text = value.to_s.strip
        text.empty? ? nil : text
      end
    end
  end
end
