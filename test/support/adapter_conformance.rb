# frozen_string_literal: true

# Shared conformance suite for source adapters (CLAUDE.md testing
# conventions; architecture §3). Every adapter's test includes this module —
# passing it is the price of admission for a new source.
#
# Include into a Minitest::Test and provide two hooks:
#
#   conformance_adapter  -> a fresh adapter instance. Called several times
#                           per test run (the stability test parses twice on
#                           independent instances), so it must not return
#                           memoized shared state.
#   conformance_workdir  -> the fixture dir discover scans
#                           (test/fixtures/<source>/ — no network, ever).
#
# Optional hook:
#
#   conformance_expected_source_id -> the id this source is registered under
#                           (config/sources.yml, once P1-6 lands). Default
#                           nil skips the check; the manifest-id ↔ ref
#                           source_id agreement is asserted regardless.
#
# What P1-1's valid-by-construction model already guarantees (NFC text,
# non-empty text, license_class enum, within-document urn/sequence
# uniqueness) is asserted here as type checks plus belt-and-braces direct
# assertions; what the model *cannot* see — uniqueness and stability across
# the whole discover set — is this suite's real job.
#
# Checks (one test method each):
#   - manifest is a valid SourceManifest (and matches the registered id)
#   - manifest declares a known license_class
#   - discover yields DocumentRefs whose source_id matches the manifest
#   - parse yields Documents with at least one passage
#   - passages are NFC and non-empty
#   - ref.id IS the document urn (parse(ref).urn == ref.id) — the identity the
#     sync circuit breaker (SyncRunner §8) relies on to predict withdrawals
#     from cheap discover ids without parsing
#   - urns are unique across the whole discover set
#   - urns are stable across two independent discover+parse passes
module AdapterConformance
  # Hook defaults: flunk with instructions rather than NoMethodError.
  def conformance_adapter
    flunk "#{self.class} must define #conformance_adapter returning a fresh adapter instance per call"
  end

  def conformance_workdir
    flunk "#{self.class} must define #conformance_workdir returning the fixture dir discover scans"
  end

  def conformance_expected_source_id
    nil
  end

  # Optional hook (P14-5): the string a passage's text_normalized is derived
  # from. Default: the pristine text (the P6-4 rule — Passage.new mints the
  # form). An adapter with a DOCUMENTED, deterministic search-form derivation
  # (conventions §9 — e.g. ccmh-txt's diplomatic line-break rejoining)
  # overrides this with that derivation, which must be recomputable from the
  # STORED passage alone (text + annotations) — so the minted-form pin keeps
  # its guarantee: text_normalized is always the per-language fold of a
  # source anyone can recompute, never an ad-hoc adapter-side fold.
  def conformance_search_source(passage)
    passage.text
  end

  # Optional hook (P19-4): may +document+ honestly parse to ZERO passages?
  # Default false — every existing adapter's at-least-one-passage guarantee
  # stands untouched. A shelf with DECLARED metadata-only documents (the
  # local-library: a scan with no text layer is catalogued, never
  # quarantined) overrides this to check the document's own honest marker
  # (metadata "text_layer" == "none"); a blanket `true` would gut the
  # zero-passage defect check, so overrides must stay marker-driven.
  def conformance_metadata_only?(_document)
    false
  end

  def test_conformance_manifest_is_a_valid_source_manifest
    manifest = conformance_adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    expected = conformance_expected_source_id
    return if expected.nil?

    assert_equal expected, manifest.id,
                 "manifest id must match the id this source is registered under"
  end

  def test_conformance_manifest_declares_a_license_class
    manifest = conformance_adapter.manifest
    assert_kind_of Nabu::SourceManifest, manifest
    assert_includes Nabu::SourceManifest::LICENSE_CLASSES, manifest.license_class
  end

  def test_conformance_discover_yields_document_refs_for_this_source
    adapter = conformance_adapter
    refs = adapter.discover(conformance_workdir).to_a
    refute_empty refs, "discover must yield at least one DocumentRef from #{conformance_workdir}"
    refs.each do |ref|
      assert_kind_of Nabu::DocumentRef, ref
      assert_equal adapter.manifest.id, ref.source_id,
                   "ref #{ref.id.inspect}: source_id must match the manifest id"
    end
  end

  def test_conformance_parse_yields_documents_with_at_least_one_passage
    each_parsed_document(conformance_adapter) do |ref, document|
      assert_kind_of Nabu::Document, document
      next if document.empty? && conformance_metadata_only?(document)

      refute_empty document,
                   "document #{document.urn.inspect} (ref #{ref.id.inspect}) parsed to zero passages"
    end
  end

  def test_conformance_passages_are_nfc_and_non_empty
    each_parsed_document(conformance_adapter) do |_ref, document|
      document.each do |passage|
        # Nabu::Passage is valid by construction — NFC, non-empty — so the
        # type check is the guarantee; the direct assertions make any future
        # subversion of construction fail vividly rather than silently.
        assert_kind_of Nabu::Passage, passage
        refute_empty passage.text, "passage #{passage.urn.inspect} has empty text"
        assert passage.text.unicode_normalized?(:nfc),
               "passage #{passage.urn.inspect} text is not NFC"
        assert passage.text_normalized.unicode_normalized?(:nfc),
               "passage #{passage.urn.inspect} text_normalized is not NFC"
      end
    end
  end

  # P6-4: text_normalized is minted at the ONE folding boundary
  # (Normalize.search_form with the passage's own language). An adapter that
  # folded text its own way would bypass the per-language rule table; this
  # pins every adapter's output to the minted form of the (default: pristine,
  # else documented — see conformance_search_source) derivation source.
  def test_conformance_text_normalized_is_the_minted_search_form
    each_parsed_document(conformance_adapter) do |_ref, document|
      document.each do |passage|
        expected = Nabu::Normalize.search_form(conformance_search_source(passage),
                                               language: passage.language)
        assert_equal expected, passage.text_normalized,
                     "passage #{passage.urn.inspect} text_normalized must be the per-language search form"
      end
    end
  end

  # The DocumentRef id IS the document urn. The sync circuit breaker
  # (SyncRunner §8) predicts a mass-withdrawal by set-differencing existing
  # document urns against the ids discover() yields — cheap directory walking,
  # no parse. That prediction is only exact when parse(ref).urn == ref.id; an
  # adapter that mints a urn diverging from its discover id would let the
  # breaker under-count withdrawals and silently weaken the mass-withdrawal
  # guard. Assert the identity here so no adapter can drift from it unnoticed.
  def test_conformance_ref_id_is_the_document_urn
    each_parsed_document(conformance_adapter) do |ref, document|
      assert_equal ref.id, document.urn,
                   "parse(#{ref.id.inspect}).urn is #{document.urn.inspect}: the DocumentRef id must " \
                   "equal the document urn, or the sync breaker's discover-id withdrawal prediction drifts"
    end
  end

  # P1-1's Document only guards uniqueness *within* one document; whole-corpus
  # uniqueness across the discover set is checked here and nowhere else.
  def test_conformance_urns_are_unique_across_the_discover_set
    document_urns = []
    passage_urns = []
    each_parsed_document(conformance_adapter) do |_ref, document|
      document_urns << document.urn
      document.each { |passage| passage_urns << passage.urn }
    end
    assert_empty duplicates(document_urns), "duplicate document urns across the discover set"
    assert_empty duplicates(passage_urns), "duplicate passage urns across the discover set"
  end

  # Urn stability is what the loader's upsert-on-urn (P1-4) rests on: two
  # independent discover+parse passes must mint identical urns.
  def test_conformance_urns_are_stable_across_independent_parses
    first = urn_snapshot(conformance_adapter)
    second = urn_snapshot(conformance_adapter)
    assert_equal first, second,
                 "document and passage urns must be identical across two independent discover+parse passes"
  end

  private

  def each_parsed_document(adapter)
    refs = adapter.discover(conformance_workdir).to_a
    refute_empty refs, "discover must yield at least one DocumentRef from #{conformance_workdir}"
    parsed = 0
    refs.each do |ref|
      document = parse_or_skip(adapter, ref) or next
      parsed += 1
      yield ref, document
    end
    refute_equal 0, parsed, "every discovered ref was skipped-by-rule; discover must yield real documents too"
  end

  def urn_snapshot(adapter)
    adapter.discover(conformance_workdir).filter_map do |ref|
      document = parse_or_skip(adapter, ref) or next
      [document.urn, document.map(&:urn)]
    end
  end

  # A discovered ref the adapter declines by rule (Nabu::DocumentSkipped, P11-7 —
  # e.g. a USFX front-matter/glossary book with no verses) is not a document to
  # round-trip; skip it, exactly as the loader and verify do. Damage
  # (Nabu::ParseError) still surfaces as a failure.
  def parse_or_skip(adapter, ref)
    adapter.parse(ref)
  rescue Nabu::DocumentSkipped
    nil
  end

  def duplicates(values)
    values.tally.select { |_urn, count| count > 1 }.keys
  end
end
