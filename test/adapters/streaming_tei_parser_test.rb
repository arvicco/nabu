# frozen_string_literal: true

require "test_helper"
require "stringio"

# Nabu::Adapters::StreamingTeiParser — the shared skeleton of the streaming
# TEI parser families (croala, bfm, corpus-corporum, openmgh, 84000, dta,
# tcp-xml, …): canonical-path resolution, the one-pass Reader extraction
# seam, the positional ":b<k>" collision tolerance, the Document assembly
# (whitespace collapse + NFC at the boundary), and the Reader walker's
# dispatch scaffold. Per-source header fields, citation grammar and unit
# shaping stay in the subclasses; this test drives the skeleton through a
# minimal probe family over real CroALa bytes.
class StreamingTeiParserTest < Minitest::Test
  FIXTURES = File.join(Nabu::TestSupport.fixtures("croala"), "txts")
  CARMINA = File.join(FIXTURES, "andreis-f-carm-h46.xml")
  INSCR = File.join(FIXTURES, "albert-i-inscr.xml")

  # A minimal family: every <l>/<p> under <body> is one unit cited by its
  # bare tag name (so collisions are the norm), <note>/<head> drop their
  # subtree, <lb> separates. Exercises every template seam.
  class ProbeParser < Nabu::Adapters::StreamingTeiParser
    Unit = Data.define(:citation, :text, :annotations)

    attr_reader :extraction_options

    def parse(source, urn:, language:, canonical_path: nil, **options)
      path = resolve_canonical_path(source, canonical_path)
      @extraction_options = options
      extraction = extract(source, path: path, **options)
      build_document(disambiguate_collisions(extraction), urn: urn, language: language,
                                                          title: nil, path: path, metadata: {})
    end

    private

    def extraction_class = Extraction

    class Extraction < Nabu::Adapters::StreamingTeiParser::Walker
      def initialize(reader:, path:, marker: nil)
        super(reader: reader, path: path)
        @marker = marker
        @in_body = false
        @drop_depth = nil
        @unit = nil
        @units = []
      end

      def call
        @reader.each { |node| process(node) }
        @units
      end

      private

      def start_element(node)
        name = local_name(node)
        return @in_body = true if name == "body"
        return unless @in_body
        return if dropping?
        return @drop_depth = node.depth if %w[note head].include?(name) && !node.empty_element?
        return @unit << " " if name == "lb" && @unit

        @unit = +"" if %w[l p].include?(name) && !node.empty_element?
      end

      def end_element(node)
        name = local_name(node)
        return @drop_depth = nil if dropping? && node.depth == @drop_depth
        return if dropping? || @unit.nil? || !%w[l p].include?(name)

        @units << Unit.new(citation: name, text: "#{@marker}#{@unit}", annotations: { "flat" => flatten(@unit) })
        @unit = nil
      end

      def text_node(node)
        @unit << node.value.to_s if @unit && !dropping?
      end
    end
  end

  # A family that keeps the default "<text><body>" wording.
  class EmptyProbe < ProbeParser
    def parse(source, urn:, language:)
      build_document([], urn: urn, language: language, title: nil, path: source, metadata: {})
    end
  end

  # A family overriding the empty-document wording.
  class WordedEmptyProbe < EmptyProbe
    private

    def no_passages_message = "no citable passages found under <TEXT>"
  end

  def parser = ProbeParser.new

  def test_a_path_source_is_its_own_canonical_path
    document = parser.parse(INSCR, urn: "urn:t:inscr", language: "lat")

    assert_equal INSCR, document.canonical_path
  end

  def test_an_io_source_resolves_its_path_or_takes_the_explicit_one
    File.open(INSCR) do |io|
      assert_equal INSCR, parser.parse(io, urn: "urn:t:inscr", language: "lat").canonical_path
    end
    io = StringIO.new(File.read(INSCR))

    assert_equal "/given/path.xml",
                 parser.parse(io, urn: "urn:t:inscr", language: "lat", canonical_path: "/given/path.xml").canonical_path
  end

  def test_an_io_without_a_path_and_no_canonical_path_is_refused
    error = assert_raises(ArgumentError) do
      parser.parse(StringIO.new(File.read(INSCR)), urn: "urn:t:inscr", language: "lat")
    end
    assert_match(/canonical_path: is required/, error.message)
  end

  def test_extraction_options_reach_the_walker
    document = parser.parse(INSCR, urn: "urn:t:inscr", language: "lat", marker: "§")

    assert document.passages.first.text.start_with?("§")
  end

  def test_units_collapse_whitespace_and_cite_under_the_document_urn
    passages = parser.parse(INSCR, urn: "urn:t:inscr", language: "lat").passages

    assert_equal ["urn:t:inscr:p"], passages.map(&:urn)
    assert_equal "HAEC QVIBUS IANCI? CVI FORTVNA FAVEBIT", passages.first.text
    assert_equal({ "flat" => "HAEC QVIBUS IANCI? CVI FORTVNA FAVEBIT" }, passages.first.annotations)
    assert_equal 0, passages.first.sequence
  end

  def test_colliding_citations_disambiguate_positionally_in_document_order
    passages = parser.parse(CARMINA, urn: "urn:t:carm", language: "lat").passages

    assert_equal "urn:t:carm:l", passages[0].urn
    assert_equal "urn:t:carm:l:b2", passages[1].urn
    assert_equal "urn:t:carm:l:b3", passages[2].urn
    assert_equal "O pater, o rerum Deus, infinita potestas,", passages[0].text
    assert_equal passages.size, passages.map(&:urn).uniq.size
    assert_equal (0...passages.size).to_a, passages.map(&:sequence)
  end

  def test_dropped_subtrees_never_reach_the_text
    passages = parser.parse(CARMINA, urn: "urn:t:carm", language: "lat").passages

    refute(passages.any? { |passage| passage.text.include?("Textus in f.") })
    refute(passages.any? { |passage| passage.text.include?("Precatio Tranquilli") })
  end

  def test_malformed_xml_is_a_parse_error_naming_the_path
    truncated = File.read(INSCR)[0, 400]
    error = assert_raises(Nabu::ParseError) do
      parser.parse(StringIO.new(truncated), urn: "urn:t:inscr", language: "lat", canonical_path: "/x/trunc.xml")
    end
    assert_match(%r{\A/x/trunc\.xml: malformed XML: }, error.message)
  end

  def test_an_empty_document_is_a_parse_error_with_the_family_wording
    default = assert_raises(Nabu::ParseError) { EmptyProbe.new.parse("/x/a.xml", urn: "urn:t:a", language: "lat") }
    worded = assert_raises(Nabu::ParseError) { WordedEmptyProbe.new.parse("/x/a.xml", urn: "urn:t:a", language: "lat") }

    assert_equal "/x/a.xml: no citable passages found in <text><body>", default.message
    assert_equal "/x/a.xml: no citable passages found under <TEXT>", worded.message
  end

  def test_document_validation_failures_become_parse_errors
    error = assert_raises(Nabu::ParseError) do
      parser.parse(INSCR, urn: "", language: "lat")
    end
    assert_match(/\A#{Regexp.escape(INSCR)}: /, error.message)
  end

  def test_a_family_without_an_extraction_class_is_told_so
    bare = Class.new(Nabu::Adapters::StreamingTeiParser) do
      def run(path) = extract(path, path: path)
    end
    assert_raises(NotImplementedError) { bare.new.run(INSCR) }
  end

  def test_walker_helpers
    walker = Nabu::Adapters::StreamingTeiParser::Walker.new(reader: nil, path: "/x/a.xml")

    assert_nil walker.send(:presence, "")
    assert_nil walker.send(:presence, nil)
    assert_equal "a", walker.send(:presence, "a")
    assert_equal "a b", walker.send(:flatten, "  a \n\t b ")
    assert_nil walker.send(:flatten, " \n ")
    refute_predicate walker, :dropping?
  end
end
