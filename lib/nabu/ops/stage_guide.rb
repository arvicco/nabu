# frozen_string_literal: true

require_relative "../display"

module Nabu
  module Ops
    # The --verbose explanation registry: ONE place that says, in
    # library-reader prose, what each composite command is about to do
    # (COMMANDS) and what each of its stages derives and who reads the
    # result (STAGES). The composite orchestrators — Rebuild,
    # IncrementalRebuild, Ops::BuilderRefresh, SyncRunner, the lect facet
    # — announce stages by LABEL through Nabu::ProgressReporter#stage; an
    # entry here matches those labels (exactly, or by a pattern for the
    # per-source ones), so the orchestrators stay byte-identical.
    #
    # Why labels and not inline texts: Rebuild, IncrementalRebuild and
    # the lect facet live in the shared derivation core
    # (DerivationFingerprint) — an inline explanation there would dirty
    # every source's derivation stamp and price the next incremental
    # rebuild as a full replay for a pure UX change. This file sits in
    # ops/, outside the core. Drift is closed by the suite instead
    # (test/ops/stage_guide_test.rb parses every stage call site in the
    # orchestrators): a stage label without an entry fails, and an entry
    # no call site matches fails — a new stage cannot ship silent, a
    # renamed one cannot leave an orphan.
    #
    # Lookup order: exact label, then patterns in definition order (so a
    # narrower pattern is defined before a wider one), then — when the
    # caller names the registered source slugs — a bare slug is that
    # source's replay stage.
    module StageGuide
      Entry = Data.define(:key, :match, :text) do
        def matches?(label) = match.is_a?(Regexp) ? match.match?(label) : match == label
      end

      @stages = []
      @exact = {}
      @commands = {}

      class << self
        def stages = @stages.dup

        def commands = @commands.dup

        def stage(key, match, text)
          raise ArgumentError, "stage #{key}: blank explanation" if text.to_s.strip.empty?
          raise ArgumentError, "stage #{key}: already registered" if @stages.any? { |entry| entry.key == key }

          entry = Entry.new(key: key, match: match, text: text)
          @stages << entry
          @exact[match] = entry if match.is_a?(String)
          entry
        end

        def command(key, text)
          raise ArgumentError, "command #{key}: blank intro" if text.to_s.strip.empty?
          raise ArgumentError, "command #{key}: already registered" if @commands.key?(key)

          @commands[key] = text
        end

        def fetch(key)
          @stages.find { |entry| entry.key == key } ||
            raise(KeyError, "no StageGuide stage #{key.inspect} (known: #{@stages.map(&:key).join(', ')})")
        end

        def intro(key)
          @commands.fetch(key) { raise KeyError, "no StageGuide command #{key.inspect}" }
        end

        # The entry explaining +label+, or nil (an unregistered sub-step).
        # +sources+: the registered slugs, so a bare slug label reads as
        # that source's replay.
        def lookup(label, sources: nil)
          @exact[label] ||
            @stages.find { |entry| entry.match.is_a?(Regexp) && entry.matches?(label) } ||
            (sources&.include?(label) ? fetch(:source_replay) : nil)
        end
      end

      # Renders explanations on the progress channel: green through
      # Display.paint when Display.color? allows (a tty, NABU_COLOR; never
      # under NO_COLOR), plain text otherwise. Each stage key explains
      # ONCE per narrator — a 200-source replay or a multi-source sync
      # explains "replay" once, not per source. +before+ runs ahead of
      # every printed line (the CLI closes its open \r stage line there).
      class Narrator
        INDENT = "  "
        MARK = "» "

        def initialize(io: $stderr, color: nil, sources: nil, before: nil)
          @io = io
          @color = color.nil? ? Display.color?(tty: io.respond_to?(:tty?) && io.tty?) : color
          @sources = sources&.to_set
          @before = before
          @seen = Set.new
        end

        def color? = @color

        # The command's intro, before any work starts.
        def intro(key) = emit("#{MARK}#{StageGuide.intro(key)}", indent: "")

        # One stage label (the ProgressReporter on_explain callable).
        def call(label)
          entry = StageGuide.lookup(label, sources: @sources)
          return if entry.nil? || !@seen.add?(entry.key)

          emit("#{MARK}#{entry.text}")
        end

        # A per-item explanation whose text another registry owns (the
        # nabu-data feature titles beside their builders).
        def line(text) = emit("#{MARK}#{text}")

        def to_proc = method(:call).to_proc

        private

        def emit(text, indent: INDENT)
          @before&.call
          @io.puts("#{indent}#{Display.paint(text, color: :green, enabled: @color)}")
        end
      end

      # ---- composite commands (what the run does to the library) ----

      command :rebuild,
              "Rebuild drops the derived catalog and search index under db/ and regenerates them from the " \
              "permanent folders alone: every held source is re-parsed from its canonical snapshot (no " \
              "network), then every corpus-wide projection — dates, places, facets, kinds, lects, titles, " \
              "the search index, links — is re-derived. Search, the desk cards and the MCP tools read the " \
              "result; until it finishes the catalog is incomplete."
      command :rebuild_incremental,
              "Incremental rebuild keeps the live catalog and re-derives only what moved: each source's " \
              "canonical tree and parser code are fingerprinted against its derivation stamp, dirty sources " \
              "are re-parsed in place, and the corpus-wide projections and search index re-run only where " \
              "their inputs changed — the result is meant to equal a full rebuild."
      command :sync,
              "Sync brings each named source up to date with its upstream: new or changed files are fetched " \
              "into canonical/<slug>/ (upstream deletions go to the attic, never lost), the snapshot is " \
              "re-parsed into the catalog, and that source's slice of the search index and of every derived " \
              "lane is refreshed, so search, cards and axes show the new holdings at once."
      command :sync_parse_only,
              "Parse-only sync re-parses each source's already-fetched canonical snapshot (no network) into " \
              "the catalog and refreshes its search-index slice and derived lanes — how a parser or mapping " \
              "change reaches one source without a library-wide rebuild."
      command :sync_fetch_only,
              "Fetch-only sync downloads upstream changes into canonical/<slug>/ and stops: nothing is parsed " \
              "or loaded, so search and the cards keep serving the previous snapshot until a later sync or " \
              "rebuild replays the new one."
      command :builders_refresh,
              "builders:refresh re-runs the corpus-wide projections over the live catalog without re-parsing " \
              "any source: timeline, places, facets, the kind axis, lect resolution, the dictionary census, " \
              "crosswalked titles and the lemma rollups are dropped and re-projected from the current catalog " \
              "and config — how a mapping or rule edit reaches every query surface between rebuilds."
      command :lect_materialize,
              "lect materialize recomputes every document's resolved language stage from the current journal " \
              "rulings, per-source overrides and the nabu-lects codemap, so --lect filters, the language cards " \
              "and the lect census follow the latest rulings."
      command :lect_apply_rules,
              "lect apply-rules compiles the ratified facet→lect rules against the live catalog into journal " \
              "assignments (hand rulings are never overwritten), then re-materializes the lect facet so --lect " \
              "filters and the language cards see the new stages."
      command :lect_infer_dates,
              "lect infer-dates assigns a stage to each dated but unstaged document whose date interval sits " \
              "inside exactly one attested stage band, journals those rows, then re-materializes the lect " \
              "facet so --lect filters see them."
      command :place_apply,
              "place apply projects the nabu-places registry's matched place decisions onto documents that " \
              "carry no upstream place reference (an adapter's own reference always wins), so --place filters, " \
              "the place desk and the axis holdings count them."
      command :data_build,
              "data build derives publishable nabu-data datasets (CSV tables, a Frictionless datapackage, a " \
              "README) from the live catalog into your nabu-data clone; the library is only read, and no git " \
              "operation is performed there."

      # ---- stages (label → what it derives, who reads it) ----
      # Narrow patterns precede wide ones (lookup is first-match).

      # Source replay and the incremental verdict pass.
      stage :source_replay, nil,
            "Each source's canonical snapshot is re-parsed and its documents, passages and dictionary entries " \
            "loaded into the catalog — the holdings every later stage projects from."
      stage :pinning_code_identities, /\Apinning code identities\b/,
            "Pins every source's parser-code fingerprint before anything runs, so each stamp written later " \
            "describes the code this run actually used."
      stage :verdict, /\Averdict \S+ \(/,
            "Fingerprints each source's canonical tree against its derivation stamp: clean sources are left " \
            "as they are, dirty ones are queued for replay."
      stage :trusted, /\A\S+ — trusted \(re-stamped, no replay\)\z/,
            "A source whose only drift is parser code that git shows predates its stamp is re-stamped " \
            "without a replay — its catalog rows stay exactly as they are."

      # Sync's per-source steps.
      stage :sync_fetch, /\Afetch: /,
            "Downloads upstream's new or changed files into canonical/<slug>/; files upstream removed move to " \
            "the attic instead of vanishing."
      stage :sync_fetched_only, /\Afetched \S+ — parse\+load deferred/,
            "The fetched snapshot waits in canonical/: the catalog keeps serving the previous load until a " \
            "sync or rebuild replays it."
      stage :sync_load, /\Aparse\+load: /,
            "Parses the source's canonical snapshot and writes new, changed and withdrawn documents to the " \
            "catalog (unchanged documents are skipped) — what search and the cards will show."
      stage :dictionary_lane, /\Adictionary lane: /,
            "Loads the source's secondary dictionary shelf into the dictionary tables in the same run, so " \
            "`define` and the language cards see it."
      stage :index_slice_skipped, /\Aindex slice: \S+ skipped\b/,
            "Leaves this source's search-index slice as it is: the load changed no passage text, so the " \
            "index already matches it."
      stage :index_slice, /\Aindex (?:slice|delta): /,
            "Rewrites this source's slice of the search index — folded text, lemma postings, fuzzy trigrams " \
            "— for the passages that changed, so `nabu search` finds the new load."
      stage :post_load_lanes, /\Apost-load lanes: /,
            "Refreshes this source's share of the derived lanes — facets, kind axis, dates, silver dates, " \
            "titles, dictionary census, lemma rollups, links, place and person indexes — so no query " \
            "surface lags the load."

      # The corpus-wide projections (full rebuild, incremental, builders:refresh).
      stage :honkoku_ndl_catalog, "honkoku ndl catalog",
            "Attaches the National Diet Library catalog record (authors, date, subjects) to each Honkoku " \
            "transcription of an NDL-held item, so the facets and timeline can project it."
      stage :timeline, "timeline",
            "Re-derives every document's date and findspot rows from upstream metadata — the timeline behind " \
            "--from/--to/--century, the date histograms and the place filters."
      stage :silver_dates, "silver dates",
            "Re-projects the owner-armed model date estimates from the local dates shelf as silver-grade " \
            "dates, ranked below any upstream date (the timeline pass just dropped them)."
      stage :place_apply, "place apply",
            "Fills place references from the nabu-places registry's matched decisions on documents that carry " \
            "none from upstream — feeding --place and the place desk."
      stage :artifact_scripts, "artifact scripts",
            "Records the script the physical artifact was written in wherever it differs from the held " \
            "transcription (config/artifact_scripts.yml) — the script axis."
      stage :facets, "facets",
            "Projects each document's genre, type, material and provenance metadata into the facet table " \
            "behind --type/--province/--material and the axis pages."
      stage :kind_axis, "kind axis",
            "Maps upstream genre and kind labels onto the house document-kind taxonomy (config/kind_map.yml) " \
            "— the axis behind `nabu kind census` and the kind filters."
      stage :passage_facets, "passage facets",
            "Projects the passage annotations facet_map.yml names (subject classes, named entities) into the " \
            "passage-grain facet tables."
      stage :entry_facets, "entry facets",
            "Projects the dictionary-entry annotations facet_map.yml names into the entry-grain facet tables " \
            "the dictionary filters read."
      stage :hiero_postings, "hiero postings",
            "Tallies every hieroglyph attested in the AED text files into one precompiled row per sign — the " \
            "corpus panel of the hieroglyph card."
      stage :lect_journal, "lect journal",
            "Re-mints the lect journal from the owner rulings, the compiled facet→lect rules and the date-band " \
            "inferences — the per-document stage assignments the lect facet reads next."
      stage :lect_facets, "lect facets",
            "Flattens journal rulings, source overrides and the nabu-lects codemap into each document's " \
            "resolved language stage — the axis behind --lect, the language cards and the lect census."
      stage :lect_facet_rewrite, /\Alect facet: re-materializing\b/,
            "Walks every language-tagged document and writes a lect row wherever its resolution differs " \
            "from its bare code (no row means the code stands for itself)."
      stage :lect_facet_stats, "lect facet: deriving the census stats",
            "Re-counts documents per resolved lect for the language cards and the lect census."
      stage :dictionary_stats, "dictionary stats",
            "Re-counts each dictionary's live entries and resolves its language to a lect node — the " \
            "precompiled header `define`, the language cards and the site desks read."
      stage :derge_titles, "derge titles",
            "Gives the Derge canon's title-less texts their English and Tibetan titles from the 84000 " \
            "headers, matched by Tohoku number."
      stage :aes_titles, "aes titles",
            "Gives the AES corpus's title-less texts their names from the AED text headers, matched by TLA " \
            "text id."
      stage :source_stats, "source stats",
            "Re-counts per-source holdings into the precompiled table `nabu status`, `nabu list` and the " \
            "language cards read."
      stage :fulltext_index, /\Afulltext index\b/,
            "Builds the search index from scratch over every live passage — folded text, lemma postings, " \
            "fuzzy trigrams, character and sign coverage, alignment references, the reflex closure — " \
            "everything `nabu search` and the desks look up."
      stage :lemma_rollups, "lemma rollups",
            "Re-aggregates lemma attestations by language, century, grade and source — the precompiled " \
            "tables behind `nabu lemma` and `language --curve/--mixing`."
      stage :links_stamping, /\Alinks: stamping\b/,
            "Fingerprints what each recorded batch scope covers, so scopes whose inputs did not change keep " \
            "their edges instead of being re-mined."
      stage :links, "links",
            "Re-derives the links journal — reference edges from every reference-bearing source plus the " \
            "recorded batch scopes (parallels, cognates, formulas, place and person links) — the edges " \
            "`nabu links` and the cards show."
      stage :analyze, "analyze",
            "Refreshes SQLite planner statistics on the catalog and the index, so the first queries plan " \
            "against real row counts."
    end
  end
end
