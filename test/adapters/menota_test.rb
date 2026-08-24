# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::Menota (P82-1, queue Q42 / grant №77-1): the Medieval
# Nordic Text Archive — ~100 manuscripts in Menota-TEI served through the
# Corpuscle REST API behind clarino.uib.no/menota/catalogue/menota.
#
# THE PARSER-FAMILY VERDICT (from the real bytes, census 2026-08-23): a NEW
# `menota-tei` family. No existing family reads the multi-level word markup
# — `<w lemma me:msa><choice><me:facs/><me:dipl/><me:norm/></choice></w>`
# with MUFI entities from the external menota-entities.txt table (DOCTYPE
# entity set; many map into the Private Use Area) — and the archive splits
# into two shapes: 86/91 documents carry the diplomatic level, 5 are
# facs-only (`<w><me:facs>…</me:facs></w>`, no choice, no lemma).
#
# THE STORED TEXT (the ReF/ReM diplomatic precedent, adjusted to reality):
# per token, the DIPLOMATIC reading when the file carries one, else
# facsimile, else normalized — so dipl-bearing documents read diplomatically
# and the 5 facs-only documents read at their only attested level. All
# levels ride annotations["tokens"] verbatim, nothing is lost. Passage =
# one manuscript LINE (the corpus's own layout grain), cited
# <page><column>.<line> — urn:nabu:menota:am-1056-ix-4to:1rB.1.
#
# LICENSE: CC BY-SA 4.0 on the catalogue license column (the quotable
# record, №77-1) AND in every sampled teiHeader availability/licence →
# attribution; the per-text gate maps each file's own licence statement and
# maps an UNRECOGNIZED explicit statement to restricted, never silently to
# the source class.
class MenotaTest < Minitest::Test
  include AdapterConformance
  include StoreTestDB

  KONUNGS = "urn:nabu:menota:am-1056-ix-4to"     # nor, 3 levels, lemma+msa, 51 lines
  BONBOK  = "urn:nabu:menota:holm-a-80"          # swe, facs-only trim, 48 lines
  STJORN  = "urn:nabu:menota:nra-norrfragm-60-a" # isl, 3 levels, xml:id tokens, 21 lines

  # The P82-r1 quarantine-recovery trims (all really-quarantined shapes):
  LAXDAELA = "urn:nabu:menota:am-132-fol-laxdaela-saga" # single-quoted local entity decl
  WORMIANUS = "urn:nabu:menota:am-242-fol"              # runic local entities + comment refs
  HOMILIES = "urn:nabu:menota:am-677-4to"               # local decls referencing table entities
  ELIS = "urn:nabu:menota:dg-4at7-elis"                 # single-level bare tokens, note-in-w
  PAMPH = "urn:nabu:menota:dg-4at7-pamph"               # single-level bare tokens, sic/corr

  ALL_URNS = [KONUNGS, LAXDAELA, WORMIANUS, HOMILIES, ELIS, PAMPH, BONBOK, STJORN].sort.freeze

  def conformance_adapter = Nabu::Adapters::Menota.new

  def conformance_workdir = Nabu::TestSupport.fixtures("menota")

  def conformance_expected_source_id = "menota"

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_text_file_sorted_by_urn
    refs = adapter.discover(workdir).to_a
    assert_equal ALL_URNS, refs.map(&:id),
                 "one document per texts/<documentId>.xml, urn downcased, sorted"
    assert(refs.all? { |ref| ref.source_id == "menota" })
    assert(refs.all? { |ref| ref.id == adapter.parse(ref).urn },
           "ref.id IS the document urn (the sync-breaker identity)")
  end

  def test_discover_never_yields_the_entity_table_or_catalogue_envelopes
    assert_equal 8, adapter.discover(workdir).map(&:id).size,
                 "menota-entities.txt and catalogue/*.json are not documents"
  end

  # -- the three-level document (AM 1056 IX 4to) ------------------------------

  def test_the_stored_text_is_the_diplomatic_level_at_line_grain
    document = adapter.parse(ref_for(KONUNGS))
    assert_equal "nor", document.language, "textLang mainLang is the document's own claim"
    assert_equal 51, document.count, "one passage per manuscript line bearing tokens"
    assert_equal "#{KONUNGS}:1rB.1", document.first.urn,
                 "cited <page><column>.<line> — folio 1r column B line 1"
    assert_equal "… i vigskorðum væria . þa er", document.first.text,
                 "the DIPLOMATIC reading (facs ꝩıgskorðum, norm vígskǫrðum stay in annotations)"
    assert_equal "#{KONUNGS}:2vB.12", document.to_a.last.urn
  end

  def test_all_reading_levels_and_morphology_ride_the_token_annotations
    document = adapter.parse(ref_for(KONUNGS))
    token = document.first.annotations["tokens"].find { |t| t["dipl"] == "vigskorðum" }
    refute_nil token
    assert_equal "ꝩıgskorðum", token["facs"], "MUFI entities resolved (&vins; &inodot;)"
    assert_equal "vígskǫrðum", token["norm"]
    assert_equal "vígskarð", token["lemma"]
    assert_equal "xNC gN nP cD sI", token["msa"], "the me:msa morphology verbatim"
    assert_equal "dipl", token["text_level"], "which level the stored text took, per token"
  end

  def test_line_breaks_inside_word_levels_advance_the_line_for_following_tokens
    document = adapter.parse(ref_for(KONUNGS))
    # <me:dipl>þur<lb ed="ms" n="7"/>fu</me:dipl>: the word stays on line 6,
    # the NEXT token opens line 7 — a word broken across lines is cited
    # where it starts.
    line6 = document.find { |p| p.urn == "#{KONUNGS}:1rB.6" }
    line7 = document.find { |p| p.urn == "#{KONUNGS}:1rB.7" }
    assert_includes line6.annotations["tokens"].map { |t| t["dipl"] }, "þurfu"
    refute_nil line7
  end

  def test_levels_census_rides_document_metadata
    metadata = adapter.parse(ref_for(KONUNGS)).metadata
    assert_equal({ "facs" => 255, "dipl" => 258, "norm" => 277 }, metadata["levels"],
                 "non-blank level attestations over all 277 tokens")
  end

  # -- the facs-only document (Holm A 80) -------------------------------------

  def test_a_facs_only_document_stores_the_facsimile_level
    document = adapter.parse(ref_for(BONBOK))
    assert_equal "swe", document.language,
                 "no textLang in this header — the langUsage language ident serves"
    assert_equal 48, document.count
    assert_equal "#{BONBOK}:2r.1", document.first.urn
    assert document.first.text.start_with?("Hær wilio"),
           "facs is the only attested level — it IS the stored text"
    assert_includes document.first.text, "ſighia", "long s preserved — canonical means canonical"
    assert_equal "#{BONBOK}:2v.24", document.to_a.last.urn, "the mid-word <pb> advances the page"
    token = document.first.annotations["tokens"].first
    assert_equal "facs", token["text_level"]
    refute token.key?("dipl"), "absent levels are absent, not empty strings"
    assert_equal({ "facs" => 424, "dipl" => 0, "norm" => 0 },
                 adapter.parse(ref_for(BONBOK)).metadata["levels"])
  end

  # -- the damaged fragment (NRA norr fragm 60 A) -----------------------------

  def test_the_fragment_parses_with_token_ids_and_supplied_text
    document = adapter.parse(ref_for(STJORN))
    assert_equal "isl", document.language
    assert_equal 21, document.count
    assert_equal "#{STJORN}:1v.1", document.first.urn
    assert_equal "her hefr bibleam , sua sem almattighr guð", document.first.text
    token = document.first.annotations["tokens"].first
    assert_equal "w100", token["id"], "upstream xml:id preserved"
    assert_equal "hér", token["lemma"]
  end

  # -- header metadata + dating (P81-1 structured envelope) -------------------

  def test_manuscript_provenance_rides_document_metadata
    document = adapter.parse(ref_for(KONUNGS))
    metadata = document.metadata
    assert_equal "A fragment of Konungs skuggsjá", document.title, "msName is the working title"
    assert_equal "AM 1056 IX 4to", metadata["signature"]
    assert_equal "Den Arnamagnæanske Samling", metadata["repository"]
    assert_equal "Copenhagen", metadata["settlement"]
    assert_equal "Denmark", metadata["country"]
    assert_equal "Norway", metadata["orig_place"], "origin claim, distinct from the holding library"
    assert_equal "nor", metadata.dig("facets", "language", "value"),
                 "the language facet the future lect rule keys on"
  end

  def test_the_orig_date_attributes_mint_the_structured_envelope
    metadata = adapter.parse(ref_for(KONUNGS)).metadata
    assert_equal({ "not_before" => 1280, "not_after" => 1310, "raw" => "c. 1300" },
                 metadata["date"], "upstream's own notBefore/notAfter, never guessed")
    assert_equal({ "not_before" => 1518, "not_after" => 1532, "raw" => "c. 1518-1532" },
                 adapter.parse(ref_for(BONBOK)).metadata["date"])
  end

  def test_menota_is_registered_for_the_structured_metadata_dates_shape
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES["menota"]
  end

  # -- the per-text license gate ----------------------------------------------

  def test_every_fixture_header_grants_by_sa_and_maps_to_attribution
    adapter.discover(workdir).each do |ref|
      document = adapter.parse(ref)
      assert_equal "attribution", document.license_override,
                   "#{ref.id}: <licence> CC-BY-SA 4.0 in the header maps explicitly"
      assert_equal "http://creativecommons.org/licenses/by-sa/4.0/",
                   document.metadata["license_url"]
    end
  end

  def test_the_license_map_is_explicit_and_a_stranger_grant_goes_restricted
    map = Nabu::Adapters::Menota.method(:license_override_for)
    assert_nil map.call(nil), "a license-silent header inherits the source class"
    assert_nil map.call("  ")
    assert_equal "attribution", map.call("CC-BY-SA 4.0")
    assert_equal "attribution", map.call("Creative Commons Attribution-ShareAlike 4.0")
    assert_equal "attribution", map.call("CC BY 4.0")
    assert_equal "nc", map.call("CC BY-NC-SA 4.0"), "NC outranks the SA match"
    assert_equal "open", map.call("This edition is in the public domain")
    assert_equal "restricted", map.call("All rights reserved by the editor"),
                 "an EXPLICIT statement the map does not recognize must never " \
                 "silently inherit BY-SA — the honest conservative class"
  end

  # -- the P82-r1 quarantine recovery -----------------------------------------
  #
  # The 2026-08-24 census of the 8 live-sync quarantines found NO unknown
  # entity in actual content anywhere in the 91-document corpus: every
  # "unknown" was either (a) an entity reference inside an XML comment —
  # which the XML spec says is not a reference at all — or (b) declared by
  # the file's own DOCTYPE internal subset, which the parser stripped
  # unread. Plus two documents encoded on a SINGLE level (bare text in
  # <w>, no me:facs/dipl/norm children) the token walker never read.

  def test_entity_references_inside_comments_are_not_references
    # AM 242 fol carries &aum;/&aumL; (transcriber's ä) ONLY inside
    # editorial comments; before P82-r1 they quarantined the document.
    document = adapter.parse(ref_for(WORMIANUS))
    assert_equal "isl", document.language
    assert_equal 3, document.count
    document.each do |passage|
      refute_match(/Kontrollera|Kolla|aum/, passage.text,
                   "comment content must never leak into passages")
    end
  end

  def test_internal_subset_local_entities_resolve
    # AM 242 fol declares 17 runic entities + an empty <!ENTITY none "">
    # in its DOCTYPE internal subset (upstream's own data, not ours).
    document = adapter.parse(ref_for(WORMIANUS))
    tokens = document.flat_map { |passage| passage.annotations["tokens"] }
    rune = tokens.find { |t| t["dipl"] == "ᚢ" }
    refute_nil rune, "&urun; resolves to RUNIC LETTER URUZ UR U per the file's own declaration"
    assert_equal "ᚢ", rune["facs"]
    qvad = tokens.find { |t| t["dipl"] == "qvað" }
    refute_nil qvad
    assert_equal "q", qvad["facs"], "<am>&none;</am> — the empty local entity — contributes nothing"
  end

  def test_local_declarations_may_reference_table_entities
    # AM 677 4to builds its local entities out of table entities:
    # &BAR; = &#x200A;&bar;, &escapacute; = &escap;&combacute;,
    # &THlig; = &#x2E24;TH&#x2E25; — nested references resolve recursively.
    document = adapter.parse(ref_for(HOMILIES))
    assert_equal "isl", document.language
    assert_equal 2, document.count
    tokens = document.flat_map { |passage| passage.annotations["tokens"] }
    konunglig = tokens.find { |t| t["dipl"] == "kononglig" }
    refute_nil konunglig
    assert_includes konunglig["facs"], " \u0305",
                    "&BAR; = hair space + combining overline (the house whitespace " \
                    "squeeze folds U+200A to a plain space)"
    assert_includes tokens.map { |t| t["dipl"] }, "Tʜᴇs", "&hscap;&escap; from the table"
    beor = tokens.find { |t| t["dipl"] == "Bᴇ́or" }
    refute_nil beor, "&escapacute; = &escap;&combacute; resolved through the table"
    thlig = tokens.find { |t| t["facs"]&.include?("⸤TH⸥") }
    refute_nil thlig, "&THlig; per the file's own declaration"
  end

  def test_single_quoted_local_declarations_parse
    # AM 132 fol (Laxdæla): <!ENTITY aacutenscapbllig '&#xF542;'> — the
    # internal subset uses single quotes, equally legal XML.
    document = adapter.parse(ref_for(LAXDAELA))
    assert_equal "isl", document.language, "no textLang — langUsage ident serves"
    assert_equal 1, document.count
    assert_equal "#{LAXDAELA}:156rb.11", document.first.urn
    tokens = document.first.annotations["tokens"]
    an = tokens.find { |t| t["facs"] == "" }
    refute_nil an, "&aacutenscapbllig; -> U+F542 (MUFI PUA) per the file's own declaration"
    assert_equal "áɴ", an["dipl"]
  end

  def test_a_single_level_document_stores_bare_tokens_at_the_declared_level
    # DG 4-7 Elis: no me:facs/dipl/norm anywhere — the reading is bare
    # text in <w>/<pc>, and the header claims the level itself:
    # <normalization me:level="dipl">.
    document = adapter.parse(ref_for(ELIS))
    assert_equal "nor", document.language
    assert_equal 4, document.count, "manuscript lines 6rA.14-17"
    assert_equal "#{ELIS}:6rA.14", document.first.urn
    assert_equal "HÆYRIT horskir menn . æína fagra saugu .", document.first.text,
                 "supplied/add/ex text rides the word; <pc> is a token"
    token = document.first.annotations["tokens"].first
    assert_equal "w100", token["id"]
    assert_equal "dipl", token["text_level"], "the header's own me:level claim"
    assert_equal "HÆYRIT", token["dipl"]
    assert_equal({ "facs" => 0, "dipl" => 30, "norm" => 0 }, document.metadata["levels"])
  end

  def test_editorial_notes_inside_bare_words_ride_annotations_not_text
    document = adapter.parse(ref_for(ELIS))
    tokens = document.flat_map { |passage| passage.annotations["tokens"] }
    ockarr = tokens.find { |t| t["id"] == "w167200" }
    refute_nil ockarr
    assert_equal "ockarr", ockarr["dipl"], "the <note> splits the word in the source bytes"
    assert_equal %(IBB: probably corrected from "i" or "u"), ockarr["note"]
    document.each { |p| refute_match(/probably corrected/, p.text) }
  end

  def test_abbreviation_choices_in_bare_words_read_the_expansion
    # <choice><am>ih&bar;c</am><ex>ieso</ex></choice>: dipl shows the
    # expansion; the abbreviation mark rides the token record.
    tokens = adapter.parse(ref_for(ELIS)).flat_map { |p| p.annotations["tokens"] }
    ieso = tokens.find { |t| t["id"] == "w128900" }
    refute_nil ieso
    assert_equal "ieso", ieso["dipl"]
    assert_equal "ih̅c", ieso["am"]
  end

  def test_sic_corr_choices_in_bare_words_read_the_manuscript
    # DG 4-7 Pamphilus: <choice><sic>gera</sic><corr resp="HP">gefa</corr>
    # </choice> — the manuscript reading is the diplomatic text, the
    # editor's emendation rides the record.
    document = adapter.parse(ref_for(PAMPH))
    assert_equal "nor", document.language
    assert_equal 8, document.count
    tokens = document.flat_map { |passage| passage.annotations["tokens"] }
    gera = tokens.find { |t| t["id"] == "w00043" }
    refute_nil gera
    assert_equal "gera", gera["dipl"]
    assert_equal "gefa", gera["corr"]
    document.each { |p| refute_match(/gefa/, p.text) }
  end

  def test_milestone_adjacent_whitespace_inside_bare_words_is_layout
    document = adapter.parse(ref_for(PAMPH))
    assert_equal "#{PAMPH}:3ra.1", document.first.urn
    assert_equal "EC EM SÆRÐR . oc ber ec gaflak", document.first.text,
                 "gaf<lb/>lak: XML indentation around a mid-word milestone is not reading text"
    tokens = document.flat_map { |passage| passage.annotations["tokens"] }
    assert_includes tokens.map { |t| t["dipl"] }, "hæilsu hialp",
                    "a REAL internal space in a bare token is preserved"
    assert_includes tokens.map { |t| t["dipl"] }, "bæiskari", "<unclear> readings ride the word"
    assert_equal "#{PAMPH}:3ra.19", document.to_a.last.urn
  end

  def test_a_bare_token_document_without_a_declared_level_quarantines
    Dir.mktmpdir("menota-no-level") do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(workdir, "menota-entities.txt"), dir)
      body = File.read(File.join(workdir, "texts", "DG-4at7-Pamph.xml"))
                 .sub(%r{<normalization me:level="dipl">.*?</normalization>}m, "")
      File.write(File.join(texts, "DG-4at7-Pamph.xml"), body)
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/me:level/, error.message,
                   "a level we cannot attribute honestly is a quarantine, never a guess")
    end
  end

  def test_mixed_level_documents_still_drop_level_less_tokens
    # The status-quo pin for the 83 already-loaded documents: a document
    # WITH me: levels keeps ignoring bare tokens (AM 1056's counts are
    # pinned above); recovery must not rewrite loaded corpora.
    assert_equal 51, adapter.parse(ref_for(KONUNGS)).count
    assert_equal 48, adapter.parse(ref_for(BONBOK)).count
  end

  # -- damage -----------------------------------------------------------------

  def test_a_missing_entity_table_quarantines_with_an_instructive_error
    Dir.mktmpdir("menota-no-entities") do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(workdir, "texts", "AM-1056-IX-4to.xml"), texts)
      refs = adapter.discover(dir).to_a
      assert_equal 1, refs.size
      error = assert_raises(Nabu::ParseError) { adapter.parse(refs.first) }
      assert_match(/menota-entities\.txt/, error.message)
    end
  end

  def test_an_unknown_entity_quarantines_naming_it
    Dir.mktmpdir("menota-bad-entity") do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(workdir, "menota-entities.txt"), dir)
      body = File.read(File.join(workdir, "texts", "AM-1056-IX-4to.xml"))
                 .sub("&inodot;", "&nosuchentity;")
      File.write(File.join(texts, "AM-1056-IX-4to.xml"), body)
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/nosuchentity/, error.message, "unknown entities quarantine loudly, never drop")
    end
  end

  def test_a_non_tei_body_quarantines_as_parse_error
    Dir.mktmpdir("menota-broken") do |dir|
      texts = File.join(dir, "texts")
      FileUtils.mkdir_p(texts)
      FileUtils.cp(File.join(workdir, "menota-entities.txt"), dir)
      File.write(File.join(texts, "Broken-1.xml"), "{\"error\": \"not xml at all\"}")
      assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
    end
  end

  # -- manifest + probe -------------------------------------------------------

  def test_manifest_records_the_by_sa_grant_and_the_crawl_blessing
    manifest = adapter.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "CC BY-SA 4.0"
    assert_includes manifest.license, "catalogue"
    assert_equal "menota-tei", manifest.parser_family
  end

  def test_remote_probe_is_a_liveness_only_head_of_the_api
    assert_equal :http_zip, Nabu::Adapters::Menota.remote_probe_strategy
    targets = Nabu::Adapters::Menota.http_probe_targets
    assert_equal 1, targets.size
    target = targets.first
    assert target.liveness_only, "a session-based API the probe cannot diff URL-by-URL"
    assert_equal "https://clarino.uib.no/korpuskel-api/rest?command=get-session", target.zip_url
    assert_equal Nabu::MenotaFetch::STATE_FILE, target.state_file
  end

  # -- store: idempotent load -------------------------------------------------

  def test_loads_idempotently_into_the_store
    db = store_test_db
    source = create_source(db)
    first = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 8, first.added
    assert_equal 0, first.errored
    assert_equal 138, db[:passages].count,
                 "51 + 48 + 21 manuscript lines + the P82-r1 trims (3 + 2 + 1 + 4 + 8)"

    second = Nabu::Store::Loader.new(db: db, source: source).load_from(adapter, workdir: workdir)
    assert_equal 0, second.errored
    assert_equal 8, second.skipped, "a byte-identical reload skips every document"
    assert_equal 138, db[:passages].count
    assert_equal [1], db[:passages].distinct.select_map(:revision)
  ensure
    db&.disconnect
  end

  private

  def ref_for(urn)
    adapter.discover(workdir).to_a.find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def create_source(_db)
    Nabu::Store::Source.create(
      slug: "menota", name: "Menota", adapter_class: "Nabu::Adapters::Menota",
      license_class: "attribution"
    )
  end
end
