# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# A TestAdapter whose #fetch succeeds WITHOUT any network: the quickstart rig
# (P18-2). The canonical dir already holds the fixture files, so fetch is a
# no-op that returns a pinned sha, and the rest of the sync path (load, index,
# ledger pin) runs for real.
class QuickstartFetchAdapter < TestAdapter
  def fetch(_workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
    Nabu::FetchReport.new(sha: "deadbeefcafe", fetched_at: Time.now)
  end
end

# The partial-failure rig: fetch always raises, as an unreachable upstream
# would (Nabu::FetchError aborts THIS source's sync, never the batch).
class QuickstartFailingAdapter < TestAdapter
  def fetch(_workdir, progress: nil, force: false) # rubocop:disable Lint/UnusedMethodArgument
    raise Nabu::FetchError, "upstream unreachable (rigged)"
  end
end

class CLITest < Minitest::Test
  # Run the Thor CLI in-process (never shell out to bin/nabu). Returns the
  # captured [stdout, stderr, exit_status]. exit_status is nil when the CLI
  # returned normally without calling exit.
  def run_cli(argv)
    status = nil
    out, err = capture_io do
      exc = begin
        Nabu::CLI.start(argv)
        nil
      rescue SystemExit => e
        e
      end
      status = exc&.status
    end
    [out, err, status]
  end

  def test_version_prints_version_to_stdout
    out, _err, status = run_cli(["version"])
    assert_equal "#{Nabu::VERSION}\n", out
    assert_nil status, "version should not signal failure"
  end

  def test_help_lists_all_commands
    out, _err, _status = run_cli(["help"])
    %w[version quickstart sync status rebuild verify search show export define etym].each do |command|
      assert_match(/\b#{command}\b/, out, "help output should list #{command}")
    end
  end

  def test_exit_on_failure_is_enabled
    assert Nabu::CLI.exit_on_failure?
  end

  # -- inline subcommand help (owner UX) -----------------------------------
  # `nabu help <command>` must teach the command, not just name it: query
  # syntax, real urn shapes, worked examples. Anchors only — prose may move.

  def test_help_search_documents_syntax_filters_and_examples
    out, _err, _status = run_cli(%w[help search])
    assert_match(/implicit AND/, out, "must state the multi-term semantics")
    assert_match(/μῆνιν/, out, "must show the diacritic-folding promise")
    assert_match(/prefix/, out, "must document the * prefix form")
    assert_match(%r{OR/NOT are not supported}i, out, "must be honest about booleans")
    assert_match(/Examples:/, out)
    assert_match(/--lang/, out)
  end

  def test_help_show_documents_urn_shapes_and_full_urn
    out, _err, _status = run_cli(%w[help show])
    assert_match(/provenance/, out, "must explain the passage view")
    assert_match(/:suffixes/, out, "must explain the document listing form")
    assert_match(/--full-urn/, out)
    assert_match(/urn:cts:greekLit:/, out, "must show a real CTS urn shape")
    assert_match(/restart block/, out, "must explain papyri :b<k> segments")
    assert_match(/Examples:/, out)
  end

  def test_help_show_documents_parallel_with_an_example
    out, _err, _status = run_cli(%w[help show])
    assert_match(/--parallel/, out)
    assert_match(/citation suffix/, out, "must explain the alignment rule")
    assert_match(/--parallel\b.*\n?.*eng/, out, "must show a worked --parallel example")
    assert_match(/one-sided|only in/i, out, "must be honest about unmatched suffixes")
  end

  def test_help_show_documents_range_syntax_with_a_papyri_example
    out, _err, _status = run_cli(%w[help show])
    assert_match(/RANGE|range/, out, "must document the range syntax")
    assert_match(/1\.1-1\.10/, out, "must show a CTS range example")
    assert_match(/:1-b2:2|:b2:/, out, "must show a papyri cross-block range example")
    assert_match(/inclusive/i, out, "must state the endpoints are inclusive")
  end

  def test_help_search_mentions_translations
    out, _err, _status = run_cli(%w[help search])
    assert_match(/translation/i, out, "must say eng translations are searchable when ingested")
    assert_match(/--lang eng/, out)
  end

  def test_help_search_documents_lemma_search_with_a_real_example
    out, _err, _status = run_cli(%w[help search])
    assert_match(/--lemma/, out)
    assert_match(/treebank/i, out, "must scope --lemma to the gold treebanks")
    assert_match(/--lemma λέγω/, out, "must show a worked Greek example")
    assert_match(/εἶπας/, out, "must show the suppletive payoff — forms no text query reaches")
    assert_match(/replaces the text query/i, out, "must be honest that --lemma and a query don't combine")
  end

  # P11-4 (+P12-3): `nabu define` help must teach the shelf, the folding
  # promise, the citation-resolution behavior, and worked examples in all
  # three languages — including the OE ASCII-folding promise (aethele finds
  # æðele).
  def test_help_define_documents_the_dictionary_shelf
    out, _err, _status = run_cli(%w[help define])
    assert_match(/LSJ/, out)
    assert_match(/Lewis & Short/, out)
    assert_match(/Bosworth-Toller/, out)
    assert_match(/Wiktionary/, out, "must document the OCS shelf (P13-10)")
    assert_match(/μηνις finds μῆνις/, out, "must show the diacritic-folding promise")
    assert_match(/aethele finds æðele/, out, "must show the OE ASCII-folding promise")
    assert_match(/nabu show <urn>/, out, "must teach the resolved-citation handoff")
    assert_match(/Monier-Williams/, out, "must document the Sanskrit shelf (P17-4)")
    assert_match(/--lang grc\|lat\|ang\|san\|chu/, out)
    assert_match(/nabu define virtus/, out, "must show a Latin example")
    assert_match(/nabu define amsa/, out, "must show the SLP1-transcode Sanskrit example")
  end

  # P14-1: `nabu etym` help must teach the walk (attested → proto →
  # cognates), the asterisk convention, the romanization bridge, and worked
  # examples on the demo chains.
  def test_help_etym_documents_the_reconstruction_walk
    out, _err, _status = run_cli(%w[help etym])
    assert_match(/Proto-Slavic/, out)
    assert_match(/Proto-Indo-European/, out)
    assert_match(/Proto-Germanic/, out)
    assert_match(/attestation count/i, out, "must promise corpus counts")
    assert_match(/\*bogъ/, out, "must show the asterisk convention")
    assert_match(/guþ/, out, "must show the romanization bridge example")
    assert_match(/nabu etym богъ/, out, "must show the OCS worked example")
    assert_match(/bhewgh/, out, "P14-10: must teach the ASCII bare-form fallback")
    assert_match(/'\*kaisaraz'/, out, "P14-10: shell star examples must be quoted")
    assert_match(/no reconstruction\s+path in the crosswalk/, out,
                 "P24-2: must teach the dictionary-shelf fallback")
  end

  def test_help_define_documents_the_reconstruction_shelves
    out, _err, _status = run_cli(%w[help define])
    assert_match(/sla-pro\|ine-pro\|gem-pro/, out, "the widened --lang gate")
    assert_match(/define '\*bogъ'/, out, "must show the quoted asterisk example (zsh globs bare *)")
  end

  # -- P14-11: --long expands the truncated reflex/cognate lists ------------
  # The ONE truncation in the define/etym renderers is print_reflexes' "other
  # reflexes (not attested here)" cap (first 10 inline + "… and N more"). The
  # *zima fixture entry names 26 non-attested reflexes, so the cap fires by
  # default and --long must expand every one, grouped by language. The
  # attested list is already unbounded, so it needs no flag.

  def test_show_resolves_the_urn_define_prints
    with_recon_shelf do |config|
      out, = with_config(config) { run_cli(%w[define *zima]) }
      urn = out[/urn:nabu:dict:\S+/]
      refute_nil urn, "define prints the entry urn"
      shown, _err, status = with_config(config) { run_cli(["show", urn]) }
      assert_nil status
      assert_match(/zima/, shown, "show renders the entry define invited (owner repro 2026-07-15)")
      assert_match(/#{Regexp.escape(urn)}/, shown)
    end
  end

  def test_define_reflexes_are_capped_by_default
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[define *zima]) }
      assert_nil status
      assert_match(/other reflexes \(not attested here\): /, out)
      assert_match(/… and 16 more/, out, "the 16-past-10 tail is summarised, not listed")
      refute_match(/grouped by language/, out, "compact is the default (house rule)")
      refute_match(/\[dsb\]/, out, "a tail language must not appear in the capped form")
    end
  end

  def test_define_long_expands_every_reflex_grouped_by_language
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[define *zima --long]) }
      assert_nil status
      assert_match(/other reflexes \(not attested here\) — all 26, grouped by language:/, out)
      refute_match(/ more$/, out, "nothing is elided under --long")
      # A language from the truncated tail is now present, on its own group
      # line — named inline from the derived census (P18-4).
      assert_match(/^ {2}\[dsb · Lower Sorbian\] zyma$/, out, "the capped-away Lower Sorbian reflex now shows, named")
      # Multiple forms of one language collapse onto that language's line.
      assert_match(/^ {2}\[cu · Old Church Slavonic\] .*,.*$/, out, "Old Church Slavonic's two forms share one line")
    end
  end

  def test_etym_cognates_are_capped_by_default
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym *zima]) }
      assert_nil status
      assert_match(/… and 16 more/, out, "the direct-lookup cognate list caps like define")
      refute_match(/grouped by language/, out)
    end
  end

  def test_etym_long_expands_every_cognate_grouped_by_language
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym *zima --long]) }
      assert_nil status
      assert_match(/other reflexes \(not attested here\) — all 26, grouped by language:/, out)
      assert_match(/^ {2}\[dsb · Lower Sorbian\] zyma$/, out, "grouped headers name the code inline (P18-4)")
      refute_match(/ and \d+ more$/, out)
    end
  end

  # -- P26-0: the lemma tier on the define/etym render ------------------------
  # attested_count keeps gold-only semantics; silver (automatic lemmatization)
  # counts are ALWAYS labeled — "1 passage (+2 silver)" beside a gold count,
  # "silver 3 passages" for a silver-only reflex. NEVER a bare number that
  # could read as gold: that is the rule under test, stated as refutations.

  def test_define_renders_silver_counts_labeled_beside_gold
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[define *zima]) }
      assert_nil status
      assert_match(/^ {2}\[chu\] зима \(zima\) — 1 passage \(\+2 silver\)$/, out,
                   "the gold count keeps its meaning; silver rides beside it, labeled")
      refute_match(/\[chu\] зима \(zima\) — 3 passage/, out,
                   "gold and silver must never sum into one number")
    end
  end

  def test_define_renders_silver_only_reflexes_labeled_never_a_bare_number
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[define *zima]) }
      assert_nil status
      assert_match(/silver-only \(automatic lemmatization/, out)
      assert_match(/^ {2}\[orv\] зима \(zima\) — silver 3 passages$/, out)
      refute_match(/\[orv\] зима \(zima\) — 3 passages/, out,
                   "a silver-only count must never render as a bare (gold-readable) number")
      refute_match(/attested in this corpus.*\n.*\[orv\]/, out,
                   "silver-only reflexes must not sit in the gold-attested section")
    end
  end

  def test_etym_renders_the_same_tier_labels
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym зима --lang chu]) }
      assert_nil status
      assert_match(/^ {2}\[chu\] зима \(zima\) — 1 passage \(\+2 silver\)$/, out,
                   "etym rides the same print_reflexes — same labels")
      assert_match(/^ {2}\[orv\] зима \(zima\) — silver 3 passages$/, out)
    end
  end

  def test_search_lemma_labels_silver_hits_and_gold_only_excludes_them
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma зима --lang chu]) }
      assert_nil status
      assert_match(/urn:nabu:test:auto:chu:1 \[chu\] \[silver\]/, out, "the silver hit says so")
      refute_match(/urn:nabu:test:treebank:chu:1 \[chu\] \[silver\]/, out, "gold hits stay unlabeled")
      assert_match(/2 silver \(automatic lemmatization/, out, "the footer totals the silver hits")

      gold, _err2, status2 = with_config(config) { run_cli(%w[search --lemma зима --lang chu --gold-only]) }
      assert_nil status2
      assert_match(/urn:nabu:test:treebank:chu:1/, gold)
      refute_match(/urn:nabu:test:auto/, gold, "--gold-only excludes the silver tier")
    end
  end

  # -- P26-4: the tier on the concord and vocab renders ------------------------

  def test_concord_lemma_mode_tags_silver_rows_and_totals_them
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord --lemma зима --lang chu]) }
      assert_nil status
      assert_match(/urn:nabu:test:auto:chu:1 \[chu\] \[silver\]$/, out, "silver rows say so")
      refute_match(/urn:nabu:test:treebank:chu:1 \[chu\] \[silver\]/, out, "gold rows stay untagged")
      assert_match(/— 2 silver \(automatic lemmatization\)$/, out, "the footer totals the silver share")
    end
  end

  def test_vocab_labels_a_silver_document_never_as_gold
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[vocab urn:nabu:test:auto:chu]) }
      assert_nil status
      assert_match(/silver lemmas: 2 tokens/, out, "the count line itself says silver")
      assert_match(/lemma tier: silver \(automatic lemmatization/, out)
      refute_match(/gold lemmas:/, out, "a silver profile must never render under the gold name")
    end
  end

  def test_vocab_keeps_the_pre_tier_render_for_gold_documents
    with_tiered_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[vocab urn:nabu:test:treebank:chu]) }
      assert_nil status
      assert_match(/gold lemmas: 1 token/, out)
      refute_match(/lemma tier:/, out, "gold renders exactly as before — no label noise")
    end
  end

  # -- P24-2: define/etym coordination — etym must not miss what define finds --

  # THE incident (owner, 2026-07-16): `define сигать` finds the Vasmer
  # article (urn:nabu:dict:starling-vasmer:12561 — prose fields, no reflex
  # rows) while `etym сигать` returned a flat miss. On a crosswalk miss,
  # etym now falls back to the SAME Query::Define lookup and renders the
  # entries in the define house format (print_define_entry — zero renderer
  # divergence) under an honest header. The folded headword carries the
  # dictionary's verbatim trailing comma (сига́ть,) — the fold must reach it.
  def test_etym_falls_back_to_the_dictionary_shelf_on_a_crosswalk_miss
    with_starling_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym сигать]) }
      assert_nil status
      assert_match(/no reconstruction path in the crosswalk for сигать — the dictionary shelf holds:/,
                   out)
      assert_match(/сига́ть,.*urn:nabu:dict:starling-vasmer:12561/, out,
                   "the define house format — headword (verbatim comma) + urn on the headline")
      assert_match(/Near etymology:/, out, "the entry body renders whole")
      refute_match(/no reconstruction names/, out,
                   "the fallback fired — the full miss text is unnecessary")
    end
  end

  def test_etym_crosswalk_hit_never_mixes_the_dictionary_fallback
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym прьстъ]) }
      assert_nil status
      assert_match(/\*pьrstъ/, out, "the walk itself is untouched")
      refute_match(/dictionary shelf holds/, out,
                   "etym's primary contract stays the walk — no fallback mixing on a hit")
    end
  end

  # The genuine total miss enumerates the crosswalk shelves DB-DRIVEN (the
  # P11/P18 hardcoded-list lesson): the starling fixture crosswalk holds
  # bat-pro/gem-pro/ine-pro (vasmer's rus mints no reflex rows and must
  # not appear); the stale Wiktionary proto-shelf roll call is gone; the
  # '*form' quoting hint stays.
  def test_etym_total_miss_enumerates_the_live_crosswalk_shelves
    with_starling_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym зззз]) }
      assert_nil status
      assert_match(/the crosswalk covers bat-pro, gem-pro, ine-pro\b/, out,
                   "db-derived enumeration — exactly the shelves with reflex rows")
      refute_match(%r{Proto-Slavic/PIE/Proto-Germanic}, out, "the hardcoded enumeration is gone")
      assert_match(/'\*form'/, out, "the quoting hint stays")
    end
  end

  # -- P18-4: nabu language — the code desk reference --------------------------

  def test_help_language_documents_the_desk_reference
    out, _err, _status = run_cli(%w[help language])
    assert_match(/zle-ort/, out, "must show the etymology-tail worked example")
    assert_match(/--list/, out)
    assert_match(/--export-dossiers/, out, "the one-shot canonical-memory migration")
    assert_match(/local-language/, out, "must name the dossier shelf the curation lives in")
    assert_match(/family-level/, out, "must explain the family fallback for the tail")
  end

  def test_language_card_for_a_held_shelf_language_merges_all_three_layers
    with_recon_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language sla-pro])
        assert_nil status
        assert_match(/^sla-pro — Proto-Slavic$/, out, "curated name headline")
        assert_match(/family: Slavic < Balto-Slavic < Indo-European \(reconstructed\)/, out)
        assert_match(/reconstructed headwords/, out, "curated context renders")
        assert_match(/dictionary: Wiktionary — Proto-Slavic.*\(\d+ entries\)/, out)
        assert_match(/etymology: \d+ reflex edges/, out, "PIE/PBS descendants name sla-pro forms")
        refute_match(/corpus:/, out, "zero corpus holdings are suppressed (house rule)")
        refute_match(/no curated note/, out)
      end
    end
  end

  def test_language_card_for_a_tail_code_census_name_with_family_fallback
    with_recon_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language zlw-osk])
        assert_nil status
        assert_match(/^zlw-osk — Old Slovak$/, out, "the name comes from the derived kaikki census")
        assert_match(/family: zlw-\* — West Slavic/, out)
        assert_match(/no curated note for this code — its zlw-\* family/, out)
        assert_match(/etymology: \d+ reflex edge/, out)
      end
    end
  end

  def test_language_card_long_shows_the_upstream_code_split
    with_recon_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language chu --long])
        assert_nil status
        assert_match(/^chu — Old Church Slavonic$/, out)
        assert_match(/edge codes: cu \d+/, out, "chu's edges arrive under Wiktionary's cu — said honestly")
      end
    end
  end

  def test_language_unknown_code_misses_honestly_with_a_family_hint
    with_recon_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language zle-qqq])
        assert_nil status
        assert_match(/^zle-qqq — unknown here/, out)
        assert_match(/family hint: zle-\* — East Slavic/, out)
        assert_match(/nabu language --list/, out)

        out, _err, _status = run_cli(%w[language qqqq])
        assert_match(/^qqqq — unknown here/, out)
        refute_match(/family hint/, out, "no known prefix — no guessed hint")
      end
    end
  end

  def test_language_list_scopes_to_held_languages_and_names_the_tail
    with_recon_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language --list])
        assert_nil status
        assert_match(/^held languages \(\d+ with corpus documents, gold lemmas, or a shelf\):/, out)
        assert_match(/^ {2}sla-pro\s+Proto-Slavic — .*Wiktionary — Proto-Slavic/, out)
        refute_match(/^ {2}zle-ort/, out, "the etymology tail never floods the list")
        assert_match(/etymology tail: ~800 more codes.*nabu language CODE/, out)
      end
    end
  end

  # P19-1: THE canonical-memory migration — ledger notes export as dossier
  # files, idempotently; --dry-run touches nothing.
  def test_language_export_dossiers_is_idempotent_and_dry_run_touches_nothing
    with_recon_shelf do |config|
      ledger = Nabu::Store::Ledger.open!(config.history_path)
      ledger[:language_notes].insert(lang_code: "gkm", kind: "name", body: "Medieval Greek",
                                     source: "seed:config/languages.yml", created_at: Time.now)
      ledger.disconnect
      with_config(config) do
        shelf_dir = Nabu::LanguageShelf.dir(config.canonical_dir)
        out, _err, status = run_cli(%w[language --export-dossiers --dry-run])
        assert_nil status
        assert_match(/dossiers: would write 1/, out)
        refute File.exist?(File.join(shelf_dir, "gkm.md")), "dry-run touches nothing"

        out, _err, status = run_cli(%w[language --export-dossiers])
        assert_nil status
        assert_match(/dossiers: wrote 1/, out)
        assert_match(%r{next: bin/nabu sync local-language}, out)
        assert File.file?(File.join(shelf_dir, "gkm.md"))

        out, _err, _status = run_cli(%w[language --export-dossiers])
        assert_match(/dossiers: wrote 0, 1 unchanged/, out, "re-exporting writes nothing")
      end
    end
  end

  def test_language_without_code_or_flag_errors
    with_recon_shelf do |config|
      _out, err, status = with_config(config) { run_cli(%w[language]) }
      assert_equal 1, status
      assert_match(/give a code/, err)
    end
  end

  # -- P18-5: the IE-CoR shelf — cognacy sets as etym/define surfaces, the
  # loan label, and the language card's accreted iecor note ---------------------

  def test_language_card_renders_the_iecor_accreted_note
    with_iecor_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language chu])
        assert_nil status
        assert_match(/^chu — /, out)
        assert_match(/iecor: IE-CoR variety: Old Church Slavonic/, out, "the accreted note renders")
        assert_match(/Balto-Slavic/, out, "the clade travels")
        assert_match(/etymology: \d+ reflex edge/, out, "iecor reflexes count as edges")
      end
    end
  end

  def test_language_card_for_a_code_known_only_through_iecor
    with_iecor_shelf do |config|
      with_config(config) do
        out, _err, status = run_cli(%w[language lit])
        assert_nil status
        assert_match(/^lit — Lithuanian$/, out, "the census name comes from IE-CoR's languages table")
        assert_match(/iecor: IE-CoR variety: Lithuanian/, out)
      end
    end
  end

  def test_etym_reaches_the_iecor_heart_set_from_the_attested_side
    with_iecor_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym срьдьцє --long]) }
      assert_nil status
      assert_match(/срьдьцє \[chu\] → \*k̑erd- \[ine\]/, out, "the upstream asterisk displays verbatim")
      assert_match(/IE-CoR/, out)
      assert_match(/\[got · Gothic\] 𐌷𐌰𐌹𐍂𐍄𐍉 \(hairto\)/, out,
                   "the Gothic witness rides word (roman), named by the iecor census")
      assert_match(/καρδία/, out)
      assert_match(/\[lat( · Latin)?\] cor/, out)
    end
  end

  def test_etym_labels_the_iecor_loan_event_edges
    with_iecor_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym кожа]) }
      assert_nil status
      assert_match(/кожа \[chu\] \(loan\) → \*kož- \[ine\]/, out,
                   "the loans.csv event ORs into the member edge and labels it")
    end
  end

  def test_define_finds_the_iecor_root_by_folded_headword
    with_iecor_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[define kerd-]) }
      assert_nil status
      assert_match(/^\*k̑erd- — IE-CoR/, out)
      assert_match(/cognate set 6458/, out)
      assert_match(/Proto-Indo-European/, out)
    end
  end

  def test_etym_footer_points_at_the_language_desk_reference
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym *zima]) }
      assert_nil status
      assert_match(/^codes: nabu language CODE/, out, "the compact render's way out of raw codes")
    end
  end

  # -- P17-3: the etym ancestor CHAIN renders indented, loans labeled ---------

  def test_etym_renders_the_multi_hop_chain_indented
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym прьстъ]) }
      assert_nil status
      assert_match(/\*pьrstъ \[sla-pro\]/, out)
      assert_match(/^ {2}← \*pírštan \[ine-bsl-pro\]/, out, "hop 1 indents once")
      assert_match(/^ {4}← \*per- \[ine-pro\]/, out, "hop 2 indents twice — the chain reads as a chain")
    end
  end

  def test_etym_labels_a_loan_edge_on_its_arrow
    with_recon_shelf do |config|
      out, _err, status = with_config(config) { run_cli(%w[etym хлѣбъ]) }
      assert_nil status
      assert_match(/^ {2}←\(loan\) \*hlaibaz \[gem-pro\]/, out,
                   "the flagged gem→sla edge labels its own arrow")
      refute_match(/←\(loan\) \*pírštan/, out)
    end
  end

  # -- P15-8: --long expands vocab's truncated hapax list (house rule) --------
  # vocab's ONE marked elision is print_vocab_hapax's "(+N more)" tail: the
  # Greek-PROIEL head-50 fixture holds 211 hapax, so --limit 3 fires the cap by
  # default and --long must list every hapax with no tail. The distinctive
  # table is a "top N" RANKING governed by --limit (no "(+N more)" marker), so
  # --long deliberately leaves it alone — the census verdict argued openly.
  VOCAB_URN = "urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50"

  def test_vocab_hapax_is_capped_by_default
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["vocab", VOCAB_URN, "--limit", "3"]) }
      assert_nil status
      assert_match(/hapax legomena \(211, once each\): .+ \(\+208 more\)/, out,
                   "the 208-past-3 tail is summarised, not listed")
      assert_match(/distinctive vocabulary \(log-odds vs corpus, top 3\)/, out)
    end
  end

  def test_vocab_long_lists_every_hapax_and_leaves_the_ranking_capped
    with_treebank_corpus do |config|
      out, _err, status =
        with_config(config) { run_cli(["vocab", VOCAB_URN, "--limit", "3", "--long"]) }
      assert_nil status
      assert_match(/hapax legomena \(211, once each\): /, out)
      refute_match(/\+\d+ more/, out, "nothing is elided under --long")
      # The distinctive ranking is a --limit knob, not a marked elision: --long
      # leaves "top 3" exactly as the compact default renders it.
      assert_match(/distinctive vocabulary \(log-odds vs corpus, top 3\)/, out,
                   "--long escapes elisions, not the distinctive ranking cap")
    end
  end

  def test_help_export_documents_formats_and_filters
    out, _err, _status = run_cli(%w[help export])
    assert_match(/jsonl/, out)
    assert_match(/annotations/, out, "must say what rides in jsonl lines")
    assert_match(/Examples:/, out)
  end

  # -- list (P22-1): the what-is-held view -----------------------------------

  def test_help_list_documents_the_modes_and_points_at_status
    out, _err, _status = run_cli(%w[help list])
    assert_match(/--documents/, out)
    assert_match(/--entries/, out)
    assert_match(/--collections/, out)
    assert_match(/--prefix/, out)
    assert_match(/nabu status/, out, "the sync-state sibling must be named for discoverability")
    assert_match(/Examples:/, out)
  end

  def test_help_status_points_at_list
    out, _err, _status = run_cli(%w[help status])
    assert_match(/nabu list/, out, "the contents-view sibling must be named for discoverability")
  end

  def test_list_census_one_line_per_source_with_counts_and_mix
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["list"]) }
      assert_nil status, "the census exits 0"
      assert_match(/^shelf\s+docs=2 pass=3\s+langs=grc,lat\s+license=nc,open\s+withdrawn=1\s+retired=1/, out)
      assert_match(/^lex\s+entries=2\s+langs=sla-pro\s+license=attribution/, out)
      assert_match(/^library\s+docs=3/, out)
      assert_match(/3 sources/, out)
    end
  end

  def test_list_census_without_catalog_hints_to_sync_or_rebuild
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(["list"]) }
      assert_equal 1, status
      assert_match(/no catalog.*sync.*rebuild/i, err)
    end
  end

  def test_list_source_card_identity_counts_languages_and_credit
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list shelf]) }
      assert_nil status
      assert_match(/^shelf — Shelf$/, out)
      assert_match(/adapter TestAdapter/, out)
      assert_match(/license nc,open · CC BY-NC 4\.0 \(compiled by Test\)/, out, "credit line rides the card")
      assert_match(/docs=2 pass=3 withdrawn=1 retired=1/, out)
      assert_match(/langs grc=2 lat=1/, out)
      assert_match(/dated 1 doc -113\.\.602/, out)
    end
  end

  def test_list_dictionary_source_card_lists_its_dictionaries
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list lex]) }
      assert_nil status
      assert_match(/entries=2/, out)
      assert_match(/dict sla-pro — Proto-Slavic \[sla-pro\] entries=2/, out)
    end
  end

  # P23-3b: the registry is authoritative for enablement — the card's header
  # shows the registry value even when the db row is stale (a sources.yml
  # flip reaches the db only at the source's next sync).
  def test_list_card_enabled_comes_from_the_registry_not_the_stale_db_row
    with_list_corpus do |config|
      catalog = Nabu::Store.connect(config.catalog_path)
      catalog[:sources].where(slug: "shelf").update(enabled: false) # stale row; registry says true
      catalog.disconnect
      out, _err, status = with_config(config) { run_cli(%w[list shelf]) }
      assert_nil status
      assert_match(/· sync manual · on$/, out, "registry enabled: true must win over the stale db row")
    end
  end

  # The P22-1 loud-orphan case must not regress: a catalog source with no
  # registry line reads NOT IN REGISTRY on its card.
  def test_list_card_of_an_unregistered_catalog_source_reads_loudly
    with_list_corpus do |config|
      catalog = Nabu::Store.connect(config.catalog_path)
      catalog[:sources].insert(slug: "orphan", name: "Orphan", adapter_class: "TestAdapter",
                               license_class: "open", enabled: true)
      catalog.disconnect
      out, _err, status = with_config(config) { run_cli(%w[list orphan]) }
      assert_nil status
      assert_match(/NOT IN REGISTRY/, out)
    end
  end

  def test_list_unknown_source_misses_honestly_naming_the_slugs
    with_list_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[list nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
      assert_match(/shelf/, err, "the miss lists the valid slugs")
    end
  end

  # -- P24-0: the source-dossier consumers ----------------------------------

  def test_list_card_renders_the_dossier_description_under_the_header
    with_list_corpus do |config|
      catalog = Nabu::Store.connect(config.catalog_path)
      catalog[:source_records].insert(
        slug: "shelf", kind: "description", provenance: "dossier",
        body: "A deliberately long shelf description that carries enough words to force the card " \
              "renderer to wrap it onto a second indented line at the house measure."
      )
      catalog.disconnect
      out, _err, status = with_config(config) { run_cli(%w[list shelf]) }
      assert_nil status
      lines = out.lines
      header = lines.index { |line| line.start_with?("shelf — Shelf") }
      assert_match(/^  A deliberately long shelf description/, lines[header + 1],
                   "the description renders directly under the header")
      assert_match(/^  \S/, lines[header + 2], "long descriptions wrap onto further indented lines")
      assert_match(/house measure\.$/, lines[header + 2].chomp, "the prose tail survives the wrap whole")
    end
  end

  def test_list_census_long_adds_one_description_line_per_described_source
    with_list_corpus do |config|
      catalog = Nabu::Store.connect(config.catalog_path)
      catalog[:source_records].insert(slug: "lex", kind: "description",
                                      body: "The reference shelf.", provenance: "dossier")
      catalog.disconnect
      out, _err, status = with_config(config) { run_cli(%w[list --long]) }
      assert_nil status
      assert_match(/^\s+The reference shelf\.$/, out)
      description_lines = out.lines.count { |line| line.match?(/\A\s+\S/) }
      assert_equal 1, description_lines,
                   "only the described source gets a description line (zero fields suppressed)"
    end
  end

  def test_list_long_and_dry_run_flag_validations
    with_list_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[list shelf --long]) }
      assert_equal 1, status
      assert_match(/--long expands the bare census/, err)

      _out, err, status = with_config(config) { run_cli(%w[list --dry-run]) }
      assert_equal 1, status
      assert_match(/--dry-run composes with --export-source-dossiers/, err)

      _out, err, status = with_config(config) { run_cli(%w[list shelf --export-source-dossiers]) }
      assert_equal 1, status
      assert_match(/scaffolds ALL registered sources/, err)
    end
  end

  def test_list_export_source_dossiers_scaffolds_every_registered_source_idempotently
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list --export-source-dossiers]) }
      assert_nil status
      assert_match(/scaffolded 3, 0 existing untouched/, out)
      assert_match(/honest stub/, out, "scratch sources carry no library.md prose — stubs, said so")
      shelf_dir = Nabu::SourceShelf.dir(config.canonical_dir)
      assert File.file?(File.join(shelf_dir, "shelf.md"))
      assert File.file?(File.join(shelf_dir, "lex.md"))
      assert File.file?(File.join(shelf_dir, "library.md"))

      out, _err, status = with_config(config) { run_cli(%w[list --export-source-dossiers]) }
      assert_nil status
      assert_match(/scaffolded 0, 3 existing untouched/, out, "the export is idempotent")
    end
  end

  def test_list_documents_enumerates_with_flags_and_an_honest_tail
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list shelf --documents]) }
      assert_nil status
      assert_match(/urn:nabu:shelf:alpha — Alpha \[grc\] open/, out)
      assert_match(/urn:nabu:shelf:beta — Beta \[lat\] nc \(retired upstream\)/, out)
      assert_match(/urn:nabu:shelf:gone — Gone \[grc\] nc \(withdrawn\)/, out)

      out, _err, status = with_config(config) { run_cli(%w[list shelf --documents --limit 1]) }
      assert_nil status
      assert_match(/… 2 more — raise --limit \(0 = all\)/, out)
    end
  end

  def test_list_documents_filters_compose
    with_list_corpus do |config|
      out, _err, _status = with_config(config) { run_cli(%w[list shelf --documents --lang lat]) }
      assert_match(/urn:nabu:shelf:beta/, out)
      refute_match(/urn:nabu:shelf:alpha/, out)

      out, _err, _status = with_config(config) { run_cli(%w[list shelf --documents --license open]) }
      assert_match(/urn:nabu:shelf:alpha/, out)
      refute_match(/urn:nabu:shelf:beta/, out)

      out, _err, _status = with_config(config) { run_cli(%w[list shelf --documents --withdrawn]) }
      assert_match(/urn:nabu:shelf:gone/, out)
      assert_match(/urn:nabu:shelf:beta/, out, "retired upstream is part of the stewardship lens")
      refute_match(/urn:nabu:shelf:alpha/, out)

      out, _err, _status = with_config(config) { run_cli(%w[list shelf --documents --century -2]) }
      assert_match(/urn:nabu:shelf:alpha/, out)
      refute_match(/urn:nabu:shelf:beta/, out)
    end
  end

  def test_list_entries_enumerates_headwords_with_prefix_folding
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list lex --entries]) }
      assert_nil status
      assert_match(/bʰer- \[sla-pro\] — to carry/, out)
      assert_match(/bogъ \[sla-pro\] — god/, out)

      out, _err, _status = with_config(config) { run_cli(%w[list lex --entries --prefix bh]) }
      assert_match(/bʰer-/, out, "ASCII bh reaches the folded proto headword")
      refute_match(/bogъ/, out)
    end
  end

  def test_list_entries_on_a_passage_shelf_misses_honestly_exit_zero
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list shelf --entries]) }
      assert_nil status, "an honest miss is not a failure"
      assert_match(/no dictionary entries/, out)
      assert_match(/--documents/, out, "the miss points at the lens that works")
    end
  end

  def test_list_collections_census_and_honest_miss
    with_list_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[list library --collections]) }
      assert_nil status
      assert_match(/slavistics\s+docs=2/, out)
      assert_match(/articles\s+docs=1/, out)

      out, _err, status = with_config(config) { run_cli(%w[list shelf --collections]) }
      assert_nil status, "an honest miss is not a failure"
      assert_match(/no collection segments/, out)
    end
  end

  def test_list_flag_guards_are_honest
    with_list_corpus do |config|
      with_config(config) do
        _out, err, status = run_cli(%w[list --documents])
        assert_equal 1, status
        assert_match(/give a SOURCE/, err)

        _out, err, status = run_cli(%w[list shelf --documents --entries])
        assert_equal 1, status
        assert_match(/one of/, err)

        _out, err, status = run_cli(%w[list lex --prefix bh])
        assert_equal 1, status
        assert_match(/--prefix.*--entries/, err)

        _out, err, status = run_cli(%w[list shelf --entries --license open])
        assert_equal 1, status
        assert_match(/--license.*--documents/, err)
      end
    end
  end

  # -- search/export --source (P22-1) ----------------------------------------

  def test_search_source_scopes_and_unknown_source_misses_honestly
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search μηνιν --source corpus]) }
      assert_nil status
      assert_match(/urn:nabu:test_adapter:one:1/, out)

      _out, err, status = with_config(config) { run_cli(%w[search μηνιν --source nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
      assert_match(/corpus/, err, "the miss lists the valid slugs")
    end
  end

  def test_export_source_scopes_the_stream
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[export --format plain --source corpus]) }
      assert_nil status
      assert_match(/μῆνιν/, out)

      _out, err, status = with_config(config) { run_cli(%w[export --format plain --source nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
    end
  end

  # status is implemented (P1-6). Against an empty registry with no catalog db,
  # it reports "no sources" and exits cleanly (0). (The shipped sources.yml now
  # registers perseus-greek, so this behaviour is tested against an isolated
  # empty registry rather than the real config.)
  def test_status_reports_no_sources_and_succeeds
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status, "status should not signal failure with an empty registry"
      assert_match(/no sources registered/i, out)
    end
  end

  # rebuild against an empty registry: nothing to replay, clean exit (0).
  def test_rebuild_empty_registry_says_nothing_to_rebuild
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(["rebuild"]) }
      assert_nil status, "rebuild should not signal failure with an empty registry"
      assert_match(/nothing to rebuild/i, out)
    end
  end

  def test_rebuild_dry_run_lists_plan_and_changes_nothing
    with_rebuild_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[rebuild --dry-run]) }

      assert_nil status
      assert_match(/dry run/i, out)
      assert_match(/replay\s+corpus/, out)
      refute File.exist?(config.catalog_path), "dry run must not build the db"
    end
  end

  def test_rebuild_runs_and_reports_counts
    with_rebuild_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[rebuild]) }

      assert_nil status
      assert_match(/Dropped catalog db/, out)
      assert_match(/corpus.*\+2 added/, out)
      assert_match(/TOTAL.*\+2 added/, out)
      assert_match(/indexed 3 passages/, out) # μῆνιν, ἄειδε, ἄνδρα
      assert File.exist?(config.fulltext_path), "a real run builds the fulltext index"
      assert File.exist?(config.catalog_path), "a real run builds the db"
    end
  end

  # -- backup (P7-2) -------------------------------------------------------

  def test_backup_runs_to_a_local_target_and_reports_ok
    with_backup_env do |config, target|
      out, _err, status = with_config(config) { run_cli(["backup", "--to", target, "--allow-unmounted"]) }

      assert_nil status, "a clean backup exits 0"
      assert_match(/Backup → #{Regexp.escape(target)}/, out)
      assert_match(/canonical\s+ok/, out)
      assert_match(/OK\b/, out)
      assert File.exist?(File.join(target, "canonical", "corpus", "one.txt"))
      assert File.exist?(File.join(target, "config", "sources.yml"))
    end
  end

  def test_backup_dry_run_prints_plan_and_changes_nothing
    with_backup_env do |config, target|
      out, _err, status = with_config(config) { run_cli(["backup", "--to", target, "--allow-unmounted", "--dry-run"]) }

      assert_nil status
      assert_match(/dry run/i, out)
      refute File.exist?(File.join(target, "canonical")), "dry-run writes nothing"
    end
  end

  # The mount-point guard: a same-device tmp target without --allow-unmounted
  # is refused loudly (exit 1), and nothing is written.
  def test_backup_refuses_an_unmounted_target
    with_backup_env do |config, target|
      _out, err, status = with_config(config) { run_cli(["backup", "--to", target]) }

      assert_equal 1, status
      assert_match(/volume not mounted/i, err)
      refute File.exist?(File.join(target, "canonical"))
    end
  end

  def test_help_backup_documents_the_set_guard_and_examples
    out, _err, _status = run_cli(%w[help backup])
    assert_match(/mount-point guard/i, out)
    assert_match(/\.attic/, out, "must explain why the attic rides along")
    assert_match(/--skip-derived/, out)
    assert_match(/Examples:/, out)
  end

  # -- verify (P4-4) -------------------------------------------------------

  def test_verify_clean_corpus_reports_ok_and_exits_zero
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) } # build the catalog first
      out, _err, status = with_config(config) { run_cli(%w[verify]) }

      assert_nil status, "a clean verify exits 0"
      assert_match(/OK\s+corpus\s+\(2 documents verified\)/, out)
      assert_match(/All canonical documents verified/, out)
    end
  end

  def test_verify_corrupted_file_reports_mismatch_and_exits_one
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) }
      # Change a word in one canonical file (filename unchanged ⇒ same urn).
      File.write(File.join(config.canonical_dir, "corpus", "one.txt"), "Iliad\nμῆνιν\nΧΧΧ\n")

      out, err, status = with_config(config) { run_cli(%w[verify]) }

      assert_equal 1, status
      assert_match(/FAILED\s+corpus/, out)
      assert_match(/MISMATCH\s+urn:nabu:test_adapter:one/, out)
      assert_match(/Integrity check FAILED/, out)
      assert_match(/failed the integrity check/, err)
    end
  end

  def test_verify_without_catalog_hints_to_sync_or_rebuild
    with_rebuild_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[verify]) }
      assert_equal 1, status
      assert_match(/no catalog/i, err)
    end
  end

  # -- sync (P2-4) ---------------------------------------------------------

  def test_sync_without_slug_or_all_fails
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[sync]) }
      assert_equal 1, status
      assert_match(/slug or --all/i, err)
    end
  end

  def test_sync_unknown_slug_fails
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[sync nope]) }
      assert_equal 1, status
      assert_match(/unknown source/i, err)
    end
  end

  # --parse-only skips fetch, so TestAdapter (whose #fetch is unimplemented)
  # loads straight off the canonical dir and the counts are reported.
  def test_sync_parse_only_loads_and_reports_counts
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      assert_match(/corpus\s+parse-only/, out)
      assert_match(/\+2 added/, out)
      # P26-5: the sync line reports the SOURCE's own indexed rows, labeled —
      # never the corpus total.
      assert_match(/indexed 3 passages \(corpus\)/, out) # μῆνιν, ἄειδε, ἄνδρα
    end
  end

  # P19-1: the local shelf end to end — a REAL `nabu sync local-language`
  # (fetch = LocalFetch re-scan, per-file ledger pins, records derived), then
  # the card reads the merged view from the derived records. No network:
  # sync_policy local never touches one.
  def test_sync_local_language_scans_pins_and_derives_then_the_card_reads_it
    Dir.mktmpdir("nabu-cli-local") do |root|
      shelf = File.join(root, "canonical", "local-language")
      FileUtils.mkdir_p(File.dirname(shelf))
      FileUtils.cp_r(Nabu::TestSupport.fixtures("local-language"), shelf)
      sources = File.join(root, "sources.yml")
      File.write(sources, <<~YAML)
        local-language:
          adapter: Nabu::Adapters::LocalLanguage
          enabled: true
          sync_policy: local
      YAML
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      with_config(config) do
        out, _err, status = run_cli(%w[sync local-language])
        assert_nil status
        assert_match(/added/, out)
        # P26-5 Part A: an index-inert shelf's sync does no index work, and
        # the line honestly omits the "indexed N passages" fragment.
        refute_match(/indexed \d+ passages/, out, "an inert shelf sync must not claim index work")

        ledger = Nabu::Store::Ledger.open!(config.history_path)
        pins = ledger[:pins].where(source_slug: "local-language").select_map(:repo_url)
        ledger.disconnect
        assert_includes pins, "local:chu.md", "one ledger pin per scanned file"

        out, _err, status = run_cli(%w[language sla-pro])
        assert_nil status
        assert_match(/^sla-pro — Proto-Slavic$/, out)
        assert_match(/family: Slavic < Balto-Slavic/, out)

        out, _err, _status = run_cli(%w[language ine-pro])
        assert_match(/witness \(liv\): LIV — Lexikon/, out, "dossier sections render as witness lanes")
        assert_match(/period: reconstructed/, out, "front-matter extras render as extra lanes")

        out, _err, _status = run_cli(%w[sync local-language])
        assert_match(/0 added/, out, "a re-scan of an unchanged shelf loads nothing")
      end
    end
  end

  # Explicit beats config: a disabled source named by slug still syncs, with a
  # printed note.
  def test_sync_disabled_source_by_slug_prints_note_and_runs
    with_sync_env(enabled: false) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      assert_match(/disabled; syncing anyway/i, out)
      assert_match(/\+2 added/, out)
    end
  end

  # -- sync --review (P18-7): the optional post-sync hook --------------------

  # The hook gets the JSON brief on stdin (tool-agnostic stub: a shell
  # command), its output is relayed, exit 0 reported.
  def test_sync_review_pipes_the_brief_and_relays_the_hook_output
    with_sync_env(enabled: true) do |config|
      sink = File.join(config.canonical_dir, "..", "brief.json")
      out, _err, status = with_config(config) do
        run_cli(["sync", "corpus", "--parse-only", "--review", "tee #{sink} >/dev/null && echo LGTM"])
      end
      assert_nil status, "the sync itself succeeded"
      assert_match(/review\| LGTM/, out)
      assert_match(/review hook: exit 0/, out)
      brief = JSON.parse(File.read(sink))
      assert_equal "nabu.sync-review/1", brief["schema"]
      assert_equal "corpus", brief["source"]
      assert_equal 2, brief.dig("counts", "added")
      assert_equal 2, brief["sample_urns"].size
    end
  end

  # NON-FATALITY: the hook's failure is reported and the sync still exits 0.
  def test_sync_review_hook_failure_never_fails_the_sync
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) do
        run_cli(["sync", "corpus", "--parse-only", "--review", "cat >/dev/null; echo no thanks >&2; exit 7"])
      end
      assert_nil status, "a failing review hook must never fail the sync"
      assert_match(/\+2 added/, out, "the sync report still prints")
      assert_match(/review\| no thanks/, out)
      assert_match(/review hook: exit 7 \(advisory — sync unaffected\)/, out)
    end
  end

  # Off by default: no --review, no hook, no review lines.
  def test_sync_without_review_runs_no_hook
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) { run_cli(%w[sync corpus --parse-only]) }
      assert_nil status
      refute_match(/review/, out)
    end
  end

  # -- progress reporting (P2-6) -------------------------------------------

  # When $stderr is a tty, the loader's per-document ticks render a \r-updating
  # "loading…" counter on $stderr; the final counts still land on $stdout.
  def test_sync_progress_hits_stderr_when_tty_stdout_counts_unchanged
    with_sync_env(enabled: true) do |config|
      out, err = with_config(config) do
        capture_with_tty(stderr_tty: true) { Nabu::CLI.start(%w[sync corpus --parse-only]) }
      end
      assert_match(/loading…/, err, "tty progress must write the counter to $stderr")
      assert_match(/corpus\s+parse-only/, out, "final counts stay on $stdout")
      assert_match(/\+2 added/, out)
      refute_match(/loading…/, out, "progress must not leak into $stdout")
    end
  end

  # Non-tty (the default in the suite): a small corpus stays completely silent
  # on $stderr — the per-100-docs line never triggers for two documents.
  def test_sync_non_tty_small_corpus_emits_no_progress
    with_sync_env(enabled: true) do |config|
      _out, err = with_config(config) do
        capture_with_tty(stderr_tty: false) { Nabu::CLI.start(%w[sync corpus --parse-only]) }
      end
      assert_empty err, "non-tty small corpus must not emit progress"
    end
  end

  # -- quickstart (P18-2): the starter shelf --------------------------------

  # The starter list must stay wired to real registry entries: every slug in
  # STARTER_SOURCES is registered AND enabled in the shipped config/sources.yml
  # (a renamed/retired source would otherwise fail only at a live quickstart).
  def test_quickstart_starter_sources_are_registered_in_the_shipped_registry
    registry = Nabu::SourceRegistry.load(File.expand_path("../config/sources.yml", __dir__))
    Nabu::CLI.starter_sources.each do |starter|
      entry = registry[starter.slug]
      refute_nil entry, "starter source #{starter.slug} must be registered in config/sources.yml"
      assert entry.enabled, "starter source #{starter.slug} must be enabled"
    end
  end

  # --list previews the set (slugs, sizes, blurbs) and touches nothing: no
  # network (WebMock would trip), no catalog, no ledger.
  def test_quickstart_list_prints_the_starter_set_without_syncing
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[quickstart --list]) }
      assert_nil status
      assert_match(/starter shelf/, out)
      %w[sblgnt proiel iswoc lexica].each do |slug|
        assert_match(/^  #{slug}\b/, out, "--list must name #{slug}")
      end
      assert_match(/MB/, out, "--list must carry the measured sizes")
      refute File.exist?(config.catalog_path), "--list must not create the catalog"
      refute File.exist?(config.history_path), "--list must not create the ledger"
    end
  end

  # The command syncs the starter list IN ORDER through the normal per-source
  # path (fetch → load → index) and ends with the "try these" epilogue naming
  # the three marvels and the growth pointer.
  def test_quickstart_syncs_the_starter_list_in_order_and_prints_the_epilogue
    with_quickstart_env("alpha" => "QuickstartFetchAdapter", "beta" => "QuickstartFetchAdapter") do |config|
      with_starter_sources(%w[alpha beta]) do
        out, _err, status = with_config(config) { run_cli(%w[quickstart]) }
        assert_nil status
        assert_match(/alpha\s+deadbeefcafe\s+\+2 added/, out)
        assert_match(/beta\s+deadbeefcafe\s+\+2 added/, out)
        assert_operator out.index("alpha "), :<, out.index("beta "), "starter order must be respected"
        assert_match(/try these:/, out)
        assert_match(/align "MARK 2\.3"/, out)
        assert_match(/search --lemma/, out)
        assert_match(/define λόγος/, out)
        assert_match(%r{grow the library: bin/nabu sync --all}, out)
      end
    end
  end

  # Idempotent by construction: a re-run is an ordinary re-sync (same content
  # on disk → =N skipped, nothing re-added), and the epilogue still prints.
  def test_quickstart_rerun_is_an_ordinary_resync
    with_quickstart_env("alpha" => "QuickstartFetchAdapter") do |config|
      with_starter_sources(%w[alpha]) do
        with_config(config) { run_cli(%w[quickstart]) }
        out, _err, status = with_config(config) { run_cli(%w[quickstart]) }
        assert_nil status
        assert_match(/alpha\s+deadbeefcafe\s+\+0 added\s+~0 updated\s+=2 skipped/, out)
        assert_match(/try these:/, out)
      end
    end
  end

  # One source's failure never stops the rest: the failure is reported at the
  # end (stdout, before the epilogue), the batch exit status is 1, and the
  # later sources still sync. An unregistered starter slug fails the same way.
  def test_quickstart_one_failure_does_not_stop_the_rest_and_exits_one
    with_quickstart_env("alpha" => "QuickstartFailingAdapter", "beta" => "QuickstartFetchAdapter") do |config|
      with_starter_sources(%w[alpha beta ghost]) do
        out, err, status = with_config(config) { run_cli(%w[quickstart]) }
        assert_equal 1, status
        assert_match(/beta\s+deadbeefcafe\s+\+2 added/, out, "a failure must not stop later sources")
        assert_match(/alpha\s+FAILED — upstream unreachable/, out)
        assert_match(/ghost\s+FAILED — unknown source/, out)
        assert_match(/try these:/, out, "the epilogue still prints after failures")
        assert_match(/2 of 3 starter sources failed/, err)
      end
    end
  end

  # `nabu help quickstart` must teach the starter shelf: what it holds (with
  # sizes), the three marvels, --list, and the idempotency promise.
  def test_help_quickstart_documents_the_starter_shelf
    out, _err, _status = run_cli(%w[help quickstart])
    %w[sblgnt proiel iswoc lexica].each { |slug| assert_match(/#{slug}/, out) }
    assert_match(/MB/, out, "must state the measured sizes")
    assert_match(/align "MARK 2\.3"/, out)
    assert_match(/--lemma/, out)
    assert_match(/define λόγος/, out)
    assert_match(/--list/, out)
    assert_match(/idempotent/i, out)
    assert_match(/never stops the rest/i, out, "must state the partial-failure posture")
  end

  # -- ingest (P19-5): the canonical-memory intake front door ----------------

  # A scratch root with both local shelves registered (the real adapters —
  # sync_policy local means no network anywhere on this path).
  def with_ingest_env
    Dir.mktmpdir("nabu-cli-ingest") do |root|
      sources = <<~YAML
        local-library:
          adapter: Nabu::Adapters::LocalLibrary
          enabled: true
          sync_policy: local
        local-language:
          adapter: Nabu::Adapters::LocalLanguage
          enabled: true
          sync_policy: local
      YAML
      path = File.join(root, "sources.yml")
      File.write(path, sources)
      FileUtils.mkdir_p(File.join(root, "canonical"))
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: path, config_path: "(test)"
      )
      yield config, root
    end
  end

  def write_note(root, name = "reading-notes.txt")
    path = File.join(root, name)
    File.write(path, "Marginalia on the Marianus gospel codex.\n\nSecond paragraph on Jagić.\n")
    path
  end

  def test_ingest_yes_copies_appends_syncs_and_prints_minted_urns_with_the_try_epilogue
    with_ingest_env do |config, root|
      source = write_note(root)
      out, _err, status = with_config(config) do
        run_cli(["ingest", source, "--yes", "--collection", "notes",
                 "--languages", "eng", "--related", "urn:nabu:ccmh:mar:mt"])
      end
      assert_nil status
      assert_match(%r{added\s+reading-notes\.txt → notes/reading-notes\.txt}, out)
      assert_match(/local-library\s+\S+\s+\+1 added/, out, "the shelf's ordinary sync runs after the append")
      assert_match(/minted:\n  urn:nabu:local-library:notes:reading-notes/, out)
      assert_match(%r{try:\n  bin/nabu show urn:nabu:local-library:notes:reading-notes}, out)
      assert_match(%r{bin/nabu search Marginalia --license research_private}, out)
      assert_match(%r{bin/nabu links urn:nabu:local-library:notes:reading-notes}, out,
                   "related urns just became reference edges — point at them")
      assert_path_exists source, "ingest copies, never moves"
      copied = File.join(config.canonical_dir, "local-library", "notes", "reading-notes.txt")
      assert_equal File.read(source), File.read(copied)
      manifest = Nabu::LibraryManifest.load(File.join(File.dirname(copied), "manifest.yml"))
      assert_equal ["reading-notes.txt"], manifest.entries.map(&:file)
      assert_equal ["eng"], manifest.entries.first.languages
    end
  end

  def test_ingest_reingesting_the_same_bytes_is_a_no_op_without_a_sync
    with_ingest_env do |config, root|
      source = write_note(root)
      with_config(config) { run_cli(["ingest", source, "--yes"]) }
      out, _err, status = with_config(config) { run_cli(["ingest", source, "--yes"]) }
      assert_nil status
      assert_match(/skipped\s+reading-notes\.txt — identical bytes already catalogued/, out)
      refute_match(/minted:/, out, "nothing landed, nothing minted, no sync")
    end
  end

  # P20-1 owner doctrine: a batch lands WHOLE or not at all — a defect
  # anywhere names itself, the valid files say aborted, canonical is
  # byte-identical, exit 1. (Replaces the old bad-file-named-rest-proceed
  # ladder, which let a typo'd batch half-land.)
  def test_ingest_names_the_bad_file_and_aborts_the_whole_batch
    with_ingest_env do |config, root|
      source = write_note(root)
      out, err, status = with_config(config) do
        run_cli(["ingest", File.join(root, "ghost.pdf"), source, "--yes"])
      end
      assert_equal 1, status
      assert_match(/FAILED\s+ghost\.pdf/, out)
      assert_match(/aborted\s+reading-notes\.txt — not ingested — batch aborted, canonical untouched/, out)
      refute_match(/minted:/, out, "nothing lands, nothing syncs")
      refute Dir.exist?(File.join(config.canonical_dir, "local-library")), "canonical untouched"
      assert_match(/1 of 2 file\(s\) failed/, err)
    end
  end

  # P20-1 (the "chu (body ger)" incident): a bad --languages flag is one
  # named FAILED line from the PREPARE phase — no copy, no manifest entry,
  # canonical byte-identical; the manifest can never be poisoned.
  def test_ingest_yes_with_a_bad_languages_flag_fails_in_prepare_touching_nothing
    with_ingest_env do |config, root|
      source = write_note(root)
      out, err, status = with_config(config) do
        run_cli(["ingest", source, "--yes", "--languages", "chu (body ger)"])
      end
      assert_equal 1, status
      assert_match(/FAILED\s+reading-notes\.txt — .*"chu \(body ger\)" is not a language tag/, out)
      refute_match(/minted:/, out)
      assert_match(/1 of 1 file\(s\) failed/, err)
      refute Dir.exist?(File.join(config.canonical_dir, "local-library")),
             "atomic: a failed ingest leaves canonical byte-identical — no stray copy, no manifest"
    end
  end

  def test_ingest_refuses_an_executable_file_with_an_honest_line
    with_ingest_env do |config, root|
      rogue = File.join(root, "nabu")
      File.write(rogue, "#!/usr/bin/env ruby\n")
      File.chmod(0o755, rogue)
      out, _err, status = with_config(config) { run_cli(["ingest", rogue, "--yes"]) }
      assert_equal 1, status
      assert_match(/FAILED\s+nabu — nabu is executable \(mode \+x\) — refusing; shelf material never runs/,
                   out)
      refute Dir.exist?(File.join(config.canonical_dir, "local-library"))
    end
  end

  def test_ingest_url_end_to_end_downloads_ingests_and_records_the_original_url
    url = "https://archive.org/download/handbuch/handbuch-notes.txt"
    mirror = "https://ia601500.us.archive.org/5/items/handbuch/handbuch-notes.txt"
    stub_request(:get, url).to_return(status: 302, headers: { "Location" => mirror })
    stub_request(:get, mirror).to_return(status: 200, body: "Altbulgarische Marginalien.\n\nZweiter Absatz.\n")
    with_ingest_env do |config, _root|
      out, _err, status = with_config(config) { run_cli(["ingest", url, "--yes"]) }
      assert_nil status
      assert_match(%r{added\s+handbuch-notes\.txt → inbox/handbuch-notes\.txt}, out)
      assert_match(/minted:\n  urn:nabu:local-library:inbox:handbuch-notes/, out)
      copied = File.join(config.canonical_dir, "local-library", "inbox", "handbuch-notes.txt")
      assert_equal "Altbulgarische Marginalien.\n\nZweiter Absatz.\n", File.read(copied),
                   "the mirror body landed through the ordinary intake"
      entry = Nabu::LibraryManifest.load(File.join(File.dirname(copied), "manifest.yml")).entries.first
      assert_equal url, entry.source_url, "the manifest records the url the owner gave, not the mirror"
    end
  end

  # The 2026-07-14 incident, exactly: interactive mode, a bad argument —
  # the categorize header must NOT print before validation/download settles.
  def test_ingest_url_failure_is_one_honest_line_without_a_categorize_header
    url = "https://archive.org/download/ghost/ghost.pdf"
    stub_request(:get, url).to_return(status: 404)
    with_ingest_env do |config, _root|
      out, err, status = with_config(config) do
        with_tty_stdin { run_cli(["ingest", url]) }
      end
      assert_equal 1, status
      refute_match(/categorize/, out, "no interactive header before the download settles")
      assert_match(/FAILED\s+ghost\.pdf — .*HTTP 404/, out)
      assert_match(/1 of 1 file\(s\) failed/, err)
    end
  end

  def test_ingest_missing_local_file_prints_no_categorize_header_either
    with_ingest_env do |config, root|
      out, _err, status = with_config(config) do
        with_tty_stdin { run_cli(["ingest", File.join(root, "ghost.pdf")]) }
      end
      assert_equal 1, status
      refute_match(/categorize/, out, "existence is validated before any interactive furniture")
      assert_match(/FAILED\s+ghost\.pdf/, out)
    end
  end

  # A stdin double that CLAIMS a TTY (so the interactive resolver is chosen)
  # without ever being read — for asserting what must NOT prompt.
  def with_tty_stdin
    original = $stdin
    fake = Object.new
    def fake.tty? = true
    $stdin = fake
    yield
  ensure
    $stdin = original
  end

  def test_ingest_without_a_tty_and_without_yes_refuses_honestly
    with_ingest_env do |config, root|
      source = write_note(root)
      _out, err, status = with_config(config) { run_cli(["ingest", source]) }
      assert_equal 1, status
      assert_match(/needs a TTY — pass --yes/, err)
      refute_path_exists File.join(config.canonical_dir, "local-library", "inbox", "reading-notes.txt"),
                         "nothing is copied before the mode question is settled"
    end
  end

  def test_ingest_shelf_language_scaffolds_a_dossier_and_syncs_the_dossier_shelf
    with_ingest_env do |config, _root|
      out, _err, status = with_config(config) do
        run_cli(["ingest", "--shelf", "language", "zle-ort", "--yes",
                 "--name", "Old Ruthenian", "--context", "Chancery language of the GDL."])
      end
      assert_nil status
      assert_match(/added\s+zle-ort dossier scaffolded/, out)
      # The dossier loader counts derived RECORDS (name/family/context lanes),
      # not files — three lanes scaffolded → +3 added.
      assert_match(/local-language\s+\S+\s+\+3 added/, out)
      assert_match(%r{try: bin/nabu language zle-ort}, out)
      dossier = File.join(config.canonical_dir, "local-language", "zle-ort.md")
      assert_path_exists dossier
      assert_match(/name: Old Ruthenian/, File.read(dossier))
      assert_match(/family: zle/, File.read(dossier), "the family candidate derives from the code prefix")
    end
  end

  def test_ingest_shelf_language_is_a_no_op_on_an_existing_dossier
    with_ingest_env do |config, _root|
      FileUtils.mkdir_p(File.join(config.canonical_dir, "local-language"))
      File.write(File.join(config.canonical_dir, "local-language", "chu.md"),
                 "---\ncode: chu\nname: Old Church Slavonic\n---\n")
      out, _err, status = with_config(config) { run_cli(%w[ingest --shelf language chu --yes]) }
      assert_nil status
      assert_match(/skipped\s+chu — dossier exists — edit/, out)
    end
  end

  def test_ingest_flag_guards_are_honest
    with_ingest_env do |config, root|
      source = write_note(root)
      _out, err, status = with_config(config) { run_cli(["ingest", source, "--yes", "--name", "X"]) }
      assert_equal 1, status
      assert_match(/--name only applies with --shelf language/, err)
      _out, err, status = with_config(config) { run_cli(%w[ingest --shelf attic x --yes]) }
      assert_equal 1, status
      assert_match(/unknown shelf/, err)
      _out, err, status = with_config(config) do
        run_cli(["ingest", "--shelf", "language", "chu", "--yes", "--title", "X"])
      end
      assert_equal 1, status
      assert_match(/--title is a library-shelf field/, err)
    end
  end

  # -- nabu note (P24-1): the owner-annotation lane ---------------------------

  ILIAD_DOC = "urn:nabu:test_adapter:one"

  # A corpus catalog (TestAdapter, rebuilt) + the local-notes shelf
  # registered: what `nabu note` needs to resolve urns and run the shelf
  # sync after an append.
  def with_note_env
    Dir.mktmpdir("nabu-cli-note") do |root|
      sources = <<~YAML
        corpus:
          adapter: TestAdapter
          enabled: true
        local-notes:
          adapter: Nabu::Adapters::LocalNotes
          enabled: true
          sync_policy: local
      YAML
      path = File.join(root, "sources.yml")
      File.write(path, sources)
      canonical = File.join(root, "canonical")
      FileUtils.mkdir_p(File.join(canonical, "corpus"))
      File.write(File.join(canonical, "corpus", "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      config = Nabu::Config.new(canonical_dir: canonical, db_dir: File.join(root, "db"),
                                sources_path: path, config_path: "(test)")
      capture_io { Nabu::Rebuild.new(config: config, registry: Nabu::SourceRegistry.load(path)).run }
      yield config, root
    end
  end

  def test_note_scripted_append_is_surgical_fast_and_renders_on_show
    with_note_env do |config, _root|
      out, _err, status = with_config(config) do
        run_cli(["note", ILIAD_DOC, "Collate against Jagić 1883.", "--tags", "collation,ocs"])
      end
      assert_nil status
      assert_match(/noted\s+#{Regexp.escape(ILIAD_DOC)}/, out)
      # The 2026-07-18 owner defect: the append ran the shelf's FULL sync
      # (LocalFetch discovery + the corpus indexer — minutes for one line).
      # The fast path replaces one topic's derived rows surgically: no sync
      # furniture may ever appear here again.
      refute_match(/loading…|indexed \d+ passages|discovery:/, out,
                   "a note append must never run the sync pipeline")
      assert_match(%r{try: bin/nabu show #{Regexp.escape(ILIAD_DOC)}}, out)
      notes = Nabu::NoteFile.load(File.join(config.canonical_dir, "local-notes", "notes.yml"))
      assert_equal [ILIAD_DOC], notes.records.map(&:urn)
      assert_equal %w[collation ocs], notes.records.first.tags

      shown, = with_config(config) { run_cli(["show", ILIAD_DOC]) }
      assert_match(/owner note \(notes, \d{4}-\d{2}-\d{2}\): Collate against Jagić 1883\.  \[collation, ocs\]/,
                   shown, "the show footer carries the note")
    end
  end

  def test_note_on_a_passage_counts_as_a_child_on_the_document_and_renders_on_the_passage
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", "#{ILIAD_DOC}:1", "The invocation line."]) }
      doc_view, = with_config(config) { run_cli(["show", ILIAD_DOC]) }
      assert_match(/passage notes: 1/, doc_view, "a document counts its passage-note children")
      refute_match(/owner note .*invocation/, doc_view, "the child note renders on the child, not the parent")
      passage_view, = with_config(config) { run_cli(["show", "#{ILIAD_DOC}:1"]) }
      assert_match(/owner note \(notes, .*\): The invocation line\./, passage_view)
    end
  end

  def test_note_typod_urn_is_an_error_naming_the_miss_and_writes_nothing
    with_note_env do |config, _root|
      _out, err, status = with_config(config) { run_cli(["note", "urn:nabu:test_adapter:eno", "typo"]) }
      assert_equal 1, status
      assert_match(/urn:nabu:test_adapter:eno does not resolve/, err)
      assert_match(/--force/, err, "the planned-material escape hatch is taught")
      refute Dir.exist?(File.join(config.canonical_dir, "local-notes")), "a refusal writes nothing"
    end
  end

  def test_note_force_records_a_dangling_note_and_list_flags_it
    with_note_env do |config, _root|
      out, _err, status = with_config(config) do
        run_cli(["note", "urn:nabu:planned:vaillant", "Order the reprint.", "--force", "--topic", "acquisitions"])
      end
      assert_nil status
      assert_match(/reads \(dangling\)/, out, "the append says the urn is not held yet")
      listed, _err, list_status = with_config(config) { run_cli(%w[note --list]) }
      assert_nil list_status
      pattern = /urn:nabu:planned:vaillant \(dangling\) — \[\h{8}\] \(acquisitions, \d{4}-\d{2}-\d{2}\)/
      assert_match(pattern,
                   listed)
    end
  end

  def test_note_without_text_shows_existing_notes_a_read_not_a_write
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", ILIAD_DOC, "First thought."]) }
      out, _err, status = with_config(config) { run_cli(["note", ILIAD_DOC]) }
      assert_nil status
      assert_match(/notes on #{Regexp.escape(ILIAD_DOC)} \(1\):/, out)
      assert_match(/\(notes, \d{4}-\d{2}-\d{2}\) First thought\./, out)
      assert_match(/add another/, out)
      assert_equal 1, Nabu::NoteFile.load(File.join(config.canonical_dir, "local-notes", "notes.yml"))
                                    .records.size, "showing is a read — nothing appended"
    end
  end

  def test_note_without_text_without_a_tty_refuses_before_any_write
    with_note_env do |config, _root|
      _out, err, status = with_config(config) { run_cli(["note", ILIAD_DOC]) }
      assert_equal 1, status
      assert_match(/no TTY to prompt/, err)
      assert_match(/nothing was written/, err)
      refute Dir.exist?(File.join(config.canonical_dir, "local-notes"))
    end
  end

  def test_note_interactive_prompts_on_a_tty_and_appends
    with_note_env do |config, _root|
      out, _err, status = with_config(config) do
        with_stdin_lines("Prompted marginal note.\n") { run_cli(["note", ILIAD_DOC]) }
      end
      assert_nil status
      assert_match(/note for #{Regexp.escape(ILIAD_DOC)}/, out, "the ingest prompt furniture")
      assert_match(/noted\s+#{Regexp.escape(ILIAD_DOC)}/, out)
      notes = Nabu::NoteFile.load(File.join(config.canonical_dir, "local-notes", "notes.yml"))
      assert_equal ["Prompted marginal note."], notes.records.map(&:note)
    end
  end

  def test_note_list_shows_stable_computed_ids
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", ILIAD_DOC, "First."]) }
      out, = with_config(config) { run_cli(%w[note --list]) }
      id = out[/\[([0-9a-f]{8})\]/, 1]
      refute_nil id, "--list shows the 8-hex computed id"
      again, = with_config(config) { run_cli(%w[note --list]) }
      assert_includes again, "[#{id}]", "ids are content-derived — stable across reads"
    end
  end

  def test_note_rm_removes_one_note_and_its_derived_row
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", ILIAD_DOC, "Keep me."]) }
      with_config(config) { run_cli(["note", ILIAD_DOC, "Remove me."]) }
      out, = with_config(config) { run_cli(%w[note --list]) }
      id = out[/\[([0-9a-f]{8})\] \(notes, [^)]+\) Remove me\./, 1]
      refute_nil id
      removed, _err, status = with_config(config) { run_cli(["note", "--rm", id]) }
      assert_nil status
      assert_match(/removed\s+\[#{id}\]/, removed)
      refute_match(/loading…|indexed \d+ passages/, removed, "removal stays surgical")
      listing, = with_config(config) { run_cli(%w[note --list]) }
      assert_includes listing, "Keep me."
      refute_includes listing, "Remove me."
      notes = Nabu::NoteFile.load(File.join(config.canonical_dir, "local-notes", "notes.yml"))
      assert_equal ["Keep me."], notes.records.map(&:note)
    end
  end

  def test_note_rm_last_note_deletes_the_topic_file_and_rows
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", ILIAD_DOC, "Only one.", "--topic", "solo"]) }
      out, = with_config(config) { run_cli(%w[note --list --topic solo]) }
      id = out[/\[([0-9a-f]{8})\]/, 1]
      _rm, _err, status = with_config(config) { run_cli(["note", "--rm", id, "--topic", "solo"]) }
      assert_nil status
      refute_path_exists File.join(config.canonical_dir, "local-notes", "solo.yml"),
                         "an empty notes file is furniture, not content"
      listing, = with_config(config) { run_cli(%w[note --list --topic solo]) }
      assert_match(/no notes yet/, listing)
    end
  end

  def test_note_rm_unknown_id_is_an_honest_miss
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", ILIAD_DOC, "Something."]) }
      _out, err, status = with_config(config) { run_cli(%w[note --rm deadbeef]) }
      assert_equal 1, status
      assert_match(/no note with id deadbeef/, err)
    end
  end

  def test_note_list_is_bounded_and_topic_narrowed
    with_note_env do |config, _root|
      with_config(config) { run_cli(["note", ILIAD_DOC, "General note."]) }
      with_config(config) { run_cli(["note", "#{ILIAD_DOC}:1", "Logged.", "--topic", "reading-log"]) }
      out, = with_config(config) { run_cli(%w[note --list --limit 1]) }
      assert_match(/— \[\h{8}\] \(notes, .*\) General note\./, out)
      assert_match(/… and 1 more \(--limit lifts/, out, "the honest total survives the bound")
      narrowed, = with_config(config) { run_cli(%w[note --list --topic reading-log]) }
      assert_match(/Logged\./, narrowed)
      refute_match(/General note/, narrowed)
    end
  end

  def test_note_on_a_dictionary_entry_urn_renders_after_the_define_body
    with_note_env do |config, _root|
      folded = Nabu::Normalize.search_form("λόγος", language: "grc")
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.first(slug: "corpus")
      dictionary = Nabu::Store::Dictionary.create(source_id: source.id, slug: "lsj", title: "LSJ",
                                                  language: "grc")
      Nabu::Store::DictionaryEntry.create(dictionary_id: dictionary.id, urn: "urn:nabu:dict:lsj:logos",
                                          entry_id: "logos", key_raw: "λόγος", headword: "λόγος",
                                          headword_folded: folded, body: "the word, the account",
                                          content_sha256: "x")
      db.disconnect
      with_config(config) { run_cli(["note", "urn:nabu:dict:lsj:logos", "Anchor for John 1.1."]) }

      defined, _err, status = with_config(config) { run_cli(%w[define λόγος]) }
      assert_nil status
      assert_match(/owner note \(notes, .*\): Anchor for John 1\.1\./, defined,
                   "entry notes render after the define body")
      shown, = with_config(config) { run_cli(%w[show urn:nabu:dict:lsj:logos]) }
      assert_match(/owner note \(notes, .*\): Anchor for John 1\.1\./, shown,
                   "show on the minted dict urn carries the same footer")
    end
  end

  def test_links_shows_an_owner_notes_lane
    with_parallels_corpus do |config|
      with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      db = Nabu::Store.connect(config.catalog_path)
      db[:urn_notes].insert(urn: "urn:h:od:1.1", note: "The anchor verse of the survey.", topic: "notes",
                            added: "2026-07-16", provenance: "local-notes/notes.yml")
      db.disconnect
      out, _err, status = with_config(config) { run_cli(%w[links urn:h:od:1.1]) }
      assert_nil status
      assert_match(/owner notes \(1\):\n  \[\h{8}\] \(notes, 2026-07-16\) The anchor verse of the survey\./, out,
                   "notes are a lane beside the mined edges")
    end
  end

  # A stdin double that claims a TTY AND yields scripted lines — the
  # interactive-note rig (Thor's ask reads $stdin.gets).
  def with_stdin_lines(script)
    original = $stdin
    fake = StringIO.new(script)
    def fake.tty? = true
    $stdin = fake
    yield
  ensure
    $stdin = original
  end

  def test_help_note_documents_the_modes_the_resolution_rule_and_force
    out, _err, _status = run_cli(%w[help note])
    assert_match(%r{canonical/local-notes}, out, "canonical memory is stated")
    assert_match(/RESOLVE/, out, "the resolution rule is taught")
    assert_match(/--force/, out)
    assert_match(/dangling/, out)
    assert_match(/--list/, out)
    assert_match(/Examples:/, out)
  end

  # `nabu help ingest` must teach the front door: the three modes, the
  # license default, the copy-never-move promise, and the language scaffold.
  def test_help_ingest_documents_the_three_modes_and_the_license_default
    out, _err, _status = run_cli(%w[help ingest])
    assert_match(/never move/, out)
    assert_match(/interactive/, out)
    assert_match(/--assist CMD/, out)
    assert_match(/--yes/, out)
    assert_match(/research_private/, out, "the shelf's license default is stated")
    assert_match(/--shelf language CODE/, out)
    assert_match(/ingest-assist-claude/, out, "the bundled example hook is named")
    assert_match(/Examples:/, out)
    assert_match(%r{https?://}, out, "the url form is taught")
    assert_match(/source_url/, out, "the provenance lane is named")
  end

  # -- the history ledger at the CLI seam (P7-1) ----------------------------

  # Fresh bootstrap: no ledger file exists; status degrades honestly, the
  # first sync creates it, and the recorded run shows up in status.
  def test_first_sync_creates_the_ledger_and_status_reads_it
    with_sync_env(enabled: true) do |config|
      refute File.exist?(config.history_path), "no ledger before the first sync"

      with_config(config) { run_cli(%w[sync corpus --parse-only]) }

      assert File.exist?(config.history_path), "the first sync creates the ledger"
      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status
      assert_match(/corpus.*last \d{4}-\d{2}-\d{2} \d{2}:\d{2} ok \(\+2 ~0 -0 !0\)/, out)
    end
  end

  # A catalog built without any run history (e.g. restored derived dbs, no
  # ledger): status stays functional and says so instead of inventing history.
  def test_status_without_ledger_reports_no_run_history
    with_rebuild_env do |config|
      with_config(config) { run_cli(%w[rebuild]) }
      File.delete(config.history_path) # simulate a ledger-less derived set

      out, _err, status = with_config(config) { run_cli(["status"]) }
      assert_nil status
      assert_match(/corpus.*docs=2.*no run history/, out)
    end
  end

  # -- health (P5-3 remote, P5-5 local) ------------------------------------

  # Bare `health` over a freshly synced, healthy corpus: source row "ok", golden
  # queries all skipped (the TestAdapter corpus holds none of the golden urns),
  # exit 0.
  def test_health_local_healthy_corpus_exits_zero
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[health]) }
      assert_nil status, "a healthy corpus is exit 0"
      assert_match(/corpus\s+ok/, out)
      assert_match(/golden replay:/, out)
      assert_match(/health: OK/, out)
      assert_match(/health --remote/, out, "bare health hints at the upstream probe")
    end
  end

  # A seeded quarantine spike in the run history is a loud finding: exit 1.
  def test_health_local_seeded_spike_exits_one
    with_indexed_corpus do |config|
      seed_spike_runs(config)
      out, err, status = with_config(config) { run_cli(%w[health]) }
      assert_equal 1, status, "a quarantine spike fails health"
      assert_match(/ANOMALY/, out)
      assert_match(/quarantine spike/i, out)
      assert_match(/loud finding/i, err)
    end
  end

  # P18-7 last-run honesty end-to-end: a FAILED most-recent run is a loud
  # ANOMALY naming the error, exit 1 — the failed-Coptic-sync gap closed.
  def test_health_local_failed_last_run_exits_one_with_the_error
    with_indexed_corpus do |config|
      seed_failed_run(config, notes: "fetch exploded: connection reset")
      out, _err, status = with_config(config) { run_cli(%w[health]) }
      assert_equal 1, status
      assert_match(/ANOMALY last sync run FAILED/, out)
      assert_match(/fetch exploded/, out)
      assert_match(/re-run/, out)
    end
  end

  # No catalog on disk: an informational "no corpus" note, exit 0.
  def test_health_local_no_corpus_notes_and_exits_zero
    with_empty_registry_env do |config|
      out, _err, status = with_config(config) { run_cli(%w[health]) }
      assert_nil status
      assert_match(/no corpus/i, out)
      assert_match(/health: OK/, out)
    end
  end

  # --remote, every upstream alive → the table lands on stdout and exit is 0.
  # TestAdapter's upstream is non-github, so the license check stays unchecked
  # (no HTTP), and with no catalog built drift reads never-synced.
  def test_health_remote_all_alive_exits_zero
    with_sync_env(enabled: true) do |config|
      out, _err, status = with_config(config) do
        with_stubbed_shell(->(*_argv) { "sha_head\tHEAD\n" }) { run_cli(%w[health --remote]) }
      end
      assert_nil status, "all-alive is exit 0"
      assert_match(/corpus\s+alive/, out)
      assert_match(/1 source, 1 alive/, out)
      # An unchecked license verdict carries no signal — the row says nothing
      # rather than "license: unchecked" (owner rule: suppress zero fields),
      # and suppression leaves no trailing whitespace behind.
      refute_match(/unchecked/, out)
      out.each_line { |line| assert_equal line.chomp, line.chomp.rstrip }
    end
  end

  # --remote, a gone upstream → GONE in the table (stdout) and exit 1.
  def test_health_remote_gone_upstream_exits_one
    with_sync_env(enabled: true) do |config|
      dead = ->(*_argv) { raise Nabu::Shell::Error.new("x", status: 128, stderr: "remote: Repository not found.") }
      out, err, status = with_config(config) do
        with_stubbed_shell(dead) { run_cli(%w[health --remote]) }
      end
      assert_equal 1, status
      assert_match(/corpus\s+GONE/, out)
      assert_match(/upstream.*gone/i, err)
    end
  end

  # P15-7: `health --backfill-pins` records a ledger pin from the local git
  # clone (no network, read-only on canonical/) and is idempotent — a second
  # run finds nothing to do.
  def test_health_backfill_pins_from_local_clone_and_idempotent
    Dir.mktmpdir("nabu-cli-backfill") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\n")
      Nabu::Shell.run("git", "-C", corpus, "init", "-q")
      Nabu::Shell.run("git", "-C", corpus, "add", ".")
      Nabu::Shell.run("git", "-C", corpus, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: true\n  sync_policy: manual\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )

      out, _err, status = with_config(config) { run_cli(%w[health --backfill-pins]) }
      assert_nil status
      assert_match(/corpus\s+pinned/, out)
      assert_match(/backfilled-from-local-clone/, out)
      assert_match(/recorded 1 pin/, out)

      again, = with_config(config) { run_cli(%w[health --backfill-pins]) }
      assert_match(/nothing to backfill/, again)
    end
  end

  # P14-12: `status --remote` runs the upstream probe inline (the SAME stubbed
  # ls-remote path as `health --remote`), persists the verdict, then renders the
  # up= column from that fresh cache — the one-command informed-update flow.
  def test_status_remote_probes_inline_persists_and_renders_up_column
    with_sync_env(enabled: true) do |config|
      with_config(config) { run_cli(%w[sync corpus --parse-only]) }

      # Bare status before any probe: the upstream is genuinely unknown.
      before, = with_config(config) { run_cli(%w[status]) }
      assert_match(/corpus.*up=\?\(unprobed\)/, before)

      # --remote probes inline and writes the cache.
      out, _err, status = with_config(config) do
        with_stubbed_shell(->(*_argv) { "sha_head\tHEAD\n" }) { run_cli(%w[status --remote]) }
      end
      assert_nil status
      assert_match(/corpus.*up=\S+\(0d\)/, out, "a freshly probed verdict (age 0d)")

      # The verdict persists: a subsequent bare status reads it from the cache.
      after, = with_config(config) { run_cli(%w[status]) }
      assert_match(/corpus.*up=\S+\(0d\)/, after)
    end
  end

  # -- search (P4-2) -------------------------------------------------------

  # Build the store (catalog + fulltext index) via a real parse-only sync, then
  # search. The unaccented query "μηνιν" must find the accented passage μῆνιν —
  # proving query and index share the diacritic fold.
  def test_search_finds_greek_passage_via_unaccented_query
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search μηνιν]) }
      assert_nil status, "a successful search exits 0"
      assert_match(/urn:nabu:test_adapter:one:1 \[grc\]/, out)
      assert_match(/\[μηνιν\]/, out, "the folded match is highlighted")
      assert_match(/1 hit\b/, out)
    end
  end

  def test_search_zero_hits_says_no_matches_and_succeeds
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search zzzznotfound]) }
      assert_nil status, "zero hits is not a failure"
      assert_match(/no matches/i, out)
    end
  end

  def test_search_bad_license_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search μηνιν --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  def test_search_without_index_hints_to_sync_or_rebuild
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[search anything]) }
      assert_equal 1, status
      assert_match(/no index.*sync.*rebuild/i, err)
    end
  end

  # -- search date/place axis (P15-2) --------------------------------------

  def test_search_from_to_filters_by_date
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search στρατηγος --from -300 --to -30]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:a:1", out)  # 113 BCE
      assert_match("urn:nabu:ddbdp:c:1", out)  # 30 BCE
      refute_match("urn:nabu:ddbdp:b:1", out)  # 591 CE, out of window
    end
  end

  def test_search_century_shorthand_scopes_one_century
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search στρατηγος --century 6]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:b:1", out) # 6th c. CE
      refute_match("urn:nabu:ddbdp:a:1", out)
    end
  end

  def test_search_place_filters_by_provenance
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search στρατηγος --place oxyrhynch%]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:a:1", out)
      refute_match("urn:nabu:ddbdp:b:1", out) # Arsinoites
    end
  end

  def test_search_year_zero_is_rejected
    _out, err, status = run_cli(%w[search foo --from 0])
    assert_equal 1, status
    assert_match(/no year 0/i, err)
  end

  def test_search_from_after_to_is_rejected
    _out, err, status = run_cli(%w[search foo --from -30 --to -300])
    assert_equal 1, status
    assert_match(/--from -30 is after --to -300/, err)
  end

  def test_search_date_does_not_compose_with_lemma
    _out, err, status = run_cli(%w[search --lemma λέγω --from -300])
    assert_equal 1, status
    assert_match(/text search only/i, err)
  end

  # -- search facets (P17-2, document_facets) -------------------------------

  def test_search_type_filters_by_genre_facet_and_names_the_filter
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search στρατηγος --type epitaph]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:a:1", out)
      refute_match("urn:nabu:ddbdp:b:1", out) # votive
      refute_match("urn:nabu:ddbdp:c:1", out) # unfaceted — honest absence
      assert_match(/facets: genre=epitaph/, out, "the active facet filter is named in the footer")
    end
  end

  def test_search_type_matches_the_raw_code_certainty_included
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search στρατηγος --type titsep?]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:a:1", out)
      refute_match("urn:nabu:ddbdp:b:1", out)
    end
  end

  def test_search_province_composes_with_century
    with_dated_corpus do |config|
      out, _err, status = with_config(config) do
        run_cli(["search", "στρατηγος", "--province", "pannonia%", "--century", "-2"])
      end
      assert_nil status
      assert_match("urn:nabu:ddbdp:a:1", out) # 113 BCE, Pannonia inferior
      refute_match("urn:nabu:ddbdp:b:1", out)

      out2, _err2, = with_config(config) do
        run_cli(["search", "στρατηγος", "--province", "pannonia%", "--century", "6"])
      end
      assert_match(/no matches/i, out2, "right province, wrong century")
    end
  end

  def test_search_fuzzy_composes_with_facet_filters
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --fuzzy ρατηγ --type votive%]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:b:1", out)
      refute_match("urn:nabu:ddbdp:a:1", out)
      assert_match(/facets: genre=votive%/, out)
    end
  end

  def test_search_facets_do_not_compose_with_lemma
    _out, err, status = run_cli(%w[search --lemma λέγω --type epitaph])
    assert_equal 1, status
    assert_match(/text search only/i, err)
  end

  def test_search_facets_against_a_pre_facet_catalog_hint_to_rebuild
    with_dated_corpus do |config|
      catalog = Nabu::Store.connect(config.catalog_path)
      catalog.drop_table?(:document_facets)
      catalog.disconnect
      _out, err, status = with_config(config) { run_cli(%w[search στρατηγος --type epitaph]) }
      assert_equal 1, status
      assert_match(/no facet table.*rebuild/i, err)
    end
  end

  # -- search --fuzzy (P16-4) ------------------------------------------------

  # The papyrologist's fragment, brackets and all: an infix hit on the
  # documentary shelf, folded snippet with the fragment bracketed, and the
  # honest scope footer.
  def test_search_fuzzy_matches_bracketed_fragment_and_names_its_scope
    with_fuzzy_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["search", "--fuzzy", "]μηνιν αει["]) }
      assert_nil status, "a successful fuzzy search exits 0"
      assert_match(/urn:nabu:pap:a:1 \[grc\]/, out)
      assert_match(/\[μηνιν αει\]/, out, "the fragment is bracketed in the folded snippet")
      assert_match(/1 hit .*fuzzy substring/, out)
      assert_match(/fuzzy index covers: pap/, out, "every fuzzy render names the indexed scope")
      refute_match(/urn:nabu:lit/, out, "the literary shelf is not trigram-indexed")
    end
  end

  def test_search_fuzzy_mid_word_fragment_hits
    with_fuzzy_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --fuzzy ηληιαδ]) }
      assert_nil status
      assert_match(/urn:nabu:pap:a:1/, out, "mid-word matching is the point: ηληιαδ inside Πηληϊάδεω")
    end
  end

  # --long lifts the snippet window (house rule): the full folded passage.
  def test_search_fuzzy_long_prints_the_full_folded_passage
    with_fuzzy_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --fuzzy ηληιαδ --long]) }
      assert_nil status
      assert_match(/μηνιν αειδε θεα π\[ηληιαδ\]εω αχιληοσ/, out, "--long shows the whole folded line")
    end
  end

  # A fragment living only on a non-indexed (literary) shelf: honest empty
  # result PLUS the one-line hint naming what is indexed.
  def test_search_fuzzy_literary_only_fragment_misses_with_scope_hint
    with_fuzzy_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --fuzzy ολομπι]) }
      assert_nil status
      assert_match(/no matches/i, out)
      assert_match(/fuzzy index covers: pap/, out, "the miss explains itself — the scope line names the shelves")
    end
  end

  def test_search_fuzzy_short_fragment_gets_the_trigram_floor_message
    with_fuzzy_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --fuzzy αε]) }
      assert_equal 1, status
      assert_match(/at least 3 characters/, err)
      assert_match(/trigram floor/, err)
    end
  end

  def test_search_fuzzy_composes_with_date_filters
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --fuzzy ρατηγ --century 6]) }
      assert_nil status
      assert_match("urn:nabu:ddbdp:b:1", out) # 6th c. CE
      refute_match("urn:nabu:ddbdp:a:1", out) # 113 BCE, out of window
    end
  end

  def test_search_fuzzy_against_a_pre_trigram_index_hints_to_reindex
    with_fuzzy_corpus do |config|
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      fulltext.drop_table?(Nabu::Store::Indexer::TRIGRAM_TABLE)
      fulltext.drop_table?(Nabu::Store::Indexer::TRIGRAM_SCOPE_TABLE)
      fulltext.disconnect
      _out, err, status = with_config(config) { run_cli(%w[search --fuzzy μηνιν]) }
      assert_equal 1, status
      assert_match(/no fuzzy index.*sync.*rebuild/i, err)
    end
  end

  def test_search_fuzzy_does_not_compose_with_lemma
    _out, err, status = run_cli(%w[search --fuzzy --lemma λέγω μηνιν])
    assert_equal 1, status
    assert_match(/--fuzzy.*does not combine/i, err)
  end

  def test_search_fuzzy_needs_a_fragment
    _out, err, status = run_cli(%w[search --fuzzy])
    assert_equal 1, status
    assert_match(/--fuzzy needs a fragment/, err)
  end

  def test_help_search_documents_fuzzy_with_the_papyrological_example
    out, _err, _status = run_cli(%w[help search])
    assert_match(/--fuzzy/, out)
    assert_match(/\]μηνιν αει\[/, out, "must show the damaged-scrap example, brackets and all")
    assert_match(/papyri-ddbdp, oracc/, out, "must name the documentary scope")
    assert_match(/parallels/, out, "must give the honest literary answer")
  end

  def test_show_prints_the_facets_line_compactly
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:ddbdp:a]) }
      assert_nil status
      assert_match(/facets: genre=epitaph \(titsep\?\) · province=Pannonia inferior \(PaI\)/, out)

      # An unfaceted document prints NO facets line (zero-signal silence).
      out_c, _err_c, = with_config(config) { run_cli(%w[show urn:nabu:ddbdp:c]) }
      refute_match(/facets:/, out_c)
    end
  end

  def test_show_prints_the_date_place_axis_line
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:ddbdp:a]) }
      assert_nil status
      assert_match(/date: 113 BCE \(low\) · Oxyrhynchus/, out)
    end
  end

  def test_vocab_by_century_buckets_the_dated_corpus
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[vocab --by-century]) }
      assert_nil status
      assert_match(/2nd c\. BCE\s+1 document/, out)
      assert_match(/6th c\. CE\s+1 document/, out)
      assert_match(/3 dated documents \(bucketed by earliest year; 2 span multiple centuries\)/, out)
    end
  end

  def test_vocab_by_century_plots_a_word
    with_dated_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[vocab --by-century κακος]) }
      assert_nil status
      assert_match(/diachrony of "κακος"/, out)
      assert_match(/6th c\. CE\s+1 document/, out) # only urn:b carries κακος
    end
  end

  # -- search --lemma (P7-5) -------------------------------------------------

  # Real UD Ancient Greek PROIEL fixture synced through the real pipeline:
  # --lemma λέγω must surface the suppletive aorist εἶπας (sentence 64498) —
  # an attestation no λεγ- text query can reach.
  def test_search_lemma_finds_inflected_attestations
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma λέγω --lang grc]) }
      assert_nil status, "a successful lemma search exits 0"
      assert_match(/urn:nabu:ud:greek-proiel:grc_proiel-ud-test-head50:64498 \[grc\]/, out)
      assert_match(/λέγω → εἶπας/, out, "the hit names the matched surface form")
      assert_match(/λέγειν, εἰπεῖν/, out, "multiple forms in one passage aggregate on one hit")
      assert_match(/exact lemma match/, out, "the footer labels the match kind")
    end
  end

  # Fold both sides at the CLI seam: the unaccented spelling still hits.
  def test_search_lemma_unaccented_query_matches
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma λεγω]) }
      assert_nil status
      assert_match(/:64498 \[grc\]/, out)
    end
  end

  def test_search_lemma_zero_hits_says_no_matches
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma τίθημι]) }
      assert_nil status, "zero hits is not a failure"
      assert_match(/no matches/i, out)
    end
  end

  def test_search_lemma_with_a_text_query_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search μηνιν --lemma λέγω]) }
      assert_equal 1, status
      assert_match(/--lemma replaces the text query/, err)
    end
  end

  # A fulltext file built before P7-5 has no lemma table: honest hint, exit 1.
  def test_search_lemma_against_a_pre_lemma_index_hints_to_reindex
    with_treebank_corpus do |config|
      ft = Nabu::Store.connect_fulltext(config.fulltext_path)
      ft.drop_table(Nabu::Store::Indexer::LEMMA_TABLE)
      ft.disconnect
      _out, err, status = with_config(config) { run_cli(%w[search --lemma λέγω]) }
      assert_equal 1, status
      assert_match(/no lemma index.*sync.*rebuild/i, err)
    end
  end

  # -- search --near (P14-8 proximity) -------------------------------------

  # Real UD grc sentence 64498: … ὁ κῆρυξ(7) καὶ(8) εἶπας(9) … — κῆρυξ and
  # εἶπας sit a word apart. --window 1 admits them, both folded terms
  # bracketed; --window 0 (adjacency) does not.
  def test_search_near_within_window_hits_with_both_terms_highlighted
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search κῆρυξ --near εἶπας --window 1]) }
      assert_nil status, "a successful proximity search exits 0"
      assert_match(/:64498 \[grc\]/, out)
      assert_match(/\[κηρυξ\]/, out, "the anchor term is highlighted")
      assert_match(/\[ειπασ\]/, out, "the near term is highlighted too")
    end
  end

  def test_search_near_window_zero_requires_adjacency
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search κῆρυξ --near εἶπας --window 0]) }
      assert_nil status, "zero hits is not a failure"
      assert_match(/no matches/i, out, "window 0 needs adjacency — κῆρυξ and εἶπας are a word apart")
    end
  end

  # The lemma anchor expands to attested surface forms before the NEAR: the
  # suppletive aorist εἶπας is a form of λέγω, so it sits near the rare κῆρυξ.
  def test_search_near_expands_a_lemma_anchor
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[search --lemma λέγω --near κῆρυξ --window 1]) }
      assert_nil status
      assert_match(/:64498 \[grc\]/, out, "εἶπας (a form of λέγω) is one word from κῆρυξ")
    end
  end

  def test_search_near_with_morph_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --lemma λέγω --near κύριος --morph case=nom]) }
      assert_equal 1, status
      assert_match(/--morph does not compose with --near/, err)
    end
  end

  def test_search_near_without_an_anchor_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[search --near θεα]) }
      assert_equal 1, status
      assert_match(/--near needs an anchor/, err)
    end
  end

  # -- concord (P8-3) ------------------------------------------------------

  def test_concord_prints_kwic_lines_with_the_keyword_located
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord μηνιν --width 10]) }
      assert_nil status, "a successful concord exits 0"
      assert_match(/μῆνιν/, out, "the pristine accented keyword appears in the KWIC line")
      assert_match(/urn:nabu:test_adapter:one:1 \[grc\]/, out, "the urn + language tag per row")
      assert_match(/1 line\b/, out, "the footer counts KWIC lines")
    end
  end

  # Alignment: the keyword column is identical across rows of varying keyword
  # length. Two passages, different words matched by one prefix query; the
  # keyword's left edge sits at the same character offset on both lines.
  def test_concord_aligns_the_keyword_column
    with_kwic_corpus do |config|
      out, _err, _status = with_config(config) { run_cli(%w[concord μηνι* --width 8]) }
      lines = out.split("\n").select { |line| line.include?("test_adapter:kwic:") }
      assert_equal 2, lines.size, "two hits with different-length keywords"
      # Each line begins with an 8-char left context; the keyword's left edge
      # (the μ of μῆνιν / μηνιτισι) therefore sits at column 8 on both rows.
      assert lines.all? { |line| line.chars[8] == "μ" }, "keyword column aligned at width"
    end
  end

  def test_concord_zero_hits_says_no_matches
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord zzzznotfound]) }
      assert_nil status
      assert_match(/no matches/i, out)
    end
  end

  def test_concord_lemma_mode_finds_inflected_forms_in_context
    with_treebank_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord --lemma λέγω --lang grc]) }
      assert_nil status
      assert_match(/:64498 \[grc\]/, out)
      assert_match(/εἶπας/, out, "the located surface form is the inflected attestation")
    end
  end

  def test_concord_bad_license_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[concord μηνιν --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  def test_concord_without_index_hints_to_sync_or_rebuild
    with_empty_registry_env do |config|
      _out, err, status = with_config(config) { run_cli(%w[concord anything]) }
      assert_equal 1, status
      assert_match(/no index.*sync.*rebuild/i, err)
    end
  end

  def test_concord_lemma_with_a_text_query_errors
    with_treebank_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[concord μηνιν --lemma λέγω]) }
      assert_equal 1, status
      assert_match(/--lemma replaces the text query/, err)
    end
  end

  def test_help_concord_documents_kwic_lemma_and_examples
    out, _err, _status = run_cli(%w[help concord])
    assert_match(/KWIC|keyword-in-context/i, out)
    assert_match(/--width/, out)
    assert_match(/corpus order/i, out, "must say rows are corpus-ordered, not ranked")
    assert_match(/nabu concord μῆνιν/, out, "a worked grc example")
    assert_match(/--lemma λέγω/, out, "a worked lemma example")
    assert_match(/Examples:/, out)
  end

  # -- parallels (P15-1 intertext) -----------------------------------------

  def test_parallels_finds_the_quotation_with_evidence
    with_parallels_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[parallels urn:h:od:1.1]) }
      assert_nil status, "a successful parallels exits 0"
      assert_match(/parallels of urn:h:od:1\.1/, out)
      assert_match(/urn:q:full:1 \[grc\]/, out, "the verbatim quoter is a hit")
      assert_match(/score \d/, out)
      assert_match(/ανδρα μοι εννεπε μουσα/, out, "the shared phrase is the folded evidence")
      assert_match(/parallels? from \d+ grams/, out)
    end
  end

  # The owner house rule (2026-07-12): --long expands any truncated list. The
  # full quoter shares FOUR separated phrase spans; compact shows three with a
  # "… and N more (--long)" tail, --long shows all four and no tail.
  def test_parallels_long_expands_the_truncated_evidence_spans
    with_parallels_corpus do |config|
      compact, = with_config(config) { run_cli(%w[parallels urn:h:od:1.1]) }
      long, = with_config(config) { run_cli(%w[parallels urn:h:od:1.1 --long]) }

      assert_match(/… and 1 more \(--long\)/, compact, "compact elides beyond three spans")
      refute_match(/π4a π4b π4c π4d/, compact, "the fourth span is hidden in compact")
      refute_match(/and 1 more/, long, "--long drops the elision tail")
      assert_match(/π4a π4b π4c π4d/, long, "--long shows the fourth span in full")
    end
  end

  def test_parallels_unknown_urn_exits_one_with_a_hint
    with_parallels_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[parallels urn:no:such:thing]) }
      assert_equal 1, status
      assert_match(/no live passage/i, err)
    end
  end

  def test_parallels_bad_license_exits_one
    with_parallels_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[parallels urn:h:od:1.1 --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  def test_help_parallels_documents_the_engine_and_long
    out, _err, _status = run_cli(%w[help parallels])
    assert_match(/quote|echo|intertext/i, out)
    assert_match(/--long/, out, "the truncation-expand flag is documented")
    assert_match(/Examples:/, out)
  end

  # -- formulas (P15-5 formula miner) --------------------------------------

  def test_formulas_mines_the_refrain_with_loci
    with_formulas_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[formulas aspr]) }
      assert_nil status, "a successful formulas exits 0"
      assert_match(%r{formulas in aspr — 4 passages / 24 tokens}, out)
      assert_match(/4×  saga hwaet ic hatte/, out, "the refrain is the top formula, count first")
      assert_match(/e\.g\. urn:nabu:aspr:riddle:0/, out, "compact shows a few example loci")
      assert_match(/rank = count × 4-gram length/, out, "the footer states the ranking")
    end
  end

  def test_formulas_long_lists_every_locus
    with_formulas_corpus do |config|
      compact, = with_config(config) { run_cli(%w[formulas aspr]) }
      long, = with_config(config) { run_cli(%w[formulas aspr --long]) }
      refute_match(/urn:nabu:aspr:riddle:3/, compact, "compact keeps only a few examples")
      assert_match(/urn:nabu:aspr:riddle:3/, long, "--long lists every locus")
      refute_match(/e\.g\./, long, "--long is the full list, not examples")
    end
  end

  def test_formulas_gram_size_and_min_count_compose
    with_formulas_corpus do |config|
      out, = with_config(config) { run_cli(%w[formulas aspr --gram-size 3 --min-count 4]) }
      assert_match(/4×  hwaet ic hatte/, out, "the 3-gram refrain at the raised floor")
    end
  end

  def test_formulas_unknown_scope_reports_empty
    with_formulas_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[formulas urn:nabu:nope:x]) }
      assert_nil status
      assert_match(/no passages in scope/, out)
    end
  end

  def test_formulas_bad_gram_size_exits_one
    with_formulas_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[formulas aspr --gram-size 1]) }
      assert_equal 1, status
      assert_match(/gram size must be/i, err)
    end
  end

  def test_help_formulas_documents_scope_lang_and_ranking
    out, _err, _status = run_cli(%w[help formulas])
    assert_match(/formula/i, out)
    assert_match(/--lang/, out, "the language filter is documented")
    assert_match(/--long/, out)
    assert_match(/Examples:/, out)
  end

  # -- parallels --batch + links (P16-1 links journal) -----------------------

  def test_parallels_batch_persists_edges_and_names_its_thresholds
    with_parallels_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      assert_nil status, "a successful batch exits 0"
      assert_match(/batch parallels over urn:h:od: 1 edge written · run 1/, out)
      assert_match(%r{1 anchor · kept top 5/anchor at score ≥ 0.05}, out,
                   "the summary names every pruning threshold — no silent caps")
      journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
      edge = journal[:links].first
      assert_equal %w[urn:h:od:1.1 urn:q:full:1 parallel],
                   [edge[:from_urn], edge[:to_urn], edge[:kind]]
      journal.disconnect
    end
  end

  def test_parallels_batch_rerun_reports_the_superseded_run
    with_parallels_corpus do |config|
      with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      out, _err, status = with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      assert_nil status
      assert_match(/superseded 1 prior run \(1 edge\)/, out)
      journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
      assert_equal [1, 1], [journal[:links].count, journal[:link_runs].count], "rerun is idempotent"
      journal.disconnect
    end
  end

  def test_parallels_batch_db_override_writes_the_journal_elsewhere
    with_parallels_corpus do |config|
      scratch = File.join(config.db_dir, "scratch-links.sqlite3")
      _out, _err, status = with_config(config) { run_cli(["parallels", "--batch", "urn:h:od", "--db", scratch]) }
      assert_nil status
      assert_path_exists scratch
      refute_path_exists config.links_path, "the default journal path is untouched"
    end
  end

  def test_parallels_batch_flags_require_batch
    with_parallels_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[parallels urn:h:od:1.1 --min-score 0.1]) }
      assert_equal 1, status
      assert_match(/--min-score only applies with --batch/, err)
      assert_match(/never persisted/, err, "the no-caching stance is stated, not just enforced")
    end
  end

  def test_links_reads_both_directions_with_resolution_and_provenance
    with_parallels_corpus do |config|
      with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      out, _err, status = with_config(config) { run_cli(%w[links urn:q:full:1]) }
      assert_nil status
      assert_match(/links of urn:q:full:1 — urn:q:full/, out)
      assert_match(/parallel \(1\):/, out, "edges group by kind")
      assert_match(/← urn:h:od:1\.1 — urn:h:od \[grc\]  score \d/, out,
                   "the incoming edge resolves its counterpart to title\\/language")
      assert_match(/1 edge · run 1: parallels over urn:h:od \(min_score 0.05, per_anchor 5\)/, out,
                   "the provenance footer cites the producer run and its params")

      anchor_side, = with_config(config) { run_cli(%w[links urn:h:od:1.1]) }
      assert_match(/→ urn:q:full:1/, anchor_side, "the same edge reads outgoing from its anchor")
    end
  end

  def test_links_long_lifts_the_per_kind_truncation
    with_parallels_corpus do |config|
      journal = Nabu::Store::LinksJournal.open!(config.links_path)
      run_id = Nabu::Store::LinksJournal.record_run!(
        journal, producer: "parallels", scope: "urn:h", params: {}, code_version: "t/1"
      )
      12.times do |i|
        Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:h:od:1.1", to_urn: "urn:z:#{i}",
                                                       kind: "parallel", score: 1.0, run_id: run_id)
      end
      journal.disconnect
      compact, _err, status = with_config(config) { run_cli(%w[links urn:h:od:1.1]) }
      assert_nil status
      assert_match(/… and 2 more \(--long lists all\)/, compact)
      assert_match(/\(not in catalog\)/, compact, "unresolvable counterparts are flagged, not hidden")
      long, = with_config(config) { run_cli(%w[links urn:h:od:1.1 --long]) }
      refute_match(/… and \d+ more/, long)
      assert_match(/urn:z:11/, long, "--long lists every edge")
    end
  end

  def test_links_unknown_urn_exits_one
    with_parallels_corpus do |config|
      with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      _out, err, status = with_config(config) { run_cli(%w[links urn:no:such]) }
      assert_equal 1, status
      assert_match(/links: unknown urn urn:no:such/, err)
    end
  end

  def test_links_without_a_journal_is_a_state_not_an_error
    with_parallels_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[links urn:h:od:1.1]) }
      assert_nil status
      assert_match(/no links journal yet/, out)
      assert_match(/parallels --batch/, out, "the empty state teaches the producer")
    end
  end

  def test_help_links_documents_directions_provenance_and_long
    out, _err, _status = run_cli(%w[help links])
    assert_match(/BOTH directions/, out)
    assert_match(/provenance/, out)
    assert_match(/--long/, out)
    assert_match(/rebuild/, out, "the rebuild-survival promise is documented")
    assert_match(/Examples:/, out)
  end

  def test_show_footer_lists_linked_counts_only_when_edges_exist
    with_parallels_corpus do |config|
      before, = with_config(config) { run_cli(%w[show urn:h:od:1.1]) }
      refute_match(/linked:/, before, "no journal → zero-signal silence")

      with_config(config) { run_cli(%w[parallels --batch urn:h:od]) }
      after, _err, status = with_config(config) { run_cli(%w[show urn:h:od:1.1]) }
      assert_nil status
      assert_match(/^  linked: 1 parallel$/, after)

      unlinked, = with_config(config) { run_cli(%w[show urn:h:od]) }
      refute_match(/linked:/, unlinked, "a urn without edges stays silent even with a journal present")
    end
  end

  # -- formulas --batch + cognates --batch (P16-2 producers) ------------------

  def test_formulas_batch_persists_the_star_and_names_its_knobs
    with_formulas_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[formulas --batch aspr]) }
      assert_nil status, "a successful batch exits 0"
      assert_match(/batch formulas over aspr: 3 edges written · run 1/, out)
      assert_match(/1 formula persisted as stars \(top 200 by rank of 1 recurring ≥3× 4-grams\)/, out,
                   "the summary names every pruning knob — no silent caps")
      journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
      edges = journal[:links].order(:to_urn).all
      assert_equal %w[urn:nabu:aspr:riddle:0] * 3, edges.map { |e| e[:from_urn] },
                   "the star hub is the first locus in urn order"
      assert_equal ["saga hwaet ic hatte"], edges.map { |e| e[:detail] }.uniq
      assert_equal %w[formula], edges.map { |e| e[:kind] }.uniq
      journal.disconnect
    end
  end

  def test_formulas_batch_rerun_reports_the_superseded_run
    with_formulas_corpus do |config|
      with_config(config) { run_cli(%w[formulas --batch aspr]) }
      out, _err, status = with_config(config) { run_cli(%w[formulas --batch aspr]) }
      assert_nil status
      assert_match(/superseded 1 prior run \(3 edges\)/, out)
      journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
      assert_equal [3, 1], [journal[:links].count, journal[:link_runs].count], "rerun is idempotent"
      journal.disconnect
    end
  end

  def test_formulas_batch_db_override_writes_the_journal_elsewhere
    with_formulas_corpus do |config|
      scratch = File.join(config.db_dir, "scratch-links.sqlite3")
      _out, _err, status = with_config(config) { run_cli(["formulas", "--batch", "aspr", "--db", scratch]) }
      assert_nil status
      assert_path_exists scratch
      refute_path_exists config.links_path, "the default journal path is untouched"
    end
  end

  def test_formulas_batch_flags_require_batch
    with_formulas_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[formulas aspr --max-formulas 10]) }
      assert_equal 1, status
      assert_match(/--max-formulas only applies with --batch/, err)
      assert_match(/never persisted/, err, "the no-caching stance is stated — consistent with parallels")
    end
  end

  def test_cognates_batch_persists_the_meets_and_links_reads_them_back
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[cognates --batch nt]) }
      assert_nil status, "a successful batch exits 0"
      assert_match(/batch cognates over nt: 3 edges written · run 1/, out)
      assert_match(/3 verse-root groups/, out)

      links, _err2, links_status = with_config(config) { run_cli(%w[links urn:nabu:test:grc-nt:1]) }
      assert_nil links_status
      assert_match(/cognate \(1\):/, links, "edges group under their kind")
      assert_match(/urn:nabu:test:marianus:1 — Codex Marianus \[chu\]  MARK 1\.1 · \*bʰeh₂g- \[ine-pro\]/,
                   links, "a cognate edge shows its meet: ref · root [shelf]")
      refute_match(/score/, links, "a cognate's score merely counts the roots its detail lists")
      assert_match(/run 1: cognates over nt/, links, "the provenance footer cites the producer")

      # P17-3: the loan verdict rides the persisted meet — the got×chu pair
      # at *hlaibaz names the flagged witness language per edge.
      loan_links, _err3, = with_config(config) { run_cli(%w[links urn:nabu:test:gothic:1]) }
      assert_match(/JOHN 13\.18 · \*hlaibaz \[gem-pro\] \(loan: chu\)/, loan_links,
                   "the batch detail states the loan, not just the shelf")
    end
  end

  def test_cognates_batch_langs_ride_the_run_params
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[cognates --batch nt --langs grc,chu]) }
      assert_nil status
      assert_match(/batch cognates over nt \[grc×chu\]: 1 edge written/, out)
      journal = Nabu::Store::LinksJournal.open_readonly(config.links_path)
      assert_equal({ "kind" => "cognate", "langs" => %w[grc chu] },
                   JSON.parse(journal[:link_runs].first[:params_json]))
      journal.disconnect

      links, = with_config(config) { run_cli(%w[links urn:nabu:test:grc-nt:1]) }
      assert_match(/cognates over nt \(langs grc,chu\)/, links,
                   "array params render comma-joined in the provenance footer")
    end
  end

  def test_cognates_batch_takes_a_work_id_and_db_requires_batch
    with_cognates_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["cognates", "--batch", "MARK 1.1"]) }
      assert_equal 1, status
      assert_match(/registered work id/, err)

      _out2, err2, status2 = with_config(config) { run_cli(["cognates", "nt", "--db", "/tmp/x.sqlite3"]) }
      assert_equal 1, status2
      assert_match(/--db only applies with --batch/, err2)
    end
  end

  def test_links_renders_a_formula_edge_with_its_gram_and_count
    with_formulas_corpus do |config|
      with_config(config) { run_cli(%w[formulas --batch aspr]) }
      out, _err, status = with_config(config) { run_cli(%w[links urn:nabu:aspr:riddle:2]) }
      assert_nil status
      assert_match(/formula \(1\):/, out)
      assert_match(/← urn:nabu:aspr:riddle:0 — Riddles \[ang\]  “saga hwaet ic hatte”  ×4/, out,
                   "a locus shows WHICH refrain ties it to the hub and how strongly — not a bare score")
      hub, = with_config(config) { run_cli(%w[links urn:nabu:aspr:riddle:0]) }
      assert_match(/formula \(3\):/, hub, "the hub fans out every other locus")
    end
  end

  def test_links_groups_mixed_kinds_and_show_footer_counts_them_with_zero_suppression
    with_formulas_corpus do |config|
      with_config(config) { run_cli(%w[formulas --batch aspr]) }
      journal = Nabu::Store::LinksJournal.open!(config.links_path)
      run_id = Nabu::Store::LinksJournal.record_run!(
        journal, producer: "parallels", scope: "aspr", params: {}, code_version: "t/1"
      )
      Nabu::Store::LinksJournal.write_edge!(journal, from_urn: "urn:nabu:aspr:riddle:1",
                                                     to_urn: "urn:z:1", kind: "parallel",
                                                     score: 0.4, run_id: run_id)
      journal.disconnect

      links, = with_config(config) { run_cli(%w[links urn:nabu:aspr:riddle:1]) }
      assert_match(/formula \(1\):.*parallel \(1\):/m, links, "kinds render as separate groups")
      assert_match(/score 0\.40/, links, "the parallel edge keeps its rarity score")

      mixed, = with_config(config) { run_cli(%w[show urn:nabu:aspr:riddle:1]) }
      assert_match(/^  linked: 1 formula, 1 parallel$/, mixed,
                   "the footer counts each kind present and suppresses absent kinds")
      single, = with_config(config) { run_cli(%w[show urn:nabu:aspr:riddle:2]) }
      assert_match(/^  linked: 1 formula$/, single)
    end
  end

  def test_help_formulas_and_cognates_document_batch
    formulas_help, = run_cli(%w[help formulas])
    assert_match(/--batch/, formulas_help)
    assert_match(/STAR/, formulas_help, "the edge-shape verdict is documented where the flag lives")
    cognates_help, = run_cli(%w[help cognates])
    assert_match(/--batch/, cognates_help)
    assert_match(/shelf rides every edge/, cognates_help, "the meet-provenance stance is documented")
  end

  # -- show (P4-3) ---------------------------------------------------------

  def test_show_passage_prints_text_document_and_provenance
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1]) }
      assert_nil status, "a resolved urn exits 0"
      assert_match(/urn:nabu:test_adapter:one:1 \[grc\]/, out)
      assert_match(/μῆνιν/, out, "the pristine passage text is shown")
      assert_match(/document: urn:nabu:test_adapter:one/, out)
      assert_match(/provenance:/, out)
      assert_match(/loaded/, out, "the loader's provenance event is listed")
    end
  end

  def test_show_document_lists_passages_as_suffixes
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one]) }
      assert_nil status
      assert_match(/passages \(2\):/, out)
      assert_match(/^ +:1  /, out, "passage lines carry only the suffix relative to the document urn")
      assert_match(/^ +:2  /, out)
      refute_match(/^ +urn:nabu:test_adapter:one:1\b/, out,
                   "the document urn is printed once in the header, not per line")
    end
  end

  def test_show_document_full_urn_flag_restores_absolute_urns
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one --full-urn]) }
      assert_nil status
      assert_match(/^ +urn:nabu:test_adapter:one:1\b/, out)
      assert_match(/^ +urn:nabu:test_adapter:one:2\b/, out)
    end
  end

  def test_show_unknown_urn_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:nope]) }
      assert_equal 1, status
      assert_match(/urn not found/i, err)
    end
  end

  # -- show --random (P11-9) -------------------------------------------------

  def test_show_random_prints_a_passage_in_the_standard_layout
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show --random]) }
      assert_nil status, "a random draw over a non-empty corpus exits 0"
      assert_match(/urn:nabu:test_adapter:\w+:\d+ \[grc\]/, out, "a passage urn + language header")
      assert_match(/document: urn:nabu:test_adapter:/, out, "the standard show layout, document line")
      assert_match(/provenance:/, out, "the full provenance trail, as `show <urn>` renders it")
    end
  end

  def test_show_random_count_bounds_the_number_of_passages
    with_indexed_corpus do |config|
      # The fixture corpus holds three live passages; --count 3 shows all three.
      out, _err, status = with_config(config) { run_cli(%w[show --random --count 3]) }
      assert_nil status
      headers = out.scan(/^urn:nabu:test_adapter:/).length
      assert_equal 3, headers, "three passages, three headers"
    end
  end

  def test_show_random_scopes_to_a_source
    with_indexed_corpus do |config|
      # The fixture source's slug is "corpus" (the sources.yml key); its adapter
      # mints urn:nabu:test_adapter:… passage urns.
      out, _err, status = with_config(config) { run_cli(%w[show --random --source corpus --count 3]) }
      assert_nil status
      headers = out.scan(/^urn:\S+/)
      refute_empty headers
      assert(headers.all? { |urn| urn.start_with?("urn:nabu:test_adapter") },
             "every drawn passage belongs to the scoped source")
    end
  end

  def test_show_random_unknown_source_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random --source nope]) }
      assert_equal 1, status
      assert_match(/unknown source "nope"/, err)
    end
  end

  def test_show_random_rejects_a_urn
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show --random urn:nabu:test_adapter:one:1]) }
      assert_equal 1, status
      assert_match(/--random takes no urn/, err)
    end
  end

  def test_show_source_without_random_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1 --source test_adapter]) }
      assert_equal 1, status
      assert_match(/--source requires --random/, err)
    end
  end

  # -- show ranges (P7-6) ----------------------------------------------------

  def test_show_range_lists_the_slice_as_suffixes_with_an_honest_count
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1-1]) }
      assert_nil status, "a resolved range exits 0"
      assert_match(/urn:nabu:test_adapter:one\b/, out, "the document header names the document urn")
      assert_match(/1 of 2 passages/, out, "the honest [N of M] note")
      assert_match(/^ +:1  /, out, "slice lines carry only the :suffix")
      refute_match(/^ +:2  /, out, "the slice excludes passages outside the range")
    end
  end

  def test_show_range_full_urn_restores_absolute_urns
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1-2 --full-urn]) }
      assert_nil status
      assert_match(/^ +urn:nabu:test_adapter:one:1\b/, out)
      assert_match(/^ +urn:nabu:test_adapter:one:2\b/, out)
    end
  end

  def test_show_range_endpoint_not_found_exits_one_naming_the_endpoint
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:1-99]) }
      assert_equal 1, status
      assert_match(/range end not found/i, err)
      assert_match(/urn:nabu:test_adapter:one:99/, err)
    end
  end

  def test_show_reversed_range_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:test_adapter:one:2-1]) }
      assert_equal 1, status
      assert_match(/reversed/i, err)
    end
  end

  def test_show_parallel_composes_with_a_range
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1-2", "--parallel"]) }
      assert_nil status
      # eng :1 owns grc :1 and :2 as ONE block; :3 is outside the slice.
      assert_match(/0 paired, 1 block covering 2 lines, 0 grc only, 0 eng only/, out)
      assert_match(/grc {2}μῆνιν/, out)
      assert_match(/grc {2}ἄειδε/, out, "the whole span shows, not just the anchor line")
      assert_match(/eng \[:1 — covers :1–:2\]/, out, "the block is labeled by its coverage")
      assert_match(/Wrath/, out)
      refute_match(/θεά/, out, ":3 is outside the slice")
    end
  end

  # -- show --parallel (P7-4, span-grouped P8-1b) ----------------------------

  # OSHB Gen 1:1 / TOROT zogr exactly as the parsers store them (P27-0
  # display pins, exercised end-to-end through the CLI; see display_test.rb).
  HBO_GEN_1_1 = "בְּרֵאשִׁ֖ית בָּרָ֣א אֱלֹהִ֑ים אֵ֥ת הַשָּׁמַ֖יִם וְאֵ֥ת הָאָֽרֶץ׃"
  HBO_GEN_1_1_NO_CANT = "בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם וְאֵת הָאָֽרֶץ׃"
  HBO_GEN_1_1_CONSONANTAL = "בראשית ברא אלהים את השמים ואת הארץ׃"
  CHU_ZOGR = "тъ васъ крьститъ дх҃омь ст҃ъꙇмь ꙇ огн҄емь·"
  CHU_ZOGR_NO_TITLA = "тъ васъ крьститъ дхомь стъꙇмь ꙇ огн҄емь·"
  RLI = "⁧"
  PDI = "⁩"

  GRC_URN = "urn:cts:greekLit:tg1.w1.perseus-grc2"
  ENG_URN = "urn:cts:greekLit:tg1.w1.perseus-eng2"

  # A verse-for-verse translation renders byte-identically to pre-P8-1b: every
  # anchor is a 1:1 pair, no blocks clause, the compact two-line pair form.
  def test_show_parallel_verse_output_is_byte_identical_to_the_pair_form
    with_verse_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel"]) }
      assert_nil status
      expected = <<~OUT
        #{GRC_URN} — Iliad [grc]
          parallel: #{ENG_URN} — Iliad [eng]
          aligned by citation: 3 paired, 0 grc only, 0 eng only
          :1
            grc  μῆνιν
            eng  Wrath
          :2
            grc  ἄειδε
            eng  sing
          :3
            grc  θεά
            eng  goddess
      OUT
      assert_equal expected, out
    end
  end

  # A card-cited coarse translation: the whole span of original lines, then the
  # translation block ONCE with its coverage label — no wall of dashes.
  def test_show_parallel_full_document_coarse_render
    with_card_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel"]) }
      assert_nil status
      assert_match(/aligned by citation: 0 paired, 2 blocks covering 8 lines, 0 grc only, 0 eng only/, out)
      assert_match(/eng \[:1\.1 — covers :1\.1–:1\.4\]\n {4}Block one/, out)
      assert_match(/eng \[:1\.5 — covers :1\.5–:1\.8\]\n {4}Block two/, out)
      assert_match(/^ +:1\.4\n {4}grc {2}grc4$/, out, "each owned original line is shown once, suffix-labeled")
      refute_match(/eng {2}—/, out, "no per-line dashes under a coarse block")
    end
  end

  def test_show_parallel_mid_card_range_clips_with_a_note
    with_card_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1.2-1.3", "--parallel"]) }
      assert_nil status
      assert_match(/0 paired, 1 block covering 2 lines/, out)
      assert_match(/eng \[:1\.1 — covers :1\.1–:1\.4; range shows :1\.2–:1\.3\]/, out)
      assert_match(/grc {2}grc2/, out)
      refute_match(/grc1|grc4/, out, "only the in-slice originals are listed")
    end
  end

  # The regression the owner hit: a range that STARTS inside a card — the
  # owning anchor lies outside the slice, yet the block still renders (it used
  # to dash every line).
  def test_show_parallel_range_starting_inside_a_card_still_shows_the_block
    with_card_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1.3-1.6", "--parallel"]) }
      assert_nil status
      assert_match(/eng \[:1\.1 — covers :1\.1–:1\.4; range shows :1\.3–:1\.4\]\n {4}Block one/, out,
                   "the card anchored at 1.1 (outside the slice) still renders its block")
      assert_match(/eng \[:1\.5 — covers :1\.5–:1\.8; range shows :1\.5–:1\.6\]\n {4}Block two/, out)
      refute_match(/eng {2}—/, out)
    end
  end

  def test_show_parallel_takes_an_explicit_language
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", ENG_URN, "--parallel", "grc"]) }
      assert_nil status
      assert_match(/#{Regexp.escape(GRC_URN)}/, out)
      assert_match(/grc {2}ἄειδε/, out, "grc :2, absent from the eng original, stays one-sided")
    end
  end

  def test_show_parallel_passage_urn_scopes_to_the_owning_block
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1", "--parallel"]) }
      assert_nil status
      assert_match(/grc {2}μῆνιν/, out)
      assert_match(/eng \[:1 — covers :1–:2; range shows :1–:1\]/, out, "the owning block, clipped to the line")
      assert_match(/Wrath/, out)
      refute_match(/ἄειδε/, out, "a passage urn shows only its own line of the block")
    end
  end

  def test_show_parallel_full_urn_restores_absolute_row_labels
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel", "eng", "--full-urn"]) }
      assert_nil status
      assert_match(/^ +#{Regexp.escape("#{GRC_URN}:1")}$/, out)
    end
  end

  def test_show_parallel_without_a_sibling_exits_one_naming_the_language
    with_parallel_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["show", GRC_URN, "--parallel", "lat"]) }
      assert_equal 1, status
      assert_match(/no lat parallel edition/i, err)
    end
  end

  def test_show_parallel_unknown_urn_exits_one
    with_parallel_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:cts:greekLit:tg1.w1.nope --parallel]) }
      assert_equal 1, status
      assert_match(/urn not found/i, err)
    end
  end

  # -- align (P11-3) ---------------------------------------------------------

  def test_align_renders_a_verse_across_witnesses_with_license_labels
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status, "an attested ref exits 0"
      assert_match(/MARK 2\.3 — New Testament/, out)
      assert_match(/greek-nt — Greek NT \[grc\] {3}license: nc/, out)
      assert_match(/marianus — Codex Marianus \[chu\] {3}license: nc/, out)
      assert_match(/παραλυτικὸν/, out)
      assert_match(/носѧште/, out)
      assert(out.index("παραλυτικὸν") < out.index("носѧште"),
             "witnesses render in registry order")
      assert_match(/2 of 2 witnesses/, out)
    end
  end

  def test_align_shows_the_hebrew_witness_at_its_native_ref_with_a_numbering_label
    registry = <<~YAML
      psalms:
        title: "Psalms"
        witnesses:
          - label: LXX
            extractor: cts-verse
            documents:
              PSA: urn:cts:greekLit:tlg0527.tlg027.1st1K-grc1
          - label: WEB (English)
            extractor: cts-verse
            numbering:
              system: "Hebrew (Masoretic)"
              ranges:
                - { from: 11, to: 113, shift: -1 }
            documents:
              PSA: urn:nabu:eng-web:psa
    YAML
    with_psalms_corpus(registry) do |config|
      out, _err, status = with_config(config) { run_cli(["align", "PSA", "22.1"]) }
      assert_nil status, "an attested ref exits 0"
      assert_match(/PSA 22\.1 — Psalms/, out)
      assert_match(/ποιμαίνει/, out, "the Greek witness at the work ref")
      assert_match(/Hebrew \(Masoretic\) numbering/, out, "the WEB column is flagged as remapped")
      assert_match(/\[Hebrew \(Masoretic\): PSA 23\.1\]/, out, "and shows its native Hebrew ref")
      assert_match(/shepherd/, out)
    end
  end

  def test_align_normalizes_the_query_ref
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "mark", "2:3"]) }
      assert_nil status
      assert_match(/MARK 2\.3/, out)
    end
  end

  def test_align_pivots_from_a_passage_urn
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align urn:nabu:proiel:marianus:1]) }
      assert_nil status
      assert_match(/MARK 2\.3/, out)
      assert_match(/παραλυτικὸν/, out)
    end
  end

  def test_align_unattested_ref_reads_honestly_and_exits_zero
    with_aligned_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "JOHN", "1.1"]) }
      assert_nil status, "an all-absent ref is a result, not an error"
      assert_match(/0 of 2 witnesses/, out)
      assert_match(/not attested/, out)
    end
  end

  def test_align_unsynced_witness_reads_not_synced
    with_aligned_corpus(extra_witness: "urn:nabu:proiel:wscp") do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status
      assert_match(/wscp — not synced/, out)
      assert_match(/2 of 3 witnesses/, out)
    end
  end

  # P11-5: a multi-document (cts-verse) witness that misses the ref heads its
  # column with the label alone — no arbitrary book title.
  def test_align_multi_document_witness_miss_renders_label_without_a_title
    registry = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - label: verses
            extractor: cts-verse
            documents:
              MARK: urn:nabu:proiel:marianus
              JOHN: urn:nabu:sblgnt:john
    YAML
    with_aligned_corpus(registry: registry) do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status
      assert_match(/^verses \[chu\] {3}license: nc/, out)
      assert_match(/not attested/, out)
      assert_match(/1 of 2 witnesses/, out)
    end
  end

  # …and when the multi-document witness does not even map the queried ref's
  # book, the not-synced note phrases the miss neutrally (no unrelated urn).
  def test_align_not_synced_multi_document_witness_with_unmapped_book_reads_neutrally
    registry = <<~YAML
      nt:
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:marianus
          - label: verses
            extractor: cts-verse
            documents:
              JOHN: urn:nabu:sblgnt:john
              ACTS: urn:nabu:sblgnt:acts
    YAML
    with_aligned_corpus(registry: registry) do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_nil status
      assert_match(/verses — not synced \(its registered documents are not in the catalog\)/, out)
      refute_match(/urn:nabu:sblgnt/, out, "no unrelated book urn is named")
    end
  end

  def test_align_without_index_hints_to_sync_or_rebuild
    with_aligned_corpus(indexed: false) do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_equal 1, status
      assert_match(/nabu sync or nabu rebuild/, err)
    end
  end

  def test_align_with_no_registry_exits_one_with_guidance
    with_aligned_corpus(registry: "") do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK", "2.3"]) }
      assert_equal 1, status
      assert_match(/no alignment works registered/i, err)
    end
  end

  def test_align_unknown_work_exits_one_naming_the_registered
    with_aligned_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK", "2.3", "--work", "iliad"]) }
      assert_equal 1, status
      assert_match(/iliad/, err)
      assert_match(/nt/, err)
    end
  end

  def test_align_without_a_ref_exits_one
    with_aligned_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[align]) }
      assert_equal 1, status
      assert_match(/give a citation/i, err)
    end
  end

  # -- align ranges / chapters (P11-8) ---------------------------------------

  def test_align_chapter_renders_every_ref_compactly_with_a_witness_legend
    with_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align JON 1]) }
      assert_nil status
      assert_match(/JON 1 — /, out, "the query heads the block")
      assert_match(/witnesses:.*full.*partial/m, out, "a one-line legend, titles shown once")
      # Every attested verse in document order, verse 1 before verse 2 before 10.
      assert(out.index("JON 1.1") < out.index("JON 1.2"), "refs in document order")
      assert(out.index("JON 1.2") < out.index("JON 1.10"), "numeric, not lexical, order")
      assert_match(/full  greek verse 1/, out)
      assert_match(/partial — not attested/, out, "per-ref attestation honesty")
    end
  end

  # P15-8: --long is wired on align (the flag never errors, the owner's
  # complaint). Under the cap it renders identically to compact; the cap-lift
  # itself is proven at the query level (a 205-verse fixture there).
  def test_align_accepts_long_and_renders_every_ref_under_the_cap
    with_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align JON 1 --long]) }
      assert_nil status
      assert_match(/JON 1 — /, out)
      assert_match(/full  greek verse 1/, out, "every attested ref still renders")
    end
  end

  def test_align_chapter_summarizes_all_absent_witnesses_once_in_the_header
    with_absent_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[align JON 1]) }
      assert_nil status
      assert_match(/not synced: ghost/, out, "an all-absent witness is summarized once in the header")
      assert_equal 1, out.scan("ghost").length, "ghost never repeats down the per-ref blocks"
      assert_match(/partial — not attested/, out, "a partially-attesting witness stays per-ref")
      assert_match(/full  greek verse 1/, out, "attesting witnesses render per ref as before")
    end
  end

  def test_align_verse_range_renders_the_inclusive_slice
    with_range_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "JON 1.3-1.5"]) }
      assert_nil status
      assert_match(/JON 1\.3/, out)
      assert_match(/JON 1\.5/, out)
      refute_match(/JON 1\.6/, out, "the range is inclusive and bounded")
      refute_match(/JON 1\.2\b/, out)
    end
  end

  def test_align_reversed_range_exits_one
    with_range_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["align", "JON 1.5-1.3"]) }
      assert_equal 1, status
      assert_match(/reversed range/, err)
    end
  end

  def test_help_align_documents_refs_work_and_examples
    out, _err, _status = run_cli(%w[help align])
    assert_match(/MARK 2\.3/, out, "a worked ref example")
    assert_match(/--work/, out)
    assert_match(%r{config/alignments\.yml}, out, "must point at the registry")
    assert_match(/Examples:/, out)
  end

  # -- cognates (P15-3) ------------------------------------------------------

  def test_cognates_renders_a_shared_root_verse_compactly
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["cognates", "MARK", "1.1"]) }
      assert_nil status
      assert_match(/MARK 1\.1 — work nt/, out)
      assert_match(/1 hit · 1 verse · 1 root/, out)
      assert_match(/\*bʰeh₂g- \[ine-pro · attribution\]/, out)
      assert_match(/grc {2}ἔφᾰγον — attested as ἔφαγεν/, out)
      assert_match(/chu {2}богъ/, out)
      refute_match(/gloss:/, out, "gloss is --long detail")
      refute_match(/urn:nabu:test/, out, "document urns are --long detail")
    end
  end

  def test_cognates_long_expands_gloss_and_witness_documents
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["cognates", "MARK", "1.1", "--long"]) }
      assert_nil status
      assert_match(/Wiktionary — Proto-Indo-European .* gloss: to divide/, out)
      assert_match(/urn:nabu:test:marianus — Codex Marianus \[nc\]/, out)
    end
  end

  def test_cognates_batches_a_work_and_labels_the_loan_shelf
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[cognates nt]) }
      assert_nil status
      assert_match(/nt — work nt/, out)
      assert_match(/\*kaisaraz \[gem-pro · attribution\]/, out,
                   "цѣсар҄ь ~ cāsere meet at the GERMANIC shelf — the borrowing label")
      assert(out.index("MARK 1.1") < out.index("MARK 2.1"), "hits in citation order")
    end
  end

  def test_cognates_langs_restricts_and_reports_no_hits_honestly
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[cognates nt --langs grc,ang]) }
      assert_nil status
      assert_match(/no hits/, out)
    end
  end

  # P17-3 acceptance render (the survey's JOHN 13.18 before/after): before,
  # the reader had to apply the taught meet-shelf reading to
  # "*hlaibaz [gem-pro]: chu хлѣбъ ~ got hlaifs"; after, the loan is STATED
  # per edge — the flagged OCS witness reads "(loan)", the Gothic side stays
  # an inheritance claim.
  def test_cognates_labels_the_flagged_loan_witness_per_edge
    with_cognates_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["cognates", "JOHN", "13.18"]) }
      assert_nil status
      assert_match(/\*hlaibaz \[gem-pro · attribution\]/, out)
      assert_match(/chu {2}хлѣбъ \(loan\)/, out, "the flagged witness edge says so itself")
      assert_match(/got {2}hlaifs(?! \(loan\))/, out, "the Gothic side carries no loan label")
    end
  end

  def test_cognates_langs_needs_two_languages
    with_cognates_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[cognates nt --langs chu]) }
      assert_equal 1, status
      assert_match(/at least two/, err)
    end
  end

  def test_cognates_unattested_ref_exits_one_with_guidance
    with_cognates_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["cognates", "JOHN", "99.1"]) }
      assert_equal 1, status
      assert_match(/not attested/, err)
    end
  end

  def test_help_cognates_documents_the_join_and_the_borrowing_caveat
    out, _err, _status = run_cli(%w[help cognates])
    assert_match(/LUKE 14\.34/, out, "the salt-saying example")
    assert_match(/--langs/, out)
    assert_match(/BORROWING/, out, "must teach the meet-shelf reading")
    assert_match(/Examples:/, out)
  end

  # -- align --collate (P15-4) -------------------------------------------------

  # A chu corpus for collation: the Cyrillic PROIEL Marianus + two Helsinki-
  # ASCII CCMH codices (registry order), so a chu/Latin cell forms and the
  # Cyrillic witness is the cross-script aside.
  COLLATE_REGISTRY = <<~YAML
    nt:
      title: "New Testament (parallel witnesses)"
      witnesses:
        - document: urn:nabu:proiel:marianus
          label: marianus
        - document: urn:nabu:ccmh:assemanianus
          label: ccmh-assemanianus
        - document: urn:nabu:ccmh:marianus
          label: ccmh-marianus
  YAML

  def with_collation_corpus
    Dir.mktmpdir("nabu-cli-collate") do |root|
      config = aligned_corpus_config(root, COLLATE_REGISTRY, nil)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      source_id = catalog[:sources].insert(slug: "proiel", name: "PROIEL",
                                           adapter_class: "TestAdapter", license_class: "nc", enabled: true)
      [["urn:nabu:proiel:marianus", "chu", "Ꙇ придѫ къ немоу носѧште ослабленъ жилами."],
       ["urn:nabu:ccmh:assemanianus", "chu", "*/i pridO k$ nemu nosEqe /oslablena ZIlamI ."],
       ["urn:nabu:ccmh:marianus", "chu", "*J pridO k& nemu nosESte oslablen& Zilami ."]].each do |urn, lang, text|
        doc_id = catalog[:documents].insert(source_id: source_id, urn: urn, title: urn.split(":").last,
                                            language: lang, content_sha256: "x", revision: 1, withdrawn: false)
        catalog[:passages].insert(
          document_id: doc_id, urn: "#{urn}:s", sequence: 0, language: lang, text: text,
          text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
          annotations_json: JSON.generate("citation" => "MARK 2.3",
                                          "tokens" => [{ "citation_part" => "MARK 2.3", "form" => "x" }])
        )
      end
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def test_align_collate_renders_an_apparatus_with_cross_script_honesty
    with_collation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK 2.3", "--collate"]) }
      assert_nil status
      assert_match(/MARK 2\.3 — New Testament.*· collation/, out)
      assert_match(%r{\[chu/Latin\] 2 witnesses, base ccmh-assemanianus}, out)
      assert_match(/= ccmh-assemanianus/, out, "the base reading is printed in full")
      # The real substitution surfaces, markers kept raw.
      assert_match(/nosEqe.*→.*nosESte/, out)
      # The Cyrillic witness is set aside, honestly.
      assert_match(%r{\[chu/Cyrillic\] marianus.*different transcription system}, out)
      assert_match(/придѫ/, out, "the aside still shows its text")
    end
  end

  def test_align_collate_base_flag_selects_the_base
    with_collation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK 2.3", "--collate", "--base", "ccmh-marianus"]) }
      assert_nil status
      assert_match(/base ccmh-marianus/, out)
    end
  end

  def test_align_collate_long_prints_full_tokens_per_witness
    with_collation_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["align", "MARK 2.3", "--collate", "--long"]) }
      assert_nil status
      # Under --long the divergent witness prints its whole token line, not marks.
      assert_match(/ccmh-marianus  \*J pridO k& nemu nosESte/, out)
      refute_match(/→/, out, "--long shows tokens, not apparatus arrows")
    end
  end

  def test_align_base_without_collate_exits_one
    with_collation_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK 2.3", "--base", "ccmh-marianus"]) }
      assert_equal 1, status
      assert_match(/--base only applies with --collate/, err)
    end
  end

  def test_align_collate_base_miss_exits_one
    with_collation_corpus do |config|
      _out, err, status = with_config(config) { run_cli(["align", "MARK 2.3", "--collate", "--base", "nope"]) }
      assert_equal 1, status
      assert_match(/no witness matches --base/, err)
    end
  end

  def test_help_align_documents_collate
    out, _err, _status = run_cli(%w[help align])
    assert_match(/--collate/, out)
    assert_match(/--base/, out)
  end

  # -- export (P4-3) -------------------------------------------------------

  def test_export_plain_streams_one_line_per_passage
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[export --format plain]) }
      assert_nil status
      lines = out.split("\n")
      assert_equal 3, lines.size, "three live passages, one line each"
      assert_includes lines, "μῆνιν"
    end
  end

  def test_export_jsonl_emits_valid_json_objects
    with_indexed_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[export --format jsonl]) }
      assert_nil status
      records = out.split("\n").map { |line| JSON.parse(line) }
      assert_equal 3, records.size
      record = records.first
      assert_equal %w[annotations language text text_normalized urn].sort, record.keys.sort
      assert_kind_of Hash, record.fetch("annotations")
    end
  end

  def test_export_conllu_is_deferred
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[export --format conllu]) }
      assert_equal 1, status
      assert_match(/deferred until the enrichment phase/i, err)
    end
  end

  def test_export_bad_license_exits_one
    with_indexed_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[export --format plain --license bogus]) }
      assert_equal 1, status
      assert_match(/unknown license/i, err)
    end
  end

  # -- display policy (P27-0) ----------------------------------------------

  def test_show_default_display_strips_cantillation_and_hints_once
    with_hebrew_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:gen:1.1]) }
      assert_nil status
      assert_includes out, HBO_GEN_1_1_NO_CANT, "cantillation stripped, points kept"
      refute_includes out, HBO_GEN_1_1, "the marked bytes must not render in default mode"
      assert_equal 1, out.scan("display:").size, "the hint prints exactly once"
      assert_includes out, "display: cantillation stripped · rtl isolates (--display full shows all marks)"
    end
  end

  def test_show_display_full_is_byte_identical_and_hint_free
    with_hebrew_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:gen:1.1 --display full]) }
      assert_nil status
      assert_includes out, HBO_GEN_1_1, "full mode shows the stored bytes"
      refute_includes out, RLI, "full mode adds no isolates"
      refute_includes out, "display:", "nothing transformed → no hint (compact rule)"
    end
  end

  def test_show_display_plain_renders_consonantal_hebrew
    with_hebrew_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:gen:1.1 --display plain]) }
      assert_nil status
      assert_includes out, HBO_GEN_1_1_CONSONANTAL
      assert_includes out, "display:", "plain mode transforms → hint"
    end
  end

  def test_show_display_chu_titla_footer_matches_the_house_form
    with_hebrew_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:torot:zogr:1]) }
      assert_nil status
      assert_includes out, CHU_ZOGR_NO_TITLA
      assert_includes out, "display: titla stripped (--display full shows all marks)"
      refute_includes out, RLI, "chu has no isolates policy"
    end
  end

  def test_show_unknown_display_mode_is_a_named_error
    with_hebrew_corpus do |config|
      _out, err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:gen:1.1 --display sideways]) }
      assert_equal 1, status
      assert_match(/sideways/, err)
      assert_match(/default/, err, "the error names the registered modes")
    end
  end

  def test_no_display_hint_when_language_has_no_policy
    with_parallel_corpus do |config|
      out, _err, status = with_config(config) { run_cli(["show", "#{GRC_URN}:1"]) }
      assert_nil status
      refute_includes out, "display:", "grc has no policy — silence, not a no-op hint"
    end
  end

  # The independence pin: --display changes RENDER only. The same query must
  # return the same hits under every mode, and matching/folding never see the
  # transforms.
  def test_search_hits_are_identical_under_every_display_mode
    with_hebrew_corpus do |config|
      outs = %w[default full plain reading diplomatic].to_h do |mode|
        out, _err, status = with_config(config) { run_cli(["search", "אלהים", "--display", mode]) }
        assert_nil status, "search must succeed under --display #{mode}"
        [mode, out]
      end
      urns = outs.transform_values { |out| out.lines.grep(/urn:/).map { |l| l[/urn:\S+/] } }
      assert_equal urns["full"], urns["default"]
      assert_equal urns["full"], urns["plain"]
      assert_equal urns["full"], urns["reading"], "edition transforms never change matching (P27-1)"
      assert_equal urns["full"], urns["diplomatic"]
      assert_includes urns["full"].join, "urn:nabu:oshb:gen:1.1"
      assert_includes outs["default"], RLI, "hbo snippets are isolate-wrapped in default mode"
      refute_includes outs["full"], RLI
    end
  end

  # KWIC width pin: the keyword column must sit at exactly --width visible
  # characters — isolates excluded from the math, and the stripped (shorter)
  # left context re-padded so columns still line up.
  def test_concord_keyword_column_ignores_isolates_and_stripped_marks
    with_hebrew_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[concord אלהים]) }
      assert_nil status
      row = out.lines.find { |line| line.include?("urn:nabu:oshb:gen:1.1") }
      refute_nil row, "the Hebrew verse must appear as a KWIC row"
      visible = row.delete(RLI + PDI)
      assert_equal Nabu::Query::Concord::DEFAULT_WIDTH, visible.index("אֱלֹהִים"),
                   "keyword column = width, counted over visible characters"
      assert_includes out, "display: cantillation stripped · rtl isolates (--display full shows all marks)"
    end
  end

  # -- edition-level display (P27-1) ---------------------------------------

  # SBLGNT 3John 1:4 exactly as SblgntParser stores it: the upstream ⸀
  # apparatus sigla ride the verse bytes verbatim.
  SBLGNT_3JOHN_1_4 = "μειζοτέραν τούτων οὐκ ἔχω ⸀χαράν, ἵνα ἀκούω τὰ ἐμὰ τέκνα ἐν ⸀τῇ ἀληθείᾳ περιπατοῦντα."

  def test_show_display_reading_substitutes_qere_and_hints_the_edition_footer
    with_edition_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:ruth:1.8 --display reading]) }
      assert_nil status
      body = out.delete(RLI + PDI)
      assert_includes body, "יַעַשׂ", "the qere reading, cantillation stripped by the hbo policy"
      refute_includes body, "יעשה", "the ketiv must not render under reading mode"
      assert_equal 1, out.scan("display:").size, "the hint prints exactly once"
      assert_includes out, "display: cantillation stripped · apparatus simplified: qere · " \
                           "rtl isolates (--display diplomatic shows the edition marks)"
    end
  end

  def test_show_display_diplomatic_is_byte_identical_and_hint_free
    with_edition_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:ruth:1.8 --display diplomatic]) }
      assert_nil status
      assert_includes out, "יעשה", "diplomatic shows the stored ketiv"
      refute_includes out, RLI, "diplomatic adds no isolates"
      refute_includes out, "display:", "nothing transformed → no hint (compact rule)"
    end
  end

  def test_show_display_reading_strips_sblgnt_sigla_with_the_edition_footer
    with_edition_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:sblgnt:3john:1.4 --display reading]) }
      assert_nil status
      refute_includes out, "⸀", "the apparatus sigla are simplified away"
      assert_includes out, "μειζοτέραν τούτων οὐκ ἔχω χαράν"
      assert_includes out, "display: apparatus simplified: sigla (--display diplomatic shows the edition marks)"
    end
  end

  def test_show_default_mode_keeps_the_sblgnt_sigla_silently
    with_edition_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:sblgnt:3john:1.4]) }
      assert_nil status
      assert_includes out, SBLGNT_3JOHN_1_4, "edition rules belong to reading mode only"
      refute_includes out, "display:", "grc has no language policy — silence"
    end
  end

  def test_show_document_listing_substitutes_qere_under_reading
    with_edition_corpus do |config|
      out, _err, status = with_config(config) { run_cli(%w[show urn:nabu:oshb:ruth --display reading]) }
      assert_nil status
      body = out.delete(RLI + PDI)
      assert_includes body, "יַעַשׂ", "the document listing renders lines through the same edition seam"
      refute_includes body, "יעשה"
    end
  end

  def test_align_layout_is_identical_apart_from_the_text_transforms
    with_hebrew_corpus do |config|
      default_out, _err, status = with_config(config) { run_cli(["align", "GEN", "1.1"]) }
      assert_nil status
      full_out, _err2, = with_config(config) { run_cli(["align", "GEN", "1.1", "--display", "full"]) }
      assert_includes default_out, "#{RLI}#{HBO_GEN_1_1_NO_CANT}#{PDI}"
      assert_includes full_out, HBO_GEN_1_1
      structural = ->(out) { out.lines.reject { |l| l.include?("אֱ") || l.include?("display:") } }
      assert_equal structural.call(full_out), structural.call(default_out),
                   "every non-Hebrew line (headers, labels, urns) must be unaffected by the transforms"
    end
  end

  private

  # A config whose db/ has been fully built (catalog + fulltext index) by a real
  # parse-only sync of the two-document TestAdapter corpus. Yields the config.
  def with_indexed_corpus
    with_sync_env(enabled: true) do |config|
      with_config(config) do
        capture_io { Nabu::CLI.start(%w[sync corpus --parse-only]) }
      end
      yield config
    end
  end

  # A parallels (P15-1) corpus: an anchor line and a verbatim quoter that shares
  # FOUR non-contiguous phrase spans (the fillers ξξ*/ζζ break continuity), so
  # the quoter's evidence has four spans — compact elides the fourth, --long
  # expands it. Built and indexed through the real Indexer (no alignments).
  def with_parallels_corpus
    anchor = "ἄνδρα μοι ἔννεπε μοῦσα ξξ1 ξξ2 ξξ3 π2a π2b π2c π2d ξξ4 ξξ5 ξξ6 " \
             "π3a π3b π3c π3d ξξ7 ξξ8 ξξ9 π4a π4b π4c π4d"
    quoter = "λεγει ἄνδρα μοι ἔννεπε μοῦσα ζζ π2a π2b π2c π2d ζζ π3a π3b π3c π3d ζζ π4a π4b π4c π4d"
    Dir.mktmpdir("nabu-cli-parallels") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      src = catalog[:sources].insert(slug: "h", name: "Homer", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      seed_parallels_passage(catalog, src, "urn:h:od", "urn:h:od:1.1", anchor)
      seed_parallels_passage(catalog, src, "urn:q:full", "urn:q:full:1", quoter)
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext, alignments: nil)
      fulltext.disconnect
      catalog.disconnect
      yield config
    end
  end

  # A formula-miner (P15-5) corpus: one ASPR document whose refrain "saga hwaet
  # ic hatte" recurs across four riddle lines, each with unique tail words. Only
  # the catalog is needed (the miner reads text_normalized directly, no index).
  def with_formulas_corpus
    Dir.mktmpdir("nabu-cli-formulas") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      src = catalog[:sources].insert(slug: "aspr", name: "ASPR", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      doc_id = catalog[:documents].insert(
        source_id: src, urn: "urn:nabu:aspr:riddle", title: "Riddles", language: "ang",
        content_sha256: "x", revision: 1, withdrawn: false
      )
      ["foo bar", "baz qux", "alpha beta", "gamma delta"].each_with_index do |tail, i|
        text = "saga hwaet ic hatte #{tail}"
        catalog[:passages].insert(
          document_id: doc_id, urn: "urn:nabu:aspr:riddle:#{i}", sequence: i, language: "ang",
          text: text, text_normalized: Nabu::Normalize.search_form(text, language: "ang"),
          content_sha256: "x", revision: 1, withdrawn: false, annotations_json: "{}"
        )
      end
      catalog.disconnect
      yield config
    end
  end

  # A list (P22-1) corpus: a passage shelf with live/withdrawn/retired
  # documents, a mixed license story and one dated document; a dictionary
  # shelf; and a manifest-collection shelf — everything `nabu list` renders,
  # seeded directly (no fulltext index needed: list reads only the catalog).
  def with_list_corpus
    Dir.mktmpdir("nabu-cli-list") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, <<~YAML)
        shelf:
          adapter: TestAdapter
          enabled: true
          sync_policy: manual
        lex:
          adapter: TestAdapter
          enabled: true
          sync_policy: frozen
        library:
          adapter: TestAdapter
          enabled: true
          sync_policy: local
      YAML
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_list_shelf(catalog)
      seed_list_lex(catalog)
      seed_list_library(catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_list_shelf(catalog)
    src = catalog[:sources].insert(slug: "shelf", name: "Shelf", adapter_class: "TestAdapter",
                                   license: "CC BY-NC 4.0 (compiled by Test)",
                                   license_class: "nc", enabled: true)
    alpha = seed_list_document(catalog, src, "urn:nabu:shelf:alpha", "Alpha", "grc", override: "open")
    seed_list_passage(catalog, alpha, "urn:nabu:shelf:alpha:1", 0, "grc")
    seed_list_passage(catalog, alpha, "urn:nabu:shelf:alpha:2", 1, "grc")
    catalog[:document_axes].insert(document_id: alpha, not_before: -113, not_after: 602, axis_source: "hgv")
    beta = seed_list_document(catalog, src, "urn:nabu:shelf:beta", "Beta", "lat", retired: true)
    seed_list_passage(catalog, beta, "urn:nabu:shelf:beta:1", 0, "lat")
    gone = seed_list_document(catalog, src, "urn:nabu:shelf:gone", "Gone", "grc", withdrawn: true)
    seed_list_passage(catalog, gone, "urn:nabu:shelf:gone:1", 0, "grc")
  end

  def seed_list_lex(catalog)
    src = catalog[:sources].insert(slug: "lex", name: "Lexica", adapter_class: "TestAdapter",
                                   license_class: "attribution", enabled: true)
    dict = catalog[:dictionaries].insert(source_id: src, slug: "sla-pro", title: "Proto-Slavic",
                                         language: "sla-pro")
    [["n1", "bʰer-", "bher-", "to carry"], ["n2", "bogъ", "bogъ", "god"]].each do |id, head, folded, gloss|
      catalog[:dictionary_entries].insert(
        dictionary_id: dict, urn: "urn:nabu:dict:sla-pro:#{id}", entry_id: id, key_raw: head,
        headword: head, headword_folded: folded, gloss: gloss, body: "#{head} body",
        content_sha256: "x", revision: 1, withdrawn: false
      )
    end
  end

  def seed_list_library(catalog)
    src = catalog[:sources].insert(slug: "library", name: "Library", adapter_class: "TestAdapter",
                                   license_class: "research_private", enabled: true)
    %w[slavistics:leskien slavistics:jagic articles:vaillant].each do |tail|
      seed_list_document(catalog, src, "urn:nabu:library:#{tail}", tail, "deu")
    end
  end

  def seed_list_document(catalog, source_id, urn, title, language, override: nil, withdrawn: false, retired: false)
    catalog[:documents].insert(
      source_id: source_id, urn: urn, title: title, language: language,
      license_override: override, content_sha256: "x", revision: 1,
      withdrawn: withdrawn, retired_upstream: retired
    )
  end

  def seed_list_passage(catalog, doc_id, urn, sequence, language)
    catalog[:passages].insert(
      document_id: doc_id, urn: urn, sequence: sequence, language: language,
      text: "text #{sequence}", text_normalized: "text #{sequence}",
      content_sha256: "x", revision: 1, withdrawn: false, annotations_json: "{}"
    )
  end

  def seed_parallels_passage(catalog, source_id, doc_urn, passage_urn, text)
    doc_id = catalog[:documents].insert(
      source_id: source_id, urn: doc_urn, title: doc_urn, language: "grc",
      content_sha256: "x", revision: 1, withdrawn: false
    )
    catalog[:passages].insert(
      document_id: doc_id, urn: passage_urn, sequence: 0, language: "grc",
      text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
      content_sha256: "x", revision: 1, withdrawn: false, annotations_json: "{}"
    )
  end

  # A dated corpus (P15-2): three papyri with document_axes rows spanning BCE→CE,
  # indexed through the real Indexer, for the CLI date/place surfaces.
  def with_dated_corpus
    Dir.mktmpdir("nabu-cli-dated") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      src = catalog[:sources].insert(slug: "p", name: "Papyri", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      seed_dated_passage(catalog, src, "urn:nabu:ddbdp:a", "στρατηγος αγαθος", -113, -113, "Oxyrhynchus")
      seed_dated_passage(catalog, src, "urn:nabu:ddbdp:b", "στρατηγος κακος", 591, 602, "Arsinoites")
      seed_dated_passage(catalog, src, "urn:nabu:ddbdp:c", "στρατηγος μεγας", -30, 14, "Oxyrhynchus")
      # Facet rows (P17-2): a/b faceted, c honestly unfaceted — the dated
      # corpus doubles as the facet-composition fixture.
      seed_facet(catalog, "urn:nabu:ddbdp:a", "genre", "epitaph", "titsep?")
      seed_facet(catalog, "urn:nabu:ddbdp:a", "province", "Pannonia inferior", "PaI")
      seed_facet(catalog, "urn:nabu:ddbdp:b", "genre", "votive inscription", "titsac")
      seed_facet(catalog, "urn:nabu:ddbdp:b", "province", "Britannia", "Bri")
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      # fuzzy_slugs (P16-4): the dated corpus doubles as the fuzzy+date
      # composition fixture — the "p" shelf is documentary by construction.
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext, alignments: nil, fuzzy_slugs: ["p"])
      fulltext.disconnect
      catalog.disconnect
      yield config
    end
  end

  # A fuzzy (P16-4) corpus: one documentary source ("pap", trigram-indexed)
  # and one literary source ("lit", word-index only) sharing a damaged-text
  # fragment, built through the real Indexer with the documentary scope.
  def with_fuzzy_corpus
    Dir.mktmpdir("nabu-cli-fuzzy") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      pap = catalog[:sources].insert(slug: "pap", name: "Papyri", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      lit = catalog[:sources].insert(slug: "lit", name: "Literary", adapter_class: "TestAdapter",
                                     license_class: "open", enabled: true)
      seed_fuzzy_passage(catalog, pap, "urn:nabu:pap:a", "μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος")
      seed_fuzzy_passage(catalog, lit, "urn:nabu:lit:a", "μῆνιν ἄειδε θεὰ καὶ ὀλόμπιος ἀοιδός")
      fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
      Nabu::Store::Indexer.rebuild!(catalog: catalog, fulltext: fulltext, alignments: nil, fuzzy_slugs: ["pap"])
      fulltext.disconnect
      catalog.disconnect
      yield config
    end
  end

  def seed_fuzzy_passage(catalog, source_id, doc_urn, text)
    doc_id = catalog[:documents].insert(
      source_id: source_id, urn: doc_urn, title: doc_urn, language: "grc",
      content_sha256: doc_urn, revision: 1, withdrawn: false
    )
    catalog[:passages].insert(
      document_id: doc_id, urn: "#{doc_urn}:1", sequence: 0, language: "grc",
      text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
      content_sha256: "#{doc_urn}p", revision: 1, withdrawn: false, annotations_json: "{}"
    )
  end

  def seed_facet(catalog, doc_urn, facet, value, raw)
    doc_id = catalog[:documents].where(urn: doc_urn).get(:id)
    catalog[:document_facets].insert(document_id: doc_id, facet: facet, value: value, raw: raw)
  end

  def seed_dated_passage(catalog, source_id, doc_urn, text, not_before, not_after, place)
    doc_id = catalog[:documents].insert(
      source_id: source_id, urn: doc_urn, title: doc_urn, language: "grc",
      content_sha256: doc_urn, revision: 1, withdrawn: false
    )
    catalog[:passages].insert(
      document_id: doc_id, urn: "#{doc_urn}:1", sequence: 0, language: "grc",
      text: text, text_normalized: Nabu::Normalize.search_form(text, language: "grc"),
      content_sha256: "#{doc_urn}p", revision: 1, withdrawn: false, annotations_json: "{}"
    )
    catalog[:document_axes].insert(
      document_id: doc_id, not_before: not_before, not_after: not_after,
      precision: "low", place_name: place, axis_source: "hgv"
    )
  end

  # An on-disk two-witness alignment corpus (P11-3): a registry file, a
  # catalog with the greek-nt/marianus MARK 2.3 sentences (real live-catalog
  # snippets, sentence-id urns, verse identity in the token citation_parts),
  # and — unless indexed: false — the fulltext db with alignment_refs built.
  def with_aligned_corpus(registry: nil, extra_witness: nil, indexed: true)
    Dir.mktmpdir("nabu-cli-align") do |root|
      config = aligned_corpus_config(root, registry, extra_witness)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_aligned_witnesses(catalog)
      index_aligned_corpus(config, catalog) if indexed
      catalog.disconnect
      yield config
    end
  end

  # A two-witness Psalms corpus (P13-5): the LXX shepherd verse at Greek 22.1
  # and the WEB shepherd verse at Hebrew 23.1, so the numbering remap is
  # exercised end to end through the CLI render.
  def with_psalms_corpus(registry)
    Dir.mktmpdir("nabu-cli-psalms") do |root|
      alignments = File.join(root, "alignments.yml")
      File.write(alignments, registry)
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, alignments_path: alignments, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_psalms_witnesses(catalog)
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_psalms_witnesses(catalog)
    source_id = catalog[:sources].insert(
      slug: "bible", name: "Bible", adapter_class: "TestAdapter", license_class: "attribution",
      enabled: true
    )
    [["urn:cts:greekLit:tlg0527.tlg027.1st1K-grc1", "Psalmi", "grc", "22.1", "Κύριος ποιμαίνει με"],
     ["urn:nabu:eng-web:psa", "Psalms", "eng", "23.1",
      "Yahweh is my shepherd: I shall lack nothing."]].each do |doc_urn, title, lang, tail, text|
      doc_id = catalog[:documents].insert(
        source_id: source_id, urn: doc_urn, title: title, language: lang,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      catalog[:passages].insert(
        document_id: doc_id, urn: "#{doc_urn}:#{tail}", sequence: 0, language: lang,
        text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
        annotations_json: "{}"
      )
    end
  end

  def aligned_corpus_config(root, registry, extra_witness)
    yaml = registry || <<~YAML
      nt:
        title: "New Testament (parallel witnesses)"
        witnesses:
          - document: urn:nabu:proiel:greek-nt
          - document: urn:nabu:proiel:marianus
    YAML
    yaml += "    - document: #{extra_witness}\n" if extra_witness
    alignments = File.join(root, "alignments.yml")
    File.write(alignments, yaml)
    sources = File.join(root, "sources.yml")
    File.write(sources, "# none\n")
    Nabu::Config.new(
      canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
      sources_path: sources, alignments_path: alignments, config_path: "(test)"
    )
  end

  def seed_aligned_witnesses(catalog)
    source_id = catalog[:sources].insert(
      slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter", license_class: "nc",
      enabled: true
    )
    [["greek-nt", "Greek NT", "grc",
      "καὶ ἔρχονται φέροντες πρὸς αὐτὸν παραλυτικὸν αἰρόμενον ὑπὸ τεσσάρων."],
     ["marianus", "Codex Marianus", "chu",
      "Ꙇ придѫ къ немоу носѧште ослабленъ жилами. носимъ четꙑрьми."]].each do |tail, title, lang, text|
      doc_id = catalog[:documents].insert(
        source_id: source_id, urn: "urn:nabu:proiel:#{tail}", title: title, language: lang,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      catalog[:passages].insert(
        document_id: doc_id, urn: "urn:nabu:proiel:#{tail}:1", sequence: 0, language: lang,
        text: text, text_normalized: text, content_sha256: "x", revision: 1, withdrawn: false,
        annotations_json: JSON.generate(
          "citation" => "MARK 2.3",
          "tokens" => [{ "citation_part" => "MARK 2.3", "form" => "x" }]
        )
      )
    end
  end

  # A synced+indexed corpus for range/chapter align tests: two cts-verse
  # witnesses over Jonah 1 — "full" attests vv. 1..10, "partial" only 1 and 3.
  def range_registry_yaml
    <<~YAML
      ot:
        witnesses:
          - label: full
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-a:jon
          - label: partial
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-b:jon
    YAML
  end

  def with_range_corpus
    Dir.mktmpdir("nabu-cli-range") do |root|
      config = aligned_corpus_config(root, range_registry_yaml, nil)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_range_witnesses(catalog)
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  # Jonah 1 with a THIRD witness (ghost) whose document is never seeded — it is
  # not_synced across the whole range, so P11-9 lifts it to the header summary
  # and drops it from every per-ref block. full/partial seed as usual.
  def with_absent_range_corpus
    yaml = <<~YAML
      ot:
        witnesses:
          - label: full
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-a:jon
          - label: partial
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-b:jon
          - label: ghost
            extractor: cts-verse
            documents:
              JON: urn:nabu:src-z:jon
    YAML
    Dir.mktmpdir("nabu-cli-absent") do |root|
      config = aligned_corpus_config(root, yaml, nil)
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_range_witnesses(catalog) # src-a + src-b only; src-z stays unsynced
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_range_witnesses(catalog)
    source_id = catalog[:sources].insert(
      slug: "bible", name: "Bible", adapter_class: "TestAdapter", license_class: "open", enabled: true
    )
    seed_verse_book(catalog, source_id, "urn:nabu:src-a:jon", "ΙΩΝΑΣ", "grc",
                    (1..10).map { |v| ["1.#{v}", "greek verse #{v}"] })
    seed_verse_book(catalog, source_id, "urn:nabu:src-b:jon", "Jonas", "lat",
                    [["1.1", "latin one"], ["1.3", "latin three"]])
  end

  def seed_verse_book(catalog, source_id, urn, title, lang, verses)
    doc_id = catalog[:documents].insert(
      source_id: source_id, urn: urn, title: title, language: lang,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    verses.each_with_index do |(tail, text), sequence|
      catalog[:passages].insert(
        document_id: doc_id, urn: "#{urn}:#{tail}", sequence: sequence, language: lang,
        text: text, text_normalized: text, content_sha256: "x", revision: 1,
        withdrawn: false, annotations_json: "{}"
      )
    end
  end

  def index_aligned_corpus(config, catalog)
    FileUtils.mkdir_p(File.dirname(config.fulltext_path))
    fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
    Nabu::Store::Indexer.rebuild!(
      catalog: catalog, fulltext: fulltext,
      alignments: Nabu::AlignmentRegistry.load(config.alignments_path)
    )
    fulltext.disconnect
  end

  # A synced-and-indexed corpus with one document whose two passages carry the
  # keyword in different-length words (μῆνιν vs μηνιτισι), matched by one
  # prefix query — the KWIC alignment rig. Same parse-only sync pipeline.
  def with_kwic_corpus
    Dir.mktmpdir("nabu-cli-kwic") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "kwic.txt"),
                 "KWIC\nalpha μῆνιν beta gamma\ndelta μηνιτισι epsilon\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: true\n  sync_policy: live\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      with_config(config) { capture_io { Nabu::CLI.start(%w[sync corpus --parse-only]) } }
      yield config
    end
  end

  # A synced-and-indexed corpus of ONE real treebank fixture (UD Ancient Greek
  # PROIEL), for the --lemma path: the lemma index only has rows when
  # annotations carry token lemmas, which TestAdapter's plaintext corpus never
  # does. Same parse-only sync pipeline as with_indexed_corpus.
  def with_treebank_corpus
    Dir.mktmpdir("nabu-cli-lemma") do |root|
      treebank = File.join(root, "canonical", "ud", "greek-proiel")
      FileUtils.mkdir_p(treebank)
      FileUtils.cp(File.expand_path("fixtures/ud/greek-proiel/grc_proiel-ud-test-head50.conllu", __dir__),
                   treebank)
      sources = File.join(root, "sources.yml")
      File.write(sources, "ud:\n  adapter: Nabu::Adapters::UniversalDependencies\n  " \
                          "enabled: true\n  sync_policy: live\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      with_config(config) do
        capture_io { Nabu::CLI.start(%w[sync ud --parse-only]) }
      end
      yield config
    end
  end

  # Append three succeeded runs for the just-synced "corpus" source so the
  # latest errored count (90) towers over the recent norm — a quarantine spike.
  # Runs live in the history ledger (P7-1), slug-keyed; writes through its own
  # connection, then hands back so the CLI opens it fresh.
  def seed_failed_run(config, notes:)
    db = Nabu::Store::Ledger.open!(config.history_path)
    now = Time.now
    Nabu::Store::Run.create(source_slug: "corpus", kind: "sync", started_at: now, finished_at: now,
                            status: "failed", notes: notes)
  ensure
    db&.disconnect
  end

  def seed_spike_runs(config)
    db = Nabu::Store::Ledger.open!(config.history_path)
    now = Time.now
    [2, 3, 90].each do |errored|
      Nabu::Store::Run.create(source_slug: "corpus", kind: "sync", started_at: now, finished_at: now,
                              added: 1, updated: 0, errored: errored, status: "succeeded")
    end
  ensure
    db&.disconnect
  end

  # capture_io, but with tty? forced on the swapped StringIO streams so the
  # tty-gated progress paths can be exercised (Minitest 6 has no Mock; this is
  # the house swap-singleton pattern). Returns [stdout_string, stderr_string].
  def capture_with_tty(stderr_tty:)
    out = StringIO.new
    err = StringIO.new
    out.define_singleton_method(:tty?) { false }
    err.define_singleton_method(:tty?) { stderr_tty }
    old_out = $stdout
    old_err = $stderr
    $stdout = out
    $stderr = err
    yield
    [out.string, err.string]
  ensure
    $stdout = old_out
    $stderr = old_err
  end

  # A built catalog holding two sibling CTS editions of one work (grc + eng,
  # aligned suffixes :1/:3, grc-only :2) for the show --parallel surface.
  def with_parallel_corpus
    Dir.mktmpdir("nabu-cli-parallel") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.create(
        slug: "src", name: "Source", adapter_class: "TestAdapter", license_class: "attribution"
      )
      loader = Nabu::Store::Loader.new(db: db, source: source)
      loader.load([parallel_document(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]]),
                   parallel_document(ENG_URN, "eng", [%w[1 Wrath], %w[3 goddess]])], full: false)
      db.disconnect
      yield config
    end
  end

  def parallel_document(urn, language, passages)
    document = Nabu::Document.new(
      urn: urn, language: language, title: "Iliad", canonical_path: "/canonical/src/#{language}.xml"
    )
    passages.each_with_index do |(suffix, text), index|
      document << Nabu::Passage.new(urn: "#{urn}:#{suffix}", language: language, text: text, sequence: index)
    end
    document
  end

  # A verse-for-verse corpus (grc :1/:2/:3 ↔ eng :1/:2/:3, all 1:1) for the
  # byte-identical pair-form regression pin.
  def with_verse_corpus(&)
    build_parallel_corpus(
      parallel_document(GRC_URN, "grc", [%w[1 μῆνιν], %w[2 ἄειδε], %w[3 θεά]]),
      parallel_document(ENG_URN, "eng", [%w[1 Wrath], %w[2 sing], %w[3 goddess]]), &
    )
  end

  # A card-cited corpus: grc lines 1.1..1.8, eng cards anchored at 1.1 (owns
  # 1.1–1.4) and 1.5 (owns 1.5–1.8) — the coarse span-grouped case.
  def with_card_corpus(&)
    build_parallel_corpus(
      parallel_document(GRC_URN, "grc", (1..8).map { |n| ["1.#{n}", "grc#{n}"] }),
      parallel_document(ENG_URN, "eng", [["1.1", "Block one"], ["1.5", "Block two"]]), &
    )
  end

  def build_parallel_corpus(*documents)
    Dir.mktmpdir("nabu-cli-parallel") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.create(
        slug: "src", name: "Source", adapter_class: "TestAdapter", license_class: "attribution"
      )
      Nabu::Store::Loader.new(db: db, source: source).load(documents, full: false)
      db.disconnect
      yield config
    end
  end

  # A built catalog holding the real wiktionary-recon reconstruction shelves
  # (the query-layer fixtures) for the define/etym --long surface. No fulltext
  # db is built, so every reflex counts as "not attested here" — exactly the
  # list the P14-11 flag expands. The caller stubs Config.load with the config.
  def with_recon_shelf
    Dir.mktmpdir("nabu-cli-recon") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.create(
        slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
        adapter_class: "Nabu::Adapters::WiktionaryRecon", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                   .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                              workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
      load_language_shelf(db)
      db.disconnect
      yield config
    end
  end

  # P26-0: the recon shelf PLUS a tiered lemma index at config.fulltext_path —
  # chu зима attested 1× by a gold source and 2× by a silver (automatic)
  # source, orv зима 3× silver-only. The tier map is what the registry's
  # `lemma_tier: silver` line would thread through sync/rebuild.
  def with_tiered_recon_shelf
    with_recon_shelf do |config|
      db = Nabu::Store.connect(config.catalog_path)
      begin
        gold = Nabu::Store::Source.create(
          slug: "treebank", name: "Treebank", adapter_class: "TestAdapter", license_class: "open"
        )
        silver = Nabu::Store::Source.create(
          slug: "auto", name: "Auto", adapter_class: "TestAdapter", license_class: "open"
        )
        seed_tier_passages(source: gold, language: "chu", count: 1)
        seed_tier_passages(source: silver, language: "chu", count: 2)
        seed_tier_passages(source: silver, language: "orv", count: 3)
        fulltext = Nabu::Store.connect_fulltext(config.fulltext_path)
        begin
          Nabu::Store::Indexer.rebuild!(catalog: db, fulltext: fulltext,
                                        lemma_tiers: { "auto" => "silver" })
        ensure
          fulltext.disconnect
        end
      ensure
        db.disconnect
      end
      yield config
    end
  end

  def seed_tier_passages(source:, language:, count:)
    urn_stem = "urn:nabu:test:#{source.slug}:#{language}"
    document = Nabu::Store::Document.create(
      source_id: source.id, urn: urn_stem, title: "T", language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    count.times do |i|
      Nabu::Store::Passage.create(
        document_id: document.id, urn: "#{urn_stem}:#{i + 1}", sequence: i,
        language: language, text: "зима", text_normalized: "зима",
        annotations_json: JSON.generate({ "tokens" => [{ "lemma" => "зима", "form" => "зима" }] }),
        content_sha256: "x", revision: 1
      )
    end
  end

  # P24-2: the starling shelves — a crosswalk WITH reflex rows (piet/
  # germet/baltet) alongside a prose-only etymological dictionary (vasmer,
  # rus — zero reflex rows), the exact define/etym coordination incident.
  def with_starling_shelf
    Dir.mktmpdir("nabu-cli-starling") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      source = Nabu::Store::Source.create(
        slug: "starling", name: "StarLing IE",
        adapter_class: "Nabu::Adapters::Starling",
        license: Nabu::Adapters::Starling::MANIFEST.license, license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: db, source: source)
                                   .load_from(Nabu::Adapters::Starling.new,
                                              workdir: Nabu::TestSupport.fixtures("starling"))
      db.disconnect
      yield config
    end
  end

  # P19-1: the curated layer of the language card — the local-language
  # dossier shelf loaded into the catalog's derived records (the production
  # read path; what `nabu sync local-language` derives on a live box).
  def load_language_shelf(db)
    source = Nabu::Store::Source.create(
      slug: "local-language", name: "Language dossiers (local shelf)",
      adapter_class: "Nabu::Adapters::LocalLanguage", license_class: "open"
    )
    Nabu::Store::LanguageDossierLoader.new(db: db, source: source)
                                      .load_from(Nabu::Adapters::LocalLanguage.new,
                                                 workdir: Nabu::TestSupport.fixtures("local-language"))
  end

  # P18-5: the IE-CoR cognacy shelf loaded from the fixture CLDF bundle,
  # WITH a real ledger so the language-notes rider accretes (the loader's
  # programmatic write path, end to end).
  def with_iecor_shelf
    Dir.mktmpdir("nabu-cli-iecor") do |root|
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(root, "sources.yml"), config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      db = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(db)
      Nabu::Store.setup!(db)
      ledger = Nabu::Store::Ledger.open!(config.history_path)
      source = Nabu::Store::Source.create(
        slug: "iecor", name: "IE-CoR", adapter_class: "Nabu::Adapters::Iecor",
        license: "CC BY 4.0", license_class: "attribution"
      )
      Nabu::Store::DictionaryLoader.new(db: db, source: source, ledger: ledger,
                                        canonical_dir: config.canonical_dir)
                                   .load_from(Nabu::Adapters::Iecor.new,
                                              workdir: Nabu::TestSupport.fixtures("iecor"))
      db.disconnect
      ledger.disconnect
      yield config
    end
  end

  # One TestAdapter source "corpus" (two documents) with canonical data; the
  # caller stubs Config.load with the yielded config. +enabled+ seeds the row.
  def with_sync_env(enabled:)
    Dir.mktmpdir("nabu-cli-sync") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: #{enabled}\n  sync_policy: live\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end

  # A quickstart env (P18-2): one source per (slug => adapter class name),
  # each with its own canonical fixture files already on disk (distinct
  # filenames per slug — TestAdapter mints urns from filenames, and two
  # sources must never collide on a urn). The caller stubs Config.load.
  def with_quickstart_env(adapters)
    Dir.mktmpdir("nabu-cli-quickstart") do |root|
      sources = +""
      adapters.each do |slug, klass|
        dir = File.join(root, "canonical", slug)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "#{slug}-one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
        File.write(File.join(dir, "#{slug}-two.txt"), "Odyssey\nἄνδρα\n")
        sources << "#{slug}:\n  adapter: #{klass}\n  enabled: true\n  sync_policy: manual\n"
      end
      path = File.join(root, "sources.yml")
      File.write(path, sources)
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: path, config_path: "(test)"
      )
    end
  end

  # Pin the starter list to test slugs by swapping the class method (the
  # with_config / with_stubbed_shell house pattern), restoring after.
  def with_starter_sources(slugs)
    original = Nabu::CLI.method(:starter_sources)
    list = slugs.map { |slug| Nabu::CLI::StarterSource.new(slug: slug, size: "~1 MB", blurb: "test source") }
    Nabu::CLI.define_singleton_method(:starter_sources) { list }
    yield
  ensure
    Nabu::CLI.define_singleton_method(:starter_sources, original)
  end

  # Swap Nabu::Shell.run for +impl+ (a proc) so the health probe sees canned
  # ls-remote output/failures with no network, restoring the original after.
  def with_stubbed_shell(impl)
    original = Nabu::Shell.method(:run)
    Nabu::Shell.define_singleton_method(:run) { |*argv| impl.call(*argv) }
    yield
  ensure
    Nabu::Shell.define_singleton_method(:run, original)
  end

  # Minitest 6 dropped Minitest::Mock (and it is outside the dependency budget),
  # so pin Config.load to +config+ by swapping the singleton method, restoring
  # the original afterward.
  def with_config(config)
    original = Nabu::Config.method(:load)
    Nabu::Config.define_singleton_method(:load) { |*, **| config }
    yield
  ensure
    Nabu::Config.define_singleton_method(:load, original)
  end

  # Build a throwaway config with an empty (comments-only) registry and no
  # catalog db, and yield it.
  # An on-disk cognates corpus (P15-3): the real wiktionary-recon shelf, an
  # nt registry over grc/chu/ang witnesses whose sentences carry gold lemmas
  # in citation-bearing tokens, and the full index build (FTS + lemmas +
  # alignment refs + reflex_roots) — the production pipeline end to end.
  # MARK 1.1 meets grc ἔφᾰγον × chu богъ at PIE *bʰeh₂g-; MARK 2.1 meets
  # ang cāsere × chu цѣсар҄ь at gem-pro *kaisaraz (the loan shelf).
  def with_cognates_corpus
    Dir.mktmpdir("nabu-cli-cognates") do |root|
      registry_yaml = <<~YAML
        nt:
          title: "New Testament (test witnesses)"
          witnesses:
            - document: urn:nabu:test:grc-nt
            - document: urn:nabu:test:marianus
            - document: urn:nabu:test:oe-mark
            - document: urn:nabu:test:gothic
      YAML
      alignments = File.join(root, "alignments.yml")
      File.write(alignments, registry_yaml)
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, alignments_path: alignments, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_cognates_corpus(catalog)
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_cognates_corpus(catalog)
    recon = Nabu::Store::Source.create(
      slug: "wiktionary-recon", name: "Wiktionary reconstructions", license: "CC-BY-SA + GFDL",
      adapter_class: "Nabu::Adapters::WiktionaryRecon", license_class: "attribution"
    )
    Nabu::Store::DictionaryLoader.new(db: catalog, source: recon)
                                 .load_from(Nabu::Adapters::WiktionaryRecon.new,
                                            workdir: Nabu::TestSupport.fixtures("wiktionary-recon"))
    texts = catalog[:sources].insert(slug: "proiel", name: "PROIEL", adapter_class: "TestAdapter",
                                     license_class: "nc", enabled: true)
    [["grc-nt", "Greek NT", "grc", [["MARK 1.1", "ἔφᾰγον", "ἔφαγεν"]]],
     ["marianus", "Codex Marianus", "chu",
      [["MARK 1.1", "богъ", "ба"], ["MARK 2.1", "цѣсар҄ь", "цѣсар҄ь"],
       ["JOHN 13.18", "хлѣбъ", "хлѣбъ"]]], # the P17-3 loan-flag acceptance verse
     ["oe-mark", "OE Mark", "ang", [["MARK 2.1", "cāsere", "cāsere"]]],
     ["gothic", "Gothic NT", "got", [["JOHN 13.18", "hlaifs", "hlaifs"]]]].each do |tail, title, lang, rows|
      doc_id = catalog[:documents].insert(
        source_id: texts, urn: "urn:nabu:test:#{tail}", title: title, language: lang,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      rows.each_with_index do |(ref, lemma, form), seq|
        catalog[:passages].insert(
          document_id: doc_id, urn: "urn:nabu:test:#{tail}:#{seq + 1}", sequence: seq,
          language: lang, text: form, text_normalized: form, content_sha256: "x", revision: 1,
          withdrawn: false,
          annotations_json: JSON.generate(
            "citation" => ref,
            "tokens" => [{ "citation_part" => ref, "lemma" => lemma, "form" => form }]
          )
        )
      end
    end
  end

  def with_empty_registry_env
    Dir.mktmpdir("nabu-cli-empty") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# no sources registered\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end

  # Build a throwaway config whose config_dir is a REAL tmp dir (so the backup's
  # config/ section never rsyncs the project root) plus a tiny canonical tree,
  # and yield [config, target].
  def with_backup_env
    Dir.mktmpdir("nabu-cli-backup") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\n")
      cfg = File.join(root, "config")
      FileUtils.mkdir_p(cfg)
      File.write(File.join(cfg, "sources.yml"), "corpus:\n  adapter: TestAdapter\n")
      File.write(File.join(cfg, "nabu.yml"), "# nabu config\n")
      target = File.join(root, "backup-target")
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: File.join(cfg, "sources.yml"), config_path: File.join(cfg, "nabu.yml")
      )
      yield config, target
    end
  end

  # -- display policy rig (P27-0) ------------------------------------------

  # A built + indexed corpus of one hbo document (OSHB verses) and one eng
  # sibling, with the SHIPPED config/display.yml copied beside sources.yml
  # (Config's default display_path) and a two-witness alignment registry so
  # show/search/concord/align all run under real display policies.
  def with_hebrew_corpus
    Dir.mktmpdir("nabu-cli-display") do |root|
      registry_yaml = <<~YAML
        genesis:
          title: "Genesis"
          witnesses:
            - label: oshb
              extractor: cts-verse
              documents:
                GEN: urn:nabu:oshb:gen
            - label: web
              extractor: cts-verse
              documents:
                GEN: urn:nabu:eng-web:gen
      YAML
      alignments = File.join(root, "alignments.yml")
      File.write(alignments, registry_yaml)
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      FileUtils.cp(File.expand_path("../config/display.yml", __dir__), File.join(root, "display.yml"))
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, alignments_path: alignments, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_hebrew_corpus(catalog)
      index_aligned_corpus(config, catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_hebrew_corpus(catalog)
    source_id = catalog[:sources].insert(
      slug: "oshb", name: "OSHB", adapter_class: "TestAdapter", license_class: "attribution",
      enabled: true
    )
    [["urn:nabu:oshb:gen", "Genesis", "hbo", [["1.1", HBO_GEN_1_1]]],
     ["urn:nabu:eng-web:gen", "Genesis (WEB)", "eng",
      [["1.1", "In the beginning, God created the heavens and the earth."]]],
     ["urn:nabu:torot:zogr", "Zographensis", "chu", [["1", CHU_ZOGR]]]].each do |doc_urn, title, lang, passages|
      doc_id = catalog[:documents].insert(
        source_id: source_id, urn: doc_urn, title: title, language: lang,
        content_sha256: "x", revision: 1, withdrawn: false
      )
      passages.each_with_index do |(tail, text), sequence|
        catalog[:passages].insert(
          document_id: doc_id, urn: "#{doc_urn}:#{tail}", sequence: sequence, language: lang,
          text: text, text_normalized: Nabu::Normalize.search_form(text, language: lang),
          content_sha256: "x", revision: 1, withdrawn: false, annotations_json: "{}"
        )
      end
    end
  end

  # -- edition-level display rig (P27-1) -----------------------------------

  # A catalog carrying REAL edition-apparatus bytes under their registry
  # slugs: OSHB Ruth (parsed by the shipping adapter from the checked-in
  # fixture, so the 1:8 ketiv/qere annotations are the full real token
  # hashes) and the SBLGNT 3John sigla verse. The SHIPPED display.yml sits
  # beside sources.yml (Config's default display_path).
  def with_edition_corpus
    Dir.mktmpdir("nabu-cli-edition") do |root|
      sources = File.join(root, "sources.yml")
      File.write(sources, "# none\n")
      FileUtils.cp(File.expand_path("../config/display.yml", __dir__), File.join(root, "display.yml"))
      config = Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
      FileUtils.mkdir_p(config.db_dir)
      catalog = Nabu::Store.connect(config.catalog_path)
      Nabu::Store.migrate!(catalog)
      Nabu::Store.setup!(catalog)
      seed_edition_corpus(catalog)
      catalog.disconnect
      yield config
    end
  end

  def seed_edition_corpus(catalog)
    adapter = Nabu::Adapters::Oshb.new
    ref = adapter.discover(Nabu::TestSupport.fixtures("oshb")).find { |r| r.id == "urn:nabu:oshb:ruth" }
    ruth = adapter.parse(ref)
    seed_edition_document(catalog, slug: "oshb", urn: "urn:nabu:oshb:ruth", title: "Ruth",
                                   language: ruth.language,
                                   passages: ruth.passages.map do |p|
                                     [p.urn, p.language, p.text,
                                      Nabu::Store::ContentHash.canonical_json(p.annotations)]
                                   end)
    seed_edition_document(catalog, slug: "sblgnt", urn: "urn:nabu:sblgnt:3john", title: "ΙΩΑΝΝΟΥ Γ",
                                   language: "grc",
                                   passages: [["urn:nabu:sblgnt:3john:1.4", "grc", SBLGNT_3JOHN_1_4, "{}"]])
  end

  def seed_edition_document(catalog, slug:, urn:, title:, language:, passages:)
    source_id = catalog[:sources].insert(
      slug: slug, name: slug, adapter_class: "TestAdapter", license_class: "attribution", enabled: true
    )
    doc_id = catalog[:documents].insert(
      source_id: source_id, urn: urn, title: title, language: language,
      content_sha256: "x", revision: 1, withdrawn: false
    )
    passages.each_with_index do |(passage_urn, lang, text, annotations_json), sequence|
      catalog[:passages].insert(
        document_id: doc_id, urn: passage_urn, sequence: sequence, language: lang,
        text: text, text_normalized: Nabu::Normalize.search_form(text, language: lang),
        content_sha256: "x", revision: 1, withdrawn: false, annotations_json: annotations_json
      )
    end
  end

  # Build a throwaway config with one replayable TestAdapter source ("corpus",
  # two documents) and yield it; the caller stubs Config.load with it.
  def with_rebuild_env
    Dir.mktmpdir("nabu-cli-rebuild") do |root|
      corpus = File.join(root, "canonical", "corpus")
      FileUtils.mkdir_p(corpus)
      File.write(File.join(corpus, "one.txt"), "Iliad\nμῆνιν\nἄειδε\n")
      File.write(File.join(corpus, "two.txt"), "Odyssey\nἄνδρα\n")
      sources = File.join(root, "sources.yml")
      File.write(sources, "corpus:\n  adapter: TestAdapter\n  enabled: true\n")
      yield Nabu::Config.new(
        canonical_dir: File.join(root, "canonical"), db_dir: File.join(root, "db"),
        sources_path: sources, config_path: "(test)"
      )
    end
  end
end
