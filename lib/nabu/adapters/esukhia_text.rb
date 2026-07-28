# frozen_string_literal: true

require_relative "esukhia_text_parser"

module Nabu
  module Adapters
    # Shared adapter base of the `esukhia-text` family (P48-1): the Digital
    # Derge Kangyur and Tengyur — plain-text volume files under text/, one
    # physical woodblock volume per file. Subclasses supply MANIFEST,
    # REPO_URL and PINNED_SHA; everything else — the Toh-boundary document
    # model, the page.line passage grain, the pinned git fetch — is this
    # class.
    #
    # == Identity (the P48 crosswalk contract, FROZEN)
    #
    # Document = one Tohoku text: urn:nabu:<slug>:toh<payload> with the
    # marker payload lowercased verbatim — toh1, toh1-1 (subindex), toh846a
    # (Tohoku-gap text). The toh<N> slug is the join key the e84000 packet
    # builds against. A parent marker immediately followed by its own
    # subindex ({D1}{D1-1} — a zero-text span) parses as a CONTAINER
    # document: zero passages, metadata container:true + its subtext slugs;
    # an empty document that is NOT a container shape quarantines loudly.
    #
    # == Passages: page.line, and THE MULTI-VOLUME RULE
    #
    # One passage per citable line slice: urn:nabu:<slug>:toh<N>:<page>.<line>
    # (e.g. :1b.3; page-only lines that carry text cite the bare page). BUT
    # Derge pagination restarts per physical volume and a Toh text spans
    # whole volume files (Kangyur vols 002–004 carry ZERO markers — all
    # Toh 1), so page.line alone is NOT unique inside a multi-volume
    # document. The rule: a document spanning MORE THAN ONE volume file
    # volume-prefixes every passage ref (…:toh1-6:2.1b.3); single-volume
    # documents (the vast majority) keep the contract's bare page.line.
    # Residual collisions — a mid-volume pagination restart inside one text,
    # never seen in the censused volumes — take the house :b2 counter (the
    # ReM lesson: never quarantine for a ref collision). Volume numbers ride
    # document metadata ("volumes") and, for multi-volume documents, each
    # passage's annotations.
    #
    # == Text discipline
    #
    # Language xct (Classical Tibetan — the code the catalog already holds
    # via GRETIL). Upstream is UTF-8 NFD-by-convention; every Tibetan
    # precomposed character is a composition exclusion, so the standard
    # Normalize.nfc boundary is deterministic (stray precomposed U+0F75/
    # U+0F43 decompose — the fixture pins the one real occurrence). Text is
    # verbatim beyond markup extraction: no word segmentation (tsheg
    # delimits syllables, not words — enrichment land), the apparatus keeps
    # original readings in the text (exact-representation doctrine, see the
    # parser).
    #
    # == Fetch: pinned git (the corph posture)
    #
    # Ordinary GitFetch (attic + breaker) then the pin gate: a HEAD other
    # than PINNED_SHA aborts the sync loudly — the Kangyur repo is ARCHIVED
    # (frozen June 2022) and the Tengyur dormant (last push 2021-10-20), so
    # any drift is an upstream event the owner must review and re-pin.
    class EsukhiaText < Nabu::Adapter
      LANGUAGE = "xct"

      TEXT_DIRNAME = "text"

      # A Tohoku-gap letter suffix (D846a) vs a dash subindex (D1-1).
      LETTER_SUFFIX = /\A\d+[a-zA-Z]\z/

      # +repo_url+/+pinned_sha+ exist for the tests (local upstream repos);
      # real syncs keep the subclass constants. No-arg construction stays
      # the registry contract.
      def initialize(repo_url: self.class::REPO_URL, pinned_sha: self.class::PINNED_SHA)
        super()
        @repo_url = repo_url
        @pinned_sha = pinned_sha
      end

      def fetch(workdir, progress: nil, force: false)
        report = git_fetch!(repo_url: @repo_url, workdir: workdir, progress: progress, force: force)
        return report if report.sha == @pinned_sha

        raise Nabu::FetchError,
              "#{manifest.id}: upstream #{@repo_url} is at #{report.sha[0, 12]}, but the source is " \
              "pinned to #{@pinned_sha[0, 12]} — review the new commits (license + text) and re-pin " \
              "(owner decision; the upstream is archived/dormant, so drift is an event, not a cadence)"
      end

      # One DocumentRef per Tohoku marker, in corpus order. The ref carries
      # the document's span (files + start/end positions) so parse never
      # rescans the whole corpus, plus the identity metadata (parent /
      # tohoku_gap / subtexts).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        paths = volume_paths(workdir)
        return if paths.empty?

        scan = parser.scan(paths)
        scan.markers.each_with_index do |marker, index|
          yield document_ref(paths, marker, scan.markers[index + 1], scan.markers)
        end
      end

      # The census (P11-7): preamble text lines (before the corpus's first
      # marker — no Toh text owns them) are benign, counted skips; a file
      # under text/ that is not a volume file is unrecognized — loud.
      def discovery_skips(workdir)
        paths = volume_paths(workdir)
        return Nabu::Adapter::DiscoverySkips.new if paths.empty?

        strays = Dir.glob(File.join(workdir, TEXT_DIRNAME, "*"))
                    .select { |path| File.file?(path) && parser.volume_number(path).nil? }
                    .sort
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: parser.scan(paths).preamble_text_lines,
          unrecognized: strays.size,
          notes: strays.map { |path| "non-volume file under #{TEXT_DIRNAME}/: #{path}" }
        )
      end

      def parse(document_ref)
        meta = document_ref.metadata
        paths = span_paths(document_ref)
        volumes = paths.map { |path| parser.volume_number(path) }
        passages, unrecognized = collect_passages(document_ref, paths, meta,
                                                  multi_volume: volumes.uniq.size > 1)
        build_document(document_ref, passages, volumes, unrecognized)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.id}: #{e.message}"
      end

      private

      def parser
        @parser ||= EsukhiaTextParser.new
      end

      # -- discover -----------------------------------------------------------

      def volume_paths(workdir)
        Dir.glob(File.join(workdir, TEXT_DIRNAME, "*.txt"))
           .select { |path| parser.volume_number(path) }
           .sort_by { |path| File.basename(path) }
      end

      def document_ref(paths, marker, next_marker, markers)
        span_files = paths[marker.file_index..(next_marker ? next_marker.file_index : -1)]
        Nabu::DocumentRef.new(
          source_id: manifest.id,
          id: "#{urn_prefix}#{slug(marker.payload)}",
          path: File.expand_path(paths[marker.file_index]),
          metadata: {
            "marker" => marker.marker,
            "files" => span_files.map { |path| File.basename(path) },
            "start_line" => marker.line_index, "start_char" => marker.char_end,
            "end_line" => next_marker&.line_index, "end_char" => next_marker&.char_start,
            "parent" => parent_slug(marker.payload),
            "tohoku_gap" => (true if LETTER_SUFFIX.match?(marker.payload)),
            "subtexts" => subtext_slugs(marker.payload, markers)
          }.compact
        )
      end

      def urn_prefix
        "urn:nabu:#{manifest.id}:"
      end

      def slug(payload)
        "toh#{payload.downcase}"
      end

      def parent_slug(payload)
        return nil unless payload.include?("-")

        slug(payload.split("-", 2).first)
      end

      def subtext_slugs(payload, markers)
        return nil if payload.include?("-")

        children = markers.select { |m| m.payload.start_with?("#{payload}-") }
        children.empty? ? nil : children.map { |m| slug(m.payload) }
      end

      # -- parse --------------------------------------------------------------

      def span_paths(document_ref)
        dir = File.dirname(document_ref.path)
        document_ref.metadata.fetch("files").map { |basename| File.join(dir, basename) }
      end

      def collect_passages(document_ref, paths, meta, multi_volume:)
        passages = []
        unrecognized = 0
        seen = Hash.new(0)
        segments(paths, meta).each do |segment|
          cleaned = parser.clean(Nabu::Normalize.nfc(segment.text))
          next if cleaned.text.strip.empty?
          if segment.page.nil?
            raise ParseError, "#{document_ref.id}: text without a citation bracket (line grammar broken)"
          end

          unrecognized += cleaned.unrecognized_curly
          passages << passage_values(document_ref, segment, cleaned, seen, multi_volume: multi_volume)
        end
        [passages, unrecognized]
      end

      def segments(paths, meta)
        parser.each_segment(paths,
                            start_line: meta.fetch("start_line"), start_char: meta.fetch("start_char"),
                            end_line: meta["end_line"], end_char: meta["end_char"])
      end

      def passage_values(document_ref, segment, cleaned, seen, multi_volume:)
        label = +""
        label << "#{segment.volume}." if multi_volume
        label << segment.page
        label << ".#{segment.line}" if segment.line
        count = (seen[label] += 1)
        label = "#{label}:b#{count}" if count > 1
        { urn: "#{document_ref.id}:#{label}", text: cleaned.text,
          annotations: annotations(segment, cleaned, multi_volume: multi_volume) }
      end

      def annotations(segment, cleaned, multi_volume:)
        annotations = {}
        annotations["apparatus"] = cleaned.apparatus unless cleaned.apparatus.empty?
        annotations["note_marks"] = cleaned.note_marks unless cleaned.note_marks.empty?
        annotations["volume"] = segment.volume if multi_volume
        annotations
      end

      def build_document(document_ref, passages, volumes, unrecognized)
        document = Nabu::Document.new(
          urn: document_ref.id, language: LANGUAGE, canonical_path: document_ref.path,
          metadata: document_metadata(document_ref, passages, volumes, unrecognized)
        )
        passages.each_with_index do |values, sequence|
          document << Nabu::Passage.new(urn: values[:urn], language: LANGUAGE, text: values[:text],
                                        annotations: values[:annotations], sequence: sequence)
        end
        document
      end

      def document_metadata(document_ref, passages, volumes, unrecognized)
        meta = document_ref.metadata
        base = { "marker" => meta["marker"], "volumes" => volumes.uniq,
                 "parent" => meta["parent"], "tohoku_gap" => meta["tohoku_gap"] }
        base["census"] = { "unrecognized_curly" => unrecognized } if unrecognized.positive?
        if passages.empty?
          unless meta["subtexts"]
            raise ParseError, "#{document_ref.id}: zero passages and no subtexts — a Toh marker with no " \
                              "text is only legal as a {D<n>}{D<n>-1} container"
          end
          base.merge!("container" => true, "subtexts" => meta["subtexts"])
        end
        base.compact
      end
    end
  end
end
