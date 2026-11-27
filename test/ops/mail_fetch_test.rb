# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "digest"
require "nabu/ops/mail_fetch"

module Ops
  # Nabu::Ops::MailFetch (`rake "mail:fetch[EMAIL_ID]"`): save one
  # message's attachments into the local intake folder over JMAP.
  #
  # The response shapes below are SPEC-DERIVED, not recorded: the Session
  # object follows RFC 8620 §2 (its example), the Email/get response and
  # the EmailBodyPart attachment rows RFC 8621 §4.1.4/§4.2, the download
  # endpoint RFC 8620 §6.2 — no download-capable token existed when this
  # was written, so no live response could be captured. Re-trim from a
  # real response once one is available.
  class MailFetchTest < Minitest::Test
    FETCH = Nabu::Ops::MailFetch
    TOKEN = "fmu1-test-token-never-printed"
    API = "https://api.fastmail.com/jmap/api/"
    ACCOUNT = "u1234abcd"
    EMAIL = "Mf3a9c1e2b"
    ZIP = "PK\x03\x04corpus-bytes".b
    CSV = "id,text\n1,a\n".b

    SESSION = {
      "capabilities" => { "urn:ietf:params:jmap:core" => { "maxSizeUpload" => 50_000_000 },
                          "urn:ietf:params:jmap:mail" => {} },
      "accounts" => { ACCOUNT => { "name" => "someone@example.com", "isPersonal" => true, "isReadOnly" => true,
                                   "accountCapabilities" => { "urn:ietf:params:jmap:mail" => {} } } },
      "primaryAccounts" => { "urn:ietf:params:jmap:mail" => ACCOUNT },
      "username" => "someone@example.com",
      "apiUrl" => API,
      "downloadUrl" => "https://www.fastmailusercontent.com/jmap/download/{accountId}/{blobId}/{name}?type={type}",
      "uploadUrl" => "https://api.fastmail.com/jmap/upload/{accountId}/",
      "eventSourceUrl" => "https://api.fastmail.com/jmap/event/",
      "state" => "cyrus-0;p-5"
    }.freeze

    def setup
      @dir = Dir.mktmpdir
      @inbox = File.join(@dir, ".docs", "inbox")
      @out = StringIO.new
    end

    def teardown
      FileUtils.remove_entry(@dir)
      super
    end

    def attachment(blob, name, type, size)
      { "blobId" => blob, "name" => name, "type" => type, "size" => size }
    end

    def stub_session(status: 200)
      stub_request(:get, FETCH::SESSION_URL)
        .with(headers: { "Authorization" => "Bearer #{TOKEN}" })
        .to_return(status: status, body: status == 200 ? JSON.generate(SESSION) : "Unauthorized")
    end

    def stub_email(attachments, not_found: [])
      list = not_found.empty? ? [{ "id" => EMAIL, "attachments" => attachments }] : []
      body = { "methodResponses" => [["Email/get", { "accountId" => ACCOUNT, "state" => "s1", "list" => list,
                                                     "notFound" => not_found }, "0"]],
               "sessionState" => "cyrus-0;p-5" }
      stub_request(:post, API).with(headers: { "Authorization" => "Bearer #{TOKEN}" })
                              .to_return(status: 200, body: JSON.generate(body),
                                         headers: { "Content-Type" => "application/json" })
    end

    def stub_blob(blob, name, type, bytes)
      url = "https://www.fastmailusercontent.com/jmap/download/#{ACCOUNT}/#{blob}/#{name}?type=#{type}"
      stub_request(:get, url).with(headers: { "Authorization" => "Bearer #{TOKEN}" })
                             .to_return(status: 200, body: bytes)
    end

    def two_attachments
      stub_session
      stub_email([attachment("Gzip1", "corpus.zip", "application/zip", ZIP.bytesize),
                  attachment("Gcsv2", "index list.csv", "text/csv", CSV.bytesize)])
      stub_blob("Gzip1", "corpus.zip", "application%2Fzip", ZIP)
      stub_blob("Gcsv2", "index%20list.csv", "text%2Fcsv", CSV)
    end

    def run_fetch(filter: nil)
      FETCH.new(token: TOKEN, inbox_dir: @inbox, log: @out).run(EMAIL, filter: filter)
    end

    def test_missing_token_names_the_key_and_the_file
      local = File.join(@dir, "local")
      FileUtils.mkdir_p(File.join(local, "config"))
      File.write(File.join(local, "config", "settings.yml"), YAML.dump("email" => { "token" => "other" }))
      error = assert_raises(FETCH::Error) { FETCH.token!(local_dir: local) }
      assert_match(/email\.download_token/, error.message)
      assert_includes error.message, File.join(local, "config", "settings.yml")
      refute_includes error.message, "other"
    end

    def test_the_token_is_read_from_the_settings_overlay
      local = File.join(@dir, "local")
      FileUtils.mkdir_p(File.join(local, "config"))
      File.write(File.join(local, "config", "settings.yml"), YAML.dump("email" => { "download_token" => TOKEN }))
      assert_equal TOKEN, FETCH.token!(local_dir: local)
    end

    def test_a_rejected_token_fails_without_printing_it
      stub_session(status: 401)
      error = assert_raises(FETCH::Error) { run_fetch }
      assert_match(/401/, error.message)
      refute_includes error.message + @out.string, TOKEN
      assert_not_requested :post, API
    end

    def test_an_email_with_two_attachments_saves_both_and_reports_size_and_sha
      two_attachments
      report = run_fetch
      assert report.ok?
      assert_equal ZIP, File.binread(File.join(@inbox, "corpus.zip"))
      assert_equal CSV, File.binread(File.join(@inbox, "index list.csv"))
      assert_includes @out.string, "corpus.zip · #{ZIP.bytesize} bytes · sha256 #{Digest::SHA256.hexdigest(ZIP)}"
      assert_includes @out.string, "index list.csv · #{CSV.bytesize} bytes"
      refute_includes @out.string, TOKEN
    end

    def test_only_read_methods_are_called
      two_attachments
      run_fetch
      assert_requested(:post, API, times: 1) do |request|
        calls = JSON.parse(request.body).fetch("methodCalls")
        calls.map(&:first) == ["Email/get"] && calls.first[1]["ids"] == [EMAIL] &&
          calls.first[1]["properties"] == ["attachments"]
      end
    end

    def test_the_name_filter_selects_attachments
      two_attachments
      report = run_fetch(filter: "ZIP")
      assert report.ok?
      assert File.file?(File.join(@inbox, "corpus.zip"))
      refute File.exist?(File.join(@inbox, "index list.csv"))
      assert_not_requested :get, %r{/Gcsv2/}
    end

    def test_a_filter_matching_nothing_is_a_failure
      two_attachments
      refute run_fetch(filter: "pdf").ok?
      assert_match(/no attachment matches/, @out.string)
    end

    def test_an_identical_file_is_already_present_and_a_different_one_is_refused
      two_attachments
      FileUtils.mkdir_p(@inbox)
      File.binwrite(File.join(@inbox, "corpus.zip"), ZIP)
      File.binwrite(File.join(@inbox, "index list.csv"), "something else")
      report = run_fetch
      refute report.ok?, "a refusal is a failure"
      assert_match(/corpus\.zip .*already present/, @out.string)
      assert_includes @out.string, Digest::SHA256.hexdigest("something else")
      assert_includes @out.string, Digest::SHA256.hexdigest(CSV)
      assert_equal "something else", File.binread(File.join(@inbox, "index list.csv")), "never overwritten"
    end

    def test_a_size_mismatch_is_a_failure_and_saves_nothing
      stub_session
      stub_email([attachment("Gzip1", "corpus.zip", "application/zip", ZIP.bytesize + 5)])
      stub_blob("Gzip1", "corpus.zip", "application%2Fzip", ZIP)
      refute run_fetch.ok?
      assert_match(/size mismatch/, @out.string)
      refute File.exist?(File.join(@inbox, "corpus.zip"))
    end

    def test_a_hostile_attachment_name_is_reduced_to_a_safe_basename
      stub_session
      stub_email([attachment("Gevil", "../../.ssh/..authorized_keys", "text/plain", CSV.bytesize),
                  attachment("Gwin", "C:\\Windows\\..\\evil.bat", "text/plain", CSV.bytesize)])
      stub_blob("Gevil", "authorized_keys", "text%2Fplain", CSV)
      stub_blob("Gwin", "evil.bat", "text%2Fplain", CSV)
      assert run_fetch.ok?
      assert_equal %w[authorized_keys evil.bat], Dir.children(@inbox).sort
      assert_equal [".docs"], Dir.children(@dir), "nothing written outside the inbox"
    end

    def test_an_unknown_email_fails
      stub_session
      stub_email([], not_found: [EMAIL])
      error = assert_raises(FETCH::Error) { run_fetch }
      assert_match(/not found/, error.message)
    end
  end
end
