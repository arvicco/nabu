# frozen_string_literal: true

# Minimal fixture-backed adapter proving the conformance suite
# (test/support/adapter_conformance.rb). This is the contract's own test rig,
# not an upstream source, so CLAUDE.md's "fixtures are real upstream samples"
# rule does not apply: the tiny plain-text files under
# test/fixtures/test_adapter/ are hand-written.
#
# Document format: line 1 is the title; each subsequent non-blank line is one
# passage. The DocumentRef id IS the document urn (minted from the filename,
# stable across runs) — the identity the sync circuit breaker relies on and the
# conformance suite asserts. parse reads the file via the ref path and takes the
# urn straight from the ref id.
class TestAdapter < Nabu::Adapter
  SOURCE_ID = "test_adapter"

  MANIFEST = Nabu::SourceManifest.new(
    id: SOURCE_ID,
    name: "Conformance Test Adapter",
    license: "CC0 1.0 (hand-written test data)",
    license_class: "open",
    upstream_url: "https://example.invalid/test_adapter",
    parser_family: "plaintext"
  )

  def self.manifest
    MANIFEST
  end

  # #fetch is deliberately left unimplemented (inherits the NotImplementedError
  # raiser): the suite never touches the network, and this adapter's
  # "upstream" is the checked-in fixture dir itself.

  def discover(workdir)
    return enum_for(:discover, workdir) unless block_given?

    Dir.glob("*.txt", base: workdir).sort.each do |filename|
      yield Nabu::DocumentRef.new(
        source_id: SOURCE_ID,
        id: document_urn(File.basename(filename, ".txt")),
        path: File.join(workdir, filename)
      )
    end
  end

  def parse(document_ref)
    title, *body = File.read(document_ref.path, encoding: Encoding::UTF_8).lines.map(&:strip)
    # An empty (or whitespace-only) file has no title line: that is a malformed
    # document, so raise ParseError — the same "unparseable" signal a real
    # adapter emits on broken XML/CoNLL-U (exercised by `nabu verify`).
    raise Nabu::ParseError, "#{document_ref.path}: empty document (no title line)" if title.nil? || title.empty?

    urn = document_ref.id
    document = Nabu::Document.new(
      urn: urn,
      language: language,
      title: title,
      canonical_path: document_ref.path
    )
    body.reject(&:empty?).each_with_index do |line, index|
      # Normalize at the adapter boundary, as every real adapter must.
      text = Nabu::Normalize.nfc(line)
      document << Nabu::Passage.new(
        urn: "#{urn}:#{index + 1}",
        language: language,
        text: text,
        sequence: index
      )
    end
    document
  end

  private

  # The language every minted document/passage carries. A seam so the
  # fold-granularity tests (P39-1) can run a CJK sibling; grc is the rig's
  # historical default.
  def language = "grc"

  def document_urn(slug)
    "urn:nabu:#{SOURCE_ID}:#{slug}"
  end
end

# The jpn-minting sibling of the rig (P39-1 fold-digest granularity): same
# plain-text format, every row tagged jpn — the language whose fold consults
# lib/nabu/jpn.rb (and, through composition, hani.rb).
class JpnTestAdapter < TestAdapter
  private

  def language = "jpn"
end

# The multi-shelf sibling of the rig (P104-4, Q81): a PASSAGES source that
# also declares a secondary dictionary lane, for the sync/rebuild routing
# tests. The lane reads glossary.tsv beside the *.txt corpus — one
# "id<TAB>headword<TAB>gloss" line per entry — into one "test-lexicon"
# dictionary; no file means no dictionaries, honestly (the absent-cone
# posture every lane must hold).
class LaneTestAdapter < TestAdapter
  GLOSSARY_FILENAME = "glossary.tsv"
  DICTIONARY_SLUG = "test-lexicon"

  def self.dictionary_lane = DictionaryLane.new

  # The dictionary-shaped sub-adapter (see Nabu::Adapter.dictionary_lane):
  # discover/parse only — DictionaryLoader#load_from drives it.
  class DictionaryLane < Nabu::Adapter
    def discover(workdir)
      return enum_for(:discover, workdir) unless block_given?

      path = File.join(workdir, GLOSSARY_FILENAME)
      return unless File.file?(path)

      yield Nabu::DocumentRef.new(
        source_id: TestAdapter::SOURCE_ID, id: "#{DICTIONARY_SLUG}:#{GLOSSARY_FILENAME}",
        path: File.expand_path(path)
      )
    end

    def parse(document_ref)
      document = Nabu::DictionaryDocument.new(
        slug: DICTIONARY_SLUG, language: "grc", title: "Test Lexicon",
        canonical_path: document_ref.path
      )
      File.readlines(document_ref.path, encoding: Encoding::UTF_8, chomp: true).each do |line|
        id, headword, gloss = line.split("\t")
        raise Nabu::ParseError, "#{document_ref.path}: malformed glossary line #{line.inspect}" if headword.nil?

        headword = Nabu::Normalize.nfc(headword)
        document << Nabu::DictionaryEntry.new(
          entry_id: id, key_raw: headword, language: "grc", headword: headword,
          headword_folded: Nabu::Normalize.search_form(headword, language: "grc"),
          gloss: gloss, body: [headword, gloss].compact.join(" — ")
        )
      end
      document
    end
  end
end
