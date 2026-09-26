# frozen_string_literal: true

require "nokogiri"

module Nabu
  module Adapters
    # The Papyri.info adapter (architecture §3, packet P3-6): a thin
    # composition of the DdbdpParser family with the idp.data repo layout. It
    # owns what the streaming parser deliberately does not: repo walking,
    # header metadata resolution (idnos/title/language peeked cheaply from
    # each file's teiHeader), and fetch.
    #
    # == Layout and discovery
    #
    # The DDbDP tree lives under DDB_EpiDoc_XML/<collection>/, with volumed
    # collections nesting one more level (<collection>.<volume>/): both
    # bgu/bgu.1/bgu.1.102.xml (nested) and c.epist.lat/c.epist.lat.10.xml
    # (flat, volume-less) occur. Discover globs both shapes and peeks each
    # header; files without an <idno type="ddb-hybrid"> or an edition
    # language are skipped defensively (the repo carries the odd non-DDbDP
    # artifact that must not error discover).
    #
    # == Identity (FROZEN minting)
    #
    # urn = urn:nabu:ddbdp:<ddb-hybrid with ";" replaced by ":">, e.g. idno
    # "bgu;1;102" → urn:nabu:ddbdp:bgu:1:102. Empty hybrid segments survive:
    # "c.epist.lat;;10" (volume-less) → urn:nabu:ddbdp:c.epist.lat::10. The
    # parser mints from the same idno and cross-checks, so
    # ref.id == parse(ref).urn (the conformance identity the sync circuit
    # breaker relies on). HGV and TM idnos ride along in DocumentRef metadata
    # for future cross-linking (Trismegistos is the id crosswalk of the
    # papyrological world).
    #
    # == The DCLP lane (P104-3)
    #
    # The same idp.data clone carries DCLP/ — the Digital Corpus of
    # Literary Papyri, 14,842 EpiDoc files under DCLP/<TM-thousand>/<TM>.xml
    # — parsed since P104-3 as a SECOND document family of THIS source.
    # Shape decision (extend-the-walk over a papyri-dclp sibling row,
    # recorded here): one upstream repo is one canonical asset is one
    # source — a sibling row's workdir is slug-bound (Config#source_workdir
    # → canonical/<slug>), so `papyri-dclp` would have to clone the
    # multi-GB idp.data a SECOND time and keep two GitFetch states racing
    # one upstream; the perseus-latin one-line sibling is no precedent
    # (canonical-latinLit is a genuinely separate upstream repo). The DCLP
    # delta is exactly a second walk root, a second identity idno
    # (dclp-hybrid) and a second urn namespace — the parser family and the
    # Leiden policy are shared verbatim, so DdbdpParser is parameterized
    # (idno_type:/urn_namespace:) rather than forked.
    #
    # Identity: urn = urn:nabu:dclp:<idno type="dclp">, e.g.
    # urn:nabu:dclp:62952 — the dclp number is upstream's own primary key
    # (papyri.info/dclp/<n>, the TM number, AND the filename; unique
    # across all 14,842 files, census 2026-09-26). NOT the dclp-hybrid:
    # the hybrid is demonstrably non-unique (two Homer papyri, TM 60467
    # and TM 61136, both carry <idno type="dclp-hybrid">p.hal;;5 — an
    # upstream cataloguing defect that would collide urns). Non-numeric
    # dclp idnos (one "hgvTEMP" placeholder upstream) skip defensively —
    # a temp id is not a stable identity. The namespace is distinct, so
    # dclp urns are structurally non-colliding with urn:nabu:ddbdp:* even
    # where one papyrus is held by both corpora.
    #
    # Discovery reality (census 2026-09-26 on the live clone): 12,571 of
    # 14,842 files are metadata-only catalog stubs — a SELF-CLOSED edition
    # div, no transcription — and a further handful scaffold an empty
    # <ab>/<lb> skeleton with no text. The DCLP peek therefore requires,
    # beyond dclp-hybrid + edition language, at least one non-whitespace
    # text node INSIDE the edition div (still a bounded header-and-edition
    # Reader walk that stops at the first hit); text-less files are
    # skipped at discover, not quarantined at parse. Expected live yield:
    # ~2,260 literary documents (grc ~2,19x, lat ~6x, cop ~1x).
    #
    # == fetch
    #
    # Single upstream repo → the Perseus git clone/pull pattern verbatim.
    # idp.data is HUGE (hundreds of thousands of files, years of edit
    # history), so the house `--depth 1` clone matters even more than usual
    # here. sync_policy: manual — DDbDP updates continuously but syncing it
    # is an owner decision, not a scheduled one.
    #
    # == License
    #
    # Repo and per-document <availability> agree: CC BY 3.0 ("© Duke Databank
    # of Documentary Papyri … Creative Commons Attribution 3.0 License";
    # DCLP files carry the same license under "© Digital Corpus of Literary
    # Papyri") — license_class "attribution". "per-document availability"
    # in the manifest license string records where the authoritative
    # statement lives.
    class Papyri < Nabu::Adapter
      MANIFEST = Nabu::SourceManifest.new(
        id: "papyri-ddbdp",
        name: "Papyri.info — Duke Databank of Documentary Papyri + " \
              "Digital Corpus of Literary Papyri",
        license: "CC BY 3.0 (per-document availability)",
        license_class: "attribution",
        upstream_url: "https://github.com/papyri/idp.data",
        parser_family: "ddbdp"
      )

      # Header idno types discover records (beyond ddb-hybrid identity).
      IDNO_TYPES = %w[ddb-hybrid HGV TM].freeze
      # The DCLP tree's identity idno + crosslinks (no HGV there; TM is the
      # crosswalk id AND the filename).
      DCLP_IDNO_TYPES = %w[dclp HGV TM].freeze
      private_constant :IDNO_TYPES, :DCLP_IDNO_TYPES

      def self.manifest
        MANIFEST
      end

      # Walk <workdir>/DDB_EpiDoc_XML for both nested and flat collections
      # plus <workdir>/DCLP (P104-3), one DocumentRef per file, the whole
      # union sorted by urn (dclp:* precedes ddbdp:* — discovery order is
      # urn order). Returns an Enumerator without a block (the adapter
      # contract's lazy shape).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        (document_refs(workdir) + dclp_document_refs(workdir)).sort_by(&:id).each(&block)
      end

      # Delegate to the DdbdpParser with the urn/language/title discover
      # resolved from the header; DCLP refs (by urn namespace) parse under
      # the dclp identity, everything else stays the frozen DDbDP default.
      def parse(document_ref)
        parser = if document_ref.id.start_with?("urn:nabu:dclp:")
                   DdbdpParser.new(idno_type: "dclp", urn_namespace: "dclp")
                 else
                   DdbdpParser.new
                 end
        parser.parse(
          document_ref.path,
          urn: document_ref.id,
          language: document_ref.metadata["language"],
          title: document_ref.metadata["title"],
          metadata: idno_metadata(document_ref.metadata)
        )
      end

      # P104-1 (Q77 under №R-70): the HGV/TM idnos, peeked at discover
      # since day one, now PERSIST — tm_nr/hgv verbatim plus a "tm:<n>"
      # related edge per numeric TM token (the P25-1 scheme rule; a
      # multi-text papyrus lists several, space-separated). HGV has no
      # ruled edge scheme and stays metadata-only.
      def idno_metadata(ref_metadata)
        metadata = {}
        metadata["hgv"] = ref_metadata["hgv"] if ref_metadata["hgv"]
        metadata["tm_nr"] = ref_metadata["tm"] if ref_metadata["tm"]
        related = ref_metadata["tm"].to_s.split(/\s+/).grep(/\A\d+\z/).map { |id| "tm:#{id}" }
        metadata["related"] = related unless related.empty?
        metadata
      end

      # The Trismegistos concordance edges (P104-1 — metadata "related").
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "papyri-ddbdp")
      end

      # Clone or non-destructively pull the idp.data repo into +workdir+ via
      # the shared git path (Adapter#git_fetch! → Nabu::GitFetch, P5-2: attic
      # + pre-merge mass-deletion breaker), returning a Nabu::FetchReport
      # pinning HEAD. No network in tests: exercised against a local fixture
      # git repo. A Shell failure aborts the sync as Nabu::FetchError; a
      # tripped breaker as Nabu::SyncAborted (+force+ overrides).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: repo_url, workdir: workdir, progress: progress, force: force)
      end

      private

      # The upstream repo URL, split out so fetch tests can point a singleton
      # at a local git tmpdir (the house pattern), keeping fetch off the
      # network.
      def repo_url
        manifest.upstream_url
      end

      def document_refs(workdir)
        root = File.join(workdir, "DDB_EpiDoc_XML")
        paths = Dir.glob(File.join(root, "*", "*.xml")) + Dir.glob(File.join(root, "*", "*", "*.xml"))
        paths.filter_map do |path|
          header = peek_header(path)
          next unless header

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:ddbdp:#{header[:hybrid].tr(';', ':')}",
            path: File.expand_path(path),
            metadata: metadata_for(header, path)
          )
        end.sort_by(&:id)
      end

      # The DCLP walk (P104-3): DCLP/<TM-thousand>/<TM>.xml, one ref per
      # file that carries a numeric dclp idno, an edition language AND
      # transcription text — the 12,571 metadata-only stubs (self-closed
      # or text-less edition) are skipped here, never quarantined at
      # parse (see the file header's census).
      def dclp_document_refs(workdir)
        Dir.glob(File.join(workdir, "DCLP", "*", "*.xml")).filter_map do |path|
          header = peek_dclp_header(path)
          next unless header

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:dclp:#{header[:hybrid]}",
            path: File.expand_path(path),
            metadata: metadata_for(header, path)
          )
        end
      end

      def metadata_for(header, path)
        metadata = {
          "language" => header[:language],
          "title" => header[:title] || File.basename(path, ".xml")
        }
        metadata["hgv"] = header[:hgv] if header[:hgv]
        metadata["tm"] = header[:tm] if header[:tm]
        metadata
      end

      # Cheap Reader peek at a file's teiHeader (Proiel#peek_source pattern):
      # the interesting idnos, the titleStmt <title>, and — first thing past
      # the header — the edition div's xml:lang (mapped la→lat), stopping
      # right there. Returns nil — skip the file — when the ddb-hybrid idno
      # or the edition language is missing, or the XML is malformed. Never
      # reads past the edition div's start tag.
      def peek_header(path)
        idnos, title, language, = read_header(path)
        hybrid = idnos["ddb-hybrid"]
        return nil if hybrid.nil? || hybrid.empty? || language.nil?

        { hybrid: hybrid, title: title, language: language, hgv: idnos["HGV"], tm: idnos["TM"] }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      # The DCLP peek: same header walk keyed on the numeric dclp idno,
      # plus the text requirement — the Reader continues INTO the edition
      # div just far enough to see one non-whitespace text node (most
      # stubs self-close the div, so the walk usually ends where the
      # DDbDP peek ends). nil — skip — when identity, language or text is
      # missing (a non-numeric idno, upstream's one "hgvTEMP" placeholder,
      # counts as missing identity).
      def peek_dclp_header(path)
        idnos, title, language, has_text =
          read_header(path, idno_types: DCLP_IDNO_TYPES, require_edition_text: true)
        id = idnos["dclp"]
        return nil unless id&.match?(/\A\d+\z/) && language && has_text

        { hybrid: id, title: title, language: language, hgv: idnos["HGV"], tm: idnos["TM"] }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      def read_header(path, idno_types: IDNO_TYPES, require_edition_text: false)
        state = { idnos: {}, title: nil, language: nil, has_text: false,
                  capture: nil, edition_depth: nil }
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            break unless continue_header_walk?(node, state, idno_types, require_edition_text)
          end
        end
        [state[:idnos], state[:title], state[:language], state[:has_text]]
      end

      # One Reader step of the header walk; false stops the scan. Before
      # the edition div: capture idnos/title. At the edition div: record
      # the language and stop — unless edition text is required and the
      # div has a body, in which case the walk continues inside it until
      # the first non-whitespace text node (or the div's end).
      def continue_header_walk?(node, state, idno_types, require_edition_text)
        case node.node_type
        when Nokogiri::XML::Reader::TYPE_ELEMENT
          return continue_after_element?(node, state, idno_types, require_edition_text)
        when Nokogiri::XML::Reader::TYPE_END_ELEMENT
          return false if state[:edition_depth] && node.depth == state[:edition_depth]

          state[:capture] = nil
        when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
          return continue_after_text?(node, state)
        end
        true
      end

      def continue_after_element?(node, state, idno_types, require_edition_text)
        return true if state[:edition_depth] # inside the edition: text is all we seek

        case node.name.split(":").last
        when "idno"
          state[:capture] = idno_types.find { |type| type == node.attribute("type") }
        when "title"
          state[:capture] = :title if state[:title].nil?
        when "div"
          if node.attribute("type") == "edition"
            state[:language] = DdbdpParser.normalize_language(node.attribute("xml:lang"))
            return false unless require_edition_text && !node.empty_element?

            state[:edition_depth] = node.depth
          end
        end
        true
      end

      def continue_after_text?(node, state)
        value = node.value.to_s.strip
        if state[:edition_depth]
          state[:has_text] = true unless value.empty?
          return !state[:has_text] # first real text inside the edition: done
        end
        state[:title] = value if state[:capture] == :title
        state[:idnos][state[:capture]] = value if state[:capture].is_a?(String)
        state[:capture] = nil
        true
      end
    end
  end
end
