# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Nabu::Adapters::DharmaTamil (P118-1): the DHARMA project's Tamil-country
# epigraphy — Task Force A's eleven tfa-* edition repos (github.com/
# erc-dharma), ~1,300 TEI editions composed through the held
# `dharma-epidoc` family. The first MULTI-REPO DHARMA source: one
# GitFetch per repo into canonical/dharma-tamil/<repo>/, sparse to the
# repo root's DHARMA_*.xml editions + README/LICENCE.
#
# Fixtures: four whole real files from four repos (retrieved 2026-10-11,
# see the fixture README) — a licence-less SII edition tagged bare
# "tam" (upstream tag dirt, aliased), a BY-SA French+Tamil Réunion
# temple pair of slabs, a BY-SA Tamil/Telugu/Sanskrit copper-plate grant
# carrying an anuṣṭubh verse, and a lang-less Cōḻa plate (an honest
# quarantine: no xml:lang anywhere in the edition). P120: a fifth whole
# file, a Grantha Sanskrit verse whose title pairs a regnal statement with
# a Śaka-era year ("time of Tammusiddhi, Śaka era, year 1129").
class DharmaTamilTest < Minitest::Test
  include AdapterConformance

  SII = "urn:nabu:dharma-tamil:INStfaSIIv06p0i0012"
  REUNION = "urn:nabu:dharma-tamil:INSTamilOutsideTN90002"
  GRANT = "urn:nabu:dharma-tamil:INSTiruvavatuturai00018"
  LANGLESS = "urn:nabu:dharma-tamil:INSTamilNadu01015"
  TAMMUSIDDHI = "urn:nabu:dharma-tamil:INSTamilNadu00011"
  CLEAN = [SII, REUNION, GRANT, TAMMUSIDDHI].freeze

  BY_SA = "https://creativecommons.org/licenses/by-sa/4.0/"

  # Two repos are enough to exercise the per-repo composition in the
  # fetch tests; the roster is narrowed through the repos seam.
  FETCH_REPOS = %w[tfa-pallava-epigraphy tfa-sii-epigraphy].freeze

  # The lang-less plate quarantines by design, so the conformance sweep
  # runs over the four clean fixtures (the nusantara pattern); the
  # quarantine is asserted on its own below.
  def conformance_adapter
    adapter = Nabu::Adapters::DharmaTamil.new
    original = adapter.method(:discover)
    adapter.define_singleton_method(:discover) do |workdir, &block|
      return enum_for(:discover, workdir) unless block

      original.call(workdir) { |ref| block.call(ref) if CLEAN.include?(ref.id) }
    end
    adapter
  end

  def conformance_workdir = Nabu::TestSupport.fixtures("dharma-tamil")

  def conformance_expected_source_id = "dharma-tamil"

  def adapter = Nabu::Adapters::DharmaTamil.new

  def workdir = conformance_workdir

  def ref_for(urn)
    adapter.discover(workdir).find { |ref| ref.id == urn } || flunk("no ref #{urn}")
  end

  # -- manifest + repo roster -------------------------------------------------

  def test_manifest_is_attribution_in_the_dharma_family
    manifest = Nabu::Adapters::DharmaTamil.manifest
    assert_equal "dharma-tamil", manifest.id
    assert_equal "attribution", manifest.license_class
    assert_equal "dharma-epidoc", manifest.parser_family
    assert_match(/DHARMA/, manifest.credit)
    assert_equal "https://github.com/erc-dharma", manifest.upstream_url
  end

  def test_the_roster_is_the_eleven_tamil_country_edition_repos
    repos = Nabu::Adapters::DharmaTamil::REPOS
    assert_equal 11, repos.size
    assert(repos.all? { |repo| repo.start_with?("tfa-") && repo.end_with?("-epigraphy") })
    assert_includes repos, "tfa-pallava-epigraphy"
    assert_includes repos, "tfa-sii-epigraphy"
    refute(repos.any? { |repo| repo.include?("south-indian-inscriptions") },
           "the separate south-indian-inscriptions repo is out of scope")
    assert_equal repos.map { |repo| "https://github.com/erc-dharma/#{repo}" },
                 Nabu::Adapters::DharmaTamil.upstream_repo_urls,
                 "the remote probe ls-remotes every repo, in roster order"
  end

  # -- discover ---------------------------------------------------------------

  def test_discover_spans_the_repo_subdirs
    refs = adapter.discover(workdir).to_a
    assert_equal [LANGLESS, TAMMUSIDDHI, REUNION, GRANT, SII].sort, refs.map(&:id).sort,
                 "urn:nabu:dharma-tamil:<stem sans DHARMA_>, one per edition across repos"
    assert(refs.all? { |ref| ref.source_id == "dharma-tamil" })
    assert_equal "tfa-sii-epigraphy", refs.find { |r| r.id == SII }.metadata["repo"]
  end

  def test_upstream_templates_and_drafts_are_censused_never_ingested
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "tfa-pallava-epigraphy")
      FileUtils.mkdir_p(repo)
      source = File.join(workdir, "tfa-sii-epigraphy", "DHARMA_INStfaSIIv06p0i0012.xml")
      FileUtils.cp(source, File.join(repo, "DHARMA_INSPallava00001.xml"))
      FileUtils.cp(source, File.join(repo, "DHARMA_INSPallava00000_template.xml"))
      FileUtils.cp(source, File.join(repo, "~DHARMA_INSPallava00002.xml"))
      assert_equal ["urn:nabu:dharma-tamil:INSPallava00001"], adapter.discover(dir).map(&:id)
      skips = adapter.discovery_skips(dir)
      assert_equal 2, skips.skipped_by_rule
      notes = skips.notes.join(" ")
      assert_match(/00000_template\.xml: upstream encoding template/, notes)
      assert_match(/~DHARMA_INSPallava00002\.xml: not a DHARMA_ edition file/, notes)
    end
  end

  # -- the licence-less SII edition: bare "tam", repo-level fallback ----------

  def test_licence_less_edition_records_the_repo_level_grant_verbatim
    document = adapter.parse(ref_for(SII))
    assert_equal "repo-level CC BY 4.0 (no in-file grant)", document.metadata["license"],
                 "no <licence> in the file: the repo LICENCE.txt grant, never silence"
  end

  def test_bare_tam_aliases_to_the_romanized_code
    document = adapter.parse(ref_for(SII))
    assert_equal "tam-Latn", document.language,
                 "upstream tags 5 editions bare \"tam\" over romanized text — tag dirt, aliased"
    assert(document.passages.all? { |p| p.language == "tam-Latn" })
    assert_equal "#{SII}:1", document.passages.first.urn
    assert_equal "kō-rājakesarivanmakku yāṇṭu 9 Āvatu Ārkkāṭṭu-k-kūṟṟattu brahmadeyam",
                 document.passages.first.text,
                 "a new <p> without its own <lb> continues the physical line (the family rule)"
    assert_equal 10, document.passages.size
  end

  def test_header_mining_editors_script_status_and_title_dating
    document = adapter.parse(ref_for(SII))
    metadata = document.metadata
    assert_equal ["Emmanuel Francis"], metadata["editors"]
    assert_equal "tfa-sii-epigraphy", metadata["corpus"]
    assert_equal "class:tamil maturity:vernacular", metadata["script_rendition"],
                 "the edition div's script classification, verbatim"
    assert_equal "draft", metadata["revision_status"]
    assert_equal ["time of Rājakesarivarman, year 9"], metadata["title_dating"],
                 "the title's attributed dating statement, verbatim"
    assert_nil metadata["date"], "a regnal year stays verbatim-only (no ruled regnal table)"
    assert_equal "Centalai, Sundareśvara temple, time of Rājakesarivarman, year 9", document.title
  end

  # -- the Réunion temple: BY-SA, French + Tamil textparts --------------------

  def test_reunion_is_multilingual_with_the_in_file_licence
    document = adapter.parse(ref_for(REUNION))
    assert_equal BY_SA, document.metadata["license"], "the in-file <licence target>, verbatim"
    assert_equal %w[fra-Latn tam-Latn], document.passages.map(&:language).uniq
    assert_equal "fra-Latn", document.language,
                 "lang-less edition div: the family falls back to the first lang-carrying textpart"
    slab_a = document.passages.find { |p| p.urn == "#{REUNION}:A.1" }
    slab_b = document.passages.find { |p| p.urn == "#{REUNION}:B.1" }
    assert_equal "PYRAMIDE", slab_a.text
    assert_equal "Inta kōpuram", slab_b.text
    assert_equal ["Emmanuel Francis", "Darlini Canabady Moutien"], document.metadata["editors"]
    refute document.metadata.key?("script_rendition"), "no rendition on the edition div itself"
    refute document.metadata.key?("revision_status"), "the change carries no @status"
  end

  # -- the Peruṅkāṭṭu grant: verse inside a Tamil/Telugu prose plate ----------

  def test_grant_carries_anustubh_verse_at_pada_grain
    document = adapter.parse(ref_for(GRANT))
    padas = document.passages.select { |p| p.annotations["met"] == "anuṣṭubh" }
    assert_equal 4, padas.size, "one passage per <l>, the lg's @met riding annotations"
    assert(padas.all? { |p| p.language == "san-Latn" })
    assert_equal "dānapālanayōr mmaddhyē", padas.first.text
    assert_includes document.passages.map(&:language), "tel-Latn",
                    "the Telugu lines of a Sētupati grant mint as tel-Latn"
    assert_equal ["Śaka year 1589"], document.metadata["title_dating"]
    assert_equal "83215", document.metadata["maturity"]
  end

  # -- the date lane: era-typed title years through config/eras.yml ---------

  def test_a_saka_title_year_converts_through_the_era_table
    date = adapter.parse(ref_for(GRANT)).metadata["date"]
    assert_equal({ "not_before" => 1667, "not_after" => 1667, "raw" => "Śaka year 1589",
                   "era" => "saka", "era_year" => 1589, "basis" => "title" }, date,
                 "Śaka Y + 78, the ruled single-valued row (width 0)")
  end

  def test_a_regnal_and_saka_title_dates_by_the_era_year_only
    metadata = adapter.parse(ref_for(TAMMUSIDDHI)).metadata
    assert_equal ["time of Tammusiddhi", "Śaka era, year 1129"], metadata["title_dating"],
                 "both statements ride verbatim, the Śaka-era spelling included"
    assert_equal 1207, metadata["date"]["not_before"]
    assert_equal 1207, metadata["date"]["not_after"]
    assert_equal "Śaka era, year 1129", metadata["date"]["raw"]
    assert_equal "san-Latn", adapter.parse(ref_for(TAMMUSIDDHI)).language
  end

  def test_era_date_helper_covers_the_censused_spellings
    date = ->(*phrases) { Nabu::Adapters::DharmaTamil.era_date(phrases) }
    assert_equal 1488, date.call("Śaka 1410")["not_before"]
    assert_equal 1729, date.call("śaka 1651")["not_before"], "the lowercase spelling"
    assert_equal 1449, date.call("year 1371 of the Śaka era")["not_before"]
    assert_equal({ "not_before" => 1778, "not_after" => 1779, "raw" => "Kollam year 954",
                   "era" => "kollam", "era_year" => 954, "basis" => "title" },
                 date.call("Kollam year 954"), "Kollam is era-typed too: the width-1 envelope")
    assert_equal 1393, date.call("time of Viruppaṇa", "Śaka year 1315")["not_before"]
    assert_nil date.call("time of Parāntaka I, year 36"), "regnal years stay verbatim-only"
    assert_nil date.call("time of Bhūti Vikramakesarin"), "a king's name is no era"
    assert_nil date.call("Śaka year 14??"), "an unreadable digit is no year"
  end

  def test_title_dating_records_every_censused_era_spelling_verbatim
    scan = ->(title) { title.scan(Nabu::Adapters::DharmaTamil::TITLE_DATING) }
    assert_equal ["Śaka 1410"], scan.call("Cīrkāḻi, Brahmapurīśvara, Śaka 1410")
    assert_equal ["śaka 1651"], scan.call("Ciṟupaṇaiyūr grant, śaka 1651")
    assert_equal ["year 1371 of the Śaka era"],
                 scan.call("Poṉṉamarāvati, no king, year 1371 of the Śaka era")
    assert_equal ["Kollam year 954"], scan.call("Cattūr grant, Kollam year 954")
    assert_equal ["time of Parāntaka I, year 36"],
                 scan.call("Mēlappaḻuvūr, Agastyeśvara temple, time of Parāntaka I, year 36")
  end

  def test_the_source_registers_in_the_metadata_dates_lane
    dates = Nabu::Store::TimelineBuilder::MetadataDates
    assert_equal :structured, dates::SHAPES["dharma-tamil"]
    refute_includes dates::COMPOSITION, "dharma-tamil", "an inscription's own year dates the object"
  end

  # -- quarantines ------------------------------------------------------------

  def test_a_lang_less_edition_quarantines_loudly
    error = assert_raises(Nabu::ParseError) { adapter.parse(ref_for(LANGLESS)) }
    assert_match(/unknown language code nil/, error.message,
                 "a multilingual corpus declares no default: no xml:lang, no claim")
  end

  def test_an_unclassified_code_quarantines_the_record
    Dir.mktmpdir do |dir|
      repo = File.join(dir, "tfa-sii-epigraphy")
      FileUtils.mkdir_p(repo)
      xml = File.read(File.join(workdir, "tfa-sii-epigraphy", "DHARMA_INStfaSIIv06p0i0012.xml"))
      File.write(File.join(repo, "DHARMA_INStfaSIIv06p0i0012.xml"),
                 xml.sub('xml:lang="tam"', 'xml:lang="kan-Latn"'))
      error = assert_raises(Nabu::ParseError) { adapter.parse(adapter.discover(dir).first) }
      assert_match(/kan-Latn/, error.message, "a code outside the measured census quarantines")
    end
  end

  # -- fetch (local git only, no network) -------------------------------------

  def test_fetch_sparse_clones_every_repo_into_its_own_subdir
    Dir.mktmpdir("nabu-dharma-tamil-fetch") do |root|
      upstreams = build_upstreams(root)
      work = File.join(root, "canonical")
      tamil = pointing_at(upstreams)

      report = tamil.fetch(work)

      assert_instance_of Nabu::FetchReport, report
      expected = upstreams.values.to_h { |up| [up, git(up, "rev-parse", "HEAD")] }
      assert_equal expected, report.repos, "one ledger pin per repo, keyed by repo url"
      upstreams.each_key do |repo|
        assert File.file?(File.join(work, repo, "DHARMA_INS#{repo_token(repo)}00001.xml"))
        assert File.file?(File.join(work, repo, "LICENCE.txt")), "the repo grant rides the cone"
        refute File.exist?(File.join(work, repo, "~DHARMA_INS#{repo_token(repo)}00002.xml")),
               "upstream drafts (~DHARMA_) stay outside the cone"
        refute File.exist?(File.join(work, repo, "sii-corpus")),
               "non-edition subtrees (the SII OCR volumes) stay outside the cone"
      end
      assert_equal upstreams.size, tamil.discover(work).count
      assert_equal report.repos, tamil.fetch(work).repos, "second call: the pull path"
    end
  end

  def test_fetch_wraps_shell_failure_in_fetch_error
    Dir.mktmpdir do |root|
      tamil = pointing_at(Hash.new(File.join(root, "does-not-exist")))
      assert_raises(Nabu::FetchError) { tamil.fetch(File.join(root, "work")) }
    end
  end

  private

  def build_upstreams(root)
    source = File.read(File.join(workdir, "tfa-sii-epigraphy", "DHARMA_INStfaSIIv06p0i0012.xml"))
    FETCH_REPOS.to_h do |repo|
      upstream = File.join(root, "upstream-#{repo}")
      FileUtils.mkdir_p(File.join(upstream, "sii-corpus"))
      Nabu::Shell.run("git", "init", "-q", upstream)
      token = repo_token(repo)
      File.write(File.join(upstream, "DHARMA_INS#{token}00001.xml"), source)
      File.write(File.join(upstream, "~DHARMA_INS#{token}00002.xml"), source)
      File.write(File.join(upstream, "sii-corpus", "DHARMA_INSSII01.xml"), "<doc/>")
      File.write(File.join(upstream, "README.md"), "readme")
      File.write(File.join(upstream, "LICENCE.txt"), "Attribution 4.0 International")
      git(upstream, "add", ".")
      git(upstream, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "seed")
      [repo, upstream]
    end
  end

  def repo_token(repo) = repo == "tfa-pallava-epigraphy" ? "Pallava" : "tfaSIIv"

  def pointing_at(upstreams)
    tamil = Nabu::Adapters::DharmaTamil.new
    repos = upstreams.is_a?(Hash) && !upstreams.empty? ? upstreams.keys : FETCH_REPOS
    tamil.define_singleton_method(:repos) { repos }
    tamil.define_singleton_method(:repo_url_for) { |repo| upstreams[repo] }
    tamil
  end

  def git(dir, *)
    Nabu::Shell.run("git", "-C", dir, *).strip
  end
end
