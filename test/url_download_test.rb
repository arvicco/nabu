# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::UrlDownload (P20-0): the ingest front door's fetch arm — one-shot
# download of an owner-given url into a staging dir. Bounded manual redirect
# follow (no redirect middleware in the dependency budget — hand-rolled),
# Content-Disposition/url filename derivation, binary body. No network:
# WebMock stubs throughout.
class UrlDownloadTest < Minitest::Test
  URL = "https://archive.org/download/handbuch/handbuchderaltbu00lesk.pdf"

  def fetch(url = URL)
    Dir.mktmpdir("nabu-url-download") do |dir|
      path = Nabu::UrlDownload.new.fetch(url, dir: dir)
      [File.basename(path), File.binread(path)]
    end
  end

  def test_url_predicate_matches_http_and_https_only
    assert Nabu::UrlDownload.url?(URL)
    assert Nabu::UrlDownload.url?("HTTP://EXAMPLE.ORG/x.pdf"), "scheme match is case-insensitive"
    refute Nabu::UrlDownload.url?("/home/vb/scans/leskien.pdf")
    refute Nabu::UrlDownload.url?("ftp://example.org/x.pdf")
  end

  def test_direct_200_writes_the_body_binary_under_the_urls_basename
    stub_request(:get, URL).to_return(status: 200, body: "%PDF-1.4 \xC3\x28".b)
    name, body = fetch
    assert_equal "handbuchderaltbu00lesk.pdf", name
    assert_equal "%PDF-1.4 \xC3\x28".b, body, "the body is written binary, byte for byte"
  end

  def test_follows_an_archive_org_style_302_chain_to_the_mirror_body
    mirror = "https://ia601500.us.archive.org/5/items/handbuch/handbuchderaltbu00lesk.pdf"
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => mirror })
    stub_request(:get, mirror).to_return(status: 200, body: "mirror bytes")
    name, body = fetch
    assert_equal "handbuchderaltbu00lesk.pdf", name
    assert_equal "mirror bytes", body
    assert_requested :get, mirror
  end

  def test_relative_location_resolves_against_the_current_url
    stub_request(:get, "https://example.org/a/doc.pdf")
      .to_return(status: 301, headers: { "Location" => "../files/doc-final.pdf" })
    stub_request(:get, "https://example.org/files/doc-final.pdf").to_return(status: 200, body: "x")
    name, = fetch("https://example.org/a/doc.pdf")
    assert_equal "doc-final.pdf", name
  end

  def test_content_disposition_filename_wins_with_quotes_stripped_and_paths_dropped
    stub_request(:get, URL).to_return(
      status: 200, body: "x",
      headers: { "Content-Disposition" => %(attachment; filename="scans/leskien 1871.pdf") }
    )
    name, = fetch
    assert_equal "leskien 1871.pdf", name
  end

  def test_content_disposition_utf8_bytes_arrive_utf8_nfc_never_binary
    # The 2026-07-14 live crash (P21-0): OJS journals send Content-Disposition
    # filenames as raw UTF-8 bytes and the HTTP stack hands the header value
    # over BINARY-encoded. Unnormalized, the name reached the engine as
    # ASCII-8BIT — the success message's UTF-8 interpolation raised
    # Encoding::CompatibilityError AFTER the copy and append had landed, and
    # the manifest serialized the file lane as a YAML !binary blob.
    stub_request(:get, URL).to_return(
      status: 200, body: "x",
      headers: { "Content-Disposition" => %(attachment; filename="37850-Text článku-69488.pdf").b }
    )
    name, = fetch
    assert_equal "37850-Text článku-69488.pdf", name
    assert_equal Encoding::UTF_8, name.encoding
    assert_predicate name, :valid_encoding?
  end

  def test_derived_names_are_nfc_normalized
    # NFD percent-encoding in the wild (e + combining acute) must come out
    # as the composed form — the house rule: UTF-8 NFC at the boundary.
    decomposed = "https://example.org/Frisinske%CC%81.pdf"
    stub_request(:get, decomposed).to_return(status: 200, body: "x")
    name, = fetch(decomposed)
    assert_equal "Frisinské.pdf", name
  end

  def test_undecodable_header_bytes_are_scrubbed_not_crashed
    stub_request(:get, URL).to_return(
      status: 200, body: "x",
      headers: { "Content-Disposition" => %(attachment; filename="bad\xFFname.pdf").b }
    )
    name, = fetch
    assert_predicate name, :valid_encoding?
    assert_equal "bad\u{FFFD}name.pdf", name, "invalid bytes degrade to the replacement char, honestly"
  end

  def test_bare_content_disposition_filename_is_honored_too
    stub_request(:get, URL).to_return(
      status: 200, body: "x", headers: { "Content-Disposition" => "attachment; filename=offprint.pdf" }
    )
    name, = fetch
    assert_equal "offprint.pdf", name
  end

  def test_final_url_basename_is_percent_decoded
    stub_request(:get, "https://example.org/my%20paper.pdf").to_return(status: 200, body: "x")
    name, = fetch("https://example.org/my%20paper.pdf")
    assert_equal "my paper.pdf", name
  end

  def test_extensionless_final_basename_falls_back_to_the_original_urls
    query = "https://mirror.example.org/fetch?id=123"
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => query })
    stub_request(:get, query).to_return(status: 200, body: "x")
    name, = fetch
    assert_equal "handbuchderaltbu00lesk.pdf", name,
                 "a mirror's opaque handler path is garbage — the owner's url names the file"
  end

  def test_redirect_loop_errors_honestly_at_the_hop_cap
    stub_request(:get, URL).to_return(status: 302, headers: { "Location" => URL })
    error = assert_raises(Nabu::UrlDownload::Error) { fetch }
    assert_match(/redirect/, error.message)
    assert_match(/5/, error.message, "the cap is named")
    assert_requested :get, URL, times: 6 # the original request + 5 followed hops
  end

  def test_redirect_without_location_is_an_honest_error
    stub_request(:get, URL).to_return(status: 302)
    error = assert_raises(Nabu::UrlDownload::Error) { fetch }
    assert_match(/Location/, error.message)
  end

  def test_non_redirect_non_200_names_the_http_status
    stub_request(:get, URL).to_return(status: 404)
    error = assert_raises(Nabu::UrlDownload::Error) { fetch }
    assert_match(/HTTP 404/, error.message)
    assert_match(/archive\.org/, error.message)
  end

  def test_transport_error_is_wrapped_with_the_url_named
    stub_request(:get, URL).to_raise(Errno::ECONNREFUSED)
    error = assert_raises(Nabu::UrlDownload::Error) { fetch }
    assert_match(/transport error/, error.message)
    assert_match(/archive\.org/, error.message)
  end

  def test_collisions_in_the_staging_dir_get_a_numbered_suffix
    stub_request(:get, URL).to_return(status: 200, body: "x")
    Dir.mktmpdir do |dir|
      download = Nabu::UrlDownload.new
      first = download.fetch(URL, dir: dir)
      second = download.fetch(URL, dir: dir)
      assert_equal "handbuchderaltbu00lesk.pdf", File.basename(first)
      assert_equal "handbuchderaltbu00lesk-1.pdf", File.basename(second)
    end
  end
end
