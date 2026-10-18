# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::DharmaDeccan (P118-2): the DHARMA Task Force B estate —
# every inscription-edition `tfb-*` repo on github.com/erc-dharma composed
# into ONE source (EIAD, Kanaganahalli, Early Western Deccan, Ollett's
# Sātavāhana data, Telugu, Kalyāṇa and Vengī Cālukya, Maitraka, Bengal,
# Dakṣiṇa Kosala, Somavaṁśin, Bādāmi and the smalls), each repo GitFetched
# into canonical/dharma-deccan/<repo>/.
#
# Fixtures (whole real files, 2026-10-11; see the fixture README): EIAD 1
# (pra-Latn prose), Ollett's Am499 (licence-less, dated, placed) and N10
# (in-file CC BY 3.0, a commentary div nested INSIDE the edition), Telugu
# 48 (tel-Latn), Kalyāṇa Cālukya 1004 (kan-Latn prose + san-Latn anuṣṭubh
# verse), Vengī Cālukya 99 (the multi-face plates) with the repo's own
# metadata TSV trimmed to its row.
class DharmaDeccanTest < Minitest::Test
  include AdapterConformance

  SLUG = "dharma-deccan"
  EIAD1 = "urn:nabu:dharma-deccan:INSEIAD00001"
  AM499 = "urn:nabu:dharma-deccan:Am499"
  N10 = "urn:nabu:dharma-deccan:N10"
  TEL48 = "urn:nabu:dharma-deccan:INSTelugu00048"
  KC1004 = "urn:nabu:dharma-deccan:INSKalyanaCalukya01004"
  VC99 = "urn:nabu:dharma-deccan:INSVengiCalukya00099"

  def conformance_adapter = Nabu::Adapters::DharmaDeccan.new

  def conformance_workdir = Nabu::TestSupport.fixtures(SLUG)

  def conformance_expected_source_id = SLUG

  def adapter = conformance_adapter

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  def parsed(urn) = adapter.parse(ref_for(urn))

  def passage(document, key)
    document.passages.find { |p| p.urn == "#{document.urn}:#{key}" } || flunk("no passage #{key}")
  end

  # -- manifest / registry ----------------------------------------------------

  def test_manifest_is_attribution_on_the_dharma_epidoc_family
    manifest = Nabu::Adapters::DharmaDeccan.manifest
    assert_equal SLUG, manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "dharma-epidoc", manifest.parser_family
    assert_match(/DHARMA/, manifest.credit)
    assert_match(/Ollett/, manifest.credit, "the Sātavāhana data's own author is credited")
  end

  def test_the_repo_roster_is_the_censused_tfb_inscription_estate
    repos = Nabu::Adapters::DharmaDeccan::REPOS.keys
    assert_equal 20, repos.size, "the 2026-10-11 live census: 20 edition-bearing tfb-* repos"
    assert(repos.all? { |name| name.start_with?("tfb-") })
    refute_includes repos, "tfb-ec-epigraphy", "Epigraphia Carnatica volumes are out of scope"
    %w[tfb-gangaeast-epigraphy tfb-licchavi-epigraphy tfb-rastrakuta-epigraphy
       tfb-visnukundin-epigraphy].each do |empty|
      refute_includes repos, empty, "#{empty} carries no edition XML yet (censused, not fetched)"
    end
    assert_equal repos.sort, repos, "alphabetical, so the fetch order is stable"
  end

  def test_upstream_repo_urls_list_every_repo_for_the_remote_probe
    urls = Nabu::Adapters::DharmaDeccan.upstream_repo_urls
    assert_equal 20, urls.size
    assert_includes urls, "https://github.com/erc-dharma/tfb-satavahana-epigraphy"
  end

  def test_the_vengi_metadata_tsv_rides_the_sparse_cone
    cone = adapter.send(:sparse_paths, "tfb-vengicalukya-epigraphy")
    assert_includes cone, "xml"
    assert_includes cone, "DHARMA_mdt_VengiCalukya_v01 - Text.tsv"
    assert_includes cone, "LICENCE.txt"
    assert_nil adapter.send(:sparse_paths, "tfb-tunga-epigraphy"),
               "root-layout repos (editions at the repo root) clone whole — a cone of named " \
               "dirs would materialize nothing (the dharma-pyu first-sync lesson)"
  end

  # -- discover ---------------------------------------------------------------

  def test_discover_yields_one_ref_per_edition_across_repos_sorted
    refs = adapter.discover(workdir).to_a
    assert_equal [AM499, EIAD1, KC1004, TEL48, VC99, N10], refs.map(&:id),
                 "urn:nabu:dharma-deccan:<stem sans DHARMA_>, sorted across repos"
    assert_equal "tfb-satavahana-epigraphy", refs.first.metadata["repo"]
    assert(refs.all? { |ref| ref.source_id == SLUG })
  end

  def test_non_edition_xml_is_censused_never_silently_dropped
    Dir.mktmpdir do |dir|
      eiad = File.join(dir, "tfb-eiad-epigraphy", "texts", "xml")
      ollett = File.join(dir, "tfb-satavahana-epigraphy", "satavahana-inscriptions-data_Ollett")
      FileUtils.mkdir_p([eiad, ollett])
      FileUtils.cp(File.join(workdir, "tfb-eiad-epigraphy/texts/xml/DHARMA_INSEIAD00001.xml"), eiad)
      FileUtils.cp(File.join(workdir, "tfb-eiad-epigraphy/texts/xml/DHARMA_INSEIAD00001.xml"),
                   File.join(eiad, "DHARMA_INSEIAD00001-test.xml"))
      File.write(File.join(eiad, "DHARMA_encodingTemplateInscription_v03.xml"), "<TEI/>")
      File.write(File.join(ollett, "schemas.xml"), "<locatingRules/>")
      assert_equal ["urn:nabu:dharma-deccan:INSEIAD00001"], adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 3, skips.skipped_by_rule
      notes = skips.notes.join(" ")
      assert_match(/INSEIAD00001-test/, notes, "upstream's -test working copy is censused")
      assert_match(/schemas\.xml/, notes)
    end
  end

  def test_multi_part_eiad_stems_are_editions
    Dir.mktmpdir do |dir|
      eiad = File.join(dir, "tfb-eiad-epigraphy", "texts", "xml")
      FileUtils.mkdir_p(eiad)
      FileUtils.cp(File.join(workdir, "tfb-eiad-epigraphy/texts/xml/DHARMA_INSEIAD00001.xml"),
                   File.join(eiad, "DHARMA_INSEIAD00128-A.xml"))
      assert_equal ["urn:nabu:dharma-deccan:INSEIAD00128-A"], adapter.discover(dir).map(&:id),
                   "EIAD 50-1/2/3 and 128-A/B are the parts of real multi-part inscriptions"
    end
  end

  def test_a_cross_repo_stem_collision_keeps_the_first_and_is_censused
    Dir.mktmpdir do |dir|
      %w[tfb-telugu-epigraphy/texts tfb-vengicalukya-epigraphy/xml].each do |sub|
        FileUtils.mkdir_p(File.join(dir, sub))
        FileUtils.cp(File.join(workdir, "tfb-telugu-epigraphy/texts/DHARMA_INSTelugu00048.xml"),
                     File.join(dir, sub))
      end
      refs = adapter.discover(dir).to_a
      assert_equal [TEL48], refs.map(&:id), "one urn, never two documents claiming it"
      assert_equal "tfb-telugu-epigraphy", refs.first.metadata["repo"], "repo order decides"
      assert_match(/collision/, adapter.discovery_skips(dir).notes.join(" "))
    end
  end

  # -- EIAD: Prakrit prose ----------------------------------------------------

  def test_eiad1_is_prakrit_prose_at_line_grain
    document = parsed(EIAD1)
    assert_equal "pra-Latn", document.language
    assert_match(/\AEIAD 1\. Octagonal pillar from Nagarjunakonda/, document.title)
    assert_equal "namo bhagavato Agapogalasa", passage(document, "1").text
    assert_equal "takaṁṇṇisa sava 6 gipa 4 diva vesa", passage(document, "3").text,
                 "<num> keeps its text; break=\"no\" still ends the physical line"
  end

  def test_eiad1_records_the_dharma_grant_and_the_source_editions_grant
    metadata = parsed(EIAD1).metadata
    assert_equal "https://creativecommons.org/licenses/by-sa/4.0/", metadata["license"],
                 "the DHARMA file's own <licence> governs, verbatim"
    assert_equal "in-file", metadata["license_basis"]
    assert_equal "http://creativecommons.org/licenses/by/3.0/", metadata["license_source_edition"],
                 "the 2017 EIAD edition's CC BY 3.0 grant rides as provenance"
    assert_equal "tfb-eiad-epigraphy", metadata["repo"]
    assert_equal ["Arlo Griffiths", "Vincent Tournier"], metadata["editors"]
  end

  # -- Sātavāhana (Ollett): licence-less, dated, placed ------------------------

  def test_am499_falls_back_on_the_repo_licence_recorded_as_such
    metadata = parsed(AM499).metadata
    assert_equal "https://creativecommons.org/licenses/by/4.0/", metadata["license"]
    assert_equal "repo LICENCE.txt (CC BY 4.0; no in-file <licence>)", metadata["license_basis"],
                 "the fallback is recorded per document — never silent"
  end

  def test_am499_mines_origdate_and_origplace
    document = parsed(AM499)
    assert_equal "pra-Latn", document.language
    assert_equal "nāgabu", document.passages.first.text
    date = document.metadata["date"]
    assert_equal 100, date["not_before"]
    assert_equal 200, date["not_after"]
    assert_equal "ca. 2nd century CE", date["raw"]
    assert_equal "medium", date["precision"]
    assert_equal "Amarāvatī", document.metadata["place"], "the findspot placeName"
    assert_equal "pl:Dhānyakaṭaka", document.metadata["place_key"]
    assert_match(/\AAmarāvatī, on the reversed \(unpolished\) side of a big slab\.\z/,
                 document.metadata["orig_place_text"])
  end

  def test_n10_carries_its_own_cc_by_3_licence
    metadata = parsed(N10).metadata
    assert_equal "http://creativecommons.org/licenses/by/3.0/", metadata["license"]
    assert_equal "in-file", metadata["license_basis"]
    assert_equal({ "not_before" => 60, "not_after" => 84, "raw" => "ca. 60–84 CE",
                   "precision" => "medium" }, metadata["date"])
    assert_equal "Nasik", metadata["place"]
    assert_nil metadata["editors"], "N10's titleStmt names no editor — nothing invented"
  end

  def test_n10_commentary_nested_inside_the_edition_never_mints
    document = parsed(N10)
    assert_equal "san-Latn", document.language
    refute(document.passages.any? { |p| p.text.include?("This edition is based on") },
           "Ollett's <div type=\"commentary\"> sits INSIDE 26 editions; English prose " \
           "must not mint as a Sanskrit passage")
    assert passage(document, "1").text.start_with?("siddhaṃ rājñaḥ kṣaharātasya")
  end

  # -- inline names (the donor/king/village layer) -----------------------------

  def test_n10_inline_names_ride_the_entities_annotation_with_their_keys
    line = passage(parsed(N10), "1")

    assert_equal [
      { "type" => "person", "text" => "nahapānasya", "key" => "pers:Nahapāna" },
      { "type" => "person", "text" => "dīnīka", "key" => "pers:Dīnīka" },
      { "type" => "person", "text" => "uṣavadātena", "key" => "pers:Uṣavadāta" },
      { "type" => "place", "text" => "bārṇāsāyāṃ", "key" => "pl:Bārṇāsā" }
    ], line.annotations["entities"]
    assert_includes line.text, "kṣatrapasya nahapānasya jāmātrā dīnīkaputreṇa uṣavadātena",
                    "the names stay read-through text"
  end

  def test_n10_a_name_reads_through_its_apparatus_like_the_text
    entities = passage(parsed(N10), "2").annotations["entities"]

    assert_includes entities, { "type" => "place", "text" => "piṃḍitakā", "key" => "pl:Piṃḍitakā" },
                    "app→lem inside the placeName, rdg dropped"
    assert_equal(2, entities.count { |e| e["key"] == "pl:Śūrpāraka" })
  end

  def test_the_family_parser_mines_names_only_for_adapters_that_opt_in
    plain = Nabu::Adapters::DharmaEpidocParser.parse(ref_for(N10).path, allowed_languages: %w[pra-Latn san-Latn])

    assert(plain.passages.all? { |unit| unit.entities.nil? },
           "the other DHARMA sources keep their passages unchanged")
  end

  def test_passages_without_inline_names_carry_no_entities_layer
    verse = passage(parsed(KC1004), "1.ab")

    refute verse.annotations.key?("entities")
  end

  # -- Telugu -----------------------------------------------------------------

  def test_telugu48_is_tel_latn
    document = parsed(TEL48)
    assert_equal "tel-Latn", document.language
    assert_equal "kuṁdu kāmāyiguḍi", document.passages.first.text
    assert_equal "DHARMA_INSTelugu00048", document.title,
                 "upstream's empty title (a template comment) falls back on the stem"
  end

  # -- Kannada + verse --------------------------------------------------------

  def test_kc1004_is_kannada_prose_with_sanskrit_verse
    document = parsed(KC1004)
    assert_equal "kan-Latn", document.language
    verse = passage(document, "1.ab")
    assert_equal "san-Latn", verse.language, "the invocation stanza is Sanskrit"
    assert_equal({ "met" => "anuṣṭubh" }, verse.annotations)
    assert_equal "namas tasmai varāhāya līlaya carate mahīṁ", verse.text
    assert_equal "kan-Latn", passage(document, "1").language
    assert_equal "83215", document.metadata["maturity"]
  end

  # -- Vengī Cālukya: plates + the repo's metadata TSV -------------------------

  def test_vc99_faces_and_the_tsv_date
    document = parsed(VC99)
    assert_equal "san-Latn", document.language
    assert_equal "Pithapuram plates (set 2) of Jayasiṁha I", document.title
    assert_equal "śrī-sarvvasiddhi", passage(document, "A.1").text
    assert_equal({ "not_before" => 641, "not_after" => 673, "raw" => "641-673",
                   "evidence" => "reign", "basis" => "DHARMA_mdt_VengiCalukya_v01 - Text.tsv" },
                 document.metadata["date"],
                 "the repo's own metadata table dates the text (its reign evidence verbatim)")
  end

  def test_the_timeline_reads_the_structured_date_shape
    assert_equal :structured, Nabu::Store::TimelineBuilder::MetadataDates::SHAPES[SLUG]
  end

  # -- defensive quarantines --------------------------------------------------

  def test_an_unallowed_language_quarantines_loudly
    with_synthetic(repo: "tfb-maitraka-epigraphy", dir: "xml-provisional", lang: "pra-Latn") do |ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/pra-Latn/, error.message, "Maitraka's measured set is san-Latn only")
    end
  end

  def test_upstream_tag_dirt_resolves_through_the_censused_aliases
    with_synthetic(repo: "tfb-eiad-epigraphy", dir: "texts/xml", lang: "pra-Brah") do |ref|
      assert_equal "pra-Latn", adapter.parse(ref).language,
                   "EIAD 57 tags a ROMANIZED edition pra-Brah — the held surface is Latin"
    end
  end

  def test_a_licence_less_file_in_a_repo_without_licence_txt_quarantines
    with_synthetic(repo: "tfb-tunga-epigraphy", dir: "", lang: "san-Latn", licence: false) do |ref|
      error = assert_raises(Nabu::ParseError) { adapter.parse(ref) }
      assert_match(/no licence/, error.message)
    end
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_clones_each_repo_into_its_own_subdir_with_per_repo_pins
    Dir.mktmpdir do |root|
      roster = {
        "tfb-eiad-epigraphy" => { dir: "texts/xml" },
        "tfb-tunga-epigraphy" => { dir: "" }
      }
      upstreams = roster.keys.to_h do |name|
        upstream = File.join(root, "upstream-#{name}")
        make_upstream(upstream, roster[name][:dir])
        [name, upstream]
      end
      deccan = fetch_adapter(roster, upstreams)
      work = File.join(root, "work")
      report = deccan.fetch(work)

      assert File.file?(File.join(work, "tfb-eiad-epigraphy", "texts", "xml", "DHARMA_INSX00001.xml"))
      refute File.exist?(File.join(work, "tfb-eiad-epigraphy", "diff")),
             "the sparse cone keeps upstream's diff/ working dirs out"
      assert File.file?(File.join(work, "tfb-tunga-epigraphy", "DHARMA_INSX00001.xml"))
      expected = upstreams.values.to_h { |up| [up, git(up, "rev-parse", "HEAD")] }
      assert_equal expected, report.repos
      assert_equal report.notes, deccan.fetch(work).notes, "the pull path reports the same pins"
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      deccan = fetch_adapter({ "tfb-eiad-epigraphy" => { dir: "texts/xml" } },
                             { "tfb-eiad-epigraphy" => File.join(root, "nope") })
      assert_raises(Nabu::FetchError) { deccan.fetch(File.join(root, "work")) }
    end
  end

  private

  def fetch_adapter(roster, upstreams)
    deccan = Nabu::Adapters::DharmaDeccan.new
    deccan.define_singleton_method(:repos) { roster }
    deccan.define_singleton_method(:repo_url) { |name| upstreams.fetch(name) }
    deccan
  end

  def make_upstream(dir, xml_dir)
    target = File.join(dir, xml_dir)
    FileUtils.mkdir_p([target, File.join(dir, "diff")])
    File.write(File.join(target, "DHARMA_INSX00001.xml"), "<TEI/>")
    File.write(File.join(dir, "diff", "old.xml"), "<TEI/>")
    File.write(File.join(dir, "README.md"), "readme\n")
    git(dir, "init", "-q")
    git(dir, "add", ".")
    git(dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end

  def with_synthetic(repo:, dir:, lang:, licence: true)
    Dir.mktmpdir do |root|
      target = File.join(root, repo, dir)
      FileUtils.mkdir_p(target)
      grant = ""
      if licence
        grant = '<availability><licence target="https://creativecommons.org/licenses/by-sa/4.0/">' \
                "CC BY-SA 4.0</licence></availability>"
      end
      File.write(File.join(target, "DHARMA_INSSynthetic00001.xml"), <<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <TEI xmlns="http://www.tei-c.org/ns/1.0">
          <teiHeader><fileDesc>
            <titleStmt><title>Synthetic quarantine probe</title></titleStmt>
            <publicationStmt>#{grant}</publicationStmt>
          </fileDesc></teiHeader>
          <text><body>
            <div type="edition" xml:lang="#{lang}"><p><lb n="1"/>real text here</p></div>
          </body></text>
        </TEI>
      XML
      yield adapter.discover(root).first || flunk("synthetic edition not discovered")
    end
  end
end
