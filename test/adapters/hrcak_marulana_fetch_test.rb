# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module Adapters
  # Nabu::Adapters::HrcakMarulanaFetch — the OAI harvest (oai_openaire +
  # oai_dc, resumptionToken paging) and the licensed records' PDFs. WebMock
  # only; the OAI bodies are real ListRecords responses trimmed to four
  # records (test/fixtures/hrcak-marulana/oai), the PDF bodies real fixture
  # PDFs.
  class HrcakMarulanaFetchTest < Minitest::Test
    FIXTURES = Nabu::TestSupport.fixtures("hrcak-marulana")
    KLASS = Nabu::Adapters::HrcakMarulanaFetch
    TOKENS = { "oai_openaire" => "1795645779438_oai_openaire", "oai_dc" => "1795646479470_oai_dc" }.freeze
    # Every PDF the four trimmed records list; 277999 (InC) lists 402578.
    PDFS = { "1309" => "15232", "12183" => "12183", "12184" => "12184", "402550" => "402550" }.freeze

    def fixture(path) = File.binread(File.join(FIXTURES, path))

    def stub_oai
      KLASS::PREFIXES.each do |prefix|
        stub_request(:get, KLASS.list_url(prefix)).to_return(status: 200, body: fixture("oai/#{prefix}-1.xml"))
        stub_request(:get, KLASS.resume_url(TOKENS.fetch(prefix)))
          .to_return(status: 200, body: fixture("oai/#{prefix}-2.xml"))
      end
    end

    def stub_pdfs(except: [])
      PDFS.each do |id, fixture_id|
        next if except.include?(id)

        stub_request(:get, "https://hrcak.srce.hr/file/#{id}")
          .to_return(status: 200, body: fixture("files/#{fixture_id}.pdf"))
      end
    end

    def sync(dir) = KLASS.sync!(dir: dir, delay: 0, rate_limit_pause: 0)

    def test_harvests_both_formats_through_the_resumption_token_and_holds_each_record_alone
      stub_oai
      stub_pdfs
      Dir.mktmpdir do |dir|
        result = sync(dir)
        assert_equal 4, result.records
        assert_equal 8, result.records_written
        assert_equal %w[277980 277999 641 8030],
                     Dir.children(File.join(dir, "records")).map { |n| n[/\A\d+/] }.uniq.sort
        assert_equal fixture("records/8030.oai_openaire.xml"),
                     File.binread(KLASS.record_path(dir, "8030", "oai_openaire"))
        assert_equal fixture("records/277999.oai_dc.xml"), File.binread(KLASS.record_path(dir, "277999", "oai_dc"))
        assert_match(/\A\h{64}\z/, result.sha)
      end
    end

    def test_fetches_the_licensed_records_pdfs_and_never_an_in_copyright_one
      stub_oai
      stub_pdfs
      Dir.mktmpdir do |dir|
        result = sync(dir)
        assert_equal [4, 4, 1], [result.pdfs_fetched, result.pdfs_held, result.gated]
        assert_empty result.failed
        assert_equal fixture("files/12184.pdf"), File.binread(KLASS.pdf_path(dir, "12184"))
        assert_not_requested :get, "https://hrcak.srce.hr/file/402578"
      end
    end

    def test_a_second_sync_rewrites_nothing_and_requests_no_held_pdf
      stub_oai
      stub_pdfs
      Dir.mktmpdir do |dir|
        first = sync(dir)
        WebMock.reset!
        stub_oai
        second = sync(dir)
        assert_equal [0, 0, 4], [second.records_written, second.pdfs_fetched, second.pdfs_held]
        assert_equal first.sha, second.sha
        assert_not_requested :get, %r{/file/}
      end
    end

    def test_a_challenge_or_non_pdf_body_is_a_failed_file_and_the_rest_lands
      stub_oai
      stub_pdfs(except: %w[12183 12184])
      stub_request(:get, "https://hrcak.srce.hr/file/12183").to_return(status: 418, body: "Confirm you're not a robot")
      stub_request(:get, "https://hrcak.srce.hr/file/12184").to_return(status: 200, body: "<html>not a pdf</html>")
      Dir.mktmpdir do |dir|
        result = sync(dir)
        assert_equal %w[8030/12183 8030/12184], result.failed
        assert_equal 2, result.pdfs_held
        refute File.exist?(KLASS.pdf_path(dir, "12184"))
      end
    end

    def test_a_rate_limited_request_backs_off_and_retries
      stub_oai
      stub_pdfs(except: %w[1309])
      stub_request(:get, "https://hrcak.srce.hr/file/1309")
        .to_return({ status: 429 }, { status: 200, body: fixture("files/15232.pdf") })
      Dir.mktmpdir do |dir|
        result = sync(dir)
        assert_empty result.failed
        assert_requested :get, "https://hrcak.srce.hr/file/1309", times: 2
      end
    end

    def test_a_failing_harvest_aborts_before_any_write
      stub_request(:get, KLASS.list_url("oai_openaire")).to_return(status: 500)
      Dir.mktmpdir do |dir|
        target = File.join(dir, "hrcak-marulana")
        assert_raises(KLASS::Error) { sync(target) }
        refute Dir.exist?(target)
      end
    end

    def test_an_oai_error_response_aborts
      stub_request(:get, KLASS.list_url("oai_openaire")).to_return(
        status: 200,
        body: '<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/"><error code="badResumptionToken">' \
              "expired</error></OAI-PMH>"
      )
      Dir.mktmpdir do |dir|
        error = assert_raises(KLASS::Error) { sync(dir) }
        assert_includes error.message, "badResumptionToken"
      end
    end

    def test_file_ids_come_only_from_the_portal_file_url
      assert_equal "12183", KLASS.file_id("https://hrcak.srce.hr/file/12183")
      assert_raises(KLASS::Error) { KLASS.file_id("https://hrcak.srce.hr/broj/304") }
    end
  end
end
