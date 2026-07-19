# frozen_string_literal: true

require "test_helper"
require "support/adapter_conformance"
require "tmpdir"
require "fileutils"
require "json"

module Adapters
  # Nabu::Adapters::Cdli (P31-2): conformance + source specifics over the
  # trimmed real fixture slice (7 ATF blocks incl. a duplicated header, 12
  # catalog rows — 5 of them metadata-only artifacts; see
  # test/fixtures/cdli/README.md).
  class CdliTest < Minitest::Test
    include AdapterConformance

    FIXTURES = File.expand_path("../fixtures/cdli", __dir__)

    def conformance_adapter
      Nabu::Adapters::Cdli.new
    end

    def conformance_workdir
      FIXTURES
    end

    def conformance_expected_source_id
      "cdli"
    end

    # The universal-catalog shape: a catalog row without an ATF block (and
    # an uninscribed ATF block) parses to zero passages, marked honestly.
    def conformance_metadata_only?(document)
      document.metadata["text_layer"] == "none"
    end

    def adapter = conformance_adapter

    def refs
      adapter.discover(FIXTURES).to_a
    end

    def parse(urn)
      ref = refs.find { |r| r.id == urn }
      refute_nil ref, "no ref #{urn}"
      adapter.parse(ref)
    end

    # -- manifest -------------------------------------------------------------

    def test_manifest_carries_the_grant_verbatim
      manifest = Nabu::Adapters::Cdli.manifest
      assert_equal "attribution", manifest.license_class
      assert_includes manifest.license,
                      "Text in the pages of CDLI may be freely copied, aggregated and re-used"
      assert_equal "atf", manifest.parser_family
    end

    def test_urn_minting_is_one_rule
      assert_equal "urn:nabu:cdli:p000725", Nabu::Adapters::Cdli.urn_for("P000725")
      assert_equal "urn:nabu:cdli:p000725", Nabu::Adapters::Cdli.urn_for(725)
      assert_equal "urn:nabu:cdli:p519727", Nabu::Adapters::Cdli.urn_for("519727")
    end

    # -- discovery ------------------------------------------------------------

    def test_discover_yields_text_and_metadata_only_refs_sorted
      all = refs
      # 7 distinct ATF blocks (the P469841 duplicate collapses) + 5
      # catalog-only rows.
      assert_equal 12, all.size
      assert_equal all.map(&:id).sort, all.map(&:id)
      metadata_only, text = all.partition { |r| r.metadata["kind"] == "metadata_only" }
      assert_equal 7, text.size
      assert_equal 5, metadata_only.size
      assert(text.all? { |r| r.path.end_with?("cdliatf_unblocked.atf") })
      assert(metadata_only.all? { |r| r.path.end_with?("cdli_cat.csv") })
    end

    def test_duplicate_atf_headers_skip_by_rule_first_block_wins
      skips = adapter.discovery_skips(FIXTURES)
      assert_equal 1, skips.skipped_by_rule, "the second P469841 block is skipped by rule"
      assert_predicate skips, :clean?
      document = parse("urn:nabu:cdli:p469841")
      # The FIRST block ("Anonymous 469843") wins: its obverse has 5 lines.
      assert_equal "1(gesz2) 4(disz) 1/2(disz) gurusz u4 1(disz)-sze3",
                   document.passages.first.text
    end

    def test_lfs_pointer_files_discover_nothing_and_flag_loudly
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "cdli_cat.csv"), <<~POINTER)
          version https://git-lfs.github.com/spec/v1
          oid sha256:#{'2e' * 32}
          size 154768722
        POINTER
        assert_empty Nabu::Adapters::Cdli.new.discover(dir).to_a
        skips = Nabu::Adapters::Cdli.new.discovery_skips(dir)
        assert_equal 1, skips.unrecognized
        assert_match(/unmaterialized Git LFS pointer/, skips.notes.first)
      end
    end

    # -- text documents -------------------------------------------------------

    def test_p000725_joins_catalog_metadata_onto_the_atf_text
      document = parse("urn:nabu:cdli:p000725")
      assert_equal "qpc", document.language
      assert_equal "UET 2, 264", document.title
      assert_equal "ED I-II (ca. 2900-2700 BC)", document.metadata["period"]
      assert_equal "Ur (mod. Tell Muqayyar)", document.metadata["provenience"]
      facets = document.metadata["facets"]
      assert_equal "Lexical", facets["genre"]["value"]
      assert_equal "ED I-II (ca. 2900-2700 BC)", facets["period"]["value"]
      # >>A letter links resolved via the in-block definition → related.
      assert_includes document.metadata["related"], "urn:nabu:cdli:q000002"
      refute_empty document.passages
    end

    def test_catalog_language_fallback_when_atf_block_has_no_lang_line
      # P225015 carries neither an #atf lang line nor a catalog language
      # (the row's language column is empty) → und, honestly; the catalog
      # language fallback mechanics are pinned in AtfParserTest. P480562
      # has both — the #atf lang line wins and the catalog value rides.
      assert_equal "und", parse("urn:nabu:cdli:p225015").language
      weight = parse("urn:nabu:cdli:p480562")
      assert_equal "sux", weight.language
      assert_equal "Sumerian", weight.metadata["catalog_language"]
    end

    # -- metadata-only documents ----------------------------------------------

    def test_metadata_only_artifact_carries_facets_dates_and_concordances
      document = parse("urn:nabu:cdli:p104749")
      assert_equal 0, document.size
      assert_equal "none", document.metadata["text_layer"]
      assert_equal "sux", document.language
      assert_equal "BWAth 6, 49 15", document.title
      facets = document.metadata["facets"]
      assert_equal "Ur III (ca. 2100-2000 BC)", facets["period"]["value"]
      assert_equal "Umma (mod. Tell Jokha)", facets["provenience"]["value"]
      assert_equal "Amar-Suen", facets["ruler"]["value"]
      assert_equal ["bdtns:015946"], document.metadata["related"],
                   "the colon-schemed BDTNS concordance mints an edge target"
      assert_equal "Amar-Suen.01.04.00", document.metadata["dates_referenced"]
    end

    def test_language_mapping_is_honest_for_the_hard_catalog_values
      hittite = parse("urn:nabu:cdli:p282287")
      assert_equal "hit", hittite.language

      # "Akkadian; Persian; Elamite" — first language wins, verbatim kept.
      trilingual = parse("urn:nabu:cdli:p519993")
      assert_equal "akk", trilingual.language
      assert_equal "Akkadian; Persian; Elamite", trilingual.metadata["catalog_language"]

      # Proto-Elamite row: catalog language "undetermined" → und.
      proto = parse("urn:nabu:cdli:p008113")
      assert_equal "und", proto.language
      assert_equal "Proto-Elamite (ca. 3100-2900 BC)", proto.metadata["period"]

      # "fake (modern)" period rides verbatim; Ugaritic maps honestly.
      fake = parse("urn:nabu:cdli:p274853")
      assert_equal "uga", fake.language
      assert_equal "fake (modern)", fake.metadata["period"]
    end

    def test_ruler_facet_excludes_filler_heads
      cdli = Nabu::Adapters::Cdli.new
      assert_equal "Amar-Suen", cdli.send(:ruler_of, "Amar-Suen.01.04.00")
      assert_nil cdli.send(:ruler_of, "00.00.00.00")
      assert_nil cdli.send(:ruler_of, "--.--.00.00")
      assert_nil cdli.send(:ruler_of, "")
      assert_nil cdli.send(:ruler_of, nil)
    end

    # -- fetch (WebMock; no network ever) -------------------------------------

    def test_fetch_materializes_lfs_pointers_through_the_batch_api
      Dir.mktmpdir do |dir|
        upstream = File.join(dir, "upstream")
        payload = "&P000001 = TEST\n#atf: lang sux\n@tablet\n@obverse\n1. a-na\n"
        oid = Digest::SHA256.hexdigest(payload)
        pointer = "version https://git-lfs.github.com/spec/v1\n" \
                  "oid sha256:#{oid}\nsize #{payload.bytesize}\n"
        build_upstream_repo(upstream, "cdliatf_unblocked.atf" => pointer,
                                      "cdli_cat.csv" => tiny_catalog_csv)

        stub_request(:post, "https://github.com/cdli-gh/data.git/info/lfs/objects/batch")
          .to_return(status: 200, body: JSON.generate(
            objects: [{ oid: oid, size: payload.bytesize,
                        actions: { download: { href: "https://lfs.test/payload" } } }]
          ))
        stub_request(:get, "https://lfs.test/payload").to_return(status: 200, body: payload)

        workdir = File.join(dir, "canonical")
        adapter = clone_stubbed_adapter(upstream)
        report = adapter.fetch(workdir)
        assert_match(/cdliatf_unblocked\.atf=#{oid[0, 8]} \(#{payload.bytesize} B, downloaded\)/,
                     report.notes)
        # The committed (non-pointer) csv reads as already-materialized.
        assert_match(/cdli_cat\.csv present/, report.notes)
        assert_equal payload, File.read(File.join(workdir, "cdliatf_unblocked.atf"))
        # The materialized corpus discovers normally.
        refute_empty adapter.discover(workdir).to_a
      end
    end

    def test_fetch_wraps_lfs_verification_failure_as_fetch_error
      Dir.mktmpdir do |dir|
        upstream = File.join(dir, "upstream")
        pointer = "version https://git-lfs.github.com/spec/v1\n" \
                  "oid sha256:#{'ab' * 32}\nsize 5\n"
        build_upstream_repo(upstream, "cdliatf_unblocked.atf" => pointer,
                                      "cdli_cat.csv" => tiny_catalog_csv)
        stub_request(:post, "https://github.com/cdli-gh/data.git/info/lfs/objects/batch")
          .to_return(status: 200, body: JSON.generate(
            objects: [{ oid: "ab" * 32, size: 5,
                        actions: { download: { href: "https://lfs.test/payload" } } }]
          ))
        stub_request(:get, "https://lfs.test/payload")
          .to_return(status: 200, body: "WRONG")

        workdir = File.join(dir, "canonical")
        adapter = clone_stubbed_adapter(upstream)
        error = assert_raises(Nabu::FetchError) { adapter.fetch(workdir) }
        assert_match(/LFS payload verification failed/, error.message)
      end
    end

    private

    # An adapter whose git phase clones the local upstream repo (the LFS
    # phases under test run for real, against WebMock stubs).
    def clone_stubbed_adapter(upstream)
      adapter = Nabu::Adapters::Cdli.new
      adapter.define_singleton_method(:git_fetch!) do |workdir:, **_options|
        Nabu::Shell.run("git", "clone", "--quiet", upstream, workdir)
        Nabu::FetchReport.new(sha: "abc123", fetched_at: Time.now)
      end
      adapter
    end

    # A minimal catalog carrying the full required header (one blank row).
    def tiny_catalog_csv
      headers = Nabu::Adapters::Cdli::REQUIRED_HEADERS
      "#{headers.join(',')}\n1#{',' * (headers.size - 1)}\n"
    end

    def build_upstream_repo(dir, files)
      FileUtils.mkdir_p(dir)
      files.each { |name, content| File.write(File.join(dir, name), content) }
      Nabu::Shell.run("git", "-C", dir, "init", "--quiet")
      Nabu::Shell.run("git", "-C", dir, "add", ".")
      Nabu::Shell.run("git", "-C", dir, "-c", "user.email=t@t", "-c", "user.name=t",
                      "commit", "--quiet", "-m", "seed")
    end
  end
end
