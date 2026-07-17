# frozen_string_literal: true

require_relative "ogham_epidoc_parser"

module Nabu
  module Adapters
    # The OG(H)AM adapter (P25-1; Celtic survey pick #5): "Ogham in 3D
    # v2.0" (DIAS / Maynooth, ogham.celt.dias.ie) — ~500 EpiDoc records of
    # ogham stones (Primitive Irish pgl in REAL Ogham codepoints, plus
    # Pictish xpi, Latin-alphabet companion inscriptions, one runic stone),
    # from the ordinary git repo lguariento/og-h-am. A thin composition of
    # the OghamEpidocParser layer machinery with GitFetch.
    #
    # == License — the CONFLICT, both readings verbatim (class nc PENDING)
    #
    # - The site about-page: "the XML files… are freely accessible and
    #   downloadable under a CC-BY-NC-SA License…"
    # - EVERY sampled record's <availability>: <licence target=
    #   …/licenses/by/4.0/>"Creative Commons Attribution 4.0 International
    #   License"</licence>.
    # - The repo has NO LICENSE file.
    # Elsewhere the in-file header governs (Freising, RIIG), but here the
    # two grants CONTRADICT rather than layer, and the restrictive reading
    # is the safe one until upstream answers: license_class "nc" (GRETIL/MW
    # posture — MCP default-excluded, never redistributed) PENDING the
    # clarification email already drafted (unlock registry #14). On reply:
    # relabel via the license_class field (the P10-4 override mechanics
    # need not even fire — a source-level relabel + resync of nothing; no
    # urns change).
    #
    # == Layers (see OghamEpidocParser)
    #
    # discover yields one ref per (record × CITABLE edition layer): the
    # ogham layer under the bare urn, transliteration/roman/runic/english
    # as -suffix siblings; the FIRST citable layer of each record carries
    # the stone-grain metadata (ref metadata "primary"). Which layers are
    # citable is decided by the parser's OWN extraction
    # (OghamEpidocParser#layer_census — P25-3: the earlier raw-byte peek
    # only recognized SELF-CLOSED divs as empty and saw straight into XML
    # comments, minting 209 refs the parser could never fill): a declared
    # layer with no citable text is an honest absence — skipped by rule and
    # counted (discovery_skips), never a ref, never a quarantine — while a
    # structurally BROKEN layer (lb without @n, unresolvable glyph) still
    # mints and quarantines honestly. An edition div with an unknown
    # @subtype is unrecognized (loud). A stone with NO citable layer at all
    # (never-encoded; ~38 upstream) mints ONE metadata-only bare-urn
    # document (ref metadata "kind" => "metadata_only" — the local-library
    # text_layer:none precedent): catalogued, zero passages, never
    # quarantined.
    #
    # == Reference edges
    #
    # The commentary's word-level eDIL links ride as metadata "related"
    # (https://dil.ie/<id> — eDIL's own stable citation space) and become
    # kind=reference edges after each sync (reference_edges? +
    # reference_producer "ogham") — the same dil.ie bridge the corph packet
    # builds, coordinated through the links journal's producer field, no
    # code coupling.
    #
    # == fetch / sync policy
    #
    # One git repo through the shared non-destructive GitFetch choreography
    # (#git_fetch!). The live project still updates (v2.0 2025; commits
    # into 2026) → sync_policy manual, not frozen: re-syncs are owner-fired.
    class Ogham < Nabu::Adapter
      REPO_URL = "https://github.com/lguariento/og-h-am"

      XML_DIRNAME = "XML"
      CHARDECL_FILENAME = "charDecl.xml"

      MANIFEST = Nabu::SourceManifest.new(
        id: "ogham",
        name: "OG(H)AM — Ogham in 3D v2.0 (DIAS / Maynooth)",
        license: "UNRESOLVED CONFLICT, restrictive reading held (clarification email drafted, unlock " \
                 "registry #14): site about-page \"the XML files… are freely accessible and downloadable " \
                 "under a CC-BY-NC-SA License\" vs EVERY sampled record's <licence> \"Creative Commons " \
                 "Attribution 4.0 International License\" (target …/by/4.0/); repo has no LICENSE file — " \
                 "class nc until upstream answers, relabel-on-reply",
        license_class: "nc",
        upstream_url: REPO_URL,
        parser_family: "ogham-epidoc"
      )

      def self.manifest
        MANIFEST
      end

      # The dil.ie reference edges (class note).
      def self.reference_edges? = true

      def self.reference_producer(catalog:, journal:)
        LibraryReferences.new(catalog: catalog, journal: journal, producer: "ogham")
      end

      # One DocumentRef per (record × non-empty edition layer), sorted by
      # urn. A workdir without XML/ yields nothing (pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The discovery census (P11-7, P25-3): declared-but-empty edition
      # layers skip by rule (the parser's own extraction decides — class
      # note); an edition div with an unknown @subtype is unrecognized —
      # loud, a vocabulary drift, never a norm. An unreadable record counts
      # nowhere here: its metadata-only ref carries the honest quarantine.
      def discovery_skips(workdir)
        skipped = 0
        notes = []
        glyphs = census_glyphs(workdir)
        record_paths(workdir).each do |path|
          census = layer_census(path, glyphs) or next
          skipped += census.empty.size
          census.unknown.each do |subtype|
            notes << "#{File.basename(path)}: unknown edition subtype #{subtype.inspect}"
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      def parse(document_ref)
        return OghamEpidocParser.new.parse_metadata_only(document_ref.path, urn: document_ref.id) if
          document_ref.metadata["kind"] == "metadata_only"

        glyphs = OghamEpidocParser.glyph_map(document_ref.metadata["chardecl"])
        OghamEpidocParser.new.parse(
          document_ref.path,
          urn: document_ref.id,
          layer: document_ref.metadata.fetch("layer"),
          glyphs: glyphs,
          primary: document_ref.metadata["primary"] == true
        )
      end

      # One git repo, the shared non-destructive choreography (fetch →
      # breaker → attic → ff-merge).
      def fetch(workdir, progress: nil, force: false)
        git_fetch!(repo_url: REPO_URL, workdir: workdir, progress: progress, force: force)
      end

      private

      def record_paths(workdir)
        Dir.glob(File.join(workdir, XML_DIRNAME, "*", "*.xml"))
      end

      def chardecl_path(workdir)
        File.join(workdir, XML_DIRNAME, CHARDECL_FILENAME)
      end

      def document_refs(workdir)
        chardecl = chardecl_path(workdir)
        glyphs = census_glyphs(workdir)
        record_paths(workdir).flat_map do |path|
          record_refs(File.expand_path(path), chardecl, glyphs)
        end.sort_by(&:id)
      end

      # The record's citable layers in first-appearance order (the parser's
      # own census — class note); the first carries the stone-grain
      # metadata. No citable layer at all (or an unreadable record) → the
      # single metadata-only stone ref.
      def record_refs(path, chardecl, glyphs)
        base = "#{OghamEpidocParser::URN_PREFIX}#{File.basename(path, '.xml').downcase}"
        census = layer_census(path, glyphs)
        if census.nil? || census.citable.empty?
          return [Nabu::DocumentRef.new(source_id: manifest.id, id: base, path: path,
                                        metadata: { "kind" => "metadata_only" })]
        end

        census.citable.each_with_index.map do |layer, index|
          suffix = OghamEpidocParser::LAYER_SUFFIXES.fetch(layer)
          metadata = { "layer" => layer, "chardecl" => chardecl }
          metadata["primary"] = true if index.zero?
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: suffix ? "#{base}-#{suffix}" : base,
            path: path, metadata: metadata
          )
        end
      end

      # nil = unreadable record (malformed XML): discovery mints the
      # metadata-only ref, whose parse re-raises the real error as the
      # honest quarantine.
      def layer_census(path, glyphs)
        OghamEpidocParser.new.layer_census(path, glyphs: glyphs)
      rescue ParseError
        nil
      end

      # The census resolves glyphs with the same charDecl table parse uses;
      # a missing/broken charDecl degrades to {} so extraction raises and
      # the affected layers stay citable — quarantined at parse with the
      # real message, never silently dropped at discovery.
      def census_glyphs(workdir)
        OghamEpidocParser.glyph_map(chardecl_path(workdir))
      rescue ParseError
        {}
      end
    end
  end
end
