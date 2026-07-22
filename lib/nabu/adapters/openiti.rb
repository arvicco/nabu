# frozen_string_literal: true

require_relative "openiti_markdown_parser"

module Nabu
  module Adapters
    # The OpenITI adapter (P41-2): the Open Islamicate Texts Initiative —
    # premodern & early-modern Arabic + Persian in OpenITI mARkdown, release
    # 2025.1.9 (Zenodo record 17767721, concept DOI 10.5281/zenodo.3082463).
    # First registrant of the openiti-markdown family (parser: P41-1).
    #
    # == Scope (owner ruling D41-e, 2026-07-22): primary versions + ALL Persian
    #
    # Discovery is INDEX-DRIVEN off the central metadata TSV (the aozora
    # precedent): a version is discovered iff its TSV status == "pri" AND it
    # is not in the MSS sub-corpus. Everything else — the 4,568 "sec"
    # secondary versions and the 433 MSS documentary rows (empty book URI,
    # empty death date, multi-language URIs; ALL carry status=pri upstream) —
    # is skip-by-rule, CENSUSED in discovery_skips, never silent. Expected
    # first wave: ~9,106 versions (9,539 pri minus the 433 MSS pri rows),
    # ~1.12 B words. NOTE: 3 works carry >1 primary version upstream — both
    # are ingested (distinct texts upstream flags primary; never de-duped).
    #
    # ATTIC HONESTY (the aozora precedent): discovery is index-driven and the
    # attic holds no TSV, so upstream-scrapped versions are preserved as
    # bytes + normal catalog withdrawal, not rediscovered from the attic.
    #
    # == Identity (FROZEN minting)
    #
    # Document = one text VERSION: urn:nabu:openiti:<version_uri> — upstream's
    # own URI verbatim (urn:nabu:openiti:0792Hafiz.Muntasab.PDL00074-per1),
    # WITHOUT the .mARkdown/.completed/.inProgress status extension (a
    # filename fact carried by local_path, not identity). Language is minted
    # from the URI's language suffix: -ara* → "ara", -per* → "fas" — NOT
    # "per": Normalize::LANGUAGE_FOLDS keys on the stored tag, and a
    # per-tagged document would silently skip the shared Arabic-script fold
    # (the P41-3 catch); fas is the house ISO 639-3 resolution target. An
    # in-scope row whose suffix cannot mint cleanly (the MSS multi-language
    # shapes, should one leak in scope) QUARANTINES loudly, never guesses.
    #
    # == Passages: the ref grammar (documented, collision-guarded)
    #
    # One passage per parser Unit, sequence-ordered, cited
    #
    #   <urn>:<volume>.<page>.<n>   e.g. …PDL00074-per1:1.2.3
    #
    # where (volume, page) is the unit's retro-assigned START page (PageVnnPnnn
    # marks a page END — parser doctrine) and <n> the 1-based ordinal of the
    # unit among units starting on that page. Units after the LAST page marker
    # (and whole marker-less texts) are honestly unplaced: they take the
    # `x.<n>` tail (x = unplaced, one trailing run per document). Ordinal
    # counters are keyed by (volume, page) for the whole document, so even a
    # non-monotonic page sequence (upstream typos) cannot collide; any
    # residual collision takes the house :b2 positional disambiguator (the
    # ReM lesson — never quarantine for ref collisions).
    #
    # SECTION-HEADER RULING: a header is a PASSAGE of its own
    # (annotations kind=section_header, level, section_path, auto) — headers
    # are real searchable canonical text (chapter titles). The section_path
    # chain rides ONLY the header passage; prose/verse passages stay lean
    # (their section is derivable by sequence). Verse units: text = the
    # hemistich single-space join; hemistichs + verse_number ride
    # annotations. Page breaks falling inside a unit and msNN milestones ride
    # annotations too. The parser's loud census (image, bare-line, $TAG$,
    # orphan-*, empty-unit, "### <token>") surfaces as document metadata
    # "census" when non-empty (the aozora unrecognized_elements pattern).
    # The .yml sidecar's ISSUES line (PRIMARY_VERSION flags) rides verbatim
    # as metadata "version_issues" when the sidecar is present — no further
    # machinery on sidecars. A header-only in-scope file quarantines: the
    # TSV promised text (tok_length > 0 on every in-scope row, P41-g).
    #
    # == License (D41-b ruled)
    #
    # Zenodo record license: CC BY-NC-SA 4.0 → class "nc". Loud discrepancy,
    # recorded in the manifest: NO LICENSE file in the RELEASE repo, NO
    # in-file statements — the grant rests entirely on the Zenodo record
    # metadata.
    #
    # == fetch: two immutable Zenodo artifacts, md5-pinned (the house deviation)
    #
    # The rem choreography (ZipFetch phases hand-driven, checksum verified
    # BETWEEN download and any tree mutation) with a size-forced twist: the
    # 5,936,029,637-byte zip is too large to pre-download at build time, so
    # the pins are the UPSTREAM-PUBLISHED md5 values (Zenodo publishes md5,
    # not sha256) instead of the house sha256-computed-at-snapshot norm.
    # Zenodo artifacts are immutable: an md5 mismatch is corruption or an
    # unannounced re-release — abort loudly with a re-pin instruction. The
    # zip body's sha256 IS minted during the streamed download and recorded
    # in the ledger (FetchReport.sha + the .zip-fetch.json state file) at the
    # owner's first successful fetch, so future re-verification can hold a
    # sha256 pin. ZipFetch runs in stream mode (chunks to disk, digests
    # incremental — a 5.9 GB body is never slurped) with metadata/ in its
    # keep-list; the small TSV is a second FileFetch into metadata/, its md5
    # verified the same way. Both artifacts verify BEFORE either tree
    # mutates; mass-deletion breaker + attic as everywhere (architecture §8).
    # A new Zenodo release = the owner re-pins URLS + md5s consciously.
    class Openiti < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/17767721"
      ZIP_URL = "https://zenodo.org/api/records/17767721/files/OpenITI_data_2025-1-9.zip/content"
      TSV_URL = "https://zenodo.org/api/records/17767721/files/OpenITI_metadata_2025-1-9.tsv/content"
      TSV_FILENAME = "OpenITI_metadata_2025-1-9.tsv"

      # Upstream-published md5 checksums (Zenodo record 17767721, release
      # 2025.1.9) — see the class comment for why md5, not the sha256 norm.
      RELEASE_ZIP_MD5 = "95cf19a9320fee6c37c4c26c9fa860b1"
      RELEASE_TSV_MD5 = "cb2226f64264efa964df9ef659d40199"

      URN_PREFIX = "urn:nabu:openiti:"

      # The TSV lives beside (not inside) the zip tree: metadata/ is in
      # ZipFetch's keep-list so the tree swap never dooms it.
      METADATA_DIRNAME = "metadata"
      TSV_GLOB = "OpenITI_metadata*.tsv"

      # The single-language URI suffixes the D41-e first wave can mint
      # (-ara1, -per2, …). Multi-language MSS shapes (-per1ara1) match
      # nothing → quarantine at parse.
      VERSION_SUFFIX = /-([a-z]+)(\d+)\z/
      LANGUAGE_BY_SUFFIX = { "ara" => "ara", "per" => "fas" }.freeze

      PRIMARY_STATUS = "pri"
      MSS_SUBCORPUS = "MSS"

      # The TSV columns this adapter reads (of the 27 the index carries).
      TSV_COLUMNS = %w[version_uri subcorpus date author_ar author_lat
                       title_ar title_lat status local_path].freeze

      MANIFEST = Nabu::SourceManifest.new(
        id: "openiti",
        name: "OpenITI — Open Islamicate Texts Initiative (premodern Arabic + Persian), release 2025.1.9",
        license: "CC BY-NC-SA 4.0 — Zenodo record 17767721 license field, verbatim: \"Creative Commons " \
                 "Attribution Non Commercial Share Alike 4.0 International\". DISCREPANCY (D41-b ruled): " \
                 "no LICENSE file in the RELEASE repo, no in-file license statements — the grant rests " \
                 "entirely on the Zenodo record metadata. Cite Romanov & Seydi, OpenITI: a Machine-Readable " \
                 "Corpus of Islamicate Texts (Zenodo, 2025.1.9).",
        license_class: "nc",
        upstream_url: RECORD_URL,
        parser_family: "openiti-markdown"
      )

      def self.manifest
        MANIFEST
      end

      # HEAD both Zenodo artifacts: reachability + Last-Modified drift
      # against the on-disk pins. metadata_url nil — the license lives on
      # the record page only (D41-b).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [
          Nabu::Adapter::HttpProbeTarget.new(
            label: "OpenITI_data_2025-1-9.zip", zip_url: ZIP_URL, metadata_url: nil,
            state_subdir: "", state_file: Nabu::ZipFetch::STATE_FILE
          ),
          Nabu::Adapter::HttpProbeTarget.new(
            label: TSV_FILENAME, zip_url: TSV_URL, metadata_url: nil,
            state_subdir: METADATA_DIRNAME, state_file: Nabu::FileFetch::STATE_FILE
          )
        ]
      end

      # +zip_md5+/+tsv_md5+ override the release pins (tests; the owner's
      # re-pin drill on a new Zenodo release).
      def initialize(zip_md5: RELEASE_ZIP_MD5, tsv_md5: RELEASE_TSV_MD5)
        super()
        @zip_md5 = zip_md5
        @tsv_md5 = tsv_md5
      end

      # One DocumentRef per in-scope TSV row (status pri, not MSS), sorted by
      # version URI. Paths are minted from local_path, never probed — a
      # missing file is loud at parse, not a silent discovery gap. No TSV
      # (the day-one pre-fetch state, and the attic) yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        index_rows(workdir).each do |row|
          next unless in_scope?(row)

          yield Nabu::DocumentRef.new(
            source_id: MANIFEST.id,
            id: "#{URN_PREFIX}#{row[:version_uri]}",
            path: File.expand_path(File.join(workdir, row[:local_path])),
            metadata: ref_metadata(row)
          )
        end
      end

      # The census (P11-7): sec + MSS rows are benign, counted skips; a
      # version file on disk that no TSV row (of ANY status) accounts for is
      # unrecognized — loud. Sidecar .yml files are accounted by rule.
      def discovery_skips(workdir)
        rows = index_rows(workdir)
        accounted = rows.to_set { |row| File.expand_path(File.join(workdir, row[:local_path])) }
        strays = version_files(workdir).reject { |path| accounted.include?(path) }
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: rows.count { |row| !in_scope?(row) },
          unrecognized: strays.size,
          notes: strays.map { |path| "version file with no index row: #{path}" }
        )
      end

      def parse(document_ref)
        language = document_ref.metadata["language"]
        raise ParseError, unmappable_suffix_message(document_ref) if language.nil?
        unless File.file?(document_ref.path)
          raise ParseError, "#{document_ref.id}: in-scope version file missing " \
                            "from the extracted tree: #{document_ref.path}"
        end

        build_document(document_ref, language)
      rescue Nabu::ValidationError => e
        raise ParseError, "#{document_ref.path}: #{e.message}"
      end

      # Both immutable artifacts prepared and md5-verified BEFORE the guard
      # and BEFORE either tree mutation (the rem choreography, doubled); a
      # 304 replays the stored pin and skips its check. See the class
      # comment for the md5-not-sha256 deviation and the sha256 recording.
      def fetch(workdir, progress: nil, force: false)
        zip = zip_fetch(workdir, progress)
        tsv = tsv_fetch(workdir, progress)
        begin
          zip.prepare!
          verify_md5!(zip.not_modified?, zip.md5, @zip_md5, "OpenITI_data zip", ZIP_URL)
          tsv.prepare!
          verify_md5!(tsv.not_modified?, tsv.md5, @tsv_md5, "metadata TSV", TSV_URL)
          guard_mass_deletion!(workdir, zip.doomed_paths + tsv.doomed_paths, force: force)
          zip.complete!
          tsv.complete!
        ensure
          zip.cleanup!
        end
        Nabu::FetchReport.new(sha: zip.sha, fetched_at: Time.now, notes: fetch_notes(zip, tsv))
      rescue ZipFetch::Error, FileFetch::Error, Nabu::Shell::Error => e
        raise Nabu::FetchError, "openiti fetch failed into #{workdir}: #{e.message}"
      end

      private

      def parser
        OpenitiMarkdownParser.new
      end

      # -- the index ----------------------------------------------------------

      def in_scope?(row)
        row[:status] == PRIMARY_STATUS && row[:subcorpus] != MSS_SUBCORPUS
      end

      def ref_metadata(row)
        {
          "title" => presence(row[:title_lat]),
          "title_ar" => presence(row[:title_ar]),
          "author_lat" => presence(row[:author_lat]),
          "author_ar" => presence(row[:author_ar]),
          "death_ah" => presence(row[:date])&.to_i,
          "status" => row[:status],
          "language" => language_for(row[:version_uri])
        }.compact
      end

      # "ara" / "fas" (see the class comment), nil when the suffix cannot
      # mint cleanly — parse quarantines nil, never guesses.
      def language_for(version_uri)
        match = VERSION_SUFFIX.match(version_uri)
        match && LANGUAGE_BY_SUFFIX[match[1]]
      end

      def presence(value)
        value unless value.nil? || value.empty?
      end

      # The metadata TSV: under metadata/ (the fetched canonical place),
      # falling back to the workdir root (the fixture layout). Tab-split by
      # hand — the index is plain TSV, never quoted CSV.
      def index_rows(workdir)
        path = metadata_tsv_path(workdir)
        return [] if path.nil?

        header = nil
        rows = []
        File.foreach(path, encoding: Encoding::UTF_8) do |line|
          fields = line.chomp.split("\t", -1)
          if header.nil?
            header = column_indexes(path, fields)
          else
            rows << TSV_COLUMNS.to_h { |column| [column.to_sym, fields[header[column]].to_s] }
          end
        end
        rows.sort_by { |row| row[:version_uri] }
      end

      def metadata_tsv_path(workdir)
        canonical = Dir.glob(File.join(workdir, METADATA_DIRNAME, TSV_GLOB))
        candidates = canonical.empty? ? Dir.glob(File.join(workdir, TSV_GLOB)) : canonical
        candidates.max # newest release name sorts last; normally exactly one
      end

      def column_indexes(path, fields)
        indexes = TSV_COLUMNS.to_h { |column| [column, fields.index(column)] }
        missing = indexes.select { |_, index| index.nil? }.keys
        return indexes if missing.empty?

        raise Nabu::FetchError,
              "#{manifest.id}: metadata TSV #{path} is missing the #{missing.join(', ')} column(s) — " \
              "an upstream schema change, re-census before ingesting"
      end

      # The data/<author>/<book>/<version> tree, sidecars excluded — the
      # discovery_skips stray scan.
      def version_files(workdir)
        Dir.glob(File.join(workdir, "data", "*", "*", "*"))
           .reject { |path| path.end_with?(".yml") }
           .select { |path| File.file?(path) }
           .map { |path| File.expand_path(path) }
           .sort
      end

      # -- parse --------------------------------------------------------------

      def unmappable_suffix_message(document_ref)
        "#{document_ref.id}: unmappable language suffix in the version URI — only -ara*/-per* " \
          "(→ ara/fas) are in the D41-e first wave; multi-language suffixes belong to the MSS " \
          "sub-corpus, which is skip-by-rule. Quarantined rather than guessed."
      end

      def build_document(document_ref, language)
        header = parser.header(document_ref.path)
        body = parser.body(document_ref.path)
        document = Nabu::Document.new(
          urn: document_ref.id, language: language, title: document_ref.metadata["title"],
          canonical_path: document_ref.path,
          metadata: document_metadata(header, body, document_ref)
        )
        append_units(document, body.units, document_ref.id, language)
        if document.empty?
          raise ParseError, "#{document_ref.id}: header-only mARkdown body — the TSV promised text " \
                            "(tok_length > 0 for every in-scope row)"
        end

        document
      end

      def document_metadata(header, body, document_ref)
        document_ref.metadata.slice("title_ar", "author_lat", "author_ar", "death_ah", "status")
                    .merge(
                      "meta_lines" => (header.meta_lines unless header.meta_lines.empty?),
                      "census" => (body.census unless body.census.empty?),
                      "version_issues" => sidecar_issues(document_ref.path)
                    ).compact
      end

      # The .yml sidecar's ISSUES value (PRIMARY_VERSION flags etc.),
      # verbatim, when the sidecar travels with the tree — no machinery
      # beyond the carry (owner scope).
      def sidecar_issues(path)
        sidecar = "#{path}.yml"
        return nil unless File.file?(sidecar)

        line = File.foreach(sidecar, encoding: Encoding::UTF_8)
                   .find { |candidate| candidate.include?("#VERS#ISSUES") }
        return nil if line.nil?

        presence(line.split(":", 2).last.strip)
      end

      def append_units(document, units, urn, language)
        ordinals = Hash.new(0)
        seen = Hash.new(0)
        units.each do |unit|
          document << Nabu::Passage.new(
            urn: "#{urn}:#{disambiguate(unit_ref(unit, ordinals), seen)}",
            language: language, text: unit.text,
            annotations: unit_annotations(unit), sequence: document.size
          )
        end
      end

      # The ref grammar (class comment): <volume>.<page>.<n>, unplaced tail
      # x.<n>. Ordinals are keyed per (volume, page) across the WHOLE
      # document, so a revisited page keeps counting up — no collisions.
      def unit_ref(unit, ordinals)
        key = unit.volume ? [unit.volume, unit.page] : :unplaced
        ordinal = (ordinals[key] += 1)
        key == :unplaced ? "x.#{ordinal}" : "#{unit.volume}.#{unit.page}.#{ordinal}"
      end

      # Belt on the grammar's braces: the house :b2 positional disambiguator
      # (the ReM lesson) — never quarantine for a ref collision.
      def disambiguate(ref, seen)
        count = (seen[ref] += 1)
        count == 1 ? ref : "#{ref}:b#{count}"
      end

      def unit_annotations(unit)
        annotations = kind_annotations(unit)
        annotations["page_breaks"] = unit.page_breaks unless unit.page_breaks.empty?
        annotations["milestones"] = unit.milestones unless unit.milestones.empty?
        annotations
      end

      def kind_annotations(unit)
        case unit.kind
        when :verse
          { "kind" => "verse", "hemistichs" => unit.hemistichs,
            "verse_number" => unit.verse_number }.compact
        when :section_header
          { "kind" => "section_header", "level" => unit.level,
            "section_path" => unit.section_path }.merge(unit.annotations)
        else
          {}
        end
      end

      # -- fetch --------------------------------------------------------------

      def zip_fetch(workdir, progress)
        Nabu::ZipFetch.new(
          url: ZIP_URL, dir: workdir, attic_dir: File.join(workdir, ATTIC_DIRNAME),
          progress: progress, stream: true, keep: [METADATA_DIRNAME]
        )
      end

      def tsv_fetch(workdir, progress)
        Nabu::FileFetch.new(
          url: TSV_URL, dir: File.join(workdir, METADATA_DIRNAME), filename: TSV_FILENAME,
          attic_dir: File.join(workdir, ATTIC_DIRNAME, METADATA_DIRNAME), progress: progress
        )
      end

      def verify_md5!(not_modified, actual, pin, label, url)
        return if not_modified || actual == pin

        raise Nabu::FetchError,
              "openiti: #{label} misses the upstream-published md5 pin (expected #{pin}, got " \
              "#{actual}) — Zenodo artifacts are immutable, so this is corruption or an unannounced " \
              "re-release; verify #{url} against #{RECORD_URL} and re-pin the RELEASE_*_MD5 " \
              "constants only after reading the record"
      end

      def fetch_notes(zip, tsv)
        parts = []
        parts << if zip.not_modified?
                   "zip not modified (304)"
                 else
                   "zenodo 2025.1.9 zip md5 pin verified; zip sha256 #{zip.sha} recorded " \
                     "(the ledger pin for a future sha256 re-verification)"
                 end
        parts << (tsv.not_modified? ? "metadata tsv not modified (304)" : "metadata tsv md5 pin verified")
        parts << attic_notes(zip.atticked + tsv.atticked)
        parts.compact.join("; ")
      end
    end
  end
end
