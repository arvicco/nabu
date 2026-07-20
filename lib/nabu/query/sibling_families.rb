# frozen_string_literal: true

require_relative "../config"
require_relative "../source_registry"

module Nabu
  module Query
    # The registry-declared work-pattern compiler behind `--parallel`
    # (P34-0). Query::Parallel's sibling resolution used to be a chain of
    # ten hand-frozen per-source regex constants; every new sibling shape
    # was an owner repro plus a code rider (P29, P30, P32). The seam is now
    # the source registry (owner-decided): a row's `siblings:` key declares
    # the variant-suffix grammar its adapter mints, and this compiler turns
    # the declarations into ONE generic matcher.
    #
    # == The design note: what each retired literal tail encoded
    #
    # Studying the ten constants before unifying, every one was the same
    # three invariants plus one per-source freeze:
    #
    # 1. The variant tail is TERMINAL and OPTIONAL — one pattern matches the
    #    bare work document and its variants alike, capturing the work stem.
    # 2. The stem is MINIMAL (non-greedy): the tail always strips when
    #    present, so a variant urn and its work agree on the stem.
    # 3. Candidates are the bare work + `work-%` (the urn:nabu families) or
    #    `work.%` with NO bare-work document (CTS — editions are dotted;
    #    the work urn itself is never a document).
    #
    # The per-source freeze was the tail GRAMMAR — a census claim about
    # upstream id shapes, which is exactly what the registry now declares:
    #
    # * CTS (P7-4): the dotted-version form — work = urn:cts:<ns>:<tg>.<w>,
    #   edition = one more dot-free, colon-free token (`.perseus-grc2`).
    #   Version ranking (numeric-then-letter on the trailing token) picks
    #   among several; that ranking is family-independent machinery in
    #   Parallel, not part of the pattern.
    # * ORACC `-[a-z]+` (P13-4): ANY lowercase run may split because P/Q
    #   textids are hyphen-free upstream — the one family whose stem shape,
    #   not tail literal, carried the safety proof.
    # * Freising `-[a-z-]+` (P13-11): multi-segment tails (bs1-tr-eng) are
    #   safe because works are bs<digits> — the digit ends the stem, so the
    #   first hyphen begins the variant.
    # * Damaskini/SuttaCentral/RIIG/OpenEtruscan/ETCSL literal `-en`/`-fr`
    #   (P23-1, P26-1, P25-1, P29-0, P31-5): stems are hyphen-rich
    #   ("berlinski--slovo-petki", "dhp21-32", "all-01-01"), so ONLY the
    #   exact minted tail may split — each frozen after a census that no
    #   upstream id ends in that literal.
    # * TLA-HF/AES literal `-de` (P28-2, P28-0): same stance; AES stems span
    #   two colon segments (corpus:textid) — colon structure is irrelevant
    #   to a terminal-tail split, so the generic stem `.+` covers it.
    # * Corpus ItAnt `-(eng|ita|dipl)` (P29-2): the closed alternation of
    #   minted tails (translations + the diplomatic layer); stems end in
    #   digits.
    # * I.Sicily `-en`/`-it`/`-translit` (P34-0): record ids are
    #   isic<digits> — trivially tail-free.
    #
    # A urn whose namespace declares NO family (papyri, treebanks, cdli…)
    # matches nothing and has no siblings — the frozen chain's fall-through,
    # preserved.
    #
    # == The declaration → pattern mapping
    #
    # A variant declaration on slug S compiles to
    #   /\A(?<work>urn:nabu:S:.+?)(?:<tail>|<tail>…)?\z/
    # — the urn namespace is the slug by house convention (every sibling-
    # minting source to date). The CTS_SIBLINGS marker compiles to the one
    # shared dotted-form pattern regardless of how many rows declare it
    # (perseus-greek, perseus-latin and first1k-greek all mint urn:cts).
    class SiblingFamilies
      # The CTS dotted-version form, verbatim from the retired constant.
      CTS_WORK = /\A(?<work>urn:cts:[^:]+:[^:]+\.[^:]+)\.[^:.]+\z/

      # +family+ is :cts (candidates = work.%) or :variant (candidates =
      # the bare work + work-%).
      Match = Data.define(:work, :family)

      class << self
        # The families of the SHIPPED registry — what `Parallel.new(catalog:)`
        # consults when no explicit families are given. The sibling grammar
        # is a GLOBAL installation fact (how every source nabu knows spells
        # its variant suffixes), NOT a property of the catalog a command
        # points at — so this resolves the installation's own sources.yml
        # (NABU_ROOT-aware, mirroring Nabu::Config), never a redirected-DB
        # test config. Memoized per resolved path.
        def default
          path = shipped_sources_path
          (@default ||= {})[path] ||= from_registry(Nabu::SourceRegistry.load(path))
        end

        def shipped_sources_path
          root = ENV.fetch("NABU_ROOT", "")
          root = Nabu::Config::PROJECT_ROOT if root.strip.empty?
          File.join(root, Nabu::Config::DEFAULT_SOURCES_PATH)
        end

        def from_registry(registry)
          cts = false
          variants = {}
          registry.each_source do |entry|
            declaration = entry.siblings
            next if declaration.nil?

            if declaration == Nabu::SourceRegistry::CTS_SIBLINGS
              cts = true
            else
              variants[entry.slug] = declaration
            end
          end
          new(cts: cts, variants: variants)
        end
      end

      # +variants+ maps slug => list of tail patterns (the registry
      # declaration shape); +cts+ turns on the dotted-version form.
      def initialize(cts:, variants:)
        @cts = cts
        @variant_patterns = variants.map do |slug, tails|
          prefix = Regexp.escape("urn:nabu:#{slug}:")
          /\A(?<work>#{prefix}.+?)(?:#{tails.join('|')})?\z/
        end
      end

      # The work urn + family kind for +urn+, or nil when no declared
      # family covers its namespace (no work notion — no siblings).
      def match(urn)
        if @cts && (cts_match = urn.match(CTS_WORK))
          return Match.new(work: cts_match[:work], family: :cts)
        end

        @variant_patterns.each do |pattern|
          variant_match = urn.match(pattern) or next
          return Match.new(work: variant_match[:work], family: :variant)
        end
        nil
      end
    end
  end
end
