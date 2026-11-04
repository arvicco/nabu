# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/adapter_conformance"

module Adapters
  # ponomar — the Church Slavonic service texts of the Ponomar liturgics
  # suite (github.com/typiconman/ponomar, GPL-3.0): the Hours-assembly
  # kit under Ponomar/languages/cu/xml/Services/, one text per file.
  # Fixture: six accepted files + one real specimen per rejected grain
  # (README.md).
  class PonomarTest < Minitest::Test
    include AdapterConformance

    FIXTURES = Nabu::TestSupport.fixtures("ponomar")
    SERVICES = File.join(FIXTURES, Nabu::Adapters::Ponomar::SERVICES_DIR)
    URN = "urn:nabu:ponomar:cu"

    def conformance_adapter = Nabu::Adapters::Ponomar.new
    def conformance_workdir = FIXTURES
    def conformance_expected_source_id = "ponomar"

    def documents
      @documents ||= conformance_adapter.discover(FIXTURES).map { |ref| conformance_adapter.parse(ref) }
    end

    def doc(stem) = documents.find { |d| d.urn == "#{URN}:#{stem}" } || flunk("#{stem} missing")

    # A copy of the fixture tree to mutate.
    def landed_tree
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(File.join(FIXTURES, "Ponomar"), dir)
        yield dir, File.join(dir, Nabu::Adapters::Ponomar::SERVICES_DIR)
      end
    end

    def test_discovers_the_text_bearing_files_in_path_order
      assert_equal %w[Command.Bow CommonPrayers.KONTAKION.FRI5 CommonPrayers.NiceneCreed CommonPrayers.SufferingLord
                      CommonPrayers.TROPARION.TUES7 Text.ThirdHour].map { |s| "#{URN}:#{s}" },
                   conformance_adapter.discover(FIXTURES).map(&:id)
    end

    def test_the_rejected_grains_skip_by_rule
      skips = conformance_adapter.discovery_skips(FIXTURES)
      assert skips.clean?
      assert_equal 7, skips.skipped_by_rule
      notes = skips.notes.join("\n")
      assert_match %r{CommonPrayers/Ending\.xml: .*no text}, notes
      assert_match %r{CommonPrayers/Template\.xml: .*placeholder}, notes
      assert_match %r{Text/ThirdSource\.xml: .*source credit}, notes
      assert_match %r{Text/Third1\.xml: .*caption}, notes
      assert_match %r{Var/PKath3\.xml: .*template}, notes
      assert_match %r{Var/STYX61C\.xml: .*template}, notes
      assert_match %r{Octoecheos/Tone 1/Monday\.xml: .*schedule}, notes
    end

    def test_accepted_plus_skipped_account_for_every_file_in_the_tree
      files = Dir.glob(File.join(SERVICES, "**", "*")).count { |path| File.file?(path) }
      accepted = conformance_adapter.discover(FIXTURES).count
      assert_equal files, accepted + conformance_adapter.discovery_skips(FIXTURES).skipped_by_rule
    end

    def test_an_unknown_root_or_a_non_xml_file_is_unrecognized
      landed_tree do |dir, services|
        File.write(File.join(services, "Var", "notes.txt"), "?")
        File.write(File.join(services, "Var", "Odd.xml"), "<MENU><ITEM/></MENU>")
        skips = conformance_adapter.discovery_skips(dir)
        refute skips.clean?
        assert_equal 2, skips.unrecognized
        assert_equal 6, conformance_adapter.discover(dir).count, "unrecognized files are never yielded"
      end
    end

    def test_one_text_one_passage_with_wrapped_lines_rejoined
      creed = doc("CommonPrayers.NiceneCreed")
      assert_equal ["#{URN}:CommonPrayers.NiceneCreed:1"], creed.passages.map(&:urn)
      text = creed.passages.first.text
      assert text.start_with?("Вѣ́рꙋю во є҆ди́наго бг҃а ѻ҆ц҃а̀ вседержи́телѧ, творца̀ нб҃ꙋ и҆ землѝ")
      assert text.end_with?("Ча́ю воскрⷭ҇нїѧ ме́ртвыхъ. И҆ жи́зни бꙋ́дꙋщагѡ вѣ́ка, а҆ми́нь.")
      refute_match(/\s{2}|\n/, text, "upstream hard-wraps are layout, collapsed to single spaces")
      assert_equal "chu", creed.language
      assert_equal "chu", creed.passages.first.language
      assert_equal(6, documents.sum { |d| d.passages.size })
    end

    # Regression (real bytes): TUES7 ships a UTF-8 BOM and decomposed
    # и + U+0300 (and і + U+0308); NFC at the boundary composes them.
    def test_bom_and_decomposed_marks_are_normalized_at_the_boundary
      raw = File.binread(File.join(SERVICES, "CommonPrayers", "TROPARION", "TUES7.xml")).force_encoding("UTF-8")
      assert raw.start_with?("﻿")
      assert_includes raw, "є҆сѝ"
      text = doc("CommonPrayers.TROPARION.TUES7").passages.first.text
      assert_includes text, "є҆сѝ"
      refute_includes text, "ѝ"
      assert_includes text, "Па́мѧть првⷣнагѡ съ похвала́ми"
    end

    def test_the_header_is_the_title_and_the_liturgical_fields_are_mined
      troparion = doc("CommonPrayers.TROPARION.TUES7")
      assert_equal "Тропа́рь прⷣте́чи, гла́съ в҃", troparion.title
      meta = troparion.metadata
      assert_equal "TROPARION", meta["service_part"]
      assert_equal "Tuesday", meta["weekday"]
      assert_equal 7, meta["octoechos_tone"], "the file name's digit: the week of the Octoechos cycle"
      assert_equal 2, meta["tone"], "the header's own гла́съ в҃"
      assert_equal "CommonPrayers/TROPARION/TUES7.xml", meta["upstream_path"]
      assert_equal "TUES7", meta["upstream_name"]

      kontakion = doc("CommonPrayers.KONTAKION.FRI5").metadata
      assert_equal "KONTAKION", kontakion["service_part"]
      assert_equal ["Friday", 5, 4], kontakion.values_at("weekday", "octoechos_tone", "tone")
      assert_equal ["This is an archaic version of the Troparion as it commemorates the Emperor."],
                   kontakion["upstream_comments"]
    end

    def test_a_headerless_text_is_titled_by_its_incipit
      assert_equal "Ча́съ тре́тїй", doc("Text.ThirdHour").title
      assert_equal "Text", doc("Text.ThirdHour").metadata["service_part"]
      assert_equal "покло́нъ", doc("Command.Bow").title
      assert_equal "Command", doc("Command.Bow").metadata["service_part"]
      assert_equal "Вѣ́рꙋю во є҆ди́наго бг҃а ѻ҆ц҃а̀ вседержи́телѧ,…",
                   Nabu::Adapters::Ponomar.incipit(doc("CommonPrayers.NiceneCreed").passages.first.text)
    end

    def test_an_english_header_is_an_editorial_note_not_a_title
      suffering = doc("CommonPrayers.SufferingLord")
      assert_equal "Слава̀ стра́стїѧмъ твои̑мъ, гдⷭ҇и.", suffering.title
      assert_equal "This is not necessarily the correct spelling.", suffering.metadata["editorial_note"]
      assert_nil suffering.metadata["header"]
      assert_equal "CommonPrayers", suffering.metadata["service_part"]
    end

    def test_the_tone_numeral_reader
      assert_equal 1, Nabu::Adapters::Ponomar.tone("Тропа́рь, гла́съ а҃")
      assert_equal 6, Nabu::Adapters::Ponomar.tone("тропа́рь, гла́съ ѕ҃")
      assert_equal 8, Nabu::Adapters::Ponomar.tone("Конда́къ, гла́съ и҃")
      assert_nil Nabu::Adapters::Ponomar.tone("Мл҃тва ча̑съ")
    end

    def test_the_lect_resolves_to_new_church_slavonic
      lects = Nabu::Lects.load(Nabu::TestSupport.fixtures("nabu-lects"),
                               overrides_path: File.expand_path("../../config/lect_overrides.yml", __dir__))
      assert_equal "chu:ncs", lects.resolve("chu", source: "ponomar")
    end

    def test_registry_row_is_unwired_and_manual
      registry = Nabu::SourceRegistry.load(File.expand_path("../../config/sources.yml", __dir__))
      entry = registry["ponomar"]
      refute_nil entry
      assert_equal Nabu::Adapters::Ponomar, entry.adapter_class
      refute entry.wired, "wired: false until the first real sync is verified"
      assert_equal "manual", entry.sync_policy
    end

    def test_manifest_carries_the_gpl_and_the_copyleft_class
      manifest = Nabu::Adapters::Ponomar.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license, "GPL-3.0"
      assert_equal "https://github.com/typiconman/ponomar", manifest.upstream_url
      assert_empty Nabu::Adapters::Ponomar.materialized_paths
    end

    # -- fetch (local git only, no network) -------------------------------------

    def test_fetch_sparse_clones_only_the_services_cone
      Dir.mktmpdir("nabu-ponomar-fetch") do |root|
        upstream = File.join(root, "upstream")
        build_upstream_repo(upstream)
        work = File.join(root, "canonical")

        ponomar = conformance_adapter
        ponomar.define_singleton_method(:repo_url) { upstream }
        report = ponomar.fetch(work)

        assert_kind_of Nabu::FetchReport, report
        assert_match(/\A[0-9a-f]{40}\z/, report.sha)
        assert File.file?(File.join(work, Nabu::Adapters::Ponomar::SERVICES_DIR, "Command", "Bow.xml"))
        assert File.file?(File.join(work, "LICENSE")), "the GPL text is in the cone"
        refute File.exist?(File.join(work, "Ponomar", "languages", "cu", "xml", "lives")),
               "outside-cone paths (lives, other languages, images) must not materialize"
        assert_equal 6, ponomar.discover(work).count
      end
    end

    private

    # A local upstream repo carrying the fixture cone plus outside-cone
    # ballast the sparse fetch must not materialize.
    def build_upstream_repo(upstream)
      FileUtils.mkdir_p(upstream)
      git = ->(*args) { Nabu::Shell.run("git", "-C", upstream, *args) }
      Nabu::Shell.run("git", "init", "-q", upstream)
      FileUtils.cp_r(File.join(FIXTURES, "Ponomar"), upstream)
      File.write(File.join(upstream, "LICENSE"), "GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007\n")
      File.write(File.join(upstream, "README.md"), "Ponomar (in the cone)")
      lives = File.join(upstream, "Ponomar", "languages", "cu", "xml", "lives")
      FileUtils.mkdir_p(lives)
      File.write(File.join(lives, "010101.xml"), "<SAINT/>")
      git.call("add", ".")
      git.call("-c", "user.email=test@test", "-c", "user.name=test", "commit", "-q", "-m", "seed")
    end
  end
end
