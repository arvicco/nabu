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
    # == Layout and discovery (the post-switchover layout)
    #
    # Upstream's SVN-to-git switchover (2026-07, completed upstream by
    # 2026-10) rationalized idp.data: the edition-centric
    # DDB_EpiDoc_XML/<collection>/(<collection>.<volume>/)?<file>.xml tree
    # is GONE, replaced by two documentary trees (HGV_trans_EpiDoc/ likewise
    # became Translations/, read — with the APIS records' translations —
    # by the translation walk, see "The translation siblings" below):
    #
    # - DDbDP/<HGV-thousand>/<HGV>.xml — the CURATED, text-centric tree,
    #   one file per HGV text, named by its <idno type="filename"> (the HGV
    #   number: 8875.xml, 13a.xml). Every live edit lands here. 67,980 files
    #   at upstream 8f7ed708 (2026-10-13), of which 61,801 carry text; the
    #   other 6,179 are stubs generated from HGV ("This text has not been
    #   added to papyri.info yet." over an empty <ab/>).
    # - Historical/<collection>/(<volume>/)?<number>.xml — the archived
    #   edition-centric tree (the old layout's successor): 82,332 files,
    #   52,637 with text; the rest are "historical edition has not been
    #   added" stubs pointing at the curated edition, plus 6,458 DCLP
    #   catalog shells with no edition div at all.
    #
    # Discover walks DDbDP/ (any depth) first, then Historical/ (any depth;
    # a handful of entries nest one or two levels below the volume) as a
    # FALLBACK: a Historical file becomes a ref only when no text-bearing
    # DDbDP/ file claims its urn. Measured at 8f7ed708: 103 editions have
    # their text only in Historical/ (c.epist.lat;;10 is one — DDbDP/78/
    # 78573.xml is merely its stub); every other text-bearing Historical
    # file duplicates a curated text and yields to it. Dual-tree discovery
    # retains 61,346 of the 61,453 text-bearing pre-switchover documents
    # (DDbDP/ alone would retain 61,246); the 107 that go are upstream's
    # own retirements (69 now only stubs — superseded editions such as
    # bgu;4;1087, whose text DDbDP/ carries as bgu;13;2280 — 36 re-keyed
    # under another hybrid, 2 left only as translations). The old
    # DDB_EpiDoc_XML/ root is NOT tolerated as a third root: upstream
    # deleted it, and a canonical clone that still has it is pre-switchover
    # and needs the sync, not a compatibility walk.
    #
    # Each header is peeked; files without an <idno type="ddb-hybrid"> or an
    # edition language are skipped defensively (the repo carries the odd
    # non-DDbDP artifact that must not error discover), and so are TEXT-LESS
    # STUBS — editions without a single <lb> (the parser's citable unit). In
    # the old layout a stub had its own hybrid and merely quarantined at
    # parse; in this layout a stub can share its hybrid with the real text
    # (a multi-text edition: DDbDP/0/13.xml carries p.adl;;G13 with text,
    # its per-HGV siblings 13a.xml/13b.xml carry the same hybrid as stubs;
    # or a curated stub over a Historical text), so skipping is what keeps
    # the urn unique. Over the text-bearing files the ddb-hybrid IS unique
    # in each tree (61,801 of 61,801; 52,637 of 52,637).
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
    # Identity never reads the path — and the switchover proved why that
    # matters: every documentary file moved (and was rewritten; no blob
    # survived byte-identical), yet all 61,246 documents present text-bearing
    # in both the old tree and DDbDP/ mint the SAME document urn from either
    # file (corpus-wide parse comparison at 8f7ed708; 59,514 re-parse
    # byte-identically down to every passage). The new <idno
    # type="filename"> (an HGV number in DDbDP/, a collection/volume/number
    # path in Historical/) is path-shaped and is deliberately NOT used.
    #
    # PASSAGE urns did not all survive, and not because of paths: upstream's
    # 2026-10-04 schema pass rewrote textpart @n values without punctuation
    # ("r,1" → "r1", "int,1" → "int1", "with-fibers" → "withfibers", even
    # "1-2" → "12"), keeping the old label as a <head> inside the textpart.
    # 1,666 DDbDP and 85 DCLP documents carry such textparts; their passages
    # re-mint under the new suffixes (texts unchanged), and 20 documents
    # whose @n was all punctuation now lack @n and quarantine. This adapter
    # mints from @n as upstream publishes it (canonical means canonical).
    #
    # == The DCLP lane (P104-3)
    #
    # The same idp.data clone carries DCLP/ — the Digital Corpus of
    # Literary Papyri, 14,845 EpiDoc files under DCLP/<bucket>/<dclp>.xml
    # — parsed since P104-3 as a SECOND document family of THIS source.
    # The switchover kept the DCLP/ root but re-sharded it: the bucket was
    # <n>/1000 + 1 (DCLP/63/62952.xml) and is now <n>/1000
    # (DCLP/62/62952.xml). Three ids (62441, 62509, 65542) ALSO survive at
    # their old-bucket path as diverged duplicates — the old-bucket copies
    # carry editorial changes committed after the reshard, which suggests
    # an upstream editing path still writing the old location. One urn
    # needs one file, so discover keeps the <n>/1000 bucket copy (a
    # deterministic layout rule, not a judgment on content); the conflict
    # is upstream's to resolve.
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
    # across all 14,842 ids, census 2026-09-26, re-verified at 8f7ed708
    # modulo the three stale-bucket duplicates above). NOT the dclp-hybrid:
    # the hybrid is demonstrably non-unique (two Homer papyri, TM 60467
    # and TM 61136, both carry <idno type="dclp-hybrid">p.hal;;5 — an
    # upstream cataloguing defect that would collide urns). Non-numeric
    # dclp idnos (one "hgvTEMP" placeholder upstream) skip defensively —
    # a temp id is not a stable identity. The namespace is distinct, so
    # dclp urns are structurally non-colliding with urn:nabu:ddbdp:* even
    # where one papyrus is held by both corpora.
    #
    # Discovery reality (census 2026-09-26 on the live clone; 12,567 of
    # 14,845 at 8f7ed708): 12,571 of 14,842 files are metadata-only
    # catalog stubs — a SELF-CLOSED edition
    # div, no transcription — and a further handful scaffold an empty
    # <ab>/<lb> skeleton with no text. The DCLP peek therefore requires,
    # beyond dclp-hybrid + edition language, at least one non-whitespace
    # text node INSIDE the edition div (still a bounded header-and-edition
    # Reader walk that stops at the first hit); text-less files are
    # skipped at discover, not quarantined at parse. Expected live yield:
    # ~2,260 literary documents (grc ~2,19x, lat ~6x, cop ~1x); measured
    # at 8f7ed708: 2,256 refs (grc 2,181 · lat 57 · cop 17 · egy-Egyd 1).
    #
    # == The translation siblings (translations: true)
    #
    # Shape decision: SIBLING documents, not passage annotations. The
    # translations are whole-document prose (one <ab> for the APIS block
    # translations), several per edition (303 editions carry 2–15 in one
    # language), and only the HGV ones mark the edition's line numbers —
    # inline milestones, not one translation per line. A sibling document
    # keeps every translation whole and attributable (its own
    # bibliography/authority), and its passages cite the edition's own
    # line labels where the translator marked them, so `--parallel`
    # anchors them like any span-grouped translation. Identity
    # <edition urn>-trans-<translation id>; walk, resolution and census in
    # PapyriTranslations, parsing in PapyriTranslationParser.
    #
    # == Header mining (PapyriHeader)
    #
    # Parse also reads what idp.data asserts ABOUT each document: a DCLP
    # file's own origDate/origPlace/provenance/keywords, and — for any
    # edition carrying an HGV idno — the HGV record's later-keyword
    # sender→addressee parties, archive membership and mentioned dates
    # (HGV_meta_EpiDoc/, the same clone; the HGV origin date/place/type
    # stay the build-time timeline and kind walks'). Field shapes and the
    # census behind each rule live in PapyriHeader's header.
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

      # The documentary walk roots (see "Layout and discovery" above): the
      # curated tree first, the historical tree as fallback.
      DDBDP_ROOT = "DDbDP"
      HISTORICAL_ROOT = "Historical"
      DCLP_ROOT = "DCLP"
      private_constant :DDBDP_ROOT, :HISTORICAL_ROOT, :DCLP_ROOT

      # Walk <workdir>/DDbDP (curated) with <workdir>/Historical as the
      # fallback for editions the curated tree does not carry as text, plus
      # <workdir>/DCLP (P104-3), one DocumentRef per urn, the whole union
      # sorted by urn (dclp:* precedes ddbdp:* — discovery order is urn
      # order). Returns an Enumerator without a block (the adapter
      # contract's lazy shape).
      #
      # With `translations: true` (the registry posture) the walk also
      # yields one translation ref per translation file of the clone —
      # Translations/ and the APIS records — resolved onto the edition it
      # translates (PapyriTranslations has the census and the rules).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        bases = document_refs(workdir) + dclp_document_refs(workdir)
        refs = @translations ? bases + translation_walk(workdir, bases).refs : bases
        refs.sort_by(&:id).each(&block)
      end

      # +translations+: when true (the registry row's posture), discover
      # also yields the translation siblings. Default off — the frozen
      # edition walk alone.
      def initialize(translations: false)
        super()
        @translations = translations
      end

      # The translation walk's skip census (misnamed files, APIS duplicates,
      # translations naming no edition); nothing when translations are off.
      def discovery_skips(workdir)
        return super unless @translations

        skips = translation_walk(workdir, document_refs(workdir) + dclp_document_refs(workdir)).skips
        notes = skips.group_by(&:reason).map do |reason, group|
          named = group.first(5).map(&:name).join(", ")
          "#{group.size} translation file#{'s' if group.size > 1} skipped — #{reason} (#{named}" \
            "#{', …' if group.size > 5})"
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skips.size, notes: notes)
      end

      # Delegate to the DdbdpParser with the urn/language/title discover
      # resolved from the header; DCLP refs (by urn namespace) parse under
      # the dclp identity, everything else stays the frozen DDbDP default.
      # Translation refs parse through PapyriTranslationParser, gaining the
      # APIS record's descriptive header when one backs the translation.
      def parse(document_ref)
        return parse_translation(document_ref) if document_ref.metadata["kind"] == "translation"

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
          metadata: idno_metadata(document_ref.metadata).merge(header_metadata(document_ref))
        )
      end

      # The header mining (PapyriHeader — the aggressive-mining law): a DCLP
      # file's own origDate/origPlace/keywords, and for any edition carrying
      # an HGV idno, its HGV record's keyword persons, archive membership
      # and mentioned dates. The HGV tree sits beside the walk roots in the
      # same clone; a ref whose path sits under no walk root (a caller-built
      # ref) mines only what its own file carries.
      def header_metadata(document_ref)
        metadata = document_ref.id.start_with?("urn:nabu:dclp:") ? PapyriHeader.dclp(document_ref.path) : {}
        workdir = workdir_of(document_ref.path)
        return metadata if workdir.nil?

        metadata.merge(PapyriHeader.hgv(PapyriHeader.hgv_paths(workdir, document_ref.metadata["hgv"])))
      end

      # P104-1 (the aggressive-mining law): the HGV/TM idnos, peeked at discover
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

      def translation_walk(workdir, bases)
        PapyriTranslations.new(workdir: workdir, bases: bases, source_id: manifest.id)
      end

      def parse_translation(document_ref)
        workdir = workdir_of(document_ref.path)
        apis = workdir ? PapyriTranslations.apis_metadata(workdir, document_ref.metadata["apisid"]) : {}
        PapyriTranslationParser.new.parse(document_ref.path, urn: document_ref.id,
                                                             metadata: apis.merge(document_ref.metadata))
      end

      # The upstream repo URL, split out so fetch tests can point a singleton
      # at a local git tmpdir (the house pattern), keeping fetch off the
      # network.
      def repo_url
        manifest.upstream_url
      end

      # The clone root a ref's file sits under: the parent of the LAST walk
      # root segment in its path (DDbDP/, Historical/, DCLP/, Translations/
      # or APIS/), or nil.
      WALK_ROOTS = [DDBDP_ROOT, HISTORICAL_ROOT, DCLP_ROOT,
                    PapyriTranslations::TRANSLATIONS_ROOT, PapyriTranslations::APIS_ROOT].freeze
      private_constant :WALK_ROOTS

      def workdir_of(path)
        parts = File.expand_path(path).split(File::SEPARATOR)
        index = parts[0...-1].rindex { |part| WALK_ROOTS.include?(part) }
        index&.positive? ? parts[0...index].join(File::SEPARATOR) : nil
      end

      # The documentary walk: every text-bearing file of the curated tree,
      # then each text-bearing Historical file whose urn the curated tree
      # did not already claim (see the file header's precedence rule).
      def document_refs(workdir)
        curated = ddbdp_tree_refs(File.join(workdir, DDBDP_ROOT))
        claimed = curated.to_h { |ref| [ref.id, true] }
        historical = ddbdp_tree_refs(File.join(workdir, HISTORICAL_ROOT)).reject { |ref| claimed[ref.id] }
        (curated + historical).sort_by(&:id)
      end

      # One tree's refs, any depth (DDbDP/<n>/<n>.xml; Historical nests
      # collection/volume/number, a few entries one or two levels deeper).
      # Dir.glob's sorted path order keeps the walk deterministic.
      def ddbdp_tree_refs(root)
        Dir.glob(File.join(root, "**", "*.xml")).filter_map do |path|
          header = peek_header(path)
          next unless header

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:ddbdp:#{header[:hybrid].tr(';', ':')}",
            path: File.expand_path(path),
            metadata: metadata_for(header, path)
          )
        end
      end

      # The DCLP walk (P104-3): DCLP/<dclp-thousand>/<dclp>.xml, one ref
      # per file that carries a numeric dclp idno, an edition language AND
      # transcription text — the ~12,570 metadata-only stubs (self-closed
      # or text-less edition) are skipped here, never quarantined at
      # parse (see the file header's census). A dclp id present in more
      # than one bucket keeps only its <n>/1000 bucket copy (the stale
      # pre-reshard duplicates; file header).
      def dclp_document_refs(workdir)
        refs = Dir.glob(File.join(workdir, DCLP_ROOT, "*", "*.xml")).filter_map do |path|
          header = peek_dclp_header(path)
          next unless header

          Nabu::DocumentRef.new(
            source_id: manifest.id,
            id: "urn:nabu:dclp:#{header[:hybrid]}",
            path: File.expand_path(path),
            metadata: metadata_for(header, path)
          )
        end
        refs.group_by(&:id).map { |_, group| group.min_by { |ref| [dclp_bucket_rank(ref), ref.path] } }
      end

      # 0 when the file sits in its canonical <n>/1000 bucket, 1 otherwise.
      def dclp_bucket_rank(ref)
        bucket = File.basename(File.dirname(ref.path))
        bucket == (Integer(ref.id.delete_prefix("urn:nabu:dclp:"), 10) / 1000).to_s ? 0 : 1
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
      # the header — the edition div's xml:lang (mapped la→lat), then INTO
      # the edition div just far enough to meet its first <lb> (the parser's
      # citable unit). Returns nil — skip the file — when the ddb-hybrid
      # idno, the edition language or any <lb> is missing, or the XML is
      # malformed. The <lb> requirement is what skips upstream's text-less
      # stubs (an empty <ab/>, at most a "not yet added" <note>): in the
      # post-switchover layout a stub can share its ddb-hybrid with the real
      # text (a multi-text edition's per-HGV siblings; a curated stub over a
      # Historical text), so it must not become a ref at all.
      def peek_header(path)
        idnos, title, language, has_lb = read_header(path, probe: :lb)
        hybrid = idnos["ddb-hybrid"]
        return nil if hybrid.nil? || hybrid.empty? || language.nil? || !has_lb

        { hybrid: hybrid, title: title, language: language, hgv: idnos["HGV"], tm: idnos["TM"] }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      # The DCLP peek: same header walk keyed on the numeric dclp idno,
      # plus the text requirement — the Reader continues INTO the edition
      # div just far enough to see one non-whitespace text node (most
      # stubs self-close the div, so the walk usually ends at the edition
      # start tag). nil — skip — when identity, language or text is
      # missing (a non-numeric idno, upstream's one "hgvTEMP" placeholder,
      # counts as missing identity).
      def peek_dclp_header(path)
        idnos, title, language, has_text = read_header(path, idno_types: DCLP_IDNO_TYPES, probe: :text)
        id = idnos["dclp"]
        return nil unless id&.match?(/\A\d+\z/) && language && has_text

        { hybrid: id, title: title, language: language, hgv: idnos["HGV"], tm: idnos["TM"] }
      rescue Nokogiri::XML::SyntaxError
        nil
      end

      # +probe+ names what the walk seeks inside the edition div: :lb (the
      # first <lb> element) or :text (the first non-whitespace text node).
      # The fourth return value says whether it was found.
      def read_header(path, probe:, idno_types: IDNO_TYPES)
        state = { idnos: {}, title: nil, language: nil, found: false,
                  capture: nil, edition_depth: nil, probe: probe }
        File.open(path, "r") do |io|
          Nokogiri::XML::Reader(io, path).each do |node|
            break unless continue_header_walk?(node, state, idno_types)
          end
        end
        [state[:idnos], state[:title], state[:language], state[:found]]
      end

      # One Reader step of the header walk; false stops the scan. Before
      # the edition div: capture idnos/title. At the edition div: record
      # the language; a self-closed div ends the walk (nothing to find),
      # otherwise the walk continues inside it until the probe is met (or
      # the div ends).
      def continue_header_walk?(node, state, idno_types)
        case node.node_type
        when Nokogiri::XML::Reader::TYPE_ELEMENT
          return continue_after_element?(node, state, idno_types)
        when Nokogiri::XML::Reader::TYPE_END_ELEMENT
          return false if state[:edition_depth] && node.depth == state[:edition_depth]

          state[:capture] = nil
        when Nokogiri::XML::Reader::TYPE_TEXT, Nokogiri::XML::Reader::TYPE_CDATA
          return continue_after_text?(node, state)
        end
        true
      end

      def continue_after_element?(node, state, idno_types)
        name = node.name.split(":").last
        if state[:edition_depth] # inside the edition: only the probe matters
          state[:found] = true if state[:probe] == :lb && name == "lb"
          return !state[:found]
        end

        case name
        when "idno"
          state[:capture] = idno_types.find { |type| type == node.attribute("type") }
        when "title"
          state[:capture] = :title if state[:title].nil?
        when "div"
          if node.attribute("type") == "edition"
            state[:language] = DdbdpParser.normalize_language(node.attribute("xml:lang"))
            return false if node.empty_element?

            state[:edition_depth] = node.depth
          end
        end
        true
      end

      def continue_after_text?(node, state)
        value = node.value.to_s.strip
        if state[:edition_depth]
          state[:found] = true if state[:probe] == :text && !value.empty?
          return !state[:found] # first real text inside the edition: done
        end
        state[:title] = value if state[:capture] == :title
        state[:idnos][state[:capture]] = value if state[:capture].is_a?(String)
        state[:capture] = nil
        true
      end
    end
  end
end
