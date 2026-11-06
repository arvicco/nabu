# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # socinian-letters — the Socinian correspondence (Die sozinianischen
  # Briefwechsel, AdW Mainz): one GitLab folder zip of 2,217 teiCorpus letter
  # files (cover letter + attachments, each with its witnesses) plus the
  # data/csv/indices.csv register. Document = cover letter + the attachments
  # it holds; passage = text block of the chosen witness. Fixture: six whole
  # letter files + a trimmed register (README.md).
  class SocinianLettersTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("socinian-letters")
    LETTERS = File.join(FIXTURES, "data", "xml", "letters")
    URN = "urn:nabu:socinian-letters"
    ADAPTER = Nabu::Adapters::SocinianLetters
    ZIP_URL = ADAPTER::ZIP_URL
    INDICES_URL = ADAPTER::INDICES_URL
    ACCEPTED = %w[MAIN_anw_qlm_zdb MAIN_ckw_qlm_zdb MAIN_dq3_2dc_b2b MAIN_lfw_qlm_zdb MAIN_u3w_qlm_zdb
                  MAIN_ydw_qlm_zdb].freeze

    def conformance_adapter = ADAPTER.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "socinian-letters"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(id) = documents.find { |d| d.urn == "#{URN}:#{id}" } || flunk("#{id} missing")

    # The fixture's data/ tree as it lands in canonical/socinian-letters/.
    def landed_tree(except: [])
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "data"), dir)
        except.each { |name| FileUtils.rm_f(File.join(dir, "data", "xml", "letters", name)) }
        yield dir
      end
    end

    # -- discovery -------------------------------------------------------------

    def test_discovers_the_transcribed_letters_by_cover_id
      assert_equal(ACCEPTED.map { |id| "#{URN}:#{id}" }, conformance_adapter.discover(FIXTURES).map(&:id))
    end

    def test_a_metadata_only_letter_skips_by_rule
      landed_tree do |dir|
        skips = conformance_adapter.discovery_skips(dir)
        assert skips.clean?, skips.notes.inspect
        assert_equal 2, skips.skipped_by_rule, "the metadata-only letter + the register"
        note = skips.notes.find { |n| n.start_with?("LETTER_MAIN_ed_nnl_xb5_r5b.xml:") }
        refute_nil note, skips.notes.inspect
        assert_includes note, "metadata only"
        assert(skips.notes.any? { |n| n.start_with?("data/csv/indices.csv:") })
      end
    end

    def test_the_fetch_state_pins_skip_by_rule_and_strangers_are_unrecognized
      landed_tree do |dir|
        File.write(File.join(dir, Nabu::ZipFetch::STATE_FILE), "{}")
        File.write(File.join(dir, "data", "csv", Nabu::FileFetch::STATE_FILE), "{}")
        assert_equal 4, conformance_adapter.discovery_skips(dir).skipped_by_rule
        File.write(File.join(dir, "data", "notes.txt"), "?")
        refute conformance_adapter.discovery_skips(dir).clean?
      end
    end

    # -- the document grain: cover letter + held attachments -------------------

    def test_an_attachment_with_its_own_letter_file_is_held_there
      lfw = doc("MAIN_lfw_qlm_zdb")
      assert(lfw.passages.none? { |p| p.urn.include?("MAIN_ckw_qlm_zdb") })
      attachment = lfw.metadata["attachments"].first
      assert_equal "MAIN_ckw_qlm_zdb", attachment["id"]
      assert_equal "#{URN}:MAIN_ckw_qlm_zdb", attachment["held_in"]
      assert_equal "Brief", attachment["type"]
      assert_includes doc("MAIN_ckw_qlm_zdb").passages.map(&:text).join(" "), "Luculenta et succi plena"
    end

    def test_an_attachment_without_its_own_letter_file_rides_its_cover_letter
      landed_tree(except: ["LETTER_MAIN_ckw_qlm_zdb.xml"]) do |dir|
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "#{URN}:MAIN_lfw_qlm_zdb" }
        lfw = adapter.parse(ref)
        held = lfw.passages.select { |p| p.urn.start_with?("#{URN}:MAIN_lfw_qlm_zdb:MAIN_ckw_qlm_zdb.") }
        refute_empty held
        assert_equal "attachment", held.first.annotations["component"]
        assert_includes held.map(&:text).join(" "), "Luculenta et succi plena"
        assert_equal "here", lfw.metadata["attachments"].first["held_in"]
      end
    end

    def test_an_attachment_repeated_across_letters_is_held_once_by_the_first_file
      landed_tree(except: ["LETTER_MAIN_ckw_qlm_zdb.xml"]) do |dir|
        letters = File.join(dir, "data", "xml", "letters")
        twin = File.read(File.join(letters, "LETTER_MAIN_lfw_qlm_zdb.xml"))
                   .gsub("MAIN_lfw_qlm_zdb", "MAIN_zzz_twin")
        File.write(File.join(letters, "LETTER_MAIN_zzz_twin.xml"), twin)
        adapter = conformance_adapter
        docs = adapter.discover(dir).to_h { |r| [r.id, adapter.parse(r)] }
        holders = docs.values.select { |d| d.passages.any? { |p| p.urn.include?(":MAIN_ckw_qlm_zdb.") } }
        assert_equal ["#{URN}:MAIN_lfw_qlm_zdb"], holders.map(&:urn), "the sorted-first file holds it"
        assert_equal "#{URN}:MAIN_lfw_qlm_zdb", docs["#{URN}:MAIN_zzz_twin"].metadata["attachments"].first["held_in"]
      end
    end

    # -- passages ----------------------------------------------------------------

    def test_passages_are_the_witness_text_blocks
      ckw = doc("MAIN_ckw_qlm_zdb")
      first = ckw.passages.first
      assert_equal "#{URN}:MAIN_ckw_qlm_zdb:1", first.urn
      assert_equal "Ratisbona Hamburgum die 15. Octobris 1665.", first.text
      assert_equal "dateline", first.annotations["block"]
      assert_equal "cover_letter", first.annotations["component"]
      assert_equal "172", first.annotations["page"]
      second = ckw.passages[1]
      assert_equal "p", second.annotations["block"]
      assert second.text.start_with?("Luculenta et succi plena est haec ultima epistola generositatis vestrae")
      assert_equal "lat", second.language
    end

    def test_editorial_notes_leave_the_text_and_ride_the_passage
      passages = doc("MAIN_dq3_2dc_b2b").passages
      text = passages.map(&:text).join("\n")
      refute_includes text, "Der Eintrag steht in keinem", "the editors' German commentary is not letter text"
      noted = passages.find { |p| p.annotations["notes"] }
      assert_includes noted.annotations["notes"].first, "Der Eintrag steht in keinem inhaltlichen Zusammenhang"
      assert noted.text.start_with?("Testament du Cardinal Mazarini Senem"), "a note in the writer's hand is text"
    end

    def test_deletions_drop_and_additions_render
      text = doc("MAIN_dq3_2dc_b2b").passages.map(&:text).join("\n")
      assert_includes text, "ad revocandam in mentem meam tui memoriam"
      refute_includes text, "hac conditione institui", "struck-through text is not the reading text"
      postscript = doc("MAIN_dq3_2dc_b2b").passages.find { |p| p.annotations["block"] == "postscript" }
      assert postscript.text.start_with?("Die 3. Aprilis postscriptum.")
      assert_equal "Scribebam Lutetiae Parisiorum die 30. Martii 1663.", doc("MAIN_dq3_2dc_b2b").passages.last.text
    end

    def test_mentions_and_page_breaks_ride_the_block
      second = doc("MAIN_dq3_2dc_b2b").passages[1]
      assert_equal %w[Polonia Prussia], second.annotations["places"]
      assert_equal ["254r"], second.annotations["page_breaks"]
      assert_equal "254r", doc("MAIN_dq3_2dc_b2b").passages[2].annotations["page"]
      assert_includes doc("MAIN_dq3_2dc_b2b").passages.first.annotations["persons"], "Stanislao Lubienietzki"
    end

    def test_choice_takes_the_expansion
      text = doc("MAIN_anw_qlm_zdb").passages.map(&:text).join(" ")
      assert_includes text, "die 16. Februarii 1667."
      refute_includes text, "Febr. Februarii"
    end

    def test_a_block_wholly_inside_one_foreign_span_takes_its_language
      u3w = doc("MAIN_u3w_qlm_zdb")
      assert_equal "fra", u3w.language
      latin = u3w.passages.find { |p| p.text.start_with?("Quod attinet ad sententiam") }
      assert_equal "lat", latin.language
      french = u3w.passages.find { |p| p.text.start_with?("Quant à ce, qui touche") }
      assert_equal "fra", french.language
    end

    # -- the witness rule ----------------------------------------------------------

    def test_the_reference_witness_is_chosen
      meta = doc("MAIN_ckw_qlm_zdb").metadata
      assert_equal "ckw_qlm_zdb", meta["witness"]
      assert_equal "reference_witness", meta["witness_basis"]
    end

    def test_an_untranscribed_reference_witness_falls_back_to_the_first_transcribed_one
      meta = doc("MAIN_anw_qlm_zdb").metadata
      assert_equal "ed_stc_1nf_jzb", meta["witness"]
      assert_equal "first transcribed witness (reference witness untranscribed)", meta["witness_basis"]
      assert_equal "Druck", meta["witness_medium"]
      assert_equal 2, meta["witnesses"]
    end

    # -- licence: per TEI, read from the chosen witness ---------------------------

    def test_the_licence_is_the_chosen_witness_licence
      assert_equal ["CC BY 4.0"], doc("MAIN_ckw_qlm_zdb").metadata["license"]
      ydw = doc("MAIN_ydw_qlm_zdb").metadata
      assert_equal ["CC BY-SA 3.0"], ydw["license"], "the reference witness is BY-SA though the corpus header says BY"
      assert_equal ["https://creativecommons.org/licenses/by-sa/3.0/"], ydw["license_url"]
    end

    def test_an_unknown_licence_quarantines
      landed_tree do |dir|
        path = File.join(dir, "data", "xml", "letters", "LETTER_MAIN_ckw_qlm_zdb.xml")
        File.write(path, File.read(path).gsub("licenses/by/4.0/", "licenses/by-nc/4.0/"))
        adapter = conformance_adapter
        ref = adapter.discover(dir).find { |r| r.id == "#{URN}:MAIN_ckw_qlm_zdb" }
        assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      end
    end

    # -- axes ------------------------------------------------------------------------

    def test_the_sent_date_is_the_document_date
      assert_equal({ "not_before" => 1665, "not_after" => 1665, "raw" => "1665-10-15", "class" => "composition" },
                   doc("MAIN_ckw_qlm_zdb").metadata["date"])
      assert_equal 1597, doc("MAIN_ydw_qlm_zdb").metadata.dig("date", "not_before")
    end

    def test_the_sending_place_is_linked_through_the_register
      meta = doc("MAIN_ckw_qlm_zdb").metadata
      assert_equal "Regensburg", meta["place"]
      assert_equal "https://www.geonames.org/2849483", meta["place_ref"]
      assert_equal "sent", meta["place_role"]
      assert_equal "Hamburg", meta["place_received"]
      assert_equal "https://www.geonames.org/2911298", meta["place_received_ref"]
      assert_equal "Küstrin", doc("MAIN_u3w_qlm_zdb").metadata["place"], "the register's label, not the header's"
    end

    def test_correspondents_carry_their_register_identity
      meta = doc("MAIN_ckw_qlm_zdb").metadata
      assert_equal "Rautenstein, Johann Ernst von", meta["author"]
      assert_equal "https://d-nb.info/gnd/124058698", meta["author_ref"]
      assert_equal "Lubieniecki, Stanisław", meta["recipient"]
      sender = meta["correspondents"].find { |c| c["role"] == "sent" }
      assert_equal({ "role" => "sent", "name" => "Rautenstein, Johann Ernst von", "key" => "Rautenstein",
                     "gnd" => "https://d-nb.info/gnd/124058698", "birth" => "1623", "death" => "1666" }, sender)
      assert_nil doc("MAIN_u3w_qlm_zdb").metadata["author"], "an anonymous sender (NN) names no one"
    end

    def test_the_kind_label_rides_document_type
      assert_equal "Brief", doc("MAIN_ckw_qlm_zdb").metadata["document_type"]
      assert_equal "Briefexzerpt", doc("MAIN_u3w_qlm_zdb").metadata["document_type"]
    end

    def test_header_fields_ride_the_metadata
      meta = doc("MAIN_ckw_qlm_zdb").metadata
      assert_equal "https://sozinianer.de/id/MAIN_ckw_qlm_zdb", meta["url"]
      assert_includes meta["editorial_status"], "Transkription publikationsbereit"
      assert_equal ["lat"], meta["languages"]
      assert doc("MAIN_ckw_qlm_zdb").title.start_with?("Johann Ernst von Rautenstein (Regensburg) an Stanisław")
    end

    def test_the_language_code_normalizer
      assert_equal "lat", ADAPTER.language_code("lat")
      assert_equal "nld", ADAPTER.language_code("Niederländisch")
      assert_nil ADAPTER.language_code("")
      assert_nil ADAPTER.language_code(nil)
    end

    def test_the_lect_resolves_through_the_registry
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"))
      refute_nil lects.resolve("lat", source: "socinian-letters")
      assert_equal "fr", lects.resolve("fra", source: "socinian-letters")
    end

    def test_registry_row_is_wired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["socinian-letters"]
      refute_nil entry
      assert_equal ADAPTER, entry.adapter_class
      assert entry.wired, "first real sync verified (1,869 docs / 18,067 passages)"
      assert_equal "manual", entry.sync_policy
    end

    # -- fetch: ZipFetch + FileFetch (WebMock only) -----------------------------------

    def test_fetch_unpacks_the_letters_zip_and_lands_the_register
      stub_request(:get, ZIP_URL).to_return(status: 200, body: zip_body)
      stub_request(:get, INDICES_URL).to_return(status: 200, body: File.read(File.join(FIXTURES, "data", "csv",
                                                                                       "indices.csv")))
      Dir.mktmpdir do |workdir|
        report = conformance_adapter.fetch(workdir)
        assert_instance_of Nabu::FetchReport, report
        assert_equal(ACCEPTED.map { |id| "#{URN}:#{id}" }, conformance_adapter.discover(workdir).map(&:id))
        assert conformance_adapter.discovery_skips(workdir).clean?
        assert File.file?(File.join(workdir, "data", "csv", "indices.csv"))
      end
    end

    def test_fetch_wraps_http_failure
      stub_request(:get, ZIP_URL).to_return(status: 500)
      stub_request(:get, INDICES_URL).to_return(status: 200, body: "sbw_id\n")
      Dir.mktmpdir { |workdir| assert_raises(Nabu::FetchError) { conformance_adapter.fetch(workdir) } }
    end

    def test_the_probe_heads_both_artifacts
      assert_equal :http_zip, ADAPTER.remote_probe_strategy
      assert_equal [ZIP_URL, INDICES_URL], ADAPTER.http_probe_targets.map(&:zip_url)
    end

    private

    # The GitLab folder archive's shape: one top directory
    # csv-data-dump-main-data-xml-letters/ holding data/xml/letters/.
    def zip_body
      Dir.mktmpdir do |dir|
        top = File.join(dir, "csv-data-dump-main-data-xml-letters", "data", "xml")
        FileUtils.mkdir_p(top)
        FileUtils.cp_r(LETTERS, top)
        zip_path = File.join(dir, "letters.zip")
        Nabu::Shell.run("zip", "-q", "-r", zip_path, "csv-data-dump-main-data-xml-letters", chdir: dir)
        return File.binread(zip_path)
      end
    end
  end
end
