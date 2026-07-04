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
      language: "grc",
      title: title,
      canonical_path: document_ref.path
    )
    body.reject(&:empty?).each_with_index do |line, index|
      # Normalize at the adapter boundary, as every real adapter must.
      text = Nabu::Normalize.nfc(line)
      document << Nabu::Passage.new(
        urn: "#{urn}:#{index + 1}",
        language: "grc",
        text: text,
        text_normalized: Nabu::Normalize.nfc(text.downcase),
        sequence: index
      )
    end
    document
  end

  private

  def document_urn(slug)
    "urn:nabu:#{SOURCE_ID}:#{slug}"
  end
end
