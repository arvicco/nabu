# frozen_string_literal: true

# Nabu::CLI — links-journal miners and readers: parallels, formulas, links,
# cognates. Carved out of lib/nabu/cli.rb, the registry that loads it.
# The explain engine sits outside the batch miner's stamped code closure
# (Query::ParallelsExplain's class note) — only the interactive surfaces
# require it.
require_relative "../query/parallels_explain"

module Nabu
  class CLI < Thor
    # `links mine` / `links migrate-mined` (the mined layers' verbs) dispatch
    # from `links` below.
    include LinksMineCommands

    desc "parallels URN", "Find passages that quote or echo this one (intertext over the FTS index)"
    long_desc <<~HELP, wrap: false
      Passage-anchored intertext: point at ONE passage and find where the corpus
      quotes or echoes it — the classicist's "who cites this line? where does it
      resurface?" (docs/intertext-design.md §1). Query-time over the same FTS
      index as `search`, no precomputation: the anchor is folded to its search
      form, cut into overlapping 4-word grams, and each gram is probed as an
      exact phrase; passages that share grams are candidates, ranked by shared-
      gram count WEIGHTED BY RARITY (a rare shared phrase — a real quotation —
      outweighs a pile of common function-word grams).

      Not to be confused with `align` (the translation-column hub, verse X across
      its witnesses): parallels DISCOVERS reception across the whole corpus, from
      surface text alone.

      Each hit is one DOCUMENT (duplicate witnesses and multi-edition works
      otherwise flood the ranks): its best-matching passage urn, the score, the
      number of shared grams, and — when the document matches in several places —
      a "loci" count. Under each hit the shared PHRASE spans are shown (the grams
      merged back into contiguous text). Evidence is the folded search form, so
      accents/breathings are stripped — it marks WHAT matched; `nabu show <urn>`
      gives the pristine line.

      Elision is folded at gram-build: the apostrophe that some editions write as
      a letter (SBLGNT ἐπʼ) and others as punctuation (Swete/First1K ἐπ’) is
      stripped so a gram matches across editions — the fix that lets Matthew 4:4
      find LXX Deuteronomy 8:3.

      Only the anchor's OWN document is excluded. Translations and other-language
      witnesses self-exclude (they share no folded tokens with the anchor's
      language); a second same-language edition of the anchor's own work is kept
      — it is exactly the corroborating parallel you want.

      LEMMA ECHOES: when the anchor carries gold treebank lemmas (UD/PROIEL/
      TOROT), a second section lists passages sharing ≥2 of its RARE lemmas —
      re-inflected or reordered allusion that verbatim grams miss. Absent (and
      free) for non-lemmatized anchors.

      Filters: --lang / --license (exact class) scope candidates; --limit caps
      each list (default 15). --long expands every truncated list — all shared
      phrase spans and all shared lemmas, untrimmed (compact shows the first few
      with a "… and N more" tail).

      EXPLAIN: --explain decomposes each hit's score (the same engine, observed
      — the MCP nabu_parallels explain: true surface): one row per anchor gram
      the hit shares — the folded gram, its document frequency (df), the rarity
      weight 1/df and its contribution — the rows summing to the score exactly.
      The zero rows (grams the hit lacks, grams too common to score, all-stop
      grams never probed) are counted by status; --long lists them too.

      BATCH MODE (P16-1, the links journal): `parallels --batch SCOPE` mines a
      whole corpus slice — SCOPE is a source slug or a document-urn prefix,
      exactly the `formulas` scope grammar — looping this same engine over
      every anchor passage and PERSISTING the hits as kind=parallel edges —
      a HEAVY mined layer (config/mined_layers.yml): written to
      local/mined-links.sqlite3 with its provenance, never touched by
      `nabu rebuild`, re-mined later with `nabu links mine SCOPE` (`nabu
      links <urn>` reads them, and `show` grows a "linked:" footer). Each
      unordered pair is stored once, in
      the direction the probe found it; a rerun of the same scope supersedes
      the previous run's edges (idempotent). Pruning is explicit, never
      silent: only the top --per-anchor hits (default
      #{Nabu::BatchParallels::DEFAULT_PER_ANCHOR}) clearing --min-score
      (default #{Nabu::BatchParallels::DEFAULT_MIN_SCORE}) persist, and the
      summary line names both. --db writes the journal somewhere else (a
      scratch run). Interactive output is NEVER persisted — recomputing costs
      milliseconds; a stored copy would only go stale.

      PROFILES AND CHUNKS (P122-2): --profile NAME loads a declared tuning
      profile from config/reuse_profiles.yml (latin: trigrams, a 0.1 floor,
      a function-word drop; chinese: character 4-grams on the CJK lane, a 0.1
      floor, 10 hits per anchor) — explicit flags (--lang, --min-score,
      --per-anchor, --gram-size) still override it, and the run records the
      profile plus every effective parameter. --chunk-size N mines N anchors
      per committed chunk and prints one progress line per chunk (chunk N/M ·
      anchors · candidates · edges minted · elapsed) on stderr; a killed run
      resumes at its cursor when the same command is rerun (finished chunks
      are never re-mined, no edge is duplicated); --restart discards an
      unfinished run instead.

      Examples:
        nabu parallels urn:nabu:sblgnt:john:1.1          # John 1:1 across the Fathers
        nabu parallels urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
                                                         # the Odyssey proem — who quotes it
        nabu parallels urn:nabu:sblgnt:matt:4.4 --long   # Matt 4:4 → Luke, Origen, LXX Deut 8:3
        nabu parallels <urn> --lang grc --limit 30       # Greek parallels only, wider page
        nabu parallels urn:nabu:sblgnt:matt:4.4 --explain
                                                         # why each hit scores what it does
        nabu parallels --batch urn:nabu:sblgnt:matt --lang grc
                                                         # mine Matthew's parallels into the journal
        nabu parallels --batch sblgnt --min-score 0.1    # a whole source, stricter floor
        nabu parallels --batch corpus-corporum --profile latin --chunk-size 5000 2> pl.log
                                                         # Patrologia, resumable, logged

      Use cases: trace a verse's reception; find the source a Father is quoting;
      seed the citation graph one batch scope at a time.
    HELP
    option :lang, type: :string, desc: "Restrict candidates to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict candidates to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 15, desc: "Maximum hits per signal (default 15)"
    option :long, type: :boolean, default: false,
                  desc: "Expand every truncated list: all shared phrase spans and shared lemmas, untrimmed"
    option :explain, type: :boolean, default: false,
                     desc: "Decompose each hit's score into its per-gram contributions (gram, df, " \
                           "weight, contribution — summing to the score)"
    option :batch, type: :boolean, default: false,
                   desc: "Mine a SCOPE (source slug or urn prefix) and persist edges to the links journal"
    option :min_score, type: :numeric, banner: "S",
                       desc: "With --batch: rarity-score floor an edge must clear " \
                             "(default #{Nabu::BatchParallels::DEFAULT_MIN_SCORE})"
    option :per_anchor, type: :numeric, banner: "N",
                        desc: "With --batch: top document-grain hits kept per anchor " \
                              "(default #{Nabu::BatchParallels::DEFAULT_PER_ANCHOR})"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write a plain links journal at PATH (a scratch run) instead of the mined layer"
    option :profile, type: :string, banner: "NAME",
                     desc: "With --batch: load a tuning profile from config/reuse_profiles.yml " \
                           "(latin, chinese); explicit flags override it"
    option :gram_size, type: :numeric, banner: "N",
                       desc: "With --batch: shingle width in gram tokens " \
                             "(default #{Nabu::Query::Parallels::GRAM_SIZE}, or the profile's)"
    option :chunk_size, type: :numeric, banner: "N",
                        desc: "With --batch: mine N anchors per committed chunk — a killed run " \
                              "resumes at its cursor when rerun with the same flags"
    option :restart, type: :boolean, default: false,
                     desc: "With --batch: supersede an unfinished chunked run instead of resuming it"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Restrict candidates to a lect (P59-3, nabu-lects module): keep only hits " \
                        "whose resolution is this lect id or a more specific one under it — the " \
                        "same prefix semantics as search --lect; errors if the module is not synced"
    display_option
    def parallels(urn = nil)
      urn = urn.to_s.strip
      display_mode
      validate_license!(options[:license])
      if options[:batch] && options[:lect]
        raise Thor::Error, "parallels: --lect does not apply with --batch (the miner is corpus-wide)"
      end
      if options[:batch] && options[:explain]
        raise Thor::Error, "parallels: --explain is interactive only (the miner persists edges, not score parts)"
      end
      return batch_parallels(urn) if options[:batch]

      %i[min_score per_anchor db profile gram_size chunk_size restart].each do |flag|
        next unless options[flag]

        raise Thor::Error, "parallels: --#{flag.to_s.tr('_', '-')} only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "parallels: give a passage urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      engine = options[:explain] ? Nabu::Query::ParallelsExplain : Nabu::Query::Parallels
      result = engine.new(catalog: catalog, fulltext: fulltext)
                     .run(urn, limit: options[:limit].to_i,
                               lang: options[:lang], license: options[:license],
                               lect: options[:lect])
      print_parallels(result, urn: urn, long: options[:long])
      print_display_footer
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "formulas SCOPE", "Mine the repeated n-gram formulas within a corpus slice (oral-formulaic)"
    long_desc <<~HELP, wrap: false
      Intra-corpus formula mining: point at a corpus SLICE and find its recurring
      formulas — the oral-formulaic scholar's "what are the fixed phrases of this
      tradition, and where does each occur?" (docs/intertext-design.md §5). The
      same gram machinery as `parallels` pointed INWARD: instead of probing one
      passage against the whole corpus, every passage of the slice is folded, cut
      into overlapping n-word grams, and the grams counted in memory — the ones
      that recur are the formulas. Zero precomputation (~0.2 s per ~200k-token
      slice); reads the folded text straight from the catalog.

      SCOPE is a source slug (`aspr`) when one exists, else a urn prefix — a whole
      work (urn:cts:greekLit:tlg0012.tlg001.perseus-grc2) or a super-prefix over
      several (urn:cts:greekLit:tlg0012 = Iliad + Odyssey, the Homeric corpus).

      LANGUAGE: a translation-bearing source rides the same urn prefix as its base
      text (perseus-greek holds Greek AND aligned English), so an unfiltered run
      mixes traditions — pass --lang to mine one (a single-language source like
      ASPR needs none).

      RANKING: by count × gram length. No stoplist — the ranking is self-filtering
      (a genuine formula out-recurs any pure function-word sequence; measured, not
      one all-function-word gram reaches Homer's top). --min-count raises the
      recurrence floor against a noisy tail.

      Each formula prints its count and the folded gram (accents stripped, like
      `search` highlights — `nabu show <urn>` gives the pristine line), with a few
      example loci beneath. --long lists every locus of every reported formula.

      BATCH MODE (P16-2, the links journal): `formulas --batch SCOPE` runs the
      whole-tradition sweep once and PERSISTS kind=formula edges. A formula is
      a refrain across many loci, so it maps onto the pair-shaped journal as a
      STAR: each formula's first locus (urn order — deterministic) is the hub,
      with one edge to every other locus carrying the gram (detail) and the
      count (score); `nabu links <locus>` shows which refrain ties the line to
      the tradition, and `links <hub>` fans out every locus. Pruning is named,
      never silent: the top --max-formulas by rank persist (default
      #{Nabu::BatchFormulas::DEFAULT_MAX_FORMULAS}), at --min-count and
      --gram-size, all recorded in the run's params. A rerun of the same scope
      supersedes (idempotent); --db writes the journal elsewhere. Interactive
      output is never persisted.

      Examples:
        nabu formulas urn:cts:greekLit:tlg0012 --lang grc   # the Homeric formulas
        nabu formulas aspr                                  # Old English verse formulas
        nabu formulas aspr --gram-size 3 --min-count 5      # the riddle refrain "hwæt ic hatte"
        nabu formulas urn:cts:greekLit:tlg0012 --lang grc --long   # every locus
        nabu formulas --batch aspr                          # persist the ASPR formula stars
        nabu formulas --batch urn:cts:greekLit:tlg0012 --lang grc --max-formulas 500

      Use cases: characterize a tradition's formulaic diction; find every
      occurrence of a formula; seed an oral-formulaic study; wire the refrains
      into the mined citation graph (`nabu links`).
    HELP
    option :lang, type: :string,
                  desc: "Restrict the slice to a language (grc, ang) — wanted when a source mixes translations"
    option :min_count, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_MIN_COUNT,
                       desc: "Minimum recurrence to count as a formula (default 3)"
    option :gram_size, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_GRAM_SIZE,
                       desc: "Words per gram (2–8; default 4)"
    option :limit, type: :numeric, default: Nabu::Query::Formulas::DEFAULT_LIMIT,
                   desc: "Maximum formulas shown (default 25)"
    option :long, type: :boolean, default: false,
                  desc: "List every locus of every reported formula (compact shows a few examples)"
    option :batch, type: :boolean, default: false,
                   desc: "Sweep the SCOPE once and persist kind=formula edges to the links journal"
    option :max_formulas, type: :numeric, banner: "N",
                          desc: "With --batch: top formulas by rank persisted " \
                                "(default #{Nabu::BatchFormulas::DEFAULT_MAX_FORMULAS})"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    def formulas(scope = nil)
      scope = scope.to_s.strip
      return batch_formulas(scope) if options[:batch]

      %i[max_formulas db].each do |flag|
        next unless options[flag]

        raise Thor::Error, "formulas: --#{flag.to_s.tr('_', '-')} only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "formulas: give a source slug or urn prefix" if scope.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Query::Formulas.new(catalog: catalog).run(
        scope, gram_size: options[:gram_size].to_i, min_count: options[:min_count].to_i,
               lang: options[:lang], limit: options[:limit].to_i, long: options[:long]
      )
      print_formulas(result, long: options[:long])
    rescue ArgumentError => e
      raise Thor::Error, "formulas: #{e.message}"
    ensure
      catalog&.disconnect
    end

    desc "links URN", "Mined cross-reference edges touching this urn (the links journal)"
    long_desc <<~HELP, wrap: false
      Read the links journal (docs/intertext-design.md §7, architecture §15):
      every batch-mined edge touching URN, BOTH directions, grouped by kind
      (parallel, formula, cognate, reference, etymology). Each edge shows
      its counterpart urn resolved to the document title and language plus
      its kind's evidence — a parallel's rarity score, a formula's gram and
      count (← the hub locus of the refrain's star; `links <hub>` fans out
      every locus), a cognate's meet (ref · root [shelf] — a gem-pro shelf
      under a Slavic witness reads as a borrowing), a reference's asserting
      manifest (P19-4: a local-library article beside the passages it
      discusses), an etymology's ancestor lemma (P28-3: a Coptic dictionary
      entry's hieroglyphic/demotic predecessors from the ORAEC crosswalk);
      → means a batch anchor at URN discovered the counterpart,
      ← means the edge was found from the other end. The footer cites the
      producer run(s) that minted the edges — scope, parameters, and date —
      so every edge is honest about its provenance.

      Edges are urn-keyed in two stores, read as one: db/links.sqlite3
      holds the cheap lanes `nabu rebuild` re-derives (references,
      formulas, cognates, the place pair); local/mined-links.sqlite3 holds
      the HEAVY mined layers (config/mined_layers.yml — the parallels
      scopes), which no rebuild touches — their run footer says "mined
      layer" and gives the layer's mine date. Counterparts re-resolve
      against the current catalog (passage grain first, document grain
      second, dictionary-entry grain third — an ingested shelf's
      urn:nabu:dict: urns read "headword — dictionary"), and one that no
      longer resolves is flagged "(not in catalog)" rather than hidden.
      Edges are minted ONLY by batch producers (`parallels --batch SCOPE`,
      `formulas --batch SCOPE`, `cognates --batch WORK`, and the sync-time
      reference/etymology refreshes of the declaring sources); interactive
      output never persists.

      Compact shows the first few edges per kind; --long lists all. --db
      reads a journal written elsewhere (a scratch batch run).

      The mined layers' two verbs:
        nabu links mine SCOPE           re-mine a recorded heavy scope into
                                        local/mined-links.sqlite3 (the ONLY
                                        trigger — rebuild never does; a
                                        self-check compares the fresh edges
                                        with the layer they replace)
        nabu links migrate-mined        move heavy runs still in
                                        db/links.sqlite3 into the store, once
                                        (--dry-run counts, writes nothing)

      Examples:
        nabu links urn:nabu:sblgnt:matt:4.4     # who is wired to Matt 4:4
        nabu links urn:nabu:sblgnt:matt:4.4 --long
        nabu links <urn> --db /tmp/links.sqlite3
        nabu links mine perseus-latin           # re-mine the Latin layer (hours)

      Use cases: walk the mined citation graph passage by passage; audit what
      a batch run asserted; jump between quotation and source via `nabu show`.
    HELP
    option :long, type: :boolean, default: false,
                  desc: "List every edge of every kind (compact shows the first few per kind)"
    option :db, type: :string, banner: "PATH",
                desc: "Read the links journal at PATH instead of db/links.sqlite3"
    def links(urn = nil, *args)
      return run_links_verb(urn, args) if LinksMineCommands::VERBS.include?(urn)

      urn = urn.to_s.strip
      raise Thor::Error, "links: give a passage or document urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      journal = if options[:db]
                  Nabu::Store::LinksJournal.open_readonly(options[:db])
                else
                  Nabu::Store::LinkLayers.open_readonly(config) # db/links + the mined layers
                end
      return say("no links journal yet — mine one with `nabu parallels --batch SCOPE`") if journal.nil?

      result = Nabu::Query::Links.new(catalog: catalog, journal: journal).run(urn)
      raise Thor::Error, "links: unknown urn #{urn} (no catalog entry, no edges)" if result.nil?

      print_links(result, long: options[:long])
      print_links_notes_lane(catalog, urn)
    ensure
      catalog&.disconnect
      journal&.disconnect
    end

    desc "cognates TARGET", "Verses where aligned witnesses use reflexes of the same root (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's join (P15-3): verses of a registered alignment work
      where witnesses in TWO OR MORE languages use reflexes of the SAME
      reconstruction root — the alignment hub (nabu align) crossed with the
      Wiktionary reconstruction crosswalk (nabu etym). Gothic salt ~ OCS соль
      meet at PIE *sḗh₂l in the salt saying (LUKE 14.34); hlaifs ~ хлѣбъ at
      *hlaibaz in "he who eats my bread" (JOHN 13.18).

      TARGET is a registered work id (nt, ot, psalms — batches the whole
      work), a verse ref (LUKE 14.34), a chapter (LUKE 14), or a book (LUKE).
      Each hit names the root with its SHELF — and the shelf is part of the
      answer: a Slavic witness meeting a Germanic witness at a gem-pro entry
      (*hlaibaz, *kaisaraz) is very possibly a BORROWING, not common descent;
      ine-pro meets are the inheritance signal. Since P17-3 a witness whose
      descent from the root the crosswalk FLAGS as a loan reads "(loan)"
      (chu хлѣбъ (loan) ~ got hlaifs at *hlaibaz — the flag ORs along the
      closure path, so a loan on a proto-to-proto edge still fires); the
      shelf heuristic remains the caption for unflagged edges — upstream
      flags are high-precision, low-recall — and rows predating the flag
      reparse carry no label (honest unknown).

      Corpus-common words are suppressed by default (a lemma in ≥ 10% of its
      language's gold passages, absolute floor 50 — ὁ, jah, и would otherwise
      flood every verse); --all shows them, and the header counts what fell.
      Frequency is a coarse proxy: богъ (4.9% of OCS) and нъ "but" (4.7%) are
      inseparable by df, so some common words survive — read the hits.

      Recall is bounded by Wiktionary descendants coverage (roughly a third
      of Gothic and a fifth of OCS gold lemma types reach any proto entry)
      and by gold lemmatization (~10% of the corpus): absence of a hit is
      absence of evidence, not evidence of unrelatedness.

      --langs got,chu restricts the comparison to the named languages (at
      least two); --work picks the alignment work when the ref is ambiguous;
      --long lifts the #{Nabu::Query::Cognates::MAX_GROUPS}-hit compact cap
      and expands gloss/dictionary/document detail per hit.

      BATCH MODE (P16-2, the links journal): `cognates --batch WORK` maps the
      whole work once and PERSISTS kind=cognate edges between the aligned
      witness passages that meet at a reconstruction root — one edge per
      cross-language passage pair, its detail carrying the meet (ref · root
      [SHELF] — the shelf rides every edge because a gem-pro meet for a
      Slavic witness reads as a borrowing), its score the distinct-root
      count. WORK must be a registered work id (per-ref runs stay
      interactive). Common-word suppression stays on (--all lifts it, and
      the run records that); a rerun of the same work supersedes
      (idempotent); --db writes the journal elsewhere. Interactive output is
      never persisted.

      Examples:
        nabu cognates "LUKE 14.34"            # the salt saying, all languages
        nabu cognates nt --langs got,chu      # the whole NT, Gothic × OCS
        nabu cognates "JOHN 13" --langs got,chu,grc
        nabu cognates nt --langs got,chu --all  # keep the common-word matches
        nabu cognates --batch nt --langs got,chu  # persist the Gothic × OCS cognate map
    HELP
    option :work, type: :string,
                  desc: "Alignment work id (optional when the target decides it)"
    option :langs, type: :string, banner: "got,chu", aliases: ["--lang"],
                   desc: "Restrict the comparison to these languages (comma-joined, at least two); " \
                         "--lang is the standing alias (the one language-filter spelling)"
    option :all, type: :boolean, default: false,
                 desc: "Show the common-word matches the default suppresses"
    option :long, type: :boolean, default: false,
                  desc: "Render every hit (compact caps at #{Nabu::Query::Cognates::MAX_GROUPS}) " \
                        "and expand gloss/dictionary/document detail"
    option :batch, type: :boolean, default: false,
                   desc: "Map the whole WORK once and persist kind=cognate edges to the links journal"
    option :db, type: :string, banner: "PATH",
                desc: "With --batch: write the links journal at PATH instead of db/links.sqlite3"
    option :lect, type: :string, banner: "LECT-ID",
                  desc: "Scope witnesses OF THIS LECT'S ANCHOR LANGUAGE to the lect (P59-3: " \
                        "--lect grc:koi keeps cognate sets whose Greek witness is Koine; " \
                        "other-language witnesses pass untouched); errors if the nabu-lects " \
                        "module is not synced"
    display_option
    def cognates(*target_parts)
      target = target_parts.join(" ").strip
      display_mode
      return batch_cognates(target) if options[:batch]

      if options[:db]
        raise Thor::Error, "cognates: --db only applies with --batch " \
                           "(interactive results are never persisted)"
      end
      raise Thor::Error, "cognates: give a work id (nt) or a citation ref (e.g. LUKE 14.34)" if target.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      result = Nabu::Query::Cognates.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                    .run(target, work: options[:work], langs: parse_langs(options[:langs]),
                                                 all: options[:all], long: options[:long],
                                                 lect: options[:lect])
      print_cognates(result)
      print_display_footer
    rescue Nabu::Query::Cognates::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    # How many evidence spans / shared lemmas a compact `parallels` hit shows
    # before it elides with a "… and N more" tail; --long lifts the cap.
    PARALLELS_COMPACT_ITEMS = 3

    # Compact evidence-span width; --long prints the span untrimmed.
    PARALLELS_SPAN_CHARS = 72

    # Edges shown per kind by `nabu links` before the "… and N more" tail
    # (--long lists all — the conventions §10 house rule).
    LINKS_COMPACT_ITEMS = 10

    # Batch-mining progress tick cadence (anchors per stderr line); a scope
    # smaller than one tick prints no progress at all — just the summary.
    BATCH_PROGRESS_EVERY = 200

    no_commands do
      # Render `parallels` (P15-1): the anchor line, then one hit per document —
      # urn [lang], score, shared-gram count and loci, and the shared PHRASE
      # spans indented beneath. A lemma-echoes section follows when the anchor is
      # gold-lemmatized. `--long` expands every truncated list.
      def print_parallels(result, urn:, long:)
        raise Thor::Error, "parallels: no live passage at #{urn} (check `nabu show #{urn}`)" if result.nil?

        title = result.anchor_title ? " — #{result.anchor_title}" : ""
        say "parallels of #{result.anchor_urn}#{title}"
        if result.gram_count.zero?
          say "  passage too short for #{Nabu::Query::Parallels::GRAM_SIZE}-word grams"
          return
        end

        say "  no surface-gram parallels" if result.hits.empty?
        result.hits.each { |hit| print_parallel_hit(hit, long: long) }
        say "#{result.hits.size} #{result.hits.size == 1 ? 'parallel' : 'parallels'} " \
            "from #{result.gram_count} grams (evidence is diacritic-folded)"
        print_lemma_echoes(result.lemma_echoes, long: long) unless result.lemma_echoes.empty?
      end

      def print_parallel_hit(hit, long:)
        loci = hit.loci > 1 ? " · #{hit.loci} loci" : ""
        grams = "#{hit.shared_gram_count} #{hit.shared_gram_count == 1 ? 'gram' : 'grams'}"
        say "#{hit.urn}#{" [#{hit.language}]" if hit.language}  " \
            "score #{format('%.2f', hit.score)} · #{grams}#{loci}"
        lines = compact_list(hit.evidence, long: long) do |span|
          display_text(long ? span : truncate_line(span, PARALLELS_SPAN_CHARS), hit.language)
        end
        lines.each { |line| say "  #{line}" }
        print_parallel_explain(hit.contributions, long: long) if hit.respond_to?(:contributions)
      end

      # --explain: the shared rows (gram · df · weight → contribution),
      # summing to the score; the zero rows counted by status, listed with
      # --long.
      def print_parallel_explain(rows, long:)
        shared, zero = rows.partition { |row| row.contribution.positive? }
        say "  explain (gram · df · weight → contribution):"
        (long ? rows : shared).each do |row|
          times = row.positions > 1 ? " ×#{row.positions}" : ""
          status = row.status == "shared" ? "" : " (#{row.status})"
          say "    #{row.gram}#{times} · df #{row.df || '—'} · #{format('%.4f', row.weight)} → " \
              "#{format('%.4f', row.contribution)}#{status}"
        end
        return if long || zero.empty?

        counts = zero.group_by(&:status).map { |status, members| "#{status} #{members.size}" }.join(" · ")
        say "    … #{zero.size} zero row(s): #{counts} (--long)"
      end

      def print_lemma_echoes(echoes, long:)
        say "lemma echoes (rare shared lemmas — re-inflected/reordered allusion):"
        echoes.each do |echo|
          say "#{echo.urn}#{" [#{echo.language}]" if echo.language}  score #{format('%.2f', echo.score)}"
          say "  #{compact_list(echo.shared_lemmas, long: long).join(', ')}"
        end
      end

      # Render `formulas` (P15-5): the slice header (passages/tokens), then one
      # line per formula — count × the folded gram — with example loci beneath
      # (compact) or every locus (--long). The footer states the ranking and the
      # recurring total so the "top N of M" elision is explicit.
      def print_formulas(result, long:)
        lang = result.lang ? " [#{result.lang}]" : ""
        say "formulas in #{result.scope}#{lang} — " \
            "#{plural(result.passage_count, 'passage')} / #{plural(result.token_count, 'token')}"
        return say("  no passages in scope (unknown source slug or urn prefix?)") if result.passage_count.zero?
        return say("  no #{result.gram_size}-grams recur ≥#{result.min_count}× in this slice") if result.formulas.empty?

        result.formulas.each { |formula| print_formula(formula, long: long) }
        say "showing #{result.formulas.size} of #{plural(result.recurring_count, 'formula')} " \
            "recurring ≥#{result.min_count}× (rank = count × #{result.gram_size}-gram length; " \
            "grams are diacritic-folded)"
      end

      def print_formula(formula, long:)
        say "#{formula.count}×  #{formula.gram}"
        return if formula.loci.empty?

        prefix = !long && formula.count > formula.loci.size ? "e.g. " : ""
        say "     #{prefix}#{formula.loci.join(', ')}"
      end

      # -- links journal (P16-1) ------------------------------------------------

      # `parallels --batch SCOPE`: mine the scope with Nabu::BatchParallels and
      # persist edges to the links journal. Progress ticks go to stderr
      # (stdout keeps the summary); the summary NAMES the pruning thresholds —
      # no silent caps — and suppresses zero fields (house style).
      def batch_parallels(scope)
        raise Thor::Error, "parallels --batch: give a source slug or urn prefix" if scope.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

        profile = batch_profile
        chunk_size = batch_chunk_size
        mine = lambda do |journal|
          Nabu::BatchParallels.new(catalog: catalog, fulltext: fulltext, journal: journal)
                              .run(scope, profile: profile, lang: options[:lang], license: options[:license],
                                          chunk_size: chunk_size, restart: options[:restart],
                                          progress: chunk_size ? nil : batch_progress,
                                          on_chunk: chunk_size ? batch_chunk_progress : nil,
                                          **batch_thresholds)
        end
        # P70-3b: the batch scope is config-durable (P122-2: the profile
        # NAME and chunk size ride along, re-resolved from config/ on a
        # re-mine). The cost law: a HEAVY producer's run is a mined layer —
        # written through the mined-layers gateway with its provenance,
        # never into db/links.sqlite3.
        params = { "lang" => options[:lang], "license" => options[:license],
                   "profile" => options[:profile], "chunk_size" => chunk_size }
                 .merge(batch_thresholds.transform_keys(&:to_s)).compact
        recorded = { "producer" => "parallels", "scope" => scope, "params" => params }
        result = mined = nil
        if options[:db] || !Nabu::MinedLayers.heavy?("parallels")
          journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
          result = mine.call(journal)
        else
          warn "parallels --batch: stamping the layer's inputs (member content identities) …"
          mined = Nabu::MinedLayers.mine!(recorded, config: config, catalog: catalog,
                                                    registry: Nabu::SourceRegistry.load(config.sources_path)) do |store|
            result = mine.call(store)
          end
        end
        Nabu::LinkScopes.record!(config.link_scopes_path, producer: "parallels", scope: scope, params: params) \
          unless options[:db]
        print_batch_parallels(result)
        say "  mined layer #{config.mined_links_path}: #{mine_verdict(mined)}" if mined
      rescue Nabu::Error => e
        raise Thor::Error, e.message
      rescue Interrupt
        raise unless chunk_size

        # A chunked run's committed chunks are durable (their edges and the
        # cursor landed together); only the chunk in flight rolled back.
        warn "\ninterrupted — every committed chunk is kept; rerun the same command to resume at the cursor."
        exit 130
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        journal&.disconnect
      end

      def batch_thresholds
        thresholds = {}
        thresholds[:min_score] = options[:min_score].to_f if options[:min_score]
        thresholds[:per_anchor] = options[:per_anchor].to_i if options[:per_anchor]
        thresholds[:gram_size] = options[:gram_size].to_i if options[:gram_size]
        thresholds
      end

      # The --profile lookup (P122-2): a ReuseProfiles::Profile, nil when
      # the flag is absent; an undeclared name names the declared ones.
      def batch_profile
        return nil unless options[:profile]

        Nabu::ReuseProfiles.default.fetch(options[:profile])
      end

      # One stderr line per committed chunk (P122-2) — log-friendly, so a
      # `2> mine.log` run is readable while it is live.
      def batch_chunk_progress
        ->(report) { warn "  #{Nabu::BatchParallels.chunk_line(report)}" }
      end

      def batch_chunk_size
        return nil unless options[:chunk_size]

        size = options[:chunk_size].to_i
        raise Thor::Error, "parallels --batch: --chunk-size must be a positive integer" unless size.positive?

        size
      end

      # A stderr tick every BATCH_PROGRESS_EVERY anchors (and at the end), so a
      # minutes-long mine is visibly alive without flooding the terminal.
      def batch_progress
        lambda do |done, total, edges|
          return unless (done % BATCH_PROGRESS_EVERY).zero? || done == total

          warn "  #{done}/#{total} anchors · #{edges} edges" if total > BATCH_PROGRESS_EVERY
        end
      end

      def print_batch_parallels(result)
        say "batch parallels over #{result.scope}#{" [#{result.lang}]" if result.lang}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}" \
            "#{" · profile #{result.profile}" if result.profile}"
        say "  #{plural(result.anchor_count, 'anchor')} · kept top #{result.per_anchor}/anchor " \
            "at score ≥ #{result.min_score} · #{result.gram_size}-grams#{batch_superseded(result)} · " \
            "#{format('%.1f', result.elapsed)} s"
        return unless result.chunks > 1 || result.resumed

        say "  #{result.chunks_mined} of #{plural(result.chunks, 'chunk')} mined this run" \
            "#{' (resumed at the cursor)' if result.resumed}"
      end

      # `formulas --batch SCOPE` (P16-2): sweep the whole tradition once and
      # persist each formula as a STAR of kind=formula edges (hub = its first
      # locus in urn order; detail = the gram, score = the count — the
      # edge-shape verdict is argued in Nabu::BatchFormulas). Same summary
      # discipline as batch parallels: every pruning knob named.
      def batch_formulas(scope)
        raise Thor::Error, "formulas --batch: give a source slug or urn prefix" if scope.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog

        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchFormulas.new(catalog: catalog, journal: journal)
                                    .run(scope, gram_size: options[:gram_size].to_i,
                                                min_count: options[:min_count].to_i,
                                                lang: options[:lang], **max_formulas_option)
        unless options[:db]
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "formulas", scope: scope,
                                                            params: { "gram_size" => options[:gram_size].to_i,
                                                                      "min_count" => options[:min_count].to_i,
                                                                      "lang" => options[:lang] }
                                           .merge(max_formulas_option.transform_keys(&:to_s)).compact)
        end
        print_batch_formulas(result)
      rescue ArgumentError => e
        raise Thor::Error, "formulas: #{e.message}"
      ensure
        catalog&.disconnect
        journal&.disconnect
      end

      def max_formulas_option
        options[:max_formulas] ? { max_formulas: options[:max_formulas].to_i } : {}
      end

      def print_batch_formulas(result)
        say "batch formulas over #{result.scope}#{" [#{result.lang}]" if result.lang}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        coalesced = result.coalesced.positive? ? " · #{result.coalesced} overlapping pairs coalesced" : ""
        say "  #{plural(result.formula_count, 'formula')} persisted as stars " \
            "(top #{result.max_formulas} by rank of #{result.recurring_count} recurring " \
            "≥#{result.min_count}× #{result.gram_size}-grams)#{coalesced}" \
            "#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      # `cognates --batch WORK` (P16-2): map the whole alignment work once and
      # persist kind=cognate edges between cross-language witness passages
      # meeting at a reconstruction root; the meet (ref · root [shelf]) rides
      # each edge's detail (the provenance verdict is argued in
      # Nabu::BatchCognates).
      def batch_cognates(work_id)
        raise Thor::Error, "cognates --batch: give a registered work id (nt)" if work_id.empty?

        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        journal = Nabu::Store::LinksJournal.open!(options[:db] || config.links_path)
        result = Nabu::BatchCognates.new(catalog: catalog, fulltext: fulltext,
                                         registry: registry, journal: journal)
                                    .run(work_id, langs: parse_langs(options[:langs]), all: options[:all])
        unless options[:db]
          Nabu::LinkScopes.record!(config.link_scopes_path, producer: "cognates", scope: work_id,
                                                            params: { "langs" => parse_langs(options[:langs]),
                                                                      "all" => options[:all] }.compact)
        end
        print_batch_cognates(result)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        journal&.disconnect
      end

      def print_batch_cognates(result)
        langs = result.langs ? " [#{result.langs.join('×')}]" : ""
        say "batch cognates over #{result.work}#{langs}: " \
            "#{plural(result.edges_written, 'edge')} written#{batch_refreshed(result)} · run #{result.run_id}"
        suppressed = if result.suppressed.positive?
                       " · #{plural(result.suppressed, 'common-word group')} suppressed (--all keeps)"
                     else
                       ""
                     end
        say "  #{plural(result.group_count, 'verse-root group')}#{suppressed}" \
            "#{batch_superseded(result)} · #{format('%.1f', result.elapsed)} s"
      end

      def batch_refreshed(result)
        result.edges_refreshed.positive? ? " (+#{result.edges_refreshed} refreshed in place)" : ""
      end

      def batch_superseded(result)
        return "" unless result.superseded_runs.positive?

        " · superseded #{plural(result.superseded_runs, 'prior run')} " \
          "(#{plural(result.superseded_edges, 'edge')})"
      end

      # Render `nabu links` (P16-1): the urn header, one section per kind with
      # each edge's direction, resolved counterpart, and score, then the
      # provenance footer citing the producer run(s). Compact caps each kind at
      # LINKS_COMPACT_ITEMS; --long lists all (house rule, conventions §10).
      def print_links(result, long:)
        title = result.title ? " — #{result.title}" : ""
        say "links of #{result.urn}#{title}"
        return say("  no links") if result.total.zero?

        result.groups.keys.sort.each { |kind| print_links_group(kind, result.groups.fetch(kind), long: long) }
        result.runs.each do |run|
          date = run.mined? ? "mined #{run.mined_at.strftime('%Y-%m-%d')}" : run.created_at.strftime("%Y-%m-%d")
          say "#{plural(result.total, 'edge')} · #{run.label}: #{run.producer} over #{run.scope} " \
              "#{format_link_params(run.params)}· #{date}"
        end
      end

      def print_links_group(kind, edges, long:)
        say "#{kind} (#{edges.size}):"
        shown = long ? edges : edges.first(LINKS_COMPACT_ITEMS)
        shown.each { |edge| say "  #{format_link_edge(edge, kind)}" }
        hidden = edges.size - shown.size
        say "  … and #{hidden} more (--long lists all)" if hidden.positive?
      end

      def format_link_edge(edge, kind)
        arrow = edge.direction == :out ? "→" : "←"
        where = if edge.resolved?
                  "#{" — #{edge.title}" if edge.title}#{" [#{edge.language}]" if edge.language}"
                else
                  " (not in catalog)"
                end
        "#{arrow} #{edge.urn}#{where}#{format_link_evidence(edge, kind)}"
      end

      # The per-kind evidence tail (P16-2): a formula edge shows its gram and
      # slice count (“saga hwaet ic hatte” ×4 — "score 4.00" would misread a
      # count as a rarity score); a cognate edge shows its meet (the detail
      # already carries ref · root [shelf], and its score merely counts the
      # roots listed there — suppressed as zero-signal); a parallel edge keeps
      # the rarity score; an unknown future kind prints whatever it has.
      def format_link_evidence(edge, kind)
        case kind
        when "formula"
          "#{"  “#{edge.detail}”" if edge.detail}#{"  ×#{edge.score.to_i}" if edge.score}"
        when "cognate"
          edge.detail ? "  #{edge.detail}" : ""
        else
          "#{"  score #{format('%.2f', edge.score)}" if edge.score}#{"  #{edge.detail}" if edge.detail}"
        end
      end

      # Array params (cognates' langs) render comma-joined, not as inspected
      # Ruby arrays — compact house style.
      def format_link_params(params)
        pairs = params.except("kind").map do |key, value|
          # A long list (a profile's stop tokens) is provenance, not footer
          # reading — counted here; params_json keeps it whole.
          shown = if value.is_a?(Array)
                    value.size > 5 ? "#{value.size} tokens" : value.join(",")
                  else
                    value
                  end
          "#{key} #{shown}"
        end
        pairs.empty? ? "" : "(#{pairs.join(', ')}) "
      end

      # The `links` owner-notes lane: the urn's own notes beside its mined
      # edges (curation next to discovery), silent when unnoted.
      def print_links_notes_lane(catalog, urn)
        rows = Nabu::Query::Notes.new(catalog: catalog).for_urn(urn)
        return if rows.empty?

        say "owner notes (#{rows.size}):"
        rows.each { |row| say "  #{note_line(row)}" }
      end

      # Cap a list to PARALLELS_COMPACT_ITEMS with a "… and N more" tail unless
      # +long+; each kept item passes through the block (span trimming). The tail
      # itself names --long so the elision is discoverable.
      def compact_list(items, long:)
        kept = long ? items : items.first(PARALLELS_COMPACT_ITEMS)
        rendered = kept.map { |item| block_given? ? yield(item) : item }
        extra = items.size - kept.size
        rendered << "… and #{extra} more (--long)" if extra.positive?
        rendered
      end

      # --langs as an array: comma-joined on the CLI, validated by the query.
      def parse_langs(value)
        return nil if value.nil?

        value.split(",").map(&:strip).reject(&:empty?)
      end

      # cognates (P15-3): header with honest totals + the suppression count,
      # then one compact block per (verse, root) hit — the root line carries
      # the SHELF (a gem-pro meet with a Slavic witness reads as a borrowing;
      # see the command help), each witness its lemma and attested forms.
      def print_cognates(result)
        say "#{result.query} — work #{result.work} · shared-root verses across witnesses"
        say "  #{cognates_counts(result)}"
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} hits — narrow the " \
              "target, or pass --long to render all"
        end
        result.groups.each { |group| print_cognates_group(group, result.documents) }
      end

      def cognates_counts(result)
        verses = result.groups.map(&:ref).uniq.size
        roots = result.groups.map { |group| group.root.urn }.uniq.size
        counts = if result.total.zero?
                   "no hits — no verse here has two witnesses on one root"
                 else
                   "#{plural(result.total, 'hit')} · #{plural(verses, 'verse')} · " \
                     "#{plural(roots, 'root')}"
                 end
        return counts if result.suppressed.zero?

        "#{counts}; #{result.suppressed} common-word #{result.suppressed == 1 ? 'hit' : 'hits'} " \
          "suppressed (--all shows them)"
      end

      def print_cognates_group(group, documents)
        say ""
        say "#{group.ref}  #{group.root.headword} [#{group.root.shelf} · #{group.root.license_class}]"
        if options[:long]
          say "    #{group.root.dictionary_title}#{" · gloss: #{group.root.gloss}" if group.root.gloss}"
        end
        group.witnesses.each do |witness|
          loan = witness.borrowed ? " (loan)" : ""
          say "    #{witness.language.ljust(4)} #{display_text(witness.lemma, witness.language)}" \
              "#{loan}#{cognates_surfaces(witness)}"
          next unless options[:long]

          witness.document_urns.each do |urn|
            doc = documents[urn]
            say "         #{urn}#{" — #{doc[:title]} [#{doc[:license_class]}]" if doc}"
          end
        end
      end

      # The attested forms, shown when they add anything over the lemma.
      def cognates_surfaces(witness)
        forms = witness.surfaces - [witness.lemma]
        return "" if forms.empty?

        " — attested as #{forms.map { |form| display_text(form, witness.language) }.join(', ')}"
      end
    end
  end
end
