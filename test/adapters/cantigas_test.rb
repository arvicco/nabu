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
      urn:nabu:cantigas:475
      urn:nabu:cantigas:562
      urn:nabu:cantigas:600
      urn:nabu:cantigas:959
      urn:nabu:cantigas:1025
      urn:nabu:cantigas:1241
      urn:nabu:cantigas:1400
      urn:nabu:cantigas:1706
    ], ids, "numeric order, not string order — cdcant ids are sparse integers (P56-1 " \
            "added the six recovered quirk pages; quirks/cantiga-1066.html stays undiscovered)"
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

  # --- the P56-1 quirk pages (the first sync's 7 quarantines, all REAL) ------
  #
  # Ground truth from the pages themselves (see fixtures README): on every
  # gap page the edition's printed every-5th numbers run AHEAD of the
  # display ordinal, the offset grows ONLY across stanza-break rows, and the
  # sidebar marks each of them "Refrão" — the edition's numbering counts
  # refrain lines the page display merges/elides. The parser adopts the
  # edition's numbering (the urn line IS the edition's number, the packet
  # invariant kept), makes the jump visible in the line annotations, and
  # pins the uncounted lines as "number_gap" on the first line after each
  # gap boundary plus a document-level "number_gaps" total.

  def test_cantiga_475_adopts_the_editions_numbering_across_refrain_gaps
    document = parse(475)
    assert_equal 15, document.size, "3 cobras of 5 displayed lines (4 body + 1 merged refrain line)"
    assert_equal [1, 2, 3, 4, 5, 7, 8, 9, 10, 11, 13, 14, 15, 16, 17],
                 document.map { |p| p.annotations["line"] },
                 "edition numbering adopted: one uncounted refrain line after each cobra"
    line7 = document.passages.find { |p| p.annotations["line"] == 7 }
    assert_equal "urn:nabu:cantigas:475:7", line7.urn, "the urn line IS the edition's number"
    assert_equal 1, line7.annotations["number_gap"],
                 "the first line after the gap records how many edition lines the display elides"
    line13 = document.passages.find { |p| p.annotations["line"] == 13 }
    assert_equal 1, line13.annotations["number_gap"]
    assert_equal 2, document.metadata["number_gaps"], "document total: 2 uncounted edition lines"
    assert_equal (0..14).to_a, document.map(&:sequence), "sequence stays the dense display order"
    assert_equal [1, 2, 3], document.map { |p| p.annotations["stanza"] }.uniq
    assert_equal "Afonso X", document.metadata["author"]
  end

  def test_cantiga_959_takes_a_two_line_gap_before_the_finda
    document = parse(959)
    assert_equal 22, document.size
    assert_equal [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 23, 24, 25, 26],
                 document.map { |p| p.annotations["line"] },
                 "gaps of 1, 1, then 2 (the printed 25 pins the finda at edition 23-26)"
    finda_first = document.passages.find { |p| p.annotations["line"] == 23 }
    assert_equal 2, finda_first.annotations["number_gap"]
    assert_equal 4, finda_first.annotations["stanza"]
    assert_equal 4, document.metadata["number_gaps"]
    assert_equal "urn:nabu:cantigas:959:26", document.passages.last.urn
  end

  def test_cantiga_1025_gap_opens_once_and_the_unnumbered_finda_keeps_the_offset
    document = parse(1025)
    assert_equal 20, document.size
    assert_equal [1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21],
                 document.map { |p| p.annotations["line"] },
                 "one uncounted line after cobra 1 only; later printed 15 verifies the offset held"
    assert_equal 1, document.metadata["number_gaps"]
    assert_equal 1, document.passages.find { |p| p.annotations["line"] == 8 }.annotations["number_gap"]
    assert_equal 4, document.passages.last.annotations["stanza"], "3 cobras + finda"
  end

  def test_cantiga_1706_the_espuria_fragment_recovers_with_its_rubric
    document = parse(1706)
    assert_equal 10, document.size, "a fragment — the last displayed line trails off in (...)"
    lines = document.map { |p| p.annotations["line"] }
    assert_equal [1, 2, 3, 4, 5, 6, 7, 8, 10, 11], lines
    assert_equal 1, document.passages.find { |p| p.annotations["line"] == 10 }.annotations["number_gap"]
    assert_equal 1, document.metadata["number_gaps"]
    assert_equal "Espúria", document.metadata["genre"]
    assert_includes document.metadata["rubric"], "Pergunta que fez Álvaro Afonso"
    assert_equal "Alvaro Afonso", document.metadata["author"]
  end

  def test_cantiga_562_skips_the_numbered_but_empty_edition_line_and_records_it
    document = parse(562)
    assert_equal 19, document.size, "the numbered-but-textless row 20 yields no passage"
    assert_equal (1..19).to_a, document.map { |p| p.annotations["line"] },
                 "numbering stayed consistent — the empty row consumed edition line 20"
    assert_equal [20], document.metadata["empty_lines"],
                 "the skipped edition line is recorded, never silently swallowed"
    refute document.metadata.key?("number_gaps"), "no printed-number gap on this page"
    assert_equal "ou de me quererdes valer.", document.passages.last.text, "the one-line finda"
    assert_equal 4, document.passages.last.annotations["stanza"]
  end

  def test_cantiga_1241_is_honestly_unattributed
    document = parse(1241)
    metadata = document.metadata
    assert metadata["unattributed"], "the page's own [Sem autor atribuído] label, recorded honestly"
    refute metadata.key?("author"), "no author is minted for an unattributed cantiga"
    refute metadata.key?("author_id")
    assert_equal "Amigo", metadata["genre"]
    assert_equal 18, document.size
    assert_equal (1..18).to_a, document.map { |p| p.annotations["line"] }, "numbering is clean here"
  end

  def test_cantiga_1066_text_not_published_upstream_stays_quarantined
    ref = Nabu::DocumentRef.new(source_id: "cantigas", id: "urn:nabu:cantigas:1066",
                                path: File.join(FIXTURES, "quirks", "cantiga-1066.html"))
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
    assert_match(/Texto ainda não disponível/, error.message,
                 "the quarantine names the page's own no-text marker — upstream publishes " \
                 "no text for this cantiga, so it stays quarantined, loudly and specifically")
  end

  # --- the printed-number cross-check keeps catching real drift --------------

  def synthetic_cantiga(cdcant, rows)
    body = rows.map do |printed, text|
      if text == :break
        "<tr><td>&nbsp;&nbsp;</td></tr>"
      else
        "<tr><td></td><td>#{printed}</td><td></td><td class=\"left13\">#{text}</td></tr>"
      end
    end.join
    "<html><body><div id=\"main\"><a href=\"javascript:cantiga1('cantiga_print.asp?" \
      "cdcant=#{cdcant}');\">x</a><table>#{body}</table></div></body></html>"
  end

  def assert_number_drift_quarantines(rows, reason)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "cantiga-88.html"), synthetic_cantiga(88, rows))
      ref = Nabu::DocumentRef.new(source_id: "cantigas", id: "urn:nabu:cantigas:88",
                                  path: File.join(dir, "cantiga-88.html"))
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/printed line number/, error.message, reason)
    end
  end

  def test_a_printed_number_ahead_with_no_stanza_boundary_still_quarantines
    rows = [["", "a"], ["", "b"], ["", "c"], ["", "d"], ["5", "e"],
            ["", "f"], ["", "g"], ["", "h"], ["10", "i"]]
    assert_number_drift_quarantines rows,
                                    "a gap can only open at a stanza boundary; mid-stanza the " \
                                    "printed number must BE the ordinal — real drift stays loud"
  end

  def test_a_printed_number_behind_the_ordinal_still_quarantines
    rows = [["", "a"], ["", "b"], ["", "c"], ["", "d"], ["5", "e"], ["", :break],
            ["", "f"], ["", "g"], ["", "h"], ["8", "i"]]
    assert_number_drift_quarantines rows,
                                    "the edition's numbering never runs BEHIND the display — " \
                                    "a lower printed number is drift even across a boundary"
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
