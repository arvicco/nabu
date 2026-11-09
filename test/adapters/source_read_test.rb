# frozen_string_literal: true

require "test_helper"
require "tmpdir"

# Nabu::Adapters::SourceRead — the encoding/bounds belt every adapter read can route
# through. Its whole contract is that bad bytes become Nabu::ParseError (the
# loader's per-document quarantine), never an encoding exception or a heap
# leak that escapes the net and aborts a sync.
class SourceReadTest < Minitest::Test
  # A real upstream specimen: TITUS severed U+0331 (\xCC\xB1) around a
  # closing tag (titus-pahlavi snstrl/snstr002).
  SEVERED = "LC\xE1\xB8\x8Er\xCC\x84'\xCC</a>\xB1 x".b
  # A truncated 2-byte sequence no repair can fix.
  BROKEN = "ok \xC3( still".b

  def setup
    @dir = Dir.mktmpdir("nabu-source-read")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  # -- UTF-8 validity --------------------------------------------------------

  def test_valid_utf8_reads_through_unchanged
    path = write("ok.txt", "μῆνιν ἄειδε\n")

    text = Nabu::Adapters::SourceRead.utf8_file(path, label: "src")

    assert_equal "μῆνιν ἄειδε\n", text
    assert_equal Encoding::UTF_8, text.encoding
  end

  def test_invalid_utf8_is_a_parse_error_naming_the_file
    path = write("bad.txt", BROKEN)

    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.utf8_file(path, label: "src") }

    assert_match(/\Asrc: .*bad\.txt is not valid UTF-8/, error.message)
  end

  # Without the opt-in repair a severed page is just invalid; with it, the
  # bytes after the tag rejoin their lead byte and the character lands on
  # the text it was cut from.
  def test_severed_sequence_repair_is_opt_in
    path = write("severed.htm", SEVERED)

    assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.utf8_file(path, label: "src") }
    repaired = Nabu::Adapters::SourceRead.utf8_file(path, label: "src", repair: :severed_tags)

    assert_predicate repaired, :valid_encoding?
    assert_includes repaired, "</a>̱"
  end

  def test_an_unrepairable_page_names_the_repair_it_got_past
    path = write("bad.htm", BROKEN)

    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::SourceRead.utf8_file(path, label: "src", repair: :severed_tags)
    end
    assert_match(/bad\.htm is not valid UTF-8 \(beyond the severed-sequence repair\)/, error.message)
  end

  def test_in_memory_bytes_ride_the_same_belt
    assert_equal "abc", Nabu::Adapters::SourceRead.utf8("abc".b, label: "member.txt")
    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.utf8(BROKEN, label: "zip:member.txt") }
    assert_equal "zip:member.txt is not valid UTF-8", error.message
  end

  # -- NFC at the boundary -------------------------------------------------------

  def test_nfc_honors_the_named_exemption_list
    decomposed = "é"

    assert_equal "é", Nabu::Adapters::SourceRead.nfc(decomposed, language: "grc")
    assert_equal decomposed, Nabu::Adapters::SourceRead.nfc(decomposed, language: "hbo"),
                 "hbo/arc keep upstream mark order (Normalize::NFC_EXEMPT_LANGUAGES)"
  end

  def test_nfc_of_invalid_bytes_is_a_parse_error_not_an_encoding_error
    assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.nfc(BROKEN.dup.force_encoding("UTF-8"), language: "grc") }
  end

  # -- bounds on sliced reads ------------------------------------------------------

  def test_an_in_bounds_slice_is_exact
    assert_equal "cde".b, Nabu::Adapters::SourceRead.slice("abcdefg".b, offset: 2, length: 3, what: "rec")
  end

  # A pointer past the buffer must never return a SHORT slice silently (a
  # short read decodes as a truncated cell, or the caller reads on into the
  # next frame — the heap-byte leak shape).
  def test_a_slice_past_the_end_is_a_parse_error
    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::SourceRead.slice("abcdefg".b, offset: 5, length: 3, what: "x.var: var pointer")
    end
    assert_equal "x.var: var pointer 5+3 reaches past the end of the file", error.message
    assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.slice("abc".b, offset: 9, length: 1, what: "p") }
    assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.slice("abc".b, offset: -1, length: 1, what: "p") }
  end

  # -- zip members -----------------------------------------------------------------

  # The archive read and the member's text ride one entry point each: the
  # binary read is the belt's (a ZipReader over the bytes), and every member
  # comes out through #utf8, labelled with the member name.
  def test_a_zip_member_reads_through_the_belt
    path = write("held.zip", stored_zip("a/1.html" => "μῆνιν\n", "a/2.html" => "ok"))

    zip = Nabu::Adapters::SourceRead.zip_file(path)
    entry = zip.entries.find { |e| e.name == "a/1.html".b }
    text = Nabu::Adapters::SourceRead.utf8_member(zip, entry, label: path)

    assert_equal "μῆνιν\n", text
    assert_equal Encoding::UTF_8, text.encoding
  end

  def test_an_invalid_zip_member_is_a_parse_error_naming_the_member
    path = write("held.zip", stored_zip("a/bad.html" => BROKEN))
    zip = Nabu::Adapters::SourceRead.zip_file(path)

    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::SourceRead.utf8_member(zip, zip.entries.first, label: "held.zip")
    end
    assert_equal "held.zip: a/bad.html is not valid UTF-8", error.message
  end

  def test_a_zip_member_takes_the_same_opt_in_repair
    path = write("held.zip", stored_zip("p.htm" => SEVERED))
    zip = Nabu::Adapters::SourceRead.zip_file(path)

    assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.utf8_member(zip, zip.entries.first, label: "z") }
    repaired = Nabu::Adapters::SourceRead.utf8_member(zip, zip.entries.first, label: "z", repair: :severed_tags)
    assert_includes repaired, "</a>̱"
  end

  # A structurally broken archive stays Nabu::ZipReader::Error: each caller
  # maps it onto its own contract (quarantine at parse, a complaint at drop).
  def test_a_non_zip_raises_the_zip_readers_own_error
    path = write("not.zip", "plain text, no central directory")

    assert_raises(Nabu::ZipReader::Error) { Nabu::Adapters::SourceRead.zip_file(path) }
  end

  # -- line streaming ----------------------------------------------------------------

  def test_utf8_lines_yields_each_line_checked_with_its_terminator
    path = write("rows.jsonl", "{\"a\":1}\n{\"b\":\"ἄ\"}\nlast")

    lines = Nabu::Adapters::SourceRead.utf8_lines(path, label: "src").to_a

    assert_equal ["{\"a\":1}\n", "{\"b\":\"ἄ\"}\n", "last"], lines
    assert(lines.all? { |line| line.encoding == Encoding::UTF_8 })
  end

  def test_an_invalid_line_is_a_parse_error_naming_file_and_line
    path = write("rows.jsonl", "ok\n#{BROKEN}\n".b)

    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::SourceRead.utf8_lines(path, label: "src") { |_line| nil }
    end
    assert_match(/\Asrc: .*rows\.jsonl line 2 is not valid UTF-8\z/, error.message)
  end

  # The streamer exists for multi-hundred-MB files: it must hand line one
  # over BEFORE the rest of the file exists. A FIFO whose writer withholds
  # line two until line one has been consumed deadlocks any reader that
  # slurps (it waits for an EOF that never comes) — the timeout catches it.
  def test_utf8_lines_streams_lazily_and_never_slurps
    path = File.join(@dir, "stream.jsonl")
    File.mkfifo(path)
    gate = Queue.new
    writer = Thread.new do
      File.open(path, "w") do |io|
        io.sync = true
        io.write("first\n")
        gate.pop
        io.write("second\n")
      end
    end
    seen = []
    Timeout.timeout(5) do
      Nabu::Adapters::SourceRead.utf8_lines(path, label: "src") do |line|
        seen << line
        gate << :go if seen.size == 1
      end
    end

    assert_equal %W[first\n second\n], seen
  ensure
    writer&.kill
  end

  # -- gzip members ------------------------------------------------------------------

  # A real gzipped upstream file (the wellcome catalogue-snapshot sample).
  WELLCOME_GZ = File.expand_path("../fixtures/wellcome/works.json.gz", __dir__)

  def test_a_real_gzip_file_reads_through_the_belt_as_its_gunzipped_text
    text = Nabu::Adapters::SourceRead.utf8_gzip(WELLCOME_GZ, label: "src")

    assert_equal Zlib.gunzip(File.binread(WELLCOME_GZ)).force_encoding(Encoding::UTF_8), text
    assert_equal Encoding::UTF_8, text.encoding
    assert text.valid_encoding?
  end

  def test_an_invalid_gzip_member_is_a_parse_error_naming_the_file
    path = write("page.html.gz", Zlib.gzip(BROKEN))

    error = assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.utf8_gzip(path, label: "src") }
    assert_equal "src: #{path} is not valid UTF-8", error.message
  end

  def test_a_gzip_member_takes_the_same_opt_in_repair
    path = write("page.html.gz", Zlib.gzip(SEVERED))

    assert_raises(Nabu::ParseError) { Nabu::Adapters::SourceRead.utf8_gzip(path, label: "src") }
    repaired = Nabu::Adapters::SourceRead.utf8_gzip(path, label: "src", repair: :severed_tags)
    assert repaired.valid_encoding?
  end

  # Container defects stay the caller's to map (like ZipReader::Error).
  def test_a_non_gzip_raises_zlibs_own_error
    path = write("not.gz", "plain text, no gzip header")

    assert_raises(Zlib::Error) { Nabu::Adapters::SourceRead.utf8_gzip(path, label: "src") }
  end

  def test_utf8_lines_streams_a_real_gzip_file_line_by_line
    lines = Nabu::Adapters::SourceRead.utf8_lines(WELLCOME_GZ, label: "src", gzip: true).to_a

    assert_equal Zlib.gunzip(File.binread(WELLCOME_GZ)).force_encoding(Encoding::UTF_8).lines, lines
    assert(lines.all? { |line| line.encoding == Encoding::UTF_8 })
  end

  def test_an_invalid_gzip_line_is_a_parse_error_naming_file_and_line
    path = write("rows.jsonl.gz", Zlib.gzip("ok\n#{BROKEN}\n".b))

    error = assert_raises(Nabu::ParseError) do
      Nabu::Adapters::SourceRead.utf8_lines(path, label: "src", gzip: true) { |_line| nil }
    end
    assert_match(/\Asrc: .*rows\.jsonl\.gz line 2 is not valid UTF-8\z/, error.message)
  end

  private

  # A minimal spec-conformant STORED zip (method 0) — the container only;
  # the member bytes are the test's own specimens.
  def stored_zip(members)
    body = +"".b
    central = +"".b
    members.each do |name, content|
      name = name.b
      content = content.b
      crc = Zlib.crc32(content)
      offset = body.bytesize
      body << ["PK\x03\x04".b, 20, 0, 0, 0, 0, crc, content.bytesize, content.bytesize, name.bytesize, 0]
              .pack("a4vvvvvVVVvv") << name << content
      central << ["PK\x01\x02".b, 20, 20, 0, 0, 0, 0, crc, content.bytesize, content.bytesize,
                  name.bytesize, 0, 0, 0, 0, 0, offset].pack("a4vvvvvvVVVvvvvvVV") << name
    end
    eocd = ["PK\x05\x06".b, 0, 0, members.size, members.size, central.bytesize, body.bytesize, 0]
           .pack("a4vvvvVVv")
    body + central + eocd
  end

  def write(name, bytes)
    path = File.join(@dir, name)
    File.binwrite(path, bytes)
    path
  end
end
