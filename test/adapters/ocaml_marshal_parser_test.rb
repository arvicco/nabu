# frozen_string_literal: true

require "test_helper"

module Adapters
  # The ocaml-marshal parser family (P142). Two kinds of evidence:
  #
  # - SPEC VECTORS: byte strings assembled from the OCaml runtime's own
  #   opcode table (runtime/intern.c) — one per code the decoder admits
  #   or refuses. They encode the documented format, not an upstream
  #   corpus, so they are written here rather than snapshotted.
  # - THE REAL PAYLOAD: SigLA's `signs` blob, byte-verbatim in
  #   test/fixtures/sigla/database.js (77 KB, untrimmed) — decoded,
  #   self-checked against its header, and re-encoded BYTE-IDENTICAL,
  #   which proves the reader and the fixture-cut writer both follow
  #   extern.c's choices exactly.
  class OcamlMarshalParserTest < Minitest::Test
    P = Nabu::Adapters::OcamlMarshalParser
    FIXTURE = File.join(Nabu::TestSupport.fixtures("sigla"), "database.js")

    # A small-header payload around +body+, declaring +objects+ shared
    # objects (sizes are informational — the decoder never trusts them).
    def payload(body, objects:)
      body = body.b
      [P::MAGIC_SMALL, body.bytesize, objects, 0, 0].pack("N5") + body
    end

    def decode(body, objects: 0) = P.decode(payload(body, objects: objects))

    def signs_bytes
      line = File.binread(FIXTURE).lines.find { |l| l.start_with?("var signs = ") }
      line.scan(/\\\\(\d{3})/).map { |digits| digits[0].to_i }.pack("C*")
    end

    # -- immediates ---------------------------------------------------------

    def test_small_ints_and_the_signed_int_widths
      assert_equal 0, decode("\x40")
      assert_equal 63, decode("\x7F")
      assert_equal(-5, decode("\x00\xFB"), "INT8 is signed")
      assert_equal 1466, decode("\x01\x05\xBA"), "INT16 big-endian"
      assert_equal(-70_000, decode("\x02\xFF\xFE\xEE\x90"), "INT32 signed big-endian")
      assert_equal 2**40, decode("\x03\x00\x00\x01\x00\x00\x00\x00\x00"), "INT64"
    end

    # -- strings, doubles, blocks -------------------------------------------

    def test_strings_of_every_length_code_register_and_come_back_utf8
      assert_equal "LM IB", decode("\x25LM IB", objects: 1)
      long = "x" * 40
      assert_equal long, decode("\x09\x28#{long}", objects: 1)
      assert_equal long, decode("\x0A\x00\x00\x00\x28#{long}", objects: 1)
      assert_equal Encoding::UTF_8, decode("\x22\xCF\x80", objects: 1).encoding
      assert_equal "π", decode("\x22\xCF\x80", objects: 1)
    end

    def test_doubles_in_both_byte_orders_and_float_arrays
      assert_in_delta 0.95, decode("\x0C#{[0.95].pack('E')}", objects: 1)
      assert_in_delta 6.0, decode("\x0B#{[6.0].pack('G')}", objects: 1)
      assert_equal [6.0, 8.0], decode("\x0E\x02#{[6.0, 8.0].pack('E*')}", objects: 1)
    end

    def test_small_blocks_block32_and_atoms
      block = decode("\xA0\x41\x42", objects: 1) # tag 0, size 2
      assert_equal [0, [1, 2]], [block.tag, block.fields]
      tagged = decode("\x93\x45", objects: 1) # tag 3, size 1
      assert_equal 3, tagged.tag
      big = decode("\x08\x00\x00\x27\x00#{"\x40" * 9}", objects: 1)
      assert_equal [0, 9], [big.tag, big.size], "BLOCK32: the GC color bits (0x300) are masked off"
      atom = decode("\x80")
      assert_equal [0, 0], [atom.tag, atom.size], "a zero-size block is an atom — not registered"
    end

    def test_sharing_returns_the_very_same_object_and_admits_cycles
      shared = decode("\xA0\x23abc\x04\x01", objects: 2) # (s, s) — the second field points back
      assert_same shared[0], shared[1]
      cyclic = decode("\x90\x04\x01", objects: 1) # a one-field block whose field is itself
      assert_same cyclic, cyclic[0]
    end

    def test_boxed_int64_custom_block
      assert_equal 7, decode("\x19_j\x00#{[7].pack('q>')}", objects: 1)
    end

    # -- the self-checks and the refusals -----------------------------------

    def test_header_object_count_and_length_are_enforced
      error = assert_raises(Nabu::ParseError) { decode("\x23abc", objects: 2) }
      assert_match(/registered 1 objects, header declares 2/, error.message)
      error = assert_raises(Nabu::ParseError) { P.decode("#{[P::MAGIC_SMALL, 9, 0, 0, 0].pack('N5')}\x40") }
      assert_match(/declares 9 data bytes/, error.message)
      assert_raises(Nabu::ParseError) { decode("\xA0\x41", objects: 1) } # truncated mid-block
    end

    def test_unsupported_formats_are_refused_loudly
      [P::MAGIC_BIG, P::MAGIC_COMPRESSED, 0xDEADBEEF].each do |magic|
        assert_raises(Nabu::ParseError) { P.decode("#{[magic, 1, 0, 0, 0].pack('N5')}\x40") }
      end
      assert_match(/BLOCK64/, assert_raises(Nabu::ParseError) { decode("\x13") }.message)
      assert_match(/custom block "_x"/, assert_raises(Nabu::ParseError) { decode("\x19_x\x00") }.message)
      assert_match(/opcode 0x10/, assert_raises(Nabu::ParseError) { decode("\x10") }.message)
    end

    # -- the stdlib shapes --------------------------------------------------

    def test_map_list_and_option_helpers
      leaf = ->(key, value) { P::Block.new(0, [0, key, value, 0, 1]) }
      map = P::Block.new(0, [leaf.call("a", 1), "b", 2, leaf.call("c", 3), 2])
      assert_equal [["a", 1], ["b", 2], ["c", 3]], P.map_entries(map), "in-order walk"
      assert_empty P.map_entries(0)
      list = P::Block.new(0, ["x", P::Block.new(0, ["y", 0])])
      assert_equal %w[x y], P.list_items(list)
      assert_nil P.option(0)
      assert_equal "LM I", P.option(P::Block.new(0, ["LM I"]))
    end

    # -- the real payload ---------------------------------------------------

    def test_the_real_sigla_signs_payload_decodes_and_reencodes_byte_identical
      bytes = signs_bytes
      root = P.decode(bytes)
      signs = P.map_entries(root[0])
      assert_equal 376, signs.size, "the SigLA sign list: 376 signs (AB 77 · A 298 · N 1)"
      assert_equal %w[AB A], P.list_items(root[1]), "the series list"
      number, record = signs.first
      assert_equal 1, number
      assert_equal ["AB", 1, "da", "PH 31a/17"], [record[0], record[1], record[2][0][0], record[3][0]]
      assert_equal bytes, P.encode(root), "extern.c's choices reproduced exactly — the cut-tool proof"
    end
  end
end
