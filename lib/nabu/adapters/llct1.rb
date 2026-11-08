# frozen_string_literal: true

require_relative "pml_treebank_parser"
require_relative "../file_fetch"

module Nabu
  module Adapters
    # LLCT1 — the Late Latin Charter Treebank 1 (Timo Korkiakangas,
    # University of Helsinki; v1.2, Zenodo 3633607, 2020-02-01): "Early
    # Medieval Latin documentary texts from Italy between AD 714-869 with
    # morphological and syntactic annotation" (the record's description) —
    # 519 private charters of Lombard and Carolingian Tuscany (sales,
    # livello leases, offerings to churches, dowries, court notices …),
    # written mostly at Lucca, also Pisa, Chiusi, Sovana, Monte Amiata,
    # Pistoia. Hand-annotated LDT-style (Latin Dependency Treebank) lemma,
    # morphology and dependency syntax on every word — gold. The first
    # composition of the `aldt-pml` family (PmlTreebankParser): PML is a
    # format new to the library.
    #
    # == Delivery grains (censused 2026-11-08 over the whole v1.2 file)
    #
    # Upstream serves ONE file, "LLCT1, version 1.2.xml" (42,231,522 B,
    # md5 ec45ae3a… = the record's own checksum). Inside it:
    #   - the PML <head> (a schema href; aldt_schema.xml is NOT shipped) and
    #     an <aldt_meta> annotator block of template placeholders
    #     ("short_name", "name", "address") — furniture, no text;
    #   - 9,227 sentence trees (<LM> children of <aldt_trees>), each
    #     carrying its charter's identity and metadata on its root:
    #     document_id (the edition siglum: CDL / CDT / MED), subdoc (the
    #     charter's number in that edition), date, place, scribe, type,
    #     redaction;
    #   - 225,834 word nodes (nested <LM>);
    #   - trailing TrEd display PIs (<?tred-pattern?>, <?tred-hint?>).
    # Document = the CHARTER (document_id + subdoc), the unit upstream's
    # own metadata names: urn:nabu:llct1:<siglum>-<number> (CDL-115,
    # CDL-APPENDICE — the one non-numeric number, verbatim). Passage = the
    # sentence tree (…:<tree id>, upstream's corpus-wide sentence key).
    # Each charter's trees are contiguous in the file and carry identical
    # root metadata on every tree (both censused: 519 runs for 519
    # charters, 0 varying) — parse re-checks the second per tree, so a
    # drifted file quarantines rather than misreads. Header, annotator
    # block and PIs are no-text furniture inside the one accepted file:
    # nothing upstream serves is skipped by rule.
    #
    # Reconciliation: upstream advertises no count (the record states the
    # period only). The file's own content = 519 charters (CDL 180 · CDT
    # 39 · MED 300) / 9,227 trees / 225,834 words — expected first sync
    # 519 documents / 9,227 passages (every tree has surface text), 0
    # errored — measured through this adapter over the whole file
    # (2026-11-08, ~7 s); 197,030 of the 225,834 tokens carry a lemma
    # (4,742 distinct; the rest are the family's screened placeholders).
    #
    # Grain cost: the corpus is one 42 MB file, so discover runs the
    # family's LEXICAL span scan (byte offset + root attributes per tree,
    # ~1 s over the whole file) and each charter's ref carries its trees'
    # byte ranges; parse cuts only those bytes from the file buffer, read
    # once per adapter instance through the encoding belt. Ranges are
    # discover plumbing and never reach catalog metadata.
    #
    # == Editions, witnesses, dedupe
    #
    # The three sigla are upstream's: CDL = Schiaparelli's Codice
    # diplomatico longobardo (714–786 here; 180 charters — 155 originals,
    # 25 copies), CDT = Brunetti's Codice diplomatico toscano (775–813; 39
    # — 38 + 1), MED = the Lucca "Memorie e documenti" series (776–869;
    # 300 — 288 + 12). LLCT1 is NOT held elsewhere: the
    # held `ud` latin-llct treebank is LLCT2 ONLY (its README: "an
    # automated conversion of the LLCT2 treebank", 521 originals
    # 774–897, the Barsocchini/Bertini Lucca editions, sentence ids keyed
    # to ChLA numbers) and calls LLCT1 "the first part" — the two parts
    # are disjoint charter sets by construction (LLCT1 was LLCT2's
    # training set). The keys differ (edition number here, ChLA there),
    # so no per-charter crosswalk is possible from the assets themselves;
    # kept as its own witness. The CDT 2:1 TEI base text (Zenodo 4745111,
    # Brunetti 775–813) is the unannotated edition behind the CDT rows —
    # not taken (the 2026-11 charters survey).
    #
    # == Axes mined (aggressive-mining law — everything the asset carries)
    #
    # - date: every charter carries one year (714–869) → metadata "date"
    #   {not_before = not_after = year, raw}, :structured. For an
    #   ORIGINAL (481 charters) that is the artifact's own year — no class
    #   label; for a COPY (38) the year is the act's, not the copy's →
    #   class "composition".
    # - place: the place of issue verbatim (109 forms, upstream's own
    #   hedges "Chiusi?", "(Lucca?)" kept); "-" (4 charters) = upstream's
    #   no-place → no place key.
    # - kind: "type" → metadata "document_type" verbatim (50 labels, Latin
    #   "charta venditionis" and Italian "Istrumento di vendita" alike),
    #   folded in config/kind_map.yml.
    # - scribe (165 names incl. "anonimo"), redaction (original/copy) and
    #   the edition siglum ride metadata (facets via config/facet_map.yml).
    # - per word: seg (formulaic / free / subs — the charter's formulaic
    #   frame vs its free text vs the subscriptions) and status (normal /
    #   expan — an expanded abbreviation / damage) ride every token.
    #
    # == License
    #
    # CC BY 4.0 — the Zenodo record's license field (cc-by-4.0); the file
    # carries no header → attribution. Cite: Korkiakangas, T. (2020), Late
    # Latin Charter Treebank 1 (LLCT1), version 1.2, doi:10.5281/zenodo.3633607.
    #
    # == fetch
    #
    # Nabu::FileFetch of the single file, sha256-PINNED to v1.2 (the
    # helipad choreography: prepare, verify pin, breaker, complete). A new
    # LLCT1 version is a new Zenodo record the owner re-pins → manual.
    # Zenodo throttles a single connection hard for this file (~17 kB/s
    # measured 2026-11-08 — ~40 min for 42 MB); the first sync's fetch is
    # slow, not stuck.
    class Llct1 < Nabu::Adapter
      RECORD_URL = "https://zenodo.org/records/3633607"
      FILE_URL = "https://zenodo.org/api/records/3633607/files/LLCT1,%20version%201.2.xml/content"
      FILENAME = "llct1-1.2.xml"
      # sha256 of the full 42,231,522 B v1.2 file (md5 ec45ae3a6844fad40a00d2e8050cfc74,
      # Zenodo's own), recorded at fixture build 2026-11-08.
      FILE_SHA256 = "88c4b076237b50ca07987d50c6257e9667e4cb76be48945c43a9f431bd79991f"
      LANGUAGE = "lat"
      URN_PREFIX = "urn:nabu:llct1:"
      NO_PLACE = "-"

      MANIFEST = Nabu::SourceManifest.new(
        id: "llct1",
        name: "LLCT1 — Late Latin Charter Treebank 1 (Korkiakangas; Zenodo 3633607, v1.2)",
        license: "CC BY 4.0 (Zenodo record 3633607 license field cc-by-4.0; no in-file license " \
                 "header — record-level grant. Cite: Korkiakangas, Timo (2020), Late Latin Charter " \
                 "Treebank 1 (LLCT1), version 1.2, doi:10.5281/zenodo.3633607)",
        license_class: "attribution",
        upstream_url: RECORD_URL,
        parser_family: "aldt-pml"
      )

      def self.manifest = MANIFEST

      # The probe HEADs the file URL itself (the helipad shape: the Zenodo
      # API record body carries volatile stats, so no metadata endpoint).
      def self.remote_probe_strategy = :http_zip

      def self.http_probe_targets
        [Nabu::Adapter::HttpProbeTarget.new(
          label: FILENAME, zip_url: FILE_URL, metadata_url: nil,
          state_subdir: "", state_file: Nabu::FileFetch::STATE_FILE
        )]
      end

      # +file_sha256+ exists for the WebMock'd fetch tests — real syncs keep
      # the frozen pin.
      def initialize(file_sha256: FILE_SHA256)
        super()
        @file_sha256 = file_sha256
      end

      # One DocumentRef per charter, in file order, over every top-level
      # *.xml in +workdir+ (the fetched file; the fixture trim). A workdir
      # without one yields nothing.
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        Dir.glob(File.join(workdir, "*.xml")).each do |path|
          charter_refs(path).each(&block)
        end
      end

      def parse(document_ref)
        root = document_ref.metadata.fetch("root")
        fragment = PmlTreebankParser.fragment(buffer(document_ref.path), document_ref.metadata.fetch("ranges"),
                                              path: document_ref.path)
        verify_trees!(document_ref, root, fragment)
        PmlTreebankParser.new.parse(
          StringIO.new(fragment), urn: document_ref.id, language: LANGUAGE, title: title(root),
                                  metadata: charter_metadata(root), canonical_path: document_ref.path
        )
      end

      # Download the single pinned file via FileFetch, two-phase (helipad).
      def fetch(workdir, progress: nil, force: false)
        fetch = Nabu::FileFetch.new(url: FILE_URL, dir: workdir, filename: FILENAME,
                                    attic_dir: File.join(workdir, ATTIC_DIRNAME), progress: progress)
        fetch.prepare!
        verify_pin!(fetch)
        guard_mass_deletion!(workdir, fetch.doomed_paths, force: force)
        fetch.complete!
        FetchReport.new(sha: fetch.sha, fetched_at: Time.now, notes: attic_notes(fetch.atticked))
      rescue FileFetch::Error => e
        raise Nabu::FetchError, "llct1 fetch failed into #{workdir}: #{e.message}"
      end

      private

      def verify_pin!(fetch)
        return if fetch.sha == @file_sha256

        raise Nabu::FetchError,
              "llct1: #{FILENAME} drifted — fetched sha256 #{fetch.sha} != pinned #{@file_sha256}; " \
              "the deposit is frozen at v1.2 (Zenodo 3633607) — review upstream and re-pin (owner decision)"
      end

      # Consecutive trees sharing (document_id, subdoc) form one charter. A
      # charter recurring later in the file (none in v1.2) folds its trees
      # into the same ref, in file order.
      def charter_refs(path)
        charters = {}
        PmlTreebankParser.tree_spans(buffer(path)).each do |span|
          root = root_of(span.attributes)
          next unless root

          entry = charters[urn_for(root)] ||= { root: root, ranges: [] }
          entry[:ranges] << [span.offset, span.length]
        end
        charters.map do |urn, entry|
          Nabu::DocumentRef.new(source_id: MANIFEST.id, id: urn, path: File.expand_path(path),
                                metadata: { "root" => entry[:root], "ranges" => entry[:ranges] })
        end
      end

      # The file read ONCE per adapter instance (class note: one 42 MB file,
      # 519 documents cut from it), keyed by path + size + mtime so a
      # re-fetched file is re-read.
      def buffer(path)
        key = [path, File.size(path), File.mtime(path)]
        return @buffer if @buffer_key == key

        @buffer_key = key
        @buffer = PmlTreebankParser.read(path)
      end

      # Root attributes under the adapter's names (document_id → edition,
      # subdoc → number; the rest verbatim). nil for a tree without the
      # charter identity (none in v1.2).
      def root_of(attributes)
        edition = attributes["document_id"].to_s
        number = attributes["subdoc"].to_s
        return nil if edition.empty? || number.empty?

        { "edition" => edition, "number" => number }
          .merge(attributes.except("document_id", "subdoc").transform_values { |v| Nabu::Normalize.nfc(v) })
      end

      def urn_for(root) = "#{URN_PREFIX}#{root['edition']}-#{root['number']}"

      # Every tree cut by the ref's ranges must carry the ref's own root
      # metadata (class note: the drift guard).
      def verify_trees!(ref, root, fragment)
        PmlTreebankParser.new.trees(StringIO.new(fragment), path: ref.path).each do |tree|
          next if root_of(tree.attributes) == root

          raise ParseError, "#{ref.path}: tree #{tree.id} does not belong to #{ref.id} " \
                            "(its root carries #{tree.attributes.inspect}) — re-discover"
        end
      end

      def title(root) = "#{root['edition']} #{root['number']} — #{root['type']} (#{root['date']})"

      def charter_metadata(root)
        {
          "edition" => root["edition"], "number" => root["number"], "date" => date(root),
          "place" => (root["place"] unless root["place"].to_s.strip == NO_PLACE || root["place"].to_s.empty?),
          "document_type" => root["type"], "scribe" => root["scribe"], "redaction" => root["redaction"]
        }.compact
      end

      def date(root)
        raw = root["date"].to_s
        return nil unless raw.match?(/\A\d{3,4}\z/)

        year = Integer(raw, 10)
        { "not_before" => year, "not_after" => year, "raw" => raw,
          "class" => ("composition" if root["redaction"] == "copy") }.compact
      end
    end
  end
end
