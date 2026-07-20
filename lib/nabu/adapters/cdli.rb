# frozen_string_literal: true

require_relative "atf_parser"
require_relative "flat_csv_parser"
require_relative "../lfs_fetch"

module Nabu
  module Adapters
    # The CDLI adapter (P31-2): the Cuneiform Digital Library Initiative's
    # bulk dump — the universal cuneiform catalog (353,283 artifacts at the
    # snapshot) plus the C-ATF transliteration mass (135,255 blocks /
    # ~2.19M lines) — through the new atf parser family.
    #
    # == Upstream: github.com/cdli-gh/data, honestly a 2023-10 SNAPSHOT
    #
    # The repo self-describes as the "daily dump" but its last commit is
    # d66b12b (2023-10-11) and its README says "Last update was August
    # 2022" — the daily dump is dead. The cdli.earth API is the freshness
    # channel (journaled in docs/02-sources.md, deliberately not wired).
    # Both data files are Git LFS objects (cdli_cat.csv 154,768,722 B ·
    # cdliatf_unblocked.atf 86,897,831 B, sha256 oids in the pointers):
    # fetch = the shared GitFetch choreography + Nabu::LfsFetch
    # materialization (batch API, sha256-verified — verified live
    # 2026-07-19 against github's anonymous LFS endpoint; a plain clone on
    # a machine without git-lfs leaves 134-byte pointer stubs, which
    # discovery treats as "not materialized", never as an empty corpus).
    #
    # == License (the bespoke open grant, verbatim — cdli.earth/terms-of-use)
    #
    # "Text in the pages of CDLI may be freely copied, aggregated and
    # re-used according to common and fair academic practice; we request,
    # in the case of re-use of considerable textual data, that mention be
    # made of the source of such material, with reference to CDLI."
    # → attribution. Images are under a separate fair-use regime and
    # ENTIRELY out of scope (never fetched).
    #
    # == Identity and grain
    #
    # Document = the P-number artifact: urn:nabu:cdli:p000725 (urn_for is
    # the ONE minting rule — the timeline extractor joins through it, no
    # drift). Passage = the line within object/face/column (AtfParser class
    # note). Q composites are NOT documents here (no &Q blocks exist in
    # the dump): >>Q links and catalog composite_id mint
    # urn:nabu:cdli:q… reference edges — dangling-but-stable targets, the
    # eBL cdliNumber edges land in the same space (P31-3).
    #
    # == The universal catalog (owner-approved 2026-07-19: ALL artifacts)
    #
    # Every cdli_cat.csv row WITHOUT an ATF block becomes a metadata-only
    # document ("text_layer" => "none" — the ogham/isicily precedent at
    # scale: ~218k documents). Rows WITH a block enrich the text document's
    # metadata. Facets: genre / period / provenience / collection / ruler
    # (the ruler = the regnal head of dates_referenced, "Amar-Suen.01.04.
    # 00" — filler heads "00"/"--" excluded). 59 distinct catalog language
    # values map honestly (CATALOG_LANGUAGES; "?"-suffix and "(pseudo)"
    # markers shed for the code, verbatim kept; first language of a
    # multi-language value wins; junk values like "clay" ×9 → und).
    # NO #lem lines exist anywhere in C-ATF → the source registers
    # lemma_tier: silver defensively and emits no lemma annotations at
    # all: lemma search stays ORACC-gold.
    #
    # == Discovery (byte-offset index — 87 MB is never re-read per parse)
    #
    # One streaming pass over the ATF records each block's byte offset +
    # length keyed by P-number (duplicate &P headers — 54 at the snapshot,
    # same P re-listed under two designations — keep the FIRST block, the
    # house first-wins rule; the rest are skipped-by-rule). One streaming
    # pass over the CSV carries each row's reduced fields in the ref
    # metadata, so parse never re-reads the 155 MB catalog. Refs sort by
    # urn; the same walk works under the attic.
    #
    # == Reference edges (producer "cdli")
    #
    # metadata "related" carries: >>Q/>>P targets and #link definitions
    # (urn:nabu:cdli:q…/p…), catalog composite_id Q-numbers, and the
    # colon-schemed external_id concordances (bdtns:015946 — 96,641 rows;
    # the BDTNS bridge). ORACC edges are deliberately NOT minted: ORACC
    # urns need a project segment (urn:nabu:oracc:<project>:<P>) the
    # catalog cannot supply — the join lives on the ORACC side, where
    # every P-numbered urn already contains its CDLI id (journaled, not
    # guessed).
    class Cdli < Nabu::Adapter
      REPO_URL = "https://github.com/cdli-gh/data"

      ATF_FILENAME = "cdliatf_unblocked.atf"
      CATALOG_FILENAME = "cdli_cat.csv"
      LFS_PATHS = [CATALOG_FILENAME, ATF_FILENAME].freeze

      URN_PREFIX = "urn:nabu:cdli:"

      # The verbatim grant (class note). Retrieved 2026-07-19 from
      # cdli.earth/terms-of-use.
      LICENSE_GRANT = "Text in the pages of CDLI may be freely copied, aggregated and " \
                      "re-used according to common and fair academic practice; we request, " \
                      "in the case of re-use of considerable textual data, that mention be " \
                      "made of the source of such material, with reference to CDLI."

      MANIFEST = Nabu::SourceManifest.new(
        id: "cdli",
        name: "CDLI — Cuneiform Digital Library Initiative (2023-10 bulk-dump snapshot)",
        license: "Bespoke open grant, cdli.earth/terms-of-use verbatim: \"#{LICENSE_GRANT}\" " \
                 "— images under a separate fair-use regime, entirely out of scope",
        license_class: "attribution",
        upstream_url: REPO_URL,
        parser_family: "atf"
      )

      # #atf: lang codes → stored codes (censused over the full dump; the
      # q-range codes are CDLI's own local-use inventions and the honest
      # keepers for proto-cuneiform/proto-Elamite — these scripts' only
      # machine-readable home). qeb IS Eblaite (1,358/1,359 blocks join
      # catalog "Eblaite") → ISO 639-3 xeb; nlc = "no linguistic content"
      # → zxx; qcu (26 blocks, catalog blank/Akkadian) is undetermined →
      # und. Unmapped (typo debris "%eop", ":") → und, verbatim kept.
      ATF_LANGUAGES = {
        "sux" => "sux", "akk" => "akk", "qpc" => "qpc", "qpe" => "qpe",
        "qeb" => "xeb", "nlc" => "zxx", "qcu" => "und",
        "peo" => "peo", "elx" => "elx", "xhu" => "xhu", "hit" => "hit",
        "uga" => "uga", "arc" => "arc", "xur" => "xur", "urartian" => "xur",
        "und" => "und"
      }.freeze

      # Catalog language values → stored codes (59 distinct values censused;
      # "?" and "(pseudo)" markers shed before lookup, first entry of a
      # ";"/"," list wins, verbatim always kept in metadata). "Persian" is
      # Old Persian (Achaemenid trilinguals), "Babylonian" Akkadian;
      # explicit not-a-language values → zxx; unknowns (incl. the "clay"
      # column-drift junk) → und.
      CATALOG_LANGUAGES = {
        "Sumerian" => "sux", "Akkadian" => "akk", "Hittite" => "hit",
        "Eblaite" => "xeb", "Elamite" => "elx", "Ugaritic" => "uga",
        "Egyptian" => "egy", "Persian" => "peo", "Aramaic" => "arc",
        "Hebrew" => "heb", "Hurrian" => "xhu", "Luwian" => "xlu",
        "Urartian" => "xur", "Greek" => "grc", "Phoenician" => "phn",
        "Mandaic" => "myz", "Qatabanian" => "xqt", "Babylonian" => "akk",
        "no linguistic content" => "zxx", "uninscribed" => "zxx",
        "undetermined" => "und", "uncertain" => "und", "unclear" => "und"
      }.freeze

      # The catalog columns the adapter depends on (FlatCsvParser's loud
      # header gate — a silently renamed upstream column must fail).
      REQUIRED_HEADERS = %w[id_text designation language period provenience collection
                            genre object_type material dates_referenced museum_no
                            primary_publication composite_id external_id].freeze

      # Catalog fields carried into document metadata verbatim (non-empty,
      # NFC). language rides as "catalog_language" (the parser owns
      # "language_raw" for #atf lang drift).
      METADATA_FIELDS = %w[period provenience collection genre object_type material
                           dates_referenced museum_no primary_publication composite_id
                           external_id].freeze

      # dates_referenced heads that are date filler, not rulers.
      RULER_FILLER = /\A[0-9.\- –]*\z/

      # An ATF document header ("&P000001", the "& P519727" typo included).
      HEADER_LINE = /\A&\s*P(\d+)/

      def self.manifest
        MANIFEST
      end

      # urn:nabu:cdli:p000725 from "P000725" or an id_text integer — the
      # ONE minting rule (CdliDates joins through it; open-etruscan
      # precedent).
      def self.urn_for(id)
        number = id.to_s.delete_prefix("P").delete_prefix("p").to_i
        format("%<prefix>sp%<number>06d", prefix: URN_PREFIX, number: number)
      end

      # >>Q composite links, composite_id, and bdtns/cmawro concordances
      # (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "cdli")
      end

      def initialize
        super
        @catalog_cache = {}
        @atf_cache = {}
      end

      # One ref per artifact: text refs for ATF blocks (offset/length +
      # catalog fields in metadata), metadata-only refs for the catalog
      # remainder. Yields nothing pre-fetch, and treats unmaterialized LFS
      # pointers as absent files (discovery_skips renders that loudly).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # Duplicate &P blocks skip by rule (first wins); an LFS pointer file
      # is UNRECOGNIZED — the corpus is present-but-unmaterialized, a loud
      # state, never a silent zero.
      def discovery_skips(workdir)
        notes = pointer_notes(workdir)
        duplicates = atf_index(workdir)[:duplicates]
        Nabu::Adapter::DiscoverySkips.new(
          skipped_by_rule: duplicates,
          unrecognized: notes.size, notes: notes
        )
      end

      def parse(document_ref)
        metadata = document_ref.metadata
        if metadata["kind"] == "metadata_only"
          metadata_only_document(document_ref)
        else
          atf_document(document_ref)
        end
      rescue ValidationError => e
        raise ParseError, "#{document_ref.path}: #{document_ref.id}: #{e.message}"
      end

      # The shared GitFetch choreography wrapped with LFS materialization:
      # recorded payloads step aside (pointers restored) so the ff-merge
      # sees the tree git expects, then the pointers materialize back —
      # cache-hits by oid, downloads sha256-verified (LfsFetch).
      def fetch(workdir, progress: nil, force: false)
        lfs = lfs_fetch(workdir)
        lfs.restore_pointers!
        report = git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
        lfs_notes = lfs.materialize!(progress: progress)
        report.with(notes: [report.notes, lfs_notes].compact.join(" · "))
      rescue LfsFetch::Error => e
        raise FetchError, "cdli fetch failed into #{workdir}: #{e.message}"
      end

      private

      def lfs_fetch(workdir)
        LfsFetch.new(repo_url: REPO_URL, dir: workdir, paths: LFS_PATHS)
      end

      def atf_path(workdir) = File.join(workdir, ATF_FILENAME)
      def catalog_path(workdir) = File.join(workdir, CATALOG_FILENAME)

      # A data file is usable when present and not an LFS pointer stub.
      def usable?(path)
        File.file?(path) && !LfsFetch.pointer?(path)
      end

      def pointer_notes(workdir)
        [atf_path(workdir), catalog_path(workdir)].filter_map do |path|
          next unless File.file?(path) && LfsFetch.pointer?(path)

          "#{File.basename(path)}: unmaterialized Git LFS pointer — re-run sync to download the payload"
        end
      end

      # -- refs -----------------------------------------------------------------

      def document_refs(workdir)
        atf = usable?(atf_path(workdir)) ? atf_index(workdir)[:blocks] : {}
        rows = usable?(catalog_path(workdir)) ? catalog_rows(workdir) : {}
        refs = atf.map do |number, block|
          text_ref(workdir, number, block, rows[number])
        end
        rows.each do |number, row|
          next if atf.key?(number)

          refs << metadata_only_ref(workdir, number, row)
        end
        refs.sort_by!(&:id)
        refs
      end

      def text_ref(workdir, number, block, row)
        metadata = { "offset" => block[:offset], "length" => block[:length],
                     "line" => block[:line] }
        metadata["catalog"] = row if row
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: self.class.urn_for(number),
          path: File.expand_path(atf_path(workdir)), metadata: metadata
        )
      end

      def metadata_only_ref(workdir, number, row)
        Nabu::DocumentRef.new(
          source_id: manifest.id, id: self.class.urn_for(number),
          path: File.expand_path(catalog_path(workdir)),
          metadata: { "kind" => "metadata_only", "catalog" => row }
        )
      end

      # -- the ATF block index (one streaming pass, byte offsets) ---------------

      def atf_index(workdir)
        path = atf_path(workdir)
        return { blocks: {}, duplicates: 0 } unless usable?(path)

        @atf_cache[File.expand_path(path)] ||= build_atf_index(path)
      end

      def build_atf_index(path)
        blocks = {}
        duplicates = 0
        current = nil
        offset = 0
        line_number = 0
        File.open(path, "rb") do |io|
          io.each_line do |raw|
            line_number += 1
            if (match = HEADER_LINE.match(raw))
              current&.then { |block| block[:length] = offset - block[:offset] }
              number = match[1].to_i
              if blocks.key?(number)
                duplicates += 1
                current = nil # first block wins; this one is skipped by rule
              else
                current = { offset: offset, length: 0, line: line_number }
                blocks[number] = current
              end
            end
            offset += raw.bytesize
          end
        end
        current&.then { |block| block[:length] = offset - block[:offset] }
        { blocks: blocks, duplicates: duplicates }
      end

      # -- the catalog (one streaming pass, reduced fields) ---------------------

      def catalog_rows(workdir)
        path = catalog_path(workdir)
        @catalog_cache[File.expand_path(path)] ||= begin
          rows = {}
          parser = FlatCsvParser.new(required_headers: REQUIRED_HEADERS)
          parser.each_row(File.expand_path(path)) do |row|
            number = row["id_text"].to_s.strip
            next unless number.match?(/\A\d+\z/)

            rows[number.to_i] ||= reduce_row(row)
          end
          rows
        end
      end

      # The fields parse needs, non-empty and NFC — carried on the ref so
      # the 155 MB catalog is streamed once per discover, never per parse.
      def reduce_row(row)
        reduced = {}
        (%w[designation language] + METADATA_FIELDS).each do |field|
          value = row[field].to_s.strip
          reduced[field] = Normalize.nfc(value) unless value.empty?
        end
        reduced
      end

      # -- document building ----------------------------------------------------

      def metadata_only_document(document_ref)
        row = document_ref.metadata.fetch("catalog")
        metadata = catalog_metadata(row)
        metadata["text_layer"] = "none"
        Nabu::Document.new(
          urn: document_ref.id, language: catalog_language(row["language"]),
          title: row["designation"], canonical_path: document_ref.path,
          metadata: metadata
        )
      end

      def atf_document(document_ref)
        row = document_ref.metadata["catalog"] || {}
        block = read_block(document_ref)
        atf_parser.parse(
          block, urn: document_ref.id, path: document_ref.path,
                 line: document_ref.metadata.fetch("line", 1),
                 language_fallback: row["language"] && catalog_language(row["language"]),
                 title_fallback: row["designation"],
                 metadata: catalog_metadata(row)
        )
      end

      def read_block(document_ref)
        offset = document_ref.metadata.fetch("offset")
        length = document_ref.metadata.fetch("length")
        File.open(document_ref.path, "rb") do |io|
          io.seek(offset)
          block = io.read(length).to_s.force_encoding(Encoding::UTF_8)
          unless block.valid_encoding?
            raise ParseError, "#{document_ref.path}: #{document_ref.id}: invalid UTF-8 in ATF block"
          end

          block
        end
      end

      def atf_parser
        Nabu::Adapters::AtfParser.new(
          language_map: ATF_LANGUAGES,
          related_target: ->(id) { "#{URN_PREFIX}#{id.downcase}" }
        )
      end

      # Catalog fields → document metadata + facets + related (class note).
      def catalog_metadata(row)
        metadata = {}
        metadata["catalog_language"] = row["language"] if row["language"]
        METADATA_FIELDS.each do |field|
          metadata[field] = row[field] if row[field]
        end
        facets = build_facets(row)
        metadata["facets"] = facets unless facets.empty?
        related = catalog_related(row)
        metadata["related"] = related unless related.empty?
        metadata
      end

      def build_facets(row)
        facets = {}
        { "genre" => row["genre"], "period" => row["period"],
          "provenience" => row["provenience"], "collection" => row["collection"],
          "ruler" => ruler_of(row["dates_referenced"]) }.each do |facet, value|
          facets[facet] = { "value" => value } if value
        end
        facets
      end

      # "Amar-Suen.01.04.00" → "Amar-Suen"; filler heads ("00", "--") are
      # dates-without-rulers, not rulers.
      def ruler_of(dates_referenced)
        head = dates_referenced.to_s.split(".").first.to_s.strip
        return nil if head.empty? || head.match?(RULER_FILLER)

        head
      end

      # composite_id Q-numbers (junk like "needed" contributes nothing;
      # "Q000039, Q000040" contributes both; "Q002718.01" its Q) + the
      # colon-schemed external_id concordances (the P25-1 edge-worthiness
      # rule: a scheme mints an edge, a bare string stays metadata).
      def catalog_related(row)
        related = row["composite_id"].to_s.scan(/Q\d{6}/).map { |q| "#{URN_PREFIX}#{q.downcase}" }
        external = row["external_id"].to_s.strip
        related << external if external.match?(/\A[a-z][a-z0-9+.-]*:\S+\z/i)
        related.uniq
      end

      def catalog_language(value)
        return "und" if value.nil?

        first = value.split(/[;,]/).first.to_s.strip
        first = first.sub(/\s*\(pseudo\)\z/, "").sub(/\s*\?\z/, "").strip
        CATALOG_LANGUAGES.fetch(first, "und")
      end
    end
  end
end
