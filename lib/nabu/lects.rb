# frozen_string_literal: true

require "yaml"

module Nabu
  # The nabu-lects consume seam (P57-3): a pure READ resolver over the
  # nabu-lects module (github.com/arvicco/nabu-lects) — a small, curated
  # registry of LECTS (language varieties identified by genealogical anchor x
  # historical stage x variety x orthography) with a universal mapping from
  # standard codes (ISO 639, Wiktionary) onto them. There is NO catalog table
  # and NO migration: nabu-lects is a feature module (kind: module) in the
  # cldf-spine/nabu-data posture — absent canonical tree = lane off,
  # byte-identical behavior (#load_default -> nil, never raises).
  #
  # == The identifier grammar (nabu-lects README/docs/schema.md, verbatim)
  #
  #   lect-id = anchor [ ":" stage ] [ "/" variety ] [ "~" script ] [ "@" ortho ]
  #
  # anchor is the most specific genealogical node (an ISO 639 or established
  # Wiktionary code, e.g. "lat", "roa-opt"); stage a broad historical
  # development stage ("lat:med"); variety a register/sociolect/recension
  # ("zho/lit"); script the writing system of the text AS HELD ("san~latn" —
  # the canonical surface, P60-0/D60-b: never the artifact's original
  # script, which is a separate catalog-side field), resolved against the
  # registry's GLOBAL scripts table; ortho a spelling reform within one
  # script ("jpn:mod@kyu"). A bare anchor is a legal lect (honest
  # coarseness). Reconstruction is keyed on the registry field
  # `mode: reconstructed`, never on tag spelling (the stage tag "pro" is a
  # convention, not the machine truth).
  #
  # == Two files, two natures
  #
  # lects.yml's `anchors:` map is the registry itself: per-anchor
  # {name, kind, glottocode, band/band_note, parent, note, stages:,
  # varieties:, orthos:} — each stage/variety/ortho its own {name, ...}
  # sub-record. codemap.yml's `map:` lists ONLY non-identity code -> lect-id
  # defaults; any code absent from it resolves to itself as a bare anchor
  # (the identity default rule) — a fact stated once, true for any consumer.
  #
  # == Three-tier resolution precedence (#resolve)
  #
  # Nabu-specific knowledge does NOT belong in the universal codemap (a
  # collection's own reading of a code is not a universal fact), so it layers
  # ABOVE it in two seams, highest first:
  #
  #   1. per-document overlay  — the +overlay+ this instance is constructed
  #      with (a urn -> {code -> lect-id} hash; empty by default). The
  #      journal-backed persistence for this is a LATER packet (P57-4+) —
  #      this is the seam only.
  #   2. per-source override   — config/lect_overrides.yml (Nabu-authored;
  #      Nabu::Config#lect_overrides_path), keyed by source slug. Seeded
  #      P57-3 with exactly two ratified overrides (derom la-vul -> roa:pro,
  #      rundata gmq-pro -> gmq:run — see that file's comments).
  #   3. codemap.yml            — the module's universal defaults.
  #   4. identity               — the code itself, unchanged.
  #
  # == The parent walk (#parent_of)
  #
  # `parent:` is a DESCENT edge ("this lineage continues from that one"),
  # kept strictly apart from stage succession (carried by each stage's `ord`,
  # never by parent links). Walk rule (nabu-lects docs/schema.md, verbatim):
  # a staged lect inherits its ANCHOR's parent unless the registry declares
  # one on the lect itself (reserved for a future per-stage `parent:`, not
  # present in the v1 data — the anchor-level edge is what exists today).
  class Lects
    # One resolved lect. +mode+ is :reconstructed iff the referenced stage
    # carries `mode: reconstructed` upstream (a bare anchor, having no
    # stage, is always :attested — reconstruction is always a property of a
    # stage). +ord+/+band+ come from the stage when one is referenced, else
    # from the anchor (only bare anchors without stages carry their own
    # band in practice — see lects.yml's "non"/"ang"/"fro" rows). +script+
    # (P60-0) is the held text's surface script tag, resolved against the
    # global scripts table. +band_note+ (P76 U-7): the registry's
    # convention note on the band ("…approximate", "conventional
    # philological bands") — the "ca." carrier (conventions §12), verbatim.
    Record = Data.define(:id, :anchor, :stage, :variety, :script, :ortho, :name, :mode, :ord, :band,
                         :band_note) do
      def initialize(band_note: nil, **) = super
    end

    # One resolved code→lect mapping WITH its provenance (P81 U-5): +id+ is
    # the string #resolve returns; +basis+ names the precedence tier that
    # won — the journal row's own basis ("owner", "rule:<id>") when the
    # overlay can report one (Store::LectJournal::Overlay#basis), the
    # generic "overlay" for a plain-hash overlay, "override:<slug>" for a
    # per-source override, "codemap" for the universal default, nil for
    # identity (the code itself — no claim, no provenance to speak).
    Resolution = Data.define(:id, :basis)

    LECTS_FILE = "lects.yml"
    CODEMAP_FILE = "codemap.yml"
    SLUG = "nabu-lects"

    # anchor: 2-3 lowercase letters, optionally hyphen-extended (roa-opt,
    # ine-bsl). stage/variety: 2-5 lowercase alphanumerics starting with a
    # letter (digits admitted P58-5 for the field's own periodization names —
    # sux:ur3 is Ur III; pure-letter tags stay the norm). script: exactly 4
    # lowercase letters — a lowercased ISO 15924 code (P60-0). ortho: 2-8
    # lowercase alphanumerics starting with a letter. Axes strictly ordered
    # (":" before "/" before "~" before "@") per nabu-lects docs/schema.md.
    ID_PATTERN = %r{\A(?<anchor>[a-z]{2,3}(?:-[a-z]{2,5})?)
                     (?::(?<stage>[a-z][a-z0-9]{1,4}))?
                     (?:/(?<variety>[a-z][a-z0-9]{1,4}))?
                     (?:~(?<script>[a-z]{4}))?
                     (?:@(?<ortho>[a-z][a-z0-9]{1,7}))?\z}x

    # Grammar-only parse (no registry lookup): the anchor/stage/variety/ortho
    # capture groups, or nil for a string that does not match the identifier
    # grammar at all.
    def self.parse_id(id)
      ID_PATTERN.match(id.to_s)
    end

    # Build a resolver from a canonical/nabu-lects-shaped directory (lects.yml
    # + codemap.yml). +overrides_path+ points at the Nabu-authored per-source
    # override file (nil -> no overrides, the bare-module posture); +overlay+
    # is the per-document seam (P57-3: constructor-only, no storage yet).
    def self.load(dir, overrides_path: nil, overlay: {})
      registry = read_yaml(File.join(dir, LECTS_FILE))
      # +overrides_path+: one file or an overlay pair (P71-0) — per-source
      # maps merge in path order, a local/config/ row winning its slug.
      overrides = Array(overrides_path).each_with_object({}) do |path, merged|
        merged.merge!(read_yaml(path).fetch("sources", nil) || {})
      end
      new(
        anchors: registry.fetch("anchors", {}),
        scripts: registry.fetch("scripts", {}),
        codemap: read_yaml(File.join(dir, CODEMAP_FILE)).fetch("map", {}),
        overrides: overrides,
        overlay: overlay
      )
    end

    # Feature-detect the resolver from the owner's canonical tree: nil when
    # `nabu sync nabu-lects` has not landed both files, so a corpus without
    # the module behaves byte-identically (the cldf-spine/nabu-data posture).
    # NEVER raises on absence.
    #
    # +overlay+ :auto (the default) feature-detects the lect-assignment
    # journal (db/lects.sqlite3, P58-1) the same way: absent file -> empty
    # overlay, byte-identical P57-3 behavior; present -> the journal's lazy
    # Overlay (point lookups, not an eager hash). An explicit overlay:
    # argument — a test's fixture hash, a caller's own seam — always wins.
    def self.load_default(config: Nabu::Config.load, overlay: :auto)
      dir = File.join(config.canonical_dir, SLUG)
      return nil unless File.file?(File.join(dir, LECTS_FILE)) && File.file?(File.join(dir, CODEMAP_FILE))

      overlay = journal_overlay(config) if overlay == :auto
      load(dir, overrides_path: config.lect_overrides_paths, overlay: overlay)
    end

    # The journal read side, absence-safe. The require is lazy so the
    # registry resolver itself stays loadable without the store stack.
    def self.journal_overlay(config)
      require_relative "store/lect_journal"
      db = Store::LectJournal.open_readonly(config.lects_journal_path)
      db ? Store::LectJournal::Overlay.new(db) : {}
    end
    private_class_method :journal_overlay

    def self.read_yaml(path)
      File.file?(path) ? (YAML.safe_load_file(path) || {}) : {}
    end
    private_class_method :read_yaml

    # An override row is either the bare lect-id string (the P57-3 shape) or
    # a {lect:, tier:} hash (P81 U-5 — the D57-f tier comments promoted to
    # machine fields). Split one raw sources map into the id map #resolve
    # walks and the tier map the render side glosses from.
    def self.split_override_rows(sources_map)
      ids = {}
      tiers = {}
      sources_map.each do |slug, rows|
        ids[slug] = {}
        (rows || {}).each do |code, entry|
          if entry.is_a?(Hash)
            ids[slug][code] = entry.fetch("lect")
            (tiers[slug] ||= {})[code] = entry["tier"] if entry["tier"]
          else
            ids[slug][code] = entry
          end
        end
      end
      [ids, tiers]
    end

    # {slug => {code => tier word}} straight from the overrides file(s) —
    # the render-side lookup (Nabu::LectGloss) reads the config directly, so
    # an unsynced registry module never hides a config-stated tier.
    def self.override_tiers(paths)
      merged = Array(paths).each_with_object({}) do |path, acc|
        acc.merge!(read_yaml(path).fetch("sources", nil) || {})
      end
      split_override_rows(merged).last
    end

    def initialize(anchors:, codemap:, overrides: {}, overlay: {}, scripts: {})
      @anchors = anchors
      @scripts = scripts
      @codemap = codemap
      @overrides, @override_tiers = self.class.split_override_rows(overrides)
      @overlay = overlay
    end

    # +id+ -> a Record, or nil when +id+ does not match the identifier
    # grammar, OR references an anchor/stage/variety/ortho tag not defined in
    # the registry (an undefined tag is never silently coerced).
    def lect(id)
      match = self.class.parse_id(id) or return nil
      anchor = @anchors[match[:anchor]] or return nil

      stage = match[:stage] && (anchor.dig("stages", match[:stage]) or return nil)
      variety = match[:variety] && (anchor.dig("varieties", match[:variety]) or return nil)
      script = match[:script] && (@scripts[match[:script]] or return nil)
      ortho = match[:ortho] && (anchor.dig("orthos", match[:ortho]) or return nil)

      Record.new(
        id: id.to_s, anchor: match[:anchor], stage: match[:stage], variety: match[:variety],
        script: match[:script], ortho: match[:ortho],
        name: compose_name(anchor, stage, variety, script, ortho),
        mode: stage && stage["mode"] == "reconstructed" ? :reconstructed : :attested,
        ord: stage && stage["ord"], band: stage ? stage["band"] : anchor["band"],
        band_note: stage ? stage["band_note"] : anchor["band_note"]
      )
    end

    # true iff +id+ parses and its stage carries `mode: reconstructed`.
    # false for a bare anchor, an attested stage, or an unparseable/undefined
    # id (never raises).
    def reconstructed?(id)
      lect(id)&.mode == :reconstructed
    end

    # +code+ -> lect id STRING, by precedence (class doc): per-document
    # overlay (+urn+) > per-source override (+source+) > codemap > identity.
    # Always returns a string — a code with no mapping anywhere resolves to
    # itself (the identity default rule).
    def resolve(code, source: nil, urn: nil)
      resolution(code, source: source, urn: urn).id
    end

    # The with-basis variant (P81 U-5): the same precedence walk, returning
    # a Resolution so the facet materializer can record WHERE the id came
    # from (class Resolution note). #resolve delegates here — one walk,
    # never two answers.
    def resolution(code, source: nil, urn: nil)
      code = code.to_s

      per_document = urn && @overlay[urn]
      if per_document&.key?(code)
        basis = (@overlay.basis(urn, code) if @overlay.respond_to?(:basis))
        return Resolution.new(id: per_document[code], basis: basis || "overlay")
      end

      per_source = source && @overrides[source.to_s]
      return Resolution.new(id: per_source[code], basis: "override:#{source}") if per_source&.key?(code)
      return Resolution.new(id: @codemap[code], basis: "codemap") if @codemap.key?(code)

      Resolution.new(id: code, basis: nil)
    end

    # The config-stated tier word ("certain"/"approximation") for a
    # per-source override row (P81 U-5), nil when the row — or its tier —
    # is absent (an honest untiered override, never a guess).
    def override_tier(source, code)
      @override_tiers.dig(source.to_s, code.to_s)
    end

    # The descent edge for +id+ (class doc, "the parent walk"): a staged
    # lect inherits its anchor's `parent:` unless the registry declares one
    # on the lect itself (reserved for a future per-stage override). Returns
    # a lect id, or nil at a root (no parent edge) or for an unparseable/
    # undefined +id+.
    def parent_of(id)
      match = self.class.parse_id(id) or return nil
      anchor = @anchors[match[:anchor]] or return nil

      if match[:stage]
        stage = anchor.dig("stages", match[:stage]) or return nil
        return stage["parent"] if stage["parent"]
      end
      anchor["parent"]
    end

    # Every registered anchor code, registry order (P60 rider: the dossier
    # stage-section writer enumerates the registry; no other caller should
    # need the raw anchor map).
    def anchor_codes
      @anchors.keys
    end

    # True iff +tag+ is in the registry's GLOBAL scripts table (P61-3: the
    # artifact-script config validates against the same vocabulary the ~
    # axis resolves against — one table, two consumers).
    def script?(tag)
      @scripts.key?(tag.to_s)
    end

    # Every stage of +anchor+ as a Record (id "<anchor>:<tag>"), ord-sorted
    # (chronological display order — the future card-ladder seam). [] for an
    # undefined anchor or one with no stages.
    def stages_of(anchor)
      entry = @anchors[anchor.to_s] or return []
      stage_tags = entry["stages"] || {}
      stage_tags.keys.filter_map { |tag| lect("#{anchor}:#{tag}") }.sort_by { |record| record.ord || 0 }
    end

    # Every registered variety of +anchor+ as a Record (id
    # "<anchor>/<tag>"), in registry order (P58: the card ladder lists
    # registers beside stages — zho/lit is wenyan, not "unstaged"). [] for
    # an undefined anchor or one with no varieties.
    def varieties_of(anchor)
      entry = @anchors[anchor.to_s] or return []
      (entry["varieties"] || {}).keys.filter_map { |tag| lect("#{anchor}/#{tag}") }
    end

    private

    # The human name: the stage's (already a full title, "Medieval Latin")
    # or else the anchor's; a variety appends its own full title; a script
    # reads as the held surface ("… in Latin script"); an ortho wraps as a
    # parenthetical modifier.
    def compose_name(anchor, stage, variety, script, ortho)
      base = stage ? stage.fetch("name") : anchor.fetch("name")
      base = "#{base} — #{variety.fetch('name')}" if variety
      base = "#{base} in #{script.fetch('name')} script" if script
      ortho ? "#{base} (#{ortho.fetch('name')})" : base
    end
  end
end
