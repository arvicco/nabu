# frozen_string_literal: true

# Minimal fixture-backed adapter proving the conformance suite
# (test/support/adapter_conformance.rb). This is the contract's own test rig,
# not an upstream source, so CLAUDE.md's "fixtures are real upstream samples"
# rule does not apply: the tiny plain-text files under
# test/fixtures/test_adapter/ are hand-written.
#
# Document format: line 1 is the title; each subsequent non-blank line is one
# passage. Urns are minted from the filename, so they are stable across runs.
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
        id: filename,
        path: File.join(workdir, filename)
      )
    end
  end

  def parse(document_ref)
    title, *body = File.read(document_ref.path, encoding: Encoding::UTF_8).lines.map(&:strip)
    urn = document_urn(File.basename(document_ref.id, ".txt"))
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
