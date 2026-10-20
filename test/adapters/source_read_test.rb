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

  private

  def write(name, bytes)
    path = File.join(@dir, name)
    File.binwrite(path, bytes)
    path
  end
end
