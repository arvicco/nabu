# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# TitusFetch's credentials arm (the gated TITUS members area): an optional
# Credentials::Entry rides every request as HTTP Basic auth; a 401 to SENT
# credentials is the rotation signal (Credentials::Rejected, the gateway
# command in the message); credentials are never forwarded across a
# redirect; nothing ever prints the secret. The page-walk itself is covered
# by the per-corpus adapter tests.
class TitusFetchTest < Minitest::Test
  BASE = "https://titus.example.invalid/texte/etcc/toch/tochb"
  SECRET = "rotating-pa55"

  def setup
    @auth = Nabu::Credentials::Entry.new(name: "titus", user: "member", password: SECRET, token: nil,
                                         updated_at: nil)
  end

  def test_credentials_ride_every_request_as_basic_auth
    frameset = '<frameset><frame src="tochb001.htm" name="etatext"></frameset>'
    stub_request(:get, "#{BASE}/tochb.htm").with(basic_auth: ["member", SECRET]).to_return(body: frameset)
    stub_request(:get, "#{BASE}/tochb001.htm").with(basic_auth: ["member", SECRET])
                                              .to_return(body: "<html><body>page</body></html>")
    Dir.mktmpdir do |dir|
      result = sync(dir, auth: @auth)
      assert_equal 1, result.page_count
      assert_requested(:get, "#{BASE}/tochb001.htm", headers: { "Authorization" => @auth.basic_auth_header })
    end
  end

  def test_a_401_to_sent_credentials_is_the_rotation_signal
    stub_request(:get, "#{BASE}/tochb.htm").to_return(status: 401, body: "Unauthorized")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::Credentials::Rejected) { sync(dir, auth: @auth) }
      assert_equal "titus credentials rejected (rotated?) — run bin/nabu creds set titus", error.message
      assert_empty Dir.children(dir), "a rejected walk writes nothing"
    end
  end

  def test_a_401_without_credentials_stays_a_plain_fetch_error
    stub_request(:get, "#{BASE}/tochb.htm").to_return(status: 401, body: "Unauthorized")
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::TitusFetch::Error) { sync(dir) }
      assert_match(/HTTP 401/, error.message)
    end
  end

  def test_credentials_are_never_forwarded_across_a_redirect
    stub_request(:get, "#{BASE}/tochb.htm")
      .to_return(status: 301, headers: { "Location" => "https://elsewhere.example.invalid/tochb.htm" })
    Dir.mktmpdir do |dir|
      error = assert_raises(Nabu::TitusFetch::Error) { sync(dir, auth: @auth) }
      assert_match(/never forwarded across a redirect/, error.message)
      assert_match(/elsewhere\.example\.invalid/, error.message)
      refute_includes error.message, SECRET
    end
    assert_not_requested(:get, "https://elsewhere.example.invalid/tochb.htm")
  end

  def test_the_fetch_never_reveals_the_secret_when_inspected
    Dir.mktmpdir do |dir|
      fetch = Nabu::TitusFetch.new(entry_url: "#{BASE}/tochb.htm", dir: dir, attic_dir: File.join(dir, ".attic"),
                                   delay: 0, auth: @auth, page_re: /\Atochb\d+\.htm\z/)
      refute_includes fetch.inspect, SECRET
      refute_includes fetch.inspect, @auth.basic_auth_header.delete_prefix("Basic ")
    end
  end

  private

  def sync(dir, auth: nil)
    Nabu::TitusFetch.sync!(entry_url: "#{BASE}/tochb.htm", dir: dir, attic_dir: File.join(dir, ".attic"),
                           delay: 0, auth: auth, page_re: /\Atochb\d+\.htm\z/)
  end
end

# The partial stage: a killed first walk resumes without re-requesting.
def test_interrupted_walk_resumes_from_the_partial_stage
  Dir.mktmpdir do |root|
    dir = File.join(root, "pages")
    requests = Hash.new(0)
    frameset = '<frameset><frame name="etatext" src="aves001.htm"></frameset>'
    page1 = '<html><a href="aves002.htm"><img alt="Next part"></a>one</html>'
    page2 = "<html>two</html>"
    stub_request(:get, "https://example.org/entry.htm")
      .to_return do
      requests["entry"] += 1
      { body: frameset, status: 200 }
    end
    stub_request(:get, "https://example.org/aves001.htm")
      .to_return do
      requests["p1"] += 1
      { body: page1, status: 200 }
    end
    stub_request(:get, "https://example.org/aves002.htm")
      .to_return do
      requests["p2"] += 1
      { body: page2, status: 200 }
    end

    # First walk dies after staging page 1 (simulated by raising from the
    # page-2 request).
    stub_request(:get, "https://example.org/aves002.htm").to_timeout.then
                                                         .to_return do
      requests["p2"] += 1
      { body: page2, status: 200 }
    end
    fetch = Nabu::TitusFetch.new(entry_url: "https://example.org/entry.htm",
                                 dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0)
    assert_raises(Nabu::TitusFetch::Error) { fetch.prepare! }
    assert File.file?(File.join(dir, ".fetch-partial", "aves001.htm")),
           "the fetched page is staged before the walk dies"

    # The re-run reads page 1 from the stage: no second request for it.
    result = Nabu::TitusFetch.sync!(entry_url: "https://example.org/entry.htm",
                                    dir: dir, attic_dir: File.join(dir, ".attic"), delay: 0)
    assert_equal 2, result.page_count
    assert_equal 1, requests["p1"], "the staged page is never re-requested"
    assert File.file?(File.join(dir, "aves001.htm"))
    refute Dir.exist?(File.join(dir, ".fetch-partial")), "complete! consumes the stage"
  end
end
