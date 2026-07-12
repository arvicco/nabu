# frozen_string_literal: true

require "thor"
require_relative "version"

module Nabu
  # Command-line entry point. Only `version` is functional in Phase 0; the
  # ingest/query subcommands are stubs that report "not implemented" and exit 1
  # so scripts and CI can rely on the failure signal before the real work lands.
  class CLI < Thor
    # Raise Thor::Error (rather than aborting the process abruptly) so failures
    # surface a clean stderr message and a non-zero exit status.
    def self.exit_on_failure?
      true
    end

    desc "version", "Print the Nabu version"
    def version
      say Nabu::VERSION
    end

    desc "sync [SOURCE]", "Fetch and load a source (or --all live sources) into the store"
    option :all, type: :boolean, default: false,
                 desc: "Sync every enabled source with sync_policy: live"
    option :parse_only, type: :boolean, default: false,
                        desc: "Skip fetch; re-parse the snapshot already on disk"
    option :force, type: :boolean, default: false,
                   desc: "Override the >20% withdrawal circuit breaker"
    def sync(slug = nil)
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # Ledger FIRST: open_or_create_ledger lifts a pre-P7-1 catalog's history
      # before open_or_create_catalog migrates the moved tables away.
      ledger = open_or_create_ledger(config)
      db = open_or_create_catalog(config)
      runner = Nabu::SyncRunner.new(config: config, registry: registry, db: db, ledger: ledger)
      options[:all] ? sync_all(runner) : sync_one(runner, registry, slug)
    rescue Nabu::Error => e
      # Unknown slug (ValidationError), fetch failure (FetchError), ... all
      # surface as a clean stderr message and exit 1.
      raise Thor::Error, e.message
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    desc "status", "Show per-source sync status and passage counts"
    def status
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      db = open_catalog(config)
      ledger = open_ledger(config)
      say Nabu::StatusReport.render(registry: registry, db: db, ledger: ledger)
    ensure
      db&.disconnect
      ledger&.disconnect
    end

    desc "rebuild", "Rebuild the derived db/ from canonical/ (parse-only; no fetch)"
    option :dry_run, type: :boolean, default: false,
                     desc: "Print what would happen and change nothing"
    def rebuild
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      # db/ is derived data by design (architecture §1); dropping it is the whole
      # point, so a real run needs no confirmation. An empty registry has nothing
      # to replay.
      return say("Nothing to rebuild: no sources registered.") if registry.empty?

      rebuilder = Nabu::Rebuild.new(config: config, registry: registry)
      if options[:dry_run]
        print_plan(rebuilder.plan)
      else
        result = rebuilder.run(progress: progress_reporter)
        finish_progress
        print_result(result)
      end
    end

    desc "verify", "Re-hash canonical files against the catalog (bitrot/tamper check; cronnable)"
    def verify
      config = Nabu::Config.load
      registry = Nabu::SourceRegistry.load(config.sources_path)
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      result = Nabu::Verify.new(config: config, registry: registry, db: catalog).run
      print_verify(result)
      # A clean run returns normally (exit 0); any mismatch/missing/unparseable
      # exits 1 via the shared Thor::Error path, the report already on stdout.
      raise Thor::Error, verify_failure_summary(result) unless result.clean?
    ensure
      catalog&.disconnect
    end

    desc "health", "Source health checks (run-history trends + live golden replay; --remote for the upstream probe)"
    option :remote, type: :boolean, default: false,
                    desc: "Probe every registered upstream (git ls-remote + license drift); no cloning, no corpus fetch"
    def health
      # Bare `health` is the local, no-network P5-5 check (run-history trends +
      # live golden replay). --remote is the P5-3 upstream probe. The two share
      # nothing at runtime, so keep them in separate helpers with their own db
      # lifetimes and exit-code raises.
      options[:remote] ? run_remote_health : run_local_health
    end

    desc "search QUERY", "Full-text search the corpus (FTS5 over folded text)"
    long_desc <<~HELP, wrap: false
      Full-text search over every live passage, bm25-ranked. Matching is
      diacritic- and case-insensitive on BOTH sides: μηνιν finds μῆνιν,
      ΜΗΝΙΝ finds both — type without accents, breathings, or iota
      subscripts and still hit the polytonic editions.

      Query syntax (SQLite FTS5 over the folded text):
        μηνιν αειδε          all words must appear in the passage (implicit AND)
        '"μηνιν αειδε"'      exact adjacent phrase — FTS quotes, so shell-quote them
        μηνι*                prefix match (μῆνιν, μηνίω, μήνιμα, …)
      Boolean OR/NOT are not supported: operators are folded to lowercase
      and become ordinary search terms.

      Each hit prints the passage urn, its language, and a folded snippet
      with the match in [brackets]. The snippet is the SEARCH form, not the
      edition text — `nabu show <urn>` gives the pristine passage. DDbDP
      papyri render lost text as the […] gap marker.

      Filters (combinable):
        --lang     ISO-639-3 passage language: grc, lat, got, chu, orv, san, …
        --license  effective license class (document override beats source):
                   open, attribution, nc, research_private, restricted
        --limit    maximum hits, default 20

      LEMMA SEARCH (--lemma FORM): exact dictionary-form lookup over the
      gold treebank annotations (UD, PROIEL, TOROT — the sources that carry
      per-token lemmas). One lemma finds every inflected attestation, even
      suppletive stems no text query can reach: --lemma λέγω hits λέγουσι,
      λέγοιεν, AND εἶπας/εἰπεῖν. Hits show the dictionary form, the surface
      form(s) that matched, and the pristine passage line. Diacritics are
      optional on the query, exactly as in text search (λεγω works; so does
      final-sigma-insensitive λόγος/λογοσ). --lemma REPLACES the text query
      (combining both is not supported); it composes with --lang, --limit,
      and --license. Passages outside the treebanks carry no lemma
      annotations and are honestly absent here.

      MORPH FACETS (--morph case=dat,number=pl): with --lemma, narrow to
      attestations whose morphology matches the given facets (comma-joined
      key=value, all required). The vocabulary is Universal Dependencies
      feature names — case, number, gender, person, tense, mood, voice,
      degree (values dat, pl/sg, masc, aor, opt, sub…); UD treebanks match on
      their `feats`, PROIEL/TOROT are decoded from their positional tag into
      the same names. Each hit shows the matching surface form(s) and the
      decoded morph evidence. --morph REQUIRES --lemma (bare morphology search
      is out of scope); ORACC carries no inflectional morphology, so
      inflectional facets never match it (honest absence). See conventions §6.1.

      PROXIMITY (A --near B [--window N]): keep only hits where B occurs
      within N words of A in the SAME passage — λόγος near θεός is John 1:1.
      Built on FTS5 NEAR over the folded search forms: --window N is the max
      words BETWEEN the two terms (default 10; 0 = immediately adjacent), and
      NEAR is order-independent (A…B and B…A both count). The window counts
      folded tokens, so for cuneiform (akk/sux), where sign-joins and
      determinatives fold to spaces, one transliterated word spans several
      tokens and the window reads tighter. --near composes with --lemma (the
      anchor then expands to the lemma's attested surface forms before the
      NEAR: --lemma λέγω --near κύριος finds εἶπε near κύριος too), and with
      --lang/--license/--limit. Cross-passage adjacency is OUT — the passage
      is the unit. --morph does not compose with --near (out of scope). Both
      matched terms are bracketed in the snippet.

      Sources ingesting parallel translations (registry `translations: true`,
      P7-4) make those English passages ordinary search hits; --lang eng
      scopes to them, --lang grc keeps them out. `show <hit> --parallel`
      jumps from either side to the aligned line in the other.

      Examples:
        nabu search μηνιν                          # finds μῆνιν, accents optional
        nabu search '"ανδρα μοι εννεπε"'           # Odyssey 1.1 — including the
                                                   #   papyri that quote it
        nabu search sapientia --lang lat           # Latin corpus only
        nabu search μηνι* --lang grc               # every derivative of the stem
        nabu search αγαπη --license attribution    # only freely re-usable hits
        nabu search "rich-haired" --lang eng       # the ingested translations
        nabu search --lemma λέγω --lang grc        # every attestation in the Greek
                                                   #   treebank: λέγουσι, εἶπας, εἰπεῖν…
        nabu search --lemma tu --lang lat          # te, tibi, tu across PROIEL Cicero
        nabu search --lemma λόγος --morph case=dat,number=pl
                                                   # only the dative-plural λόγοις
        nabu search λόγος --near θεός --window 5    # λόγος within 5 words of θεός
                                                   #   (John 1:1 and its kin)
        nabu search --lemma λέγω --near κύριος      # every inflection of λέγω
                                                   #   near κύριος: τάδε λέγει κύριος

      Use cases: find a half-remembered line; concordance-style scans of a
      word across six corpora at once; checking which sources attest a term
      (and under what license) before an export.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of hits"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma search over the gold treebanks (replaces the text query)"
    option :morph, type: :string, banner: "FACETS",
                   desc: "Morphology facets (with --lemma), e.g. case=dat,number=pl"
    option :near, type: :string, banner: "TERM",
                  desc: "Proximity: keep only hits where TERM is within --window words of the query/lemma"
    option :window, type: :numeric, default: Nabu::Query::Proximity::DEFAULT_WINDOW,
                    desc: "Max words between the two --near terms (default " \
                          "#{Nabu::Query::Proximity::DEFAULT_WINDOW}; 0 = adjacent)"
    def search(query = nil)
      query = query.to_s.strip
      return proximity_search(query) if options[:near]
      return lemma_search(query) if options[:lemma]
      raise Thor::Error, "search: --morph requires --lemma (bare morphology search is out of scope)" if options[:morph]
      raise Thor::Error, "search: give a query" if query.empty?

      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      # Either half of the derived store missing means the corpus was never
      # built/indexed; a search cannot run.
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext

      results = Nabu::Query::Search.new(catalog: catalog, fulltext: fulltext)
                                   .run(query, lang: options[:lang], license: options[:license],
                                               limit: options[:limit].to_i)
      print_search_results(results)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "concord QUERY", "Concordance (KWIC): keyword-in-context lines, one per hit"
    long_desc <<~HELP, wrap: false
      Keyword-in-context concordance: every hit as one line — left context, the
      matched keyword, right context — with the keyword aligned in a fixed
      column so you can scan a word's usage down the page. The keyword is
      located in the PRISTINE edition text (accents and all), not the folded
      search form: a concordance is for reading real usage.

      Matching is exactly `nabu search`: diacritic- and case-insensitive on both
      sides (μηνιν finds μῆνιν), implicit-AND multiple words, "quoted phrase",
      prefix* — and --lemma FORM for exact dictionary-form lookup over the gold
      treebanks (finds every inflected attestation). Rows come in CORPUS order
      (urn/citation), not relevance order — the point is scanning, not ranking.
      One row per passage: a passage with the keyword twice shows its first
      occurrence.

      Layout: left context is trimmed to --width characters per side (default
      40) and right-justified so the keyword column lines up; the right context
      is trimmed to the same width; clipped context is marked with …. Each row
      ends with the passage urn and [language]. Alignment counts display
      characters (fine for grc/lat/chu); it does not model East-Asian width.

      Filters (as in search): --lang, --license, --limit (default 20).

      Examples:
        nabu concord μῆνιν                       # every attestation of μῆνιν, KWIC
        nabu concord μηνιν --width 30            # tighter context, accents optional
        nabu concord ἄειδε --lang grc --limit 50
        nabu concord --lemma λέγω --lang grc     # every inflection in context:
                                                 #   λέγουσι, εἶπας, εἰπεῖν…
        nabu concord sapientia --lang lat        # a Latin word across the corpus

      Use cases: see how a word is actually used across six corpora at once;
      spot collocations and formulae; build a hand concordance for a term before
      writing about it.
    HELP
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    option :limit, type: :numeric, default: 20, desc: "Maximum number of KWIC lines"
    option :width, type: :numeric, default: Nabu::Query::Concord::DEFAULT_WIDTH,
                   desc: "Context characters per side (default #{Nabu::Query::Concord::DEFAULT_WIDTH})"
    option :lemma, type: :string, banner: "FORM",
                   desc: "Exact-lemma concordance over the gold treebanks (replaces the text query)"
    def concord(query = nil)
      query = query.to_s.strip
      lemma = options[:lemma]
      if lemma
        raise Thor::Error, "concord: --lemma replaces the text query — give one or the other" unless query.empty?

        lemma = lemma.strip
        raise Thor::Error, "concord: --lemma needs a lemma" if lemma.empty?
      elsif query.empty?
        raise Thor::Error, "concord: give a query"
      end

      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      rows = Nabu::Query::Concord.new(catalog: catalog, fulltext: fulltext).run(
        query.empty? ? nil : query, lemma: lemma, lang: options[:lang],
                                    license: options[:license], limit: options[:limit].to_i, width: options[:width].to_i
      )
      print_concord_rows(rows)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "show URN", "Show a passage or document by urn (withdrawn items shown, flagged)"
    long_desc <<~HELP, wrap: false
      Inspect one passage or one whole document by urn. Unlike search and
      export, show hides nothing: withdrawn and retired-upstream items
      appear too, honestly labeled — this is the "what does my collection
      actually hold" lens.

      A PASSAGE urn prints the pristine text, its document, effective
      license, revision, and the full provenance trail (loaded / revised /
      withdrawn / restored / retired events with timestamps) — the
      passage's complete life story.

      A DOCUMENT urn prints the header (title, language, source, license,
      revision, any withdrawn/retired flag) and every passage in citation
      order, listed as :suffixes relative to the document urn printed once
      above; --full-urn restores absolute urns for copy-paste. Long
      documents: pipe to less.

      urn shapes across the corpus:
        CTS editions   urn:cts:greekLit:tlg0012.tlg002.perseus-grc2       (document)
                       urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1   (book 1, line 1)
        papyri (DDbDP) urn:nabu:ddbdp:aegyptus:89:240:b2:5
                       (:b2 = implicit restart block — an unlabeled column/
                        fragment where the edition's line numbers restart)
        treebanks      urn:nabu:proiel:afnik:194690                     (sentence)
                       urn:nabu:ud:gothic-proiel:got_proiel-ud-dev:37589

      RANGES (URN:<start>-<end>): a document urn plus two citation suffixes
      joined by a hyphen prints an INCLUSIVE, sequence-ordered slice of that
      one document between the endpoints — both endpoints must resolve to
      existing passages of the same document (a clear error names whichever
      fails; a start after its end is refused, suggesting a swap). The slice
      is by STORED sequence, whatever citation shapes lie between: a papyri
      restart block (:b2, an implicit column/fragment) is sliced straight
      through. Precedence: a literal passage urn is resolved FIRST, so a urn
      that itself contains a hyphen is never misparsed as a range; the range
      split is on the LAST hyphen (citation suffixes never contain one, the
      version segment perseus-grc2 does). Ranges compose with --full-urn and
      with --parallel (the range slices the queried edition; pairing then
      applies to the sliced rows only).

      PARALLEL TRANSLATIONS (--parallel [LANG], default eng): for a CTS
      document or passage urn — or an ORACC tablet, whose translation is the
      -en sibling document (P13-4) — find the sibling edition of the SAME
      work in LANG (sources ingest translations only when their registry
      entry sets `translations: true`) and render the two SPAN-GROUPED by
      citation suffix. A verse-for-verse translation pairs line by line —
      :1.1 Greek next to :1.1 English. A card-cited prose translation (both
      English Homers) anchors one block of text at a card's first line: the
      original lines are listed, then the translation ONCE, labeled with its
      coverage in the original's numbering (`eng [:1.1 — covers :1.1–:1.43]`)
      plus a clip note when a range shows only part of a card. ORACC's
      paragraph-grained SAA units render as exactly such blocks over the
      tablet's o.1/r.5 lines. A suffix present in only one edition renders
      honestly one-sided, never fuzzed. Works with --full-urn.

      Examples:
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.1
        nabu show urn:cts:greekLit:tlg0012.tlg001.perseus-grc2:1.1-1.10
                                                  # Iliad 1.1–1.10, one slice
        nabu show urn:nabu:ddbdp:aegyptus:89:240:1-b2:2
                                                  # a papyrus slice across a restart block
        nabu show urn:nabu:ddbdp:aegyptus:89:240            # whole papyrus
        nabu show urn:nabu:ddbdp:aegyptus:89:240 --full-urn # absolute urns
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-grc2 --parallel
                                                  # Greek + eng, line by line
        nabu show urn:cts:greekLit:tlg0012.tlg002.perseus-grc2:1.5-1.10 --parallel
                                                  # a mid-card slice: the eng block labeled
                                                  #   "covers :1.1–:1.43; range shows :1.5–:1.10"
        nabu show urn:cts:greekLit:tlg0013.tlg013.perseus-eng2:1 --parallel grc
                                                  # one translated line + its original

      Use cases: read the real edition text behind a search snippet; audit
      a document's revision/provenance history after a sync; eyeball what
      "withdrawn" or "retired upstream" actually holds; read a Greek work
      you can't sight-read next to its English translation.
    HELP
    option :full_urn, type: :boolean, default: false,
                      desc: "List document passages with absolute urns instead of :suffixes"
    option :parallel, type: :string, lazy_default: "eng", banner: "[LANG]",
                      desc: "Align with the same work's LANG edition by citation suffix (default eng)"
    option :random, type: :boolean, default: false,
                    desc: "Show random passages instead of a urn (the eyeball ritual at a source flip)"
    option :source, type: :string, banner: "SLUG",
                    desc: "With --random: draw only from this source (default: the whole corpus)"
    option :count, type: :numeric, default: 1,
                   desc: "With --random: how many passages (default 1, cap #{Nabu::Query::Random::MAX_COUNT})"
    def show(urn = nil)
      urn = urn.to_s.strip
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      return show_random(catalog, urn) if options[:random]
      raise Thor::Error, "show: --source requires --random" if options[:source]
      raise Thor::Error, "show: give a urn" if urn.empty?

      return show_parallel(catalog, urn, options[:parallel], config) if options[:parallel]

      result = Nabu::Query::Show.new(catalog: catalog).run(urn)
      raise Thor::Error, "urn not found: #{urn}" if result.nil?

      print_show(result)
    rescue Nabu::Query::Range::Error, Nabu::Query::Random::Error => e
      # A range urn that names two endpoints but can't be honoured (endpoint
      # missing, or reversed), or an unknown --random --source: a clean stderr
      # message + exit 1.
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
    end

    desc "align REF", "Render one citation across every witness of a registered work (the alignment hub)"
    long_desc <<~HELP, wrap: false
      Cross-source alignment (architecture §10): one citation of a registered
      WORK rendered in every witness the alignment registry
      (config/alignments.yml) names — the same verse in Greek, Latin, Gothic,
      Classical Armenian, and Old Church Slavonic, in one screen. Witnesses
      render in registry order, each with its language and its EFFECTIVE
      license class (the five NT witnesses are all nc — mind the labels when
      quoting).

      REF is a citation in the work's scheme — for the `nt` work,
      BOOK chapter.verse ("MARK 2.3"; quote it or let Thor join the words).
      Matching is forgiving: case, extra spaces, and chapter:verse colons all
      normalize ("mark 2:3" finds MARK 2.3). REF may also be a PASSAGE URN
      (pivot from a show/search hit): the sentence's verse is looked up and
      aligned across the other witnesses.

      Alignment is at citation grain over the treebanks' verse annotations,
      and sentence≠verse: a witness's sentence that spans a verse boundary is
      shown once, labeled with everything it covers. Honesty rules: a witness
      that simply lacks the verse (the Armenian sample holds only scattered
      chapters; Gothic is fragmentary) reads "not attested"; a registered
      witness whose source was never synced reads "not synced". Adding a
      witness (say, the ISWOC Old English Mark) is a registry entry, not code.

      --work names the work explicitly. Without it, a ref resolves through
      the index: when exactly one registered work attests it, that work is
      picked automatically (nt for "MARK 2.3", ot for "GEN 1.1"); a ref
      several works attest asks you to pick among the attesters.

      Examples:
        nabu align MARK 2.3                 # the paralytic, five ways
        nabu align "mark 2:3"               # same — refs normalize
        nabu align urn:nabu:proiel:marianus:36421
                                            # pivot: this OCS sentence, aligned
        nabu align MATT 5.25 --work nt      # explicit work id

      Use cases: read the Vorlage beside the translation (THE working method
      of comparative philology); check how each witness renders a
      construction; learn OCS/Gothic against the Greek you can already read.
    HELP
    option :work, type: :string, banner: "ID",
                  desc: "Alignment work id from config/alignments.yml (optional when only one is registered)"
    def align(*ref_parts)
      ref = ref_parts.join(" ").strip
      raise Thor::Error, "align: give a citation ref (e.g. MARK 2.3) or a passage urn" if ref.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog && fulltext

      registry = Nabu::AlignmentRegistry.load(config.alignments_path)
      result = Nabu::Query::Align.new(catalog: catalog, fulltext: fulltext, registry: registry)
                                 .run(ref, work: options[:work])
      print_align(result)
    rescue Nabu::Query::Align::Error, Nabu::ValidationError => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "define LEMMA", "Look up a lemma in the dictionary shelf (LSJ, Lewis & Short, Bosworth-Toller, Wiktionary-OCS)"
    long_desc <<~HELP, wrap: false
      The dictionary shelf (architecture §11): look a dictionary form up in
      the lexica the corpus holds locally — LSJ (A Greek-English Lexicon,
      grc) and Lewis & Short (A Latin Dictionary, lat), both CC BY-SA from
      the Perseus Digital Library, Bosworth-Toller (An Anglo-Saxon
      Dictionary, ang; CC BY 4.0, LINDAT dump), and Wiktionary Old Church
      Slavonic (chu; kaikki.org extract, CC-BY-SA + GFDL — etymologies with
      their Proto-Slavic/PIE chains kept in the body). Entries print whole:
      headword, short gloss, then the full entry body as structured plain
      text with sense labels on their own lines (the MCP nabu_define surface
      is the bounded sibling).

      Matching folds like lemma search (conventions §9): diacritics optional
      (μηνις finds μῆνις), final sigma both ways (λόγος/λογοσ), Latin v/u j/i
      merged, Old English æ/þ/ð typeable in ASCII (aethele finds æðele,
      thing finds þing). Homographs are separate entries and all print (volo
      the verb, volo the flyer). LEMMA must be a dictionary form —
      `nabu search --lemma` finds the attestations, and its hits carry these
      glosses.

      Citations inside an entry stay as text; those that point at a work THIS
      corpus holds are additionally resolved to passage urns and listed at
      the end of the entry — `nabu show <urn>` opens the cited line. LSJ
      cites editions we may not hold (perseus-grc1 vs our grc2); resolution
      re-anchors to the in-catalog edition of the same work, preferring the
      original language over translations. Unresolvable citations (works not
      ingested, inscriptions, fragment collections) are honest misses, not
      links.

      The reconstruction shelves (P14-1, architecture §12) join in with the
      comparativist's asterisk: `define *bogъ` scopes to the Wiktionary
      Proto-Slavic/PIE/Proto-Germanic extracts (sla-pro/ine-pro/gem-pro),
      and a reconstruction entry also lists its descendant reflexes — with
      corpus attestation counts where the reflex is a gold lemma here.
      `nabu etym` walks the same crosswalk from the attested side.

      --lang grc|lat|ang|chu|sla-pro|ine-pro|gem-pro restricts to one
      shelf; --limit caps the entries.

      Examples:
        nabu define μῆνις              # LSJ: wrath — with Il. 1.1 resolved
        nabu define λόγος              # the long one, whole
        nabu define virtus --lang lat  # Lewis & Short only
        nabu define aethele --lang ang # Bosworth-Toller: æðele, noble
        nabu define богъ --lang chu    # Wiktionary-OCS: god, ex Proto-Slavic *bogъ
        nabu define *bogъ              # the reconstruction, with its reflexes
    HELP
    DEFINE_LANGS = %w[grc lat ang chu sla-pro ine-pro gem-pro].freeze
    option :lang, type: :string, banner: "grc|lat|ang|chu|sla-pro|ine-pro|gem-pro",
                  desc: "Dictionary language: grc → LSJ, lat → Lewis & Short, " \
                        "ang → Bosworth-Toller, chu → Wiktionary-OCS, " \
                        "sla-pro/ine-pro/gem-pro → the reconstruction shelves"
    option :limit, type: :numeric, default: Nabu::Query::Define::DEFAULT_LIMIT,
                   desc: "Maximum entries printed (homographs are separate entries)"
    def define(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "define: give a lemma (e.g. λόγος, virtus)" if lemma.empty?
      if options[:lang] && !DEFINE_LANGS.include?(options[:lang])
        raise Thor::Error, "define: --lang must be one of #{DEFINE_LANGS.join(', ')}"
      end

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_entries)
        raise Thor::Error, "no dictionary shelf in this catalog yet — run nabu sync lexica " \
                           "(or nabu rebuild after one)"
      end

      fulltext = open_fulltext(config)
      results = Nabu::Query::Define.new(catalog: catalog, fulltext: fulltext)
                                   .run(lemma, lang: options[:lang], limit: options[:limit].to_i)
      print_define_results(lemma, results)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "etym LEMMA", "Walk an attested lemma to its reconstructions and cognates (architecture §12)"
    long_desc <<~HELP, wrap: false
      The comparativist's walk: from an ATTESTED lemma (богъ, guþ, deus) to
      every reconstruction whose Wiktionary descendants name it —
      Proto-Slavic, Proto-Indo-European, Proto-Germanic (kaikki.org
      extracts, CC-BY-SA + GFDL) — then one hop UP the proto-to-proto
      chain: a Proto-Slavic entry's PIE root prints with ITS cognates, so
      богъ reaches *bogъ, *bʰeh₂g- and ἔφᾰγον in one command.

      Every cognate reflex that is a gold lemma in this catalog carries its
      attestation count (searchable via `nabu search --lemma`); the rest
      are listed honestly as "not attested here". Romanization bridges
      scripts — guþ reaches *gudą through Gothic 𐌲𐌿𐌸 — and the folding is
      the conventions §9 contract (diacritics optional).

      A leading asterisk looks a reconstruction up directly (`etym *bogъ`),
      exactly like `define *bogъ` but with the walk attached. --lang scopes
      the attested match to one language; --limit caps the entries. The MCP
      sibling is nabu_etym (bounded); this CLI prints everything.

      Examples:
        nabu etym богъ --lang chu     # Zographensis god → *bogъ → *bʰeh₂g-
        nabu etym guþ --lang got      # Gothic → *gudą → *ǵʰutós
        nabu etym *kaisaraz           # the Caesar loan chain, top down
    HELP
    option :lang, type: :string, banner: "chu|orv|got|grc|lat|…",
                  desc: "Scope the attested-lemma match to one language"
    option :limit, type: :numeric, default: Nabu::Query::Etym::DEFAULT_LIMIT,
                   desc: "Maximum reconstruction entries printed"
    def etym(*lemma_parts)
      lemma = lemma_parts.join(" ").strip
      raise Thor::Error, "etym: give a lemma (e.g. богъ, guþ) or *reconstruction" if lemma.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no corpus — run nabu sync or nabu rebuild" unless catalog
      unless catalog.table_exists?(:dictionary_reflexes)
        raise Thor::Error, "no reconstruction shelf in this catalog yet — run " \
                           "nabu sync wiktionary-recon (or nabu rebuild after one)"
      end

      fulltext = open_fulltext(config)
      results = Nabu::Query::Etym.new(catalog: catalog, fulltext: fulltext)
                                 .run(lemma, lang: options[:lang], limit: options[:limit].to_i)
      print_etym_results(lemma, results)
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "vocab URN", "Lemma-frequency profile of a document/range vs the corpus (gold shelves only)"
    long_desc <<~HELP, wrap: false
      Profile the gold-lemma vocabulary of one document, a citation range, or a
      single passage (P14-3, improvements §1.7): total tokens carrying a gold
      lemma, how many distinct lemmas, the most DISTINCTIVE vocabulary, and the
      in-document hapax legomena (lemmas attested exactly once).

      "Distinctive" means over-represented HERE versus the whole corpus, ranked
      by a log-odds-ratio with an informative Dirichlet prior (Monroe et al.
      2008) — the z-score damps rare-lemma noise a plain frequency ratio would
      let blow up, so the list is the text's real subject vocabulary, not its
      accidental singletons (those get their own hapax line). Each row shows the
      lemma's document token count and its corpus passage-frequency.

      Gold lemmas exist only for the treebank shelves (PROIEL, TOROT, ISWOC, the
      UD treebanks) and the ORACC cuneiform layer — about 8% of the corpus. A
      document without gold lemmas (Perseus, First1K, the papyri, ASPR poetry)
      is not an error: it says so plainly and lists the gold-bearing languages
      so you can profile something that works. --limit caps both the distinctive
      list and the hapax spellings printed (default #{Nabu::Query::Vocab::DEFAULT_LIMIT}).

      Examples:
        nabu vocab urn:nabu:proiel:caes-gal          # Caesar's Gallic War
        nabu vocab urn:nabu:proiel:cic-off --limit 30
        nabu vocab urn:nabu:proiel:hdt:1.1-1.100     # a citation range
    HELP
    option :limit, type: :numeric, default: Nabu::Query::Vocab::DEFAULT_LIMIT,
                   desc: "Cap the distinctive list and hapax spellings printed"
    def vocab(urn = nil)
      urn = urn.to_s.strip
      raise Thor::Error, "vocab: give a document, range, or passage urn" if urn.empty?

      config = Nabu::Config.load
      catalog = open_catalog(config)
      fulltext = open_fulltext(config)
      raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
      unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
        raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                           "run nabu sync or nabu rebuild"
      end

      profile = Nabu::Query::Vocab.new(catalog: catalog, fulltext: fulltext)
                                  .run(urn, limit: options[:limit].to_i)
      print_vocab(profile)
    rescue Nabu::Query::Vocab::NotFound, Nabu::Query::Range::Error => e
      raise Thor::Error, e.message
    ensure
      catalog&.disconnect
      fulltext&.disconnect
    end

    desc "mcp", "Serve the corpus to an AI client over MCP (stdio, read-only) — see docs/mcp.md"
    long_desc <<~HELP, wrap: false
      Run the Model Context Protocol server on stdin/stdout: a READ-ONLY
      conversational surface over the local nabu corpus, exposing seven tools —
      nabu_search (full-text + exact-lemma), nabu_show (read by urn, ranges,
      parallel translations), nabu_concord (KWIC), nabu_align (cross-source
      citation alignment), nabu_define (the dictionary shelf: LSJ + Lewis &
      Short), nabu_etym (the reconstruction crosswalk), and nabu_status
      (coverage) — to any MCP client (Claude Code, Claude Desktop). The catalog and index are opened
      SQLITE_OPEN_READONLY: this process is POSITIVELY unable to write to db/.

      This is a plumbing command, not an interactive one. STDOUT IS THE PROTOCOL
      CHANNEL — it carries newline-delimited JSON-RPC and nothing else.
      Diagnostics go to stderr, or appended to a file with --log FILE. The
      openers are lazy and read-only, so a corpus that appears or is rebuilt
      mid-session is picked up without a restart. The server runs until stdin
      closes (EOF) or it is signalled (SIGINT/SIGTERM), then exits 0.

      You normally never type this yourself — a client spawns it. This repo ships
      .mcp.json, so opening Claude Code in the repo registers nabu automatically.
      User-scope, Claude Desktop, the tool reference, the license/attribution
      stance, and an example transcript are in docs/mcp.md.

      Examples:
        nabu mcp                       # a client spawns this; speaks JSON-RPC on stdio
        nabu mcp --log /tmp/nabu-mcp.log   # tee diagnostics to a file (stdout stays clean)
    HELP
    option :log, type: :string, banner: "FILE",
                 desc: "Append diagnostics to FILE instead of stderr (stdout is the protocol channel)"
    def mcp
      config = Nabu::Config.load
      log = mcp_log(options[:log])
      # Lazy, memoizing, read-only openers (Procs, per the Tools contract):
      # resolved on every tool call, so a corpus that appears or is rebuilt
      # mid-session is picked up without a restart. nil when the file is absent
      # (Tools renders the graceful "no corpus" / "rebuilding" states).
      tools = Nabu::MCP::Tools.new(
        catalog: readonly_opener(config.catalog_path) { Nabu::Store.connect(config.catalog_path, readonly: true) },
        fulltext: readonly_opener(config.fulltext_path) do
          Nabu::Store.connect_fulltext(config.fulltext_path, readonly: true)
        end,
        # Static config, loaded once — a malformed registry fails HERE, loudly,
        # not mid-conversation.
        alignments: Nabu::AlignmentRegistry.load(config.alignments_path)
      )
      $stdout.sync = true
      install_mcp_signal_traps
      # stdout carries protocol only; every diagnostic goes to the log IO.
      Nabu::MCP::Server.new(tools: tools, log: log).run($stdin, $stdout)
    ensure
      log.close if log && !log.equal?($stderr)
    end

    desc "export", "Stream non-withdrawn passages as plain text or JSONL"
    long_desc <<~HELP, wrap: false
      Stream the live corpus to stdout, one passage per line — the
      longevity-hedge exit formats: the data must survive the code.
      Withdrawn passages are excluded; retired-upstream documents are
      INCLUDED (they are part of your collection — that is the point of
      keeping them). Streaming end to end: constant memory at any corpus
      size, so piping a million passages is fine.

      Formats:
        plain   text only, internal newlines collapsed to one space
        jsonl   one JSON object per line: urn, language, text,
                text_normalized, annotations — annotations is a real nested
                object carrying lemmas/morphology where the source provides
                them (the treebanks: UD, PROIEL, TOROT)
        conllu  arrives with the enrichment phase (needs the token model)

      Same --lang / --license filters as search.

      Examples:
        nabu export --format plain --lang got > gothic.txt
        nabu export --format jsonl --license open | jq -r .urn
        nabu export --format jsonl --lang chu | jq '.annotations' | head

      Use cases: feed a corpus slice to external NLP tooling; a license-clean
      subset for anything you plan to publish; plain-text dumps for grep-scale
      workflows or personal backups independent of nabu itself.
    HELP
    option :format, type: :string, required: true, desc: "plain | jsonl"
    option :lang, type: :string, desc: "Restrict to a passage language (e.g. grc, lat)"
    option :license, type: :string,
                     desc: "Restrict to an exact license class (open, attribution, nc, …)"
    def export
      format = validate_format!(options[:format])
      validate_license!(options[:license])
      config = Nabu::Config.load
      catalog = open_catalog(config)
      raise Thor::Error, "no catalog — run nabu sync or nabu rebuild" unless catalog

      lines = Nabu::Query::Export.new(catalog: catalog)
                                 .run(format: format, lang: options[:lang], license: options[:license])
      # Stream: write each serialized line as it arrives — never join a
      # 238k-passage corpus into one string.
      lines.each { |line| $stdout.puts(line) }
    ensure
      catalog&.disconnect
    end

    desc "backup", "Snapshot canonical/, the history ledger, config/, and the derived dbs to an external volume"
    long_desc <<~HELP, wrap: false
      File-level rsync backup (architecture §8, P7-2) — the concept's promise:
      restorable from a plain rsync copy with zero services running. Backs up
      everything that is NOT re-derivable:

        canonical/   the permanent asset, INCLUDING every .attic/ (upstream-
                     scrapped files that exist nowhere else — a per-slug git
                     mirror would miss them; file-level or nothing)
        db/history.sqlite3   the ledger: run history, sync pins, license
                     baselines, durable revisions (the only copy)
        config/      nabu.yml + sources.yml
        db/catalog + db/fulltext   the derived dbs — included by DEFAULT
                     (a file copy beats an hour of rebuild); --skip-derived omits
                     them (canonical/ + `nabu rebuild` reconstitutes them)

      Target: config/nabu.yml `backup: target:` (a path under a mounted external
      volume), overridable with --to PATH.

      THE MOUNT-POINT GUARD: the target must live on a REAL mounted volume. If
      the volume is not mounted, the path is a bare directory on the boot disk,
      and rsync would silently back up onto it — then shadow the real volume once
      it mounts. backup REFUSES this unless --allow-unmounted (for deliberately
      local targets: the drill, a scratch copy).

      --dry-run prints the rsync plan and changes nothing.

      Examples:
        nabu backup                                   # to the configured volume
        nabu backup --to /Volumes/NabuBackup/nabu     # explicit target
        nabu backup --dry-run                          # show the plan
        nabu backup --skip-derived                     # canonical + ledger + config only
    HELP
    option :to, type: :string, desc: "Target path override (default: config/nabu.yml backup.target)"
    option :skip_derived, type: :boolean, default: false,
                          desc: "Omit the derived dbs (catalog + fulltext); restore rebuilds them"
    option :dry_run, type: :boolean, default: false, desc: "Print the rsync plan and change nothing"
    option :allow_unmounted, type: :boolean, default: false,
                             desc: "Skip the mount-point guard (for a deliberately-local target)"
    def backup
      config = Nabu::Config.load
      result = Nabu::Backup.new(
        config: config, target: options[:to], skip_derived: options[:skip_derived],
        dry_run: options[:dry_run], allow_unmounted: options[:allow_unmounted]
      ).run
      print_backup(result)
      raise Thor::Error, backup_failure_summary(result) unless result.ok?
    rescue Nabu::Backup::Error => e
      # No target, or the mount-point guard tripped: a clean stderr message + exit 1.
      raise Thor::Error, e.message
    end

    no_commands do
      # Reject an unknown --license up front (before opening any db) with the
      # closed enum of valid classes, so the user sees the choices. Shared by
      # search and export.
      def validate_license!(license)
        return if license.nil?
        return if Nabu::SourceManifest::LICENSE_CLASSES.include?(license)

        raise Thor::Error,
              "unknown license #{license.inspect} " \
              "(choose from #{Nabu::SourceManifest::LICENSE_CLASSES.join(', ')})"
      end

      # Export format gate. CoNLL-U is a first-class exit format (maintenance
      # §7) but needs the token model, so it is deferred to the enrichment
      # phase with an explicit message rather than a generic "unknown format".
      def validate_format!(format)
        raise Thor::Error, "export: --format conllu is deferred until the enrichment phase" if format == "conllu"
        return format if Nabu::Query::Export::FORMATS.include?(format)

        raise Thor::Error,
              "export: unknown format #{format.inspect} " \
              "(choose from #{Nabu::Query::Export::FORMATS.join(', ')})"
      end

      # Render `verify`: one line per source (OK with a count, or FAILED with
      # its itemized issues), then any never-synced skips, then a verdict.
      def print_verify(result)
        result.outcomes.each { |outcome| print_verify_outcome(outcome) }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        say(result.clean? ? "All canonical documents verified against the catalog." : "Integrity check FAILED.")
      end

      def print_verify_outcome(outcome)
        if outcome.ok?
          say "  OK      #{outcome.slug}  (#{pluralize(outcome.verified, 'document')} verified)"
        else
          say "  FAILED  #{outcome.slug}  (#{outcome.verified} checked, #{pluralize(outcome.issues.size, 'issue')})"
          outcome.issues.each { |issue| say "    #{format_verify_issue(issue)}" }
        end
      end

      def format_verify_issue(issue)
        case issue.kind
        when :mismatch
          "MISMATCH    #{issue.urn}  stored #{issue.detail.fetch(:stored)[0, 12]} != " \
          "recomputed #{issue.detail.fetch(:recomputed)[0, 12]}  (#{issue.canonical_path})"
        when :missing
          "MISSING     #{issue.urn}  (#{issue.canonical_path})"
        when :unparseable
          "UNPARSEABLE #{issue.urn}  #{issue.detail}  (#{issue.canonical_path})"
        end
      end

      def verify_failure_summary(result)
        "verify: #{pluralize(result.issues.size, 'document')} failed the integrity check"
      end

      def pluralize(count, noun) = "#{count} #{noun}#{'s' unless count == 1}"

      # Render `backup`: the target + mode banner, one line per section (name,
      # status, files/size/duration or the failure detail), then a summary.
      def print_backup(result)
        say "#{result.dry_run ? 'Backup plan (dry run — nothing changes)' : 'Backup'} → #{result.target}"
        result.sections.each { |section| say "  #{format_backup_section(section)}" }
        say "  #{backup_summary(result)}"
      end

      def format_backup_section(section)
        label = section.name.ljust(10)
        case section.status
        when :ok
          "#{label} #{section.status.to_s.ljust(8)} #{pluralize(section.files, 'file')}, " \
          "#{human_bytes(section.bytes)}  (#{format('%.2fs', section.duration)}) → #{section.dest}"
        when :skipped
          "#{label} #{'skipped'.ljust(8)} #{section.detail} (#{section.source})"
        else
          "#{label} #{'FAILED'.ljust(8)} #{section.detail}"
        end
      end

      def backup_summary(result)
        verb = result.dry_run ? "would back up" : "backed up"
        base = "#{verb} #{pluralize(result.files, 'file')}, #{human_bytes(result.bytes)} " \
               "in #{format('%.2fs', result.duration)}"
        result.ok? ? "#{base} — OK" : "#{base} — #{pluralize(result.failed.size, 'section')} FAILED"
      end

      def backup_failure_summary(result)
        "backup: #{pluralize(result.failed.size, 'section')} failed — #{result.failed.map(&:name).join(', ')}"
      end

      def human_bytes(bytes)
        units = %w[B KB MB GB TB]
        size = bytes.to_f
        unit = 0
        while size >= 1024 && unit < units.size - 1
          size /= 1024
          unit += 1
        end
        unit.zero? ? "#{bytes} B" : "#{format('%.1f', size)} #{units[unit]}"
      end

      # `show --random` (P11-9): N random visible passages, each in the standard
      # passage layout — the eyeball ritual at a source flip. A urn alongside
      # --random is contradictory (it picks passages for you); an empty result
      # is an honest note, not an error.
      def show_random(catalog, urn)
        raise Thor::Error, "show: --random takes no urn (it picks passages for you)" unless urn.empty?

        results = Nabu::Query::Random.new(catalog: catalog)
                                     .run(source: options[:source], count: options[:count].to_i)
        if results.empty?
          scope = options[:source] ? " in source #{options[:source]}" : ""
          return say("no passages to show#{scope} (nothing visible — the corpus may be empty or all withdrawn)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          print_show_passage(result)
        end
      end

      # Render `show`: a passage in the context of its document, or a document
      # header plus its passages in sequence. Withdrawn items ARE shown, tagged.
      def print_show(result)
        case result
        when Nabu::Query::Show::PassageResult then print_show_passage(result)
        when Nabu::Query::Show::DocumentResult then print_show_document(result)
        when Nabu::Query::Show::RangeResult then print_show_range(result)
        end
      end

      def print_show_passage(passage)
        say "#{passage.urn}#{" [#{passage.language}]" if passage.language}#{withdrawn_tag(passage.withdrawn)}"
        say "  #{passage.text}"
        say "  document: #{passage.document_urn}#{" — #{passage.document_title}" if passage.document_title}"
        say "  source: #{passage.source_slug}   license: #{passage.license_class}   " \
            "sequence: #{passage.sequence}   revision: #{passage.revision}"
        return if passage.provenance.empty?

        say "  provenance:"
        passage.provenance.each do |event|
          say "    #{event.at}  #{event.event}#{"  #{event.tool}" if event.tool}"
        end
      end

      def print_show_document(document)
        title = document.title ? " — #{document.title}" : ""
        lang = document.language ? " [#{document.language}]" : ""
        say "#{document.urn}#{title}#{lang}#{withdrawn_tag(document.withdrawn)}#{retired_tag(document)}"
        say "  source: #{document.source_slug}   license: #{document.license_class}   revision: #{document.revision}"
        say "  passages (#{document.passages.size}):"
        document.passages.each do |line|
          say "    #{passage_label(document, line)}#{withdrawn_tag(line.withdrawn)}  #{line.text}"
        end
      end

      # Render a range (P7-6): the document header like a document listing, an
      # honest "[N of M passages]" note plus the two endpoint urns, then the
      # inclusive slice as :suffixes (--full-urn restores absolute urns).
      def print_show_range(range)
        title = range.title ? " — #{range.title}" : ""
        lang = range.language ? " [#{range.language}]" : ""
        say "#{range.urn}#{title}#{lang}#{withdrawn_tag(range.withdrawn)}#{retired_tag(range)}"
        say "  source: #{range.source_slug}   license: #{range.license_class}   revision: #{range.revision}"
        say "  range: #{range.start_urn} … #{range.end_urn}  " \
            "[#{range.passages.size} of #{range.total} passages]"
        range.passages.each do |line|
          say "    #{passage_label(range, line)}#{withdrawn_tag(line.withdrawn)}  #{line.text}"
        end
      end

      # Print practice: the document urn appears once in the header, each
      # passage line carries only its changing :suffix (":b2:5"). --full-urn
      # restores absolute urns (copy-paste into `show`/scripts). A passage
      # whose urn doesn't extend the document urn (never minted by our
      # adapters, but data is data) falls back to the full urn.
      def passage_label(document, line)
        return line.urn if options[:full_urn]

        suffix = line.urn.delete_prefix(document.urn)
        suffix == line.urn || suffix.empty? ? line.urn : suffix
      end

      # -- show --parallel (P7-4) ------------------------------------------

      # Resolve + align + render, with the two honest failure modes: unknown
      # urn (exit 1, same message as plain show) and no LANG sibling of the
      # work in the catalog (exit 1, names the language).
      def show_parallel(catalog, urn, lang, config)
        result = Nabu::Query::Parallel.new(catalog: catalog).run(urn, lang: lang)
        raise Thor::Error, "urn not found: #{urn}" if result.nil?
        if result.right.nil?
          raise Thor::Error, "no #{lang} parallel edition of this work in the catalog for #{urn} " \
                             "(--parallel pairs sibling CTS editions WITHIN one source; is " \
                             "`translations: true` set and the source resynced?)#{align_hint(urn, config)}"
        end

        print_parallel(result)
      end

      # Cosmetic rider (P11-8): --parallel's "is translations: true set" hint is
      # misleading for a CROSS-source text (Vulgate/LXX/WEB have no sibling CTS
      # edition to pair). When the urn is a registered alignment witness, point
      # at `nabu align` instead — the hub built for exactly this.
      def align_hint(urn, config)
        registry = Nabu::AlignmentRegistry.load(config.alignments_path)
        witnessed = registry.works.any? do |work|
          work.witnesses.any? do |witness|
            witness.document_urns.any? { |doc| urn == doc || urn.start_with?("#{doc}:") }
          end
        end
        witnessed ? " — this text is an alignment-hub witness; try `nabu align REF` for cross-source alignment" : ""
      rescue Nabu::ValidationError
        ""
      end

      # Render the alignment (P8-1b span-grouped): both document headers, the
      # paired/blocks/one-sided counts, then one span-group at a time. A verse
      # pair keeps the compact pair form (byte-identical to pre-P8-1b); a coarse
      # block prints the original lines first, then the translation once with
      # its full coverage (and a clip note when a slice shows only part of it);
      # one-sided rows dash the missing side. Withdrawn passages are shown,
      # tagged (show-family).
      def print_parallel(result)
        say format_parallel_side(result.left)
        say "  parallel: #{format_parallel_side(result.right)}"
        say "  #{parallel_counts(result)}"
        width = [result.left.language.to_s.length, result.right.language.to_s.length].max + 2
        result.groups.each { |group| print_parallel_group(group, result, width) }
      end

      def print_parallel_group(group, result, width)
        case group.kind
        when :pair        then print_parallel_pair(group, result, width)
        when :block       then print_parallel_block(group, result, width)
        when :original    then print_parallel_one_sided(group, result, width, side: :left)
        when :translation then print_parallel_one_sided(group, result, width, side: :right)
        end
      end

      # Verse pair / one-sided rows: the pre-P8-1b two-line form, the suffix (or
      # absolute urn under --full-urn) over one line per language, "—" for the
      # absent side. Kept byte-identical so verse-for-verse output never shifts.
      def print_parallel_pair(group, result, width)
        line = group.originals.first
        say "  #{options[:full_urn] ? line.urn : group.anchor}"
        say "    #{parallel_line(result.left.language, line, width)}"
        say "    #{parallel_line(result.right.language, group.translation, width)}"
      end

      def print_parallel_one_sided(group, result, width, side:)
        present = side == :left ? group.originals.first : group.translation
        say "  #{options[:full_urn] ? present.urn : present.suffix}"
        left = side == :left ? present : nil
        right = side == :right ? present : nil
        say "    #{parallel_line(result.left.language, left, width)}"
        say "    #{parallel_line(result.right.language, right, width)}"
      end

      # Coarse block: each owned original as a suffix-labeled left line, then
      # the translation once, labeled with its full coverage in the original's
      # numbering plus a clip note when the shown slice is only part of it.
      def print_parallel_block(group, result, width)
        group.originals.each do |line|
          say "  #{options[:full_urn] ? line.urn : line.suffix}"
          say "    #{parallel_line(result.left.language, line, width)}"
        end
        say "  #{result.right.language} #{block_coverage(group)}"
        say "    #{group.translation.text}#{withdrawn_tag(group.translation.withdrawn)}"
      end

      # `[:1.1 — covers :1.1–:1.43; range shows :1.5–:1.10]` — the anchor, the
      # full ownership span, and (only when clipped) the shown sub-range.
      def block_coverage(group)
        covers = "covers #{group.covers_first}–#{group.covers_last}"
        clip = group.clipped ? "; range shows #{group.shown_first}–#{group.shown_last}" : ""
        "[#{group.anchor} — #{covers}#{clip}]"
      end

      # -- align (P11-3) ----------------------------------------------------

      # Render the cross-source alignment: the ref + work header with an
      # honest attestation count, then one block per witness in registry
      # order — title, language, license label, and the sentences (urn line,
      # text line), a multi-verse sentence labeled with its full span.
      def print_align(result)
        return print_align_range(result) if result.is_a?(Nabu::Query::Align::RangeResult)

        attesting = result.witnesses.count { |witness| witness.status == :ok }
        say "#{result.ref} — #{result.title}"
        say "  #{attesting} of #{result.witnesses.size} witnesses attest this ref"
        result.witnesses.each { |witness| print_align_witness(witness, result.ref) }
      end

      # A range/chapter query (P11-8): the query header, a one-line witness
      # legend (title/lang/license shown ONCE, not repeated per ref), then one
      # compact block per ref in document order — ref line, then one line per
      # witness (its text, or an honest not-attested/not-synced dash).
      def print_align_range(result)
        say "#{result.query} — #{result.title}"
        say "  #{result.total} refs; witnesses: #{align_range_legend(result).join('; ')}"
        say "  #{absent_range_summary(result.absent)}" unless result.absent.empty?
        if result.truncated
          say "  showing first #{result.groups.size} of #{result.total} refs " \
              "(cap #{Nabu::Query::Align::MAX_REFS}) — narrow the range"
        end
        result.groups.each { |group| print_align_range_group(group) }
      end

      # P11-9: witnesses absent from every rendered ref are summarized here once
      # (grouped by reason) rather than dashed on every ref line — the owner's
      # readability fix. Partially-attested witnesses stay in the per-ref blocks.
      def absent_range_summary(absent)
        by_reason = absent.group_by(&:reason)
        parts = []
        if (rows = by_reason[:not_attested])
          parts << "not attested in this range: #{rows.map(&:label).join(', ')}"
        end
        if (rows = by_reason[:not_synced])
          parts << "not synced: #{rows.map(&:label).join(', ')}"
        end
        parts.join("; ")
      end

      # One legend entry per witness (registry order): its language + license
      # from the richest view across the shown refs, or "not synced" when the
      # witness holds no data anywhere in the range.
      def align_range_legend(result)
        result.groups.first.witnesses.map(&:label).map do |label|
          views = result.groups.map { |group| group.witnesses.find { |witness| witness.label == label } }
          synced = views.find { |witness| witness.status != :not_synced }
          if synced
            "#{label} [#{synced.language}] license: #{synced.license_class}#{align_numbering_note(synced)}"
          else
            "#{label} not synced"
          end
        end
      end

      def print_align_range_group(group)
        say ""
        say group.ref
        group.witnesses.each { |witness| print_align_range_witness(witness, group.ref) }
      end

      def print_align_range_witness(witness, ref)
        case witness.status
        when :not_synced then say "    #{witness.label} — not synced"
        when :no_match   then say "    #{witness.label} — not attested"
        else
          witness.sentences.each do |sentence|
            say "    #{witness.label}  #{sentence.text}" \
                "#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          end
        end
      end

      def print_align_witness(witness, ref)
        say ""
        if witness.status == :not_synced
          # A nil urn = a multi-book witness whose map lacks this ref's book;
          # naming an unrelated book's urn would mislead — phrase neutrally.
          detail = if witness.document_urn
                     "#{witness.document_urn} is registered but not in the catalog"
                   else
                     "its registered documents are not in the catalog"
                   end
          say "#{witness.label} — not synced (#{detail})"
          return
        end

        # A multi-document witness misses without a book to name — no title.
        say "#{witness.label}#{" — #{witness.title}" if witness.title} [#{witness.language}]   " \
            "license: #{witness.license_class}#{align_numbering_note(witness)}"
        return say "  not attested (this witness lacks #{ref})" if witness.status == :no_match

        witness.sentences.each do |sentence|
          say "  #{sentence.urn}#{align_native_note(witness, sentence)}#{align_span_note(sentence, ref)}"
          say "    #{sentence.text}"
        end
      end

      # "  · Hebrew (Masoretic) numbering" — flags a witness whose psalter is
      # numbered in a different system than the work vocabulary (P13-5), so the
      # reader knows its refs were remapped to align.
      def align_numbering_note(witness)
        witness.numbering ? "   · #{witness.numbering} numbering" : ""
      end

      # "  [Hebrew (Masoretic): PSA 23.1]" — the witness's OWN ref for this
      # sentence, shown only when its numbering diverges from the queried ref.
      def align_native_note(witness, sentence)
        return "" unless sentence.native_ref

        "  [#{witness.numbering}: #{sentence.native_ref}]"
      end

      # "  [covers MARK 2.3, MARK 2.4]" — only when the sentence spans beyond
      # the queried ref (sentence≠verse, stated honestly).
      def align_span_note(sentence, ref)
        return "" if sentence.refs == [ref]

        "  [covers #{sentence.refs.join(', ')}]"
      end

      def format_parallel_side(side)
        "#{side.urn}#{" — #{side.title}" if side.title}#{" [#{side.language}]" if side.language}"
      end

      # Honest grouped arithmetic: paired counts 1:1 verse pairs; the blocks
      # clause (and its owned-line total) appears only when there ARE coarse
      # blocks, so verse-for-verse output stays byte-identical to pre-P8-1b.
      def parallel_counts(result)
        paired = result.groups.count { |group| group.kind == :pair }
        blocks = result.groups.select { |group| group.kind == :block }
        left_only = result.groups.count { |group| group.kind == :original }
        right_only = result.groups.count { |group| group.kind == :translation }
        block_lines = blocks.sum { |group| group.originals.size }
        blocks_clause = blocks_clause(blocks.size, block_lines)
        "aligned by citation: #{paired} paired, #{blocks_clause}" \
          "#{left_only} #{result.left.language} only, #{right_only} #{result.right.language} only"
      end

      # The blocks clause appears only when there ARE coarse blocks, so
      # verse-for-verse output stays byte-identical to the pre-P8-1b header.
      def blocks_clause(blocks, lines)
        return "" if blocks.zero?

        "#{plural(blocks, 'block')} covering #{plural(lines, 'line')}, "
      end

      def plural(count, noun)
        "#{count} #{noun}#{'s' unless count == 1}"
      end

      def parallel_line(language, line, width)
        label = language.to_s.ljust(width)
        return "#{label}—" if line.nil?

        "#{label}#{line.text}#{withdrawn_tag(line.withdrawn)}"
      end

      def withdrawn_tag(withdrawn)
        withdrawn ? "  (withdrawn)" : ""
      end

      # P5-2: upstream scrapped the file; the attic kept it. Live, labeled.
      def retired_tag(document)
        document.retired_upstream ? "  (retired upstream)" : ""
      end

      # Open the fulltext index for reading; nil when the file is absent OR the
      # FTS table was never built (both mean "no index" → the sync/rebuild hint).
      def open_fulltext(config)
        return nil unless File.exist?(config.fulltext_path)

        db = Nabu::Store.connect_fulltext(config.fulltext_path)
        return db if db.table_exists?(Nabu::Store::Indexer::TABLE)

        db.disconnect
        nil
      end

      # Render hits: urn + optional [language] header, then the FTS snippet
      # (diacritic-folded highlight). The footer labels that so nobody reads the
      # stripped accents in the highlight as corpus truth.
      def print_search_results(results)
        return say("no matches") if results.empty?

        results.each do |result|
          say "#{result.urn}#{" [#{result.language}]" if result.language}"
          say "  #{result.snippet}"
        end
        say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} " \
            "(highlights are diacritic-folded)"
      end

      # Render KWIC rows (P8-3): left + keyword + right (each side already
      # trimmed to width by Concord), then the urn + [language] tag. The left
      # context is a fixed width, so keyword columns align down the page.
      def print_concord_rows(rows)
        return say("no matches") if rows.empty?

        rows.each do |row|
          say "#{row.left}#{row.keyword}#{row.right}  #{row.urn}#{" [#{row.language}]" if row.language}"
        end
        say "#{rows.size} #{rows.size == 1 ? 'line' : 'lines'} (KWIC; keyword in pristine text, corpus order)"
      end

      # search --lemma FORM (P7-5): exact-lemma lookup over the treebank lemma
      # index. Replaces the FTS query (simplest honest v1 — combining both is
      # future work); composes with --lang/--license/--limit. A fulltext file
      # predating P7-5 lacks the lemma table, so that gets its own honest hint.
      def lemma_search(positional_query)
        unless positional_query.empty?
          raise Thor::Error, "search: --lemma replaces the text query — give one or the other"
        end

        lemma = options[:lemma].strip
        raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        unless fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        results = Nabu::Query::LemmaSearch.new(catalog: catalog, fulltext: fulltext)
                                          .run(lemma, lang: options[:lang], license: options[:license],
                                                      limit: options[:limit].to_i, morph: options[:morph])
        print_lemma_results(results)
      rescue Nabu::Query::MorphFacets::Error => e
        raise Thor::Error, "search: #{e.message}"
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # search A --near B [--window N] (P14-8): proximity search over the FTS
      # index via FTS5 NEAR. The anchor is the positional query OR --lemma
      # (expanded to attested surface forms); --near B is the second term;
      # --window N is the max folded tokens between them (default 10, 0 =
      # adjacent). Hits render exactly like plain search — the snippet brackets
      # BOTH terms. --morph does not compose (out of scope, said honestly).
      def proximity_search(positional_query)
        near = options[:near].strip
        raise Thor::Error, "search: --near needs a term" if near.empty?
        if options[:morph]
          raise Thor::Error, "search: --morph does not compose with --near " \
                             "(morphology-narrowed proximity is out of scope)"
        end
        window = options[:window].to_i
        raise Thor::Error, "search: --window must be 0 or more" if window.negative?

        lemma = options[:lemma]&.strip
        if options[:lemma]
          unless positional_query.empty?
            raise Thor::Error,
                  "search: --lemma replaces the text query — give one or the other"
          end
          raise Thor::Error, "search: --lemma needs a lemma" if lemma.empty?
        elsif positional_query.empty?
          raise Thor::Error, "search: --near needs an anchor term (a query, or --lemma)"
        end

        validate_license!(options[:license])
        config = Nabu::Config.load
        catalog = open_catalog(config)
        fulltext = open_fulltext(config)
        raise Thor::Error, "no index — run nabu sync or nabu rebuild" unless catalog && fulltext
        if lemma && !fulltext.table_exists?(Nabu::Store::Indexer::LEMMA_TABLE)
          raise Thor::Error, "no lemma index (the fulltext index predates lemma search) — " \
                             "run nabu sync or nabu rebuild"
        end

        results = Nabu::Query::Proximity.new(catalog: catalog, fulltext: fulltext).run(
          query: lemma ? nil : positional_query, lemma: lemma, near: near, window: window,
          lang: options[:lang], license: options[:license], limit: options[:limit].to_i
        )
        print_search_results(results)
      ensure
        catalog&.disconnect
        fulltext&.disconnect
      end

      # Render lemma hits: urn + language, the dictionary form with the surface
      # form(s) that attest it, then the PRISTINE passage line (truncated) —
      # the surface form already marks the match, so readability wins over a
      # folded snippet here.
      def print_lemma_results(results)
        return say("no matches") if results.empty?

        results.each do |result|
          forms = result.surface_forms.empty? ? "(no surface form)" : result.surface_forms
          gloss = result.gloss ? "  (#{result.gloss})" : ""
          morph = result.morph ? "  {#{result.morph}}" : ""
          say "#{result.urn}#{" [#{result.language}]" if result.language}  #{result.lemma} → #{forms}#{gloss}#{morph}"
          say "  #{truncate_line(result.text)}"
        end
        say "#{results.size} #{results.size == 1 ? 'hit' : 'hits'} (exact lemma match; text is pristine)"
      end

      # Render a vocab profile (P14-3): the header (urn, title, language, scope),
      # then either the gold-lemma summary + distinctive table + hapax line, or
      # the honest no-gold-lemmas notice naming the gold-bearing languages.
      def print_vocab(profile)
        header = "#{profile.urn}#{" — #{profile.title}" if profile.title}"
        header += " [#{profile.language}]" if profile.language
        say header
        say "  #{profile.kind}, #{pluralize(profile.passages, 'passage')}"
        return print_vocab_no_gold(profile) if profile.total_tokens.zero?

        say "  gold lemmas: #{commafy(profile.total_tokens)} tokens · " \
            "#{commafy(profile.distinct_lemmas)} distinct lemmas · " \
            "#{commafy(profile.hapax_count)} hapax legomena " \
            "(#{profile.annotated_passages} of #{profile.passages} passages annotated)"
        print_vocab_distinctive(profile.distinctive)
        print_vocab_hapax(profile.hapax, profile.hapax_count)
      end

      # The distinctive-vocabulary table: lemma, its token count here, its corpus
      # passage-frequency, and the log-odds z-score, most distinctive first.
      def print_vocab_distinctive(distinctive)
        return if distinctive.empty?

        say ""
        say "  distinctive vocabulary (log-odds vs corpus, top #{distinctive.size}):"
        width = distinctive.map { |e| e.lemma.length }.max
        distinctive.each do |entry|
          say "    #{entry.lemma.ljust(width)}  #{entry.doc_count}× here · " \
              "#{commafy(entry.corpus_freq)}× corpus  (z=#{format('%.1f', entry.score)})"
        end
      end

      # The hapax legomena line: attested exactly once in this document. The full
      # count, then up to --limit spellings (they can number in the hundreds).
      def print_vocab_hapax(hapax, hapax_count)
        return if hapax_count.zero?

        say ""
        shown = hapax.first(options[:limit].to_i)
        more = hapax_count - shown.size
        tail = more.positive? ? " (+#{commafy(more)} more)" : ""
        say "  hapax legomena (#{commafy(hapax_count)}, once each): #{shown.join(', ')}#{tail}"
      end

      # A document with no gold lemmas: say so plainly and name the gold-bearing
      # languages (from the lemma index) so the user can profile something real.
      def print_vocab_no_gold(profile)
        say "  no gold lemmas — this document is not linguistically annotated " \
            "(0 of #{pluralize(profile.passages, 'passage')} carry one)."
        say "  Gold lemmas come from the treebank shelves (PROIEL, TOROT, ISWOC, " \
            "Universal Dependencies) and the ORACC cuneiform layer."
        langs = profile.gold_languages.first(8).map { |lang, count| "#{lang} (#{commafy(count)})" }
        ellipsis = profile.gold_languages.size > langs.size ? ", …" : ""
        say "  gold-bearing languages: #{langs.join(', ')}#{ellipsis}"
        say "  Try e.g. nabu vocab urn:nabu:proiel:caes-gal"
      end

      # Group an integer's digits into thousands (12345 → "12,345"). Plain string
      # work — no locale gem for one display nicety.
      def commafy(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      # One display line of pristine text: newlines flattened, capped at 100
      # chars (treebank sentences are single lines; the cap guards outliers).
      def truncate_line(text, max = 100)
        line = text.tr("\n", " ")
        line.length > max ? "#{line[0, max]}…" : line
      end

      # Render dictionary entries whole (the CLI is the unbounded surface):
      # header with license label, gloss, the structured body, then the
      # resolved citations as show-able urns. Unresolved citations already
      # read inline in the body text.
      def print_define_results(lemma, results)
        if results.empty?
          return say("no dictionary entry for #{lemma} — the shelf holds LSJ (grc) and " \
                     "Lewis & Short (lat); give a dictionary form (search --lemma finds attestations)")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          say "#{result.headword} — #{result.dictionary_title} [#{result.license_class}]  #{result.urn}"
          say "  gloss: #{result.gloss}" if result.gloss
          say ""
          say result.body
          print_reflexes(result.reflexes)
          print_resolved_citations(result)
        end
      end

      # A reconstruction entry's descendant reflexes (P14-1): attested-here
      # cognates first with their gold-lemma passage counts, then an honest
      # one-line summary of the rest (the full tree is in the data; the
      # attested ones are the actionable ones).
      def print_reflexes(reflexes)
        return if reflexes.empty?

        attested, rest = reflexes.partition(&:attested_count)
        unless attested.empty?
          say ""
          say "attested in this corpus (nabu search --lemma):"
          attested.sort_by { |r| -r.attested_count }.each do |r|
            say "  [#{r.language}] #{reflex_form(r)} — #{r.attested_count} " \
                "#{r.attested_count == 1 ? 'passage' : 'passages'}"
          end
        end
        return if rest.empty?

        say ""
        say "other reflexes (not attested here): " \
            "#{rest.first(10).map { |r| "[#{r.lang_code}] #{reflex_form(r)}" }.join(', ')}" \
            "#{" … and #{rest.size - 10} more" if rest.size > 10}"
      end

      def reflex_form(reflex)
        reflex.roman && reflex.roman != reflex.word ? "#{reflex.word} (#{reflex.roman})" : reflex.word
      end

      # etym (P14-1): one block per reconstruction entry — where the walk
      # entered (matched reflex → *headword), the entry's own reflex list,
      # then each one-hop ancestor with its cognates.
      def print_etym_results(lemma, results)
        if results.empty?
          return say("no reconstruction names #{lemma} as a descendant — the crosswalk covers " \
                     "Proto-Slavic/PIE/Proto-Germanic (Wiktionary); try the dictionary form, " \
                     "or *form for a direct lookup")
        end

        results.each_with_index do |result, index|
          say "" if index.positive?
          say "#{etym_entry_line(result)}  #{result.urn}"
          say "  gloss: #{result.gloss}" if result.gloss
          print_reflexes(result.cognates)
          result.ancestors.each do |ancestor|
            say ""
            say "← #{etym_entry_line(ancestor)}  #{ancestor.urn}"
            say "  gloss: #{ancestor.gloss}" if ancestor.gloss
            print_reflexes(ancestor.cognates)
          end
        end
      end

      def etym_entry_line(result)
        via = result.matched_reflex
        prefix = via ? "#{via.word} [#{via.language}] → " : ""
        "#{prefix}#{result.headword} [#{result.language}] — #{result.dictionary_title} " \
          "[#{result.license_class}]"
      end

      def print_resolved_citations(result)
        resolved = result.citations.select(&:resolved_urn)
        return if resolved.empty?

        say ""
        say "resolved citations (in this corpus — nabu show <urn>):"
        resolved.each { |citation| say "  #{citation.label} → #{citation.resolved_urn}" }
      end

      # A print-free runner needs a sink for live progress; the CLI owns all
      # formatting and tty decisions here. Progress goes to $stderr (final counts
      # go to $stdout via `say`, so scripts piping stdout are unaffected). When
      # $stderr is a tty: git output streams raw (its own \r overwrites the line)
      # and a \r-updating "loading…" counter refreshes each tick. Non-tty: no git
      # streaming (callbacks stay nil) and one plain line per 100 documents.
      def progress_reporter
        tty = $stderr.tty?
        Nabu::ProgressReporter.new(
          on_fetch_line: tty ? ->(line) { $stderr.print(line) } : nil,
          on_load_tick: load_tick(tty)
        )
      end

      def load_tick(tty)
        last = 0
        lambda do |processed, errored|
          if tty
            $stderr.print("\r#{loading_line(processed, errored)}  ")
          elsif processed - last >= 100
            last = processed
            warn(loading_line(processed, errored))
          end
        end
      end

      def loading_line(processed, errored)
        suffix = errored.positive? ? " (#{errored} quarantined)" : ""
        "  loading… #{processed} docs#{suffix}"
      end

      # Break off the \r-updated counter line before the final counts, tty only.
      def finish_progress
        $stderr.print("\n") if $stderr.tty?
      end

      # sync <slug>: explicit, unconditional (disabled sources allowed, with a
      # note). A tripped breaker prints its counts + the --force hint and exits 1.
      def sync_one(runner, registry, slug)
        raise Thor::Error, "sync: give a source slug or --all" if slug.nil?

        entry = registry[slug]
        say "Note: #{slug} is disabled; syncing anyway (explicit request).", :yellow if entry && !entry.enabled
        outcome = runner.sync(slug, parse_only: options[:parse_only], force: options[:force],
                                    progress: progress_reporter)
        finish_progress
        raise Thor::Error, "#{slug}: #{outcome.breaker.message}" if outcome.aborted?

        say format_sync_outcome(outcome)
        print_discovery_accounting(outcome)
        print_sync_warnings(outcome)
      end

      # sync --all: enabled + live sources only; report each, never abort the
      # batch on one source's error.
      def sync_all(runner)
        results = runner.sync_all(parse_only: options[:parse_only], force: options[:force],
                                  progress: progress_reporter)
        finish_progress
        return say("Nothing to sync: no enabled, live sources.") if results.empty?

        results.each do |slug, result|
          say("  #{sync_all_line(slug, result)}")
          if result.is_a?(Nabu::SyncRunner::Outcome)
            print_discovery_accounting(result)
            print_sync_warnings(result)
          end
        end
      end

      def sync_all_line(slug, result)
        return "#{slug.ljust(24)} FAILED — #{result.message}" unless result.is_a?(Nabu::SyncRunner::Outcome)
        return "#{slug.ljust(24)} ABORTED — #{result.breaker.message}" if result.aborted?

        format_sync_outcome(result)
      end

      # P5-5 inline deviation warnings: advisory one-liners after the counts line,
      # in yellow, never affecting the exit code. Empty on a clean sync.
      def print_sync_warnings(outcome)
        outcome.warnings.each { |finding| say("  ! #{finding.message}", :yellow) }
      end

      # P11-7 discovery accounting: classify every content-pattern file
      # selected / skipped-by-rule / unrecognized, combining the loader's fate
      # of discovered refs (loaded → selected; parse-skipped → skipped-by-rule;
      # quarantined → unrecognized) with the adapter's discovery census (0-byte
      # skeletons, non-editions → skipped-by-rule; a tree with no ingestible
      # content → unrecognized). unrecognized ≥ 1 is rendered loudly, with its
      # notes, so a silent-ingestion gap can never hide again.
      def print_discovery_accounting(outcome)
        report = outcome.load_report
        discovery = outcome.discovery
        return unless report && discovery

        selected = report.added + report.updated + report.skipped
        skipped = report.skipped_by_rule + discovery.skipped_by_rule
        unrecognized = report.errored + discovery.unrecognized
        say("  discovery: #{selected} selected · #{skipped} skipped-by-rule · " \
            "#{unrecognized} unrecognized", unrecognized.positive? ? :yellow : nil)
        discovery.notes.each { |note| say("  ! #{note}", :yellow) }
      end

      def format_sync_outcome(outcome)
        fetched = outcome.fetch_report ? outcome.fetch_report.sha[0, 12] : "parse-only"
        report = outcome.load_report
        "#{outcome.slug.ljust(24)} #{fetched}  " \
          "+#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored  " \
          "indexed #{outcome.indexed} passages"
      end

      # --dry-run: report the plan, touch nothing.
      def print_plan(plan)
        say "Dry run — nothing will change."
        say "Would drop catalog db: #{plan.db_path} (#{plan.db_exists ? 'exists' : 'absent'})"
        plan.items.each do |slug, action|
          say(action == :replay ? "  replay  #{slug}" : "  skip    #{slug} (no canonical data)")
        end
      end

      # Real run: per-source counts, skips, warnings, then a grand total.
      def print_result(result)
        existed = result.db_existed ? "" : " (did not exist)"
        say "Dropped catalog db: #{result.db_path}#{existed}"
        result.outcomes.each { |outcome| say "  #{format_report(outcome.slug, outcome.report)}" }
        result.skips.each { |skip| say "  skip    #{skip.slug} (no canonical data — never synced)" }
        result.warnings.each do |outcome|
          say "  WARNING: #{outcome.slug} quarantined #{outcome.report.errored} document(s) — parser regression?"
        end
        say "  #{format_report('TOTAL', total_report(result))}"
        say "  indexed #{result.indexed} passages"
      end

      def format_report(label, report)
        "#{label.ljust(24)} +#{report.added} added  ~#{report.updated} updated  " \
          "=#{report.skipped} skipped  -#{report.withdrawn} withdrawn  !#{report.errored} errored"
      end

      def total_report(result)
        reports = result.outcomes.map(&:report)
        Nabu::Store::LoadReport.new(
          added: reports.sum(&:added), updated: reports.sum(&:updated),
          skipped: reports.sum(&:skipped), withdrawn: reports.sum(&:withdrawn),
          errored: reports.sum(&:errored), skipped_by_rule: reports.sum(&:skipped_by_rule)
        )
      end

      # --remote (P5-3): the no-clone upstream probe. Pins + baselines live in
      # the history ledger (P7-1), which the probe writes (baseline recording),
      # so this is a write path: create + migrate + lift. Its own exit-1 raise.
      def run_remote_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        ledger = open_or_create_ledger(config)
        report = Nabu::Health::RemoteProbe.new(
          registry: registry, ledger: ledger, canonical_dir: config.canonical_dir
        ).run
        print_remote_health(report)
        # A gone upstream is the only red finding; the table is already on stdout,
        # so raise for the exit-1 signal (Thor prints the summary to stderr).
        raise Thor::Error, remote_health_failure(report) if report.any_gone?
      ensure
        ledger&.disconnect
      end

      # Bare health (P5-5): run-history trends + live golden replay, no network.
      # open_catalog binds the Store models the LocalCheck queries; open_ledger
      # binds the run history (absent ledger = empty history, honestly). Exit 1
      # on any loud finding (quarantine spike, >15% creep, a lost golden query);
      # soft warnings (collapse, 5–15% creep, stale) stay exit 0.
      def run_local_health
        config = Nabu::Config.load
        registry = Nabu::SourceRegistry.load(config.sources_path)
        catalog = open_catalog(config)
        fulltext = catalog ? open_fulltext(config) : nil
        ledger = open_ledger(config)
        report = Nabu::Health::LocalCheck.new(
          registry: registry, catalog: catalog, fulltext: fulltext, ledger: ledger,
          golden_queries: Nabu::Health::LocalCheck.golden_queries
        ).run
        print_local_health(report)
        raise Thor::Error, local_health_failure(report) if report.any_loud?
      ensure
        catalog&.disconnect
        fulltext&.disconnect
        ledger&.disconnect
      end

      # Per-source trend rows, then the golden-replay section, then the verdict
      # and a hint toward the upstream probe.
      def print_local_health(report)
        print_source_health(report.sources)
        print_golden_health(report)
        say local_health_verdict(report)
        say "Hint: run `nabu health --remote` for the no-clone upstream probe."
      end

      def print_source_health(sources)
        return say("No sources registered.") if sources.empty?

        width = sources.map { |source| source.slug.length }.max
        sources.each { |source| print_source_row(source, width) }
      end

      # A healthy source is one "ok" line; a flagged one repeats its slug column
      # blank for continuation findings so multi-finding sources stay aligned.
      def print_source_row(source, width)
        return say("#{source.slug.ljust(width)}  ok") if source.findings.empty?

        source.findings.each_with_index do |finding, index|
          label = index.zero? ? source.slug.ljust(width) : " " * width
          say "#{label}  #{finding_tag(finding)} #{finding.message}"
        end
      end

      def finding_tag(finding)
        { loud: "ANOMALY", soft: "warning", info: "note" }.fetch(finding.severity)
      end

      def print_golden_health(report)
        case report.corpus
        when :absent
          return say("golden replay: no corpus — run nabu sync or nabu rebuild")
        when :no_index
          return say("golden replay: no fulltext index — run nabu sync or nabu rebuild")
        end

        lost = report.golden.select(&:lost?)
        lost.each { |result| say "golden query lost: #{result.query}  (expected #{result.expect_urn})" }
        found = report.golden.count { |result| result.status == :found }
        skipped = report.golden.count { |result| result.status == :skipped }
        say "golden replay: #{found} found, #{lost.size} lost, #{skipped} skipped (source not in this corpus)"
      end

      def local_health_verdict(report)
        return "health: #{report.loud_count} anomaly finding(s) — see above (exit 1)" if report.any_loud?
        return "health: OK, #{pluralize(report.soft_count, 'warning')}" if report.soft_count.positive?

        "health: OK"
      end

      def local_health_failure(report)
        "health: #{report.loud_count} loud finding(s) — see the report above"
      end

      # Render the remote probe: one aligned row per source (slug, liveness,
      # drift, license) plus any trailing detail, then a one-line summary.
      def print_remote_health(report)
        rows = report.rows
        return say("No sources registered.") if rows.empty?

        slug_w = rows.map { |row| row.slug.length }.max
        live_w = rows.map { |row| live_cell(row.liveness).length }.max
        drift_w = rows.map { |row| drift_cell(row.drift).length }.max
        rows.each do |row|
          say "#{row.slug.ljust(slug_w)}  #{live_cell(row.liveness).ljust(live_w)}  " \
              "#{drift_cell(row.drift).ljust(drift_w)}  #{license_cell(row.license)}#{health_detail(row)}"
        end
        say remote_health_summary(report)
      end

      def live_cell(liveness)
        { alive: "alive", moved: "MOVED", gone: "GONE" }.fetch(liveness.status)
      end

      def drift_cell(drift)
        { current: "current", behind: "behind", never_synced: "never-synced",
          unknown: "—", multi: "multi-repo" }.fetch(drift)
      end

      def license_cell(license)
        { baseline_recorded: "license: baseline recorded", unchanged: "license: ok",
          changed: "license: CHANGED", unchecked: "license: unchecked" }.fetch(license.status)
      end

      # Trailing context: why an upstream is not alive, or why a license row is
      # flagged. Kept off the aligned columns so the table stays readable.
      def health_detail(row)
        bits = []
        bits << row.liveness.detail if row.liveness.detail && row.liveness.status != :alive
        bits << row.drift_detail if row.drift_detail && row.drift == :behind
        bits << row.license.detail if row.license.status == :changed
        bits.empty? ? "" : "   #{bits.join(' · ')}"
      end

      def remote_health_summary(report)
        rows = report.rows
        counts = { alive: 0, moved: 0, gone: 0 }
        rows.each { |row| counts[row.liveness.status] += 1 }
        behind = rows.count { |row| row.drift == :behind }
        parts = [pluralize(rows.size, "source"), "#{counts[:alive]} alive"]
        parts << "#{counts[:moved]} moved" if counts[:moved].positive?
        parts << "#{counts[:gone]} gone" if counts[:gone].positive?
        parts << "#{behind} behind" if behind.positive?
        parts.join(", ")
      end

      def remote_health_failure(report)
        gone = report.rows.count { |row| row.liveness.status == :gone }
        "health: #{pluralize(gone, 'upstream')} gone — see the table above"
      end

      # -- mcp entrypoint plumbing (P8-2) ----------------------------------

      # A lazy, memoizing, read-only opener returned as a PROC (the Tools
      # contract resolves each connection slot per tool call). On every call:
      # absent file → nil (Tools renders the "no corpus" state); present file →
      # an open read-only handle, cached across calls so a long session does not
      # churn file descriptors. The cached handle is dropped and reopened when
      # the file's identity changes — `nabu rebuild` deletes and recreates the
      # catalog, so a mid-session rebuild is genuinely picked up, not served
      # stale from a handle onto the deleted inode.
      def readonly_opener(path, &open)
        handle = nil
        identity = nil
        lambda do
          current = file_identity(path)
          if current.nil?
            handle&.disconnect
            handle = identity = nil
          elsif current != identity
            handle&.disconnect
            handle = open.call
            identity = current
          end
          handle
        end
      end

      # (device, inode) — a file replaced in place (delete + recreate) changes
      # inode, which is how the opener notices a rebuild. nil when absent.
      def file_identity(path)
        return nil unless File.exist?(path)

        stat = File.stat(path)
        [stat.dev, stat.ino]
      end

      # The diagnostics sink for `nabu mcp`: stderr by default, or a file opened
      # for append (line-buffered) when --log FILE is given. NEVER stdout —
      # stdout is the JSON-RPC protocol channel.
      def mcp_log(path)
        return $stderr if path.to_s.strip.empty?

        # No block form: the log must stay open for the whole server lifetime;
        # `mcp` closes it in its ensure.
        file = File.open(path, "a") # rubocop:disable Style/FileOpen
        file.sync = true
        file
      end

      # SIGINT/SIGTERM → clean shutdown with EOF semantics: exit 0, unwinding the
      # command's ensure (which closes the log). A client that stops the server
      # by closing our stdin gets the same path via the run loop reaching EOF.
      def install_mcp_signal_traps
        %w[INT TERM].each { |signal| trap(signal) { exit(0) } }
      end

      # Open the catalog db for reading if it has been built; nil otherwise so
      # status degrades gracefully to registry-only output.
      def open_catalog(config)
        return nil unless File.exist?(config.catalog_path)

        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.setup!(db)
        db
      end

      # Open the catalog for writing, creating + migrating it if this is the
      # first sync before any rebuild. Migrations are idempotent (only pending
      # ones run), so this is safe on an existing db too. Callers that also
      # open the ledger MUST open it first (open_or_create_ledger lifts a
      # pre-P7-1 catalog's history before migration 005 drops those tables).
      def open_or_create_catalog(config)
        require "fileutils"
        FileUtils.mkdir_p(File.dirname(config.catalog_path))
        db = Nabu::Store.connect(config.catalog_path)
        Nabu::Store.migrate!(db)
        Nabu::Store.setup!(db)
        db
      end

      # Open the history ledger for reading; nil when absent (fresh machine —
      # read paths treat that as empty history) or not yet migrated.
      def open_ledger(config)
        return nil unless File.exist?(config.history_path)

        db = Nabu::Store::Ledger.connect(config.history_path)
        return Nabu::Store::Ledger.setup!(db) if db.table_exists?(:runs)

        db.disconnect
        nil
      end

      # Open the history ledger for writing: create + migrate it, and lift a
      # pre-P7-1 catalog's runs/pins/baselines into it (one-shot; the catalog
      # is then migrated forward, dropping the moved tables).
      def open_or_create_ledger(config)
        Nabu::Store::Ledger.open_with_lift!(
          history_path: config.history_path, catalog_path: config.catalog_path
        )
      end
    end
  end
end
