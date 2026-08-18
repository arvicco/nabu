# frozen_string_literal: true

require "test_helper"

# DataGoKrFetch (P78-1): the data.go.kr three-step resolution — page →
# JSON → terminal fileDownload.do URL. The atchFileId bumps on every
# upstream file replacement, so resolution runs fresh at every fetch;
# a portal-shape change fails LOUDLY (an unresolved fetch must never
# quietly download an HTML page as a corpus).
class DataGoKrFetchTest < Minitest::Test
  PAGE_URL = "https://www.data.go.kr/data/15053647/fileData.do"
  JSON_URL = "https://www.data.go.kr/tcs/dss/selectFileDataDownload.do" \
             "?publicDataPk=15053647&publicDataDetailPk=uddi:3557cf5a&fileDetailSn=1"

  PAGE = <<~HTML
    <button type="button" onclick="fileDetailObj.fn_fileDataDown('15053647', 'uddi:3557cf5a', '','1', '2')">
      다운로드</button>
  HTML

  def http = Nabu::ZipFetch.default_http

  def test_resolves_the_terminal_download_url
    stub_request(:get, PAGE_URL).to_return(status: 200, body: PAGE)
    stub_request(:get, JSON_URL).to_return(
      status: 200,
      body: JSON.generate("status" => true, "atchFileId" => "FILE_000000002636389", "fileDetailSn" => "1")
    )
    url = Nabu::DataGoKrFetch.resolve("15053647", http: http)
    assert_equal "https://www.data.go.kr/cmm/cmm/fileDownload.do" \
                 "?atchFileId=FILE_000000002636389&fileDetailSn=1", url
  end

  def test_a_page_without_the_download_button_raises_fetch_error
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html>고쳐진 포털</html>")
    error = assert_raises(Nabu::FetchError) { Nabu::DataGoKrFetch.resolve("15053647", http: http) }
    assert_includes error.message, "no download button"
  end

  def test_a_refused_resolution_raises_rather_than_fetching_html_as_corpus
    stub_request(:get, PAGE_URL).to_return(status: 200, body: PAGE)
    stub_request(:get, JSON_URL).to_return(
      status: 200, body: JSON.generate("status" => false, "error" => "일시적으로 제한되었습니다")
    )
    error = assert_raises(Nabu::FetchError) { Nabu::DataGoKrFetch.resolve("15053647", http: http) }
    assert_includes error.message, "resolution refused"
  end

  def test_non_json_resolution_raises_fetch_error
    stub_request(:get, PAGE_URL).to_return(status: 200, body: PAGE)
    stub_request(:get, JSON_URL).to_return(status: 200, body: "<html>captcha</html>")
    assert_raises(Nabu::FetchError) { Nabu::DataGoKrFetch.resolve("15053647", http: http) }
  end

  def test_http_failure_raises_fetch_error
    stub_request(:get, PAGE_URL).to_return(status: 500)
    error = assert_raises(Nabu::FetchError) { Nabu::DataGoKrFetch.resolve("15053647", http: http) }
    assert_includes error.message, "HTTP 500"
  end
end
