# frozen_string_literal: true

# A WebMock stub serving the REAL OpenITI MAKHZAN data zip (Zenodo record
# 19861912, 6,109,859,716 bytes) from the byte ranges captured off it
# (test/fixtures/makhzan/fetch/ranges/<first>-<last>.bin — exactly what
# Nabu::RemoteZip read for Doc102 and Doc3213, 2026-11-27). A request for
# bytes no capture covers answers 416, so a test fails loudly if the reader
# ever reaches for an image or any byte it should not need.
module MakhzanRanges
  ZIP_URL = "https://zenodo.org/api/records/19861912/files/OpenITI-Makhzan_Data_2026-1-2.zip/content"
  # census: 6109859716, 2026-11-27, the record's own file size
  ZIP_SIZE = 6_109_859_716
  def self.captures
    dir = File.join(Nabu::TestSupport.fixtures("makhzan"), "fetch", "ranges")
    @captures ||= Dir.glob("*.bin", base: dir).to_h do |name|
      first, last = File.basename(name, ".bin").split("-").map(&:to_i)
      [first..last, File.binread(File.join(dir, name))]
    end
  end

  # Stubs ZIP_URL; returns the list of [first, last] ranges requested.
  def stub_makhzan_zip(status: 206)
    requested = []
    stub_request(:get, ZIP_URL).to_return do |request|
      first, last = request.headers["Range"].to_s[/bytes=(\d+-\d+)/, 1].split("-").map(&:to_i)
      requested << [first, last]
      span, bytes = MakhzanRanges.captures.find { |range, _| range.cover?(first) && range.cover?(last) }
      if span.nil?
        { status: 416, body: "" }
      else
        { status: status, body: bytes.byteslice(first - span.first, last - first + 1),
          headers: { "Content-Range" => "bytes #{first}-#{last}/#{ZIP_SIZE}" } }
      end
    end
    requested
  end
end
