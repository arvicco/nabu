# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"

# Nabu::Adapters::Cantigas (P55-1): Cantigas Medievais Galego-Portuguesas
# (Projeto Littera, IEM/FCSH-NOVA Lisbon) — ~1,680 secular Galician-
# Portuguese lyric texts, crawled as per-cantiga HTML pages. Fixtures are
# REAL pages retrieved 2026-07-31, raw Windows-1252 bytes preserved — see
# test/fixtures/cantigas/README.md.
class CantigasTest < Minitest::Test
  include AdapterConformance

  FIXTURES = Nabu::TestSupport.fixtures("cantigas")

  def conformance_adapter
    Nabu::Adapters::Cantigas.new
  end

  def conformance_workdir
    FIXTURES
  end

  def conformance_expected_source_id
    "cantigas"
  end

  def adapter = conformance_adapter

  def parse(id)
    ref = adapter.discover(FIXTURES).find { |r| r.id == "urn:nabu:cantigas:#{id}" }
    refute_nil ref, "fixture cantiga #{id} must be discovered"
    adapter.parse(ref)
  end

  # --- discovery -------------------------------------------------------------

  def test_discover_yields_one_ref_per_page_in_numeric_cdcant_order
    ids = adapter.discover(FIXTURES).map(&:id)
    assert_equal %w[
      urn:nabu:cantigas:1
      urn:nabu:cantigas:600
      urn:nabu:cantigas:1400
    ], ids, "numeric order, not string order — cdcant ids are sparse integers"
  end

  def test_discovery_skips_counts_the_letter_index_sidecars
    assert_equal 0, adapter.discovery_skips(FIXTURES).skipped_by_rule,
                 "the fixture top dir carries no index sidecars"
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "listacantigas-A.html"), "<html/>")
      File.write(File.join(dir, "cantiga-2.html"), "<html/>")
      assert_equal 1, adapter.discovery_skips(dir).skipped_by_rule,
                   "the persisted letter indexes are skipped by rule, never silently"
    end
  end

  # --- cantiga 1 (Anónimo, Lai — the semanotacoes parse fixture) -------------

  def test_cantiga_1_lines_carry_the_verse_at_line_urns
    document = parse(1)
    assert_equal "urn:nabu:cantigas:1", document.urn
    assert_equal "roa-opt", document.language, "Old Galician-Portuguese (D55-a)"
    assert_equal "Amor, des que m'a vós cheguei,", document.title,
                 "title = the incipit, the first verse line"
    assert_equal 43, document.size, "40 numbered lines + the 3-line finda"
    first = document.passages.first
    assert_equal "urn:nabu:cantigas:1:1", first.urn
    assert_equal "Amor, des que m'a vós cheguei,", first.text
    assert_equal 1, first.annotations["line"]
    assert_equal 1, first.annotations["stanza"]
    assert_equal "Amen! Amen! Amen!", document.passages.last.text
  end

  def test_cantiga_1_stanza_breaks_follow_the_nbsp_rows
    document = parse(1)
    line5 = document.passages.find { |p| p.annotations["line"] == 5 }
    assert_equal 2, line5.annotations["stanza"], "lines 1-4 are cobra 1; line 5 opens cobra 2"
    assert_equal 11, document.passages.last.annotations["stanza"],
                 "10 four-line cobras + the finda = 11 stanzas"
    assert_equal (1..11).to_a, document.map { |p| p.annotations["stanza"] }.uniq,
                 "stanzas count 1..11 in order, no gaps"
  end

  def test_cantiga_1_metadata_carries_author_rubric_genre_form_and_sigla
    metadata = parse(1).metadata
    assert_equal "Anónimo", metadata["author"]
    assert_equal 157, metadata["author_id"], "the stable cdaut id from the autor.asp link"
    assert_equal "Lai", metadata["genre"]
    assert_includes metadata["rubric"], "Este lais fez Elis, o Baço, que foi Duc de Sansonha"
    assert_equal ["Mestria", "Cobras singulares", "Finda"], metadata["form"],
                 "the Descrição lines after the genre line"
    assert_equal ["B 1, L 1", "(C 1)"], metadata["manuscripts"],
                 "the Fontes manuscritas sigla, nbsp folded to plain space"
  end

  # --- cantiga 600 (D. Dinis, Amigo — the with-notes variant) ----------------

  def test_cantiga_600_parses_the_with_notes_variant_cleanly
    document = parse(600)
    assert_equal "- Amigo, queredes-vos ir?", document.title
    assert_equal 24, document.size
    assert_equal 4, document.passages.last.annotations["stanza"]
    line2 = document.passages.find { |p| p.annotations["line"] == 2 }
    assert_equal "- Si, mia senhor, ca nom poss'al", line2.text,
                 "inline glossary span.ref wrappers contribute their surface words, nothing else"
    metadata = document.metadata
    assert_equal "D. Dinis", metadata["author"]
    assert_equal 25, metadata["author_id"]
    refute metadata.key?("rubric"), "cantiga 600 carries no rubric — honest sparsity"
    assert_equal ["B 575/576, V 179", "(C 575)"], metadata["manuscripts"]
  end

  def test_cantiga_600_genre_drops_the_cantiga_de_prefix
    assert_equal "Amigo", parse(600).metadata["genre"],
                 "sidebar says \"Cantiga de Amigo\"; the stored facet is the bare genre"
  end

  # --- cantiga 1400 (Martim Soares, Escárnio — the cp1252 exemplar) ----------

  def test_cantiga_1400_first_line_keeps_the_entity_decoded_medieval_nasal
    document = parse(1400)
    assert_equal "Ũa donzela jaz [preto d]aqui,", document.passages.first.text,
                 "&#360;a decodes to the medieval nasal Ũ, NFC at the boundary"
    assert_equal 21, document.size
    assert_equal 3, document.passages.last.annotations["stanza"]
    assert_equal "Martim Soares", document.metadata["author"]
    assert_equal 98, document.metadata["author_id"]
  end

  def test_cantiga_1400_genre_case_variance_normalizes
    assert_equal "Escárnio e maldizer", parse(1400).metadata["genre"]
  end

  def test_genre_normalization_folds_the_censused_case_variants
    parser = Nabu::Adapters::CantigasHtmlParser
    assert_equal "Escárnio e maldizer", parser.normalize_genre("Cantiga de Escárnio e Maldizer"),
                 "the letter-A index carries BOTH casings; one facet value comes out"
    assert_equal "Escárnio e maldizer", parser.normalize_genre("Cantiga de Escárnio e maldizer")
    assert_equal "Lai", parser.normalize_genre("Lai")
    assert_equal "Género incerto", parser.normalize_genre("Género Incerto")
    assert_equal "Tenção de amor", parser.normalize_genre("Tenção de Amor")
    assert_equal "Pastorela", parser.normalize_genre("Cantiga de Pastorela"),
                 "an un-censused genre passes through with only the prefix stripped"
  end

  # --- the Windows-1252 boundary (the packet's key regression) ---------------

  def test_fixtures_keep_the_raw_windows_1252_bytes
    # The regression corpus documents the quirk at the byte level: if a
    # helpful transcode ever launders the fixtures, this fails loudly.
    assert_includes File.binread(File.join(FIXTURES, "cantiga-1400.html")).bytes, 0x92,
                    "cantiga-1400.html must keep its raw 0x92 (’) rubric byte"
    notes = File.binread(File.join(FIXTURES, "fetch", "cantiga-1-with-notes.html")).bytes
    assert_includes notes, 0x96, "the with-notes cantiga 1 keeps its 0x96 (–) byte"
    assert_includes notes, 0x93, "and its 0x93 (“) byte"
  end

  def test_the_apostrophe_rubric_byte_decodes_as_windows_twelve_fifty_two_not_latin_one
    rubric = parse(1400).metadata["rubric"]
    assert_includes rubric, "fez d’escarnho", "0x92 is U+2019 in Windows-1252 (a C1 control in " \
                                              "ISO-8859-1, which the page's own meta falsely claims)"
    assert_includes rubric, "(Em B e V, antes da composição)"
  end

  def test_both_page_variants_parse_to_identical_verse
    # The crawl lands semanotacoes=true pages; two fixtures (600, 1400) are
    # the scout's with-notes probes. Prove the tolerance is real: cantiga 1
    # exists in BOTH shapes, and the verse comes out identical.
    ref = Nabu::DocumentRef.new(source_id: "cantigas", id: "urn:nabu:cantigas:1",
                                path: File.join(FIXTURES, "fetch", "cantiga-1-with-notes.html"))
    with_notes = adapter.parse(ref)
    clean = parse(1)
    assert_equal clean.map(&:text), with_notes.map(&:text)
    assert_equal clean.map(&:annotations), with_notes.map(&:annotations)
    assert_equal clean.metadata, with_notes.metadata
  end

  # --- identity and shape defenses -------------------------------------------

  def test_a_page_served_under_the_wrong_cdcant_quarantines
    ref = Nabu::DocumentRef.new(source_id: "cantigas", id: "urn:nabu:cantigas:9999",
                                path: File.join(FIXTURES, "cantiga-600.html"))
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert_match(/600/, error.message, "the drift names the page's own cdcant")
  end

  def test_a_page_without_verse_lines_quarantines
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cantiga-77.html"),
                 "<html><body><div id=\"main\"><a href=\"javascript:cantiga1(" \
                 "'cantiga_print.asp?cdcant=77');\">x</a><p>no verse</p></div></body></html>")
      ref = Nabu::DocumentRef.new(source_id: "cantigas", id: "urn:nabu:cantigas:77",
                                  path: File.join(dir, "cantiga-77.html"))
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/verse/, error.message,
                   "every cantiga page carries verse — absence is page-shape drift, loud")
    end
  end

  # --- fetch posture ---------------------------------------------------------

  def test_fetch_wraps_a_broken_index_in_fetch_error
    stub_request(:get, /listacantigas\.asp/).to_return(status: 200, body: "<html>maintenance</html>")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::FetchError) do
        Nabu::Adapters::Cantigas.new(delay: 0).fetch(File.join(dir, "cantigas"))
      end
      assert_match(/cantigas fetch failed/, error.message)
    end
  end

  # --- license ---------------------------------------------------------------

  def test_license_is_the_lopes_grant_with_the_project_citation_verbatim
    manifest = Nabu::Adapters::Cantigas.manifest
    assert_equal "attribution", manifest.license_class
    assert_includes manifest.license, "you can do whatever you like with the data",
                    "the coordinator's grant sentence, verbatim"
    assert_includes manifest.license,
                    "Lopes, Graça Videira; Ferreira, Manuel Pedro et al. (2011–), " \
                    "Cantigas Medievais Galego Portuguesas [online database]. " \
                    "Lisboa: Instituto de Estudos Medievais, FCSH/NOVA. " \
                    "[Information retrieved on (date)] Available at: cantigas.fcsh.unl.pt.",
                    "the project's own citation format rides verbatim, both coordinators named, " \
                    "with the retrieval-date slot"
    assert_includes manifest.credit, "Lopes, Graça Videira; Ferreira, Manuel Pedro",
                    "full attribution is the grant's one condition — the credit line renders it"
  end
end
