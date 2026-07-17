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
    # discover yields one ref per (record × edition layer): the ogham layer
    # under the bare urn, transliteration/roman/runic/english as -suffix
    # siblings; the FIRST layer of each record carries the stone-grain
    # metadata (ref metadata "primary"). A SELF-CLOSED (empty) edition div
    # is a catalogued-but-unedited layer — skipped by rule and counted
    # (discovery_skips), never a quarantine; an edition div with an unknown
    # @subtype is unrecognized (loud).
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

      # Edition-div open tags in a record's raw bytes — the cheap discovery
      # peek (parse re-reads properly). A tag ending "/>" is a self-closed,
      # empty layer.
      EDITION_TAG = %r{<div\b[^>]*type="edition"[^>]*?(/?)>}
      SUBTYPE_ATTR = /subtype="([^"]*)"/

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
      def self.reference_producer = "ogham"

      # One DocumentRef per (record × non-empty edition layer), sorted by
      # urn. A workdir without XML/ yields nothing (pre-fetch state).
      def discover(workdir, &block)
        return enum_for(:discover, workdir) unless block

        document_refs(workdir).each(&block)
      end

      # The discovery census (P11-7): self-closed (empty) edition layers
      # skip by rule; an edition div with an unknown @subtype is
      # unrecognized — loud, a vocabulary drift, never a norm.
      def discovery_skips(workdir)
        skipped = 0
        notes = []
        record_paths(workdir).each do |path|
          scan_layers(path) do |subtype, empty|
            if !OghamEpidocParser::LAYER_SUFFIXES.key?(subtype)
              notes << "#{File.basename(path)}: unknown edition subtype #{subtype.inspect}"
            elsif empty
              skipped += 1
            end
          end
        end
        Nabu::Adapter::DiscoverySkips.new(skipped_by_rule: skipped, unrecognized: notes.size, notes: notes)
      end

      def parse(document_ref)
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
        record_paths(workdir).flat_map do |path|
          record_refs(File.expand_path(path), chardecl)
        end.sort_by(&:id)
      end

      # The record's non-empty layers in first-appearance order; the first
      # carries the stone-grain metadata (parser class note).
      def record_refs(path, chardecl)
        base = "#{OghamEpidocParser::URN_PREFIX}#{File.basename(path, '.xml').downcase}"
        layers(path).each_with_index.map do |layer, index|
          suffix = OghamEpidocParser::LAYER_SUFFIXES.fetch(layer)
          metadata = { "layer" => layer, "chardecl" => chardecl }
          metadata["primary"] = true if index.zero?
          Nabu::DocumentRef.new(
            source_id: manifest.id, id: suffix ? "#{base}-#{suffix}" : base,
            path: path, metadata: metadata
          )
        end
      end

      def layers(path)
        result = []
        scan_layers(path) do |subtype, empty|
          next if empty || !OghamEpidocParser::LAYER_SUFFIXES.key?(subtype)

          result << subtype unless result.include?(subtype)
        end
        result
      end

      # Yields [subtype, empty?] per edition-div open tag in the raw bytes.
      def scan_layers(path)
        File.read(path).scan(EDITION_TAG) do |(self_closed)|
          tag = Regexp.last_match(0)
          subtype = tag[SUBTYPE_ATTR, 1].to_s
          yield subtype, self_closed == "/"
        end
      end
    end
  end
end
