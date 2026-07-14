# frozen_string_literal: true

require "test_helper"

# Proof that the shared conformance suite passes against a compliant adapter.
# This is the pattern every real adapter test follows (CLAUDE.md): include
# AdapterConformance, provide the hooks, add source-specific assertions.
class TestAdapterConformanceTest < Minitest::Test
  include AdapterConformance

  def conformance_adapter
    TestAdapter.new
  end

  def conformance_workdir
    File.expand_path("fixtures/test_adapter", __dir__)
  end

  def conformance_expected_source_id
    "test_adapter"
  end

  # Source-specific spot checks, as a real adapter test would add. Ref ids ARE
  # the document urns (the identity the conformance suite now asserts).
  def test_discovers_the_three_fixture_documents
    ids = conformance_adapter.discover(conformance_workdir).map(&:id)
    assert_equal %w[urn:nabu:test_adapter:alpha urn:nabu:test_adapter:beta urn:nabu:test_adapter:gamma], ids
  end

  def test_parses_a_known_passage
    adapter = conformance_adapter
    ref = adapter.discover(conformance_workdir).find { |r| r.id == "urn:nabu:test_adapter:alpha" }
    document = adapter.parse(ref)
    assert_equal "urn:nabu:test_adapter:alpha", document.urn
    assert_equal "μῆνιν ἄειδε θεὰ Πηληϊάδεω Ἀχιλῆος", document.passages.first.text
  end
end

# Meta-tests: deliberately-broken adapter variants must fail the *specific*
# conformance assertion they violate. Each variant is run through the real
# AdapterConformance module inside an anonymous Minitest::Test, executed
# one method at a time (Test#run returns a Result) so the failure is
# captured and inspected instead of failing this suite.
class AdapterConformanceMetaTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/test_adapter", __dir__)

  # Shared plumbing for variants that rewrite a parsed document's urns:
  # copy the document, passing each passage through the block.
  module RewritesParses
    private

    def rebuild(original, urn: original.urn)
      document = Nabu::Document.new(
        urn: urn,
        language: original.language,
        title: original.title,
        canonical_path: original.canonical_path
      )
      original.each { |passage| document << yield(passage) }
      document
    end
  end

  # Passage urns collide across documents (each document reuses the same
  # "shared" urns). Within-document uniqueness still holds, so P1-1's
  # Document-level guard cannot catch this — only the conformance suite can.
  class DuplicatePassageUrnAdapter < TestAdapter
    include RewritesParses

    def parse(document_ref)
      original = super
      rebuild(original) { |passage| passage.with(urn: "urn:nabu:test_adapter:shared:#{passage.sequence}") }
    end
  end

  # Urns change between parses: every parse call mints a fresh serial into
  # both document and passage urns, so two independent passes disagree.
  class UnstableUrnAdapter < TestAdapter
    include RewritesParses

    class << self
      def next_serial
        @serial = (@serial || 0) + 1
      end
    end

    def parse(document_ref)
      original = super
      serial = self.class.next_serial
      rebuild(original, urn: "#{original.urn}.v#{serial}") { |passage| passage.with(urn: "#{passage.urn}.v#{serial}") }
    end
  end

  # The parsed document urn diverges from the ref id: the discover id and the
  # minted urn disagree, exactly what would let the sync breaker under-count
  # withdrawals. Passages are untouched, so uniqueness/stability still hold.
  class MismatchedUrnAdapter < TestAdapter
    include RewritesParses

    def parse(document_ref)
      original = super
      rebuild(original, urn: "#{original.urn}.mismatch") { |passage| passage }
    end
  end

  # Every document parses to zero passages.
  class EmptyDocumentAdapter < TestAdapter
    def parse(document_ref)
      original = super
      Nabu::Document.new(
        urn: original.urn,
        language: original.language,
        title: original.title,
        canonical_path: original.canonical_path
      )
    end
  end

  # Every document parses to zero passages but DECLARES it (the P19-4
  # local-library marker: a scan with no text layer is catalogued, not
  # quarantined).
  class MetadataOnlyAdapter < TestAdapter
    def parse(document_ref)
      original = super
      Nabu::Document.new(
        urn: original.urn,
        language: original.language,
        title: original.title,
        canonical_path: original.canonical_path,
        metadata: { "text_layer" => "none" }
      )
    end
  end

  # self.manifest returns the wrong type entirely.
  class WrongManifestAdapter < TestAdapter
    def self.manifest
      { id: SOURCE_ID, license_class: "open" }
    end
  end

  def test_duplicate_urns_across_documents_fail_the_uniqueness_assertion
    assert_fails_conformance DuplicatePassageUrnAdapter,
                             :test_conformance_urns_are_unique_across_the_discover_set,
                             /duplicate passage urns/
    # ...and only that one: the variant is still deterministic and non-empty.
    assert_passes_conformance DuplicatePassageUrnAdapter, :test_conformance_urns_are_stable_across_independent_parses
    assert_passes_conformance DuplicatePassageUrnAdapter,
                              :test_conformance_parse_yields_documents_with_at_least_one_passage
  end

  def test_unstable_urns_between_parses_fail_the_stability_assertion
    assert_fails_conformance UnstableUrnAdapter,
                             :test_conformance_urns_are_stable_across_independent_parses,
                             /identical across two independent/
    # Each parse is internally consistent, so uniqueness still passes.
    assert_passes_conformance UnstableUrnAdapter, :test_conformance_urns_are_unique_across_the_discover_set
  end

  def test_mismatched_urn_fails_the_ref_id_identity_assertion
    assert_fails_conformance MismatchedUrnAdapter,
                             :test_conformance_ref_id_is_the_document_urn,
                             /must equal the document urn/
    # Only that one: the divergent urns are still unique and deterministic, and
    # every document still has its passages.
    assert_passes_conformance MismatchedUrnAdapter, :test_conformance_urns_are_unique_across_the_discover_set
    assert_passes_conformance MismatchedUrnAdapter, :test_conformance_urns_are_stable_across_independent_parses
    assert_passes_conformance MismatchedUrnAdapter,
                              :test_conformance_parse_yields_documents_with_at_least_one_passage
  end

  def test_empty_documents_fail_the_at_least_one_passage_assertion
    assert_fails_conformance EmptyDocumentAdapter,
                             :test_conformance_parse_yields_documents_with_at_least_one_passage,
                             /parsed to zero passages/
    assert_passes_conformance EmptyDocumentAdapter, :test_conformance_manifest_is_a_valid_source_manifest
  end

  # P19-4: the conformance_metadata_only? hook admits ONLY documents that
  # carry the honest marker — an undeclared empty document still fails even
  # under an overriding suite, so the hook cannot be used as a blanket pass.
  def test_metadata_only_hook_admits_declared_empty_documents_only
    passed = run_marker_conformance(MetadataOnlyAdapter)
    assert passed.passed?, "declared metadata-only documents must pass: #{passed.failures.first}"

    failed = run_marker_conformance(EmptyDocumentAdapter)
    refute failed.passed?, "an UNDECLARED empty document must still fail under the marker-driven hook"
    assert_match(/parsed to zero passages/, failed.failures.first.message)
  end

  def test_wrong_manifest_type_fails_the_manifest_assertion
    assert_fails_conformance WrongManifestAdapter,
                             :test_conformance_manifest_is_a_valid_source_manifest,
                             /SourceManifest/
  end

  def test_missing_hooks_flunk_with_instructions
    suite = conformance_suite_for(nil, hooks: false)
    result = suite.new(:test_conformance_manifest_is_a_valid_source_manifest).run
    refute_predicate result, :passed?
    assert_match(/must define #conformance_adapter/, result.failures.first.message)
  end

  private

  # Build a throwaway test class that runs the real conformance module
  # against +adapter_class+. Anonymous Minitest::Test subclasses register
  # themselves with the global runner; delete them so they only run here.
  def conformance_suite_for(adapter_class, hooks: true)
    workdir = FIXTURES
    suite = Class.new(Minitest::Test) do
      include AdapterConformance

      if hooks
        define_method(:conformance_adapter) { adapter_class.new }
        define_method(:conformance_workdir) { workdir }
      end
    end
    Minitest::Runnable.runnables.delete(suite)
    suite
  end

  # Run one conformance test method against +adapter_class+; returns the
  # Minitest::Result (passed?/error?/failures) for inspection.
  def run_conformance(adapter_class, test_method)
    conformance_suite_for(adapter_class).new(test_method).run
  end

  def assert_fails_conformance(adapter_class, test_method, message_pattern)
    result = run_conformance(adapter_class, test_method)
    refute result.passed?, "#{adapter_class} unexpectedly passed #{test_method}"
    refute result.error?,
           "#{adapter_class} must fail the assertion cleanly, not error: #{result.failures.first}"
    assert_match message_pattern, result.failures.first.message
  end

  def assert_passes_conformance(adapter_class, test_method)
    result = run_conformance(adapter_class, test_method)
    assert result.passed?, "#{adapter_class} should pass #{test_method}, got: #{result.failures.first}"
  end

  # The at-least-one-passage check under a marker-driven metadata-only hook
  # (the local-library override, reproduced).
  def run_marker_conformance(adapter_class)
    workdir = FIXTURES
    suite = Class.new(Minitest::Test) do
      include AdapterConformance

      define_method(:conformance_adapter) { adapter_class.new }
      define_method(:conformance_workdir) { workdir }
      define_method(:conformance_metadata_only?) { |document| document.metadata["text_layer"] == "none" }
    end
    Minitest::Runnable.runnables.delete(suite)
    suite.new(:test_conformance_parse_yields_documents_with_at_least_one_passage).run
  end
end
