# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The reconstruction shelf source (P14-1, architecture §12; P17-3 part 2;
# P25-2 Celtic): ONE source, TEN dictionaries — kaikki.org's Proto-Slavic /
# Proto-Indo-European / Proto-Germanic plus the P17-3 Proto-Balto-Slavic /
# Proto-West Germanic / Proto-Italic / Proto-Indo-Iranian wiktextract
# extracts, and the P25-2 ATTESTED Celtic extracts (Old Irish sga, Middle
# Irish mga, Middle Welsh wlm — the wiktionary-cu attested precedent),
# through the existing wiktionary-jsonl
# family with reflexes: on. Dictionary-shaped (no passage conformance
# suite); mirrors the WiktionaryCuTest checks for the dictionary shape and
# adds the multi-file FileFetch choreography (per-extract subdirs, shared
# top-level attic — the UD precedent) plus the crosswalk loader contract.
class WiktionaryReconTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wiktionary-recon")

  URLS = {
    "wiktionary-sla-pro" => "https://kaikki.org/dictionary/Proto-Slavic/" \
                            "kaikki.org-dictionary-ProtoSlavic.jsonl",
    "wiktionary-ine-pro" => "https://kaikki.org/dictionary/Proto-Indo-European/" \
                            "kaikki.org-dictionary-ProtoIndoEuropean.jsonl",
    "wiktionary-gem-pro" => "https://kaikki.org/dictionary/Proto-Germanic/" \
                            "kaikki.org-dictionary-ProtoGermanic.jsonl",
    "wiktionary-ine-bsl-pro" => "https://kaikki.org/dictionary/Proto-Balto-Slavic/" \
                                "kaikki.org-dictionary-ProtoBaltoSlavic.jsonl",
    "wiktionary-gmw-pro" => "https://kaikki.org/dictionary/Proto-West%20Germanic/" \
                            "kaikki.org-dictionary-ProtoWestGermanic.jsonl",
    "wiktionary-itc-pro" => "https://kaikki.org/dictionary/Proto-Italic/" \
                            "kaikki.org-dictionary-ProtoItalic.jsonl",
    "wiktionary-iir-pro" => "https://kaikki.org/dictionary/Proto-Indo-Iranian/" \
                            "kaikki.org-dictionary-ProtoIndoIranian.jsonl",
    "wiktionary-sga" => "https://kaikki.org/dictionary/Old%20Irish/" \
                        "kaikki.org-dictionary-OldIrish.jsonl",
    "wiktionary-mga" => "https://kaikki.org/dictionary/Middle%20Irish/" \
                        "kaikki.org-dictionary-MiddleIrish.jsonl",
    "wiktionary-wlm" => "https://kaikki.org/dictionary/Middle%20Welsh/" \
                        "kaikki.org-dictionary-MiddleWelsh.jsonl",
    "wiktionary-xum" => "https://kaikki.org/dictionary/Umbrian/" \
                        "kaikki.org-dictionary-Umbrian.jsonl"
  }.freeze

  def adapter = Nabu::Adapters::WiktionaryRecon.new

  # --- manifest + content kind --------------------------------------------------

  def test_manifest_identifies_the_wiktionary_recon_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wiktionary-recon", manifest.id
    assert_match(/CC-BY-SA and GFDL/, manifest.license) # the kaikki statement, verbatim
    assert_equal "attribution", manifest.license_class
    assert_equal "wiktionary-jsonl", manifest.parser_family
  end

  def test_content_kind_is_dictionary
    assert_equal :dictionary, Nabu::Adapters::WiktionaryRecon.content_kind
  end

  # --- discover → parse round-trip ------------------------------------------------

  def test_discover_yields_one_ref_per_extract_in_registry_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wiktionary-sla-pro:kaikki.org-dictionary-ProtoSlavic.jsonl",
                  "wiktionary-ine-pro:kaikki.org-dictionary-ProtoIndoEuropean.jsonl",
                  "wiktionary-gem-pro:kaikki.org-dictionary-ProtoGermanic.jsonl",
                  "wiktionary-ine-bsl-pro:kaikki.org-dictionary-ProtoBaltoSlavic.jsonl",
                  "wiktionary-gmw-pro:kaikki.org-dictionary-ProtoWestGermanic.jsonl",
                  "wiktionary-itc-pro:kaikki.org-dictionary-ProtoItalic.jsonl",
                  "wiktionary-iir-pro:kaikki.org-dictionary-ProtoIndoIranian.jsonl",
                  "wiktionary-sga:kaikki.org-dictionary-OldIrish.jsonl",
                  "wiktionary-mga:kaikki.org-dictionary-MiddleIrish.jsonl",
                  "wiktionary-wlm:kaikki.org-dictionary-MiddleWelsh.jsonl",
                  "wiktionary-xum:kaikki.org-dictionary-Umbrian.jsonl"],
                 refs.map(&:id)
    assert_equal %w[wiktionary-recon], refs.map(&:source_id).uniq
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def test_parse_yields_the_eleven_dictionaries
    documents = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    assert_equal %w[wiktionary-sla-pro wiktionary-ine-pro wiktionary-gem-pro
                    wiktionary-ine-bsl-pro wiktionary-gmw-pro wiktionary-itc-pro
                    wiktionary-iir-pro wiktionary-sga wiktionary-mga wiktionary-wlm
                    wiktionary-xum],
                 documents.map(&:slug)
    assert_equal %w[sla-pro ine-pro gem-pro ine-bsl-pro gmw-pro itc-pro iir-pro sga mga wlm xum],
                 documents.map(&:language)
    assert_equal [77, 63, 75, 3, 3, 2, 3, 3, 3, 3, 3], documents.map(&:size)
  end

  def test_entries_carry_reflexes_the_crosswalk_edges
    slavic = adapter.parse(adapter.discover(FIXTURES).first)
    bog = slavic.entries.find { |e| e.entry_id == "bogъ:noun:2" } || flunk("bogъ:noun:2 missing")
    refute_empty bog.reflexes
    assert(bog.reflexes.any? { |r| r.language == "chu" && r.word_folded == "bogъ" }) # P27-2 skeleton
  end

  # P17-3: the borrowed flag rides the crosswalk edge. In *hlaibaz's real
  # tree the marker sits on the PROTO-TO-PROTO edge (raw_tags ["borrowed"]
  # on the sla-pro *xlěbъ node) while the got/ang nodes parse false — the
  # design-load-bearing shape the closure ORs along the path.
  def test_reflexes_carry_the_borrowed_flag_per_edge
    gem = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
                                    .find { |doc| doc.slug == "wiktionary-gem-pro" }
    hlaibaz = gem.entries.find { |e| e.entry_id == "hlaibaz:noun" } || flunk("hlaibaz:noun missing")
    xleb = hlaibaz.reflexes.find { |r| r.language == "sla-pro" } || flunk("sla-pro *xlěbъ edge missing")
    assert xleb.borrowed, "the gem-pro → sla-pro *xlěbъ edge is upstream-flagged borrowed"
    got = hlaibaz.reflexes.find { |r| r.language == "got" } || flunk("got hlaifs edge missing")
    refute got.borrowed, "the Gothic reflex is inherited — parsed false, not NULL"
  end

  # P25-2: the ATTESTED Celtic extracts mint crosswalk edges exactly like
  # the proto shelves (the wiktionary-cu attested precedent). Old Irish rí
  # "king" carries the DIL-derived Proto-Celtic/PIE etymology verbatim in
  # its body AND a descendants tree whose Middle Irish node is the mga
  # shelf's own rí headword — the sga→mga edge the shelf-visited ascent
  # rides (Middle Irish rí walks up to the Old Irish entry).
  def test_sga_entries_carry_celtic_etymologies_and_mint_crosswalk_edges
    documents = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    sga = documents.find { |doc| doc.slug == "wiktionary-sga" }
    ri = sga.entries.find { |e| e.entry_id == "rí:noun" } || flunk("rí:noun missing")
    assert_match(/Proto-Celtic \*rīxs/, ri.body) # the cel-pro chain, kept verbatim
    assert_match(/Proto-Indo-European \*h₃rḗǵs/, ri.body)
    refute_empty ri.reflexes
    assert(ri.reflexes.any? { |r| r.language == "mga" && r.word_folded == "ri" },
           "rí must mint the Middle Irish descendant edge")
    assert_equal "ri", ri.headword_folded, "sga rí must be ASCII-typable (í → i)"

    mga = documents.find { |doc| doc.slug == "wiktionary-mga" }
    assert(mga.entries.any? { |e| e.entry_id == "rí:noun" && e.headword_folded == "ri" },
           "the mga shelf holds rí — the sga reflex edge's ascent target")
  end

  # P25-2: the crosswalk LIGHTS end to end — after a load, the sga rí
  # entry's stored reflex edges come back through ReflexViews (the read
  # side Define/Etym share), and the loan flag parses on the mga clann →
  # en clan edge (the Gaelic loan into English).
  def test_reflex_views_serve_the_sga_entry_edges_after_a_load
    db, loader = loader_setup
    loader.load_from(adapter, workdir: FIXTURES)
    sga_dict = db[:dictionaries].where(slug: "wiktionary-sga").get(:id)
    ri = db[:dictionary_entries].where(dictionary_id: sga_dict, entry_id: "rí:noun").first
    refute_nil ri, "the loaded sga shelf must hold rí:noun"
    assert_equal "urn:nabu:dict:wiktionary-sga:rí:noun", ri[:urn]

    views = Nabu::Query::ReflexViews.new(catalog: db).for_entry(ri[:id])
    refute_empty views, "the sga entry's crosswalk edges must serve through ReflexViews"
    mga_view = views.find { |v| v.language == "mga" } || flunk("mga rí edge missing")
    assert_equal "rí", mga_view.word
    assert_nil mga_view.attested_count, "no fulltext handle — honest nil, never a zero claim"

    mga_dict = db[:dictionaries].where(slug: "wiktionary-mga").get(:id)
    clann = db[:dictionary_entries].where(dictionary_id: mga_dict, entry_id: "clann:noun").first
    refute_nil clann, "the loaded mga shelf must hold clann:noun"
    clan = Nabu::Query::ReflexViews.new(catalog: db).for_entry(clann[:id])
                                   .find { |v| v.lang_code == "en" && v.word == "clan" }
    refute_nil clan, "clann must mint the English clan edge"
    assert clan.borrowed, "en clan is upstream-flagged borrowed"
  end

  # P17-3: the new fold keys. The iir-pro headword *adᶻdʰáH carries the ᶻ
  # modifier letter (→ z) and ʰ (→ h); the ine-bsl-pro headword *wárˀnāˀ
  # carries the glottal-stop letter ˀ (→ dropped, ×310 upstream). Both must
  # be reachable by an ASCII typist (conventions §9).
  def test_new_shelf_headwords_fold_for_ascii_queries
    documents = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    iir = documents.find { |doc| doc.slug == "wiktionary-iir-pro" }
    assert(iir.entries.any? { |e| e.headword_folded == "adzdhah" },
           "*adᶻdʰáH must fold ᶻ→z ʰ→h (got #{iir.entries.map(&:headword_folded).inspect})")
    pbs = documents.find { |doc| doc.slug == "wiktionary-ine-bsl-pro" }
    assert(pbs.entries.any? { |e| e.headword_folded == "warna" },
           "*wárˀnāˀ must drop ˀ entirely (got #{pbs.entries.map(&:headword_folded).inspect})")
  end

  def test_entry_ids_are_unique_per_dictionary_and_stable_across_independent_passes
    snapshot = lambda do
      adapter.discover(FIXTURES).to_h { |ref| [ref.id, adapter.parse(ref).map(&:entry_id)] }
    end
    first = snapshot.call
    # unique WITHIN each dictionary (the upsert key is (dictionary, entry_id);
    # nu:adv legitimately exists in both PIE and Proto-Germanic)
    first.each_value { |ids| assert_equal ids.uniq, ids }
    assert_equal first, snapshot.call
  end

  # P29-1 rider: the ATTESTED Umbrian extract (the only kaikki-served
  # Italic corpus language; CEIPoM's xum lane). Old Italic headwords ride
  # in real U+10300-block codepoints; the romanization stubs (30 upstream)
  # parse as plain entries; etymology_text (373/500 upstream) is kept
  # verbatim in bodies.
  def test_xum_entries_carry_old_italic_headwords_and_etymologies
    documents = adapter.discover(FIXTURES).map { |ref| adapter.parse(ref) }
    xum = documents.find { |doc| doc.slug == "wiktionary-xum" }
    assert_equal "xum", xum.language
    arepes = xum.entries.find { |e| e.headword == "\u{10300}\u{1031B}\u{10304}\u{10310}\u{10304}\u{10314}" }
    refute_nil arepes, "the Old Italic-script headword record must parse"
    assert_match(/Proto-Italic/, arepes.body, "the etymology chain rides verbatim")
    assert(xum.entries.any? { |e| e.headword == "tre" },
           "romanization stubs parse as plain entries")
  end

  # --- fetch (WebMock only, no network) ----------------------------------------

  def stub_all(status: 200)
    URLS.each_value do |url|
      if status == 200
        stub_request(:get, url).to_return(
          status: 200, body: %({"word":"x","pos":"noun","lang_code":"t","senses":[]}\n),
          headers: { "Last-Modified" => "Thu, 09 Jul 2026 00:00:00 GMT" }
        )
      else
        stub_request(:get, url).to_return(status: status)
      end
    end
  end

  def test_fetch_downloads_each_extract_into_its_own_subdir
    stub_all
    Dir.mktmpdir do |workdir|
      report = adapter.fetch(workdir)
      assert_instance_of Nabu::FetchReport, report
      assert_match(/\A\h{64}\z/, report.sha)
      assert_match(/sla-pro/, report.notes)
      assert_match(/iir-pro/, report.notes)
      assert_match(/wlm/, report.notes)
      assert_equal 11, adapter.discover(workdir).count, "all eleven extracts discoverable in place"
      %w[proto-slavic proto-indo-european proto-germanic proto-balto-slavic
         proto-west-germanic proto-italic proto-indo-iranian
         old-irish middle-irish middle-welsh umbrian].each do |subdir|
        assert File.file?(File.join(workdir, subdir, Nabu::FileFetch::STATE_FILE)),
               "per-extract FileFetch state under #{subdir}/"
      end
    end
  end

  def test_fetch_wraps_http_failure_in_fetch_error
    # the upstream files are flagged DEPRECATED — a future 404 must fail clean
    stub_all(status: 404)
    Dir.mktmpdir do |workdir|
      assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
    end
  end

  # --- remote-health probe shape -------------------------------------------------

  def test_probe_targets_head_each_jsonl_with_per_extract_state
    assert_equal :http_zip, Nabu::Adapters::WiktionaryRecon.remote_probe_strategy
    targets = Nabu::Adapters::WiktionaryRecon.http_probe_targets
    assert_equal 11, targets.size
    assert_equal URLS.values.sort, targets.map(&:zip_url).sort
    assert_equal %w[middle-irish middle-welsh old-irish
                    proto-balto-slavic proto-germanic proto-indo-european proto-indo-iranian
                    proto-italic proto-slavic proto-west-germanic umbrian],
                 targets.map(&:state_subdir).sort
    targets.each do |target|
      assert_nil target.metadata_url
      assert_equal Nabu::FileFetch::STATE_FILE, target.state_file
    end
  end

  # --- DictionaryLoader contract (idempotency / revision / urn / reflexes) --------

  def loader_setup
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "wiktionary-recon", name: "Wiktionary reconstructions (kaikki.org)",
      adapter_class: "Nabu::Adapters::WiktionaryRecon",
      license: "CC-BY-SA + GFDL", license_class: "attribution",
      upstream_url: "https://kaikki.org/dictionary/", enabled: false
    )
    [db, Nabu::Store::DictionaryLoader.new(db: db, source: source)]
  end

  def test_loading_the_fixtures_twice_is_idempotent_with_stable_urns_and_reflexes
    db, loader = loader_setup
    first = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 238, first.added
    assert_equal 0, first.errored

    reflex_count = db[:dictionary_reflexes].count
    assert_operator reflex_count, :>, 1000, "the fixtures are descendants-rich"

    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added
    assert_equal 238, second.skipped
    assert_equal [1], db[:dictionary_entries].select_map(:revision).uniq
    assert_equal reflex_count, db[:dictionary_reflexes].count

    bog = db[:dictionary_entries].where(entry_id: "bogъ:noun:2").first
    assert_equal "urn:nabu:dict:wiktionary-sla-pro:bogъ:noun:2", bog[:urn]
    assert_equal "bogъ", bog[:headword_folded]
  end

  def test_registry_row_exists_disabled_with_manual_sync_policy
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wiktionary-recon"]
    refute_nil entry, "config/sources.yml must register wiktionary-recon"
    assert_equal Nabu::Adapters::WiktionaryRecon, entry.adapter_class
    assert entry.enabled, "live (owner sign-off 2026-07-12 after first sync + etym eyeball)"
    assert_equal "manual", entry.sync_policy
    assert_equal Nabu::Adapters::WiktionaryRecon.manifest, entry.manifest
  end
end
