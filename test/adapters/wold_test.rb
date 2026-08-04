# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# The WOLD adapter (P46-6): the World Loanword Database (Haspelmath &
# Tadmor 2009, lexibank/wold v4.2) as the etym desk's structured
# loanword-flow layer — one dictionary shelf per WOLD vocabulary (the
# starling many-shelves-one-source shape), one entry per lexeme with its
# curated borrowed status, and each borrowing event's donor word minted as
# a borrowed reflex edge (the donor side is where the ancient languages
# live: Latin, Old Norse, Sanskrit, Classical Arabic…). Dictionary-shaped,
# so like Iecor/Starling it mirrors the passage conformance suite by hand
# (manifest validity, discover→parse round-trip, id uniqueness/stability,
# NFC, license class) and adds the loanword-donor round-trip pins.
class WoldTest < Minitest::Test
  include StoreTestDB

  FIXTURES = Nabu::TestSupport.fixtures("wold")

  def adapter(pin: nil)
    pin ? Nabu::Adapters::Wold.new(pin: pin) : Nabu::Adapters::Wold.new
  end

  # --- manifest + capabilities -----------------------------------------------------

  def test_manifest_identifies_the_wold_source
    manifest = adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_equal "wold", manifest.id
    assert_match(/CC[- ]BY[- ]4\.0/i, manifest.license)
    assert_match(/Haspelmath/, manifest.license, "the citation rides the license lane")
    assert_equal "attribution", manifest.license_class
    assert_equal "cldf-csv", manifest.parser_family
    assert_match(/zenodo/, manifest.upstream_url)
  end

  def test_content_kind_is_dictionary_and_the_source_promises_reflexes
    assert_equal :dictionary, Nabu::Adapters::Wold.content_kind
    assert Nabu::Adapters::Wold.reflex_bearing?, "donor words mint borrowed reflex edges"
  end

  def test_probe_is_http_zip_against_the_zenodo_artifact
    assert_equal :http_zip, Nabu::Adapters::Wold.remote_probe_strategy
    targets = Nabu::Adapters::Wold.http_probe_targets
    assert_equal [Nabu::Adapters::Wold::ZENODO_ZIP_URL], targets.map(&:zip_url)
  end

  # --- discover → parse ------------------------------------------------------------

  def test_discover_yields_one_ref_per_vocabulary_in_upstream_order
    refs = adapter.discover(FIXTURES).to_a
    assert_equal ["wold-swahili:cldf", "wold-oldhighgerman:cldf", "wold-english:cldf"],
                 refs.map(&:id), "languages.csv file order"
    assert_equal %w[wold] * 3, refs.map(&:source_id)
    vocabularies = refs.map { |r| r.metadata.fetch("vocabulary") }
    assert_equal %w[Swahili OldHighGerman English], vocabularies
  end

  def test_discover_yields_nothing_before_a_first_fetch
    Dir.mktmpdir { |empty| assert_empty adapter.discover(empty).to_a }
  end

  def parse(vocabulary)
    ref = adapter.discover(FIXTURES).find { |r| r.metadata.fetch("vocabulary") == vocabulary }
    adapter.parse(ref)
  end

  def test_parse_english_yields_the_vocabulary_shelf_with_the_contributor_title
    document = parse("English")
    assert_kind_of Nabu::DictionaryDocument, document
    assert_equal "wold-english", document.slug
    assert_equal "eng", document.language, "ISO 639-3 pass-through (the eng-web tag)"
    assert_match(/English vocabulary/, document.title)
    assert_match(/Anthony Grant/, document.title, "the per-vocabulary contributor credit")
    assert_equal %w[English-1-1-1 English-1-51-1 English-5-92-1 English-23-395-1],
                 document.map(&:entry_id), "entry id = the upstream form ID, verbatim"
  end

  def test_vocabularies_without_iso_codes_use_the_censused_tag_map
    assert_equal "goh", parse("OldHighGerman").language,
                 "WOLD leaves OldHighGerman's ISO column blank — the censused map fills goh"
  end

  # --- the loanword-donor round-trip (the packet pin) ------------------------------

  def test_a_clearly_borrowed_word_carries_its_donor_as_a_borrowed_reflex
    wine = parse("English").entries.find { |e| e.entry_id == "English-5-92-1" }
    assert_equal "wine", wine.headword
    assert_equal "the wine", wine.gloss, "gloss = the WOLD meaning label"
    assert_includes wine.body, "borrowed status: 1. clearly borrowed"
    assert_includes wine.body, "loan ← Latin vīnum ‘wine’"
    assert_includes wine.body, "loan ← Greek (w)oînos ‘wine’ (earlier)",
                    "non-immediate events carry their Source_relation"
    donors = wine.reflexes
    assert_equal [%w[lat lat], %w[ell ell]],
                 donors.map { |r| [r.lang_code, r.language] },
                 "P57-5: lang_code is now the RESOLVED catalog tag, not the upstream glottocode " \
                 "verbatim; Latin resolves by NAME (the donor map), bare 'Greek' (mode1248 = Modern " \
                 "Greek) resolves through the new mechanical Glottolog join since 'Greek' alone " \
                 "isn't a DONOR_MAP key (only 'Classical Greek' is — a real, distinct donor)"
    vinum = donors.first
    assert_equal "vīnum", vinum.word
    assert vinum.borrowed, "a donor edge is a borrowing edge"
    assert_equal "Latin", vinum.lang_name
    assert_equal Nabu::Normalize.search_form("vinum", language: "lat"), vinum.word_folded,
                 "the donor fold lands on the Latin gold-side §9 key — the etym join"
  end

  # P57-5, the noon1243 hand-check: WOLD's OWN upstream borrowings.csv rows
  # name this donor "Old Norse" throughout (verified by hand against
  # canonical/wold/cldf/borrowings.csv — every noon1243 row's Source_word is
  # a genuine Old Norse form: ský "cloud", lágr "low", hvirfla "to whirl",
  # húsbondi "husband", systir "sister") even though Glottolog's noon1243 is
  # actually Noone, a Cangin language of Senegal (real Old Norse is
  # oldn1244 — pinned in test/cldf_spine_test.rb). So upstream's NAME is
  # right and its GLOTTOCODE is wrong — the adapter must keep trusting the
  # name over the glottocode, and GLOTTOCODE_LANGUAGES deliberately has NO
  # noon1243 entry (a glottocode fallback must never be allowed to override
  # a trusted name with the wrong language).
  def test_old_norse_donors_map_by_name_despite_the_upstream_glottocode
    sky = parse("English").entries.find { |e| e.entry_id == "English-1-51-1" }
    donor = sky.reflexes.first
    assert_equal "non", donor.lang_code,
                 "P57-5: lang_code is the RESOLVED tag; the NAME 'Old Norse' decides it, never the " \
                 "upstream glottocode"
    assert_equal "non", donor.language, "the NAME 'Old Norse' decides the catalog tag"
    assert_equal "ský", donor.word
    assert_equal "Old Norse", donor.lang_name, "the original upstream name still rides lang_name"
    refute_includes Nabu::Adapters::Wold::GLOTTOCODE_LANGUAGES.keys, "noon1243",
                    "the fallback table must never get a chance to mis-resolve this one"
  end

  def test_a_native_word_still_mints_an_entry_with_its_status
    world = parse("English").entries.find { |e| e.entry_id == "English-1-1-1" }
    assert_equal "world", world.headword
    assert_includes world.body, "borrowed status: 5. no evidence for borrowing"
    assert_includes world.body, "age: Proto-Germanic"
    assert_empty world.reflexes
  end

  def test_concept_line_carries_the_concepticon_id_for_the_spine
    wine = parse("English").entries.find { |e| e.entry_id == "English-5-92-1" }
    assert_includes wine.body, "concept: the wine (Concepticon 1524 WINE)",
                    "the id the cldf-spine resolver resolves (test/cldf_spine_test.rb)"
  end

  def test_a_comma_multiform_donor_with_a_non_word_part_stays_unsplit
    helfant = parse("OldHighGerman").entries.find { |e| e.entry_id == "OldHighGerman-3-77-1" }
    words = helfant.reflexes.map(&:word)
    assert_includes words, "elephantus", "the immediate Latin donor"
    assert_includes words, "elephas, -ntos",
                    "Greek ‘elephas, -ntos’ keeps its inflection tail — splitting would mint ‘-ntos’"
  end

  def test_a_weak_evidence_word_keeps_both_the_status_and_the_event
    ulimwengu = parse("Swahili").entries.find { |e| e.entry_id == "Swahili-1-1-2" }
    assert_includes ulimwengu.body, "borrowed status: 4. very little evidence for borrowing"
    assert_includes ulimwengu.body, "loan ← Arabic lˁmān + ˁālmyān",
                    "the curated event rides even where the status is doubtful — both are upstream truth"
    assert_equal ["lˁmān + ˁālmyān"], ulimwengu.reflexes.map(&:word), "unsplittable — one verbatim edge"
    assert_equal "ara", ulimwengu.reflexes.first.language
  end

  # --- P57-5: the glottocode→ISO fallback table -------------------------------------

  # A representative slice of the 94-entry GLOTTOCODE_LANGUAGES table (the
  # full 96-code report census minus noon1243, deliberately excluded above,
  # and nepa1252, resolved by NAME instead — see DONOR_MAP): every value
  # here was read directly off the vendored Glottolog CLDF dump
  # (canonical/cldf-spine/glottolog/languages.csv, the same file
  # Nabu::CldfSpine reads at query time — ISO639P3code, or for dialect-level
  # rows with no ISO of their own, Closest_ISO369P3code) — a mechanical
  # join, never a guess, per the P57-5 packet spec.
  def test_glottocode_languages_table_resolves_the_report_census
    table = Nabu::Adapters::Wold::GLOTTOCODE_LANGUAGES
    # the report's own "obvious high-volume identifications"
    assert_equal "spa", table.fetch("stan1288")
    assert_equal "fra", table.fetch("stan1290")
    assert_equal "eng", table.fetch("stan1293")
    assert_equal "deu", table.fetch("stan1295")
    assert_equal "zsm", table.fetch("stan1306")
    assert_equal "cmn", table.fetch("mand1415")
    assert_equal "por", table.fetch("port1283")
    assert_equal "nld", table.fetch("dutc1256")
    assert_equal "hun", table.fetch("hung1274")
    assert_equal "ita", table.fetch("ital1282")
    assert_equal "xgn", table.fetch("mong1329"), "Mongolic — the ISO 639-5 collective"
    assert_equal "sit", table.fetch("sino1245"), "Sino-Tibetan — the ISO 639-5 collective"
    # dialect-level Glottolog rows resolve via Closest_ISO369P3code
    assert_equal "lat", table.fetch("late1252"), "Late Latin, a dialect node — closest ISO is lat"
    assert_equal "hrv", table.fetch("croa1245")
    assert_equal "srp", table.fetch("serb1264")
    assert_equal "xno", table.fetch("angl1258")
    # family-level nodes with a confident ISO 639-5 collective (report examples)
    assert_equal "ine", table.fetch("indo1319")
    assert_equal "bnt", table.fetch("bant1294")
    assert_equal "sla", table.fetch("slav1255")
    assert_equal "gem", table.fetch("germ1287")
    assert_equal "trk", table.fetch("turk1311")
    assert_equal "gmq", table.fetch("nort3160")
    # family-level nodes with NO confident collective — honestly `und`,
    # never guessed (upstream's own donor label noted per code)
    %w[finn1317 mala1545 yuca1252 gbee1241 high1289 east2832].each do |code|
      assert_equal "und", table.fetch(code), "#{code}: no ISO 639-5 collective I can confidently attach"
    end
    refute_includes table.keys, "noon1243", "the hand-check exclusion — never a fallback candidate"
    refute_includes table.keys, "nepa1252", "Nepali resolves by NAME (not in this Glottolog dump at all)"
  end

  def test_nepali_and_arabic_moroccan_resolve_by_name
    assert_equal "nep", Nabu::Adapters::Wold::DONOR_MAP.fetch("Nepali"),
                 "nepa1252 isn't in the vendored Glottolog dump at all — Nepali is unambiguous enough " \
                 "to resolve by name instead"
  end

  # A glottocode this packet's census could NOT confidently identify (not
  # among the 96) still resolves honestly to `und`, not nil — every donor
  # edge now names a real (if undetermined) catalog language, P57-5.
  def test_an_unknown_glottocode_falls_back_to_und_not_nil
    adapter_instance = adapter
    reflexes = adapter_instance.send(:donor_reflexes, {
                                       "Source_word" => "xyzzy", "Source_languoid" => "Plonkish",
                                       "Source_languoid_glottocode" => "zzzz9999"
                                     })
    assert_equal 1, reflexes.size
    assert_equal "und", reflexes.first.lang_code
    assert_equal "und", reflexes.first.language
    assert_equal "Plonkish", reflexes.first.lang_name, "the unidentifiable name still rides lang_name"
  end

  # --- P57-5: WOLD's own verbal donor labels (group 5) -------------------------------

  # `Unidentified` (WOLD's literal "no donor word" placeholder — the exact
  # upstream row shape, verbatim, from canonical/wold/cldf/borrowings.csv
  # ID 1614: Source_languoid "Unidentified", Source_languoid_glottocode
  # blank) mints `und`, not the literal string "Unidentified" as a code.
  def test_unidentified_donor_label_maps_to_und
    reflexes = adapter.send(:donor_reflexes, {
                              "Source_word" => "maamay", "Source_languoid" => "Unidentified",
                              "Source_languoid_glottocode" => ""
                            })
    assert_equal 1, reflexes.size
    assert_equal "und", reflexes.first.lang_code
    assert_equal "und", reflexes.first.language
    assert_equal "Unidentified", reflexes.first.lang_name
  end

  # `Proto-Altaic` (wold-mandarinchinese; canonical/wold/cldf/borrowings.csv
  # ID 20121, verbatim) is a StarLing-style reconstructed-donor label with
  # no ISO code and a controversial construct (the Altaic hypothesis) —
  # `und`, with the label preserved in lang_name rather than a dossier.
  def test_proto_altaic_donor_label_maps_to_und_with_the_label_preserved
    reflexes = adapter.send(:donor_reflexes, {
                              "Source_word" => "*acV", "Source_languoid" => "Proto-Altaic",
                              "Source_languoid_glottocode" => ""
                            })
    assert_equal 1, reflexes.size
    assert_equal "und", reflexes.first.lang_code
    assert_equal "und", reflexes.first.language
    assert_equal "Proto-Altaic", reflexes.first.lang_name
  end

  def test_entry_ids_are_stable_across_independent_passes_and_nfc
    snapshot = -> { parse("English").map(&:entry_id) }
    first = snapshot.call
    assert_equal first.uniq, first
    assert_equal first, snapshot.call
    parse("English").each do |entry|
      assert_equal entry.headword.unicode_normalize(:nfc), entry.headword
      assert_equal entry.body.unicode_normalize(:nfc), entry.body
    end
  end

  # --- loader round-trip -----------------------------------------------------------

  def test_loads_through_the_dictionary_loader_idempotently
    db = store_test_db
    source = Nabu::Store::Source.create(
      slug: "wold", name: "WOLD", adapter_class: "Nabu::Adapters::Wold",
      license: "CC BY 4.0", license_class: "attribution",
      upstream_url: "https://zenodo.org", enabled: false
    )
    loader = Nabu::Store::DictionaryLoader.new(db: db, source: source)
    report = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 9, report.added
    assert_equal 0, report.errored
    wine = db[:dictionary_entries].where(entry_id: "English-5-92-1").first
    assert_equal "urn:nabu:dict:wold-english:English-5-92-1", wine[:urn]
    reflexes = db[:dictionary_reflexes].where(dictionary_entry_id: wine[:id]).all
    assert_equal 2, reflexes.size
    assert(reflexes.all? { |r| r[:borrowed] }, "every donor edge is borrowed=true")
    second = loader.load_from(adapter, workdir: FIXTURES)
    assert_equal 0, second.added + second.updated + second.withdrawn
    assert_equal 9, second.skipped
  end

  # --- fetch (WebMock only, no network) --------------------------------------------

  def zip_body
    @zip_body ||= Dir.mktmpdir do |dir|
      tree = File.join(dir, "lexibank-wold-test", "cldf")
      FileUtils.mkdir_p(tree)
      Dir.glob(File.join(FIXTURES, "cldf", "*.csv")).each { |csv| FileUtils.cp(csv, tree) }
      zip = File.join(dir, "bundle.zip")
      Dir.chdir(dir) { Nabu::Shell.run("zip", "-q", "-r", zip, "lexibank-wold-test") }
      File.binread(zip)
    end
  end

  def stub_zenodo(body)
    stub_request(:get, Nabu::Adapters::Wold::ZENODO_ZIP_URL)
      .to_return(status: 200, body: body,
                 headers: { "Last-Modified" => "Mon, 09 Feb 2026 00:00:00 GMT" })
  end

  def test_fetch_pins_the_release_sha_and_unpacks_the_bundle
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      report = adapter(pin: Digest::SHA256.hexdigest(body)).fetch(workdir)
      assert_equal Digest::SHA256.hexdigest(body), report.sha
      assert_equal 3, adapter.discover(workdir).to_a.size
    end
  end

  def test_fetch_refuses_a_body_that_misses_the_release_pin
    body = zip_body
    stub_zenodo(body)
    Dir.mktmpdir do |workdir|
      error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
      assert_match(/sha256/, error.message)
      refute File.exist?(File.join(workdir, "cldf")), "a refused fetch must leave the tree untouched"
    end
  end

  # --- registry --------------------------------------------------------------------

  def test_registry_row_is_unwired_manual_on_the_etym_axis
    registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
    entry = registry["wold"]
    refute_nil entry, "config/sources.yml must register wold"
    assert_equal Nabu::Adapters::Wold, entry.adapter_class
    assert entry.wired, "flipped 2026-07-26 (owner ruling \"flip all wired\"; first sync verified)"
    assert_equal "manual", entry.sync_policy
    assert_includes entry.axes, "etym"
  end
end
